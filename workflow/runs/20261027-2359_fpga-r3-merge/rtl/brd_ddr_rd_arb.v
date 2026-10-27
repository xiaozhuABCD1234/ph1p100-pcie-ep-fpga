`timescale 1ns/1ps
// =============================================================================
// brd_ddr_rd_arb.v -- DDR3 AXI4 read-channel arbiter (T11.BRD.P1, guide 3.4)
//
// Two read masters share the single ddr3_mc_0 AXI4 read port:
//   owner 0 = p2_ddr_bridge single-beat PAXI read (P4 slot drain after host ACK)
//   owner 1 = ddr_frame_pusher 4KB burst read (frame export)
//
// Frozen rules implemented here:
//   R1 grant granularity = ONE AR transaction including its whole rlast burst.
//      The owner cannot change between the AR handshake and the R beat that
//      carries rlast.  o_switch_err counts any internal violation (must stay 0).
//   R2 fair round robin: the preference bit flips after every completed
//      transaction, so neither master can be starved.
//   R3 while a burst is in flight m_arvalid is deasserted and the AR payload
//      mux is frozen on the owning master.
//   R4 the R channel is routed only to the current owner.  A beat that arrives
//      with no outstanding transaction (late/orphan beat) is consumed
//      (m_rready=1) but never forwarded -- it is only counted in o_late_cnt.
//   R5 bridge worst-case wait is one pusher burst (128 beats @100MHz ~ 1.28us),
//      far below the 70,000 clk_core guard inside p2_ddr_bridge.
// =============================================================================
module brd_ddr_rd_arb (
    input  wire         clk,
    input  wire         rst_n,

    // ---- owner 0: bridge single-beat read (paxi side, byte address) ----
    input  wire [28:0]  b_araddr,
    input  wire         b_arvalid,
    output wire         b_arready,
    output wire [255:0] b_rdata,
    output wire [1:0]   b_rresp,
    output wire         b_rlast,
    output wire         b_rvalid,
    input  wire         b_rready,

    // ---- owner 1: pusher 4KB burst read ----
    input  wire [3:0]   p_arid,
    input  wire [28:0]  p_araddr,
    input  wire [7:0]   p_arlen,
    input  wire [2:0]   p_arsize,
    input  wire [1:0]   p_arburst,
    input  wire         p_arvalid,
    output wire         p_arready,
    output wire [3:0]   p_rid,
    output wire [255:0] p_rdata,
    output wire [1:0]   p_rresp,
    output wire         p_rlast,
    output wire         p_rvalid,
    input  wire         p_rready,

    // ---- DDR3 AXI4 read port ----
    output wire [3:0]   m_arid,
    output wire [28:0]  m_araddr,
    output wire [7:0]   m_arlen,
    output wire [2:0]   m_arsize,
    output wire [1:0]   m_arburst,
    output reg          m_arvalid,
    input  wire         m_arready,
    input  wire [3:0]   m_rid,
    input  wire [255:0] m_rdata,
    input  wire [1:0]   m_rresp,
    input  wire         m_rlast,
    input  wire         m_rvalid,
    output wire         m_rready,

    // ---- observation ----
    output wire         o_owner,        // 1 = pusher currently owns the port
    output wire         o_busy,
    output reg  [31:0]  o_late_cnt,     // orphan R beats (no outstanding AR)
    output reg  [31:0]  o_switch_err,   // owner changed mid-burst (must stay 0)
    output reg  [31:0]  o_b_xacts,
    output reg  [31:0]  o_p_xacts
);

    reg         owner;      // current / next owner
    reg         busy;       // one AR outstanding (start .. rlast)
    reg         rr;         // round-robin preference: 1 = pusher first
    reg  [7:0]  beats_left;

    // ---------------- request arbitration (only when idle) ----------------
    wire b_req = b_arvalid;
    wire p_req = p_arvalid;

    wire grant_b = (!busy) && b_req && (!p_req || (!rr));
    wire grant_p = (!busy) && p_req && (!b_req || ( rr));

    wire sel_p = busy ? owner : grant_p;

    // AR payload mux (frozen while busy)
    assign m_arid    = sel_p ? p_arid    : 4'd0;
    assign m_araddr  = sel_p ? p_araddr  : b_araddr;
    assign m_arlen   = sel_p ? p_arlen   : 8'd0;      // bridge: single beat
    assign m_arsize  = sel_p ? p_arsize  : 3'd5;      // 32 bytes / beat
    assign m_arburst = sel_p ? p_arburst : 2'b01;     // INCR

    always @(*) begin
        if (busy)                  m_arvalid = 1'b0;
        else if (grant_b)          m_arvalid = 1'b1;
        else if (grant_p)          m_arvalid = 1'b1;
        else                       m_arvalid = 1'b0;
    end

    assign b_arready = (!busy && grant_b) ? m_arready : 1'b0;
    assign p_arready = (!busy && grant_p) ? m_arready : 1'b0;

    // ---------------- read data routing ----------------
    assign b_rvalid = (busy && !owner) ? m_rvalid : 1'b0;
    assign b_rdata  = m_rdata;
    assign b_rresp  = m_rresp;
    assign b_rlast  = m_rlast;

    assign p_rvalid = (busy &&  owner) ? m_rvalid : 1'b0;
    assign p_rid    = m_rid;
    assign p_rdata  = m_rdata;
    assign p_rresp  = m_rresp;
    assign p_rlast  = m_rlast;

    // always accept from DDR: the owner is either the bridge (rready=1) or the
    // pusher (its 128-deep FIFO never back-pressures inside one burst).  An
    // orphan beat is therefore consumed and counted instead of being parked.
    assign m_rready = busy ? (owner ? p_rready : b_rready) : 1'b1;

    wire ar_hs  = m_arvalid && m_arready;
    wire r_hs   = m_rvalid  && m_rready;
    wire r_done = r_hs && m_rlast;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            owner        <= 1'b0;
            busy         <= 1'b0;
            rr           <= 1'b0;
            beats_left   <= 8'd0;
            o_late_cnt   <= 32'd0;
            o_switch_err <= 32'd0;
            o_b_xacts    <= 32'd0;
            o_p_xacts    <= 32'd0;
        end else if (ar_hs) begin
            busy       <= 1'b1;
            owner      <= sel_p;
            beats_left <= sel_p ? p_arlen : 8'd0;
        end else if (r_hs) begin
            if (m_rlast) begin
                busy       <= 1'b0;
                beats_left <= 8'd0;
                if (owner) begin
                    o_p_xacts <= o_p_xacts + 32'd1;
                    rr        <= 1'b0;
                end else begin
                    o_b_xacts <= o_b_xacts + 32'd1;
                    rr        <= 1'b1;
                end
            end else begin
                // ternary form: an `if` on beats_left (a reg assigned in this
                // same block) trips TD's HDL-8007 clocked-block check.
                beats_left <= (beats_left == 8'd0) ? 8'd0 : (beats_left - 8'd1);
            end
        end

        // Orphan beat (rvalid while nothing is outstanding) is counted only, and
        // a mid-burst owner change is a design guard.  Both are written as
        // arithmetic on the condition instead of an `if` so TD's clocked-block
        // rule (HDL-8007) does not see a condition that has no edge in the
        // sensitivity list.
        o_late_cnt   <= o_late_cnt   + {{31{1'b0}}, (r_hs & ~busy)};
        o_switch_err <= o_switch_err + {{31{1'b0}}, (ar_hs &  busy)};
    end

    assign o_owner = owner;
    assign o_busy  = busy;

endmodule
