`timescale 1ns/1ps
// =============================================================================
// aplus_pcie_egress_adapter.v -- INT.P2: connect the actual A+ output slot
// (compressed, A1U1) to the existing PCIe send backend (ddr_frame_pusher).
//
// The A+ path produces a variable-length zlib stream stored in the compressed
// slot store (a1_ddr_slot_store, MODE=1).  This adapter bridges a published
// slot to the PCIe backend's descriptor/ARM interface:
//   - descriptor lock (cap_bytes, session_id, dst/db addresses, frame_bytes)
//   - valid transport length (4 KiB aligned, tail padded with zeros)
//   - tail handling (stream_len -> dma_bytes, padding rejected if non-zero)
//   - completion (held until host ACK)
//   - release (ACK (session,seq) match -> free slot + release source)
//
// RAW (R10F) receive entry is NOT touched here: it remains a separate,
// uncompressed transport reference.  src_sel for this adapter is 0 (DDR source)
// because the compressed frame already lives in DDR (the slot store).
//
// This module does NOT instantiate ddr_frame_pusher; it exposes the descriptor
// and control pulses that a board top wires to the pusher's register/ARM face.
// =============================================================================
module aplus_pcie_egress_adapter #(
    parameter integer SLOT_BYTES = 2594816,   // max compressed slot capacity
    parameter [31:0]  ALIGN_BYTES = 32'd4096, // PCIe transport alignment
    parameter [31:0]  SESSION_DEFAULT = 32'd1
) (
    input  wire        clk,
    input  wire        rst_n,

    // ---- configuration (from host/CTRL) ----
    input  wire        push_en,          // CTRL[6]
    input  wire [31:0] cap_bytes,        // host-authorized capacity
    input  wire [31:0] session_id,       // host session (must be != 0)
    input  wire [63:0] dst_base,         // host destination base (128B aligned)
    input  wire [63:0] db_addr,          // doorbell address (4B aligned)
    input  wire [2:0]  mps_code,
    input  wire        link_up,

    // ---- A+ compressed slot publish event ----
    input  wire        slot_ready,       // one pulse when a slot becomes READY
    input  wire [31:0] slot_id,          // published slot/frame id
    input  wire [31:0] slot_stream_len,  // exact zlib stream bytes
    input  wire [31:0] slot_base_word,   // DDR word index of slot base

    // ---- PCIe backend status (from ddr_frame_pusher) ----
    input  wire        pcie_busy,
    input  wire        pcie_held,
    input  wire        pcie_done,        // data+doorbell sent (pulse)
    input  wire        pcie_err,         // error sticky
    input  wire [31:0] pcie_held_seq,
    input  wire [31:0] pcie_held_sess,

    // ---- host ACK ----
    input  wire        ack_pulse,
    input  wire [31:0] ack_seq,
    input  wire [31:0] ack_session,
    input  wire        cancel_pulse,

    // ---- descriptor outputs to PCIe backend registers ----
    output reg         arm_pulse,        // one pulse: ARM_ONE_SHOT
    output reg  [31:0] o_cap_bytes,
    output reg  [31:0] o_session_id,
    output reg  [63:0] o_dst_base,
    output reg  [63:0] o_db_addr,
    output reg  [31:0] o_frame_bytes,     // transport (aligned) length
    output reg  [31:0] o_stream_len,      // exact A1U1 stream length
    output reg  [31:0] o_slot_base_word,
    output reg         o_src_sel,         // 0 = DDR source (compressed)
    output reg         o_cam_sel,

    // ---- slot ownership ----
    output reg         slot_release,     // pulse: free the exported slot

    // ---- status ----
    output reg  [31:0] st_exported,
    output reg  [31:0] st_bytes,
    output reg  [7:0]  st_err,
    output reg         st_busy,
    output reg         st_held
);

    localparam [2:0] S_IDLE  = 3'd0;
    localparam [2:0] S_ARM   = 3'd1;
    localparam [2:0] S_TX    = 3'd2;
    localparam [2:0] S_HELD  = 3'd3;
    localparam [2:0] S_REL   = 3'd4;

    reg [2:0] state;
    reg [31:0] held_slot_id;
    reg [31:0] held_stream_len;
    reg [31:0] held_frame_bytes;
    reg [31:0] held_seq_r;
    reg [31:0] held_sess_r;

    // transport length alignment
    function [31:0] align_up;
        input [31:0] v;
        input [31:0] a;
        begin
            align_up = (v + a - 32'd1) & ~(a - 32'd1);
        end
    endfunction

    // descriptor validity
    wire desc_ok = push_en && (session_id != 32'd0) && (cap_bytes != 32'd0) &&
                   (slot_stream_len != 32'd0) && (slot_stream_len <= SLOT_BYTES) &&
                   (mps_code <= 3'd5) && link_up &&
                   ((dst_base[6:0] == 7'd0)) && (db_addr[1:0] == 2'd0);

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= S_IDLE;
            arm_pulse <= 1'b0;
            o_cap_bytes <= 32'd0;
            o_session_id <= 32'd0;
            o_dst_base <= 64'd0;
            o_db_addr <= 64'd0;
            o_frame_bytes <= 32'd0;
            o_stream_len <= 32'd0;
            o_slot_base_word <= 32'd0;
            o_src_sel <= 1'b0;
            o_cam_sel <= 1'b0;
            slot_release <= 1'b0;
            st_exported <= 32'd0;
            st_bytes <= 32'd0;
            st_err <= 8'd0;
            st_busy <= 1'b0;
            st_held <= 1'b0;
            held_slot_id <= 32'd0;
            held_stream_len <= 32'd0;
            held_frame_bytes <= 32'd0;
            held_seq_r <= 32'd0;
            held_sess_r <= 32'd0;
        end else begin
            arm_pulse <= 1'b0;
            slot_release <= 1'b0;
            st_busy <= (state != S_IDLE);
            st_held <= (state == S_HELD);

            case (state)
                S_IDLE: begin
                    if (slot_ready) begin
                        if (!desc_ok) begin
                            st_err <= st_err + 8'd1;
                        end else begin
                            // lock descriptor
                            o_cap_bytes <= cap_bytes;
                            o_session_id <= session_id;
                            o_dst_base <= dst_base;
                            o_db_addr <= db_addr;
                            o_stream_len <= slot_stream_len;
                            o_slot_base_word <= slot_base_word;
                            o_src_sel <= 1'b0; // DDR source
                            o_cam_sel <= 1'b0;
                            o_frame_bytes <= align_up(slot_stream_len + 32'd44, ALIGN_BYTES);
                            held_slot_id <= slot_id;
                            held_stream_len <= slot_stream_len;
                            held_frame_bytes <= align_up(slot_stream_len + 32'd44, ALIGN_BYTES);
                            arm_pulse <= 1'b1;
                            state <= S_ARM;
                        end
                    end
                end
                S_ARM: begin
                    // wait for pusher to start/complete
                    if (pcie_done) begin
                        held_seq_r <= pcie_held_seq;
                        held_sess_r <= pcie_held_sess;
                        st_exported <= st_exported + 32'd1;
                        st_bytes <= st_bytes + held_stream_len;
                        state <= S_HELD;
                    end else if (pcie_busy) begin
                        state <= S_TX;
                    end else if (pcie_err) begin
                        st_err <= st_err + 8'd1;
                        slot_release <= 1'b1;
                        state <= S_IDLE;
                    end
                end
                S_TX: begin
                    if (pcie_done) begin
                        held_seq_r <= pcie_held_seq;
                        held_sess_r <= pcie_held_sess;
                        st_exported <= st_exported + 32'd1;
                        st_bytes <= st_bytes + held_stream_len;
                        state <= S_HELD;
                    end else if (pcie_err) begin
                        st_err <= st_err + 8'd1;
                        slot_release <= 1'b1;
                        state <= S_IDLE;
                    end
                end
                S_HELD: begin
                    if (cancel_pulse) begin
                        slot_release <= 1'b1;
                        state <= S_IDLE;
                    end else if (ack_pulse && (ack_seq == held_seq_r) &&
                                 (ack_session == held_sess_r) && (ack_session != 32'd0)) begin
                        slot_release <= 1'b1;
                        state <= S_IDLE;
                    end else if (ack_pulse) begin
                        st_err <= st_err + 8'd1; // bad ack, held stays
                    end
                end
                default: state <= S_IDLE;
            endcase

            if (cancel_pulse && (state == S_ARM)) begin
                slot_release <= 1'b1;
                state <= S_IDLE;
            end
        end
    end

endmodule
