
`timescale 1ps/1ps

`define USR_MCU_ROM_INIT "D:/TD/work/csi2/prj/camera_ddr_display_20261012_003550/vendor/rtl/usr_mcu_srcs/mcu_rom/mcu_rom.txt"

module camera_ddr_display_top#(
    parameter DX_NUM     = 4 ,
    parameter CS_WIDTH   = 1 ,
    parameter CKE_WIDTH  = 1 ,
    parameter ODT_WIDTH  = 1 ,
    parameter BA_WIDTH   = 3 ,
    parameter BG_WIDTH   = 0 ,
    parameter COL_WIDTH  = 10,
    parameter ROW_WIDTH  = 14

)(

    input                         sys_rst_n     ,
    input                         sys_clk50m       ,
    output                        O_uart_txd  ,
    input                         usr_uart_rxd  ,
    output [              3 : 0]  O_led           ,
    
    // ddrio
    output                      ddr_ck_p      ,
    output                      ddr_ck_n      ,
    output                      ddr_reset_n   ,
    output  [CKE_WIDTH -1 : 0]  ddr_cke       ,
    output  [ODT_WIDTH -1 : 0]  ddr_odt       ,
    output  [CS_WIDTH  -1 : 0]  ddr_cs_n      ,
    output                      ddr_ras_n     ,
    output                      ddr_cas_n     ,
    output                      ddr_we_n      ,
    output  [BA_WIDTH  -1 : 0]  ddr_ba        ,
    output  [ROW_WIDTH -1 : 0]  ddr_addr      ,
    inout   [DX_NUM    -1 : 0]  ddr_dqs_p     ,
    inout   [DX_NUM    -1 : 0]  ddr_dqs_n     ,
    inout   [DX_NUM  *8-1 : 0]  ddr_dq        ,
    inout   [DX_NUM    -1 : 0]  ddr_dm,
    input  wire         mipi_a_clk_hs_p,
    input  wire         mipi_a_clk_hs_n,
    input  wire [3:0]   mipi_a_data_hs_p,
    input  wire [3:0]   mipi_a_data_hs_n,
    input  wire         mipi_b_clk_hs_p,
    input  wire         mipi_b_clk_hs_n,
    input  wire [3:0]   mipi_b_data_hs_p,
    input  wire [3:0]   mipi_b_data_hs_n,
    output wire         cam_a_scl,
    inout  wire         cam_a_sda,
    output wire         cam_a_mclk,
    output wire         cam_a_xclr_n,
    output wire         cam_b_scl,
    inout  wire         cam_b_sda,
    output wire         cam_b_mclk,
    output wire         cam_b_xclr_n,
    output wire         O_hdmi_clk_p,
    output wire [2:0]   O_hdmi_tx_p
);
//**************************************************************************//
// Logic Signals Definition
//**************************************************************************//
wire         usr_apb_pclk     ;
wire         usr_apb_prst_n   ;
wire         usr_apb_pready   ;
wire         usr_apb_psel     ;
wire         usr_apb_penable  ;
wire         usr_apb_pwrite   ;
wire  [31:0] usr_apb_paddr    ;
wire  [31:0] usr_apb_pwdata   ;
wire  [31:0] usr_apb_prdata   ;

//**************************************************************************//
// DDRPHY Example Top
//**************************************************************************//
ddrmc_display_top #(
    .DX_NUM           ( DX_NUM           ),
    .CS_WIDTH         ( CS_WIDTH         ),
    .CKE_WIDTH        ( CKE_WIDTH        ),
    .ODT_WIDTH        ( ODT_WIDTH        ),
    .BA_WIDTH         ( BA_WIDTH         ),
    .BG_WIDTH         ( BG_WIDTH         ),
    .COL_WIDTH        ( COL_WIDTH        ),
    .ROW_WIDTH        ( ROW_WIDTH        )
) u_ddrmc_test_top (
    // clock & reset
    .ref_clk         ( sys_clk50m           ), // input
    .cfg_clk         ( usr_apb_pclk      ), // output

    .sys_rst_n       ( sys_rst_n         ), // input
    .ddrphy_rst_n    ( usr_apb_prst_n    ), // output

    // APB
    .usr_apb_pclk    ( usr_apb_pclk      ),
    .usr_apb_preset_n( usr_apb_prst_n    ),
    .usr_apb_psel    ( usr_apb_psel      ),
    .usr_apb_penable ( usr_apb_penable   ),
    .usr_apb_pwrite  ( usr_apb_pwrite    ),
    .usr_apb_paddr   ( usr_apb_paddr     ),
    .usr_apb_pwdata  ( usr_apb_pwdata    ),
    .usr_apb_pready  ( usr_apb_pready    ), // output
    .usr_apb_prdata  ( usr_apb_prdata    ), // output

    // ddrio
    .ddr_ck_p        ( ddr_ck_p          ),
    .ddr_ck_n        ( ddr_ck_n          ),
    .ddr_reset_n     ( ddr_reset_n       ),
    .ddr_cke         ( ddr_cke           ),
    .ddr_odt         ( ddr_odt           ),
    .ddr_cs_n        ( ddr_cs_n          ),
    .ddr_ras_n       ( ddr_ras_n         ),
    .ddr_cas_n       ( ddr_cas_n         ),
    .ddr_we_n        ( ddr_we_n          ),
    .ddr_ba          ( ddr_ba            ),
    .ddr_addr        ( ddr_addr          ),
    .ddr_dqs_p       ( ddr_dqs_p         ),
    .ddr_dqs_n       ( ddr_dqs_n         ),
    .ddr_dq          ( ddr_dq            ),
    .ddr_dm          ( ddr_dm            ),

 .display_pclk(display_pclk),.display_rst_n(display_rst_n),.display_vs(display_vs),.display_hs(display_hs),.display_de(display_de),
 .ddr_rgb(ddr_rgb),.ddr_vs(ddr_vs),.ddr_hs(ddr_hs),.ddr_de(ddr_de),
    .cap_clk(cap_clk),.cap_sof(cap_sof),.cap_valid(cap_valid),.cap_last(cap_last),.cap_data(cap_data),
    .led             ( O_led[2:0]        )
);

//**************************************************************************//
// MCU
//**************************************************************************//
wire  [31:0] o_reg_w_00;
wire  [31:0] o_reg_w_04;
wire  [31:0] o_reg_w_08;
wire  [31:0] o_reg_w_0c;
wire  [31:0] i_reg_r_20;
wire  [31:0] i_reg_r_24;
wire  [31:0] i_reg_r_28;
wire  [31:0] i_reg_r_2c;

`ifndef PH1P_MIS_SIM_SKIP_MCU
usr_mcu_wrapper #(
    .MCU_TCM_INIT  (`USR_MCU_ROM_INIT), 
    .CLK_FREQ      (50_000_000       )
)u_usr_mcu_wrapper(
    .i_clk         ( usr_apb_pclk    ),
    .i_rst         ( !usr_apb_prst_n ),

    .o_apb_psel    ( usr_apb_psel    ),
    .o_apb_penable ( usr_apb_penable ),
    .o_apb_pwrite  ( usr_apb_pwrite  ),
    .o_apb_paddr   ( usr_apb_paddr   ),
    .o_apb_pwdata  ( usr_apb_pwdata  ),
    .i_apb_prdata  ( usr_apb_prdata  ),
    .i_apb_pready  ( usr_apb_pready  ),

    .o_uart_txd    ( O_uart_txd    ),
    .i_uart_rxd    ( usr_uart_rxd    ),

    .o_gpio_w00    ( o_reg_w_00      ),
    .o_gpio_w04    ( o_reg_w_04      ),
    .o_gpio_w08    ( o_reg_w_08      ),
    .o_gpio_w0c    ( o_reg_w_0c      ),
    .i_gpio_r20    ( i_reg_r_20      ),
    .i_gpio_r24    ( i_reg_r_24      ),
    .i_gpio_r28    ( i_reg_r_28      ),
    .i_gpio_r2c    ( i_reg_r_2c      )
);
`else
assign usr_apb_psel     =  1'b0;
assign usr_apb_penable  =  1'b0;
assign usr_apb_pwrite   =  1'b0;
assign usr_apb_paddr    = 32'h0;
assign usr_apb_pwdata   = 32'h0;
`endif

assign  i_reg_r_20  = 32'h20240401;
assign  i_reg_r_24  = 32'h20240402;
assign  i_reg_r_28  = 32'h20240403;
assign  i_reg_r_2c  = 32'h20240404;




wire display_pclk,display_rst_n,display_vs,display_hs,display_de;
wire[23:0] ddr_rgb;wire ddr_vs,ddr_hs,ddr_de;
wire cap_clk,cap_sof,cap_valid,cap_last;wire[7:0] cap_data;wire[3:0] camera_led;wire camera_uart;
f9p_camera_display_core u_camera(
 .sys_clk50m(sys_clk50m),
 .mipi_a_clk_hs_p(mipi_a_clk_hs_p),
 .mipi_a_clk_hs_n(mipi_a_clk_hs_n),
 .mipi_a_data_hs_p(mipi_a_data_hs_p),
 .mipi_a_data_hs_n(mipi_a_data_hs_n),
 .mipi_b_clk_hs_p(mipi_b_clk_hs_p),
 .mipi_b_clk_hs_n(mipi_b_clk_hs_n),
 .mipi_b_data_hs_p(mipi_b_data_hs_p),
 .mipi_b_data_hs_n(mipi_b_data_hs_n),
 .cam_a_scl(cam_a_scl),
 .cam_a_sda(cam_a_sda),
 .cam_a_mclk(cam_a_mclk),
 .cam_a_xclr_n(cam_a_xclr_n),
 .cam_b_scl(cam_b_scl),
 .cam_b_sda(cam_b_sda),
 .cam_b_mclk(cam_b_mclk),
 .cam_b_xclr_n(cam_b_xclr_n),
 .O_hdmi_clk_p(O_hdmi_clk_p),
 .O_hdmi_tx_p(O_hdmi_tx_p),
 .display_pclk(display_pclk),.display_rst_n(display_rst_n),.display_vs(display_vs),.display_hs(display_hs),.display_de(display_de),
 .ddr_rgb(ddr_rgb),.ddr_vs(ddr_vs),.ddr_hs(ddr_hs),.ddr_de(ddr_de),
 .O_led(camera_led),.O_uart_txd(camera_uart),.cap_clk(cap_clk),.cap_sof(cap_sof),.cap_valid(cap_valid),.cap_last(cap_last),.cap_data(cap_data));
assign O_led[3]=~camera_led[0];
endmodule
