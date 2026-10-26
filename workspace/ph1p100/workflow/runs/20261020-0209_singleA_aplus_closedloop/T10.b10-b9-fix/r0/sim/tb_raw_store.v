`timescale 1ns/1ps
// =============================================================================
// tb_raw_store.v -- T10.b9 raw path: a1_ddr_slot_store (MODE 0) + the real P2
// clock bridge (p2_ddr_bridge) + a behavioural 256-bit PAXI DDR model.
//
// Every beat and every word carries a pattern unique per (frame, word, group),
// so a dropped word, a duplicate word or a shifted read shows up as a data
// mismatch.
//
// Cases (+CASE=):
//   full2  : two 1920x1080 frames written, both published and read back exact
//   abort  : frame 0 aborted after 40,000 beats -> slot freed, nothing
//            published, frame 1 still publishes and reads back
//   nofree : two frames published but never read -> a third wr_begin is
//            refused (no half frame), then after readback a new frame works
//   rdy    : full frame, ddr_rdy pulled low in bursts during readback
//            (T10.b9 F3 negative)
//
// Geometry parameters can be shrunk on the vsim command line (-gGROUPS=...),
// the F3/data checks are identical at any size.
// =============================================================================
module tb_raw_store;
    parameter integer GROUPS     = 518400;      // 480 beats x 1080 lines
    parameter integer RAW_WORDS  = 129600;
    parameter integer EXP_BYTES  = 2592000;
    parameter integer ABORT_BEATS = 40000;      // abort() case cut point

    localparam integer SLOT_WORDS = RAW_WORDS;
    localparam integer DDR_WORDS  = 2 * SLOT_WORDS;

    reg clk_a1  = 1'b0;
    reg clk_ddr = 1'b0;
    reg rst_n   = 1'b0;
    always #2.6665 clk_a1  = ~clk_a1;       // 187.5 MHz
    always #2.5    clk_ddr = ~clk_ddr;      // 200 MHz (different domain)

    // ------------------------------------------------------------ store ports
    reg         wr_begin = 1'b0, wr_valid = 1'b0, wr_last = 1'b0, wr_abort = 1'b0;
    reg  [31:0] wr_id = 32'd0;
    reg  [39:0] wr_data = 40'd0;
    reg  [3:0]  wr_keep = 4'hF;
    wire        wr_begin_ready, wr_ready;
    reg         rd_open = 1'b0, rd_take = 1'b0, rd_close = 1'b0;
    wire        rd_open_ready;
    wire [31:0] rd_id, rd_len_bytes;
    wire [255:0] rd_data;
    wire        rd_valid;

    wire [31:0]  awaddr, araddr;
    wire         awvalid, awready, wvalid, wready, arvalid, arready;
    wire [255:0] wdata, rdata;
    wire         rvalid, rready;

    // ------------------------------------------------------------- PAXI side
    reg         ddr_rdy = 1'b1;
    reg         rdy_en  = 1'b0;
    reg  [15:0] rdy_cnt = 16'd0;
    always @(negedge clk_ddr) begin
        rdy_cnt <= rdy_cnt + 16'd1;
        if (!rdy_en) ddr_rdy <= 1'b1;
        else         ddr_rdy <= (rdy_cnt[7:0] >= 8'd96);   // 96 low, 160 high
    end

    wire [26:0]  paxi_awaddr, paxi_araddr;
    wire         paxi_awvalid, paxi_awready, paxi_wvalid, paxi_wready;
    wire [255:0] paxi_wdata, paxi_rdata;
    wire [31:0]  paxi_wstrb;
    wire         paxi_wlast, paxi_arvalid, paxi_arready, paxi_rlast, paxi_rvalid, paxi_rready;
    wire [31:0]  n_ar_hs, n_aw_hs, n_whs, n_r_hs;

    a1_ddr_slot_store #(
        .MODE (0), .SLOT_WORDS (SLOT_WORDS), .BASE_WORD (32'd0), .AWB (18),
        .EXPECT_BYTES (EXP_BYTES)
    ) u_store (
        .clk (clk_a1), .rst_n (rst_n), .ddr_ready (ddr_rdy),
        .wr_begin (wr_begin), .wr_begin_ready (wr_begin_ready), .wr_id (wr_id),
        .wr_data (wr_data), .wr_keep (wr_keep),
        .wr_valid (wr_valid), .wr_last (wr_last), .wr_ready (wr_ready),
        .wr_abort (wr_abort),
        .rd_open (rd_open), .rd_open_ready (rd_open_ready),
        .rd_id (rd_id), .rd_len_bytes (rd_len_bytes), .rd_close (rd_close),
        .rd_data (rd_data), .rd_valid (rd_valid), .rd_take (rd_take),
        .ddr_awaddr (awaddr), .ddr_awvalid (awvalid), .ddr_awready (awready),
        .ddr_wdata (wdata), .ddr_wvalid (wvalid), .ddr_wready (wready),
        .ddr_araddr (araddr), .ddr_arvalid (arvalid), .ddr_arready (arready),
        .ddr_rdata (rdata), .ddr_rvalid (rvalid), .ddr_rready (rready),
        .st_published (), .st_dropped (), .st_errors (), .st_last_bytes (),
        .st_read_words (), .st_dup_words (),
        .st_wr_beats (), .st_wr_words (), .st_wr_ptr (), .st_wr_state (),
        .st_rd_state (), .st_slot_st (), .st_slot_len0 (), .st_slot_len1 (),
        .st_rd_idx (), .st_rd_words (), .st_ar_valid (), .st_ar_hs (),
        .st_rv_cnt (), .st_rd_open_ok (), .st_rd_close_cnt (), .st_abort_cnt (),
        .st_free_valid (), .st_wr_active_out ()
    );

`ifdef USE_B8_BRIDGE
    p2_ddr_bridge_b8 u_bridge (
`else
    p2_ddr_bridge u_bridge (
`endif
        .clk_a1 (clk_a1), .rst_n (rst_n),
        .s_awaddr (awaddr), .s_awvalid (awvalid), .s_awready (awready),
        .s_wdata (wdata), .s_wvalid (wvalid), .s_wready (wready),
        .s_araddr (araddr), .s_arvalid (arvalid), .s_arready (arready),
        .s_rdata (rdata), .s_rvalid (rvalid), .s_rready (rready),
        .clk_ddr (clk_ddr), .ddr_rdy (ddr_rdy),
        .paxi_awaddr (paxi_awaddr), .paxi_awvalid (paxi_awvalid), .paxi_awready (paxi_awready),
        .paxi_wdata (paxi_wdata), .paxi_wstrb (paxi_wstrb),
        .paxi_wvalid (paxi_wvalid), .paxi_wlast (paxi_wlast), .paxi_wready (paxi_wready),
        .paxi_araddr (paxi_araddr), .paxi_arvalid (paxi_arvalid), .paxi_arready (paxi_arready),
        .paxi_rdata (paxi_rdata), .paxi_rlast (paxi_rlast),
        .paxi_rvalid (paxi_rvalid), .paxi_rready (paxi_rready)
    );

    p2_paxi_model #(.WORDS (DDR_WORDS), .AR_GAP (5), .R_GAP (4)) u_ddr (
        .clk (clk_ddr), .rst_n (rst_n), .rdy (ddr_rdy),
        .awaddr (paxi_awaddr), .awvalid (paxi_awvalid), .awready (paxi_awready),
        .wdata (paxi_wdata), .wstrb (paxi_wstrb),
        .wvalid (paxi_wvalid), .wlast (paxi_wlast), .wready (paxi_wready),
        .araddr (paxi_araddr), .arvalid (paxi_arvalid), .arready (paxi_arready),
        .rdata (paxi_rdata), .rlast (paxi_rlast), .rvalid (paxi_rvalid), .rready (paxi_rready),
        .n_ar_hs (n_ar_hs), .n_aw_hs (n_aw_hs), .n_whs (n_whs), .n_r_hs (n_r_hs)
    );

    // ---------------------------------------------------------------- pattern
    function [39:0] grp;
        input [31:0] n;
        input [31:0] w;
        input [31:0] k;
        begin
            grp = {n[7:0], w[15:0], k[7:0], 8'hA5};
        end
    endfunction

    function [255:0] exp_word;
        input [31:0] n;
        input [31:0] w;
        begin
            exp_word = {96'd0, grp(n, w, 3), grp(n, w, 2), grp(n, w, 1), grp(n, w, 0)};
        end
    endfunction

    integer errors = 0;
    integer words_checked = 0;
    integer beats_written = 0;

    task check_word;
        input [255:0] d;
        input integer n;
        input integer w;
        reg   [255:0] e;
        begin
            e = exp_word(n, w);
            if (d !== e) begin
                errors = errors + 1;
                if (errors < 8) $display("WORD_MISMATCH n=%0d w=%0d got=%h exp=%h", n, w, d, e);
            end
            words_checked = words_checked + 1;
        end
    endtask

    // ------------------------------------------------------- write streamer
    reg         stream_on  = 1'b0;
    reg [31:0]  beat_i     = 32'd0;
    reg [31:0]  beats_todo = 32'd0;
    reg [31:0]  frame_n    = 32'd0;

    always @(negedge clk_a1) begin
        if (!rst_n) begin
            wr_valid <= 1'b0; wr_last <= 1'b0;
        end else if (stream_on && (beat_i < beats_todo)) begin
            wr_valid <= 1'b1;
            wr_data  <= grp(frame_n, beat_i / 4, beat_i % 4);
            wr_last  <= (beat_i == (beats_todo - 32'd1));
        end else begin
            wr_valid <= 1'b0;
            wr_last  <= 1'b0;
        end
    end

    always @(posedge clk_a1) begin
        if (rst_n && wr_valid && wr_ready) begin
            beat_i        <= beat_i + 32'd1;
            beats_written <= beats_written + 1;
        end
    end

    task write_frame;
        input integer n;
        input integer nbeats;
        input integer abort_at;      // <0 = complete frame
        begin
            wr_id = n;
            while (!wr_begin_ready) @(negedge clk_a1);
            wr_begin = 1'b1;
            @(posedge clk_a1);
            @(negedge clk_a1);
            wr_begin = 1'b0;

            frame_n    = n;
            beats_todo = nbeats;
            beat_i     = 0;
            stream_on  = 1'b1;

            if (abort_at >= 0) begin
                while (beat_i < abort_at) @(negedge clk_a1);
                stream_on = 1'b0;
                repeat (4) @(negedge clk_a1);
                wr_abort = 1'b1;
                @(posedge clk_a1);
                @(negedge clk_a1);
                wr_abort = 1'b0;
            end else begin
                while (beat_i < beats_todo) @(negedge clk_a1);
                stream_on = 1'b0;
                repeat (4) @(negedge clk_a1);
            end
            repeat (8) @(negedge clk_a1);
            $display("WRITE_DONE n=%0d beats=%0d words=%0d pub=%0d drop=%0d abort=%0d",
                     n, beats_written, u_store.st_wr_words, u_store.st_published,
                     u_store.st_dropped, u_store.st_abort_cnt);
        end
    endtask

    // ------------------------------------------------------------- read frame
    task read_frame;
        input integer n;
        input integer nwords;
        integer i;
        begin
            while (!rd_open_ready) @(negedge clk_a1);
            rd_open = 1'b1;
            @(posedge clk_a1);
            @(negedge clk_a1);
            rd_open = 1'b0;

            for (i = 0; i < nwords; i = i + 1) begin
                @(negedge clk_a1);
                while (!rd_valid) @(negedge clk_a1);
                check_word(rd_data, n, i);
                rd_take  = 1'b1;
                rd_close = (i == (nwords - 1));
                @(posedge clk_a1);
                @(negedge clk_a1);
                rd_take  = 1'b0;
                rd_close = 1'b0;
            end
            repeat (8) @(negedge clk_a1);
            $display("READ_DONE n=%0d words=%0d checked=%0d ar_paxi=%0d ar_store=%0d dup=%0d",
                     n, u_store.st_read_words, words_checked, n_ar_hs,
                     u_store.st_ar_hs, u_store.st_dup_words);
        end
    endtask

    reg [255:0] case_name;
    reg [1023:0] out_path;
    integer cyc = 0;

    always @(posedge clk_a1) begin
        cyc = cyc + 1;
        if (cyc > 30000000) begin
            $display("TB_RAW_STORE_TIMEOUT cycles=%0d beat_i=%0d wr_valid=%d wr_ready=%d wr_begin_ready=%d wr_active=%d rd_valid=%d rd_state=%0d pub=%0d",
                     cyc, beat_i, wr_valid, wr_ready, wr_begin_ready,
                     u_store.wr_active, rd_valid, u_store.rd_state, u_store.st_published);
            $display("RESULT case=timeout pass=0 errors=%0d", errors);
            $finish;
        end
        if ((cyc % 2000000) == 0)
            $display("PROGRESS cyc=%0d beat_i=%0d words=%0d pub=%0d rv=%0d ar=%0d",
                     cyc, beat_i, u_store.st_wr_words, u_store.st_published,
                     u_store.st_rv_cnt, n_ar_hs);
    end

    task expect_eq;
        input [255:0] what;
        input integer got;
        input integer exp;
        begin
            if (got !== exp) begin
                errors = errors + 1;
                $display("CHECK_FAIL %0s got=%0d exp=%0d", what, got, exp);
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("CASE=%s", case_name)) case_name = "full2";

        rst_n = 1'b0;
        repeat (30) @(negedge clk_a1);
        rst_n = 1'b1;
        repeat (30) @(negedge clk_a1);

        if (case_name == "full2") begin
            write_frame(0, GROUPS, -1);
            write_frame(1, GROUPS, -1);
            expect_eq("pub_after_2", u_store.st_published, 2);
            expect_eq("err_after_wr", u_store.st_errors, 0);
            read_frame(0, RAW_WORDS);
            read_frame(1, RAW_WORDS);
            expect_eq("words_checked", words_checked, 2 * RAW_WORDS);
            expect_eq("dup_words", u_store.st_dup_words, 0);
            expect_eq("read_words", u_store.st_read_words, 2 * RAW_WORDS);
            expect_eq("ar_hs_store", u_store.st_ar_hs, 2 * RAW_WORDS);
            expect_eq("ar_hs_paxi", n_ar_hs, 2 * RAW_WORDS);
            expect_eq("ar_valid_store", u_store.st_ar_valid, 2 * RAW_WORDS);
            expect_eq("rd_close", u_store.st_rd_close_cnt, 2);
            expect_eq("rd_open_ok", u_store.st_rd_open_ok, 2);
            expect_eq("wr_beats", u_store.st_wr_beats, 2 * GROUPS);
            expect_eq("wr_words", u_store.st_wr_words, 2 * RAW_WORDS);
            expect_eq("slot_len0", u_store.st_slot_len0, EXP_BYTES);
            expect_eq("slot_len1", u_store.st_slot_len1, EXP_BYTES);
            expect_eq("abort_cnt", u_store.st_abort_cnt, 0);
            expect_eq("dropped", u_store.st_dropped, 0);
        end else if (case_name == "abort") begin
            write_frame(0, GROUPS, ABORT_BEATS);
            expect_eq("pub_after_abort", u_store.st_published, 0);
            expect_eq("abort_cnt", u_store.st_abort_cnt, 1);
            expect_eq("dropped", u_store.st_dropped, 1);
            expect_eq("slot0_free", u_store.st_slot_st[1:0], 0);
            write_frame(1, GROUPS, -1);
            expect_eq("pub_after_next", u_store.st_published, 1);
            read_frame(1, RAW_WORDS);
            expect_eq("words_checked", words_checked, RAW_WORDS);
            expect_eq("ar_hs_paxi", n_ar_hs, RAW_WORDS);
            expect_eq("dup_words", u_store.st_dup_words, 0);
            expect_eq("err", u_store.st_errors, 0);
        end else if (case_name == "nofree") begin
            write_frame(0, GROUPS, -1);
            write_frame(1, GROUPS, -1);
            expect_eq("pub", u_store.st_published, 2);
            wr_begin = 1'b1;
            wr_id    = 32'd2;
            repeat (200) begin
                @(negedge clk_a1);
                if (wr_begin_ready) begin
                    errors = errors + 1;
                    $display("NOFREE_BEGIN_ACCEPTED");
                end
            end
            wr_begin = 1'b0;
            // same for the data phase: 200 cycles of offered beats, none may
            // be accepted while both slots are READY / READING
            frame_n    = 2;
            beats_todo = 100;
            beat_i     = 0;
            stream_on  = 1'b1;
            repeat (200) begin
                @(negedge clk_a1);
                if (wr_ready) begin
                    errors = errors + 1;
                    $display("NOFREE_BEAT_ACCEPTED");
                end
            end
            stream_on = 1'b0;
            expect_eq("nofree_beats", beat_i, 0);
            expect_eq("pub_still2", u_store.st_published, 2);
            expect_eq("err_nofree", u_store.st_errors, 0);
            read_frame(0, RAW_WORDS);
            read_frame(1, RAW_WORDS);
            write_frame(2, GROUPS, -1);
            expect_eq("pub_after_release", u_store.st_published, 3);
            read_frame(2, RAW_WORDS);
            expect_eq("words_checked", words_checked, 3 * RAW_WORDS);
            expect_eq("ar_hs_paxi", n_ar_hs, 3 * RAW_WORDS);
        end else if (case_name == "rdy") begin
            write_frame(0, GROUPS, -1);
            expect_eq("pub", u_store.st_published, 1);
            rdy_en = 1'b1;
            read_frame(0, RAW_WORDS);
            rdy_en = 1'b0;
            expect_eq("words_checked", words_checked, RAW_WORDS);
            expect_eq("ar_hs_paxi", n_ar_hs, RAW_WORDS);
            expect_eq("ar_hs_store", u_store.st_ar_hs, RAW_WORDS);
            expect_eq("dup_words", u_store.st_dup_words, 0);
            expect_eq("read_words", u_store.st_read_words, RAW_WORDS);
            expect_eq("err", u_store.st_errors, 0);
        end else begin
            $display("TB_RAW_STORE_BAD_CASE %0s", case_name);
            errors = errors + 1;
        end

        repeat (20) @(negedge clk_a1);
        $display("RESULT case=%0s pass=%0d errors=%0d words=%0d beats=%0d ar_paxi=%0d ar_store=%0d pub=%0d drop=%0d abort=%0d dup=%0d cyc=%0d",
                 case_name, (errors == 0), errors, words_checked, beats_written,
                 n_ar_hs, u_store.st_ar_hs, u_store.st_published, u_store.st_dropped,
                 u_store.st_abort_cnt, u_store.st_dup_words, cyc);
        $finish;
    end
endmodule
