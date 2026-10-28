`timescale 1ns/1ps
module tb_enc;
    reg clk = 0, rst_n = 0;
    reg [7:0] in_data = 0;
    reg in_valid = 0, in_sof = 0, in_eof = 0;
    wire in_ready;
    wire [7:0] out_data;
    wire out_valid;
    reg out_ready = 1;
    wire [31:0] st_in, st_out, st_m;

    lz77_enc dut (.clk(clk), .rst_n(rst_n),
        .in_data(in_data), .in_valid(in_valid), .in_ready(in_ready),
        .in_sof(in_sof), .in_eof(in_eof),
        .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready),
        .st_in_bytes(st_in), .st_out_bytes(st_out), .st_matches(st_m));

    always #5 clk = ~clk;

    integer fin, fout, i, c, nbytes = 0;
    reg [7:0] mem [0:65535];
    integer nin, nout = 0;
    reg [7:0] obuf [0:65535];

    always @(posedge clk) begin
        if (out_valid && out_ready) begin
            obuf[nout] = out_data; nout = nout + 1;
        end
    end

    initial begin
        fin = $fopen("/tmp/in.bin", "rb");
        for (i = 0; i < 65536; i = i + 1) begin
            c = $fgetc(fin);
            if (c < 0) begin nin = i; i = 65536; end
            else mem[i] = c[7:0];
        end
        $display("读入 %0d 字节", nin);
        rst_n = 0; repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);
        for (i = 0; i < nin; i = i + 1) begin
            in_data = mem[i];
            in_valid = 1;
            in_sof = (i == 0);
            in_eof = (i == nin - 1);
            @(negedge clk);
            while (!in_ready) @(negedge clk);
        end
        in_valid = 0; in_sof = 0; in_eof = 0;
        repeat (20000) @(negedge clk);
        fout = $fopen("/tmp/out.bin", "wb");
        for (i = 0; i < nout; i = i + 1) $fwrite(fout, "%c", obuf[i]);
        $fclose(fout);
        $display("输出 %0d 字节  st_in=%0d lacnt=%0d st=%0d litcnt=%0d wptr=%0d", nout, st_in, dut.lacnt, dut.st, dut.litcnt, dut.wptr);
        $finish;
    end
endmodule

