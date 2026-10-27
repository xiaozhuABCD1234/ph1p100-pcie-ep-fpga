
///////////////////////////////////////////////////////////////////////////////////////////////////
// mcu_system.v
///////////////////////////////////////////////////////////////////////////////////////////////////
// 0x8000_0000 : intr_ctrl (TODO)
// 0x9000_0000 : timer
// 0xA000_0000 : uart
// 0xB000_0000 : gpio
// 0xC000_0000 : iic (TODO)
// 0xD000_0000 : spi (TODO)
// 0xE000_0000 : ram (TODO)
// 0xF000_0000 : usr_apb


`timescale 1ps / 1ps

module usr_mcu_wrapper #(
    parameter MCU_TCM_INIT = "",
    parameter CLK_FREQ     = 100_000_000
)(
    input           i_clk         ,
    input           i_rst         ,

    output          o_apb_psel    ,
    output          o_apb_penable ,
    output          o_apb_pwrite  ,
    output  [31:0]  o_apb_paddr   ,
    output  [31:0]  o_apb_pwdata  ,
    input   [31:0]  i_apb_prdata  ,
    input           i_apb_pready  ,

    output          o_uart_txd    ,
    input           i_uart_rxd    ,

    output  [31:0]  o_gpio_w00    ,
    output  [31:0]  o_gpio_w04    ,
    output  [31:0]  o_gpio_w08    ,
    output  [31:0]  o_gpio_w0c    ,
    input   [31:0]  i_gpio_r20    ,
    input   [31:0]  i_gpio_r24    ,
    input   [31:0]  i_gpio_r28    ,
    input   [31:0]  i_gpio_r2c
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Local Parameters
///////////////////////////////////////////////////////////////////////////////////////////////////


///////////////////////////////////////////////////////////////////////////////////////////////////
// Internal Signals
///////////////////////////////////////////////////////////////////////////////////////////////////
wire          mst_apb_psel    ;
wire          mst_apb_penable ;
wire          mst_apb_pwrite  ;
wire  [31:0]  mst_apb_paddr   ;
wire  [31:0]  mst_apb_pwdata  ;
wire  [31:0]  mst_apb_prdata  ;
wire          mst_apb_pready  ;

wire  [ 7:0]  slv_apb_psel    ;
wire          slv_apb_penable ;
wire          slv_apb_pwrite  ;
wire  [31:0]  slv_apb_paddr   ;
wire  [31:0]  slv_apb_pwdata  ;
wire  [31:0]  slv_apb_prdata0 ;
wire  [31:0]  slv_apb_prdata1 ;
wire  [31:0]  slv_apb_prdata2 ;
wire  [31:0]  slv_apb_prdata3 ;
wire  [31:0]  slv_apb_prdata4 ;
wire  [31:0]  slv_apb_prdata5 ;
wire  [31:0]  slv_apb_prdata6 ;
wire  [31:0]  slv_apb_prdata7 ;
wire  [ 7:0]  slv_apb_pready  ;

///////////////////////////////////////////////////////////////////////////////////////////////////
// MCU_CORE
///////////////////////////////////////////////////////////////////////////////////////////////////
usr_mcu_core #(
    .MCU_TCM_INIT  ( MCU_TCM_INIT   )
)u_mcu_core (
    .i_clk         ( i_clk           ),
    .i_rst         ( i_rst           ),

    .i_apb_pready  ( mst_apb_pready  ),
    .o_apb_psel    ( mst_apb_psel    ),
    .o_apb_penable ( mst_apb_penable ),
    .o_apb_pwrite  ( mst_apb_pwrite  ),
    .o_apb_paddr   ( mst_apb_paddr   ),
    .o_apb_pwdata  ( mst_apb_pwdata  ),
    .i_apb_prdata  ( mst_apb_prdata  )
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// APB 1 to 8 Mux
///////////////////////////////////////////////////////////////////////////////////////////////////
usr_mcu_apb_decoder u_mcu_apb_decoder (
    .i_slv_apb_psel    ( mst_apb_psel     ), 
    .i_slv_apb_penable ( mst_apb_penable  ), 
    .i_slv_apb_pwrite  ( mst_apb_pwrite   ), 
    .i_slv_apb_paddr   ( mst_apb_paddr    ), 
    .i_slv_apb_pwdata  ( mst_apb_pwdata   ), 
    .o_slv_apb_prdata  ( mst_apb_prdata   ), 
    .o_slv_apb_pready  ( mst_apb_pready   ), 
    .o_slv_apb_pslverr (                  ), 

    .o_mst_apb_psel    ( slv_apb_psel     ), 
    .o_mst_apb_penable ( slv_apb_penable  ), 
    .o_mst_apb_pwrite  ( slv_apb_pwrite   ), 
    .o_mst_apb_paddr   ( slv_apb_paddr    ), 
    .o_mst_apb_pwdata  ( slv_apb_pwdata   ), 
    .i_mst_apb_prdata0 ( slv_apb_prdata0  ), 
    .i_mst_apb_prdata1 ( slv_apb_prdata1  ), 
    .i_mst_apb_prdata2 ( slv_apb_prdata2  ), 
    .i_mst_apb_prdata3 ( slv_apb_prdata3  ), 
    .i_mst_apb_prdata4 ( slv_apb_prdata4  ), 
    .i_mst_apb_prdata5 ( slv_apb_prdata5  ), 
    .i_mst_apb_prdata6 ( slv_apb_prdata6  ), 
    .i_mst_apb_prdata7 ( slv_apb_prdata7  ), 
    .i_mst_apb_pready  ( slv_apb_pready   ), 
    .i_mst_apb_pslverr ( 8'h00            )
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// APB Interrupt
///////////////////////////////////////////////////////////////////////////////////////////////////
assign slv_apb_pready[0] = 1'b1;
assign slv_apb_prdata0   = 32'h0;

///////////////////////////////////////////////////////////////////////////////////////////////////
// APB Timer
///////////////////////////////////////////////////////////////////////////////////////////////////
assign slv_apb_pready[1] = 1'b1;
assign slv_apb_prdata1   = 32'h0;

///////////////////////////////////////////////////////////////////////////////////////////////////
// APB UART
///////////////////////////////////////////////////////////////////////////////////////////////////
usr_mcu_apb_uart #(
    .CLK_FREQ  ( CLK_FREQ )
) u_mcu_apb_uart (
    .i_clk         ( i_clk               ), // input
    .i_rst         ( i_rst               ), // input
    .i_apb_psel    ( slv_apb_psel  [2]   ), // input
    .i_apb_penable ( slv_apb_penable     ), // input
    .i_apb_pwrite  ( slv_apb_pwrite      ), // input
    .i_apb_paddr   ( slv_apb_paddr [7:0] ), // input
    .i_apb_pwdata  ( slv_apb_pwdata      ), // input
    .o_apb_prdata  ( slv_apb_prdata2     ), // output
    .o_apb_pready  ( slv_apb_pready[2]   ), // output

    .i_uart_rxd    ( i_uart_rxd          ), // input
    .o_uart_txd    ( o_uart_txd          )  // output
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// APB GPIO
///////////////////////////////////////////////////////////////////////////////////////////////////
usr_mcu_apb_gpio u_mcu_apb_gpio (
    .i_clk          ( i_clk              ),
    .i_rst          ( i_rst              ),

    .i_apb_psel     ( slv_apb_psel  [3]  ), 
    .i_apb_penable  ( slv_apb_penable    ), 
    .i_apb_pwrite   ( slv_apb_pwrite     ), 
    .i_apb_paddr    ( slv_apb_paddr [7:0]), 
    .i_apb_pwdata   ( slv_apb_pwdata     ), 
    .o_apb_prdata   ( slv_apb_prdata3    ), 
    .o_apb_pready   ( slv_apb_pready[3]  ), 

    .o_reg_w_00     ( o_gpio_w00         ),
    .o_reg_w_04     ( o_gpio_w04         ),
    .o_reg_w_08     ( o_gpio_w08         ),
    .o_reg_w_0c     ( o_gpio_w0c         ),
    .o_reg_w_10     (                    ),
    .o_reg_w_14     (                    ),
    .o_reg_w_18     (                    ),
    .o_reg_w_1c     (                    ),
    .i_reg_r_20     ( i_gpio_r20         ),
    .i_reg_r_24     ( i_gpio_r24         ),
    .i_reg_r_28     ( i_gpio_r28         ),
    .i_reg_r_2c     ( i_gpio_r2c         ),
    .i_reg_r_30     ( 32'h2024_0705      ),
    .i_reg_r_34     ( 32'h2024_0706      ),
    .i_reg_r_38     ( 32'h2024_0707      ),
    .i_reg_r_3c     ( 32'h2024_0708      )
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// APB IIC
///////////////////////////////////////////////////////////////////////////////////////////////////
assign slv_apb_pready[4] = 1'b1;
assign slv_apb_prdata4   = 32'h0;

///////////////////////////////////////////////////////////////////////////////////////////////////
// APB SPI
///////////////////////////////////////////////////////////////////////////////////////////////////
assign slv_apb_pready[5] = 1'b1;
assign slv_apb_prdata5   = 32'h0;

///////////////////////////////////////////////////////////////////////////////////////////////////
// APB RAM
///////////////////////////////////////////////////////////////////////////////////////////////////
assign slv_apb_pready[6] = 1'b1;
assign slv_apb_prdata6   = 32'h0;

///////////////////////////////////////////////////////////////////////////////////////////////////
// APB User
///////////////////////////////////////////////////////////////////////////////////////////////////
assign  o_apb_psel    = slv_apb_psel  [7];
assign  o_apb_penable = slv_apb_penable  ;
assign  o_apb_pwrite  = slv_apb_pwrite   ;
assign  o_apb_paddr   = slv_apb_paddr    ;
assign  o_apb_pwdata  = slv_apb_pwdata   ;
assign  slv_apb_prdata7   = i_apb_prdata ;
assign  slv_apb_pready[7] = i_apb_pready ;

///////////////////////////////////////////////////////////////////////////////////////////////////
// END
///////////////////////////////////////////////////////////////////////////////////////////////////
endmodule
