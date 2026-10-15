//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2022 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : pcie_subsystem_tb.v
//  Author        : Gehong - hong.ge@anlogic.com
//  Last Modified : 2023-12-26 11:03:21
//  Create        : 2022-05-15 10:28:21
//  Description   : 
//   
///////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module  pcie_subsystem_tb();


`include "PCIE_REG_TABLE.v"
`include "BDF.v"
`include "ph1p_pcie_case_param.v"
// ====================================================================
// Parameter/wire/reg
// ====================================================================

    parameter integer   REF_CLK_PERIOD_PMM_PLUSE    = 100.0003 ;
    parameter integer   REF_CLK_PERIOD_PMM_MINUS    =  99.9997 ;
    integer             i;

    reg                 rc_ref_clk          ;
    reg                 ep_ref_clk          ;

    reg                 sys_clk_rc          ;
    reg                 sys_clk_ep          ;
    reg     [8:0]       tl_clk_user_freq    ;
    reg                 pcie_power_on_rst   ;
    reg                 user_int_trigger    ;
    wire                rc_ref_pad_clk_p    ;
    wire                rc_ref_pad_clk_n    ;
    wire                ep_ref_pad_clk_p    ;
    wire                ep_ref_pad_clk_n    ;
    wire    [3:0]       pcie_rc_rx_p        ;
    wire    [3:0]       pcie_rc_rx_n        ;
    wire    [3:0]       pcie_rc_tx_p        ;
    wire    [3:0]       pcie_rc_tx_n        ;
    
    wire    [3:0]       pcie_ep_rx_p        ;
    wire    [3:0]       pcie_ep_rx_n        ;
    wire    [3:0]       pcie_ep_tx_p        ;
    wire    [3:0]       pcie_ep_tx_n        ;

    wire    [7:0]       debug_led_rc        ;
    wire    [7:0]       debug_led_ep        ;
    wire                tb_uart_tx_en       ;
    wire    [7:0]       tb_uart_tx_data     ;
    wire                tb_uart_rx_en       ;
    wire    [7:0]       tb_uart_rx_data     ;
    wire                tb_uart_rx_ready    ;
    wire                rxd                 ;
    wire                txd                 ;

    // tmp registers
   reg     [31:0]      cfg0w_data           ;
   reg     [31:0]      cfg0r_data           ;
   reg     [31:0]      tmp_cfg0w_data       ;
   reg     [31:0]      tmp_cfg0r_data       ;
   reg     [31:0]      tmp_iow_data         ;
   reg     [31:0]      tmp_ior_data         ;
   reg     [31:0]      tmp_memw_data        ;
   reg     [31:0]      tmp_memr_data        ;

    // RC side 
    reg                tb_rc_tl_clk_user    ;
    reg                tb_ep_tl_clk_user    ;
    reg    [15:0]      tb_tl_ep_bdf         ;
    reg                tb_ubus_bridge_idle  ;
    reg                tb_ubus_wen          ;
    reg    [31:0]      tb_ubus_waddr        ;
    reg    [31:0]      tb_ubus_wdata        ;
    reg                tb_ubus_ren          ;
    reg    [31:0]      tb_ubus_raddr        ;
    reg                tb_ubus_bken         ;
    reg    [31:0]      tb_ubus_rdata        ;

// ====================================================================
// TestBench Clock Gen
// ====================================================================
initial begin
    rc_ref_clk = 1'b0;
    forever begin
        #(((1000000000/100003)/2)*1ps);
        rc_ref_clk = ~rc_ref_clk;
    end
end

initial begin
    ep_ref_clk = 1'b0;
    forever begin
        #(((1000000000/99997)/2)*1ps);
        ep_ref_clk = ~ep_ref_clk;
    end
end


initial begin
    sys_clk_rc       = 1'b0;
    forever begin
        #(((1000000/25)/2)*1ps);
        sys_clk_rc   = ~sys_clk_rc;
    end
end 

initial begin
    sys_clk_ep       = 1'b0;
    forever begin
        #(((1000000/25)/2)*1ps);
        sys_clk_ep   = ~sys_clk_ep;
    end
end 

initial begin 
    pcie_power_on_rst = 1'b0;
    #6000;
    pcie_power_on_rst = 1'b1;
end

// ====================================================================
// TestBench Serdes Lane and Clock 
// ====================================================================
assign  rc_ref_pad_clk_p   =  rc_ref_clk;
assign  rc_ref_pad_clk_n   = ~rc_ref_clk;
assign  ep_ref_pad_clk_p   =  ep_ref_clk;
assign  ep_ref_pad_clk_n   = ~ep_ref_clk;

// Separate each lane for lane flip
assign  pcie_rc_rx_p[0] = pcie_ep_tx_p[0];
assign  pcie_rc_rx_n[0] = pcie_ep_tx_n[0];
assign  pcie_rc_rx_p[1] = pcie_ep_tx_p[1];
assign  pcie_rc_rx_n[1] = pcie_ep_tx_n[1];
assign  pcie_rc_rx_p[2] = pcie_ep_tx_p[2];
assign  pcie_rc_rx_n[2] = pcie_ep_tx_n[2];
assign  pcie_rc_rx_p[3] = pcie_ep_tx_p[3];
assign  pcie_rc_rx_n[3] = pcie_ep_tx_n[3];

assign  pcie_ep_rx_p[0] = pcie_rc_tx_p[0];
assign  pcie_ep_rx_n[0] = pcie_rc_tx_n[0];
assign  pcie_ep_rx_p[1] = pcie_rc_tx_p[1];
assign  pcie_ep_rx_n[1] = pcie_rc_tx_n[1];
assign  pcie_ep_rx_p[2] = pcie_rc_tx_p[2];
assign  pcie_ep_rx_n[2] = pcie_rc_tx_n[2];
assign  pcie_ep_rx_p[3] = pcie_rc_tx_p[3];
assign  pcie_ep_rx_n[3] = pcie_rc_tx_n[3];

glbl glbl();
PH1P_PHY_GSR PH1P_PHY_GSR();

// ====================================================================
// RC Inst 
// ====================================================================
ph1p_pcie_rc_top u_ph1p_pcie_rc_top (
    // serdes high speed pin
    .ref_pad_clk_p                           (rc_ref_pad_clk_p              ),
    .ref_pad_clk_n                           (rc_ref_pad_clk_n              ),
    .pcie_rx_p                               (pcie_rc_rx_p                  ),
    .pcie_rx_n                               (pcie_rc_rx_n                  ),
    .pcie_tx_p                               (pcie_rc_tx_p                  ),
    .pcie_tx_n                               (pcie_rc_tx_n                  ),
    .sys_clk                                 (sys_clk_rc                    ),
    
    // pcie ip reset
    .pcie_power_on_rst                       (pcie_power_on_rst             ),
    .pcie_mperst                             (pcie_mperst                   ),
    .debug_led                               (debug_led_rc                  ),
    .txd                                     (txd                           ),
    .rxd                                     (rxd                           )
);

// ====================================================================
// EP Inst 
// ====================================================================
ph1p_pcie_ep_top  u_ph1p_pcie_ep_top  (
    // serdes high speed pin
    .ref_pad_clk_p                           (ep_ref_pad_clk_p              ),
    .ref_pad_clk_n                           (ep_ref_pad_clk_n              ),
    .pcie_rx_p                               (pcie_ep_rx_p                  ),
    .pcie_rx_n                               (pcie_ep_rx_n                  ),
    .pcie_tx_p                               (pcie_ep_tx_p                  ),
    .pcie_tx_n                               (pcie_ep_tx_n                  ),
    .sys_clk                                 (sys_clk_ep                    ),
    .user_int_trigger                        (user_int_trigger              ),
    // pcie ip reset
    .pcie_power_on_rst                       (pcie_power_on_rst             ),
    .pcie_mperst                             (pcie_mperst                   ),
    .txd                                     (txd                           ),
    .rxd                                     (1'b0                          ),
    .debug_led                               (debug_led_ep                  )
);

// ====================================================================
// TestBench Control Signal :
// Control the ubus of RC instead of whole uart module to reduce
// simulation time
// ====================================================================

initial begin 
    tb_rc_tl_clk_user                            = 'd0;
    tb_tl_ep_bdf                                 = `EP_PF0_BDF;
    user_int_trigger                             = 1'b1;
    tb_ubus_wen                                  = 'd0;
    tb_ubus_waddr                                = 'd0;
    tb_ubus_wdata                                = 'd0;
    tb_ubus_ren                                  = 'd0;
    tb_ubus_raddr                                = 'd0;
    tb_ubus_bken                                 = 'd0;
    tb_ubus_rdata                                = 'd0;

    force   u_ph1p_pcie_rc_top.tl_ep_bdf         = tb_tl_ep_bdf;
    force   tb_rc_tl_clk_user                    = u_ph1p_pcie_rc_top.tl_clk_user   ;
    force   tb_ep_tl_clk_user                    = u_ph1p_pcie_ep_top.tl_clk_user   ;
    force   u_ph1p_pcie_rc_top.ubus_pcie_wen      = tb_ubus_wen  ;
    force   u_ph1p_pcie_rc_top.ubus_pcie_waddr    = tb_ubus_waddr;
    force   u_ph1p_pcie_rc_top.ubus_pcie_wdata    = tb_ubus_wdata;
    force   u_ph1p_pcie_rc_top.ubus_pcie_ren      = tb_ubus_ren  ;
    force   u_ph1p_pcie_rc_top.ubus_pcie_raddr    = tb_ubus_raddr;
    force   tb_ubus_bken                         = u_ph1p_pcie_rc_top.ubus_pcie_bken ;
    force   tb_ubus_rdata                        = u_ph1p_pcie_rc_top.ubus_pcie_rdata;
     
end

initial begin 

    cfg0w_data                = 'd0;
    cfg0r_data                = 'd0;
    tmp_cfg0w_data            = 'd0;
    tmp_cfg0r_data            = 'd0;

    wait(!u_ph1p_pcie_rc_top.tl_rst_user);
    $display("tb info : ph1p pcie rc and ep are link up" );
    #((1_000_000)*1ps);

    pcie_apb4_read(32'h4090,tmp_cfg0r_data);
    $display("tb info : Link speed : Gen%h " , tmp_cfg0r_data[19:16]  );
    $display("tb info : Link width : X%h   " , tmp_cfg0r_data[23:20]  );

    pcie_apb4_read(32'h4004 ,  tmp_cfg0r_data);
    pcie_apb4_write(32'h4004, {tmp_cfg0r_data[31:3],3'b110});
    $display("tb info : Set rc bus master and mem space enable in command register "   );

    cfg0r(`EP_DEVICE_ID_VENDOR_ID_REG , tmp_cfg0r_data    );
    $display("tb info : rc read back ep vendor id : %h device id : %h " , tmp_cfg0r_data[15:0], tmp_cfg0r_data[31:16]);

    cfg0r(`EP_STATUS_COMMAND_REG      , tmp_cfg0r_data       );
    tmp_cfg0w_data  = tmp_cfg0r_data | 32'h7;    // enable ep side io / mem / bus master    
    cfg0w(`EP_STATUS_COMMAND_REG      , tmp_cfg0w_data       );
    cfg0r(`EP_STATUS_COMMAND_REG      , tmp_cfg0r_data       );
    $display("tb info : rc config ep command register : %h " , tmp_cfg0r_data[31:0]);

    // BAR0 has already define as 32bit memory bar
    cfg0w(`EP_BAR0_REG                , 32'hffffffff       );
    cfg0r(`EP_BAR0_REG                , tmp_cfg0r_data     );
    if(tmp_cfg0r_data[0] == 1'b0 && tmp_cfg0r_data[2:1] == 2'b00) begin
    $display("tb info : bar0 is 32bit memory bar  " );
    //$display("tb info : bar0 size is %h byte" , bit32_bar_size(tmp_cfg0r_data));
    cfg0w(`EP_BAR0_REG                , `ADDR_BAR0_BA      );
    cfg0r(`EP_BAR0_REG                , tmp_cfg0r_data     );
    $display("tb info : bar0 assign address is %h " , {tmp_cfg0r_data[31:4],4'b0}     );
    end

    // BAR1 has already define as 32bit io bar
    cfg0w(`EP_BAR1_REG                , 32'hffffffff       );
    cfg0r(`EP_BAR1_REG                , tmp_cfg0r_data     );
    if(tmp_cfg0r_data[0] == 1'b1 ) begin
    $display("tb info : bar1 is 32bit io bar  " );
    cfg0w(`EP_BAR1_REG                , `ADDR_BAR1_BA      );
    cfg0r(`EP_BAR1_REG                , tmp_cfg0r_data     );
    $display("tb info : bar1 assign address is %h " , {tmp_cfg0r_data[31:2],2'b0});
    end

    // BAR2 has already define as 64bit memory bar
    cfg0w(`EP_BAR2_REG                , 32'hffffffff       );
    cfg0r(`EP_BAR2_REG                , tmp_cfg0r_data     );
    cfg0w(`EP_BAR3_REG                , 32'hffffffff       );
    cfg0r(`EP_BAR3_REG                , tmp_cfg0w_data     );
    if(tmp_cfg0r_data[0] == 1'b0 && tmp_cfg0r_data[2:1] == 2'b10) begin
    $display("tb info : bar2 is 64bit memory bar  ");
    //$display("tb info : bar2 size is %h byte" , bit64_bar_size({tmp_cfg0w_data, tmp_cfg0r_data}));
    cfg0w(`EP_BAR2_REG                , `ADDR_BAR2_BA      );
    cfg0w(`EP_BAR3_REG                , `ADDR_BAR3_BA      );
    cfg0r(`EP_BAR2_REG                , tmp_cfg0r_data     );
    cfg0r(`EP_BAR3_REG                , tmp_cfg0w_data     );
    $display("tb info : bar2 assign address is %h " , {tmp_cfg0w_data[31:0],tmp_cfg0r_data[31:4],4'b0});
    end

    // BAR4 has already define as 64bit memory bar. used for interrupt only
    cfg0w(`EP_BAR4_REG                , 32'hffffffff       );
    cfg0r(`EP_BAR4_REG                , tmp_cfg0r_data     );
    cfg0w(`EP_BAR5_REG                , 32'hffffffff       );
    cfg0r(`EP_BAR5_REG                , tmp_cfg0w_data     );
    if(tmp_cfg0r_data[0] == 1'b0 && tmp_cfg0r_data[2:1] == 2'b10) begin
    $display("tb info : bar4 is 64bit memory bar  ");
    //$display("tb info : bar4 size is %h byte" , bit64_bar_size({tmp_cfg0w_data, tmp_cfg0r_data}));
    cfg0w(`EP_BAR4_REG                , `ADDR_BAR4_BA      );
    cfg0w(`EP_BAR5_REG                , `ADDR_BAR5_BA      );
    cfg0r(`EP_BAR4_REG                , tmp_cfg0r_data     );
    cfg0r(`EP_BAR5_REG                , tmp_cfg0w_data     );
    $display("tb info : bar4 assign address is %h " , {tmp_cfg0w_data[31:0],tmp_cfg0r_data[31:4],4'b0});
    end
    
    // rc set ep mps and mrrs
    cfg0r(`ADDR_PF_PCIE_CAP + `DEVICE_CAPABILITIES_REG , tmp_cfg0r_data     );
    $display("tb info : ep msp support is  %d " ,( 16'd128 << tmp_cfg0r_data[2:0]) );
    cfg0r(`ADDR_PF_PCIE_CAP + `DEVICE_CONTROL_DEVICE_STATUS , tmp_cfg0r_data     );

    cfg0w( `ADDR_PF_PCIE_CAP + `DEVICE_CONTROL_DEVICE_STATUS , { tmp_cfg0r_data[31:15] ,3'b101, tmp_cfg0r_data[11:8] ,3'b101, tmp_cfg0r_data[4:0] });
    $display("tb info : rc set ep msp  is  %d " , ( 16'd128 << 3'b101 ));
    $display("tb info : rc set ep mrrs is  %d " , ( 16'd128 << 3'b101 ));
    
    // rc set self mps and mrrs
    pcie_apb4_read(32'h4088,tmp_cfg0r_data);
    pcie_apb4_write(32'h4088,{ tmp_cfg0r_data[31:15] ,3'b101, tmp_cfg0r_data[11:8] ,3'b101, tmp_cfg0r_data[4:0] });
    $display("tb info : rc set self msp  is  %d " , ( 16'd128 << 3'b101 ));
    $display("tb info : rc set self mrrs is  %d " , ( 16'd128 << 3'b101 ));

    // rc set ep rcb
    cfg0r( `ADDR_PF_PCIE_CAP + `LINK_CONTROL_LINK_STATUS_REG  , tmp_cfg0r_data     );
    cfg0w( `ADDR_PF_PCIE_CAP + `LINK_CONTROL_LINK_STATUS_REG  , { tmp_cfg0r_data[31:4] ,1'b1, tmp_cfg0r_data[2:0] });
    $display("tb info : rc set ep rcb  is 1'b1 " );
    //usermode 1dw
    memwr_user({32'h0        ,`ADDR_BAR0_BA}, 32'h0, 13'd4);
    memrd_user({32'h0        ,`ADDR_BAR0_BA}, tmp_memr_data[31:0], 13'd4);
    //usermode 2dw
    memwr_user({32'h0        ,`ADDR_BAR0_BA}, 32'h0, 13'd8);
    memrd_user({32'h0        ,`ADDR_BAR0_BA}, tmp_memr_data[31:0], 13'd8);
    //usermode 4dw
    memwr_user({`ADDR_BAR3_BA,`ADDR_BAR2_BA}, 32'h0, 13'd16);
    memrd_user({`ADDR_BAR3_BA,`ADDR_BAR2_BA}, tmp_memr_data[31:0], 13'd16);
    //usermode 8dw
    memwr_user({`ADDR_BAR3_BA,`ADDR_BAR2_BA}, 32'h0, 13'd32);
    memrd_user({`ADDR_BAR3_BA,`ADDR_BAR2_BA}, tmp_memr_data[31:0], 13'd32);
    //usermode 16dw
    memwr_user({`ADDR_BAR5_BA,`ADDR_BAR4_BA}, 32'h0, 13'd64);
    memrd_user({`ADDR_BAR5_BA,`ADDR_BAR4_BA}, tmp_memr_data[31:0], 13'd64);
    //usermode 32dw
    memwr_user({`ADDR_BAR5_BA,`ADDR_BAR4_BA}, 32'h0, 13'd128);
    memrd_user({`ADDR_BAR5_BA,`ADDR_BAR4_BA}, tmp_memr_data[31:0], 13'd128);

    //prbsmode 1dw
    memwr_prbs({32'h0        ,`ADDR_BAR0_BA}, 32'h0, 13'd4);
    memrd_prbs({32'h0        ,`ADDR_BAR0_BA}, tmp_memr_data[31:0], 13'd4);
    //prbsmode 2dw
    memwr_prbs({32'h0        ,`ADDR_BAR0_BA}, 32'h0, 13'd8);
    memrd_prbs({32'h0        ,`ADDR_BAR0_BA}, tmp_memr_data[31:0], 13'd8);
    //prbsmode 4dw
    memwr_prbs({32'h0        ,`ADDR_BAR0_BA}, 32'h0, 13'd16);
    memrd_prbs({32'h0        ,`ADDR_BAR0_BA}, tmp_memr_data[31:0], 13'd16);
    //prbsmode 8dw
    memwr_prbs({32'h0        ,`ADDR_BAR0_BA}, 32'h0, 13'd32);
    memrd_prbs({32'h0        ,`ADDR_BAR0_BA}, tmp_memr_data[31:0], 13'd32);
    //prbsmode 16dw
    memwr_prbs({32'h0        ,`ADDR_BAR0_BA}, 32'h0, 13'd64);
    memrd_prbs({32'h0        ,`ADDR_BAR0_BA}, tmp_memr_data[31:0], 13'd64);
    //prbsmode 32dw
    memwr_prbs({32'h0        ,`ADDR_BAR0_BA}, 32'h0, 13'd128);
    memrd_prbs({32'h0        ,`ADDR_BAR0_BA}, tmp_memr_data[31:0], 13'd128);
    //prbsmode 64dw
    memwr_prbs({32'h0        ,`ADDR_BAR0_BA}, 32'h0, 13'd256);
    memrd_prbs({32'h0        ,`ADDR_BAR0_BA}, tmp_memr_data[31:0], 13'd256);
    //prbsmode 128dw
    memwr_prbs({32'h0        ,`ADDR_BAR0_BA}, 32'h0, 13'd512);
    memrd_prbs({32'h0        ,`ADDR_BAR0_BA}, tmp_memr_data[31:0], 13'd512);
    //prbsmode 256dw
    memwr_prbs({`ADDR_BAR3_BA,`ADDR_BAR2_BA}, 32'h0, 13'd1024);
    memrd_prbs({`ADDR_BAR3_BA,`ADDR_BAR2_BA}, tmp_memr_data[31:0], 13'd1024);
    //prbsmode 512dw
    memwr_prbs({`ADDR_BAR3_BA,`ADDR_BAR2_BA}, 32'h0, 13'd2048);
    memrd_prbs({`ADDR_BAR3_BA,`ADDR_BAR2_BA}, tmp_memr_data[31:0], 13'd2048);
    //prbsmode 1024dw
    memwr_prbs({`ADDR_BAR5_BA,`ADDR_BAR4_BA}, 32'h0, 13'd4096);
    memrd_prbs({`ADDR_BAR5_BA,`ADDR_BAR4_BA}, tmp_memr_data[31:0], 13'd4096);
    //prbsmode 1024dw
    memwr_prbs_error({`ADDR_BAR5_BA,`ADDR_BAR4_BA}, 32'h0, 13'd4096);
    memrd_prbs_error({`ADDR_BAR5_BA,`ADDR_BAR4_BA}, tmp_memr_data[31:0], 13'd4096);

    interrupt_process();
    io_wr_process();

    //tlp_error(0);
    //#((5_000_000)*1ps);
    //tlp_error(1);
    //#((5_000_000)*1ps);
    //tlp_error(2);
    //#((200_000_000)*1ps);

    $finish;

end



`include "tb_fsim_task.v"

`ifdef SIM_FSDB
  //DEBUG
  initial begin
    $fsdbDumpfile("pcie_subsystem_tb.fsdb");
    $fsdbDumpvars(0,pcie_subsystem_tb);
    $fsdbDumpMDA();
  end
`endif

// ====================================================================
// Only used to verify uart
// ====================================================================

//defparam u_ph2_pcie_ep_top.u_uart.BAUDRATE = 2000_000;
//defparam u_ph2_pcie_ep_top.u_uart.CLK_RATE = 5;
//
//ubus_model_fast ubus_model
//(
//    .clk     (u_ph2_pcie_ep_top.uart_clk    ), 
//    .rst_n   (!pcie_power_on_rst            ),
//
//    .tx_en   (tb_uart_tx_en                 ),
//    .tx_data (tb_uart_tx_data               ),
//
//    .rx_en   (tb_uart_rx_en                 ),
//    .rx_data (tb_uart_rx_data               ),
//    .rx_ready(tb_uart_rx_ready              )
//);
//
//
//initial begin
//    cfg0w_data                = 'd0;
//    cfg0r_data                = 'd0;
//    tmp_cfg0w_data            = 'd0;
//    tmp_cfg0r_data            = 'd0;
//
//    force tb_uart_rx_en       = u_ph2_pcie_ep_top.u_uart.aux_tx_en    ;
//    force tb_uart_rx_data     = u_ph2_pcie_ep_top.u_uart.aux_tx_data  ;
//
//    force u_ph2_pcie_ep_top.u_uart.aux_rx_en   = tb_uart_tx_en        ;
//    force u_ph2_pcie_ep_top.u_uart.aux_rx_data = tb_uart_tx_data      ;
//    //force u_ph2_pcie_ep_top.u_uart.aux_tx_ready= tb_uart_rx_ready     ;    
//
//    wait(!u_ph2_pcie_rc_top.tl_rst_user);
//    $display("tb info : ph2 pcie rc and ep are link up" );
//    #((1_000_000)*1ps);
//    ubus_model.ubus_rd(32'h00f0_01a4,tmp_cfg0r_data);
//    ubus_model.ubus_rd(32'h00f1_01a4,tmp_cfg0r_data);
//
//    ubus_model.ubus_rd(32'h00f0_0164,tmp_cfg0r_data);
//    ubus_model.ubus_rd(32'h00f1_0164,tmp_cfg0r_data);
//
//    ubus_model.ubus_rd(32'h0000_1c00,tmp_cfg0r_data);
//
//    ubus_model.ubus_wr(32'h0000_4000,32'habcd1234);
//end


endmodule
