// =============================================================================
//  pulse2toggle.v — 把某个时钟域里的脉冲转成翻转电平（1bit，便于跨时钟域同步）
//  用法：待测脉冲所在时钟域里例化，输出用两级同步器 + 边沿检测在目标域计数
// =============================================================================
`timescale 1ns / 1ps

module pulse2toggle (
    input  wire I_clk,
    input  wire I_rst_n,
    input  wire I_pulse,
    output reg  O_tgl
);
    reg r_d = 1'b0;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_d   <= 1'b0;
            O_tgl <= 1'b0;
        end else begin
            r_d <= I_pulse;
            if (I_pulse & ~r_d) O_tgl <= ~O_tgl;
        end
    end
endmodule
