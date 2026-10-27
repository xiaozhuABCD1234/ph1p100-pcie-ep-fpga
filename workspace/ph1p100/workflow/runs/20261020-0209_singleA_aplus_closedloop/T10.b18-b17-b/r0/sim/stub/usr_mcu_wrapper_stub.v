// T10.b18-b17-b structural stub of usr_mcu_wrapper (ports copied verbatim)
module usr_mcu_wrapper #(
    parameter MCU_TCM_INIT = "",
    parameter CLK_FREQ     = 100_000_000
) (
    input         i_clk,
    input         i_rst,
    output        o_apb_psel,
    output        o_apb_penable,
    output        o_apb_pwrite,
    output [31:0] o_apb_paddr,
    output [31:0] o_apb_pwdata,
    input  [31:0] i_apb_prdata,
    input         i_apb_pready,
    output        o_uart_txd,
    input         i_uart_rxd,
    output [31:0] o_gpio_w00,
    output [31:0] o_gpio_w04,
    output [31:0] o_gpio_w08,
    output [31:0] o_gpio_w0c,
    input  [31:0] i_gpio_r20,
    input  [31:0] i_gpio_r24,
    input  [31:0] i_gpio_r28,
    input  [31:0] i_gpio_r2c
);
    assign o_apb_psel = 1'b0;
    assign o_apb_penable = 1'b0;
    assign o_apb_pwrite = 1'b0;
    assign o_apb_paddr = 1'b0;
    assign o_apb_pwdata = 1'b0;
    assign o_uart_txd = 1'b0;
    assign o_gpio_w00 = 1'b0;
    assign o_gpio_w04 = 1'b0;
    assign o_gpio_w08 = 1'b0;
    assign o_gpio_w0c = 1'b0;
endmodule
