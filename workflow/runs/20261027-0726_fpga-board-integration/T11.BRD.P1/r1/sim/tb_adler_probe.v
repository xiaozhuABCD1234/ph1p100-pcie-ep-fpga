`timescale 1ns/1ps
// tb_adler_probe.v -- bounded probe: does a1_deflate_core emit the Adler tail?
// Feeds N bytes as ONE block with in_sop on byte 0 and in_blk_end|in_stream_end
// on byte N-1, captures the emitted zlib stream and writes it to a file.
module tb_adler_probe;
    localparam integer N = 256;

    reg clk = 0, rst_n = 0;
    always #3 clk = ~clk;

    reg         in_valid = 0;
    wire        in_ready;
    reg  [7:0]  in_data = 0;
    reg         in_sop = 0, in_blk_end = 0, in_stream_end = 0;
    wire        out_valid;
    wire [7:0]  out_data;
    wire        out_last;
    wire        out_ready = 1'b1;

    reg  [7:0]  outp [0:4095];
    integer     ocnt = 0;
    integer     i;
    integer     fd;

    a1_deflate_core u_core (
        .clk(clk), .rst_n(rst_n), .abort(1'b0),
        .in_valid(in_valid), .in_ready(in_ready), .in_data(in_data),
        .in_sop(in_sop), .in_blk_end(in_blk_end), .in_stream_end(in_stream_end),
        .out_valid(out_valid), .out_ready(out_ready), .out_data(out_data),
        .out_last(out_last), .done(), .busy(),
        .stat_blocks(), .stat_fixed(), .stat_stored(), .stat_literals(),
        .stat_matches(), .stat_cand_aborts(), .stat_stall(), .stat_max_match(),
        .stat_max_dist(), .dbg_state()
    );

    // capture output
    always @(posedge clk) begin
        if (rst_n && out_valid && out_ready) begin
            outp[ocnt] = out_data;
            ocnt = ocnt + 1;
        end
    end

    // expected Adler of the input pattern
    integer a32 = 1, b32 = 0;
    integer exp_adler;

    initial begin
        repeat (8) @(posedge clk);
        rst_n = 1;
        repeat (4) @(posedge clk);

        // drive every byte from the negedge, advance only on an accepted edge
        i = 0;
        @(negedge clk);
        in_valid = 1'b1;
        in_data  = (0 * 8'd7 + 8'd3) & 8'hFF;
        in_sop   = 1'b1; in_blk_end = 1'b0; in_stream_end = 1'b0;
        while (i < N) begin
            @(posedge clk);
            if (in_ready) begin
                i = i + 1;
                @(negedge clk);
                if (i < N) begin
                    in_data       = (i * 8'd7 + 8'd3) & 8'hFF;
                    in_sop        = 1'b0;
                    in_blk_end    = (i == N-1);
                    in_stream_end = (i == N-1);
                end else begin
                    in_valid = 1'b0; in_blk_end = 1'b0; in_stream_end = 1'b0;
                end
            end
        end

        // wait for out_last
        i = 0;
        while ((ocnt == 0 || !out_last) && (i < 200000)) begin
            @(posedge clk); i = i + 1;
        end
        repeat (50) @(posedge clk);

        $display("PROBE stream_len=%0d last8=%h %h %h %h %h %h %h %h",
                 ocnt, outp[ocnt-8], outp[ocnt-7], outp[ocnt-6], outp[ocnt-5],
                 outp[ocnt-4], outp[ocnt-3], outp[ocnt-2], outp[ocnt-1]);

        // Adler over the input bytes (a1 starts 1, b starts 0)
        for (i = 0; i < N; i = i + 1) begin
            a32 = (a32 + ((i * 8'd7 + 8'd3) & 8'hFF)) % 65521;
            b32 = (b32 + a32) % 65521;
        end
        exp_adler = (b32 << 16) | a32;
        $display("PROBE expected_adler=%08h tail=%02h%02h%02h%02h",
                 exp_adler, outp[ocnt-4], outp[ocnt-3], outp[ocnt-2], outp[ocnt-1]);

        fd = $fopen("adler_probe_stream.bin", "wb");
        for (i = 0; i < ocnt; i = i + 1) $fwrite(fd, "%c", outp[i]);
        $fclose(fd);
        $display("PROBE wrote adler_probe_stream.bin");
        if ({outp[ocnt-4], outp[ocnt-3], outp[ocnt-2], outp[ocnt-1]} === exp_adler)
            $display("PROBE_ADLER=PASS");
        else
            $display("PROBE_ADLER=FAIL");
        $finish;
    end

    initial begin
        #2000000;
        $display("PROBE_ADLER=FAIL timeout ocnt=%0d", ocnt);
        $finish;
    end
endmodule
