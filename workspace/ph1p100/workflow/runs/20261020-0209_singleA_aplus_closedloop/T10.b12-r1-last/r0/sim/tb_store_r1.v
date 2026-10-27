`timescale 1ns/1ps
// =============================================================================
// tb_store_r1.v -- T10.b12-r1-last directed cases for a1_ddr_slot_store (MODE 0)
//
//   t3 : same-cycle wr_last + wr_abort   -> abort wins: no publish, slot FREE,
//        st_dropped/st_abort_cnt +1, next good frame publishes and reads back
//   t4 : same-cycle wr_begin + wr_abort  -> old slot FREE, new frame begins and
//        publishes (other slot FREE); when no slot is FREE the begin is refused,
//        the abort still frees the slot and the next begin succeeds
//   t5 : reset in the middle of a write  -> wr_active=0, both slots FREE,
//        counters cleared, no ghost READY, next good frame publishes
//   t6 : slot0 READY + slot1 WRITE loses the LAST -> only slot1 is freed,
//        slot0 still reads back byte-exact, next frame uses the freed slot
//
// The DDR side is a direct 256-bit single-clock word memory with fully
// controlled AW/W ready, so every same-cycle case above is exact.  The data
// pattern is unique per (frame, word, group), so a dropped, duplicated or
// shifted word is a data mismatch, not a counter difference.
// =============================================================================
module tb_store_r1;
    parameter integer GROUPS    = 40;       // beats per full test frame
    parameter integer RAW_WORDS = 10;       // GROUPS/4
    parameter integer EXP_BYTES = GROUPS * 5;
    localparam integer DDR_WORDS = 64;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #2.6665 clk = ~clk;

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

    wire [31:0] awaddr, araddr;
    wire        awvalid, awready, wvalid, wready, arvalid, arready;
    wire [255:0] wdata, rdata;
    wire        rvalid, rready;

    reg  [31:0] st_pub, st_drop, st_err, st_bytes, st_read, st_dup;
    reg  [31:0] st_beats, st_words, st_ar_v, st_ar_hs, st_rv, st_open_ok, st_close, st_abort_n;
    wire        st_free, st_wr_act;

    a1_ddr_slot_store #(
        .MODE (0), .SLOT_WORDS (RAW_WORDS), .BASE_WORD (32'd0), .AWB (18),
        .EXPECT_BYTES (EXP_BYTES)
    ) u_store (
        .clk (clk), .rst_n (rst_n), .ddr_ready (1'b1),
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
        .st_published (st_pub), .st_dropped (st_drop),
        .st_errors (st_err), .st_last_bytes (st_bytes),
        .st_read_words (st_read), .st_dup_words (st_dup),
        .st_wr_beats (st_beats), .st_wr_words (st_words), .st_wr_ptr (),
        .st_wr_state (), .st_rd_state (), .st_slot_st (), .st_slot_len0 (),
        .st_slot_len1 (), .st_rd_idx (), .st_rd_words (), .st_ar_valid (st_ar_v),
        .st_ar_hs (st_ar_hs), .st_rv_cnt (st_rv), .st_rd_open_ok (st_open_ok),
        .st_rd_close_cnt (st_close), .st_abort_cnt (st_abort_n),
        .st_free_valid (st_free), .st_wr_active_out (st_wr_act)
    );

    // ------------------------------------------------ direct 256-bit DDR model
    reg [255:0] mem [0:DDR_WORDS-1];
    reg         ddr_w_ready = 1'b1;      // fully controlled AW/W ready
    integer     ddr_writes = 0;
    assign awready = ddr_w_ready;
    assign wready  = ddr_w_ready;
    always @(posedge clk) begin
        if (rst_n && awvalid && awready && wvalid && wready) begin
            mem[awaddr[5:0]] <= wdata;
            ddr_writes <= ddr_writes + 1;
        end
    end
    assign arready = 1'b1;
    reg        rvalid_r = 1'b0;
    reg [255:0] rdata_r = 256'd0;
    reg [1:0]  rpipe = 2'd0;
    assign rvalid = rvalid_r;
    assign rdata  = rdata_r;
    always @(posedge clk) begin
        if (!rst_n) begin
            rvalid_r <= 1'b0; rpipe <= 2'd0; rdata_r <= 256'd0;
        end else begin
            rvalid_r <= 1'b0;
            if (arvalid && arready) begin
                rdata_r <= mem[araddr[5:0]];
                rpipe   <= 2'd2;
            end else if (rpipe != 2'd0) begin
                rpipe <= rpipe - 2'd1;
            end
            if (rpipe == 2'd1) rvalid_r <= 1'b1;
        end
    end

    // ---------------------------------------------------------------- pattern
    function [39:0] grp;
        input [31:0] n; input [31:0] w; input [31:0] k;
        begin grp = {n[7:0], w[15:0], k[7:0], 8'hA5}; end
    endfunction
    function [255:0] exp_word;
        input [31:0] n; input [31:0] w;
        begin
            exp_word = {96'd0, grp(n,w,3), grp(n,w,2), grp(n,w,1), grp(n,w,0)};
        end
    endfunction

    integer errors = 0;
    integer words_checked = 0;
    task expect_eq;
        input [255:0] what; input integer got; input integer exp;
        begin
            if (got !== exp) begin
                errors = errors + 1;
                $display("CHECK_FAIL %0s got=%0d exp=%0d", what, got, exp);
            end
        end
    endtask

    // ------------------------------------------------------------- write/read
    task begin_frame;
        input integer id;
        begin
            while (!wr_begin_ready) @(negedge clk);
            wr_id = id; wr_begin = 1'b1;
            @(posedge clk);
            @(negedge clk);
            wr_begin = 1'b0;
            repeat (2) @(negedge clk);
        end
    endtask

    // one beat, held until the store takes it (never used with wr_abort)
    task beat;
        input integer fid; input integer b;
        begin
            @(negedge clk);
            wr_data = grp(fid, b/4, b%4);
            wr_last = (b == (GROUPS-1));
            wr_valid = 1'b1;
            @(posedge clk);
            while (!wr_ready) begin @(negedge clk); @(posedge clk); end
            @(negedge clk);
            wr_valid = 1'b0; wr_last = 1'b0;
        end
    endtask

    task write_frame;
        input integer fid;
        integer b;
        begin
            begin_frame(fid);
            for (b = 0; b < GROUPS; b = b + 1) beat(fid, b);
            repeat (4) @(negedge clk);
            $display("WRITE_DONE n=%0d words=%0d pub=%0d drop=%0d abort=%0d err=%0d",
                     fid, st_words, st_pub, st_drop, st_abort_n, st_err);
        end
    endtask

    task read_frame;
        input integer fid; input integer nwords;
        integer i;
        begin
            while (!rd_open_ready) @(negedge clk);
            rd_open = 1'b1;
            @(posedge clk);
            @(negedge clk);
            rd_open = 1'b0;
            for (i = 0; i < nwords; i = i + 1) begin
                @(negedge clk);
                while (!rd_valid) @(negedge clk);
                if (rd_data !== exp_word(fid, i)) begin
                    errors = errors + 1;
                    if (errors < 10)
                        $display("WORD_MISMATCH n=%0d w=%0d got=%h exp=%h",
                                 fid, i, rd_data, exp_word(fid, i));
                end
                words_checked = words_checked + 1;
                rd_take  = 1'b1;
                rd_close = (i == (nwords-1));
                @(posedge clk);
                @(negedge clk);
                rd_take = 1'b0; rd_close = 1'b0;
            end
            repeat (6) @(negedge clk);
            $display("READ_DONE n=%0d checked=%0d ar_store=%0d dup=%0d close=%0d",
                     fid, words_checked, st_ar_hs, st_dup, st_close);
        end
    endtask

    // same-cycle LAST + ABORT: wr_ready must stay 0, abort must free the slot
    task last_abort;
        input integer fid; input integer b;
        integer writes_before;
        begin
            writes_before = ddr_writes;
            @(negedge clk);
            wr_data = grp(fid, b/4, b%4);
            wr_last = 1'b1; wr_valid = 1'b1; wr_abort = 1'b1;
            @(posedge clk);
            if (wr_ready !== 1'b0) begin
                errors = errors + 1;
                $display("CHECK_FAIL abort_cycle_ready got=%b exp=0", wr_ready);
            end
            @(negedge clk);
            wr_last = 1'b0; wr_valid = 1'b0; wr_abort = 1'b0;
            repeat (3) @(negedge clk);
            expect_eq("abort_no_ddr_write", ddr_writes, writes_before);
        end
    endtask

    // same-cycle BEGIN + ABORT
    task begin_abort;
        input integer id;
        begin
            @(negedge clk);
            wr_id = id; wr_begin = 1'b1; wr_abort = 1'b1;
            @(posedge clk);
            @(negedge clk);
            wr_begin = 1'b0; wr_abort = 1'b0;
            repeat (3) @(negedge clk);
        end
    endtask

    reg [255:0] case_name;
    initial begin
        if (!$value$plusargs("CASE=%s", case_name)) case_name = "t3";
        repeat (20) @(negedge clk);
        rst_n = 1'b1;
        repeat (20) @(negedge clk);

        if (case_name == "t3") begin
            begin_frame(0);
            begin : pre3
                integer k;
                for (k = 0; k < 6; k = k + 1) beat(0, k);
            end
            // 6 beats accepted -> wcnt=2, so the abort beat would have flushed
            last_abort(0, 6);
            expect_eq("t3_pub", st_pub, 0);
            expect_eq("t3_drop", st_drop, 1);
            expect_eq("t3_abort", st_abort_n, 1);
            expect_eq("t3_wr_active", st_wr_act, 0);
            expect_eq("t3_slot0", u_store.slot_st[0], 0);
            expect_eq("t3_slot1", u_store.slot_st[1], 0);
            write_frame(1);
            expect_eq("t3_pub_after", st_pub, 1);
            expect_eq("t3_err", st_err, 0);
            read_frame(1, RAW_WORDS);
            expect_eq("t3_words", words_checked, RAW_WORDS);
            expect_eq("t3_dup", st_dup, 0);
            expect_eq("t3_slot0_after", u_store.slot_st[0], 0);
        end else if (case_name == "t4") begin
            // ---- sub A: begin + abort in the same cycle, other slot FREE ----
            begin_frame(0);
            begin : pre4
                integer k;
                for (k = 0; k < 6; k = k + 1) beat(0, k);
            end
            @(negedge clk);
            wr_id = 32'd1; wr_begin = 1'b1; wr_abort = 1'b1;
            #1;
            if (wr_begin_ready !== 1'b1) begin
                errors = errors + 1;
                $display("CHECK_FAIL t4_begin_ready_with_free got=%b exp=1", wr_begin_ready);
            end
            @(posedge clk);
            @(negedge clk);
            wr_begin = 1'b0; wr_abort = 1'b0;
            repeat (3) @(negedge clk);
            expect_eq("t4a_pub", st_pub, 0);
            expect_eq("t4a_drop", st_drop, 1);
            expect_eq("t4a_abort", st_abort_n, 1);
            expect_eq("t4a_slot_old", u_store.slot_st[0], 0);
            expect_eq("t4a_slot_new", u_store.slot_st[1], 1);
            expect_eq("t4a_wr_active", st_wr_act, 1);
            expect_eq("t4a_wr_slot", u_store.wr_slot, 1);
            // finish the new frame in the new slot
            repeat (0) @(negedge clk);
            begin : fin4
                integer b;
                for (b = 0; b < GROUPS; b = b + 1) beat(1, b);
            end
            repeat (4) @(negedge clk);
            expect_eq("t4a_pub1", st_pub, 1);
            expect_eq("t4a_slot_new_ready", u_store.slot_st[1], 2);
            read_frame(1, RAW_WORDS);
            expect_eq("t4a_words", words_checked, RAW_WORDS);
            expect_eq("t4a_dup", st_dup, 0);
            // ---- sub B: both slots busy -> begin refused, abort frees the old
            write_frame(2);                       // slot0
            expect_eq("t4b_pub2", st_pub, 2);
            begin_frame(3);                       // slot1
            begin : pre4b
                integer k;
                for (k = 0; k < 6; k = k + 1) beat(3, k);
            end
            @(negedge clk);
            wr_id = 32'd4; wr_begin = 1'b1; wr_abort = 1'b1;
            #1;
            if (wr_begin_ready !== 1'b0) begin
                errors = errors + 1;
                $display("CHECK_FAIL t4b_begin_ready_no_free got=%b exp=0", wr_begin_ready);
            end
            @(posedge clk);
            @(negedge clk);
            wr_begin = 1'b0; wr_abort = 1'b0;
            repeat (3) @(negedge clk);
            expect_eq("t4b_pub_still", st_pub, 2);
            expect_eq("t4b_slot1_free", u_store.slot_st[1], 0);
            expect_eq("t4b_wr_active", st_wr_act, 0);
            expect_eq("t4b_drop", st_drop, 2);
            expect_eq("t4b_abort", st_abort_n, 2);
            // no two WRITE slots at any point is checked by the monitor below
            write_frame(4);                       // slot1 again
            expect_eq("t4b_pub3", st_pub, 3);
            read_frame(2, RAW_WORDS);
            read_frame(4, RAW_WORDS);
            expect_eq("t4b_words", words_checked, 3 * RAW_WORDS);
        end else if (case_name == "t5") begin
            begin_frame(0);
            begin : pre5
                integer k;
                for (k = 0; k < 6; k = k + 1) beat(0, k);
            end
            @(negedge clk);
            rst_n = 1'b0;
            repeat (5) @(negedge clk);
            rst_n = 1'b1;
            repeat (5) @(negedge clk);
            expect_eq("t5_wr_active", st_wr_act, 0);
            expect_eq("t5_slot0", u_store.slot_st[0], 0);
            expect_eq("t5_slot1", u_store.slot_st[1], 0);
            expect_eq("t5_pub", st_pub, 0);
            expect_eq("t5_drop", st_drop, 0);
            expect_eq("t5_abort", st_abort_n, 0);
            expect_eq("t5_free", st_free, 1);
            expect_eq("t5_open_ready", rd_open_ready, 0);   // no ghost READY
            expect_eq("t5_nbytes", u_store.nbytes, 0);
            expect_eq("t5_begin_ready", wr_begin_ready, 1);
            write_frame(1);
            expect_eq("t5_pub1", st_pub, 1);
            expect_eq("t5_err", st_err, 0);
            read_frame(1, RAW_WORDS);
            expect_eq("t5_words", words_checked, RAW_WORDS);
            expect_eq("t5_dup", st_dup, 0);
        end else if (case_name == "t6") begin
            write_frame(0);                       // slot0 READY
            expect_eq("t6_pub1", st_pub, 1);
            expect_eq("t6_slot0_ready", u_store.slot_st[0], 2);
            begin_frame(1);                       // slot1 WRITE
            begin : pre6
                integer k;
                for (k = 0; k < 6; k = k + 1) beat(1, k);
            end
            // lost LAST on the WRITE slot: abort only frees slot1
            @(negedge clk);
            wr_abort = 1'b1;
            @(posedge clk);
            @(negedge clk);
            wr_abort = 1'b0;
            repeat (3) @(negedge clk);
            expect_eq("t6_slot0_still_ready", u_store.slot_st[0], 2);
            expect_eq("t6_slot1_free", u_store.slot_st[1], 0);
            expect_eq("t6_pub_still", st_pub, 1);
            expect_eq("t6_abort", st_abort_n, 1);
            expect_eq("t6_drop", st_drop, 1);
            // reader is untouched: slot0 reads back byte-exact
            read_frame(0, RAW_WORDS);
            expect_eq("t6_words", words_checked, RAW_WORDS);
            expect_eq("t6_dup", st_dup, 0);
            expect_eq("t6_close", st_close, 1);
            // the freed slot is reused by the next good frame
            write_frame(2);
            expect_eq("t6_pub2", st_pub, 2);
            read_frame(2, RAW_WORDS);
            expect_eq("t6_words2", words_checked, 2 * RAW_WORDS);
            expect_eq("t6_free_end", st_free, 1);
        end else begin
            $display("TB_STORE_R1_BAD_CASE %0s", case_name);
            errors = errors + 1;
        end

        repeat (10) @(negedge clk);
        $display("RESULT case=%0s pass=%0d errors=%0d words=%0d pub=%0d drop=%0d abort=%0d dup=%0d slot0=%0d slot1=%0d wr_active=%0d cyc=%0t",
                 case_name, (errors == 0), errors, words_checked, st_pub, st_drop,
                 st_abort_n, st_dup, u_store.slot_st[0], u_store.slot_st[1], st_wr_act, $time);
        $finish;
    end

    // invariant monitor: never two WRITE slots, never READY+READY on one slot
    always @(posedge clk) begin
        if (rst_n) begin
            if ((u_store.slot_st[0] == 2'd1) && (u_store.slot_st[1] == 2'd1)) begin
                errors = errors + 1;
                $display("CHECK_FAIL two_write_slots slot0=%0d slot1=%0d", u_store.slot_st[0], u_store.slot_st[1]);
            end
            if (u_store.wr_active && (u_store.slot_st[u_store.wr_slot] != 2'd1)) begin
                errors = errors + 1;
                $display("CHECK_FAIL wr_active_orphan wr_slot=%0d st=%0d", u_store.wr_slot, u_store.slot_st[u_store.wr_slot]);
            end
        end
    end
endmodule
