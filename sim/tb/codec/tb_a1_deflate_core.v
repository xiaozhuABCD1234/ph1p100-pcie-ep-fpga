// =============================================================================
// tb_a1_deflate_core.v -- P2 module TB for the A+ v1 DEFLATE core
//
// Reads a hex byte image (one byte per line) + a word meta image
// (meta[0]=nblocks, meta[1..n]=block byte lengths), streams it through the
// DUT, writes the DUT byte stream as hex, and records cycle/stat counters.
//
// Plusargs:
//   +IN=<hex> +META=<hex> +OUT=<hex> +STAT=<txt>
//   +BP=0|1      random output backpressure
//   +GAP=0|1     random input-valid gaps
//   +ABORT_AT=<n>  pulse abort after n accepted bytes, then stop
//   +RST_AT=<n>    pulse synchronous reset after n accepted bytes, then stop
//   +TIMEOUT=<n>   cycle timeout (default 5000000)
// =============================================================================
`timescale 1ns / 1ps

module tb_a1_deflate_core;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg        rst_n = 1'b0;
    reg        abort = 1'b0;
    reg        in_valid = 1'b0;
    wire       in_ready;
    reg [7:0]  in_data = 8'd0;
    reg        in_sop = 1'b0;
    reg        in_blk_end = 1'b0;
    reg        in_stream_end = 1'b0;

    wire       out_valid;
    reg        out_ready = 1'b1;
    wire [7:0] out_data;
    wire       out_last;

    wire       done;
    wire       busy;
    wire [31:0] stat_blocks, stat_fixed, stat_stored, stat_literals;
    wire [31:0] stat_matches, stat_cand_aborts, stat_stall;
    wire [31:0] stat_max_match, stat_max_dist;

    a1_deflate_core dut (
        .clk(clk), .rst_n(rst_n), .abort(abort),
        .in_valid(in_valid), .in_ready(in_ready), .in_data(in_data),
        .in_sop(in_sop), .in_blk_end(in_blk_end), .in_stream_end(in_stream_end),
        .out_valid(out_valid), .out_ready(out_ready), .out_data(out_data),
        .out_last(out_last), .done(done), .busy(busy),
        .stat_blocks(stat_blocks), .stat_fixed(stat_fixed),
        .stat_stored(stat_stored), .stat_literals(stat_literals),
        .stat_matches(stat_matches), .stat_cand_aborts(stat_cand_aborts),
        .stat_stall(stat_stall), .stat_max_match(stat_max_match),
        .stat_max_dist(stat_max_dist)
    );

    reg [7:0]  imem [0:262143];
    reg [31:0] meta [0:1023];

    integer outf, statf, inf, metaf;
    integer nblocks, total, idx, b, k;
    integer ends [0:1023];
    integer bp_mode, gap_mode, abort_at, rst_at, timeout_max;
    integer cyc, first_cyc, done_cyc, timeout;
    integer out_bytes, last_seen, stopped_early;
    reg [1023:0] in_path, out_path, stat_path, meta_path;
    reg done_seen;

    always @(posedge clk) cyc <= cyc + 1;

    always @(posedge clk) begin
        if (done && !done_seen) begin
            done_seen <= 1'b1;
            done_cyc  <= cyc;
        end
    end

    always @(posedge clk) begin
        if (out_valid && out_ready) begin
            $fwrite(outf, "%02x\n", out_data);
            out_bytes <= out_bytes + 1;
            if (out_last) last_seen <= 1;
        end
    end

    always @(negedge clk) begin
        if (bp_mode != 0) out_ready <= (($random & 3) != 0);
        else              out_ready <= 1'b1;
    end

    initial begin
        cyc = 0; first_cyc = 0; done_cyc = 0; out_bytes = 0;
        last_seen = 0; stopped_early = 0; done_seen = 1'b0;
        bp_mode = 0; gap_mode = 0; abort_at = 0; rst_at = 0;
        timeout_max = 5000000; nblocks = 0; total = 0; idx = 0;

        if (!$value$plusargs("IN=%s", in_path))       begin $display("no +IN"); $finish; end
        if (!$value$plusargs("META=%s", meta_path))   begin $display("no +META"); $finish; end
        if (!$value$plusargs("OUT=%s", out_path))     begin $display("no +OUT"); $finish; end
        if (!$value$plusargs("STAT=%s", stat_path))   begin $display("no +STAT"); $finish; end
        $value$plusargs("BP=%d", bp_mode);
        $value$plusargs("GAP=%d", gap_mode);
        $value$plusargs("ABORT_AT=%d", abort_at);
        $value$plusargs("RST_AT=%d", rst_at);
        $value$plusargs("TIMEOUT=%d", timeout_max);

        $readmemh(in_path, imem);
        $readmemh(meta_path, meta);

        outf  = $fopen(out_path, "w");
        statf = $fopen(stat_path, "w");
        if (outf == 0 || statf == 0) begin $display("cannot open output files"); $finish; end

        nblocks = meta[0];
        total = 0;
        for (b = 0; b < nblocks; b = b + 1) begin
            ends[b] = total + meta[b + 1] - 1;
            total = total + meta[b + 1];
        end
        if (total > 262144) begin $display("input image too large"); $finish; end

        repeat (5) @(posedge clk);
        rst_n <= 1'b1;
        repeat (2) @(posedge clk);

        b = 0;
        while (idx < total && !stopped_early) begin
            if (gap_mode != 0 && (($random & 7) == 0)) begin
                in_valid <= 1'b0;
                repeat (1 + ($random & 1)) @(posedge clk);
            end
            in_data        <= imem[idx];
            in_sop         <= (idx == 0);
            in_blk_end     <= (idx == ends[b]);
            in_stream_end  <= (idx == (total - 1));
            in_valid       <= 1'b1;
            @(posedge clk);
            while (!in_ready) @(posedge clk);
            if (idx == 0) first_cyc = cyc;
            idx = idx + 1;
            if (idx > ends[b] && b < (nblocks - 1)) b = b + 1;
            @(negedge clk);
            in_valid <= 1'b0;

            if (abort_at > 0 && idx >= abort_at) begin
                abort <= 1'b1;
                @(posedge clk);
                abort <= 1'b0;
                stopped_early = 1;
            end
            if (rst_at > 0 && idx >= rst_at) begin
                rst_n <= 1'b0;
                repeat (3) @(posedge clk);
                rst_n <= 1'b1;
                stopped_early = 1;
            end
        end

        in_valid <= 1'b0;
        in_sop <= 1'b0;
        in_blk_end <= 1'b0;
        in_stream_end <= 1'b0;

        timeout = 0;
        while (!done_seen && timeout < timeout_max && !stopped_early) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (stopped_early) begin
            repeat (500) @(posedge clk);
        end

        $fdisplay(statf, "in_bytes %0d", idx);
        $fdisplay(statf, "out_bytes %0d", out_bytes);
        $fdisplay(statf, "first_cycle %0d", first_cyc);
        $fdisplay(statf, "done_cycle %0d", done_cyc);
        $fdisplay(statf, "run_cycles %0d", (done_cyc > first_cyc) ? (done_cyc - first_cyc) : 0);
        $fdisplay(statf, "done %0d", done_seen);
        $fdisplay(statf, "out_last %0d", last_seen);
        $fdisplay(statf, "stopped_early %0d", stopped_early);
        $fdisplay(statf, "bp %0d", bp_mode);
        $fdisplay(statf, "gap %0d", gap_mode);
        $fdisplay(statf, "stat_blocks %0d", stat_blocks);
        $fdisplay(statf, "stat_fixed %0d", stat_fixed);
        $fdisplay(statf, "stat_stored %0d", stat_stored);
        $fdisplay(statf, "stat_literals %0d", stat_literals);
        $fdisplay(statf, "stat_matches %0d", stat_matches);
        $fdisplay(statf, "stat_cand_aborts %0d", stat_cand_aborts);
        $fdisplay(statf, "stat_stall %0d", stat_stall);
        $fdisplay(statf, "stat_max_match %0d", stat_max_match);
        $fdisplay(statf, "stat_max_dist %0d", stat_max_dist);
        $fdisplay(statf, "timeout_hit %0d", (!done_seen && !stopped_early));

        $fclose(outf);
        $fclose(statf);
        $finish;
    end

    // guard: no simulation should run away silently
    initial begin
        #2000000000;
        $display("GLOBAL_TIMEOUT");
        $finish;
    end

endmodule
