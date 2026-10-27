`timescale 1ns/1ps
// **回放 stub —— 只用于验证测试台本身，不是算法实现，不可综合、不得进位流。**
//
// 它按 DUT 端口契约回放向量文件里的期望值。作用：
//   1) 证明 TB 的装载/驱动/顺序比对/超时逻辑可用；
//   2) 用 +define+STUB_MUTATE 注入一处错误，证明 TB 真的能报错（负对照）。
// 真正的算法 RTL 由主线实现后，把本文件从编译列表里换掉即可。
module image_algo_dut #(parameter W = 16, parameter H = 12) (
    input  wire       clk, rst_n, start,
    input  wire [9:0] raw_in,
    input  wire       raw_valid,
    input  wire       lut_we,
    input  wire [7:0] lut_addr, lut_data,
    output reg  [7:0] y8_out, gau_out, he_out,
    output reg        y8_valid, gau_valid, he_valid,
    output reg        busy
);
    localparam NP = W * H;
    reg [15:0] y8_mem[0:NP-1], gau_mem[0:NP-1], he_mem[0:NP-1];
    reg [1023:0] vecdir, fn;
    integer k;
    reg mutate;
    initial begin
        mutate = $test$plusargs("STUB_MUTATE");   // 运行时负对照开关
        if ($value$plusargs("VECDIR=%s", vecdir)) begin
            fn = {vecdir, "/y8.hex"};    $readmemh(fn, y8_mem);
            fn = {vecdir, "/gauss.hex"}; $readmemh(fn, gau_mem);
            fn = {vecdir, "/he.hex"};    $readmemh(fn, he_mem);
        end
        y8_out = 0; gau_out = 0; he_out = 0;
        y8_valid = 0; gau_valid = 0; he_valid = 0; busy = 0; k = 0;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y8_valid <= 0; gau_valid <= 0; he_valid <= 0; busy <= 0; k <= 0;
        end else begin
            y8_valid <= 0; gau_valid <= 0; he_valid <= 0;
            if (start) begin
                k <= 0; busy <= 1;
            end else if (busy) begin
                if (k < NP) begin
                    y8_out <= y8_mem[k][7:0]; y8_valid <= 1;
                    gau_out <= (mutate && (k == 5)) ? (gau_mem[k][7:0] ^ 8'h01) : gau_mem[k][7:0];
                    gau_valid <= 1;
                    he_out <= he_mem[k][7:0]; he_valid <= 1;
                    k <= k + 1;
                end else begin
                    busy <= 0;
                end
            end
        end
    end
endmodule
