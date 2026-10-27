`timescale 1ns/1ps
// =============================================================================
// brd_export_seq.v -- T11.BRD.P1 r1 F1 fix: ARM / source-event alignment (tl domain)
//
// Why this block exists
// ---------------------
// ddr_frame_pusher (read-only reference) implements one-shot ARM with
//   src_evt = src_rdy && (src_seq != last_seq)
// and latches last_seq <= src_seq on the accepted ARM ("only push frames
// published after ARM").  In the board datapath the source sequence came from
// the P4 descriptor capture_seq, which only changes when a *new* capture is
// admitted -- and a new capture is only admitted after the host ACK, i.e.
// after the export.  That is a deadlock:
//   * ARM before the P4 publish  -> frame_bytes == 0 -> E_ARM_REJ(6)
//   * ARM after  the P4 publish  -> last_seq == src_seq -> src_evt never rises
//
// r1 fix: the host ARM is latched here and only presented to the pusher after
// a frame is actually available (desc publish event + non-zero frame_bytes).
// After the pusher enters G_ARMED, exactly ONE source event is generated on a
// board-owned sequence counter, so claim happens once.  A repeated ARM while
// pending / armed / busy / held is ignored and counted (defined behaviour).
//
// The pusher keeps owning HELD/ACK semantics: held_seq = doorbell value
// (st_done+1), so the host ACK sequence is the pusher's held_seq.
// =============================================================================
module brd_export_seq (
    input  wire         clk,            // tl_clk_user
    input  wire         rst_n,          // tl_rst_n

    input  wire         host_arm,       // BAR TX_CMD.bit0 (one tl cycle)
    input  wire         host_ack,       // BAR TX_CMD.bit1
    input  wire         host_cancel,    // BAR TX_CMD.bit2

    input  wire         desc_evt,       // C4 mailbox: new published descriptor (one cycle)
    input  wire [31:0]  frame_bytes,    // C4 mailbox: aligned transport length
    input  wire [31:0]  tx_status,      // pusher 0xC4: bit0 tx_active, bit1 held, bit2 armed

    output reg          pu_arm,         // one-cycle ARM_ONE_SHOT to the pusher
    output reg  [31:0]  pu_seq,         // board-owned source sequence (pusher ddr_seq)
    output reg          armed_q,        // ARM accepted, waiting for export completion/ACK
    output reg          frame_pend_q,   // published frame waiting for a source event
    output reg  [31:0]  evt_cnt,        // source events emitted (must be 1 per export)
    output reg  [31:0]  arm_ignored     // ARM dropped while pending/armed/busy/held
);

    reg  arm_pend;
    reg  evt_busy;
    reg  frame_pend;

    wire pusher_idle  = ~tx_status[0] & ~tx_status[1] & ~tx_status[2];  // [0]=ARMED [1]=TX [2]=HELD
    wire pusher_armed =  tx_status[0];   // ddr_frame_pusher 0xC4 bit0 = G_ARMED
    wire pusher_busy  =  tx_status[1];   // bit1 = tx_active
    wire frame_valid  =  (frame_bytes != 32'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pu_arm       <= 1'b0;
            pu_seq       <= 32'd0;
            armed_q      <= 1'b0;
            frame_pend_q <= 1'b0;
            evt_cnt      <= 32'd0;
            arm_ignored  <= 32'd0;
            arm_pend     <= 1'b0;
            evt_busy     <= 1'b0;
            frame_pend   <= 1'b0;
        end else begin
            pu_arm <= 1'b0;

            // ---- published-frame tracking (C4 mailbox arm event) ----
            if (desc_evt)
                frame_pend <= 1'b1;

            // ---- host ARM: latched, or ignored with a counter ----
            if (host_arm) begin
                if (!arm_pend && !armed_q && pusher_idle)
                    arm_pend <= 1'b1;
                else
                    arm_ignored <= arm_ignored + 32'd1;
            end

            // ---- present ARM only when a real frame is available ----
            if (arm_pend && frame_pend && frame_valid && pusher_idle) begin
                pu_arm   <= 1'b1;
                arm_pend <= 1'b0;
                armed_q  <= 1'b1;
            end

            // ---- one source event per accepted ARM ----
            if (armed_q && frame_pend && pusher_armed && !evt_busy) begin
                pu_seq       <= pu_seq + 32'd1;
                frame_pend   <= 1'b0;
                evt_busy     <= 1'b1;
                evt_cnt      <= evt_cnt + 32'd1;
            end
            // the claim is visible as tx_active; an ARM that was refused leaves
            // ARMED without a claim, so release the guard on either edge
            if (evt_busy && (pusher_busy || !pusher_armed))
                evt_busy <= 1'b0;

            // ---- ACK/CANCEL close the session ----
            if (host_ack || host_cancel) begin
                armed_q    <= 1'b0;
                frame_pend <= 1'b0;
                evt_busy   <= 1'b0;
            end

            frame_pend_q <= frame_pend;
        end
    end

endmodule

