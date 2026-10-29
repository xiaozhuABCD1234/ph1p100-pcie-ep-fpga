`timescale 1ns/1ps
module tb_d2d_one;
    reg clk = 0, rst_n = 0;
    reg [31:0] s_data = 0;
    reg s_valid = 0, s_sof = 0, s_eof = 0;
    wire s_ready;
    wire [127:0] m_data;
    wire m_valid, m_sof, m_eof;
    reg m_ready = 1;

    dct2d8 dut (.clk(clk), .rst_n(rst_n),
        .s_data(s_data), .s_valid(s_valid), .s_ready(s_ready),
        .s_sof(s_sof), .s_eof(s_eof),
        .m_data(m_data), .m_valid(m_valid), .m_ready(m_ready),
        .m_sof(m_sof), .m_eof(m_eof));

    always #5 clk = ~clk;

    integer i, k, fi, code, v;
    reg [7:0] px [0:63];
    reg [127:0] cap;

    initial begin
        fi = $fopen("/tmp/one_in.txt", "r");
        for (i = 0; i < 64; i = i + 1) begin
            code = $fscanf(fi, "%d", v);
            px[i] = v[7:0];
        end
        $fclose(fi);
        rst_n = 0; repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);

        for (i = 0; i < 16; i = i + 1) begin
            s_data  = {px[i*4+3], px[i*4+2], px[i*4+1], px[i*4]};
            s_valid = 1;
            s_sof   = (i == 0);
            @(negedge clk);
            while (!s_ready) @(negedge clk);
        end
        s_valid = 0; s_sof = 0;
        repeat (200) @(negedge clk);

        $display("--- 行 DCT 结果 tmp[0..7] ---");
        for (k = 0; k < 8; k = k + 1) $display("tmp[%0d]=%0d", k, $signed(dut.tmp[k]));
        $display("--- 列 DCT 结果 out[0..7] ---");
        for (k = 0; k < 8; k = k + 1) $display("out[%0d]=%0d", k, $signed(dut.out[k]));
        $finish;
    end

    always @(posedge clk) if (m_valid && m_ready) begin
        cap = m_data;
        $display("OUT %0d %0d %0d %0d %0d %0d %0d %0d",
            $signed(cap[15:0]), $signed(cap[31:16]), $signed(cap[47:32]), $signed(cap[63:48]),
            $signed(cap[79:64]), $signed(cap[95:80]), $signed(cap[111:96]), $signed(cap[127:112]));
    end
endmodule

