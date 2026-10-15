//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2024 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : ph1p_pcie_ep_top.v
//  Author        : Gehong - hong.ge@anlogic.com
//  Last Modified : 2024-07-10 17:43:34
//  Create        : 2023-05-05 11:06:25
//  Description   : 
//
///////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`include "../common/ph1p_pcie_case_param.v" 
 module ph1p_pcie_ep_top(

    // serdes high speed pin
    input      wire                      ref_pad_clk_p                           ,
    input      wire                      ref_pad_clk_n                           ,
    input      wire  [1:0]               pcie_rx_p                               ,
    input      wire  [1:0]               pcie_rx_n                               ,
    output     wire  [1:0]               pcie_tx_p                               ,
    output     wire  [1:0]               pcie_tx_n                               ,
    input      wire                      user_int_trigger                        ,
    input      wire                      sys_clk                                 ,
    // pcie ip reset
    input      wire                      pcie_mperst                             ,
    input      wire                      pcie_power_on_rst                       ,
    // uart signals（rxd 让位给 MIPI 子卡的 cam_a_xclr_n，板上不再用串口接收）
    // MIPI 摄像头（FEP-VID006 子卡，A/B 两路 IMX415）
    input      wire                      mipi_a_clk_hs_p                         ,
    input      wire                      mipi_a_clk_hs_n                         ,
    input      wire  [3:0]               mipi_a_data_hs_p                        ,
    input      wire  [3:0]               mipi_a_data_hs_n                        ,
    input      wire                      mipi_b_clk_hs_p                         ,
    input      wire                      mipi_b_clk_hs_n                         ,
    input      wire  [3:0]               mipi_b_data_hs_p                        ,
    input      wire  [3:0]               mipi_b_data_hs_n                        ,
    output     wire                      cam_a_mclk                              ,
    output     wire                      cam_a_xclr_n                            ,
    output     wire                      cam_a_scl                               ,
    inout      wire                      cam_a_sda                               ,
    output     wire                      cam_b_mclk                              ,
    output     wire                      cam_b_xclr_n                            ,
    output     wire                      cam_b_scl                               ,
    inout      wire                      cam_b_sda                               ,
    output     wire                      txd                                     ,
    output     wire     [3:0]            debug_led                               ,
    // DDR3 颗粒（板载 DDR3L x16/2048：4 个 DQ byte + AC；球号与 IOSTANDARD 由
    // al_ip/ddr3_mc_0 自带的 src/adc/ddr3_mc_0.adc（set_ippin_assignment）给出，
    // 本工程的 adc 里不写任何 ddr_* 引脚，见文件末 DDR3 段说明）
    output     wire                      ddr_ck_p                                ,
    output     wire                      ddr_ck_n                                ,
    output     wire                      ddr_reset_n                             ,
    output     wire                      ddr_cke                                 ,
    output     wire                      ddr_odt                                 ,
    output     wire                      ddr_cs_n                                ,
    output     wire                      ddr_ras_n                               ,
    output     wire                      ddr_cas_n                               ,
    output     wire                      ddr_we_n                                ,
    output     wire  [2:0]               ddr_ba                                  ,
    output     wire  [13:0]              ddr_addr                                ,
    inout      wire  [3:0]               ddr_dqs_p                               ,
    inout      wire  [3:0]               ddr_dqs_n                               ,
    inout      wire  [31:0]              ddr_dq                                  ,
    inout      wire  [3:0]               ddr_dm                                 

);   

// ====================================================================
// Parameter/wire/reg
// =================================================================== 
/// Simlation
//pragma translate_off
`define         PH1P_HXT_FAST_SIM 
//pragma translate_on 
`ifdef PH1P_HXT_FAST_SIM
    parameter PH1P_HXT_FAST_SIM = 1'b1;
`else
    parameter PH1P_HXT_FAST_SIM = 1'b0;
`endif   

    // ---- 图像通路（本移植新增）----
    localparam IMG_W      = 640;
    localparam IMG_H      = 480;
    localparam IMG_WORDS  = (IMG_W * IMG_H) / 4;
    localparam IMG_PTRBYTES = IMG_W * IMG_H;
    localparam IMG_PTRMSK   = (IMG_WORDS * 4) - 4;   // 保留（未用）

// ==== 图像通路（本移植新增：img_regs + img_frame_src）====
wire [31:0]  img_fb_raddr;
wire [31:0]  img_fb_rdata;
wire         img_enable;
wire         img_trigger;
wire         img_ready;
wire         img_busy;
wire [31:0]  img_frame_cnt;
wire [31:0]  img_data_len;
wire [15:0]  img_width;
wire [15:0]  img_height;
wire [1:0]   img_pattern;
wire [31:0]  img_dbg_idx;

// ==== 相机写帧缓存通路（cam_fb_writer，本移植新增）====
//  CTRL[4] = 写源选择：0 = 测试图源（默认），1 = 相机。
//  它在 ep_bar_win 里存着，但 pcie_ep_engine.v 的端口不许改，只能借
//  ctrl_pattern[1] 这条本来没人消费的通道送到顶层（见 ep_bar_win.v 头部说明）。
wire         img_cam_sel;
wire         cam_fb_wr_en;
wire [31:0]  cam_fb_wr_addr;
wire [31:0]  cam_fb_wr_data;
wire [31:0]  cam_fb_frame_cnt;
wire [31:0]  cam_fb_data_len;
wire         cam_fb_ready;
wire         cam_fb_busy;
wire         cam_fb_frame_done;    // 帧完成标志（EOF 置 1、下个 SOF 清 0；顶层暂无寄存器口）
wire [31:0]  cam_fb_wr_word_cnt;   // 本帧已写字数（诊断）
wire [15:0]  cam_fb_drop_cnt;      // FIFO 满丢掉像素组数（诊断，正常 = 0）
wire [15:0]  cam_fb_ovf_cnt;       // FIFO 满丢掉 SOF/EOF 标记数（诊断，正常 = 0）
assign img_cam_sel = img_pattern[1];   // = CTRL[4]（原语义不变）
// img_pattern[0] = CTRL[2] 现在用作「传感器 MCLK 源选择」（见顶层相机段说明）；
// CTRL[3]（原 pattern[1]）仍然无人消费。
wire [255:0] w_cam_stat;      // 声明必须早于例化处使用（否则 TD 造 1 位隐式网）
wire [6:0]   cam_tap_cfg;
wire         w_uart_rxd_unused = 1'b1;

    // clock and reset signals
    wire                          tl_clk_gate                             ;
    wire       [8:0]              tl_clk_user_freq                        ;
    wire                          tl_clk_user                             ;
    wire                          uart_clk                                ;
    wire                          pcie_pll_locked                         ;
    wire                          tl_rst_user                             ;
    reg                           power_on_rst_dly                        ;
    wire                          tl_clk_locked                           ;
    // user apb configure signals
    wire                          tl_cfg_pclk                             ;
    wire                          tl_cfg_prst                             ;
    wire                          tl_cfg_penable                          ;
    wire                          tl_cfg_psel                             ;
    wire                          tl_cfg_pwrite                           ;
    wire       [31:0]             tl_cfg_paddr                            ;
    wire       [3:0]              tl_cfg_pstrb                            ;
    wire       [31:0]             tl_cfg_pwdata                           ;
    wire                          tl_cfg_pready                           ;
    wire       [31:0]             tl_cfg_prdata                           ;
    wire                          tl_cfg_pslverr                          ;
    
    // cfg direct access
    wire       [7:0]              tl_cfg_tcvc                             ;
    wire       [12:0]             tl_cfg_busdev                           ;
    wire       [2:0]              tl_cfg_max_payload_size                 ;
    wire       [2:0]              tl_cfg_max_read_request_size            ;
    wire       [2:0]              tl_cfg_current_link_speed               ;
    wire       [3:0]              tl_cfg_negotiated_width                 ;
    wire                          tl_cfg_read_completion_boundary         ;
    wire       [7:0]              tl_cfg_pfregs_cmd                       ;
    wire       [7:0]              tl_cfg_pf0_primary_bus = 8'd0           ;
    wire       [7:0]              tl_cfg_pf1_primary_bus = 8'd0           ;
  
    // physical ltssm signals
    wire       [1:0]              pl_equ_phase                            ;
    wire       [4:0]              tl_ltssm                                ;
    wire       [4:0]              pl_ltssm                                ;
    wire                          pl_link_up                              ;
    wire                          tl_ltssm_enable                         =1'b1;

    // Rx interface
    wire                          tl_rx_wait                              ;
    wire                          tl_rx_masknp                            ;
    wire      [47:0]              tl_rx_bardec                            ;
    wire      [255:0]             tl_rx_data                              ;
    wire                          tl_rx_eop                               ;
    wire      [7:0]               tl_rx_err                               ;
    wire      [9:0]               tl_rx_mchit                             ;
    wire                          tl_rx_sop                               ;
    wire      [7:0]               tl_rx_valid                             ;

    // TX interface
    wire      [255:0]             tl_tx_data                              ;
    wire                          tl_tx_eop                               ;
    wire      [7:0]               tl_tx_err                               ;
    wire                          tl_tx_sop                               ;
    wire                          tl_tx_stream                            ;
    wire      [7:0]               tl_tx_valid                             ;
    wire                          tl_tx_wait                              ;
    wire      [95:0]              tl_tx_credits                           ;

   `ifdef PH1P_PCIE_LEGACY_INT_ENABLE
    wire      [1:0]               tl_int_status                           ;
    wire      [3:0]               tl_int_pincontrol                       ;
    wire      [3:0]               tl_int_pinstate                         ;
  `endif
  
  `ifdef PH1P_PCIE_MSI_INT_ENABLE
    wire      [1:0]               tl_int_msireq                           ;
    wire      [9:0]               tl_int_msinum                           ;
    wire      [1:0]               tl_int_msiack                           ;
    wire      [1:0]               tl_int_msi_enable                       ;
    wire      [5:0]               tl_int_msi_multi_enable                 ;
    wire      [31:0]              tl_int_pf0_msi_pending                  ;
    wire      [31:0]              tl_int_pf1_msi_pending                  ;
    wire      [31:0]              tl_int_pf0_msi_mask                     ;
    wire      [31:0]              tl_int_pf1_msi_mask                     ;
  `endif 
    
  `ifdef PH1P_PCIE_MSIX_INT_ENABLE
    wire      [1:0]               tl_cfg_msix_enable                      ;
    wire      [1:0]               tl_cfg_msix_function_mask               ;
  `endif

    //
    wire                          hxt_apb4_psel_i                         ;
    wire                          hxt_apb4_penable_i                      ;
    wire                          hxt_apb4_pwrite_i                       ;
    wire      [31:0]              hxt_apb4_paddr_i                        ;
    wire      [31:0]              hxt_apb4_pwdata_i                       ;
    wire      [3:0]               hxt_apb4_pstrb_i                        ;
    wire      [2:0]               hxt_apb4_pprot_i                        ;
    wire      [31:0]              hxt_apb4_prdata_o                       ;
    wire                          hxt_apb4_pready_o                       ;
    wire                          hxt_apb4_pslverr_o                      ;

    // Ubus
    wire                          ubus_pcie_wen                           ;
    wire      [31:0]              ubus_pcie_waddr                         ;
    wire      [31:0]              ubus_pcie_wdata                         ;
    wire                          ubus_pcie_ren                           ;
    wire      [31:0]              ubus_pcie_raddr                         ;
    wire                          ubus_pcie_bken                          ;
    wire      [31:0]              ubus_pcie_rdata                         ;

    wire                          ubus_hxt_wen                            ;
    wire      [31:0]              ubus_hxt_waddr                          ;
    wire      [31:0]              ubus_hxt_wdata                          ;
    wire                          ubus_hxt_ren                            ;
    wire      [31:0]              ubus_hxt_raddr                          ;
    wire                          ubus_hxt_bken                           ;
    wire      [31:0]              ubus_hxt_rdata                          ;

    // ubus to logic
    wire                          ubus_wen_logic                          ;
    wire      [31:0]              ubus_waddr_logic                        ;
    wire      [31:0]              ubus_wdata_logic                        ;
    wire                          ubus_ren_logic                          ;
    wire      [31:0]              ubus_raddr_logic                        ;
    wire                          ubus_bken_logic                         ;
    wire      [31:0]              ubus_rdata_logic                        ;
    // Debug Logic 
    reg                           ubus_wen_logic_dly                      ;
    reg       [31:0]              ubus_waddr_logic_dly                    ;
    reg       [31:0]              ubus_wdata_logic_dly                    ;
    reg                           ubus_ren_logic_dly                      ;
    reg       [31:0]              ubus_raddr_logic_dly                    ;
    reg                           ubus_bken_logic_dly                     =1'b0;
    reg       [31:0]              ubus_rdata_logic_dly                    =32'd0;

    reg       [31:0]              rd_data0                                ;
    reg       [31:0]              rd_data1                                ;
    reg       [31:0]              rd_data2                                ;
    reg       [31:0]              rd_data3                                ;
    reg       [31:0]              rd_data4                                ;

    reg       [4:0]               ltssm_reg                               =5'd0;
    reg       [4:0]               ltssm_reg_dly                           =5'd0;
    reg       [4:0]               ltssm_debug[19:0]                       ;
    reg       [31:0]              ltssm_change_cnt                        ;

    wire      [3:0]               tl_int_msix_trigger                     ;
    reg                           pcie_power_on_rst_reg                   ;
    wire                          clk_50M                                 ;
    reg                           pcie_power_on_rst_uart                  ;
    reg                           uart_rst                                ;
// ====================================================================
// PCIe Controller Clock Generate
// ====================================================================
//--------------------------------------------
// clock logic
//--------------------------------------------
pcie_pll_ep u_pcie_pll_ep(
    .refclk                       (sys_clk                    ),
    .reset                        (!pcie_power_on_rst         ),
    .lock                         (pcie_pll_locked            ),
    .clk0_out                     (tl_clk_user                ) 
);

assign  tl_cfg_pclk = tl_clk_user;

always@(posedge tl_clk_user or negedge pcie_power_on_rst )
begin
    if(!pcie_power_on_rst )
        uart_rst <= 1'b1;
    else 
        uart_rst <= ~pcie_pll_locked;
end


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
        power_on_rst_dly <= !pcie_mperst | pcie_power_on_rst_uart;
end

ph1p_pcie_rst_sync#(
    .LTSSM_VAULE                  (5'h10                                   )
) u_ph1p_pcie_rst_sync(
    .clk                          (tl_clk_user                             ),
    .rst                          (power_on_rst_dly                        ),
    .tl_ltssm                     (tl_ltssm                                ),
    .pl_link_up                   (pl_link_up&tl_clk_locked&pcie_pll_locked),
    .rst_sync                     (tl_rst_user                             )
);

// ====================================================================
// PCIE IP Inst
// ====================================================================
pcie_ep_core #( 
    .PH1P_HXT_FAST_SIM(PH1P_HXT_FAST_SIM)
)u_ph1p_pcie_ep_subsystem_top(
    
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

pcie_ep_engine #(
    .IMG_PTRBYTES                            (IMG_PTRBYTES                           ),
    .IMG_CLK_MHZ                             (9'd62                                  )
) u_pcie_ep_engine (


    // Clock and Reset
    .tl_clk_user                             (tl_clk_user                             ),
    .tl_rst_user                             (tl_rst_user                             ),

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

`ifdef PH1P_PCIE_MSIX_INT_ENABLE
    .tl_int_msix_trigger                     (tl_int_msix_trigger                     ),
`else
    .tl_int_msix_trigger                     (4'b0                                    ),
`endif

    // TX interface 
    .tl_tx_data                              (tl_tx_data                              ),
    .tl_tx_eop                               (tl_tx_eop                               ),
    .tl_tx_err                               (tl_tx_err                               ),
    .tl_tx_sop                               (tl_tx_sop                               ),
    .tl_tx_stream                            (tl_tx_stream                            ),
    .tl_tx_valid                             (tl_tx_valid                             ),
    .tl_tx_wait                              (tl_tx_wait                              ),
    .tl_tx_credits                           (tl_tx_credits                           ),
    // ==== 本移植新增：BAR0 真窗口 → 图像源 ====
    .img_ctrl_enable                         (img_enable                             ),
    .img_ctrl_trigger                        (img_trigger                            ),
    .img_ctrl_pattern                        (img_pattern                            ),
    .img_st_ready                            (img_ready                              ),
    .img_st_busy                             (img_busy                               ),
    .img_st_frame_cnt                        (img_frame_cnt                          ),
    .img_st_width                            (img_width                              ),
    .img_st_height                           (img_height                             ),
    .img_st_data_len                         (img_data_len                           ),
    .img_fb_raddr                            (img_fb_raddr                           ),
    .img_fb_rdata                            (img_fb_rdata                           )
    ,.img_dbg_rd_idx                          (img_dbg_idx                            ),
    .cam_stat_bus                            (w_cam_stat                             ),
    .cam_tap_cfg                             (cam_tap_cfg                            )
);

pcie_ep_int_handle u_pcie_ep_int_handle(

    // Clock and Reset
    .tl_clk_user                             (tl_clk_user                             )
   ,.tl_rst_user                             (tl_rst_user                             )
   ,.user_int_trigger                        (!user_int_trigger                       )
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
   ,.tl_int_msix_trigger                     (tl_int_msix_trigger                     )
`endif
);

pcie_uart
#(
    .BAUDRATE                                (115200                                  ),
    .CLK_RATE                                (16                                      )// Period
)u_uart (
    .aux_clk                                 (tl_clk_user                             ),
    .core_clk                                (tl_clk_user                             ),
    .rst_n                                   (uart_rst                                ),
                                                                                      
    .rx                                      (w_uart_rxd_unused                                     ),
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

ep_ubus_bridge u_ep_ubus_bridge(
    .tl_clk_user                             (tl_clk_user                            ),
    .uart_clk                                (tl_clk_user                            ),
    .rst                                     (uart_rst                               ),
    .tl_clk_locked                           (tl_clk_locked                          ),

    // pcie Ubus
    .ubus_pcie_wen                           (ubus_pcie_wen                          ),
    .ubus_pcie_waddr                         (ubus_pcie_waddr                        ),
    .ubus_pcie_wdata                         (ubus_pcie_wdata                        ),
    .ubus_pcie_ren                           (ubus_pcie_ren                          ),
    .ubus_pcie_raddr                         (ubus_pcie_raddr                        ),
    .ubus_pcie_bken                          (ubus_pcie_bken                         ),
    .ubus_pcie_rdata                         (ubus_pcie_rdata                        ),

    // hxt Ubus
    .ubus_hxt_wen                            (ubus_hxt_wen                           ),
    .ubus_hxt_waddr                          (ubus_hxt_waddr                         ),
    .ubus_hxt_wdata                          (ubus_hxt_wdata                         ),
    .ubus_hxt_ren                            (ubus_hxt_ren                           ),
    .ubus_hxt_raddr                          (ubus_hxt_raddr                         ),
    .ubus_hxt_bken                           (ubus_hxt_bken                          ),
    .ubus_hxt_rdata                          (ubus_hxt_rdata                         ),

    // To fabric logic
    .ubus_wen_logic                          (ubus_wen_logic                         ),
    .ubus_waddr_logic                        (ubus_waddr_logic                       ),
    .ubus_wdata_logic                        (ubus_wdata_logic                       ),
    .ubus_ren_logic                          (ubus_ren_logic                         ),
    .ubus_raddr_logic                        (ubus_raddr_logic                       ),
    .ubus_bken_logic                         (ubus_bken_logic                        ),
    .ubus_rdata_logic                        (ubus_rdata_logic                       ),

    // To PCIe APB
    .tl_cfg_prst                             (tl_cfg_prst                            ),
    .tl_cfg_penable                          (tl_cfg_penable                         ),
    .tl_cfg_psel                             (tl_cfg_psel                            ),
    .tl_cfg_pwrite                           (tl_cfg_pwrite                          ),
    .tl_cfg_paddr                            (tl_cfg_paddr                           ),
    .tl_cfg_pstrb                            (tl_cfg_pstrb                           ),
    .tl_cfg_pwdata                           (tl_cfg_pwdata                          ),
    .tl_cfg_pready                           (tl_cfg_pready                          ),
    .tl_cfg_prdata                           (tl_cfg_prdata                          ),
    .tl_cfg_pslverr                          (tl_cfg_pslverr                         ),
    
    // To HXT APB
    .hxt_apb4_psel_o                         (hxt_apb4_psel_i                        ),
    .hxt_apb4_penable_o                      (hxt_apb4_penable_i                     ),
    .hxt_apb4_pwrite_o                       (hxt_apb4_pwrite_i                      ),
    .hxt_apb4_paddr_o                        (hxt_apb4_paddr_i                       ),
    .hxt_apb4_pwdata_o                       (hxt_apb4_pwdata_i                      ),
    .hxt_apb4_pstrb_o                        (hxt_apb4_pstrb_i                       ),
    .hxt_apb4_pprot_o                        (hxt_apb4_pprot_i                       ),
    .hxt_apb4_prdata_i                       (hxt_apb4_prdata_o                      ),
    .hxt_apb4_pready_i                       (hxt_apb4_pready_o                      ),
    .hxt_apb4_pslverr_i                      (hxt_apb4_pslverr_o                     )
);
// Debug Logic 

img_frame_src #(
    .W          (IMG_W),
    .H          (IMG_H),
    .IDLE_CYCLE (1000000)
) u_img_frame_src (
    .clk       (tl_clk_user     ),
    .rst       (power_on_rst_dly),
    .enable    (img_enable      ),
    .trigger   (img_trigger     ),
    .rd_addr   (img_fb_raddr    ),
    .rd_data   (img_fb_rdata    ),
    .dbg_rd_idx(img_dbg_idx ),
    .frame_cnt (img_frame_cnt   ),
    .width     (img_width       ),
    .height    (img_height      ),
    .data_len  (img_data_len    ),
    .ready     (img_ready       ),
    .busy      (img_busy        ),
    // 相机写源（cam_fb_writer）
    .cam_sel       (img_cam_sel      ),
    .cam_wr_en     (cam_fb_wr_en     ),
    .cam_wr_addr   (cam_fb_wr_addr   ),
    .cam_wr_data   (cam_fb_wr_data   ),
    .cam_frame_cnt (cam_fb_frame_cnt ),
    .cam_data_len  (cam_fb_data_len  ),
    .cam_ready     (cam_fb_ready     ),
    .cam_busy      (cam_fb_busy      )
);

assign  ubus_bken_logic = ubus_bken_logic_dly ;
assign  ubus_rdata_logic= ubus_rdata_logic_dly;

always@(posedge tl_clk_user or posedge power_on_rst_dly )
begin
    if(power_on_rst_dly)begin
        ubus_wen_logic_dly   <= 'd0 ;
        ubus_waddr_logic_dly <= 'd0 ;
        ubus_wdata_logic_dly <= 'd0 ;
        ubus_ren_logic_dly   <= 'd0 ;
        ubus_raddr_logic_dly <= 'd0 ;
    end else begin
        ubus_wen_logic_dly   <= ubus_wen_logic   ;
        ubus_waddr_logic_dly <= ubus_waddr_logic ;
        ubus_wdata_logic_dly <= ubus_wdata_logic ;
        ubus_ren_logic_dly   <= ubus_ren_logic   ;
        ubus_raddr_logic_dly <= ubus_raddr_logic ;
    end
end 

always@(posedge tl_clk_user or posedge power_on_rst_dly )
begin
    if( power_on_rst_dly )
        ubus_bken_logic_dly <= 1'b0;
    else 
        ubus_bken_logic_dly  <= ubus_bken_logic_dly  ? 1'b0 : 
                                ubus_ren_logic_dly   ? 1'b1 : ubus_bken_logic_dly;
end

always@(posedge tl_clk_user or posedge power_on_rst_dly )
begin
    if( power_on_rst_dly ) begin
        ltssm_reg <= 5'd0;
        ltssm_reg_dly <= 5'd0;
    end
    else begin 
        ltssm_reg <= tl_ltssm;
        ltssm_reg_dly <= ltssm_reg;
    end
end

always@(posedge tl_clk_user or posedge power_on_rst_dly )
begin
    if( power_on_rst_dly ) 
        ltssm_change_cnt <= 5'd0;
    else if( ltssm_reg != ltssm_reg_dly )
        ltssm_change_cnt <= ltssm_change_cnt + 1'b1;
end

always@(posedge tl_clk_user or posedge power_on_rst_dly )
begin
    if( power_on_rst_dly ) begin
        ltssm_debug[0]  <= 5'b0;
        ltssm_debug[1]  <= 5'b0;
        ltssm_debug[2]  <= 5'b0;
        ltssm_debug[3]  <= 5'b0;
        ltssm_debug[4]  <= 5'b0;
        ltssm_debug[5]  <= 5'b0;
        ltssm_debug[6]  <= 5'b0;
        ltssm_debug[7]  <= 5'b0;
        ltssm_debug[8]  <= 5'b0;
        ltssm_debug[9]  <= 5'b0;
        ltssm_debug[10] <= 5'b0;
        ltssm_debug[11] <= 5'b0;
        ltssm_debug[12] <= 5'b0;
        ltssm_debug[13] <= 5'b0;
        ltssm_debug[14] <= 5'b0;
        ltssm_debug[15] <= 5'b0;
        ltssm_debug[16] <= 5'b0;
        ltssm_debug[17] <= 5'b0;
        ltssm_debug[18] <= 5'b0;
        ltssm_debug[19] <= 5'b0;
    end else if( ltssm_reg != ltssm_reg_dly) begin
        ltssm_debug[ltssm_change_cnt] <= ltssm_reg_dly;
    end
end

// read logic
always@(posedge tl_clk_user or posedge power_on_rst_dly )
begin
    if( power_on_rst_dly) begin 
        rd_data0 <= 32'd0;
        rd_data1 <= 32'd0;
        rd_data2 <= 32'd0;
        rd_data3 <= 32'd0;
        ubus_rdata_logic_dly <= 32'd0;
    end else begin 
        rd_data0             <= {27'b0,tl_ltssm[4:0]};
        rd_data1             <= {pl_link_up,11'd0,tl_clk_locked,3'b0,16'd0};
        rd_data2             <= {23'b0,9'd0};
        rd_data3             <= {5'd0,tl_cfg_max_read_request_size[2:0],5'd0,tl_cfg_max_payload_size[2:0],
                                 5'd0,tl_cfg_current_link_speed[2:0],   4'd0,tl_cfg_negotiated_width[3:0]};
        case(ubus_raddr_logic_dly[7:0])
            8'd0 : ubus_rdata_logic_dly <= rd_data0;
            8'd1 : ubus_rdata_logic_dly <= rd_data1;
            8'd2 : ubus_rdata_logic_dly <= rd_data2;
            8'd3 : ubus_rdata_logic_dly <= rd_data3;
            8'd4 : ubus_rdata_logic_dly <= rd_data3;
            8'd5 : ubus_rdata_logic_dly <= rd_data3;
            8'd6 : ubus_rdata_logic_dly <= ltssm_change_cnt;
            8'd10: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[0]};
            8'd11: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[1]};
            8'd12: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[2]};
            8'd13: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[3]};
            8'd14: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[4]};
            8'd15: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[5]};
            8'd16: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[6]};
            8'd17: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[7]};
            8'd18: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[9]};
            8'd19: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[10]};
            8'd20: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[11]};
            8'd21: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[12]};
            8'd22: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[13]};
            8'd23: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[14]};
            8'd24: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[15]};
            8'd25: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[16]};
            8'd26: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[17]};
            8'd27: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[18]};
            8'd28: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[19]};
        default:;
        endcase
    end
end
//write logic

always@(posedge tl_clk_user or negedge pcie_power_on_rst_reg )
begin
    if(!pcie_power_on_rst_reg )begin
        pcie_power_on_rst_uart <= 1'b0;
    end else begin                        
    if(ubus_wen_logic_dly == 1'b1 && ubus_waddr_logic_dly[7:0] == 8'd0)
        pcie_power_on_rst_uart <= ubus_wdata_logic_dly[0];
    end
end

assign  debug_led[0] = power_on_rst_dly;
assign  debug_led[1] = pl_link_up;
assign  debug_led[2] = tl_clk_locked;
assign  debug_led[3] = ltssm_reg_dly[4];
//assign  debug_led[4] = ltssm_reg_dly[3];
//assign  debug_led[5] = ltssm_reg_dly[2];
//assign  debug_led[6] = ltssm_reg_dly[1];
//assign  debug_led[7] = ltssm_reg_dly[0];


// ====================================================================
//  摄像头通路（本移植新增）：2x IMX415 + MIPI CSI-2 软 PHY
//  说明：本步只把“传感器是否起来”通过 PCIe 寄存器暴露出来（0x80~0x94），
//        像素数据由 cam_fb_writer 接进帧缓存（CTRL[4]=1 时接管写口）。
//        跨时钟域：慢变电平 + toggle 计数（状态字），像素走 cam_fb_writer 的异步 FIFO。
// ====================================================================
    // ====================================================================
    //  传感器 MCLK（12.5MHz）+ 上电 / 重触发时序
    //
    //  为什么是 12.5MHz（本机上板实测，见本次提交说明）：
    //    · 25MHz（62.5MHz ÷ 2.5 分数分频）    → A 路字节时钟不跳、lane_valid=0、无帧
    //    · 25MHz（50MHz sys_clk ÷ 2，占空 50%）→ 同样不锁（两个独立源都是 25MHz）
    //    · 12.5MHz                                  → 字节时钟跳动、lane_valid=0xf、
    //                                                  约 14.5fps 出帧（链路正常）
    //  参考工程 f9p_imx415x2_top.v:92-98 用 50MHz÷2 = 25MHz，而且两边的 201 条
    //  寄存器表逐字节相同（ui_imx415_reg.v 与参考工程 diff 为空），但本板实测
    //  25MHz 就是不锁——所以本工程改回 12.5MHz。
    //
    //  MCLK = 62.5MHz(tl_clk_user) ÷ 5 = 12.5MHz（半周期 2/3 拍交替 → 周期恒
    //         80ns、占空 40/60）：板上实测能锁、能出帧的就是这一档。
    //  CTRL[2] 现在只当「重触发」用：电平一变 → XCLR 再拉低 134ms → 放开后
    //         重写整张 201 条寄存器表。它原来还兼作 MCLK 源选择（另一档是
    //         50MHz sys_clk ÷ 4），那一档已删，原因见下面 (b) 段。
    // ====================================================================
    wire       w_mclk_sel_raw = img_pattern[0];          // = CTRL[2]

    // CTRL 写在 ep_bar_win.v 里会被解成多拍，期间 img_pattern 会有 1~2 拍的毛刺
    // （实测：同一笔 CTRL 写会造成 2 次模式变化）；按“连续 16 拍相同才认”去抖，
    // 否则一次 CTRL 写会把 XCLR 反复拉低、重触发连跑好几遍。
    reg [15:0] r_sel_sr     = 16'd0;
    reg        r_mclk_sel_f = 1'b0;      // 去抖后的 CTRL[2]（重触发位；名字沿用旧名）
    always @(posedge tl_clk_user) begin
        r_sel_sr <= {r_sel_sr[14:0], w_mclk_sel_raw};
        if (&r_sel_sr)       r_mclk_sel_f <= 1'b1;       // 连续 16 拍为 1
        else if (~|r_sel_sr) r_mclk_sel_f <= 1'b0;       // 连续 16 拍为 0
    end

    // 慢复位：MCLK 先跑，~134ms 后放开 XCLR 并启动 I2C
    //   CTRL[2] 一变就重走一遍（重触发配置：XCLR 再拉低 → 放开 → 重写整张 201 条表）
    reg [22:0] r_pwr_cnt2   = 23'd0;
    reg        r_rst_n_slow = 1'b0;
    reg        r_mclk_sel_d = 1'b0;      // 上一拍的选择位（检测变化）
    reg [3:0]  r_reinit_cnt = 4'd0;      // 重触发次数（诊断）
    wire       w_sel_chg    = (r_mclk_sel_f != r_mclk_sel_d);
    always @(posedge tl_clk_user) begin
        r_mclk_sel_d <= r_mclk_sel_f;
        if (w_sel_chg) begin
            r_pwr_cnt2   <= 23'd0;       // 重新计时 = XCLR 再拉低 134ms
            r_rst_n_slow <= 1'b0;
            if (r_reinit_cnt != 4'hF) r_reinit_cnt <= r_reinit_cnt + 1'b1;
        end else if (r_pwr_cnt2 != 23'h7FFFFF) begin
            r_pwr_cnt2   <= r_pwr_cnt2 + 1'b1;
            r_rst_n_slow <= 1'b0;
        end else begin
            r_rst_n_slow <= 1'b1;
        end
    end

    // CSI 接收器复位：上电计数器一走就放开（原先漏声明 → TD 当悬空网络 → PHY 常复位）
    reg        r_rst_n      = 1'b0;
    always @(posedge tl_clk_user) r_rst_n <= (r_pwr_cnt2 > 23'd1000);

    // cam_fb_writer 的复位：PCIe 上电复位 或 XCLR 拉低期间
    //   （两者都让异步 FIFO 的写侧与读侧指针同时归零，不会只复位一半）
    wire       w_cam_fb_rst = power_on_rst_dly | ~r_rst_n_slow;

    // ---- (a) 62.5MHz → 12.5MHz（旧分频器：acc+2、>=5 时 -3 并翻转，默认）----
    //   半周期 2/3 拍交替 → 输出周期恒 80ns、瞬时占空 40/60（无周期抖动）
    reg [2:0] r_macc     = 3'd0;
    reg       r_mclk_125 = 1'b0;
    always @(posedge tl_clk_user) begin
        if (r_macc >= 3'd5) begin
            r_macc     <= r_macc - 3'd3;      // 等价 (acc+2)-5
            r_mclk_125 <= ~r_mclk_125;
        end else begin
            r_macc     <= r_macc + 3'd2;
        end
    end

    // ---- (b) 已删除：原来的「50MHz sys_clk ÷ 4 = 12.50MHz」那一档 ----
    //   它与 (a) 同频（都是 12.5MHz），唯一区别是占空 50%、周期零抖动；板上从未
    //   选中过（CTRL[2] 默认 0，实测靠 (a) 锁定出帧）。但它一存在，sys_clk 这个
    //   50MHz 输入就必须进通用时钟网络：实测该网（sys_clk_dup_1）走本地绕线，
    //   根就是 H4 那个球，扇出两只挂 r_mdiv2 与 r_mclk_c125，STA 里被算成 local
    //   clock、也没有全局缓冲（DRC RTCLK-5079 / check_timing 的 local clock /
    //   RTCLK-5078 那一类风险）。删掉后 sys_clk 只做 PCIe PLL 的参考时钟，
    //   MCLK 恒等于 (a) 的 12.5MHz，即板上已验证的那一档。
    wire w_mclk = r_mclk_125;

    // 诊断：img_pattern 历史出现过哪些取值（确认 CTRL 写的毛刺，见 0x80[15:12]）
    reg [3:0] r_mode_hits = 4'd0;
    always @(posedge tl_clk_user) begin
        if (img_pattern == 2'd0) r_mode_hits[0] <= 1'b1;
        if (img_pattern == 2'd1) r_mode_hits[1] <= 1'b1;
        if (img_pattern == 2'd2) r_mode_hits[2] <= 1'b1;
        if (img_pattern == 2'd3) r_mode_hits[3] <= 1'b1;
    end

    assign cam_a_mclk   = w_mclk;
    assign cam_b_mclk   = w_mclk;
    assign cam_a_xclr_n = r_rst_n_slow;
    assign cam_b_xclr_n = r_rst_n_slow;

    // IDELAY tap：参考工程实测 45~47 眼图最好（自动扫描会落到 32，误码很高）
    localparam        USE_MANUAL_TAP = 1'b1;
    localparam [5:0]  CAM_IDELAY_TAP = 6'd46;

    wire [5:0]  w_a_delay_tap, w_b_delay_tap;
    wire        w_a_delay_done, w_b_delay_done;
    wire        w_a_byte_clk, w_b_byte_clk;
    wire        w_a_rst_out, w_b_rst_out;
    wire [3:0]  w_a_lane_valid, w_b_lane_valid;
    wire        w_a_sync_wait, w_b_sync_wait, w_a_pkt_done, w_b_pkt_done;
    wire        w_a_vsync, w_b_vsync, w_a_in_frame, w_b_in_frame;
    wire        w_a_in_line, w_b_in_line;
    wire [39:0] w_a_pixel, w_b_pixel;
    wire        w_a_pixel_valid, w_b_pixel_valid;
    wire        w_a_cfg_done, w_b_cfg_done, w_a_bus_err, w_b_bus_err;
    wire [8:0]  w_a_cfg_idx;   wire w_a_cfg_busy;
    wire        w_a_ae_done, w_b_ae_done;
    wire        w_a_bclk_tgl, w_b_bclk_tgl;

    mipi_csi2_rx_ph1p #(.LANE_NUM(4)) u_csi_a (
        .I_ref_clk          (tl_clk_user),
        .I_rst_n            (r_rst_n    ),
        .I_rx_en            (r_rst_n    ),
        .I_clk_pad_hs_p     (mipi_a_clk_hs_p ),
        .I_clk_pad_hs_n     (mipi_a_clk_hs_n ),
        .I_data_pad_hs_p    (mipi_a_data_hs_p),
        .I_data_pad_hs_n    (mipi_a_data_hs_n),
        .I_manual_delay     (cam_tap_cfg[5:0]),
        .I_manual_en        (cam_tap_cfg[6]),
        .O_byte_clk         (w_a_byte_clk),
        .O_rst_out          (w_a_rst_out ),
        .O_lane_valid       (w_a_lane_valid),
        .O_delay_tap        (w_a_delay_tap),
        .O_auto_delay_done  (w_a_delay_done),
        .O_sync_wait        (w_a_sync_wait),
        .O_packet_done      (w_a_pkt_done),
        .O_vsync            (w_a_vsync),
        .O_in_frame         (w_a_in_frame),
        .O_in_line          (w_a_in_line),
        .O_pixel_data       (w_a_pixel),
        .O_pixel_valid      (w_a_pixel_valid)
    );

    mipi_csi2_rx_ph1p #(.LANE_NUM(4)) u_csi_b (
        .I_ref_clk          (tl_clk_user),
        .I_rst_n            (r_rst_n    ),
        .I_rx_en            (r_rst_n    ),
        .I_clk_pad_hs_p     (mipi_b_clk_hs_p ),
        .I_clk_pad_hs_n     (mipi_b_clk_hs_n ),
        .I_data_pad_hs_p    (mipi_b_data_hs_p),
        .I_data_pad_hs_n    (mipi_b_data_hs_n),
        .I_manual_delay     (cam_tap_cfg[5:0]),
        .I_manual_en        (cam_tap_cfg[6]),
        .O_byte_clk         (w_b_byte_clk),
        .O_rst_out          (w_b_rst_out ),
        .O_lane_valid       (w_b_lane_valid),
        .O_delay_tap        (w_b_delay_tap),
        .O_auto_delay_done  (w_b_delay_done),
        .O_sync_wait        (w_b_sync_wait),
        .O_packet_done      (w_b_pkt_done),
        .O_vsync            (w_b_vsync),
        .O_in_frame         (w_b_in_frame),
        .O_in_line          (w_b_in_line),
        .O_pixel_data       (w_b_pixel),
        .O_pixel_valid      (w_b_pixel_valid)
    );

    // ====================================================================
    //  相机像素 → 帧缓存写口（本移植新增）
    //
    //  接 A 路（本板实测锁定的就是 A 路；帧缓存只有一份，B 路 FPGA 侧未接）。
    //  信号/时序约定逐条写在 rtl/ep_side/img/cam_fb_writer.v 头部：
    //    w_a_pixel/w_a_pixel_valid : 1 拍 = 1 组 = RAW10 的 4 个像素
    //    w_a_vsync                 : 1 拍脉冲 = FS  → SOF（复位写指针 + 写帧号）
    //    w_a_in_frame              : 电平，下降沿 = FE → EOF（置帧完成）
    //    w_a_in_line               : 每行 1 拍脉冲（长包头）→ 行号 +1 / 列归零
    //  写口在 img_frame_src 内按 CTRL[4]（img_cam_sel）在两种写源之间 mux。
    // ====================================================================
    cam_fb_writer #(
        .W       (IMG_W),
        .H       (IMG_H),
        .AW      (17),
        .FIFO_AW (9)
    ) u_cam_fb_writer (
        .cam_clk       (w_a_byte_clk    ),
        .cam_rst_n     (w_a_rst_out     ),
        .cam_vsync     (w_a_vsync       ),
        .cam_in_frame  (w_a_in_frame    ),
        .cam_in_line   (w_a_in_line     ),
        .cam_pix       (w_a_pixel       ),
        .cam_pix_valid (w_a_pixel_valid ),

        .clk           (tl_clk_user     ),
        // 重触发（CTRL[4:3] 变化）时 XCLR 会被拉低 134ms：让 cam_fb_writer 的
        // tl 侧与字节侧同时复位，避免只复位一半导致异步 FIFO 写/读指针错位
        .rst           (w_cam_fb_rst    ),

        .fb_wr_en      (cam_fb_wr_en     ),
        .fb_wr_addr    (cam_fb_wr_addr   ),
        .fb_wr_data    (cam_fb_wr_data   ),

        .frame_cnt     (cam_fb_frame_cnt ),
        .data_len      (cam_fb_data_len  ),
        .ready         (cam_fb_ready     ),
        .busy          (cam_fb_busy      ),
        .frame_done    (cam_fb_frame_done),

        .wr_word_cnt   (cam_fb_wr_word_cnt),
        .drop_cnt      (cam_fb_drop_cnt   ),
        .ovf_cnt       (cam_fb_ovf_cnt    )
    );

    ui_cfg_imx415 #(.CLK_DIV(16'd624)) u_cfg_a (
        .I_clk         (tl_clk_user   ),
        .I_rst_n       (r_rst_n_slow  ),
        .I_cam_mode    (2'd1          ),   // 1 = 4K
        .I_ae_req      (1'b0          ),
        .I_ae_data     (8'd100        ),
        .O_cam_scl     (cam_a_scl     ),
        .IO_cam_sda    (cam_a_sda     ),
        .O_cfg_done    (w_a_cfg_done  ),
        .O_ae_cfg_done (w_a_ae_done   ),
        .O_bus_error   (w_a_bus_err   ),
        .O_dbg_idx     (w_a_cfg_idx   ),
        .O_dbg_busy    (w_a_cfg_busy  )
    );

    ui_cfg_imx415 #(.CLK_DIV(16'd624)) u_cfg_b (
        .I_clk         (tl_clk_user   ),
        .I_rst_n       (r_rst_n_slow  ),
        .I_cam_mode    (2'd1          ),
        .I_ae_req      (1'b0          ),
        .I_ae_data     (8'd100        ),
        .O_cam_scl     (cam_b_scl     ),
        .IO_cam_sda    (cam_b_sda     ),
        .O_cfg_done    (w_b_cfg_done  ),
        .O_ae_cfg_done (w_b_ae_done   ),
        .O_bus_error   (w_b_bus_err   )
    );

    // ---- 诊断：I2C 两根线电平 ----
    //   （原来这里还有一个 always @(posedge sys_clk) 的 r_syscnt 计数器，用来验证
    //     sys_clk 在不在跳；它只写不读、状态字里没有它，综合时已被优化成 0 个
    //     触发器。这里一并删掉，免得以后有人把它接出去、又把 sys_clk 拽回通用
    //     时钟网络。）
    reg [2:0] s_a_scl, s_a_sda, s_b_scl, s_b_sda;
    always @(posedge tl_clk_user) begin
        s_a_scl <= {s_a_scl[1:0], cam_a_scl};
        s_a_sda <= {s_a_sda[1:0], cam_a_sda};
        s_b_scl <= {s_b_scl[1:0], cam_b_scl};
        s_b_sda <= {s_b_sda[1:0], cam_b_sda};
    end

    // ---- I2C 状态机进度（跨到 tl 域只做电平同步，慢变量）----
    reg  [8:0] w_a_i2c_idx;   reg w_a_i2c_busy;
    always @(posedge tl_clk_user) begin w_a_i2c_idx <= w_a_cfg_idx; w_a_i2c_busy <= w_a_cfg_busy; end

    // ---- 字节时钟在不在跑 ----
    clk_activity #(.DIV_BITS(15)) u_a_clk_act (.I_clk(w_a_byte_clk), .I_rst_n(w_a_rst_out), .O_tgl(w_a_bclk_tgl));
    clk_activity #(.DIV_BITS(15)) u_b_clk_act (.I_clk(w_b_byte_clk), .I_rst_n(w_b_rst_out), .O_tgl(w_b_bclk_tgl));

    // ---- 字节域 → tl_clk_user 域：vsync / pixel_valid 边沿做成 toggle 再数 ----
    reg a_vs_tgl = 1'b0, b_vs_tgl = 1'b0, a_pv_tgl = 1'b0, b_pv_tgl = 1'b0;
    reg a_vs_d = 1'b0, b_vs_d = 1'b0, a_pv_d = 1'b0, b_pv_d = 1'b0;
    always @(posedge w_a_byte_clk or negedge w_a_rst_out) begin
        if (!w_a_rst_out) begin a_vs_tgl <= 1'b0; a_pv_tgl <= 1'b0; a_vs_d <= 1'b0; a_pv_d <= 1'b0; end
        else begin
            a_vs_d <= w_a_vsync;   if (w_a_vsync   & ~a_vs_d) a_vs_tgl <= ~a_vs_tgl;
            a_pv_d <= w_a_pixel_valid; if (w_a_pixel_valid & ~a_pv_d) a_pv_tgl <= ~a_pv_tgl;
        end
    end
    always @(posedge w_b_byte_clk or negedge w_b_rst_out) begin
        if (!w_b_rst_out) begin b_vs_tgl <= 1'b0; b_pv_tgl <= 1'b0; b_vs_d <= 1'b0; b_pv_d <= 1'b0; end
        else begin
            b_vs_d <= w_b_vsync;   if (w_b_vsync   & ~b_vs_d) b_vs_tgl <= ~b_vs_tgl;
            b_pv_d <= w_b_pixel_valid; if (w_b_pixel_valid & ~b_pv_d) b_pv_tgl <= ~b_pv_tgl;
        end
    end

    // ---- tl_clk_user 域：同步 + 计数 + 状态字 ----
    reg [2:0]  s_a_vs, s_b_vs, s_a_pv, s_b_pv, s_a_tgl, s_b_tgl;
    reg [3:0]  s_a_lane, s_b_lane;
    reg [5:0]  s_a_tap, s_b_tap;
    reg [2:0]  s_a_cfg, s_b_cfg;
    reg [31:0] r_a_frames = 32'd0, r_b_frames = 32'd0, r_a_pix = 32'd0, r_b_pix = 32'd0;
    reg        r_a_bclk_seen = 1'b0, r_b_bclk_seen = 1'b0;
    reg        r_a_pv_seen = 1'b0, r_b_pv_seen = 1'b0;

    always @(posedge tl_clk_user) begin
        s_a_vs   <= {s_a_vs[1:0],   a_vs_tgl};
        s_b_vs   <= {s_b_vs[1:0],   b_vs_tgl};
        s_a_pv   <= {s_a_pv[1:0],   a_pv_tgl};
        s_b_pv   <= {s_b_pv[1:0],   b_pv_tgl};
        s_a_tgl  <= {s_a_tgl[1:0],  w_a_bclk_tgl};
        s_b_tgl  <= {s_b_tgl[1:0],  w_b_bclk_tgl};
        s_a_lane <= w_a_lane_valid;
        s_b_lane <= w_b_lane_valid;
        s_a_tap  <= w_a_delay_tap;
        s_b_tap  <= w_b_delay_tap;
        s_a_cfg  <= {w_a_bus_err, w_a_delay_done, w_a_cfg_done};
        s_b_cfg  <= {w_b_bus_err, w_b_delay_done, w_b_cfg_done};

        if (s_a_vs[2] ^ s_a_vs[1]) r_a_frames <= r_a_frames + 32'd1;
        if (s_b_vs[2] ^ s_b_vs[1]) r_b_frames <= r_b_frames + 32'd1;
        if (s_a_pv[2] ^ s_a_pv[1]) begin r_a_pix <= r_a_pix + 32'd1; r_a_pv_seen <= 1'b1; end
        if (s_b_pv[2] ^ s_b_pv[1]) begin r_b_pix <= r_b_pix + 32'd1; r_b_pv_seen <= 1'b1; end
        if (s_a_tgl[2] ^ s_a_tgl[1]) r_a_bclk_seen <= 1'b1;
        if (s_b_tgl[2] ^ s_b_tgl[1]) r_b_bclk_seen <= 1'b1;
    end

    // 状态字：bit0 字节时钟在跑 | [4:1] lane_valid | 5 cfg_done | 6 bus_err
    //         7 auto_delay_done | 8 in_frame | 9 in_line | 10 收到过像素
    //         bit15 保留 0 | [14:11] img_pattern={CTRL[4]=cam_sel, CTRL[2]=MCLK源}
    //                            历史出现过的取值（每出现一次置 1 位，只增不减，诊断 CTRL 写的毛刺）
    //         [21:16] tap | 22 xclr 已放开 | 23 csi_rst_n | 24/25 SCL/SDA 电平 | [31:26]=110011
    wire [31:0] w_cam_a_stat = {6'b110011, s_a_sda[2], s_a_scl[2], r_rst_n, r_rst_n_slow,
                                s_a_tap, 1'b0, r_mode_hits, r_a_pv_seen, w_a_in_line, w_a_in_frame,
                                s_a_cfg[1], s_a_cfg[2], s_a_cfg[0], s_a_lane, r_a_bclk_seen};
    wire [31:0] w_cam_b_stat = {6'b110011, s_b_sda[2], s_b_scl[2], r_rst_n, r_rst_n_slow,
                                s_b_tap, 5'd0, r_b_pv_seen, w_b_in_line, w_b_in_frame,
                                s_b_cfg[1], s_b_cfg[2], s_b_cfg[0], s_b_lane, r_b_bclk_seen};
    // 0x98 中段 8 位（由原来的 8'd0 改成诊断位）：
    //   [8:5] r_reinit_cnt | [4] 去抖后的 CTRL[2] | [3] 0 | [2] r_rst_n_slow(XCLR)
    //   | [1] 0
    assign w_cam_stat = {32'd0, {r_pwr_cnt2, r_reinit_cnt, r_mclk_sel_f, 1'b0, r_rst_n_slow, 1'b0, w_a_i2c_busy},
                              r_b_pix, r_a_pix, r_b_frames, r_a_frames,
                              w_cam_b_stat, w_cam_a_stat};

    // 串口接收不用了（管脚让给摄像头）


// ====================================================================
//  DDR3 控制器（al_ip/ddr3_mc_0，本移植新增）
//
//  ★ 本步只接「参考时钟 + 复位 + 颗粒引脚」，用户侧（AXI / 调试 APB / 用户刷新）
//    全部静态化，不接任何主设备。
//
//  (1) 参考时钟 ref_clk = sys_clk
//      板上给 FPGA 的那颗 50MHz 单端时钟就是 H4；IP 生成时按 PH1P_REFCLK_TYPE=SINGLE、
//      PH1P_SYSCLK_LOC=H4 配置，所以接 IP 的单端 ref_clk 一路（IP 没有差分 ref_clk 端口，
//      wrapper 端口表见 al_ip/ddr3_mc_0/.ports_ddr3_mc_0.txt:1 `ref_clk; 1`）。
//      H4 的引脚约束一直在本工程里（constraints/ph1p_pcie_case_ep.adc:17，SSTL135），
//      IP 自己不给 refclk 写引脚约束（src/adc/ddr3_mc_0.adc 里没有 ref_clk / refclks 条目），
//      所以这条网同时喂 PCIe 的 u_pcie_pll_ep 和本 IP，不冲突。
//      IPUG034 §2.1.3 建议参考时钟与 AC 信号同 Bank：H4 在 BANK33 = 本 IP 的 AC bank。
//
//  (2) 复位 sys_rst_n（低有效）= pcie_power_on_rst
//      即板上 SW7 那颗复位按钮所在的球 R14，低有效。依据：厂商 DDR 例程 example_top 的
//      sys_rst_n 就是同一个球（09_ddr3_ddrmc_cal_x32_1066mbps/prj_src/adc/ap115v2.adc:5
//      `sys_rst_n R14 LVCMOS33 PULLUP`，注释写着 SW7）；本工程该球已由
//      constraints/ph1p_pcie_case_ep.adc 分配给 pcie_power_on_rst。
//      刻意不取 power_on_rst_dly / tl_rst_user：那两条与 PCIe 链路状态耦合
//      （pcie_mperst、pcie_pll_locked、tl_ltssm），主机每次 PERST / 重新枚举都会把
//      DDR 拉回复位、白跑一遍初始化与训练。
//
//  (3) 颗粒引脚：从 IP 端口直连到顶层端口，中间不插任何逻辑（IPUG034 §3.3.1 的
//      IO 分配规则；厂商例程同样直连）。1 位信号按厂商例程写成标量，
//      实测该例程的 place 报告里顶层端口 `ddr_ck_p` 就落在 H3/DIFF_SSTL135
//      （09 例程 ph1p_ddr_Runs/phy_1/ph1p_ddr_phy.area:67），说明 IP 的
//      set_ippin_assignment 能派生出顶层管脚。
//
//  (4) 用户侧静态化：
//      · AXI：本设计是主（IP 是从），aw/ar/w 的 valid 与 wlast 恒 0 → IP 收不到任何
//        读写命令；bready/rready 取常数 1（无命令即无响应，取 1 不会产生任何事务）。
//        axi_aclk = dhi_clk、axi_aresetn = ddrphy_rst_n：都是 IP 自己输出的用户侧
//        总线时钟/复位（IPUG034 表 2-1：dhi_clk「DHI 总线的时钟输出」、ddrphy_rst_n
//        「DDRPHY 复位信号输出」）。这样 DDR 用户侧自成一个时钟域，不引入新时钟、
//        也不与 tl_clk_user 打交道。
//      · 调试 APB：本步不读校准状态 → psel/penable/pwrite/paddr/pwdata 全置 0；
//        apb_prst_n = cfg_rst_n（与 apb_pclk = cfg_clk 同域）。
//      · 用户刷新：usr_ref_type = 2'b00（IPUG034 表 2-19：00 = 正常 tREFI 自动刷新），
//        usr_ref_req = 1'b0（不请求用户刷新）。
//      · ecc_err_*、ctl_ram_*、ddrphy_rdy 等输出本步不使用，留空（与厂商例程
//        ddrmc_test_top 的接法一致）。
// ====================================================================
// 注意：IP 的 apb_pclk 与 cfg_clk 是同一个物理时钟的两个输出端口，
//       不能同时接到一条 wire（会变成双驱动），这里只取 cfg_clk 一路。
wire w_ddr_cfg_clk   ;   // cfg_clk = IP 的 mcu/APB 域时钟（50MHz）
wire w_ddr_cfg_rst_n ;   // cfg_clk 域复位，用作 apb_prst_n
wire w_ddr_dhi_clk   ;   // 用户总线时钟（= 未来的 AXI 主时钟）
wire w_ddrphy_rst_n  ;   // IP 给用户逻辑的复位

ddr3_mc_0 u_ddr3_mc_0 (
    .ref_clk        (sys_clk             ),
    .sys_rst_n      (pcie_power_on_rst   ),

    .apb_pclk       (                    ),   // 与 cfg_clk 同源，见上方说明
    .apb_prst_n     (w_ddr_cfg_rst_n     ),
    .apb_pready     (                    ),
    .apb_psel       (1'b0                ),
    .apb_penable    (1'b0                ),
    .apb_pwrite     (1'b0                ),
    .apb_paddr      (16'd0               ),
    .apb_pwdata     (32'd0               ),
    .apb_prdata     (                    ),

    .dhi_clk        (w_ddr_dhi_clk       ),
    .cfg_clk        (w_ddr_cfg_clk       ),
    .cfg_rst_n      (w_ddr_cfg_rst_n     ),
    .ddrphy_rst_n   (w_ddrphy_rst_n      ),
    .ddrphy_rdy     (                    ),

    .axi_aclk       (w_ddr_dhi_clk       ),
    .axi_aresetn    (w_ddrphy_rst_n      ),
    .axi_awid       (4'd0                ),
    .axi_awaddr     (29'd0               ),
    .axi_awlen      (8'd0                ),
    .axi_awsize     (3'd0                ),
    .axi_awburst    (2'd0                ),
    .axi_awvalid    (1'b0                ),
    .axi_awready    (                    ),
    .axi_wdata      (256'd0              ),
    .axi_wstrb      (32'd0               ),
    .axi_wlast      (1'b0                ),
    .axi_wvalid     (1'b0                ),
    .axi_wready     (                    ),
    .axi_bid        (                    ),
    .axi_bresp      (                    ),
    .axi_bvalid     (                    ),
    .axi_bready     (1'b1                ),
    .axi_arid       (4'd0                ),
    .axi_araddr     (29'd0               ),
    .axi_arlen      (8'd0                ),
    .axi_arsize     (3'd0                ),
    .axi_arburst    (2'd0                ),
    .axi_arvalid    (1'b0                ),
    .axi_arready    (                    ),
    .axi_rid        (                    ),
    .axi_rdata      (                    ),
    .axi_rresp      (                    ),
    .axi_rlast      (                    ),
    .axi_rvalid     (                    ),
    .axi_rready     (1'b1                ),

    .usr_ref_type   (2'b00               ),
    .usr_ref_req    (1'b0                ),
    .usr_ref_ack    (                    ),
    .ecc_err_sig    (                    ),
    .ecc_err_mul    (                    ),
    .ctl_ram_rst_n  (                    ),
    .ctl_ram_cke    (                    ),

    .ddr_ck_p       (ddr_ck_p            ),
    .ddr_ck_n       (ddr_ck_n            ),
    .ddr_reset_n    (ddr_reset_n         ),
    .ddr_cke        (ddr_cke             ),
    .ddr_odt        (ddr_odt             ),
    .ddr_cs_n       (ddr_cs_n            ),
    .ddr_ras_n      (ddr_ras_n           ),
    .ddr_cas_n      (ddr_cas_n           ),
    .ddr_we_n       (ddr_we_n            ),
    .ddr_ba         (ddr_ba              ),
    .ddr_addr       (ddr_addr            ),
    .ddr_dqs_p      (ddr_dqs_p           ),
    .ddr_dqs_n      (ddr_dqs_n           ),
    .ddr_dq         (ddr_dq              ),
    .ddr_dm         (ddr_dm              )
);

endmodule
