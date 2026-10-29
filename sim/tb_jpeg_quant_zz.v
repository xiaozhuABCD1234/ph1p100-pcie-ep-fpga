`timescale 1ns/1ps
// tb_jpeg_qz.v — 量化 + 之字形对拍
module tb_jpeg_qz;
    reg clk = 0, rst_n = 0;
    reg [127:0] s_data = 0;
    reg s_valid = 0;
    wire s_ready;
    wire [127:0] m_data;
    wire m_valid, m_sof;
    reg  m_ready = 1;
    wire [31:0] st_blocks;

    jpeg_quant_zz dut (.clk(clk), .rst_n(rst_n),
        .s_data(s_data), .s_valid(s_valid), .s_ready(s_ready),
        .m_data(m_data), .m_valid(m_valid), .m_ready(m_ready), .m_sof(m_sof),
        .st_blocks(st_blocks));

    always #5 clk = ~clk;

    integer fi, fo, i, k, code, v;
    integer coef [0:63];
    reg [127:0] cap;

    always @(posedge clk) if (m_valid && m_ready) begin
        cap = m_data;
        for (k = 0; k < 8; k = k + 1)
            $fwrite(fo, "%0d%s", $signed(cap[k*16 +: 16]), (k == 7) ? "\n" : " ");
    end

    initial begin
        $display("TB start");
        fi = $fopen("/tmp/qz_in.txt", "r");
        $display("fi=%0d", fi);
        fo = $fopen("/tmp/qz_out.txt", "w");
        rst_n = 0; repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);

        for (i = 0; i < 64; i = i + 1) begin
            code = $fscanf(fi, "%d", v); if (i < 2) $display("i=%0d code=%0d v=%0d", i, code, v);
            coef[i] = v;
        end
        // 8 拍送 64 个系数
        $display("start send");
        for (i = 0; i < 8; i = i + 1) begin
            s_data = { coef[i*8+7][15:0], coef[i*8+6][15:0], coef[i*8+5][15:0], coef[i*8+4][15:0],
                       coef[i*8+3][15:0], coef[i*8+2][15:0], coef[i*8+1][15:0], coef[i*8+0][15:0] };
            s_valid = 1;
            @(negedge clk);
            while (!s_ready) @(negedge clk);
        end
        s_valid = 0;
        repeat (40) @(negedge clk);
        $display("处理 %0d 块", st_blocks);
        $fclose(fo);
        $finish;
    end
endmodule

