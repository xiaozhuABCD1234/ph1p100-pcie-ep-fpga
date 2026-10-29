`timescale 1ns/1ps
// tb_jpeg_frame.v — 完整 JPEG 编码器整帧对拍（64x16 小图）
module tb_jpeg_frame;
    localparam W = 64, H = 16;
    reg clk = 0, rst_n = 0;
    reg [31:0] s_data = 0;
    reg s_valid = 0, s_eol = 0, s_eof = 0;
    wire s_ready;
    wire [7:0] m_data;
    wire m_valid;
    reg  m_ready = 1;
    wire [31:0] st_blocks;

    jpeg_frame #(.W(W)) dut (.clk(clk), .rst_n(rst_n),
        .s_data(s_data), .s_valid(s_valid), .s_ready(s_ready),
        .s_eol(s_eol), .s_eof(s_eof),
        .m_data(m_data), .m_valid(m_valid), .m_ready(m_ready),
        .st_blocks(st_blocks));

    always #5 clk = ~clk;

    integer i, y, x, nout, fi, fo, code, v;
    reg [7:0] img [0:1023];

    always @(posedge clk) if (m_valid && m_ready) begin
        $fwrite(fo, "%02x ", m_data);
        nout = nout + 1;
    end

    initial begin
        fi = $fopen("/tmp/l2b_in.txt", "r");
        fo = $fopen("/tmp/jf_out.txt", "w");
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
        repeat (3000) @(negedge clk);
        $display("块数 %0d 码流字节 %0d", st_blocks, nout);
        $fclose(fo);
        $finish;
    end
endmodule

