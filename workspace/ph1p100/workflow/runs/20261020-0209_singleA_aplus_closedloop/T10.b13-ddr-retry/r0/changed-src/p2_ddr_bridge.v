`timescale 1ns/1ps
// =============================================================================
// p2_ddr_bridge.v -- single-beat 256-bit PAXI clock bridge.
//
// The P1 A1 store model exposes one 256-bit word per AW/W pair and one word per
// AR, with no burst length, no B channel and no write strobes.  The board DDR
// PAXI has the same single-beat contract but runs on the DDR user clock
// (dhi_clk, ~200 MHz), so the A1 chain (187.5 MHz) must cross domains.
//
// Three Gray-pointer asynchronous FIFOs (one reset, two clock domains):
//   WF: {awaddr[26:0], wdata[255:0]}  A1 -> DDR
//   AF: araddr[26:0]                  A1 -> DDR
//   RF: rdata[255:0]                  DDR -> A1
// The DDR side holds AW/W until both are accepted, sets wstrb=all-ones and
// wlast=1 for the single beat, and issues one AR at a time.
// No reset-domain-hopping logic beyond the FIFO reset synchronizers that the
// existing capture_async_fifo already contains.
//
// T10.b11-aplus-read: observation only (no protocol / data change).
// The DDR-side read engines were the only place that could swallow an A1 read
// answer, so the bridge now publishes a clk_a1 snapshot of its state and event
// counters to the status packet:
//   dbg_a1[191:0] = {stale_r_cnt, rlast_cnt, r_cnt, ar_block_cnt, ar_cnt, br0}
//   br0[0] ddr_rdy  [1] ar_pending  [2] af_rvalid  [3] af_wready
//       [4] rf_rvalid [5] rf_wready [6] s_rvalid_r [7] s_rready
//       [8] wstate [9] aw_seen [10] w_seen [11] wf_rvalid [12] wf_pop
// The five counters live in clk_ddr and cross through one stable-hold/toggle
// mailbox (cam_diag_mailbox), so the packet never samples a moving multi-bit
// counter.  Nothing here feeds back into the engines.
// =============================================================================
module p2_ddr_bridge (
    // A1 / 187.5 MHz side (same shape as the P1 store's DDR port)
    input  wire         clk_a1,
    input  wire         rst_n,
    input  wire [31:0]  s_awaddr,
    input  wire         s_awvalid,
    output wire         s_awready,
    input  wire [255:0] s_wdata,
    input  wire         s_wvalid,
    output wire         s_wready,
    input  wire [31:0]  s_araddr,
    input  wire         s_arvalid,
    output wire         s_arready,
    output wire [255:0] s_rdata,
    output wire         s_rvalid,
    input  wire         s_rready,

    // T10.b13: 1 clk_a1 pulse from the raw store read timeout.  Purges the read
    // path only (AF addresses, RF data, skid), never the global reset, so the
    // write FIFO keeps every accepted write request.
    input  wire         rd_abort,

    // DDR user-clock side (PH1P PAXI)
    input  wire         clk_ddr,
    input  wire         ddr_rdy,
    output wire [26:0]  paxi_awaddr,
    output wire         paxi_awvalid,
    input  wire         paxi_awready,
    output wire [255:0] paxi_wdata,
    output wire [31:0]  paxi_wstrb,
    output wire         paxi_wvalid,
    output wire         paxi_wlast,
    input  wire         paxi_wready,
    output wire [26:0]  paxi_araddr,
    output wire         paxi_arvalid,
    input  wire         paxi_arready,
    input  wire [255:0] paxi_rdata,
    input  wire         paxi_rlast,
    input  wire         paxi_rvalid,
    output wire         paxi_rready,

    // T10.b11 observation (clk_a1, stable between mailbox publications)
    // T10.b13: 192 -> 256 bits; [255:224]=purge_cnt, [223:192]=stale_guard_cnt,
    // [191:0] unchanged.
    output wire [255:0] dbg_a1
);
    // ---------------------------------------------------------- write request
    wire        wf_wready;
    wire        wf_rvalid;
    wire [282:0] wf_rdata;
    reg         wf_pop;

    wire wf_push = s_awvalid && s_wvalid;
    assign s_awready = wf_wready && s_wvalid;
    assign s_wready  = s_awready;

    capture_async_fifo #(.WIDTH(283), .ADDR_BITS(5)) u_wf (
        .rst_n   (rst_n),
        .wclk    (clk_a1),
        .w_valid (wf_push),
        .w_data  ({s_awaddr[26:0], s_wdata}),
        .w_ready (wf_wready),
        .rclk    (clk_ddr),
        .r_valid (wf_rvalid),
        .r_data  (wf_rdata),
        .r_ready (wf_pop)
    );

    // ----------------------------------------------------------- read request
    wire        af_wready;
    wire        af_rvalid;
    wire [26:0] af_rdata;
    wire        af_pop;
    // T10.b13b: the FIFO write enable must be the AR *handshake*
    // (s_arvalid && s_arready), not the bare request level.  s_arvalid is held
    // high until the AR is accepted; with s_arready additionally gated by the
    // abort guard, a bare-level w_valid pushed one AF entry per cycle and the
    // retry read replayed the same address.  af_push is qualified after the
    // s_arready/purge declarations below.
    wire        af_push;

    // T10.b13b: the real s_arready assignment lives after the purge/guard
    // declarations below (it must be gated while the bridge is purging).

    capture_async_fifo #(.WIDTH(27), .ADDR_BITS(4)) u_af (
        .rst_n   (rst_n),
        .wclk    (clk_a1),
        .w_valid (af_push),
        .w_data  (s_araddr[26:0]),
        .w_ready (af_wready),
        .rclk    (clk_ddr),
        .r_valid (af_rvalid),
        .r_data  (af_rdata),
        .r_ready (af_pop)
    );

    // -------------------------------------------------------------- read data
    wire         rf_wready;
    wire         rf_rvalid;
    wire [255:0] rf_rdata;

    // Board-integration output register: isolate the ERAM clk2q read data from
    // the frozen slot store's wide read-data/duplicate comparator. One-deep
    // skid register, same handshake, no protocol/order change.
    reg  [255:0] s_rdata_r;
    reg          s_rvalid_r;

    // ------------------------------------------------- T10.b13 read-path purge
    // A1 side: 4 cycles of "no load, drain RF", started by rd_abort.  The skid
    // register and any RF entry still in flight belong to the aborted attempt
    // and must never reach the retried frame.
    localparam integer A1_PURGE_N = 4;
    // T10.b13b: the DDR-side purge guard (BRIDGE_GUARD_N clk_ddr = 327 us) is
    // LONGER in real time than the store guard (GUARD_N clk_a1 = 175 us), so a
    // retry AR issued right after the store guard would land inside the bridge
    // guard: it would either be drained by af_pop_purge or wait there for more
    // than TIMEOUT_N cycles, and the store would time out again.  Hold
    // s_arready low in clk_a1 for A1_GUARD_N (> 65536 clk_ddr in real time)
    // after an abort, so the retry AR stays in R_AR (no timeout there) until
    // the whole bridge purge/guard window is over.
    localparam [31:0] A1_GUARD_N = 32'd70000;   // clk_a1, 373 us > 327 us
    reg  [31:0] a1_ar_hold;
    wire        a1_ar_hold_act = (a1_ar_hold != 32'd0);
    reg  [2:0]  a1_purge;
    reg  [31:0] purge_cnt;
    wire        a1_purge_act = (a1_purge != 3'd0);
    // T10.b13b: no AR may enter AF during the abort purge or the following
    // guard window (see A1_GUARD_N below).
    assign s_arready = af_wready && !a1_purge_act && !a1_ar_hold_act;
    assign af_push   = s_arvalid && s_arready;
    // T10.b13b: the whole abort/guard window (not just the 4-cycle purge) must be
    // silent on the A1 side: no new load into the skid and RF drained.  Combined
    // with the store's R_AR/R_GUARD drain this makes "an R left over from the
    // aborted attempt" structurally impossible, instead of relying on the guard
    // duration.  a1_ar_hold is 0 in the normal path, so nothing changes there.
    wire        a1_drain_win = a1_purge_act || a1_ar_hold_act;
    wire        s_load = rf_rvalid && (!s_rvalid_r || s_rready) && !a1_drain_win;
    wire        rf_pop = s_load || (a1_drain_win && rf_rvalid);

    // T10.b10 R3: an R that arrives while this bridge has no outstanding AR
    // (i.e. a response left over from before a business reset) must never be
    // handed to the A1 side as if it were the answer to a new AR.  Such an R is
    // consumed and discarded so the PAXI port keeps flowing.
    reg          ar_pending;
    wire         r_expected = ar_pending;
    wire         rf_push    = paxi_rvalid && r_expected;

    capture_async_fifo #(.WIDTH(256), .ADDR_BITS(4)) u_rf (
        .rst_n   (rst_n),
        .wclk    (clk_ddr),
        .w_valid (rf_push),
        .w_data  (paxi_rdata),
        .w_ready (rf_wready),
        .rclk    (clk_a1),
        .r_valid (rf_rvalid),
        .r_data  (rf_rdata),
        .r_ready (rf_pop)
    );

    // ------------------------------------------------- DDR-side purge + guard
    // rd_abort is a clk_a1 single-cycle pulse; it crosses as a toggle through a
    // 2-flop synchronizer (same style as the existing mailboxes) and becomes a
    // one-cycle purge_evt in clk_ddr.  It is never used as a clk_ddr level.
    localparam integer DDR_PURGE_N    = 4;
    localparam [31:0]  BRIDGE_GUARD_N = 32'd65536;   // > store GUARD_N (clk_a1)
    reg         ab_tgl_a1;
    reg  [1:0]  ab_sync_ddr;
    wire        purge_evt = ab_sync_ddr[1] ^ ab_sync_ddr[0];
    reg  [3:0]  ddr_purge;
    reg  [31:0] guard_cnt_ddr;
    reg  [31:0] stale_guard_cnt;
    wire        purge_phase = (ddr_purge != 4'd0);
    wire        guard_phase = (guard_cnt_ddr != 32'd0);
    wire        rd_hold     = purge_phase || guard_phase;

    always @(posedge clk_a1 or negedge rst_n) begin
        if (!rst_n) ab_tgl_a1 <= 1'b0;
        else if (rd_abort) ab_tgl_a1 <= ~ab_tgl_a1;
    end
    always @(posedge clk_ddr or negedge rst_n) begin
        if (!rst_n) ab_sync_ddr <= 2'b00;
        else        ab_sync_ddr <= {ab_sync_ddr[0], ab_tgl_a1};
    end

    always @(posedge clk_a1 or negedge rst_n) begin
        if (!rst_n) begin
            s_rdata_r <= 256'd0;
            s_rvalid_r <= 1'b0;
            a1_purge <= 3'd0;
            purge_cnt <= 32'd0;
            a1_ar_hold <= 32'd0;
        end else begin
            if (a1_ar_hold != 32'd0) a1_ar_hold <= a1_ar_hold - 32'd1;
            if (rd_abort) begin
                a1_purge  <= A1_PURGE_N[2:0];
                purge_cnt <= purge_cnt + 32'd1;
                a1_ar_hold <= A1_GUARD_N;
                s_rvalid_r <= 1'b0;          // drop the aborted attempt's data
            end else if (a1_purge_act) begin
                a1_purge <= a1_purge - 3'd1;
                s_rvalid_r <= 1'b0;          // stay silent for the whole purge
            end else if (s_load) begin
                s_rdata_r <= rf_rdata;
                s_rvalid_r <= 1'b1;
            end else if (s_rvalid_r && s_rready) begin
                s_rvalid_r <= 1'b0;
            end
        end
    end

    assign s_rdata  = s_rdata_r;
    assign s_rvalid = s_rvalid_r;
    // Only take an R into the FIFO when an AR is outstanding; otherwise swallow
    // it (rready is high regardless of FIFO space) so a stale response can
    // never block or corrupt the next session.  During the T10.b13 purge guard
    // rready is forced high so a late R is absorbed and counted, never queued.
    assign paxi_rready = rd_hold ? 1'b1 : (r_expected ? rf_wready : 1'b1);

    // ------------------------------------------------- DDR-side write engine
    localparam [1:0] W_IDLE = 2'd0, W_RUN = 2'd1;
    reg [1:0] wstate;
    reg       aw_seen, w_seen;

    assign paxi_awaddr  = wf_rdata[282:256];
    assign paxi_wdata   = wf_rdata[255:0];
    assign paxi_wstrb   = 32'hFFFF_FFFF;   // every store word is a full 32-byte beat
    assign paxi_wlast   = 1'b1;            // single-beat transaction
    assign paxi_awvalid = (wstate == W_RUN) && !aw_seen;
    assign paxi_wvalid  = (wstate == W_RUN) && !w_seen;

    always @(posedge clk_ddr or negedge rst_n) begin
        if (!rst_n) begin
            wstate <= W_IDLE; aw_seen <= 1'b0; w_seen <= 1'b0; wf_pop <= 1'b0;
        end else begin
            wf_pop <= 1'b0;
            case (wstate)
                W_IDLE: begin
                    aw_seen <= 1'b0;
                    w_seen  <= 1'b0;
                    // T10.b10 R2: wf_pop is a registered pulse, so wf_rvalid is
                    // still high in the cycle after the pop.  Starting W_RUN in
                    // that cycle presented the same FIFO word a second time and
                    // produced two AW/W handshakes for one store word.  Wait for
                    // the pop to actually take effect.
                    if (wf_rvalid && !wf_pop && ddr_rdy) wstate <= W_RUN;
                end
                W_RUN: begin
                    if (paxi_awvalid && paxi_awready) aw_seen <= 1'b1;
                    if (paxi_wvalid  && paxi_wready ) w_seen  <= 1'b1;
                    if ((aw_seen || (paxi_awvalid && paxi_awready)) &&
                        (w_seen  || (paxi_wvalid  && paxi_wready ))) begin
                        wf_pop <= 1'b1;
                        wstate <= W_IDLE;
                    end
                end
                default: wstate <= W_IDLE;
            endcase
        end
    end

    // -------------------------------------------------- DDR-side read engine
    // T10.b9 F3: the AR must only be issued when the DDR side is actually ready
    // (ddr_rdy) and when no earlier AR is still outstanding, and the address
    // FIFO may only be popped by the AR handshake itself.  The old form
    //   paxi_arvalid = af_rvalid && !ar_pending            (no ddr_rdy)
    //   af_pop       = af_rvalid && paxi_arready && ddr_rdy (no arvalid)
    // could pop an address that was never issued (read stalls forever) or
    // re-issue the same address while ddr_rdy was low (duplicate rdata).
    // (ar_pending / r_expected are declared with the read-data section above.)
    assign paxi_araddr  = af_rdata;
    // T10.b13: no AR while the purge/guard window is open, and the AF is drained
    // by the purge itself (af_pop_purge never sets ar_pending).
    assign paxi_arvalid = af_rvalid && !ar_pending && ddr_rdy && !rd_hold;
    wire   af_pop_normal = paxi_arvalid && paxi_arready;
    wire   af_pop_purge  = rd_hold && af_rvalid;
    assign af_pop        = af_pop_normal || af_pop_purge;

    always @(posedge clk_ddr or negedge rst_n) begin
        if (!rst_n) ar_pending <= 1'b0;
        else if (purge_evt || rd_hold) ar_pending <= 1'b0;         // purge wins
        else if (af_pop_normal) ar_pending <= 1'b1;                // AR accepted by the DDR
        else if (paxi_rvalid && paxi_rready) ar_pending <= 1'b0;   // data returned
    end

    always @(posedge clk_ddr or negedge rst_n) begin
        if (!rst_n) begin
            ddr_purge <= 4'd0;
            guard_cnt_ddr <= 32'd0;
            stale_guard_cnt <= 32'd0;
        end else begin
            if (purge_evt) begin
                ddr_purge      <= DDR_PURGE_N[3:0];
                guard_cnt_ddr  <= BRIDGE_GUARD_N;
            end else begin
                if (ddr_purge != 4'd0)     ddr_purge     <= ddr_purge - 4'd1;
                if (guard_cnt_ddr != 32'd0) guard_cnt_ddr <= guard_cnt_ddr - 32'd1;
            end
            // A response that arrives while this bridge has no outstanding AR
            // (the timed-out read, or anything after it) is absorbed by
            // paxi_rready=1 and only counted.
            if (rd_hold && paxi_rvalid) stale_guard_cnt <= stale_guard_cnt + 32'd1;
        end
    end

    // =========================================================================
    // T10.b11-aplus-read: observation only (no effect on the engines above).
    // =========================================================================
    reg [31:0] ar_cnt;        // PAXI AR handshakes
    reg [31:0] ar_block_cnt;  // clk_ddr cycles with af_rvalid but no paxi_arvalid
    reg [31:0] r_cnt;         // PAXI R handshakes
    reg [31:0] rlast_cnt;     // PAXI R handshakes with rlast
    reg [31:0] stale_r_cnt;   // paxi_rvalid while no AR is outstanding (swallowed)

    wire ar_hs    = paxi_arvalid && paxi_arready;
    wire r_hs     = paxi_rvalid  && paxi_rready;
    wire r_block  = af_rvalid && !paxi_arvalid;
    wire r_stale  = paxi_rvalid && !ar_pending;

    always @(posedge clk_ddr or negedge rst_n) begin
        if (!rst_n) begin
            ar_cnt <= 32'd0; ar_block_cnt <= 32'd0; r_cnt <= 32'd0;
            rlast_cnt <= 32'd0; stale_r_cnt <= 32'd0;
        end else begin
            if (ar_hs)   ar_cnt       <= ar_cnt       + 32'd1;
            if (r_block) ar_block_cnt <= ar_block_cnt + 32'd1;
            if (r_hs)    r_cnt        <= r_cnt        + 32'd1;
            if (r_hs && paxi_rlast) rlast_cnt <= rlast_cnt + 32'd1;
            if (r_stale) stale_r_cnt  <= stale_r_cnt  + 32'd1;
        end
    end

    // clk_ddr observation word (bit map fixed by the v4 #44 field):
    wire [31:0] br0_ddr = {23'd0, wf_pop, wf_rvalid, w_seen, aw_seen, wstate,
                           rf_wready, af_rvalid, ar_pending, ddr_rdy};
    wire [255:0] dbg_ddr = {32'd0, stale_guard_cnt, stale_r_cnt, rlast_cnt,
                            r_cnt, ar_block_cnt, ar_cnt, br0_ddr};
    wire [255:0] dbg_mid;

    // Stable-hold/toggle transfer: 256 clk_ddr cycles (1.28 us @ 200 MHz)
    // between publications, so the slower clk_a1 side always samples a frozen
    // bus.  The mailbox is observation-only and never blocks either domain.
    cam_diag_mailbox #(.W(256), .DIV_BITS(8)) u_dbg_mail(
        .clk_slow   (clk_ddr),
        .rst_slow_n (rst_n),
        .i_data     (dbg_ddr),
        .clk_fast   (clk_a1),
        .rst_fast_n (rst_n),
        .o_data     (dbg_mid)
    );

    // #44 keeps the clk_a1-side bits direct (they are already clk_a1):
    reg [31:0] br0_a1;
    always @(*) begin
        br0_a1     = 32'd0;
        br0_a1[0]  = dbg_mid[0];   // ddr_rdy
        br0_a1[1]  = dbg_mid[1];   // ar_pending
        br0_a1[2]  = dbg_mid[2];   // af_rvalid
        br0_a1[3]  = af_wready;
        br0_a1[4]  = rf_rvalid;
        br0_a1[5]  = dbg_mid[3];   // rf_wready
        br0_a1[6]  = s_rvalid_r;
        br0_a1[7]  = s_rready;
        br0_a1[8]  = dbg_mid[4];   // wstate
        br0_a1[9]  = dbg_mid[5];   // aw_seen
        br0_a1[10] = dbg_mid[6];   // w_seen
        br0_a1[11] = dbg_mid[7];   // wf_rvalid
        br0_a1[12] = dbg_mid[8];   // wf_pop
    end
    assign dbg_a1 = {purge_cnt,           // [255:224] T10.b13 purge events
                     dbg_mid[223:192],    // [223:192] stale_guard_cnt
                     dbg_mid[191:160],    // [191:160] stale_r_cnt
                     dbg_mid[159:128],    // [159:128] rlast_cnt
                     dbg_mid[127:96],     // [127:96]  r_cnt
                     dbg_mid[95:64],      // [95:64]   ar_block_cnt
                     dbg_mid[63:32],      // [63:32]   ar_cnt
                     br0_a1};             // [31:0]    br0 (unchanged)
endmodule
