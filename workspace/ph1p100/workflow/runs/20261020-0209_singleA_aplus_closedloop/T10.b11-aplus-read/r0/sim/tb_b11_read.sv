`timescale 1ns/1ps
// =============================================================================
// tb_b11_read.sv -- T10.b11 W1: read-response discrimination bench.
//
// Real RTL: a1_ddr_slot_store (MODE 0, raw geometry) -> a1_ddr_arb2 ->
// p2_ddr_bridge (187.5 MHz <-> 200 MHz CDC) -> p2_paxi_model_b11.
// The bench writes NWRITE 256-bit raw words, then reads the whole slot back
// and compares every beat against a shadow copy.
//
// Reported per run (the H1..H4 discrimination vector):
//   store side : ar_hs, rv_cnt, read_words, dup_words, rd_state
//   bridge     : ar_cnt (PAXI AR handshakes), ar_block_cnt, r_cnt, rlast_cnt,
//                stale_r_cnt, br0 (ddr_rdy/ar_pending/af_rvalid/...)
//   model      : n_ar_hs, n_r_hs
//
// Elaboration knobs (-g on vsim): NWRITE, AR_GAP, R_GAP, DUP_R, STRAY_R.
// Case names / plusargs: +NAME=<label>.
// =============================================================================
module tb_b11_read #(
    parameter integer NWRITE  = 2000,
    parameter integer AR_GAP  = 3,
    parameter integer R_GAP   = 3,
    parameter integer DUP_R   = 0,
    parameter integer STRAY_R = 0,
    parameter integer DO_RESET= 0
) ();
    localparam integer SLOTW = 129600;
    // only the exact full raw frame is length-checked by the store
    localparam integer EXPB  = (NWRITE == SLOTW) ? 2592000 : 0;

    reg clk_a1 = 1'b0;
    reg clk_ddr = 1'b0;
    initial begin #1.7000; forever #2.6665 clk_a1 = ~clk_a1; end   // 187.5 MHz
    initial begin #0.4000; forever #2.5000 clk_ddr = ~clk_ddr; end // 200 MHz

    reg rst_n = 1'b0;

    wire        wr_begin_ready, wr_ready;
    reg         wr_begin = 1'b0, wr_valid = 1'b0, wr_last = 1'b0, wr_abort = 1'b0;
    reg  [39:0] wr_data = 40'd0;
    wire [255:0] rd_data;
    wire        rd_valid;
    reg         rd_take = 1'b0;
    reg         rd_open = 1'b0, rd_close = 1'b0;
    wire        rd_open_ready;
    wire [31:0] rd_id, rd_len;

    wire [31:0] st_pub, st_drop, st_err, st_bytes, st_read, st_dup;
    wire [31:0] st_wr_beats, st_wr_words, st_wr_ptr, st_wr_state;
    wire [31:0] st_rd_state, st_slot_st, st_len0, st_len1, st_rd_idx, st_rd_words;
    wire [31:0] st_ar_valid, st_ar_hs, st_rv_cnt, st_open_ok, st_close_cnt, st_abort;
    wire        st_free, st_wr_active;

    wire [31:0] m0_awaddr, m0_araddr;
    wire        m0_awvalid, m0_awready, m0_wvalid, m0_wready;
    wire [255:0] m0_wdata;
    wire        m0_arvalid, m0_arready, m0_rvalid, m0_rready;
    wire [255:0] m0_rdata;
    wire [31:0] m1_awaddr, m1_araddr;
    wire        m1_awvalid, m1_awready, m1_wvalid, m1_wready;
    wire [255:0] m1_wdata;
    wire        m1_arvalid, m1_arready, m1_rvalid, m1_rready;
    wire [255:0] m1_rdata;

    wire [31:0] s_awaddr, s_araddr;
    wire        s_awvalid, s_awready, s_wvalid, s_wready;
    wire [255:0] s_wdata;
    wire        s_arvalid, s_arready, s_rvalid, s_rready;
    wire [255:0] s_rdata;

    wire [26:0]  p_awaddr, p_araddr;
    wire         p_awvalid, p_awready, p_wvalid, p_wlast, p_wready;
    wire [255:0] p_wdata;
    wire [31:0]  p_wstrb;
    wire         p_arvalid, p_arready, p_rlast, p_rvalid, p_rready;
    wire [255:0] p_rdata;
    wire [31:0]  n_ar, n_aw, n_w, n_r;

    wire [191:0] dbg_a1;

    a1_ddr_slot_store #(
        .MODE (0), .SLOT_WORDS (SLOTW), .BASE_WORD (32'd0), .AWB (18),
        .EXPECT_BYTES (EXPB)
    ) u_store (
        .clk (clk_a1), .rst_n (rst_n), .ddr_ready (1'b1),
        .wr_begin (wr_begin), .wr_begin_ready (wr_begin_ready), .wr_id (32'd1),
        .wr_data (wr_data), .wr_keep (4'hF),
        .wr_valid (wr_valid), .wr_last (wr_last), .wr_ready (wr_ready),
        .wr_abort (wr_abort),
        .rd_open (rd_open), .rd_open_ready (rd_open_ready),
        .rd_id (rd_id), .rd_len_bytes (rd_len), .rd_close (rd_close),
        .rd_data (rd_data), .rd_valid (rd_valid), .rd_take (rd_take),
        .ddr_awaddr (m0_awaddr), .ddr_awvalid (m0_awvalid), .ddr_awready (m0_awready),
        .ddr_wdata (m0_wdata), .ddr_wvalid (m0_wvalid), .ddr_wready (m0_wready),
        .ddr_araddr (m0_araddr), .ddr_arvalid (m0_arvalid), .ddr_arready (m0_arready),
        .ddr_rdata (m0_rdata), .ddr_rvalid (m0_rvalid), .ddr_rready (m0_rready),
        .st_published (st_pub), .st_dropped (st_drop), .st_errors (st_err),
        .st_last_bytes (st_bytes), .st_read_words (st_read), .st_dup_words (st_dup),
        .st_wr_beats (st_wr_beats), .st_wr_words (st_wr_words),
        .st_wr_ptr (st_wr_ptr), .st_wr_state (st_wr_state),
        .st_rd_state (st_rd_state), .st_slot_st (st_slot_st),
        .st_slot_len0 (st_len0), .st_slot_len1 (st_len1),
        .st_rd_idx (st_rd_idx), .st_rd_words (st_rd_words),
        .st_ar_valid (st_ar_valid), .st_ar_hs (st_ar_hs),
        .st_rv_cnt (st_rv_cnt), .st_rd_open_ok (st_open_ok),
        .st_rd_close_cnt (st_close_cnt), .st_abort_cnt (st_abort),
        .st_free_valid (st_free), .st_wr_active_out (st_wr_active)
    );

    a1_ddr_arb2 u_arb (
        .clk (clk_a1), .rst_n (rst_n),
        .m0_awaddr (m0_awaddr), .m0_awvalid (m0_awvalid), .m0_awready (m0_awready),
        .m0_wdata (m0_wdata), .m0_wvalid (m0_wvalid), .m0_wready (m0_wready),
        .m0_araddr (m0_araddr), .m0_arvalid (m0_arvalid), .m0_arready (m0_arready),
        .m0_rdata (m0_rdata), .m0_rvalid (m0_rvalid), .m0_rready (m0_rready),
        .m1_awaddr (m1_awaddr), .m1_awvalid (m1_awvalid), .m1_awready (m1_awready),
        .m1_wdata (m1_wdata), .m1_wvalid (m1_wvalid), .m1_wready (m1_wready),
        .m1_araddr (m1_araddr), .m1_arvalid (m1_arvalid), .m1_arready (m1_arready),
        .m1_rdata (m1_rdata), .m1_rvalid (m1_rvalid), .m1_rready (m1_rready),
        .s_awaddr (s_awaddr), .s_awvalid (s_awvalid), .s_awready (s_awready),
        .s_wdata (s_wdata), .s_wvalid (s_wvalid), .s_wready (s_wready),
        .s_araddr (s_araddr), .s_arvalid (s_arvalid), .s_arready (s_arready),
        .s_rdata (s_rdata), .s_rvalid (s_rvalid), .s_rready (s_rready)
    );
    assign m1_awvalid = 1'b0;
    assign m1_wvalid  = 1'b0;
    assign m1_awaddr  = 32'd0;
    assign m1_wdata   = 256'd0;
    assign m1_arvalid = 1'b0;
    assign m1_araddr  = 32'd0;
    assign m1_rready  = 1'b0;

    p2_ddr_bridge u_bridge (
        .clk_a1 (clk_a1), .rst_n (rst_n),
        .s_awaddr (s_awaddr), .s_awvalid (s_awvalid), .s_awready (s_awready),
        .s_wdata (s_wdata), .s_wvalid (s_wvalid), .s_wready (s_wready),
        .s_araddr (s_araddr), .s_arvalid (s_arvalid), .s_arready (s_arready),
        .s_rdata (s_rdata), .s_rvalid (s_rvalid), .s_rready (s_rready),
        .clk_ddr (clk_ddr), .ddr_rdy (1'b1),
        .paxi_awaddr (p_awaddr), .paxi_awvalid (p_awvalid), .paxi_awready (p_awready),
        .paxi_wdata (p_wdata), .paxi_wstrb (p_wstrb), .paxi_wvalid (p_wvalid),
        .paxi_wlast (p_wlast), .paxi_wready (p_wready),
        .paxi_araddr (p_araddr), .paxi_arvalid (p_arvalid), .paxi_arready (p_arready),
        .paxi_rdata (p_rdata), .paxi_rlast (p_rlast), .paxi_rvalid (p_rvalid),
        .paxi_rready (p_rready),
        .dbg_a1 (dbg_a1)
    );

    p2_paxi_model_b11 #(.WORDS(524288), .AR_GAP(AR_GAP), .R_GAP(R_GAP),
                        .DUP_R(DUP_R), .STRAY_R(STRAY_R)) u_ddr (
        .clk (clk_ddr), .rst_n (rst_n), .rdy (1'b1),
        .awaddr (p_awaddr), .awvalid (p_awvalid), .awready (p_awready),
        .wdata (p_wdata), .wstrb (p_wstrb), .wvalid (p_wvalid), .wlast (p_wlast),
        .wready (p_wready),
        .araddr (p_araddr), .arvalid (p_arvalid), .arready (p_arready),
        .rdata (p_rdata), .rlast (p_rlast), .rvalid (p_rvalid), .rready (p_rready),
        .n_ar_hs (n_ar), .n_aw_hs (n_aw), .n_whs (n_w), .n_r_hs (n_r)
    );

    // ------------------------------------------------------- shadow + compare
    reg [255:0] shadow [0:131071];
    integer     n_ok = 0, n_bad = 0, n_beats = 0, cmp_idx = 0;
    integer     cyc = 0, i, w, g;
    reg [255:0] case_name = "multi";
    reg [39:0]  pix;

    always @(posedge clk_a1) begin
        cyc = cyc + 1;
        if (cyc > 20000000) begin
            report("TIMEOUT");
            $finish;
        end
    end

    task report(input [255:0] why);
        begin
            $display("B11_READ_STATE case=%0s cyc=%0d ar_hs=%0d rv=%0d rd_idx=%0d rd_words=%0d dup=%0d rd_state=%0d slot=%h",
                     case_name, cyc, st_ar_hs, st_rv_cnt, st_rd_idx, st_rd_words,
                     st_dup, st_rd_state[5:0], st_slot_st);
            $display("B11_READ_BRIDGE ar_cnt=%0d ar_block=%0d r_cnt=%0d rlast=%0d stale=%0d br0=%h",
                     dbg_a1[63:32], dbg_a1[95:64], dbg_a1[127:96],
                     dbg_a1[159:128], dbg_a1[191:160], dbg_a1[31:0]);
            $display("B11_READ_MODEL ar=%0d r=%0d aw=%0d w=%0d", n_ar, n_r, n_aw, n_w);
            $display("B11_READ_DATA ok=%0d bad=%0d beats=%0d", n_ok, n_bad, n_beats);
            $display("B11_READ_RESULT case=%0s pass=%0d words=%0d bad=%0d why=%0s",
                     case_name, ((why == "ok") && (n_bad == 0) && (st_read == NWRITE)) ? 1 : 0,
                     st_read, n_bad, why);
        end
    endtask

    // read consumer: take every presented word, compare against the shadow
    always @(posedge clk_a1) begin
        if (rst_n && rd_valid && !rd_take) begin
            rd_take <= 1'b1;
            n_beats = n_beats + 1;
            if (rd_data === shadow[cmp_idx]) n_ok = n_ok + 1;
            else begin
                n_bad = n_bad + 1;
                if (n_bad < 4)
                    $display("B11_READ_MISMATCH idx=%0d got=%h exp=%h",
                             cmp_idx, rd_data, shadow[cmp_idx]);
            end
            cmp_idx = cmp_idx + 1;
        end else begin
            rd_take <= 1'b0;
        end
    end

    function [255:0] pack_of(input integer idx);
        integer b;
        reg [39:0] p;
        begin
            pack_of = 256'd0;
            for (b = 0; b < 4; b = b + 1) begin
                p[ 7: 0] = (idx*4 + b) & 8'hFF;
                p[15: 8] = (idx + b*7) & 8'hFF;
                p[23:16] = (idx ^ (b*13)) & 8'hFF;
                p[31:24] = 8'h5A ^ (idx & 8'hFF);
                p[39:32] = idx[5:0];
                pack_of = pack_of | ({216'd0, p} << (b*40));
            end
        end
    endfunction

    task write_frame;
        begin
            wr_begin = 1'b1;
            @(negedge clk_a1);
            while (!wr_begin_ready) @(negedge clk_a1);
            @(posedge clk_a1);
            wr_begin = 1'b0;
            wr_valid = 1'b1;
            for (w = 0; w < NWRITE; w = w + 1) begin
                for (g = 0; g < 4; g = g + 1) begin
                    pix[ 7: 0] = (w*4 + g) & 8'hFF;
                    pix[15: 8] = (w + g*7) & 8'hFF;
                    pix[23:16] = (w ^ (g*13)) & 8'hFF;
                    pix[31:24] = 8'h5A ^ (w & 8'hFF);
                    pix[39:32] = w[5:0];
                    wr_data = pix;
                    wr_last = (g == 3) && (w == NWRITE-1);
                    @(negedge clk_a1);
                    while (!wr_ready) @(negedge clk_a1);
                    @(posedge clk_a1);          // beat accepted here
                end
            end
            wr_valid = 1'b0;
            wr_last  = 1'b0;
            while (st_pub == 0) @(posedge clk_a1);
            $display("B11_READ_WR_DONE words=%0d pub=%0d wr_words=%0d bytes=%0d",
                     NWRITE, st_pub, st_wr_words, st_bytes);
        end
    endtask

    task read_frame;
        begin
            cmp_idx = 0;
            rd_open = 1'b1;
            @(negedge clk_a1);
            while (!rd_open_ready) @(negedge clk_a1);
            @(posedge clk_a1);
            rd_open = 1'b0;
            while ((st_read < NWRITE) && (cyc < 20000000)) @(posedge clk_a1);
            repeat (20) @(posedge clk_a1);
            rd_close = 1'b1;
            @(posedge clk_a1);
            rd_close = 1'b0;
            repeat (50) @(posedge clk_a1);
        end
    endtask

    initial begin
        if (!$value$plusargs("NAME=%s", case_name)) case_name = "multi";
        for (i = 0; i < 131072; i = i + 1) shadow[i] = 256'd0;
        for (i = 0; i < NWRITE; i = i + 1) shadow[i] = pack_of(i);

        repeat (20) @(posedge clk_a1);
        rst_n = 1'b1;
        repeat (40) @(posedge clk_a1);

        write_frame;

        if (DO_RESET != 0) begin
            // start the read, reset mid-session, then require a clean re-read
            rd_open = 1'b1;
            @(negedge clk_a1);
            while (!rd_open_ready) @(negedge clk_a1);
            @(posedge clk_a1);
            rd_open = 1'b0;
            while ((st_read < (NWRITE/4)) && (cyc < 20000000)) @(posedge clk_a1);
            @(negedge clk_a1);
            rst_n = 1'b0;
            repeat (20) @(posedge clk_a1);
            rst_n = 1'b1;
            repeat (60) @(posedge clk_a1);
            $display("B11_READ_RESET_STATE pub=%0d read=%0d free=%0d slot=%h",
                     st_pub, st_read, st_free, st_slot_st);
            n_ok = 0; n_bad = 0; n_beats = 0;
            write_frame;
            read_frame;
            report("ok");
        end else begin
            read_frame;
            report((st_read == NWRITE) ? "ok" : "stall");
        end
        $finish;
    end
endmodule
