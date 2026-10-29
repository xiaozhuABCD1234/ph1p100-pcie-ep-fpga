`timescale 1ns/1ps
// tb_jpeg_huff.v — 多块熵编码对拍（验证 DC 差分跨块 + 帧末补位）
module tb_jpeg_huff;
    reg clk = 0, rst_n = 0;
    reg [127:0] s_data = 0;
    reg s_valid = 0, s_sof = 0, s_eof = 0;
    wire s_ready;
    wire [7:0] m_data;
    wire m_valid;
    reg  m_ready = 1;
    wire [31:0] st_bits, st_blocks;

    jpeg_huff_enc dut (.clk(clk), .rst_n(rst_n),
        .s_data(s_data), .s_valid(s_valid), .s_ready(s_ready),
        .s_sof(s_sof), .s_eof(s_eof),
        .m_data(m_data), .m_valid(m_valid), .m_ready(m_ready),
        .st_bits(st_bits), .st_blocks(st_blocks));

    always #5 clk = ~clk;

    integer fi, fo, i, j, code, v, nblk, nout;
    integer zz [0:63];

    always @(posedge clk) if (m_valid && m_ready) begin
        $fwrite(fo, "%02x ", m_data);
        nout = nout + 1;
    end

    initial begin
        fi = $fopen("/tmp/huff_in.txt", "r");
        fo = $fopen("/tmp/huff_out.txt", "w");
        rst_n = 0; repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);
        nblk = 0; nout = 0;

        for (j = 0; j < 3; j = j + 1) begin
            for (i = 0; i < 64; i = i + 1) begin
                code = $fscanf(fi, "%d", v);
                zz[i] = v;
            end
            // 最后一块的最后一拍带 eof
            for (i = 0; i < 8; i = i + 1) begin
                s_data = { zz[i*8+7][15:0], zz[i*8+6][15:0], zz[i*8+5][15:0], zz[i*8+4][15:0],
                           zz[i*8+3][15:0], zz[i*8+2][15:0], zz[i*8+1][15:0], zz[i*8+0][15:0] };
                s_valid = 1;
                s_sof   = (i == 0) && (j == 0);
                s_eof   = (j == 2) && (i == 7);
                @(negedge clk);
                while (!s_ready) @(negedge clk);
            end
            s_valid = 0; s_sof = 0; s_eof = 0;
            wait (st_blocks >= j + 1);
            repeat (5) @(negedge clk);
            nblk = nblk + 1;
        end
        $display("块数 %0d 输出字节 %0d", nblk, nout);
        $fclose(fo);
        $finish;
    end
endmodule

