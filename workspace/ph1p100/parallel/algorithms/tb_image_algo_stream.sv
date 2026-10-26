`timescale 1ns/1ps
// 三算法 RTL 测试台（向量驱动）。**这是测试台，不是生产 RTL。**
//
// 背景：赛题 R2 要求三种硬件预处理。本 TB 把 `parallel/algorithms` 金参考产出的
// 向量（$readmemh 十六进制）灌给 DUT，并按**出现顺序**逐像素比对三路输出。
// 顺序比对（而非固定周期）是有意的：首版 RTL 的延迟/流水级数尚未冻结。
//
// DUT 端口契约（提案，需与 RTL 线冻结）：
//   start        单周期脉冲，开始一帧
//   raw_in[9:0] / raw_valid   行主序 RAW10 样本，每拍 1 个像素
//   lut_we/lut_addr/lut_data  装载 HE 的 256×8bit LUT（与帧无关，先装后跑）
//   y8_out/gau_out/he_out + *_valid  三路输出，顺序与输入像素一一对应
//   busy         处理中
//
// 向量目录用 +VECDIR=<dir> 传入，目录内固定文件名：raw10.hex / y8.hex / gauss.hex / he.hex
// 通过条件：三路各 W*H 个样本逐字节相同，打印 ALGO_TB_PASS。
module tb_image_algo_stream #(parameter W = 16, parameter H = 12);
    localparam NP = W * H;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;

    reg [1023:0] vecdir;
    reg [1023:0] fn;
    // 用 16bit 宽度装载：向量文件是 4 位十六进制，避免 $readmemh 截断告警
    reg [15:0] raw_mem[0:NP-1];
    reg [15:0] y8_mem[0:NP-1], gau_mem[0:NP-1], he_mem[0:NP-1];
    reg [7:0] lut_mem[0:255];

    // DUT 侧信号
    reg start = 0, raw_valid = 0, lut_we = 0;
    reg [9:0] raw_in = 0;
    reg [7:0] lut_addr = 0, lut_data = 0;
    wire [7:0] y8_out, gau_out, he_out;
    wire y8_valid, gau_valid, he_valid, busy;

    image_algo_dut #(.W(W), .H(H)) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .raw_in(raw_in), .raw_valid(raw_valid),
        .lut_we(lut_we), .lut_addr(lut_addr), .lut_data(lut_data),
        .y8_out(y8_out), .y8_valid(y8_valid),
        .gau_out(gau_out), .gau_valid(gau_valid),
        .he_out(he_out), .he_valid(he_valid),
        .busy(busy));

    integer n_y8, n_gau, n_he, errs, i;
    reg [9:0] first_bad;
    reg [7:0] got, exp;

    // 顺序收集并立即比对
    always @(posedge clk) begin
        if (rst_n && y8_valid) begin
            if (y8_out !== y8_mem[n_y8][7:0]) begin
                if (errs == 0) first_bad = 10'(n_y8);
                errs = errs + 1;
                $display("ALGO_TB_MISMATCH y8 idx=%0d got=%02x exp=%02x", n_y8, y8_out, y8_mem[n_y8][7:0]);
            end
            n_y8 = n_y8 + 1;
        end
        if (rst_n && gau_valid) begin
            if (gau_out !== gau_mem[n_gau][7:0]) begin
                if (errs == 0) first_bad = 10'(n_gau);
                errs = errs + 1;
                $display("ALGO_TB_MISMATCH gau idx=%0d got=%02x exp=%02x", n_gau, gau_out, gau_mem[n_gau][7:0]);
            end
            n_gau = n_gau + 1;
        end
        if (rst_n && he_valid) begin
            if (he_out !== he_mem[n_he][7:0]) begin
                if (errs == 0) first_bad = 10'(n_he);
                errs = errs + 1;
                $display("ALGO_TB_MISMATCH he idx=%0d got=%02x exp=%02x", n_he, he_out, he_mem[n_he][7:0]);
            end
            n_he = n_he + 1;
        end
    end

    integer k;
    initial begin
        n_y8 = 0; n_gau = 0; n_he = 0; errs = 0; first_bad = 0;
        if (!$value$plusargs("VECDIR=%s", vecdir)) begin
            $display("ALGO_TB_FAIL no +VECDIR");
            $finish;
        end
        fn = {vecdir, "/raw10.hex"}; $readmemh(fn, raw_mem);
        fn = {vecdir, "/y8.hex"};    $readmemh(fn, y8_mem);
        fn = {vecdir, "/gauss.hex"}; $readmemh(fn, gau_mem);
        fn = {vecdir, "/he.hex"};    $readmemh(fn, he_mem);
        repeat (4) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);
        start = 1; @(negedge clk); start = 0;
        for (k = 0; k < NP; k = k + 1) begin
            raw_in = raw_mem[k][9:0]; raw_valid = 1; @(negedge clk);
        end
        raw_valid = 0;
        // 等待三路收满
        for (i = 0; i < 100000; i = i + 1) begin
            @(negedge clk);
            if (n_y8 >= NP && n_gau >= NP && n_he >= NP) i = 100000;
        end
        if (n_y8 < NP || n_gau < NP || n_he < NP) begin
            $display("ALGO_TB_FAIL short streams y8=%0d gau=%0d he=%0d of %0d", n_y8, n_gau, n_he, NP);
        end else if (errs != 0) begin
            $display("ALGO_TB_FAIL errors=%0d first_bad=%0d", errs, first_bad);
        end else begin
            $display("ALGO_TB_PASS pixels=%0d", NP);
        end
        $finish;
    end
    initial begin #20000000; $display("ALGO_TB_FAIL timeout y8=%0d gau=%0d he=%0d", n_y8, n_gau, n_he); $finish; end
endmodule
