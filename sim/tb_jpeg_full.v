`timescale 1ns/1ps
// tb_jpeg_full.v — 连续两帧整帧 JPEG 编码（1920x1088）
//
// 目的：
//   1) 「一帧到底会不会结束」——1088 = 136 组，最后一组最后一拍必须带 eof；
//   2) 连续帧的 DC 预测必须每帧从 0 起，第二帧码流应与第一帧**逐字节相同**。
//      板上连续帧曾出现整帧被常数抬亮（+102），根因就是 prev_dc 没在 SOF 清零。
// 产物：/tmp/jf_full.bin（两帧拼接）。主机侧按帧长度切开对拍。
module tb_jpeg_full;
    localparam W = 1920, H = 1088;
    localparam NF = 2;

    reg clk = 0, rst_n = 0;
    reg [31:0] s_data = 0;
    reg s_valid = 0, s_eol = 0, s_eof = 0;
    wire s_ready;
    wire [7:0] m_data;
    wire m_valid;
    reg  m_ready = 1;
    wire [31:0] st_blocks;
    wire m_done;

    jpeg_frame #(.W(W)) dut (.clk(clk), .rst_n(rst_n),
        .s_data(s_data), .s_valid(s_valid), .s_ready(s_ready),
        .s_eol(s_eol), .s_eof(s_eof),
        .m_data(m_data), .m_valid(m_valid), .m_ready(m_ready),
        .st_blocks(st_blocks), .m_done(m_done));

    always #5 clk = ~clk;

    integer fi, fo;
    integer y, x, nout, ndone, code, cyc, f, mark;
    reg [7:0] img [0:W*H-1];

    always @(posedge clk) begin
        if (m_valid && m_ready) begin
            $fwrite(fo, "%c", m_data);
            nout = nout + 1;
        end
        if (m_done) begin
            ndone = ndone + 1;
            mark  = nout;
            $display("[%0t] m_done 第 %0d 次：块 %0d 累计字节 %0d", $time, ndone, st_blocks, nout);
        end
        cyc = cyc + 1;
    end

    initial begin
        fi = $fopen("/tmp/jf_full_in.raw", "rb");
        fo = $fopen("/tmp/jf_full.bin", "wb");
        if (fi == 0) begin $display("缺少 /tmp/jf_full_in.raw"); $finish; end
        code = $fread(img, fi);
        $fclose(fi);
        nout = 0; ndone = 0; cyc = 0; mark = 0;
        rst_n = 0; repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);
        for (f = 0; f < NF; f = f + 1) begin
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
            repeat (20000) @(negedge clk);
        end
        repeat (200000) @(negedge clk);
        $display("块数 %0d（应为 %0d） 码流字节 %0d m_done 脉冲 %0d 周期 %0d",
                 st_blocks, NF*(W/8)*(H/8), nout, ndone, cyc);
        if (ndone != NF) $display("失败：m_done 脉冲数应为 %0d", NF);
        else $display("通过：两帧都正常结束");
        $fclose(fo);
        $finish;
    end
endmodule
