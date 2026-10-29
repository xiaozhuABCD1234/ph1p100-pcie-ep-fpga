`timescale 1ns/1ps
// tb_dct2d8.v — 2x2 DCT 批量对拍：连续送 20 个 8x8 块，逐块比对系数
module tb_dct2d8;
    reg clk = 0, rst_n = 0;
    reg [31:0] s_data = 0;
    reg s_valid = 0, s_sof = 0, s_eof = 0;
    wire s_ready;
    wire [127:0] m_data;
    wire m_valid, m_sof, m_eof;
    reg  m_ready = 1;

    dct2d8 dut (.clk(clk), .rst_n(rst_n),
        .s_data(s_data), .s_valid(s_valid), .s_ready(s_ready),
        .s_sof(s_sof), .s_eof(s_eof),
        .m_data(m_data), .m_valid(m_valid), .m_ready(m_ready),
        .m_sof(m_sof), .m_eof(m_eof));

    always #5 clk = ~clk;

    integer fi, fo, i, j, k, code, v, nblk, nline;
    reg [7:0] px [0:63];
    reg [127:0] cap;

    always @(posedge clk) begin
        if (m_valid && m_ready) begin
            cap = m_data;
            for (k = 0; k < 8; k = k + 1)
                $fwrite(fo, "%0d%s", $signed(cap[k*16 +: 16]), (k == 7) ? "\n" : " ");
            nline = nline + 1;
        end
    end

    initial begin
        fi = $fopen("/tmp/d2d_in.txt", "r");
        fo = $fopen("/tmp/d2d_out.txt", "w");
        rst_n = 0; repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);

        nblk = 0; nline = 0;
        for (j = 0; j < 20; j = j + 1) begin
            for (i = 0; i < 64; i = i + 1) begin
                code = $fscanf(fi, "%d", v);
                px[i] = v[7:0];
            end
            // 送 64 个像素：16 拍 x 4
            for (i = 0; i < 16; i = i + 1) begin
                s_data  = {px[i*4+3], px[i*4+2], px[i*4+1], px[i*4]};
                s_valid = 1;
                s_sof   = (i == 0);
                s_eof   = (j == 19) && (i == 15);
                @(negedge clk);
                while (!s_ready) @(negedge clk);
            end
            s_valid = 0; s_sof = 0; s_eof = 0;
            // 等这一块算完并输出（约 45 拍），再多留余量
            wait (nline >= (j + 1) * 8);
            repeat (5) @(negedge clk);
            nblk = nblk + 1;
        end
        $display("处理 %0d 块，输出 %0d 行", nblk, nline);
        $fclose(fo);
        $finish;
    end
endmodule

