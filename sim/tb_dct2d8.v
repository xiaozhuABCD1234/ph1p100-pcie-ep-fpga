`timescale 1ns/1ps
// tb_dct2d8.v — 对拍二维 DCT：读 8x8 块，输出 64 个系数（8 个/行）
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

    integer fi, fo, i, j, k, code, nb;
    integer px [0:63];
    reg [127:0] cap;

    always @(posedge clk) begin
        if (m_valid && m_ready) begin
            cap = m_data;
            for (k = 0; k < 8; k = k + 1)
                $fwrite(fo, "%0d%s", $signed(cap[k*16 +: 16]), (k == 7) ? "\n" : " ");
        end
    end

    initial begin
        fi = $fopen("/tmp/d2d_in.txt", "r");
        fo = $fopen("/tmp/d2d_out.txt", "w");
        rst_n = 0; repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);

        nb = 0;
        for (j = 0; j < 20; j = j + 1) begin
            for (i = 0; i < 64; i = i + 1) begin
                code = $fscanf(fi, "%d", px[i]);
            end
            if (code != 1) j = 20;
            else begin
                // 16 拍送完 64 像素
                for (i = 0; i < 16; i = i + 1) begin
                    s_data  = {px[i*4+3], px[i*4+2], px[i*4+1], px[i*4]};
                    s_valid = 1;
                    s_sof   = (i == 0);

                    s_eof   = (j == 19) && (i == 15);
                    @(negedge clk);
                    while (!s_ready) @(negedge clk);
                end
                s_valid = 0; s_sof = 0;
                repeat (150) @(negedge clk);  // 等变换 + 输出 8 拍
                nb = nb + 1;
            end
        end
        $display("处理 %0d 块", nb);
        $fclose(fo);
        $finish;
    end
endmodule

