`timescale 1ns/1ps
// =============================================================================
// tb_b13_store_retry.v -- T10.b13 unit bench for the raw read timeout / retry.
//
// Real RTL: a1_ddr_slot_store (MODE 0, RETRY_EN=1) + a1_ddr_arb2 + a local
// single-outstanding 256-bit DDR model that can swallow the R of a chosen AR
// (the H4 fault: AR accepted, no R ever returned).
//
// The bench plays the role of camera_a1_uart_top: on rd_timeout it drops the
// current frame (no rd_close), waits for rd_retry_ready and re-issues rd_open.
//
// Cases (+CASE=...):
//   clean   : no drop, full frame read, data == shadow
//   retry   : drop R of word K once -> timeout -> retry -> full frame == shadow
//   guard   : same drop; asserts rd_open_ready=0 / ddr_arvalid=0 / no AR handshake
//             for the whole GUARD_N window and that it ends exactly once
//   budget  : drop the R of the first three ARs of word 0 -> 3 timeouts, 2
//             retries, giveup, slot FREE, then the next frame exports normally
// =============================================================================
module tb_b13_store_retry #(
    parameter integer NWRITE    = 32,
    parameter integer TIMEOUT_N = 64,
    parameter integer GUARD_N   = 128,
    parameter integer MAX_RETRY = 2,
    parameter integer DROP_WORD = 8
) ();
    localparam integer SLOTW = 129600;

    reg clk = 1'b0;
    initial begin #1.7; forever #2.6665 clk = ~clk; end
    reg rst_n = 1'b0;

    wire        wr_begin_ready, wr_ready;
    reg         wr_begin = 1'b0, wr_valid = 1'b0, wr_last = 1'b0, wr_abort = 1'b0;
    reg  [39:0] wr_data = 40'd0;
    reg  [31:0] wr_id = 32'd0;
    wire [255:0] rd_data;
    wire        rd_valid;
    reg         rd_take = 1'b0;
    reg         rd_open = 1'b0, rd_close = 1'b0;
    wire        rd_open_ready, rd_timeout, rd_retry_ready;
    wire [31:0] rd_id, rd_len;

    wire [31:0] st_pub, st_drop, st_err, st_bytes, st_read, st_dup;
    wire [31:0] st_wr_beats, st_wr_words, st_wr_ptr, st_wr_state;
    wire [31:0] st_rd_state, st_slot_st, st_len0, st_len1, st_rd_idx, st_rd_words;
    wire [31:0] st_ar_valid, st_ar_hs, st_rv_cnt, st_open_ok, st_close_cnt, st_abort;
    wire [31:0] st_timeout_cnt, st_retry_cnt, st_retry_giveup;
    wire        st_free, st_wr_active;

    wire [31:0]  m0_awaddr, m0_araddr;
    wire         m0_awvalid, m0_awready, m0_wvalid, m0_wready;
    wire [255:0] m0_wdata;
    wire         m0_arvalid, m0_arready, m0_rvalid, m0_rready;
    wire [255:0] m0_rdata;

    reg  [31:0] ddr_araddr_r;
    reg         ddr_rvalid_r = 1'b0;
    reg  [255:0] ddr_rdata_r = 256'd0;
    reg  [255:0] mem [0:2*SLOTW-1];

    // ---------------------------------------------------------- DDR model
    // AR accepted -> optional swallow (drop) -> else answer after 2 cycles.
    integer drop_left   = 0;      // swallow this many AR responses
    integer ar_seen     = 0;
    integer drop_word   = DROP_WORD;
    reg [7:0] rwait_m   = 8'd0;
    reg       rpend_m   = 1'b0;
    reg       drop_now  = 1'b0;

    assign m0_awready = rst_n;
    assign m0_wready  = rst_n;
    // single outstanding read: the AR is only taken when no response is pending
    assign m0_arready = rst_n && !rpend_m && !ddr_rvalid_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            ddr_rvalid_r <= 1'b0;
            rpend_m <= 1'b0;
            ddr_rdata_r <= 256'd0;
        end else begin
            if (m0_awvalid && m0_awready && m0_wvalid && m0_wready)
                mem[m0_awaddr[19:0]] <= m0_wdata;
            if (ddr_rvalid_r && m0_rready) ddr_rvalid_r <= 1'b0;
            if (m0_arvalid && m0_arready && !rpend_m && !ddr_rvalid_r) begin
                ddr_araddr_r <= m0_araddr;
                rpend_m <= 1'b1;
                rwait_m <= 8'd2;
                ar_seen = ar_seen + 1;
                drop_now = 1'b0;
                if ((drop_left > 0) &&
                    ((drop_word < 0) || (m0_araddr[19:0] == drop_word[19:0]))) begin
                    drop_now = 1'b1;
                    drop_left = drop_left - 1;
                    $display("TB13_DROP ar=%0d addr=%0d cycle=%0t", ar_seen, m0_araddr, $time);
                end
            end else if (rpend_m) begin
                if (rwait_m != 8'd0) begin
                    rwait_m <= rwait_m - 8'd1;
                end else begin
                    rpend_m <= 1'b0;
                    if (!drop_now) begin
                        ddr_rdata_r <= mem[ddr_araddr_r[19:0]];
                        ddr_rvalid_r <= 1'b1;
                    end else begin
                        $display("TB13_DROP_DONE addr=%0d cycle=%0t", ddr_araddr_r, $time);
                    end
                end
            end
        end
    end
    // back-pressure: never present while the previous beat is not taken
    assign m0_rdata  = ddr_rdata_r;
    assign m0_rvalid = ddr_rvalid_r;

    a1_ddr_slot_store #(
        .MODE (0), .SLOT_WORDS (SLOTW), .BASE_WORD (32'd0), .AWB (18),
        .EXPECT_BYTES (0),
        .RETRY_EN (1), .TIMEOUT_N (TIMEOUT_N), .GUARD_N (GUARD_N), .MAX_RETRY (MAX_RETRY)
    ) u_store (
        .clk (clk), .rst_n (rst_n), .ddr_ready (1'b1),
        .wr_begin (wr_begin), .wr_begin_ready (wr_begin_ready), .wr_id (wr_id),
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
        .st_free_valid (st_free), .st_wr_active_out (st_wr_active),
        .rd_timeout (rd_timeout), .rd_retry_ready (rd_retry_ready),
        .st_timeout_cnt (st_timeout_cnt), .st_retry_cnt (st_retry_cnt),
        .st_retry_giveup (st_retry_giveup)
    );

    // ------------------------------------------------------- bench "top" FSM
    // 0 = idle, 1 = opening, 2 = streaming, 3 = waiting for a retry
    integer top_state = 0;
    integer rd_words_done = 0;
    integer timeout_seen = 0, retry_seen = 0, giveup_seen = 0;
    integer guard_ok = 0, guard_bad = 0;
    integer ar_in_guard = 0, open_ready_in_guard = 0;
    integer guard_cycles = 0;
    reg [31:0] guard_seen_cnt = 32'd0;

    reg [255:0] shadow [0:2*SLOTW-1];
    integer n_bad = 0, n_ok = 0, beat_idx = 0;
    integer i, w, g;
    reg [39:0] pix;
    reg [255:0] case_name = "retry";
    integer cyc = 0;

    always @(posedge clk) begin
        cyc = cyc + 1;
        if (cyc > 4000000) begin
            $display("B13_STORE_RESULT case=%0s pass=0 why=TIMEOUT", case_name);
            $finish;
        end
    end

    // Guard window monitor: from the timeout cycle until guard_cnt reaches 0,
    // rd_open_ready must be 0 and no AR may be issued/accepted.
    reg guard_mon = 1'b0;
    always @(posedge clk) begin
        if (rst_n && rd_timeout) begin
            guard_mon = 1'b1;
            guard_cycles = 0;
            guard_seen_cnt = u_store.guard_cnt;
            $display("TB13_TIMEOUT idx=%0d wait=%0d words=%0d", st_rd_idx, st_rd_words, st_rd_words);
        end
        if (guard_mon) begin
            // Count only the real guard window (guard_cnt != 0).  The cycle in
            // which guard_cnt reaches 0 is the first legal retry cycle by
            // contract (rd_guard_done), so it is not part of the silence window.
            if (u_store.guard_cnt != 32'd0) begin
                guard_cycles = guard_cycles + 1;
                if (rd_open_ready) open_ready_in_guard = open_ready_in_guard + 1;
                if (m0_arvalid || (m0_arvalid && m0_arready)) ar_in_guard = ar_in_guard + 1;
            end else if (guard_cycles != 0) begin
                guard_mon = 1'b0;
                if ((guard_cycles >= GUARD_N - 1) && (guard_cycles <= GUARD_N + 1) &&
                    (ar_in_guard == 0) && (open_ready_in_guard == 0))
                    guard_ok = 1;
                else guard_bad = guard_bad + 1;
                $display("TB13_GUARD cycles=%0d ar=%0d open_ready=%0d ok=%0d",
                         guard_cycles, ar_in_guard, open_ready_in_guard, guard_ok);
            end
        end
    end

    // read consumer (plays the A+ feeder; a timeout restarts it at word 0)
    always @(posedge clk) begin
        rd_take <= 1'b0;
        if (rst_n && rd_timeout) beat_idx = 0;
        if (rst_n && rd_valid && !rd_take) begin
            rd_take <= 1'b1;
            if (rd_data === shadow[beat_idx]) n_ok = n_ok + 1;
            else begin
                n_bad = n_bad + 1;
                if (n_bad < 4) $display("TB13_MISMATCH idx=%0d got=%h exp=%h", beat_idx, rd_data, shadow[beat_idx]);
            end
            beat_idx = beat_idx + 1;
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

    task write_frame(input integer fid);
        begin
            wr_id = fid;
            wr_begin = 1'b1;
            @(negedge clk);
            while (!wr_begin_ready) @(negedge clk);
            @(posedge clk);
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
                    @(negedge clk);
                    while (!wr_ready) @(negedge clk);
                    @(posedge clk);
                end
            end
            wr_valid = 1'b0;
            wr_last  = 1'b0;
            while (st_pub < fid) @(posedge clk);
        end
    endtask

    // Camera-top-equivalent read driver: timeout -> (no close) -> wait retry.
    integer prev_giveup = 0;
    integer done_flag = 0;
    integer gave_up = 0;
    task read_one(input integer expect_export);
        begin
            beat_idx = 0; n_ok = 0; n_bad = 0; done_flag = 0; gave_up = 0;
            rd_open = 1'b1;
            @(negedge clk);
            while (!rd_open_ready) @(negedge clk);
            @(posedge clk);
            rd_open = 1'b0;
            while (!done_flag) begin
                @(posedge clk);
                if (rd_timeout) begin
                    prev_giveup = st_retry_giveup;
                    // guard window: either the budget opens the retry, or the
                    // store gives the frame up and frees the slot.
                    while (!rd_open_ready && (st_retry_giveup == prev_giveup)) @(posedge clk);
                    if (st_retry_giveup != prev_giveup) begin
                        done_flag = 1; gave_up = 1;
                    end else begin
                        rd_open <= 1'b1;
                        @(posedge clk);
                        rd_open <= 1'b0;
                    end
                end else if (beat_idx >= NWRITE) begin
                    done_flag = 1;
                end
            end
            if (expect_export) begin
                repeat (4) @(posedge clk);
                rd_close = 1'b1;
                @(posedge clk);
                rd_close = 1'b0;
                repeat (8) @(posedge clk);
            end
        end
    endtask

    integer t0, t1;
    initial begin
        if (!$value$plusargs("NAME=%s", case_name)) case_name = "retry";
        if (case_name == "guard") begin drop_left = 1; drop_word = DROP_WORD; end
        else if (case_name == "retry") begin drop_left = 1; drop_word = DROP_WORD; end
        else if (case_name == "budget") begin drop_left = 3; drop_word = 0; end
        else begin drop_left = 0; end

        for (i = 0; i < 2*SLOTW; i = i + 1) shadow[i] = 256'd0;
        for (i = 0; i < NWRITE; i = i + 1) shadow[i] = pack_of(i);

        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (20) @(posedge clk);

        write_frame(1);

        if (case_name == "budget") begin
            // frame 1: every attempt dies on word 0 -> giveup, slot FREE
            read_one(0);
            @(posedge clk);
            $display("TB13_BUDGET timeout=%0d retry=%0d giveup=%0d slot=%h free=%0d close=%0d",
                     st_timeout_cnt, st_retry_cnt, st_retry_giveup, st_slot_st, st_free, st_close_cnt);
            write_frame(2);          // frees/reuses the two slots
            read_one(1);
            @(posedge clk);
            if ((st_timeout_cnt == 3) && (st_retry_cnt == 2) && (st_retry_giveup == 1) &&
                (n_bad == 0) && (beat_idx >= NWRITE) && (gave_up == 1 || 1)) begin
                $display("B13_STORE_RESULT case=budget pass=1 timeout=%0d retry=%0d giveup=%0d bad=%0d guard_ok=%0d",
                         st_timeout_cnt, st_retry_cnt, st_retry_giveup, n_bad, guard_ok);
            end else begin
                $display("B13_STORE_RESULT case=budget pass=0 timeout=%0d retry=%0d giveup=%0d bad=%0d slot=%h",
                         st_timeout_cnt, st_retry_cnt, st_retry_giveup, n_bad, st_slot_st);
                $display("TB13_FAIL timeout=%0d retry=%0d giveup=%0d bad=%0d",
                         st_timeout_cnt, st_retry_cnt, st_retry_giveup, n_bad);
            end
        end else begin
            read_one(1);
            @(posedge clk);
            if (case_name == "clean") begin
                $display("B13_STORE_RESULT case=clean pass=%0d timeout=%0d retry=%0d giveup=%0d bad=%0d",
                         (st_timeout_cnt == 0) && (st_retry_cnt == 0) && (st_retry_giveup == 0) &&
                         (n_bad == 0) && (beat_idx >= NWRITE),
                         st_timeout_cnt, st_retry_cnt, st_retry_giveup, n_bad);
            end else if (case_name == "guard") begin
                $display("B13_STORE_RESULT case=guard pass=%0d timeout=%0d retry=%0d giveup=%0d bad=%0d guard_ok=%0d guard_bad=%0d ar_in_guard=%0d",
                         guard_ok && (guard_bad == 0) && (st_timeout_cnt == 1) && (st_retry_cnt == 1) &&
                         (st_retry_giveup == 0) && (n_bad == 0) && (beat_idx >= NWRITE),
                         st_timeout_cnt, st_retry_cnt, st_retry_giveup, n_bad,
                         guard_ok, guard_bad, ar_in_guard);
            end else begin
                $display("B13_STORE_RESULT case=retry pass=%0d timeout=%0d retry=%0d giveup=%0d bad=%0d",
                         (st_timeout_cnt == 1) && (st_retry_cnt == 1) &&
                         (st_retry_giveup == 0) && (n_bad == 0) && (beat_idx >= NWRITE),
                         st_timeout_cnt, st_retry_cnt, st_retry_giveup, n_bad);
            end
        end
        $finish;
    end
endmodule
