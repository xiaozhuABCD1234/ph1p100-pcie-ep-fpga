//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2024 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : ph1p_pcie_rc_top.v
//  Author        : Gehong - hong.ge@anlogic.com
//  Last Modified : 2024-07-10 20:35:57
//  Create        : 2023-05-15 15:54:39
//  Description   : 
//   
///////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`include "../common/ph1p_pcie_case_param.v"
 module ph1p_pcie_rc_top(
     
    // serdes high speed pin
    input       wire                ref_pad_clk_p          ,
    input       wire                ref_pad_clk_n          ,
    input       wire    [3:0]       pcie_rx_p              ,
    input       wire    [3:0]       pcie_rx_n              ,
    output      wire    [3:0]       pcie_tx_p              ,
    output      wire    [3:0]       pcie_tx_n              ,

    input       wire                sys_clk                ,
    // pcie ip reset
    output      wire                pcie_mperst            ,
    input       wire                pcie_power_on_rst      ,
//    `ifndef FAST_SIM
//    // Si5345 100Mhz Generate
//    output      wire                SI5345_FINC            ,
//    output      wire                SI5345_FDEC            ,
//    output      wire                SI5345_OEB             ,
//    output      wire                SI5345_RSTB_N          ,
//    inout       wire                SI5345_SCK_O           ,
//    inout       wire                SI5345_SDA_IO          ,
//    `endif
    // Uart signals
    input       wire                rxd                    ,
    output      wire                txd                    ,
    
    // Debug Led
    output      wire     [7:0]      debug_led              

);

// ====================================================================
// Parameter/wire/reg
// ====================================================================
/// Simlation
//pragma translate_off
`define         PH1P_HXT_FAST_SIM 
//pragma translate_on 
`ifdef PH1P_HXT_FAST_SIM
    parameter PH1P_HXT_FAST_SIM = 1'b1;
`else
    parameter PH1P_HXT_FAST_SIM = 1'b0;
`endif   
// transcation layer clock signals  
    wire                tl_clk_user                             ;
    wire                tl_clk_locked                           ;
    wire                pcie_pll_locked                         ;
    wire                tl_rst_user                             ;
    reg                 power_on_rst_dly                        ;
    reg                 power_on_rst_dly_uart                   ;
    wire                sys_rst_uart_ep                         ;
    wire                sys_rst_uart_rc                         ;
    // clock and reset signals
    wire                tl_clk_gate                             ;
    wire  [8:0]         tl_clk_user_freq                        ;

    // user apb configure signals
    wire                tl_cfg_pclk                             ;
    wire                tl_cfg_prst                             ;
    wire                tl_cfg_penable                          ;
    wire                tl_cfg_psel                             ;
    wire                tl_cfg_pwrite                           ;
    wire  [31:0]        tl_cfg_paddr                            ;
    wire  [3:0]         tl_cfg_pstrb                            ;
    wire  [31:0]        tl_cfg_pwdata                           ;
    wire                tl_cfg_pready                           ;
    wire  [31:0]        tl_cfg_prdata                           ;
    wire                tl_cfg_pslverr                          ;
    //
    wire                hxt_apb4_psel_i                         ;
    wire                hxt_apb4_penable_i                      ;
    wire                hxt_apb4_pwrite_i                       ;
    wire  [31:0]        hxt_apb4_paddr_i                        ;
    wire  [31:0]        hxt_apb4_pwdata_i                       ;
    wire  [3:0]         hxt_apb4_pstrb_i                        ;
    wire  [2:0]         hxt_apb4_pprot_i                        ;
    wire  [31:0]        hxt_apb4_prdata_o                       ;
    wire                hxt_apb4_pready_o                       ;
    wire                hxt_apb4_pslverr_o                      ;

    wire  [7:0]         tl_cfg_tcvc                             ;
    wire  [12:0]        tl_cfg_busdev                           ;
    wire  [2:0]         tl_cfg_max_payload_size                 ;
    wire  [2:0]         tl_cfg_max_read_request_size            ;
    wire  [2:0]         tl_cfg_current_link_speed               ;
    wire  [3:0]         tl_cfg_negotiated_width                 ;
    wire                tl_cfg_read_completion_boundary         ;
    wire  [7:0]         tl_cfg_pfregs_cmd                       ;
    wire  [7:0]         tl_cfg_pf0_primary_bus = 8'd0           ;
    wire  [7:0]         tl_cfg_pf1_primary_bus = 8'd0           ;

    // physical ltssm signals 
    wire  [1:0]         pl_equ_phase                            ;
    wire  [4:0]         tl_ltssm                                ;
    reg   [4:0]         ltssm_reg                               ;
    wire  [4:0]         pl_ltssm                                ;
    wire                pl_link_up                              ;
    wire                tl_ltssm_enable                         =1'b1;

    // Rx interface 
    wire                tl_rx_wait                              ;
    wire                tl_rx_masknp                            ;
    wire  [47:0]        tl_rx_bardec                            ;
    wire  [255:0]       tl_rx_data                              ;
    wire                tl_rx_eop                               ;
    wire  [7:0]         tl_rx_err                               ;
    wire  [9:0]         tl_rx_mchit                             ;
    wire                tl_rx_sop                               ;
    wire  [7:0]         tl_rx_valid                             ;

    // TX interface 
    wire  [255:0]       tl_tx_data                              ;
    wire                tl_tx_eop                               ;
    wire  [7:0]         tl_tx_err                               ;
    wire                tl_tx_sop                               ;
    wire                tl_tx_stream                            ;
    wire  [7:0]         tl_tx_valid                             ;
    wire                tl_tx_wait                              ;
    wire  [95:0]        tl_tx_credits                           ;

  `ifdef PH1P_PCIE_LEGACY_INT_ENABLE
    wire  [1:0]         tl_int_status                           ;
    wire  [3:0]         tl_int_pincontrol                       ;
    wire  [3:0]         tl_int_pinstate                         ;
  `endif

  `ifdef PH1P_PCIE_MSI_INT_ENABLE
    wire  [1:0]         tl_int_msireq                           ;
    wire  [9:0]         tl_int_msinum                           ;
    wire  [1:0]         tl_int_msiack                           ;
    wire  [1:0]         tl_int_msi_enable                       ;
    wire  [5:0]         tl_int_msi_multi_enable                 ;
    wire  [31:0]        tl_int_pf0_msi_pending                  ;
    wire  [31:0]        tl_int_pf1_msi_pending                  ;
    wire  [31:0]        tl_int_pf0_msi_mask                     ;
    wire  [31:0]        tl_int_pf1_msi_mask                     ;
  `endif

  `ifdef PH1P_PCIE_MSIX_INT_ENABLE
    wire  [1:0]         tl_cfg_msix_enable                      ;
    wire  [1:0]         tl_cfg_msix_function_mask               ;
  `endif

    // Ubus
    wire                ubus_pcie_wen                           ;
    wire  [31:0]        ubus_pcie_waddr                         ;
    wire  [31:0]        ubus_pcie_wdata                         ;
    wire                ubus_pcie_ren                           ;
    wire  [31:0]        ubus_pcie_raddr                         ;
    wire                ubus_pcie_bken                          ;
    wire  [31:0]        ubus_pcie_rdata                         ;

    wire                ubus_hxt_wen                            ;
    wire  [31:0]        ubus_hxt_waddr                          ;
    wire  [31:0]        ubus_hxt_wdata                          ;
    wire                ubus_hxt_ren                            ;
    wire  [31:0]        ubus_hxt_raddr                          ;
    wire                ubus_hxt_bken                           ;
    wire  [31:0]        ubus_hxt_rdata                          ;

    wire                tl_op_start                             ;
    wire  [15:0]        tl_ep_bdf                               ;
    wire                tl_mw_en                                ;
    wire  [63:0]        tl_mw_addr                              ;
    wire  [12:0]        tl_mw_len                               ;
    wire  [31:0]        tl_mw_data                              ;
    wire                tl_mw_data_vld                          ;
    wire                tl_mw_mode                              ;
    wire                tl_mw_prbs_error                        ;
    wire                tl_mr_en                                ;
    wire  [63:0]        tl_mr_addr                              ;
    wire  [12:0]        tl_mr_len                               ;
    wire  [31:0]        tl_mr_data                              ;
    wire                tl_mr_data_vld                          ;
    wire                tl_mr_mode                              ;
    wire                tl_mr_prbs_clear                        ;
    wire                tl_iow_en                               ;
    wire  [31:0]        tl_iow_addr                             ;
    wire  [31:0]        tl_iow_data                             ;
    wire                tl_ior_en                               ;
    wire  [31:0]        tl_ior_addr                             ;
    wire  [31:0]        tl_ior_data                             ;
    wire                tl_cfg0w_en                             ;
    wire  [31:0]        tl_cfg0w_addr                           ;
    wire  [31:0]        tl_cfg0w_data                           ;
    wire                tl_cfg0r_en                             ;
    wire  [31:0]        tl_cfg0r_addr                           ;
    wire  [31:0]        tl_cfg0r_data                           ;
    wire                tl_mw_op_over                           ;
    wire                tl_mr_op_over                           ;
    wire                tl_iow_op_over                          ;
    wire                tl_ior_op_over                          ;
    wire                tl_cfg0w_op_over                        ;
    wire                tl_cfg0r_op_over                        ;
   // error debug
    wire                tl_error_ep                             ;
    wire                tl_error_length                         ;
    wire                tl_error_address                        ;
    wire                o_alm                                   ;

    // INT
    wire                legacy_int_clear                        ;
    wire                inta                                    ;
    wire                intb                                    ;
    wire                intc                                    ;
    wire                intd                                    ;
    
    // MSI & MSI-X
    wire                msi_ctrl_int                            ;
    wire        [31:0]  msi_ctrl_int_vec                        ;
    wire        [31:0]  msi_ctrl_clear                          ;
    wire                clk_50M                                 ;
    reg                 pcie_power_on_rst_reg                   ;

// ====================================================================
// PCIe Controller Clock Generate
// ====================================================================

//--------------------------------------------
// clock logic
//--------------------------------------------
pcie_pll_rc u_pcie_pll_rc(
    .refclk                         (sys_clk                   ),
    .reset                          (!pcie_power_on_rst        ),
    .lock                           (pcie_pll_locked           ),
    .clk0_out                       (tl_clk_user               )
//    ,.clk1_out                       (clk_50M                   )
);
always@(posedge tl_clk_user or negedge pcie_power_on_rst )
begin
    if(!pcie_power_on_rst )
        pcie_power_on_rst_reg <= 1'b0;                         
    else 
        pcie_power_on_rst_reg <= pcie_pll_locked;
end

always@(posedge tl_clk_user or negedge pcie_power_on_rst_reg )
begin
    if(!pcie_power_on_rst_reg )
        power_on_rst_dly <= 1'b1;                         
    else 
        power_on_rst_dly <= sys_rst_uart_rc;
end

// uart module reset, it's only controlled by pad pin named pcie_power_on_rst
always@( posedge tl_clk_user or negedge pcie_power_on_rst_reg)
begin
    if( !pcie_power_on_rst_reg ) begin
        power_on_rst_dly_uart <= 1'b1;
    end else begin
        power_on_rst_dly_uart <= 1'b0;
    end
end

// pcie endpoint reset, it's only controlled uart reset logic sys_rst_uart_ep
assign  pcie_mperst         = !sys_rst_uart_rc;
assign  tl_cfg_pclk         =  tl_clk_user;

// user logic reset, when pcie controller has release reset, it's not mean can
// send or receive tlp, it should wait pcie controller read and link up 
ph1p_pcie_rst_sync#(
    .LTSSM_VAULE                             (5'h10                                   )
) u_ph1p_pcie_rst_sync(
    .clk                                     (tl_clk_user                             ),
    .rst                                     (power_on_rst_dly                        ),
    .tl_ltssm                                (tl_ltssm                                ),
    .pl_link_up                              (pl_link_up&tl_clk_locked&pcie_pll_locked),
    .rst_sync                                (tl_rst_user                             )
);
// ====================================================================
// PCIE IP Inst
// ====================================================================

pcie_rc_core  #( 
    .PH1P_HXT_FAST_SIM(PH1P_HXT_FAST_SIM)
)u_ph1p_pcie_rc_subsystem_top(
    // serdes high speed pin
    .ref_pad_clk_p                           (ref_pad_clk_p                           ),
    .ref_pad_clk_n                           (ref_pad_clk_n                           ),
    .pcie_rx_p                               (pcie_rx_p                               ),
    .pcie_rx_n                               (pcie_rx_n                               ),
    .pcie_tx_p                               (pcie_tx_p                               ),
    .pcie_tx_n                               (pcie_tx_n                               ),

    // transcation layer clock signals  
    .tl_clk_user                             (tl_clk_user                             ),
    .tl_clk_user_ce_n                        (!pcie_pll_locked                        ),
    .tl_clk_locked                           (tl_clk_locked                           ),

    // clock and reset signals
    .tl_clk_gate                             (tl_clk_gate                             ),
    .tl_power_on_rst                         (power_on_rst_dly                        ),

    // user apb configure signals
    .tl_cfg_pclk                             (tl_cfg_pclk                             ),
    .tl_cfg_prst                             (tl_cfg_prst                             ),
    .tl_cfg_penable                          (tl_cfg_penable                          ),
    .tl_cfg_psel                             (tl_cfg_psel                             ),
    .tl_cfg_pwrite                           (tl_cfg_pwrite                           ),
    .tl_cfg_paddr                            (tl_cfg_paddr                            ),
    .tl_cfg_pstrb                            (tl_cfg_pstrb                            ),
    .tl_cfg_pwdata                           (tl_cfg_pwdata                           ),
    .tl_cfg_pready                           (tl_cfg_pready                           ),
    .tl_cfg_prdata                           (tl_cfg_prdata                           ),
    .tl_cfg_pslverr                          (tl_cfg_pslverr                          ),

    .apb4_clk_i                              (tl_cfg_pclk                             ),
    .apb4_preset_i                           (1'b0                                    ),
    .apb4_psel_i                             (hxt_apb4_psel_i                         ),
    .apb4_penable_i                          (hxt_apb4_penable_i                      ),
    .apb4_pwrite_i                           (hxt_apb4_pwrite_i                       ),
    .apb4_paddr_i                            (hxt_apb4_paddr_i                        ),
    .apb4_pwdata_i                           (hxt_apb4_pwdata_i                       ),
    .apb4_pstrb_i                            (hxt_apb4_pstrb_i                        ),
    .apb4_pprot_i                            (hxt_apb4_pprot_i                        ),
    .apb4_prdata_o                           (hxt_apb4_prdata_o                       ),
    .apb4_pready_o                           (hxt_apb4_pready_o                       ),
    .apb4_pslverr_o                          (hxt_apb4_pslverr_o                      ),

    // cfg direct access   
    .tl_cfg_tcvc                             (tl_cfg_tcvc                             ),
    .tl_cfg_busdev                           (tl_cfg_busdev                           ),
    .tl_cfg_max_payload_size                 (tl_cfg_max_payload_size                 ),
    .tl_cfg_max_read_request_size            (tl_cfg_max_read_request_size            ),
    .tl_cfg_current_link_speed               (tl_cfg_current_link_speed               ),
    .tl_cfg_negotiated_width                 (tl_cfg_negotiated_width                 ),
    .tl_cfg_read_completion_boundary         (tl_cfg_read_completion_boundary         ),
    .tl_cfg_pfregs_cmd                       (tl_cfg_pfregs_cmd                       ),
    .tl_cfg_pf0_primary_bus                  (tl_cfg_pf0_primary_bus                  ),
    .tl_cfg_pf1_primary_bus                  (tl_cfg_pf1_primary_bus                  ),
    
    // pf legacy int / msi 
    `ifdef PH1P_PCIE_LEGACY_INT_ENABLE
    .tl_int_status                           (tl_int_status                           ),
    .tl_int_pincontrol                       (tl_int_pincontrol                       ),
    .tl_int_pinstate                         (tl_int_pinstate                         ),
    `endif
    
    `ifdef PH1P_PCIE_MSI_INT_ENABLE
    .tl_int_status                           (tl_int_status                           ),
    .tl_int_msireq                           (tl_int_msireq                           ),
    .tl_int_msinum                           (tl_int_msinum                           ),
    .tl_int_msiack                           (tl_int_msiack                           ),
    .tl_int_msi_enable                       (tl_int_msi_enable                       ),
    .tl_int_msi_multi_enable                 (tl_int_msi_multi_enable                 ),
    .tl_int_pf0_msi_pending                  (tl_int_pf0_msi_pending                  ),
    .tl_int_pf1_msi_pending                  (tl_int_pf1_msi_pending                  ),
    .tl_int_pf0_msi_mask                     (tl_int_pf0_msi_mask                     ),
    .tl_int_pf1_msi_mask                     (tl_int_pf1_msi_mask                     ),
    `endif 
      
    // pf msi 
    `ifdef PH1P_PCIE_MSIX_INT_ENABLE
    .tl_cfg_msix_enable                      (tl_cfg_msix_enable                      ),
    .tl_cfg_msix_function_mask               (tl_cfg_msix_function_mask               ),
    `endif

    // physical ltssm signals 
    .pl_equ_phase                            (pl_equ_phase                            ),
    .tl_ltssm                                (tl_ltssm                                ),
    .pl_ltssm                                (pl_ltssm                                ),
    .pl_link_up                              (pl_link_up                              ),
    .tl_ltssm_enable                         (tl_ltssm_enable                         ),

    // Rx interface 
    .tl_rx_wait                              (tl_rx_wait                              ),
    .tl_rx_masknp                            (tl_rx_masknp                            ),
    .tl_rx_bardec                            (tl_rx_bardec                            ),
    .tl_rx_data                              (tl_rx_data                              ),
    .tl_rx_eop                               (tl_rx_eop                               ),
    .tl_rx_err                               (tl_rx_err                               ),
    .tl_rx_mchit                             (tl_rx_mchit                             ),
    .tl_rx_sop                               (tl_rx_sop                               ),
    .tl_rx_valid                             (tl_rx_valid                             ),

    // TX interface 
    .tl_tx_data                              (tl_tx_data                              ),
    .tl_tx_eop                               (tl_tx_eop                               ),
    .tl_tx_err                               (tl_tx_err                               ),
    .tl_tx_sop                               (tl_tx_sop                               ),
    .tl_tx_stream                            (tl_tx_stream                            ),
    .tl_tx_valid                             (tl_tx_valid                             ),
    .tl_tx_wait                              (tl_tx_wait                              ),
    .tl_tx_credits                           (tl_tx_credits                           )
);

pcie_rc_tx_engine u_pcie_rc_tx_engine(
    // Clock and Reset
    .tl_clk_user                             (tl_clk_user                             ),
    .tl_rst_user                             (tl_rst_user                             ),

    // Tx Control signals
    .tl_op_start                             (tl_op_start                             ),
    .tl_ep_bdf                               (tl_ep_bdf                               ),
    .tl_mw_en                                (tl_mw_en                                ),
    .tl_mw_addr                              (tl_mw_addr                              ),
    .tl_mw_len                               (tl_mw_len                               ),
    .tl_mw_data                              (tl_mw_data                              ),
    .tl_mw_data_vld                          (tl_mw_data_vld                          ),
    .tl_mw_mode                              (tl_mw_mode                              ),
    .tl_mw_prbs_error                        (tl_mw_prbs_error                        ),
    .tl_mr_en                                (tl_mr_en                                ),
    .tl_mr_addr                              (tl_mr_addr                              ),
    .tl_mr_len                               (tl_mr_len                               ),
    .tl_iow_en                               (tl_iow_en                               ),
    .tl_iow_addr                             (tl_iow_addr                             ),
    .tl_iow_data                             (tl_iow_data                             ),
    .tl_ior_en                               (tl_ior_en                               ),
    .tl_ior_addr                             (tl_ior_addr                             ),
    .tl_cfg0w_en                             (tl_cfg0w_en                             ),
    .tl_cfg0w_addr                           (tl_cfg0w_addr                           ),
    .tl_cfg0w_data                           (tl_cfg0w_data                           ),
    .tl_cfg0r_en                             (tl_cfg0r_en                             ),
    .tl_cfg0r_addr                           (tl_cfg0r_addr                           ),
    .tl_mw_op_over                           (tl_mw_op_over                           ),
    // error debug
    .tl_error_ep                             (tl_error_ep                             ),
    .tl_error_length                         (tl_error_length                         ),
    .tl_error_address                        (tl_error_address                        ),

    // TX interface
    .tl_tx_data                              (tl_tx_data                              ),
    .tl_tx_eop                               (tl_tx_eop                               ),
    .tl_tx_err                               (tl_tx_err                               ),
    .tl_tx_sop                               (tl_tx_sop                               ),
    .tl_tx_stream                            (tl_tx_stream                            ),
    .tl_tx_valid                             (tl_tx_valid                             ),
    .tl_tx_wait                              (tl_tx_wait                              ),
    .tl_tx_credits                           (tl_tx_credits                           )
);

pcie_rc_rx_engine u_pcie_rc_rx_engine(
    // Clock and Reset
    .tl_clk_user                             (tl_clk_user                             ),
    .tl_rst_user                             (tl_rst_user                             ),

    // Rx Control signals
    .tl_mr_op_over                           (tl_mr_op_over                           ),
    .tl_mr_en                                (tl_mr_en                                ),
    .tl_mr_len                               (tl_mr_len                               ),
    .tl_mr_data                              (tl_mr_data                              ),
    .tl_mr_data_vld                          (tl_mr_data_vld                          ),
    .tl_mr_mode                              (tl_mr_mode                              ),
    .tl_mr_prbs_clear                        (tl_mr_prbs_clear                        ),

    .tl_iow_en                               (tl_iow_en                               ),
    .tl_iow_op_over                          (tl_iow_op_over                          ),
    .tl_ior_en                               (tl_ior_en                               ),
    .tl_ior_op_over                          (tl_ior_op_over                          ),
    .tl_ior_data                             (tl_ior_data                             ),

    .tl_cfg0w_en                             (tl_cfg0w_en                             ),
    .tl_cfg0w_op_over                        (tl_cfg0w_op_over                        ),
    .tl_cfg0r_en                             (tl_cfg0r_en                             ),
    .tl_cfg0r_op_over                        (tl_cfg0r_op_over                        ),
    .tl_cfg0r_data                           (tl_cfg0r_data                           ),

    .msi_ctrl_int                            (msi_ctrl_int                            ),
    .msi_ctrl_int_vec                        (msi_ctrl_int_vec                        ),
    .msi_ctrl_clear                          (msi_ctrl_clear                          ),

    // RX interface
    .tl_rx_wait                              (tl_rx_wait                              ),
    .tl_rx_masknp                            (tl_rx_masknp                            ),
    .tl_rx_bardec                            (tl_rx_bardec                            ),
    .tl_rx_data                              (tl_rx_data                              ),
    .tl_rx_eop                               (tl_rx_eop                               ),
    .tl_rx_err                               (tl_rx_err                               ),
    .tl_rx_mchit                             (tl_rx_mchit                             ),
    .tl_rx_sop                               (tl_rx_sop                               ),
    .tl_rx_valid                             (tl_rx_valid                             ),

    // MSIC interface
    .o_alm                                   (o_alm                                   )
);

pcie_rc_int_handle u_pcie_rc_int_handle(

    // Clock and Reset
    .tl_clk_user                             (tl_clk_user                             )
   ,.tl_rst_user                             (tl_rst_user                             )
    // INT  
   ,.legacy_int_clear                        (legacy_int_clear                        )
   ,.inta                                    (inta                                    )
   ,.intb                                    (intb                                    )
   ,.intc                                    (intc                                    )
   ,.intd                                    (intd                                    )
   
`ifdef PH1P_PCIE_LEGACY_INT_ENABLE
   ,.tl_int_status                           (tl_int_status                           )
   ,.tl_int_pincontrol                       (tl_int_pincontrol                       )
   ,.tl_int_pinstate                         (tl_int_pinstate                         )
`endif

`ifdef PH1P_PCIE_MSI_INT_ENABLE
   ,.tl_int_status                           (tl_int_status                           )
   ,.tl_int_msireq                           (tl_int_msireq                           )
   ,.tl_int_msinum                           (tl_int_msinum                           )
   ,.tl_int_msiack                           (tl_int_msiack                           )
   ,.tl_int_msi_enable                       (tl_int_msi_enable                       )
   ,.tl_int_msi_multi_enable                 (tl_int_msi_multi_enable                 )
   ,.tl_int_pf0_msi_pending                  (tl_int_pf0_msi_pending                  )
   ,.tl_int_pf1_msi_pending                  (tl_int_pf1_msi_pending                  )
   ,.tl_int_pf0_msi_mask                     (tl_int_pf0_msi_mask                     )
   ,.tl_int_pf1_msi_mask                     (tl_int_pf1_msi_mask                     )
`endif

`ifdef PH1P_PCIE_MSIX_INT_ENABLE
   ,.tl_cfg_msix_enable                      (tl_cfg_msix_enable                      )
   ,.tl_cfg_msix_function_mask               (tl_cfg_msix_function_mask               )
`endif
);

rc_ubus_bridge u_ubus_bridge(
    .tl_clk_user                             (tl_clk_user                             ),
    .uart_clk                                (tl_clk_user                             ),
    .rst                                     (power_on_rst_dly_uart                   ),

    // pcie Ubus
    .ubus_pcie_wen                           (ubus_pcie_wen                           ),
    .ubus_pcie_waddr                         (ubus_pcie_waddr                         ),
    .ubus_pcie_wdata                         (ubus_pcie_wdata                         ),
    .ubus_pcie_ren                           (ubus_pcie_ren                           ),
    .ubus_pcie_raddr                         (ubus_pcie_raddr                         ),
    .ubus_pcie_bken                          (ubus_pcie_bken                          ),
    .ubus_pcie_rdata                         (ubus_pcie_rdata                         ),

    // hxt Ubus
    .ubus_hxt_wen                            (ubus_hxt_wen                            ),
    .ubus_hxt_waddr                          (ubus_hxt_waddr                          ),
    .ubus_hxt_wdata                          (ubus_hxt_wdata                          ),
    .ubus_hxt_ren                            (ubus_hxt_ren                            ),
    .ubus_hxt_raddr                          (ubus_hxt_raddr                          ),
    .ubus_hxt_bken                           (ubus_hxt_bken                           ),
    .ubus_hxt_rdata                          (ubus_hxt_rdata                          ),

    // to tlp engine
    .sys_rst_uart_ep                         (sys_rst_uart_ep                         ),
    .sys_rst_uart_rc                         (sys_rst_uart_rc                         ),
    .op_start                                (tl_op_start                             ),
    .ep_bdf                                  (tl_ep_bdf                               ),
    .mw_en                                   (tl_mw_en                                ),
    .mr_en                                   (tl_mr_en                                ),
    .iow_en                                  (tl_iow_en                               ),
    .ior_en                                  (tl_ior_en                               ),
    .cfg0w_en                                (tl_cfg0w_en                             ),
    .cfg0r_en                                (tl_cfg0r_en                             ),
    .mw_addr                                 (tl_mw_addr                              ),
    .mw_len                                  (tl_mw_len                               ),
    .mw_data                                 (tl_mw_data                              ),
    .mw_data_vld                             (tl_mw_data_vld                          ),
    .mw_mode                                 (tl_mw_mode                              ),
    .mw_prbs_error                           (tl_mw_prbs_error                        ),
    .mr_addr                                 (tl_mr_addr                              ),
    .mr_len                                  (tl_mr_len                               ),
    .mr_data                                 (tl_mr_data                              ),
    .mr_data_vld                             (tl_mr_data_vld                          ),
    .mr_mode                                 (tl_mr_mode                              ),
    .mr_prbs_clear                           (tl_mr_prbs_clear                        ),
    .iow_addr                                (tl_iow_addr                             ),
    .iow_data                                (tl_iow_data                             ),
    .ior_addr                                (tl_ior_addr                             ),
    .ior_data                                (tl_ior_data                             ),
    .cfg0w_addr                              (tl_cfg0w_addr                           ),
    .cfg0w_data                              (tl_cfg0w_data                           ),
    .cfg0r_addr                              (tl_cfg0r_addr                           ),
    .cfg0r_data                              (tl_cfg0r_data                           ),
    .mw_op_over                              (tl_mw_op_over                           ),
    .mr_op_over                              (tl_mr_op_over                           ),
    .iow_op_over                             (tl_iow_op_over                          ),
    .ior_op_over                             (tl_ior_op_over                          ),
    .cfg0w_op_over                           (tl_cfg0w_op_over                        ),
    .cfg0r_op_over                           (tl_cfg0r_op_over                        ),

    // error debug
    .error_ep                                (tl_error_ep                             ),
    .error_length                            (tl_error_length                         ),
    .error_address                           (tl_error_address                        ),

    // INT
    .legacy_int_clear                        (legacy_int_clear                        ),
    .inta                                    (inta                                    ),
    .intb                                    (intb                                    ),
    .intc                                    (intc                                    ),
    .intd                                    (intd                                    ),

    // MSI
    .msi_ctrl_int                            (msi_ctrl_int                            ),
    .msi_ctrl_int_vec                        (msi_ctrl_int_vec                        ),
    .msi_ctrl_clear                          (msi_ctrl_clear                          ),
    
    // APB4 bus
    .tl_cfg_prst                             (tl_cfg_prst                             ),
    .tl_cfg_penable                          (tl_cfg_penable                          ),
    .tl_cfg_psel                             (tl_cfg_psel                             ),
    .tl_cfg_pwrite                           (tl_cfg_pwrite                           ),
    .tl_cfg_paddr                            (tl_cfg_paddr                            ),
    .tl_cfg_pstrb                            (tl_cfg_pstrb                            ),
    .tl_cfg_pwdata                           (tl_cfg_pwdata                           ),
    .tl_cfg_pready                           (tl_cfg_pready                           ),
    .tl_cfg_prdata                           (tl_cfg_prdata                           ),
    .tl_cfg_pslverr                          (tl_cfg_pslverr                          ),
    
     // To HXT APB
    .hxt_apb4_psel_o                         (hxt_apb4_psel_i                         ),
    .hxt_apb4_penable_o                      (hxt_apb4_penable_i                      ),
    .hxt_apb4_pwrite_o                       (hxt_apb4_pwrite_i                       ),
    .hxt_apb4_paddr_o                        (hxt_apb4_paddr_i                        ),
    .hxt_apb4_pwdata_o                       (hxt_apb4_pwdata_i                       ),
    .hxt_apb4_pstrb_o                        (hxt_apb4_pstrb_i                        ),
    .hxt_apb4_pprot_o                        (hxt_apb4_pprot_i                        ),
    .hxt_apb4_prdata_i                       (hxt_apb4_prdata_o                       ),
    .hxt_apb4_pready_i                       (hxt_apb4_pready_o                       ),
    .hxt_apb4_pslverr_i                      (hxt_apb4_pslverr_o                      )

  );


pcie_uart 
#(
    .BAUDRATE                                (115200                                  ),
    .CLK_RATE                                (8                                       )// Period
)u_uart (
    .aux_clk                                 (tl_clk_user                             ),
    .core_clk                                (tl_clk_user                             ),
    .rst_n                                   (power_on_rst_dly_uart                   ),

    .rx                                      (rxd                                     ),
    .tx                                      (txd                                     ),

    .ubus_pcie_wen                           (ubus_pcie_wen                           ),
    .ubus_pcie_waddr                         (ubus_pcie_waddr                         ),
    .ubus_pcie_wdata                         (ubus_pcie_wdata                         ),
    .ubus_pcie_ren                           (ubus_pcie_ren                           ),
    .ubus_pcie_raddr                         (ubus_pcie_raddr                         ),
    .ubus_pcie_bken                          (ubus_pcie_bken                          ),
    .ubus_pcie_rdata                         (ubus_pcie_rdata                         ),

    .ubus_hxt_wen                            (ubus_hxt_wen                            ),
    .ubus_hxt_waddr                          (ubus_hxt_waddr                          ),
    .ubus_hxt_wdata                          (ubus_hxt_wdata                          ),
    .ubus_hxt_ren                            (ubus_hxt_ren                            ),
    .ubus_hxt_raddr                          (ubus_hxt_raddr                          ),
    .ubus_hxt_bken                           (ubus_hxt_bken                           ),
    .ubus_hxt_rdata                          (ubus_hxt_rdata                          )
);

//`ifndef FAST_SIM
//si5344_si5345 u_si5344_5345_config(
//    .clk                                     (clk_50M                                 ),
//    .SI5345_FINC                             (SI5345_FINC                             ),
//    .SI5345_FDEC                             (SI5345_FDEC                             ),
//    .SI5345_OEB                              (SI5345_OEB                              ),
//    .SI5345_RSTB_N                           (SI5345_RSTB_N                           ),
//    .SI5345_SCK_O                            (SI5345_SCK_O                            ),
//    .SI5345_SDA_IO                           (SI5345_SDA_IO                           )
//    );
//`endif
always@(posedge tl_clk_user) 
    ltssm_reg  <= tl_ltssm;  

assign  debug_led[0] = power_on_rst_dly;
assign  debug_led[1] = pl_link_up;
assign  debug_led[2] = tl_clk_locked;
assign  debug_led[3] = ltssm_reg[4];
assign  debug_led[4] = ltssm_reg[3];
assign  debug_led[5] = ltssm_reg[2];
assign  debug_led[6] = ltssm_reg[1];
assign  debug_led[7] = ltssm_reg[0];

endmodule
