`timescale 1ns/1ps
// tb_jpeg_enc.v — 整条 JPEG 流水线对拍（块级）：像素 -> 码流
module tb_jpeg_enc;
    reg clk = 0, rst_n = 0;
    reg [31:0] s_data = 0;
    reg s_valid = 0, s_sof = 0, s_eof = 0;
    wire s_ready;
    wire [7:0] m_data;
    wire m_valid;
    reg  m_ready = 1;
    wire [31:0] st_blocks;

    jpeg_enc dut (.clk(clk), .rst_n(rst_n),
        .s_data(s_data), .s_valid(s_valid), .s_ready(s_ready),
        .s_sof(s_sof), .s_eof(s_eof),
        .m_data(m_data), .m_valid(m_valid), .m_ready(m_ready),
        .st_blocks(st_blocks));

    always #5 clk = ~clk;

    integer fi, fo, i, j, code, v, nblk, nout;
    integer px [0:63];

    always @(posedge clk) if (m_valid && m_ready) begin
        $fwrite(fo, "%02x ", m_data);
        nout = nout + 1;
    end

    initial begin
        fi = $fopen("/tmp/jenc_in.txt", "r");
        fo = $fopen("/tmp/jenc_out.txt", "w");
        rst_n = 0; repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);
        nblk = 0; nout = 0;
        for (j = 0; j < 4; j = j + 1) begin
            for (i = 0; i < 64; i = i + 1) begin
                code = $fscanf(fi, "%d", v); px[i] = v;
            end
            for (i = 0; i < 16; i = i + 1) begin
                s_data = { px[i*4+3][7:0], px[i*4+2][7:0], px[i*4+1][7:0], px[i*4][7:0] };
                s_valid = 1;
                s_sof   = (i == 0) && (j == 0);
                s_eof   = (j == 3) && (i == 15);
                @(negedge clk);
                while (!s_ready) @(negedge clk);
            end
            s_valid = 0; s_sof = 0; s_eof = 0;
            wait (st_blocks >= j + 1);
            repeat (20) @(negedge clk);
            nblk = nblk + 1;
        end
        $display("块数 %0d 码流字节 %0d", nblk, nout);
        $fclose(fo);
        $finish;
    end
endmodule

