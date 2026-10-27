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
//
// T10.b15-ddr-pace: read engine only (no protocol/format change).
//   R1 ar_busy  : set on the AR handshake, cleared ONLY by rvalid&&rready&&rlast
//                 (or the b13 purge/guard force-clear).  b13 cleared it on the
//                 first R handshake, which made "one outstanding AR" nominal and
//                 let a beat with r_expected=0 be swallowed (rready=1, no push).
//   R2 AR gate  : a new AR needs !ar_busy && the read-data path empty
//                 (rf_level==0 from a Gray pop counter + empty skid) && ddr_rdy
//                 && !rd_hold.  MAX_OS = 1 (one AR in flight, start .. rlast).
//   R3 rready   : constant 1; overflow is prevented by R2, never by back-pressure.
//   R4 push     : every beat of an owned burst is pushed; an orphan beat is only
//                 counted (stale_r_cnt), never queued.
//   R5 fallback : TIMEOUT 8192 clk_a1 / RETRY_MAX 2 / A1_GUARD_N 70000 /
//                 BRIDGE_GUARD_N 65536 / purge semantics are b13-identical.
//
// T10.b17-paxi-native: this module is the ONE native PAXI boundary.
//   A1  : internal slot address is a 256-bit WORD index (max 424313).
//   PAXI: native word address {word_index[23:0], 3'b000} on AW and AR, so
//         internal word 0/1/2 appears on the port as 0/8/16.
//   mask: paxi_wstrb = 0 (native contract: mask 0 writes every byte).
//   cmd : ALLOW_CONCURRENT=0 (default) makes AW/W and AR mutually exclusive,
//         write-priority; =1 is a comparison-only configuration.
//   v6  : dbg_a1 grows to 512 bits with the last-issued AR address, the
//         timeout-latched AR address/low3, same-cycle AW/W+AR counters and
//         the in-flight state word.  Bits [255:0] keep the b15 layout.
// =============================================================================
module p2_ddr_bridge #(
    // 0 = native single-command diagnostic default (bitgen/board value).
    // 1 = comparison only: lets an AR request coincide with a write start.
    parameter integer ALLOW_CONCURRENT = 0
) (
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
    // T10.b17: 256 -> 512 bits; [511:256] are the v6 diagnostics, [255:0] are
    // byte-for-byte the b15 layout.
    output wire [511:0] dbg_a1
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
    //
    // T10.b15 R1/R3/R4: ar_busy replaces b13's ar_pending.  ar_pending was
    // cleared by the FIRST R handshake, so "one outstanding AR" was only
    // nominal: the next AR could be accepted while the previous burst was still
    // returning, and a beat presented after that first handshake met
    // r_expected=0 -> paxi_rready=1 but rf_push=0, i.e. the beat was swallowed
    // (r_cnt grew, no frame data, exactly the board's "one R short per attempt").
    //   * ar_busy is set by the AR handshake and cleared ONLY by
    //     paxi_rvalid && paxi_rready && paxi_rlast (plus the b13 purge/guard
    //     force-clear), so a new AR can never overlap an owned burst;
    //   * paxi_rready is constant 1 (see below), so no beat of an owned burst
    //     can ever be back-pressured away; overflow is made structurally
    //     impossible by the AR issue condition instead (R2);
    //   * every beat of an owned burst is pushed, an orphan beat is only
    //     counted (stale_r_cnt) and never queued.
    reg          ar_busy;
    wire         ar_busy_win = ar_busy;                                // R4 window
    wire         rf_push     = paxi_rvalid && paxi_rready && ar_busy_win;

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

    // ------------------------------------------- T10.b15 R2 read-data-path gate
    // A new AR may only be issued when the whole read-data path is empty, so the
    // 16-entry RF can never overflow and paxi_rready never has to back-pressure.
    // Occupancy = pushes (clk_ddr, local) - pops (clk_a1, Gray counter through a
    // 2-flop synchroniser).  A Gray counter changes one bit per pop, so any
    // sampled value is a real, possibly stale, pop count: rf_level can only be
    // OVER-estimated, never under-estimated.  rf_level==0 therefore really means
    // "the FIFO is empty" (never the reverse), which is exactly the conservative
    // direction for a no-overflow argument.  The one-deep skid register is
    // included as a synchronised level, so "empty" covers the whole path.
    reg  [4:0]  rf_push_cnt;
    reg  [4:0]  rf_pop_bin;
    reg  [4:0]  rf_pop_gray;
    (* async_reg = "true" *) reg [4:0] rf_pop_s0, rf_pop_s1;
    (* async_reg = "true" *) reg       skid_s0, skid_s1;
    wire [4:0]  rf_pop_nxt      = rf_pop_bin + 5'd1;
    wire [4:0]  rf_pop_sync_bin = { rf_pop_s1[4],
                                    rf_pop_s1[4]^rf_pop_s1[3],
                                    rf_pop_s1[4]^rf_pop_s1[3]^rf_pop_s1[2],
                                    rf_pop_s1[4]^rf_pop_s1[3]^rf_pop_s1[2]^rf_pop_s1[1],
                                    rf_pop_s1[4]^rf_pop_s1[3]^rf_pop_s1[2]^rf_pop_s1[1]^rf_pop_s1[0] };
    wire [4:0]  rf_level        = rf_push_cnt - rf_pop_sync_bin;
    wire        rf_path_empty   = (rf_level == 5'd0) && skid_s1;

    always @(posedge clk_ddr or negedge rst_n) begin
        if (!rst_n) rf_push_cnt <= 5'd0;
        // Count only beats the FIFO really took (capture_async_fifo drops a beat
        // when w_ready is low).  R2 makes that case unreachable; qualifying it
        // keeps the occupancy counter from leaking if it ever does happen.
        else if (rf_push && rf_wready) rf_push_cnt <= rf_push_cnt + 5'd1;
    end

    always @(posedge clk_a1 or negedge rst_n) begin
        if (!rst_n) begin
            rf_pop_bin  <= 5'd0;
            rf_pop_gray <= 5'd0;
        end else if (rf_pop) begin
            rf_pop_bin  <= rf_pop_nxt;
            rf_pop_gray <= rf_pop_nxt ^ (rf_pop_nxt >> 1);
        end
    end

    always @(posedge clk_ddr or negedge rst_n) begin
        if (!rst_n) begin
            rf_pop_s0 <= 5'd0;
            rf_pop_s1 <= 5'd0;
            skid_s0   <= 1'b1;
            skid_s1   <= 1'b1;
        end else begin
            rf_pop_s0 <= rf_pop_gray;
            rf_pop_s1 <= rf_pop_s0;
            skid_s0   <= !s_rvalid_r;
            skid_s1   <= skid_s0;
        end
    end

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
    // T10.b15 R3: paxi_rready is 1 at ALL times.  b13 lowered it to rf_wready
    // while an AR was outstanding, i.e. it used R-channel back-pressure to keep
    // the RF from overflowing; on the board that cost exactly one beat per read
    // attempt.  With a strictly single outstanding AR that is only issued into
    // an empty read-data path (R2), no burst can ever fill the FIFO, so the
    // response channel never has to be stalled.  A beat with no owned burst
    // (ar_busy=0: timed-out attempt, business reset, purge window) is absorbed
    // and only counted (stale_r_cnt / stale_guard_cnt).
    assign paxi_rready = 1'b1;

    // ------------------------------------------------- DDR-side write engine
    localparam [1:0] W_IDLE = 2'd0, W_RUN = 2'd1;
    reg [1:0] wstate;
    reg       aw_seen, w_seen;

    // T10.b17: native PAXI address unit.  The only address conversion in the
    // whole chain: internal 256-bit word index -> native address (word * 8).
    localparam [23:0] PAXI_MAX_WORD = 24'd424313;
    assign paxi_awaddr  = {wf_rdata[276:256], 5'b00000};  // T11 r1: 256-bit word index -> byte address (x32); the x8 form left the store writes and the pusher byte reads in different units
    assign paxi_wdata   = wf_rdata[255:0];
    // T10.b17: native full-word write mask.  Bit=0 enables the byte; all-zero
    // therefore writes the complete 32-byte beat (all-ones would write nothing).
    assign paxi_wstrb   = 32'h0000_0000;
    assign paxi_wlast   = 1'b1;            // single-beat transaction
    assign paxi_awvalid = (wstate == W_RUN) && !aw_seen;
    assign paxi_wvalid  = (wstate == W_RUN) && !w_seen;

    // T10.b17 single-command acceptance (ALLOW_CONCURRENT=0 default).
    // wr_start_req is the write-priority request that moves W_IDLE -> W_RUN.
    // rd_req additionally requires W_IDLE, so an AR is never presented while
    // the write engine owns the command port; the combinational term below
    // also suppresses an AR in the exact cycle a write starts.
    wire wr_start_req = wf_rvalid && !wf_pop && ddr_rdy && !ar_busy;
    // ALLOW_CONCURRENT=1 removes the W_IDLE gate too, so the comparison build
    // can really present AR while AW/W are active; =0 keeps the native rule.
    wire rd_req       = af_rvalid && !ar_busy && rf_path_empty &&
                        ddr_rdy && !rd_hold &&
                        ((ALLOW_CONCURRENT != 0) || (wstate == W_IDLE));

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
                    if (wr_start_req) wstate <= W_RUN;
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
    // (ar_busy / the RF occupancy counters are declared with the read-data
    //  section above; T10.b15 replaced the old ar_pending first-beat clear.)
    // T10.b17: the same unique address conversion is applied to AR.
    assign paxi_araddr  = {af_rdata[20:0], 5'b00000};  // T11 r1: same word->byte scaling as the AW side
    // T10.b13: no AR while the purge/guard window is open, and the AF is drained
    // by the purge itself (af_pop_purge never sets ar_busy).
    // T10.b15 R2: a new AR also requires the whole read-data path to be empty
    // (!ar_busy, rf_level==0, skid empty) so the burst that follows has room by
    // construction and MAX_OS stays 1 (one AR in flight, start to rlast).
    // T10.b17: write-priority single-command arbitration.  With the default
    // ALLOW_CONCURRENT=0, an AR request in the same cycle as a write start is
    // held (valid dropped before any ready) until the write has completed.
    assign paxi_arvalid = rd_req && ((ALLOW_CONCURRENT != 0) || !wr_start_req);
    wire   af_pop_normal = paxi_arvalid && paxi_arready;
    wire   af_pop_purge  = rd_hold && af_rvalid;
    assign af_pop        = af_pop_normal || af_pop_purge;

    always @(posedge clk_ddr or negedge rst_n) begin
        if (!rst_n) ar_busy <= 1'b0;
        else if (purge_evt || rd_hold) ar_busy <= 1'b0;        // purge/guard wins
        else if (af_pop_normal) ar_busy <= 1'b1;               // AR accepted by the DDR
        // T10.b15 R1: only the FINAL beat of the burst closes the AR.
        else if (paxi_rvalid && paxi_rready && paxi_rlast) ar_busy <= 1'b0;
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
    // T10.b15: "no owned burst" is ar_busy (b13: ar_pending).
    wire r_stale  = paxi_rvalid && !ar_busy;

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

    // =========================================================================
    // T10.b17 v6 diagnostics (clk_ddr; observation only, no engine feedback).
    // =========================================================================
    reg  [26:0] last_issued_ar_addr;
    reg  [26:0] timeout_ar_addr;
    reg         timeout_ar_valid;
    reg  [31:0] same_aw_ar_cnt, same_w_ar_cnt;
    reg         same_aw_ar_seen, same_w_ar_seen;
    reg         oob_addr_seen, low3_nonzero_seen, wstrb_nonzero_seen;

    wire aw_hs_v6 = paxi_awvalid && paxi_awready;
    wire w_hs_v6  = paxi_wvalid  && paxi_wready;
    wire ar_hs_v6 = paxi_arvalid && paxi_arready;
    wire same_aw_ar = aw_hs_v6 && ar_hs_v6;
    wire same_w_ar  = w_hs_v6  && ar_hs_v6;
    wire aw_idx_oob = (wf_rdata[282:256] > PAXI_MAX_WORD);
    wire ar_idx_oob = (af_rdata > PAXI_MAX_WORD);

    always @(posedge clk_ddr or negedge rst_n) begin
        if (!rst_n) begin
            last_issued_ar_addr <= 27'd0;
            timeout_ar_addr     <= 27'd0;
            timeout_ar_valid    <= 1'b0;
            same_aw_ar_cnt      <= 32'd0;
            same_w_ar_cnt       <= 32'd0;
            same_aw_ar_seen     <= 1'b0;
            same_w_ar_seen      <= 1'b0;
            oob_addr_seen       <= 1'b0;
            low3_nonzero_seen   <= 1'b0;
            wstrb_nonzero_seen  <= 1'b0;
        end else begin
            if (ar_hs_v6) last_issued_ar_addr <= paxi_araddr;
            // Latch the failed AR when the b13 abort purge fires with an AR
            // still outstanding; a successful rlast (or reset) clears the flag.
            if (purge_evt && ar_busy) begin
                timeout_ar_addr  <= last_issued_ar_addr;
                timeout_ar_valid <= 1'b1;
            end else if (paxi_rvalid && paxi_rready && paxi_rlast) begin
                timeout_ar_valid <= 1'b0;
            end
            if (same_aw_ar) begin
                same_aw_ar_cnt  <= same_aw_ar_cnt + 32'd1;
                same_aw_ar_seen <= 1'b1;
            end
            if (same_w_ar) begin
                same_w_ar_cnt  <= same_w_ar_cnt + 32'd1;
                same_w_ar_seen <= 1'b1;
            end
            // Sticky contract monitors.  The OOB check only evaluates while the
            // source FIFO really holds a word (never on reset/empty garbage).
            if (wf_rvalid && aw_idx_oob) oob_addr_seen <= 1'b1;
            if (af_rvalid && ar_idx_oob) oob_addr_seen <= 1'b1;
            if ((paxi_awvalid && (paxi_awaddr[2:0] != 3'b000)) ||
                (paxi_arvalid && (paxi_araddr[2:0] != 3'b000)))
                low3_nonzero_seen <= 1'b1;
            if (paxi_wvalid && (|paxi_wstrb)) wstrb_nonzero_seen <= 1'b1;
        end
    end

    wire [31:0] inflight_state = {24'd0, paxi_arvalid, rf_path_empty, rd_hold,
                                  ddr_rdy, wstate[0], w_seen, aw_seen, ar_busy};
    wire [31:0] diag_flags = {26'd0, wstrb_nonzero_seen, low3_nonzero_seen,
                              oob_addr_seen, same_w_ar_seen, same_aw_ar_seen,
                              timeout_ar_valid};

    // clk_ddr observation word (bit map fixed by the v4 #44 field):
    // T10.b15: bit [1] keeps its "an AR is outstanding" meaning (ar_busy).
    wire [31:0] br0_ddr = {23'd0, wf_pop, wf_rvalid, w_seen, aw_seen, wstate,
                           rf_wready, af_rvalid, ar_busy, ddr_rdy};
    wire [511:0] dbg_ddr = {diag_flags,                    // [511:480]
                            inflight_state,                // [479:448]
                            same_w_ar_cnt,                 // [447:416]
                            same_aw_ar_cnt,                // [415:384]
                            {29'd0, timeout_ar_addr[2:0]}, // [383:352]
                            {5'd0,  timeout_ar_addr},      // [351:320]
                            {29'd0, last_issued_ar_addr[2:0]}, // [319:288]
                            {5'd0,  last_issued_ar_addr},  // [287:256]
                            32'd0,                         // [255:224] unused (b15)
                            stale_guard_cnt,               // [223:192]
                            stale_r_cnt,                   // [223:192]
                            rlast_cnt,                     // [191:160]
                            r_cnt,                         // [159:128]
                            ar_block_cnt,                  // [127:96]
                            ar_cnt,                        // [95:64]
                            br0_ddr};                      // [63:0]
    wire [511:0] dbg_mid;

    // Stable-hold/toggle transfer: 256 clk_ddr cycles (1.28 us @ 200 MHz)
    // between publications, so the slower clk_a1 side always samples a frozen
    // bus.  The mailbox is observation-only and never blocks either domain.
    cam_diag_mailbox #(.W(512), .DIV_BITS(8)) u_dbg_mail(
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
    assign dbg_a1 = {dbg_mid[511:256],    // [511:256] T10.b17 v6 diagnostics
                     purge_cnt,           // [255:224] T10.b13 purge events
                     dbg_mid[223:192],    // [223:192] stale_guard_cnt
                     dbg_mid[191:160],    // [191:160] stale_r_cnt
                     dbg_mid[159:128],    // [159:128] rlast_cnt
                     dbg_mid[127:96],     // [127:96]  r_cnt
                     dbg_mid[95:64],      // [95:64]   ar_block_cnt
                     dbg_mid[63:32],      // [63:32]   ar_cnt
                     br0_a1};             // [31:0]    br0 (unchanged)
`ifdef SIMULATION
    // T10.b17: an out-of-range word index must never reach the PAXI port.
    // Simulation fails loudly; the synthesized path only sets the sticky bit.
    always @(posedge clk_ddr) begin
        if (rst_n && ((paxi_awvalid && aw_idx_oob) ||
                      (paxi_arvalid && ar_idx_oob)))
            $fatal(1, "B17_PAXI_OOB_ADDR aw=%b awidx=%0d aridx=%0d max=%0d",
                   paxi_awvalid, wf_rdata[282:256], af_rdata, PAXI_MAX_WORD);
    end
`endif
endmodule
