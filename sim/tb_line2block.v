`timescale 1ns/1ps
// tb_line2block.v — 16 行 x 64 像素转成 16 个 8x8 块
module tb_line2block;
    localparam W = 64, H = 16;
    reg clk = 0, rst_n = 0;
    reg [31:0] s_data = 0;
    reg s_valid = 0, s_eol = 0, s_eof = 0;
    wire s_ready;
    wire [31:0] m_data;
    wire m_valid, m_sof, m_eof;
    reg  m_ready = 1;

    line2block #(.W(W)) dut (.clk(clk), .rst_n(rst_n),
        .s_data(s_data), .s_valid(s_valid), .s_ready(s_ready),
        .s_eol(s_eol), .s_eof(s_eof),
        .m_data(m_data), .m_valid(m_valid), .m_ready(m_ready),
        .m_sof(m_sof), .m_eof(m_eof));

    always #5 clk = ~clk;

    integer i, y, x, nout, fi, fo, code, v;
    reg [7:0] img [0:1023];

    always @(posedge clk) if (m_valid && m_ready) begin
        $fwrite(fo, "%02x %02x %02x %02x\n",
                m_data[7:0], m_data[15:8], m_data[23:16], m_data[31:24]);
        nout = nout + 1;
    end

    initial begin
        fi = $fopen("/tmp/l2b_in.txt", "r");
        fo = $fopen("/tmp/l2b_out.txt", "w");
        for (i = 0; i < 1024; i = i + 1) begin
            code = $fscanf(fi, "%d", v);
            img[i] = v[7:0];
        end
        rst_n = 0; repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);
        nout = 0;
        for (y = 0; y < H; y = y + 1) begin
            for (x = 0; x < W/4; x = x + 1) begin
                s_data = { img[y*W + x*4 + 3], img[y*W + x*4 + 2],
                           img[y*W + x*4 + 1], img[y*W + x*4 + 0] };
                s_valid = 1;
                s_eol = (x == W/4 - 1);
                s_eof = (y == H-1) && (x == W/4 - 1);
                @(negedge clk);
                while (!s_ready) @(negedge clk);
            end
        end
        s_valid = 0; s_eol = 0; s_eof = 0;
        repeat (500) @(negedge clk);
        $display("输出 %0d 拍（应为 %0d）", nout, (W/4)*(H/8)*8);
        $fclose(fo);
        $finish;
    end
endmodule

