`timescale 1ns/1ps
// tb_jpeg_huff.v — 熵编码对拍：送 64 个之字形系数，输出字节流
module tb_jpeg_huff;
    reg clk = 0, rst_n = 0;
    reg [127:0] s_data = 0;
    reg s_valid = 0, s_sof = 0;
    wire s_ready;
    wire [7:0] m_data;
    wire m_valid, m_sof;
    reg  m_ready = 1;
    wire [31:0] st_bits, st_blocks;

    jpeg_huff_enc dut (.clk(clk), .rst_n(rst_n),
        .s_data(s_data), .s_valid(s_valid), .s_ready(s_ready), .s_sof(s_sof),
        .m_data(m_data), .m_valid(m_valid), .m_ready(m_ready), .m_sof(m_sof),
        .st_bits(st_bits), .st_blocks(st_blocks));

    always #5 clk = ~clk;

    integer fi, fo, i, k, code, v;
    integer zz [0:63];

    always @(posedge clk) if (m_valid && m_ready)
        $fwrite(fo, "%02x ", m_data);

    initial begin
        fi = $fopen("/tmp/blk_zz.txt", "r");
        fo = $fopen("/tmp/huff_out.txt", "w");
        rst_n = 0; repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);

        for (i = 0; i < 64; i = i + 1) begin
            code = $fscanf(fi, "%d", v);
            zz[i] = v;
        end
        // 8 拍送完，第 1 拍带 sof
        for (i = 0; i < 8; i = i + 1) begin
            s_data = { zz[i*8+7][15:0], zz[i*8+6][15:0], zz[i*8+5][15:0], zz[i*8+4][15:0],
                       zz[i*8+3][15:0], zz[i*8+2][15:0], zz[i*8+1][15:0], zz[i*8+0][15:0] };
            s_valid = 1;
            s_sof   = (i == 0);
            @(negedge clk);
            while (!s_ready) @(negedge clk);
        end
        s_valid = 0; s_sof = 0;
        repeat (400) @(negedge clk);
        $display("块数 %0d  比特 %0d", st_blocks, st_bits);
        $fclose(fo);
        $finish;
    end
endmodule

