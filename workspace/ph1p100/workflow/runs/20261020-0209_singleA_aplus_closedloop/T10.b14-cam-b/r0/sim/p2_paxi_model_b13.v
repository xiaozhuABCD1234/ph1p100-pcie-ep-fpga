`timescale 1ns/1ps
// =============================================================================
// p2_paxi_model_b11.v -- behavioural single-beat 256-bit PAXI model (sim only).
//
// T10.b11: widened from the frozen b10 model (2^18 -> 2^19 words) so the
// CMP_CORE slots at 262144..424313 are in range, and given three explicit
// negative-path knobs so the read-response hypotheses can be discriminated:
//   DUP_R    : return a second copy of the same beat (H1 source: extra R)
//   STRAY_R  : return one unsolicited beat before the first AR (H1 source:
//              a leftover response the bridge never asked for)
// Both are off by default; the clean runs use them as negative controls only.
// The model never drops a legitimate R: AR handshakes are queued and every
// queued address is answered 1:1 with rlast=1.
// =============================================================================
module p2_paxi_model_b13 #(
    parameter integer WORDS  = 524288,   // 2^19 beats cover raw pair + cmp pair
    parameter integer AR_GAP = 3,        // cycles between arready stalls
    parameter integer R_GAP  = 3,        // read latency in clk beats
    parameter integer DUP_R  = 0,        // 1 = duplicate every 4096th beat
    parameter integer STRAY_R= 0,        // 1 = one unsolicited R after reset
    // ---------------- T10.b13 deterministic lost-response injection ----------
    // DROP_ADDR / DROP_OCC : drop the R of the DROP_OCC-th AR that reads
    //                        DROP_ADDR (never returned; the AR is still taken).
    // DROP_FIRST_N         : drop the R of the first N ARs that read word 0.
    // LATE_ADDR / LATE_OCC / LATE_DELAY : answer that AR LATE_DELAY clk later.
    parameter integer DROP_ADDR  = -1,
    parameter integer DROP_OCC   = 0,
    parameter integer DROP_FIRST_N = 0,
    parameter integer LATE_ADDR  = -1,
    parameter integer LATE_OCC   = 0,
    parameter integer LATE_DELAY = 0
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
    output reg  [31:0]  n_r_hs
);
    reg [255:0] mem [0:WORDS-1];

    reg [7:0] tick;
    always @(posedge clk) begin
        if (!rst_n) tick <= 8'd0;
        else        tick <= tick + 8'd1;
    end

    wire aw_stall = (AR_GAP > 1) && ((tick % AR_GAP) == 0);
    wire ar_stall = (AR_GAP > 1) && ((tick % AR_GAP) == 1);

    assign awready = rst_n && !aw_stall;
    assign wready  = rst_n && !aw_stall;
    assign arready = rst_n && !ar_stall;
    assign rlast   = 1'b1;

    // ------------------------------------------------------------- write beat
    always @(posedge clk) begin
        if (awvalid && awready) n_aw_hs <= n_aw_hs + 32'd1;
        if (wvalid  && wready ) n_whs   <= n_whs   + 32'd1;
        if (awvalid && awready && wvalid && wready)
            mem[awaddr[18:0]] <= wdata;
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

    // T10.b13 fault bookkeeping (only one AR may be outstanding per bridge, so a
    // single "this response" flag is enough).
    integer     occ_drop = 0;
    integer     occ_late = 0;
    integer     occ_zero = 0;
    reg         drop_this, late_this;
    reg         late_hold = 1'b0;
    reg  [31:0] late_cnt;
    integer     late_left, idx;

    wire ar_hs    = arvalid && arready;
    wire start_rd = !rpend && (pq_cnt != 4'd0);
    wire ret      = rpend && (rwait <= 8'd1);

    always @(posedge clk) begin
        if (ar_hs) begin
            drop_this <= 1'b0;
            late_this <= 1'b0;
            if ((DROP_ADDR >= 0) && (araddr == DROP_ADDR[26:0])) begin
                occ_drop <= occ_drop + 1;
                if ((DROP_OCC > 0) && (occ_drop + 1 == DROP_OCC)) begin
                    drop_this <= 1'b1;
                    $display("MODEL_DROP_R addr=%0d occ=%0d cycle=%0t", araddr, occ_drop+1, $time);
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
            n_ar_hs <= 32'd0; n_aw_hs <= 32'd0; n_whs <= 32'd0; n_r_hs <= 32'd0;
            dup_phase <= 1'b0; dup_done <= 1'b0; stray_done <= 1'b0;
            beat_ctr <= 27'd0;
        end else begin
            if (rvalid && rready) begin rvalid <= 1'b0; n_r_hs <= n_r_hs + 32'd1; end

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

            // STRAY_R: one beat nobody asked for, presented once after reset.
            if ((STRAY_R != 0) && !stray_done && !rvalid && (pq_cnt == 4'd0) &&
                (n_ar_hs == 0) && (tick > 8'd40)) begin
                rdata     <= 256'hDEAD_0000_0000_0000_0000_0000_0000_BEEF;
                rvalid    <= 1'b1;
                stray_done<= 1'b1;
            end else if (start_rd) begin
                raddr_r <= pq[pq_r[2:0]];
                pq_r    <= pq_r + 4'd1;
                rwait   <= R_GAP[7:0];
                rpend   <= 1'b1;
            end else if (rpend) begin
                if (late_hold) begin
                    if (late_cnt == 32'd0) begin
                        rdata  <= mem[raddr_r[18:0]];
                        rvalid <= 1'b1;
                        rpend  <= 1'b0;
                        late_hold <= 1'b0;
                        beat_ctr <= beat_ctr + 27'd1;
                    end else begin
                        late_cnt <= late_cnt - 32'd1;
                    end
                end else if (rwait <= 8'd1) begin
                    if (drop_this) begin
                        // AR accepted, R never returned (the H4 fault)
                        rpend     <= 1'b0;
                        drop_this <= 1'b0;
                        $display("MODEL_DROP_DONE cycle=%0t", $time);
                    end else if (late_this) begin
                        // AR accepted, R arrives only after LATE_DELAY cycles
                        late_hold <= 1'b1;
                        late_cnt  <= LATE_DELAY[31:0];
                        late_this <= 1'b0;
                    end else begin
                        rdata  <= mem[raddr_r[18:0]];
                        rvalid <= 1'b1;
                        rpend  <= 1'b0;
                        beat_ctr <= beat_ctr + 27'd1;
                    end
                end else begin
                    rwait <= rwait - 8'd1;
                end
            end

            // DUP_R: after 4096 answered beats, replay the last one exactly once
            // outside any outstanding AR (the classic "extra response" fault).
            if ((DUP_R != 0) && !dup_done && !rpend && !rvalid &&
                (beat_ctr == 27'd4096) && (pq_cnt == 4'd0)) begin
                // rdata still holds the last answered beat
                rvalid    <= 1'b1;
                dup_phase <= 1'b0;
                dup_done  <= 1'b1;
            end
        end
    end
    wire unused_rdy = rdy && (|wstrb) && wlast && (DUP_R == DUP_R);
endmodule
