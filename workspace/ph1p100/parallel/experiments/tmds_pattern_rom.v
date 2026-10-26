`timescale 1ns/1ps
// 闪点受控实验：TMDS 码级图样 ROM（**实验件，不是生产 RTL**）。
//
// 作用：从 ROM 读出已知的 40bit {clk,ch2,ch1,ch0} 码字，直接喂给明文
// `hdmi_tx_phy_wrapper`，**绕过加密的 TMDS 编码核**，从而在物理层发出可控激励。
//
// 位序约定（与 gen_rom.py 一致，别搞反）：
//   ROM 里存的是 **位反转后**的字段；wrapper + lane 各反转一次，净效果是
//   **线上先发 ROM 字的 bit0**，也就是自然码的 bit9（TMDS 符号 MSB）。
//
// 使用前必须：走项目工作流 5.1 节候选交付检查、独立存放、并取得上板授权。
module tmds_pattern_rom #(
    parameter DEPTH = 20,
    parameter INIT_FILE = "pattern_rom.hex"
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       enable,
    output wire [9:0] ch0,
    output wire [9:0] ch1,
    output wire [9:0] ch2,
    output wire [9:0] clk_ch,
    output reg  [15:0] index
);
    reg [39:0] mem[0:DEPTH-1];
    reg [15:0] addr;

    initial begin
        $readmemh(INIT_FILE, mem);
    end

    assign {clk_ch, ch2, ch1, ch0} = mem[addr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr  <= 16'd0;
            index <= 16'd0;
        end else if (enable) begin
            addr  <= (addr == DEPTH - 1) ? 16'd0 : addr + 16'd1;
            index <= addr;
        end
    end
endmodule
