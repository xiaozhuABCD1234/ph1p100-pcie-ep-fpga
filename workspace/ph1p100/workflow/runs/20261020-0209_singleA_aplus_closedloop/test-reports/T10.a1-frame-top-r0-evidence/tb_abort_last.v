// Independent tester TB: hold the final output word, then abort.
// Goal: check guide §4 "abort ... eop 不得置位" in the last-word-pending corner.
// Test-only; no candidate source is modified. W=20,H=5.
`timescale 1ns / 1ps

module tb_abort_last;
    localparam integer W = 20;
    localparam integer H = 5;
    localparam integer NGRP = (W * 5 / 4) * H / 5; // 25

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg         rst_n = 1'b0;
    reg  [39:0] in_pix = 40'd0;
    reg         in_valid = 1'b0;
    wire        in_ready;
    reg         in_sof = 1'b0;
    reg         prep_en = 1'b1;
    reg         pred_en = 1'b1;
    reg         abort = 1'b0;

    wire [31:0] out_data;
    wire        out_valid;
    reg         out_ready = 1'b1;
    wire [3:0]  out_keep;
    wire        out_last;
    wire        frame_commit;
    wire        frame_abort;
    wire [31:0] st_raw_len, st_xform_len, st_stream_len;
    wire [31:0] st_raw_crc, st_xform_crc, st_stream_crc;
    wire [31:0] st_blocks, st_stall_cycles;
    wire        st_busy;

    a1_frame_top #(.W(W), .H(H)) dut (
        .clk(clk), .rst_n(rst_n),
        .in_pix(in_pix), .in_valid(in_valid), .in_ready(in_ready), .in_sof(in_sof),
        .prep_en(prep_en), .pred_en(pred_en), .abort(abort),
        .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready),
        .out_keep(out_keep), .out_last(out_last),
        .frame_commit(frame_commit), .frame_abort(frame_abort),
        .st_raw_len(st_raw_len), .st_xform_len(st_xform_len), .st_stream_len(st_stream_len),
        .st_raw_crc(st_raw_crc), .st_xform_crc(st_xform_crc), .st_stream_crc(st_stream_crc),
        .st_blocks(st_blocks), .st_stall_cycles(st_stall_cycles), .st_busy(st_busy)
    );

    integer g;
    integer commit_seen = 0;
    integer saw_pending_last = 0;
    integer last_while_pending = 0;
    integer last_after_release = 0;
    integer commit_after_release = 0;
    reg [39:0] p;

    // Stop consuming exactly when the core presents its final byte, so the
    // final output word remains pending (out_valid && out_last, !out_ready).
    always @(negedge clk) begin
        if (!out_valid && dut.core_out_valid && dut.core_out_last)
            out_ready <= 1'b0;
    end

    always @(posedge clk) if (frame_commit) commit_seen <= commit_seen + 1;

    initial begin
        repeat (6) @(posedge clk);
        rst_n <= 1'b1;
        repeat (6) @(posedge clk);

        for (g = 0; g < NGRP; g = g + 1) begin
            @(negedge clk);
            p[7:0]   = g + 1;
            p[15:8]  = g + 2;
            p[23:16] = g + 3;
            p[31:24] = g + 4;
            p[39:32] = g + 5;
            in_pix   <= p;
            in_sof   <= (g == 0);
            in_valid <= 1'b1;
            #1;
            while (!in_ready) begin
                @(negedge clk);
                #1;
            end
            @(posedge clk);
            @(negedge clk);
            in_valid <= 1'b0;
            in_sof   <= 1'b0;
        end

        while (!(out_valid && out_last && !out_ready)) @(negedge clk);
        saw_pending_last = 1;
        last_while_pending = out_last;
        $display("PENDING_LAST valid=%b last=%b keep=%h slen=%0d stream_len=%0d",
                 out_valid, out_last, out_keep, dut.slen_r, st_stream_len);

        @(negedge clk);
        abort <= 1'b1;
        repeat (4) @(negedge clk);
        abort <= 1'b0;
        @(negedge clk);
        last_after_release = out_last;
        $display("AFTER_ABORT valid=%b last=%b frame_abort=%b commit=%b",
                 out_valid, out_last, frame_abort, frame_commit);

        out_ready <= 1'b1;
        repeat (4) @(negedge clk);
        commit_after_release = commit_seen;
        $display("RESULT saw_pending_last=%0d last_while_pending=%0d last_after_release=%0d commit_after_release=%0d frame_abort=%b",
                 saw_pending_last, last_while_pending, last_after_release,
                 commit_after_release, frame_abort);
        if (saw_pending_last && (last_while_pending || last_after_release) && commit_after_release == 0)
            $display("ABORT_LAST_EOP_BUG reproduced");
        else if (saw_pending_last && !last_while_pending && commit_after_release == 0)
            $display("ABORT_LAST_EOP_CLEAN");
        else
            $display("ABORT_LAST_TEST_INCONCLUSIVE");
        $finish;
    end

    initial begin
        #200000000;
        $display("GLOBAL_TIMEOUT");
        $finish;
    end
endmodule
