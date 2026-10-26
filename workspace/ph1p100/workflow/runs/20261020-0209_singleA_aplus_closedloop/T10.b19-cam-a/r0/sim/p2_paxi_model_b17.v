`timescale 1ns/1ps
// =============================================================================
// p2_paxi_model_b17.v -- native-contract PAXI model (simulation only).
//
// T10.b17: the b15 model assumed "array word index, mask ignored".  This model
// enforces the native contract that the b17 bridge is supposed to meet:
//   * address   : word = addr[26:3]; addr[2:0] MUST be 0 (n_bad_low3);
//                 word > 424313 is out of range (n_oob).  A bad address is
//                 consumed/counted on write and returns poison with rlast=1 on
//                 read, so it can never alias a neighbouring word and never
//                 hangs the DUT.
//   * mask      : wstrb[i] == 0 enables byte i, wstrb[i] == 1 preserves it.
//                 All-zero = full-word write, all-ones = write nothing.
//   * AW/W      : separate channels latched independently and committed once
//                 both are present (n_write_commit).
//   * commands  : awready and arready are never high together (write priority);
//                 n_same_hs counts same-cycle handshakes, n_same_req counts a
//                 DUT that presents AW+AR or W+AR in the same cycle.
//
// All b13/b15 injections are kept; DROP_ADDR / LATE_ADDR are NATIVE addresses
// (word * 8), so a dropped AR must have addr[2:0] == 0.
// =============================================================================
module p2_paxi_model_b17 #(
    parameter integer WORDS  = 524288,   // 2^19 beats cover raw pair + cmp pair
    parameter integer AR_GAP = 3,        // cycles between arready stalls
    parameter integer R_GAP  = 3,        // read latency in clk beats
    parameter integer DUP_R  = 0,        // 1 = duplicate every 4096th beat
    parameter integer STRAY_R= 0,        // 1 = one unsolicited R after reset
    // ---------------- T10.b13 deterministic lost-response injection ----------
    parameter integer DROP_ADDR  = -1,   // native address
    parameter integer DROP_OCC   = 0,
    parameter integer DROP_FIRST_N = 0,
    parameter integer LATE_ADDR  = -1,   // native address
    parameter integer LATE_OCC   = 0,
    parameter integer LATE_DELAY = 0,
    // ---------------- T10.b15 channel-timing injection ----------------------
    parameter integer AR_STALL_OCC = 0,
    parameter integer AR_STALL_N   = 0,
    parameter integer RV_GAP_OCC   = 0,
    parameter integer RV_GAP_N     = 0,
    // Comparison-only: emulate a permissive responder that can assert awready
    // and arready together, so the negative control can observe same-cycle
    // handshakes from an ALLOW_CONCURRENT=1 bridge.  Never used by clean runs.
    parameter integer ALLOW_BOTH_READY = 0
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         rdy,

    input  wire [26:0]  awaddr,
    input  wire         awvalid,
    output wire         awready,
    input  wire [255:0] wdata,
    input  wire [31:0]  wstrb,
    input  wire         wvalid,
    input  wire         wlast,
    output wire         wready,

    input  wire [26:0]  araddr,
    input  wire         arvalid,
    output wire         arready,
    output reg  [255:0] rdata,
    output wire         rlast,
    output reg          rvalid,
    input  wire         rready,

    output reg  [31:0]  n_ar_hs,
    output reg  [31:0]  n_aw_hs,
    output reg  [31:0]  n_whs,
    output reg  [31:0]  n_r_hs,
    // T10.b17 contract counters
    output reg  [31:0]  n_bad_low3,
    output reg  [31:0]  n_oob,
    output reg  [31:0]  n_mask_nonzero,
    output reg  [31:0]  n_same_req,
    output reg  [31:0]  n_same_hs,
    output reg  [31:0]  n_write_commit
);
    localparam [23:0] MAX_WORD = 24'd424313;
    localparam [255:0] POISON  = 256'hBAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0;

    reg [255:0] mem [0:WORDS-1];

    reg [7:0] tick;
    always @(posedge clk) begin
        if (!rst_n) tick <= 8'd0;
        else        tick <= tick + 8'd1;
    end

    // T10.b15 S7c: a long arready stall after a chosen AR handshake.
    integer    ar_occ = 0;
    reg [15:0] stall_cnt = 16'd0;
    always @(posedge clk) begin
        if (!rst_n) begin
            ar_occ    <= 0;
            stall_cnt <= 16'd0;
        end else begin
            if (stall_cnt != 16'd0) stall_cnt <= stall_cnt - 16'd1;
            if (arvalid && arready && (AR_STALL_OCC > 0) && (ar_occ + 1 == AR_STALL_OCC))
                stall_cnt <= AR_STALL_N[15:0];
            if (arvalid && arready) ar_occ <= ar_occ + 1;
        end
    end

    wire aw_stall = (AR_GAP > 1) && ((tick % AR_GAP) == 0);
    wire ar_stall = (AR_GAP > 1) && ((tick % AR_GAP) == 1);

    reg         aw_pend, w_pend;
    // Native single-command model: an AR is accepted only in a cycle where no
    // AW is being accepted (write priority).  Idle awready does not block AR.
    wire aw_accept = awvalid && awready;
    assign awready = rst_n && !aw_stall && !aw_pend;
    assign wready  = rst_n && !aw_stall && !w_pend;
    assign arready = rst_n && !ar_stall && (stall_cnt == 16'd0) &&
                     ((ALLOW_BOTH_READY != 0) || !aw_accept);
    assign rlast   = 1'b1;

    // ------------------------------------------------------- AW / W split latch
    reg [26:0]  aw_addr_r;
    reg [255:0] w_data_r;
    reg [31:0]  w_strb_r;

    wire aw_hs = awvalid && awready;
    wire w_hs  = wvalid  && wready;
    wire ar_hs = arvalid && arready;
    wire commit = (aw_pend || aw_hs) && (w_pend || w_hs);

    wire [26:0] commit_addr = aw_pend ? aw_addr_r : awaddr;
    wire [255:0] commit_data = w_pend ? w_data_r : wdata;
    wire [31:0]  commit_strb = w_pend ? w_strb_r : wstrb;
    wire [23:0]  commit_word24 = commit_addr[26:3];
    wire         commit_bad = (commit_addr[2:0] != 3'b000) ||
                              (commit_word24 > MAX_WORD);

    // Per-cycle request-level concurrency observation (before any ready).
    wire req_same = (awvalid && arvalid) || (wvalid && arvalid);
    wire hs_same  = (aw_hs && ar_hs) || (w_hs && ar_hs);

    integer bi;
    always @(posedge clk) begin
        if (!rst_n) begin
            aw_pend <= 1'b0; w_pend <= 1'b0;
            aw_addr_r <= 27'd0; w_data_r <= 256'd0; w_strb_r <= 32'd0;
            n_ar_hs <= 32'd0; n_aw_hs <= 32'd0; n_whs <= 32'd0; n_r_hs <= 32'd0;
            n_bad_low3 <= 32'd0; n_oob <= 32'd0; n_mask_nonzero <= 32'd0;
            n_same_req <= 32'd0; n_same_hs <= 32'd0; n_write_commit <= 32'd0;
        end else begin
            if (req_same) n_same_req <= n_same_req + 32'd1;
            if (hs_same)  n_same_hs  <= n_same_hs  + 32'd1;

            if (aw_hs) begin
                n_aw_hs   <= n_aw_hs + 32'd1;
                if (awaddr[2:0] != 3'b000) n_bad_low3 <= n_bad_low3 + 32'd1;
                if (awaddr[26:3] > MAX_WORD) n_oob <= n_oob + 32'd1;
                aw_pend   <= 1'b1;
                aw_addr_r <= awaddr;
            end
            if (w_hs) begin
                n_whs <= n_whs + 32'd1;
                if (|wstrb) n_mask_nonzero <= n_mask_nonzero + 32'd1;
                w_pend   <= 1'b1;
                w_data_r <= wdata;
                w_strb_r <= wstrb;
            end
            if (commit) begin
                n_write_commit <= n_write_commit + 32'd1;
                if (!commit_bad) begin
                    // Native mask semantics: bit=0 enables that byte.
                    for (bi = 0; bi < 32; bi = bi + 1) begin
                        if (!commit_strb[bi])
                            mem[commit_word24[18:0]][bi*8 +: 8] <= commit_data[bi*8 +: 8];
                    end
                end
                aw_pend <= 1'b0;
                w_pend  <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------- read beat
    reg [26:0] pq [0:7];
    reg [3:0]  pq_w, pq_r, pq_cnt;
    reg [26:0] raddr_r;
    reg [7:0]  rwait;
    reg        rpend;
    reg        dup_phase;
    reg        dup_done;
    reg        stray_done;
    reg [26:0] beat_ctr;

    integer    occ_drop = 0;
    integer    occ_late = 0;
    integer    occ_zero = 0;
    reg        drop_this, late_this;
    reg        late_hold = 1'b0;
    reg        rvgap_this = 1'b0;
    reg [31:0] late_cnt;
    integer    late_left, idx;

    wire start_rd = !rpend && (pq_cnt != 4'd0);

    // A bad (low3/oob) address returns poison, never an alias of a real word.
    function [255:0] rd_value;
        input [26:0] a;
        reg [23:0] wd;
        begin
            wd = a[26:3];
            if ((a[2:0] != 3'b000) || (wd > MAX_WORD))
                rd_value = POISON;
            else
                rd_value = mem[wd[18:0]];
        end
    endfunction

    always @(posedge clk) begin
        if (ar_hs) begin
            if (araddr[2:0] != 3'b000) n_bad_low3 <= n_bad_low3 + 32'd1;
            if (araddr[26:3] > MAX_WORD) n_oob <= n_oob + 32'd1;
            drop_this <= 1'b0;
            late_this <= 1'b0;
            rvgap_this <= (RV_GAP_N > 0) && (RV_GAP_OCC > 0) &&
                          (ar_occ + 1 == RV_GAP_OCC);
            if ((DROP_ADDR >= 0) && (araddr == DROP_ADDR[26:0])) begin
                occ_drop <= occ_drop + 1;
                if ((DROP_OCC > 0) && (occ_drop + 1 == DROP_OCC)) begin
                    drop_this <= 1'b1;
                    $display("MODEL_DROP_R addr=%0d occ=%0d cycle=%0t",
                             araddr, occ_drop+1, $time);
                end
            end
            if (araddr == 27'd0) begin
                occ_zero <= occ_zero + 1;
                if ((DROP_FIRST_N > 0) && (occ_zero + 1 <= DROP_FIRST_N)) begin
                    drop_this <= 1'b1;
                    $display("MODEL_DROP_R word0 occ=%0d cycle=%0t", occ_zero+1, $time);
                end
            end
            if ((LATE_ADDR >= 0) && (araddr == LATE_ADDR[26:0])) begin
                occ_late <= occ_late + 1;
                if ((LATE_OCC > 0) && (occ_late + 1 == LATE_OCC)) begin
                    late_this <= 1'b1;
                    $display("MODEL_LATE_R addr=%0d delay=%0d cycle=%0t",
                             araddr, LATE_DELAY, $time);
                end
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            pq_w <= 4'd0; pq_r <= 4'd0; pq_cnt <= 4'd0;
            raddr_r <= 27'd0; rwait <= 8'd0; rpend <= 1'b0;
            rvalid <= 1'b0; rdata <= 256'd0;
            dup_phase <= 1'b0; dup_done <= 1'b0; stray_done <= 1'b0;
            beat_ctr <= 27'd0;
        end else begin
            if (rvalid && rready) begin
                rvalid <= 1'b0;
                n_r_hs <= n_r_hs + 32'd1;
            end

            if (ar_hs) begin
                pq[pq_w[2:0]] <= araddr;
                pq_w          <= pq_w + 4'd1;
                n_ar_hs       <= n_ar_hs + 32'd1;
                if (pq_cnt >= 4'd8) $display("MODEL_PQ_OVERFLOW cnt=%0d", pq_cnt);
            end

            case ({ar_hs, start_rd})
                2'b10: pq_cnt <= pq_cnt + 4'd1;
                2'b01: pq_cnt <= pq_cnt - 4'd1;
                default: pq_cnt <= pq_cnt;
            endcase

            if ((STRAY_R != 0) && !stray_done && !rvalid && (pq_cnt == 4'd0) &&
                (n_ar_hs == 0) && (tick > 8'd40)) begin
                rdata     <= 256'hDEAD_0000_0000_0000_0000_0000_0000_BEEF;
                rvalid    <= 1'b1;
                stray_done<= 1'b1;
            end else if (start_rd) begin
                raddr_r <= pq[pq_r[2:0]];
                pq_r    <= pq_r + 4'd1;
                rwait   <= R_GAP[7:0] + (rvgap_this ? RV_GAP_N[7:0] : 8'd0);
                rpend   <= 1'b1;
            end else if (rpend) begin
                if (late_hold) begin
                    if (late_cnt == 32'd0) begin
                        rdata  <= rd_value(raddr_r);
                        rvalid <= 1'b1;
                        rpend  <= 1'b0;
                        late_hold <= 1'b0;
                        beat_ctr <= beat_ctr + 27'd1;
                    end else begin
                        late_cnt <= late_cnt - 32'd1;
                    end
                end else if (rwait <= 8'd1) begin
                    if (drop_this) begin
                        rpend     <= 1'b0;
                        drop_this <= 1'b0;
                        $display("MODEL_DROP_DONE cycle=%0t", $time);
                    end else if (late_this) begin
                        late_hold <= 1'b1;
                        late_cnt  <= LATE_DELAY[31:0];
                        late_this <= 1'b0;
                    end else begin
                        rdata  <= rd_value(raddr_r);
                        rvalid <= 1'b1;
                        rpend  <= 1'b0;
                        beat_ctr <= beat_ctr + 27'd1;
                    end
                end else begin
                    rwait <= rwait - 8'd1;
                end
            end

            if ((DUP_R != 0) && !dup_done && !rpend && !rvalid &&
                (beat_ctr == 27'd4096) && (pq_cnt == 4'd0)) begin
                rvalid    <= 1'b1;
                dup_phase <= 1'b0;
                dup_done  <= 1'b1;
            end
        end
    end

    // A bad (low3/oob) address returns poison, never an alias of a real word.
    wire unused_rdy = rdy && wlast && (DUP_R == DUP_R);
endmodule
