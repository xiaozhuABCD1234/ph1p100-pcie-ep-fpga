// =============================================================================
//  clk_activity.v — 由某个时钟域产生一个慢速翻转电平，供另一个（慢）时钟域测频
//  用途：不用跨域多比特计数器，也能量出该时钟"活没活"以及大致频率
//    O_tgl 翻转频率 = I_clk / (2 * 2^DIV_BITS)
//    目标域数每 0.5s 的跳变次数 N → 源时钟 ≈ N * 2 * 2^DIV_BITS / 0.5
// =============================================================================
`timescale 1ns / 1ps

module clk_activity #(
    parameter DIV_BITS = 15
)(
    input  wire I_clk,          // 被测量的时钟
    input  wire I_rst_n,
    output reg  O_tgl
);
    reg [DIV_BITS-1:0] r_cnt = {DIV_BITS{1'b0}};

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_cnt <= {DIV_BITS{1'b0}};
            O_tgl <= 1'b0;
        end else begin
            if (&r_cnt) begin
                r_cnt <= {DIV_BITS{1'b0}};
                O_tgl <= ~O_tgl;
            end else begin
                r_cnt <= r_cnt + 1'b1;
            end
        end
    end
endmodule
