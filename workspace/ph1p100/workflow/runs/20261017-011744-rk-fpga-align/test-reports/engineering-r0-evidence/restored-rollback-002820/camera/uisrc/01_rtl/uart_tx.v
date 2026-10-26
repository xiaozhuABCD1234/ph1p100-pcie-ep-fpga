// =============================================================================
//  uart_tx.v — 极简 UART 发送（8N1）
//  波特率 = I_clk / CLK_DIV；50MHz / 434 ≈ 115200
// =============================================================================
`timescale 1ns / 1ps

module uart_tx #(
    parameter CLK_DIV = 16'd434        // 50MHz / 434 ≈ 115200
)(
    input  wire       I_clk,
    input  wire       I_rst_n,
    input  wire [7:0] I_data,
    input  wire       I_valid,         // 单周期脉冲，O_busy=0 时才接受
    output wire       O_txd,           // 空闲为高
    output reg        O_busy
);

    reg [15:0] r_div   = 16'd0;
    reg [3:0]  r_bit   = 4'd0;
    reg [9:0]  r_shift = 10'h3FF;
    reg        r_run   = 1'b0;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_run   <= 1'b0;
            r_bit   <= 4'd0;
            r_div   <= 16'd0;
            O_busy  <= 1'b0;
            r_shift <= 10'h3FF;
        end else begin
            if (!r_run) begin
                O_busy <= 1'b0;
                if (I_valid) begin
                    r_shift <= {1'b1, I_data, 1'b0};   // 停止位 + 8 数据 + 起始位
                    r_run   <= 1'b1;
                    r_bit   <= 4'd0;
                    r_div   <= 16'd0;
                    O_busy  <= 1'b1;
                end
            end else begin
                if (r_div == CLK_DIV - 1) begin
                    r_div   <= 16'd0;
                    r_shift <= {1'b1, r_shift[9:1]};
                    if (r_bit == 4'd9) begin
                        r_run  <= 1'b0;
                        O_busy <= 1'b0;
                    end else begin
                        r_bit <= r_bit + 1'b1;
                    end
                end else begin
                    r_div <= r_div + 1'b1;
                end
            end
        end
    end

    assign O_txd = r_run ? r_shift[0] : 1'b1;

endmodule
