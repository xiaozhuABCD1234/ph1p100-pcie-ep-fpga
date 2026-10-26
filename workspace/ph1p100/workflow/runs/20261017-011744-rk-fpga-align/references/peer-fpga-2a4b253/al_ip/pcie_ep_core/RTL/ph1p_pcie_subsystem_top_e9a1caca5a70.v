
//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2022 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : pcie_subsystem_top.v
//  Author        : Gehong - hong.ge@anlogic.com
//  Last Modified : 2024-07-18 15:28:07
//  Create        : 2023-04-14 13:48:34
//  Description   : AL6100 PCIe IPGen Template
//                  2023-04-17:
//                          1.first initial release
/////////////////////////////////////////////////////////////// 
`timescale 1ns / 1ps

module  ph1p_pcie_subsystem_top_e9a1caca5a70#(
// ====================================================================
// Parameter Define
// ====================================================================
//GUI TAB 1
// System Config
parameter CFG_DNS                                 = 64'h0000_0000_dcba_1edb,
parameter PCIE_CFG_QUICK_LINK                     = 1'b0,
parameter PCIE_CFG_PCLK_SOURCE_SEL                = 2'b00,
parameter PCIE_CFG_PIPE_LANE_FLIP                 = 2'b00,
parameter PCIE_CFG_DEVICE_TYPE                    = "EP",
parameter PCIE_CFG_LINK_SPEED                     = 4'b0001,
parameter PCIE_CFG_LINK_WIDTH                     = 4'b1100,
parameter PCIE_CFG_LANE_ENABLE                    = 4'b0001,
parameter PCIE_CFG_CONTROLLER_LOCATION            = "x69y120z0",
parameter PCIE_CFG_QUARD_LOCATION                 = "BANK94",
parameter PCIE_CFG_LANE0_LOCATION                 = "LANE3",
parameter PCIE_CFG_REF_CLK_LOCATION               = 8'b00000001,
parameter PCIE_CFG_REF_CLK_FREQ                   = 8'd100,
parameter PCIE_CFG_TL_CLK_FREQ                    = 9'd63,
parameter LINK_WIDTH                              = 1, 
//GUI TAB2
// Physical Basic
parameter PCIE_CFG_PF0_ENABLE                     = 1'b1,
parameter PCIE_CFG_PF1_ENABLE                     = 1'b0,
parameter PCIE_CFG_MAX_PAYLOAD_SIZE               = 3'b000,
parameter PCIE_CFG_EXT_TAG                        = 1'b1,
parameter PCIE_CFG_SLOT_CLOCK                     = 1'b1,
parameter PCIE_CFG_FUNC_LVL_RESET                 = 1'b0,

//GUI TAB3
// Physical Bar
parameter PCIE_CFG_PF0_VENDOR_ID                  = 16'h1edb,
parameter PCIE_CFG_PF0_DEVICE_ID                  = 16'h0001,
parameter PCIE_CFG_PF0_REV_NUM                    = 8'h00,
parameter PCIE_CFG_PF0_SUB_VENDOR_ID              = 16'h0000,
parameter PCIE_CFG_PF0_SUB_DEVICE_ID              = 16'h0000,
parameter PCIE_CFG_PF0_CLASS_CODE                 = 24'h000000,
parameter PCIE_CFG_PF0_BAR0_TYPE                  = 1'b0,
parameter PCIE_CFG_PF0_BAR0_64BIT                 = 1'b0,
parameter PCIE_CFG_PF0_BAR0_PREFETCHABLE          = 1'b0,
parameter PCIE_CFG_PF0_BAR0_MASK                  = 32'hFFFFFF00,
parameter PCIE_CFG_PF0_BAR1_TYPE                  = 1'b0,
parameter PCIE_CFG_PF0_BAR1_MASK                  = 32'h00000000,
parameter PCIE_CFG_PF0_BAR2_TYPE                  = 1'b0,
parameter PCIE_CFG_PF0_BAR2_64BIT                 = 1'b0,
parameter PCIE_CFG_PF0_BAR2_PREFETCHABLE          = 1'b0,
parameter PCIE_CFG_PF0_BAR2_MASK                  = 32'h00000000,
parameter PCIE_CFG_PF0_BAR3_TYPE                  = 1'b0,
parameter PCIE_CFG_PF0_BAR3_MASK                  = 32'h00000000,
parameter PCIE_CFG_PF0_BAR4_TYPE                  = 1'b0,
parameter PCIE_CFG_PF0_BAR4_64BIT                 = 1'b0,
parameter PCIE_CFG_PF0_BAR4_PREFETCHABLE          = 1'b0,
parameter PCIE_CFG_PF0_BAR4_MASK                  = 32'h00000000,
parameter PCIE_CFG_PF0_BAR5_TYPE                  = 1'b0,
parameter PCIE_CFG_PF0_BAR5_MASK                  = 32'h00000000,
parameter PCIE_CFG_PF0_EXP_ROM_MASK               = 32'h00000000,

parameter PCIE_CFG_PF1_VENDOR_ID                  = 16'h1edb,
parameter PCIE_CFG_PF1_DEVICE_ID                  = 16'h0002,
parameter PCIE_CFG_PF1_REV_NUM                    = 8'h00,
parameter PCIE_CFG_PF1_SUB_VENDOR_ID              = 16'h0000,
parameter PCIE_CFG_PF1_SUB_DEVICE_ID              = 16'h0000,
parameter PCIE_CFG_PF1_CLASS_CODE                 = 24'h000000,
parameter PCIE_CFG_PF1_BAR0_TYPE                  = 1'b0,
parameter PCIE_CFG_PF1_BAR0_64BIT                 = 1'b0,
parameter PCIE_CFG_PF1_BAR0_PREFETCHABLE          = 1'b0,
parameter PCIE_CFG_PF1_BAR0_MASK                  = 32'h00000000,
parameter PCIE_CFG_PF1_BAR1_TYPE                  = 1'b0,
parameter PCIE_CFG_PF1_BAR1_MASK                  = 32'h00000000,
parameter PCIE_CFG_PF1_BAR2_TYPE                  = 1'b0,
parameter PCIE_CFG_PF1_BAR2_64BIT                 = 1'b0,
parameter PCIE_CFG_PF1_BAR2_PREFETCHABLE          = 1'b0,
parameter PCIE_CFG_PF1_BAR2_MASK                  = 32'h00000000,
parameter PCIE_CFG_PF1_BAR3_TYPE                  = 1'b0,
parameter PCIE_CFG_PF1_BAR3_MASK                  = 32'h00000000,
parameter PCIE_CFG_PF1_BAR4_TYPE                  = 1'b0,
parameter PCIE_CFG_PF1_BAR4_64BIT                 = 1'b0,
parameter PCIE_CFG_PF1_BAR4_PREFETCHABLE          = 1'b0,
parameter PCIE_CFG_PF1_BAR4_MASK                  = 32'h00000000,
parameter PCIE_CFG_PF1_BAR5_TYPE                  = 1'b0,
parameter PCIE_CFG_PF1_BAR5_MASK                  = 32'h00000000,
parameter PCIE_CFG_PF1_EXP_ROM_MASK               = 32'h00000000,

//GUI TAB4
// Virtual Function
parameter PCIE_CFG_PF0_VF_VER_ID                  = 8'h00,
parameter PCIE_CFG_PF0_VF_TOTAL_NUM               = 9'h000,
parameter PCIE_CFG_PF0_VF_OFFSET                  = 16'h0008,
parameter PCIE_CFG_PF0_VF_DEVICE_ID               = 16'h0000,
parameter PCIE_CFG_PF0_VF_DEPENDENCY_LINK         = 8'h00,
parameter PCIE_CFG_PF0_VF_PAGE_SIZE               = 12'h533,
parameter PCIE_CFG_PF0_VF_SUB_DEVICE_ID           = 16'h000,
parameter PCIE_CFG_PF1_VF_VER_ID                  = 8'h00,
parameter PCIE_CFG_PF1_VF_TOTAL_NUM               = 9'h000,
parameter PCIE_CFG_PF1_VF_OFFSET                  = 16'h0008,
parameter PCIE_CFG_PF1_VF_DEVICE_ID               = 16'h0000,
parameter PCIE_CFG_PF1_VF_DEPENDENCY_LINK         = 8'h00,
parameter PCIE_CFG_PF1_VF_PAGE_SIZE               = 12'h533,
parameter PCIE_CFG_PF1_VF_SUB_DEVICE_ID           = 16'h000,

// Virtual Bar
parameter PCIE_CFG_PF0_VF_BAR0_TYPE               = 1'b0,
parameter PCIE_CFG_PF0_VF_BAR0_64BIT              = 1'b0,
parameter PCIE_CFG_PF0_VF_BAR0_PREFETCHABLE       = 1'b0,
parameter PCIE_CFG_PF0_VF_BAR0_MASK               = 32'h00000000,
parameter PCIE_CFG_PF0_VF_BAR1_TYPE               = 1'b0,
parameter PCIE_CFG_PF0_VF_BAR1_MASK               = 32'h00000000,
parameter PCIE_CFG_PF0_VF_BAR2_TYPE               = 1'b0,
parameter PCIE_CFG_PF0_VF_BAR2_64BIT              = 1'b0,
parameter PCIE_CFG_PF0_VF_BAR2_PREFETCHABLE       = 1'b0,
parameter PCIE_CFG_PF0_VF_BAR2_MASK               = 32'h00000000,
parameter PCIE_CFG_PF0_VF_BAR3_TYPE               = 1'b0,
parameter PCIE_CFG_PF0_VF_BAR3_MASK               = 32'h00000000,
parameter PCIE_CFG_PF0_VF_BAR4_TYPE               = 1'b0,
parameter PCIE_CFG_PF0_VF_BAR4_64BIT              = 1'b0,
parameter PCIE_CFG_PF0_VF_BAR4_PREFETCHABLE       = 1'b0,
parameter PCIE_CFG_PF0_VF_BAR4_MASK               = 32'h00000000,
parameter PCIE_CFG_PF0_VF_BAR5_TYPE               = 1'b0,
parameter PCIE_CFG_PF0_VF_BAR5_MASK               = 32'h00000000,
parameter PCIE_CFG_PF1_VF_BAR0_TYPE               = 1'b0,
parameter PCIE_CFG_PF1_VF_BAR0_64BIT              = 1'b0,
parameter PCIE_CFG_PF1_VF_BAR0_PREFETCHABLE       = 1'b0,
parameter PCIE_CFG_PF1_VF_BAR0_MASK               = 32'h00000000,
parameter PCIE_CFG_PF1_VF_BAR1_TYPE               = 1'b0,
parameter PCIE_CFG_PF1_VF_BAR1_MASK               = 32'h00000000,
parameter PCIE_CFG_PF1_VF_BAR2_TYPE               = 1'b0,
parameter PCIE_CFG_PF1_VF_BAR2_64BIT              = 1'b0,
parameter PCIE_CFG_PF1_VF_BAR2_PREFETCHABLE       = 1'b0,
parameter PCIE_CFG_PF1_VF_BAR2_MASK               = 32'h00000000,
parameter PCIE_CFG_PF1_VF_BAR3_TYPE               = 1'b0,
parameter PCIE_CFG_PF1_VF_BAR3_MASK               = 32'h00000000,
parameter PCIE_CFG_PF1_VF_BAR4_TYPE               = 1'b0,
parameter PCIE_CFG_PF1_VF_BAR4_64BIT              = 1'b0,
parameter PCIE_CFG_PF1_VF_BAR4_PREFETCHABLE       = 1'b0,
parameter PCIE_CFG_PF1_VF_BAR4_MASK               = 32'h00000000,
parameter PCIE_CFG_PF1_VF_BAR5_TYPE               = 1'b0,
parameter PCIE_CFG_PF1_VF_BAR5_MASK               = 32'h00000000,

//TAB5
//Legacy Int & MSI Interrput 
parameter PCIE_CFG_PF0_INT_PIN                    = 3'b000,
parameter PCIE_CFG_PF1_INT_PIN                    = 3'b000,
parameter PCIE_CFG_PF0_MSI_ENABLE                 = 1'b0,
parameter PCIE_CFG_PF0_MSI_MME                    = 3'b000,
parameter PCIE_CFG_PF0_MSI_MASKING                = 1'b0,
parameter PCIE_CFG_PF1_MSI_ENABLE                 = 1'b0,
parameter PCIE_CFG_PF1_MSI_MME                    = 3'b000,
parameter PCIE_CFG_PF1_MSI_MASKING                = 1'b0,

//MSI-X Interrput
parameter PCIE_CFG_PF0_MSIX_ENABLE                = 1'b0,
parameter PCIE_CFG_PF0_MSIX_TAB_SIZE              = 11'b0,
parameter PCIE_CFG_PF0_MSIX_TAB_OFFSET            = 29'b0,
parameter PCIE_CFG_PF0_MSIX_TAB_BIR               = 3'b0,
parameter PCIE_CFG_PF0_MSIX_PBA_OFFSET            = 29'b0,
parameter PCIE_CFG_PF0_MSIX_PBA_BIR               = 3'b0,
parameter PCIE_CFG_PF1_MSIX_ENABLE                = 1'b0,
parameter PCIE_CFG_PF1_MSIX_TAB_SIZE              = 11'b0,
parameter PCIE_CFG_PF1_MSIX_TAB_OFFSET            = 29'b0,
parameter PCIE_CFG_PF1_MSIX_TAB_BIR               = 3'b0,
parameter PCIE_CFG_PF1_MSIX_PBA_OFFSET            = 29'b0,
parameter PCIE_CFG_PF1_MSIX_PBA_BIR               = 3'b0,

//TAB 6
// Miscellaneous
parameter PCIE_CFG_POWER_MGT_D1_SUPPORT           = 1'b0,
parameter PCIE_CFG_POWER_MGT_D2_SUPPORT           = 1'b0,
parameter PCIE_CFG_POWER_MGT_ASPM_L0_SUPPORT      = 1'b0,
parameter PCIE_CFG_POWER_MGT_ASPM_L1_SUPPORT      = 1'b0,
parameter PCIE_CFG_POWER_MGT_PME_D0_SUPPORT       = 1'b0,
parameter PCIE_CFG_POWER_MGT_PME_D1_SUPPORT       = 1'b0,
parameter PCIE_CFG_POWER_MGT_PME_D2_SUPPORT       = 1'b0,
parameter PCIE_CFG_POWER_MGT_PME_D3HOT_SUPPORT    = 1'b0,
parameter PCIE_CFG_POWER_MGT_PME_D3COLD_SUPPORT   = 1'b0,
parameter PCIE_CFG_AER_CAP_ENABLE                 = 1'b1,
parameter PCIE_CFG_AER_ECRC_GEN_ENABLE            = 1'b0,
parameter PCIE_CFG_AER_ECRC_CHK_ENABLE            = 1'b0,
parameter PCIE_CFG_DSN_CAP_ENABLE                 = 1'b0,
parameter PCIE_CFG_DSN_NUM                        = 64'h0000_0000_0000_0000,
parameter PCIE_CFG_EXTERNAL_REG_ENABLE            = 1'b0,
parameter PCIE_CFG_EXTERNAL_FIRST_OFFSET          = 8'h00,
parameter PH1P_HXT_FAST_SIM                       = 1'b0
)
(

    // serdes high speed pin

    input      wire                 ref_pad_clk_p                           ,
    input      wire                 ref_pad_clk_n                           ,

    input      wire  [LINK_WIDTH-1:0]   pcie_rx_p                           ,
    input      wire  [LINK_WIDTH-1:0]   pcie_rx_n                           ,
    output     wire  [LINK_WIDTH-1:0]   pcie_tx_p                           ,
    output     wire  [LINK_WIDTH-1:0]   pcie_tx_n                           ,    

    // transcation layer clock signals
    input      wire                 tl_clk_user                             ,
    input      wire                 tl_clk_user_ce_n                        ,
    output     reg                  tl_clk_locked                           ,
    // clock and reset signals
    output     wire                 tl_clk_gate                             ,
    input      wire                 tl_power_on_rst                         ,

    // user apb configure signals

    input      wire                 tl_cfg_pclk                             ,
    input      wire                 tl_cfg_prst                             ,
    input      wire                 tl_cfg_penable                          ,
    input      wire                 tl_cfg_psel                             ,
    input      wire                 tl_cfg_pwrite                           ,
    input      wire  [31:0]         tl_cfg_paddr                            ,
    input      wire  [3:0]          tl_cfg_pstrb                            ,
    input      wire  [31:0]         tl_cfg_pwdata                           ,
    output     wire                 tl_cfg_pready                           ,
    output     wire  [31:0]         tl_cfg_prdata                           ,
    output     wire                 tl_cfg_pslverr                          ,

    //cfg direct access

    output     wire   [7:0]         tl_cfg_tcvc                            , 
    output     wire   [12:0]        tl_cfg_busdev                          , 
    output     wire   [2:0]         tl_cfg_max_payload_size                , 
    output     wire   [2:0]         tl_cfg_max_read_request_size           , 
    output     wire   [2:0]         tl_cfg_current_link_speed              , 
    output     wire   [3:0]         tl_cfg_negotiated_width                , 
    output     wire                 tl_cfg_read_completion_boundary        , 
    output     wire   [7:0]         tl_cfg_pfregs_cmd                      , 
    input      wire   [7:0]         tl_cfg_pf0_primary_bus                 , 
    input      wire   [7:0]         tl_cfg_pf1_primary_bus                 , 
     
    input      wire  [1:0]          tl_int_status                           ,

    // pf legacy int  

    input      wire  [3:0]          tl_int_pincontrol                       ,
    output     wire  [3:0]          tl_int_pinstate                         ,

// pf msi int  

    // pf msi-x
  
    // vf msi 

    // physical ltssm signals 
    output     wire  [1:0]          pl_equ_phase                            ,
    output     wire  [4:0]          tl_ltssm                                ,
    output     wire  [4:0]          pl_ltssm                                ,
    output     wire                 pl_link_up                              ,
    input      wire                 tl_ltssm_enable                         ,
    // PM CLOCK#

    // PM legacy/native 

    // PM link width/speed

    // External register interface 

    // VPD cap signals

    // OBFF signals 

    // PTM signals 

    // DOE cap signals 

    // pin share select 

// physical layer clock signals

    // physical bar size

    input                           apb4_clk_i                              ,
    input                           apb4_preset_i                           ,
    input                           apb4_psel_i                             ,
    input                           apb4_penable_i                          ,
    input                           apb4_pwrite_i                           ,
    input       [31:0]              apb4_paddr_i                            ,
    input       [31:0]              apb4_pwdata_i                           ,
    input       [3:0]               apb4_pstrb_i                            ,
    input       [2:0]               apb4_pprot_i                            ,
    output      [31:0]              apb4_prdata_o                           ,
    output                          apb4_pready_o                           ,
    output                          apb4_pslverr_o                          ,

    // Rx interface 
    input      wire                 tl_rx_wait                              ,
    input      wire                 tl_rx_masknp                            ,
    output     wire  [47:0]         tl_rx_bardec                            ,
    output     wire  [255:0]        tl_rx_data                              ,
    output     wire                 tl_rx_eop                               ,
    output     wire  [7:0]          tl_rx_err                               ,
    output     wire  [9:0]          tl_rx_mchit                             ,
    output     wire                 tl_rx_sop                               ,
    output     wire  [7:0]          tl_rx_valid                             ,

    // TX interface 
    input      wire  [255:0]        tl_tx_data                              ,
    input      wire                 tl_tx_eop                               ,
    input      wire  [7:0]          tl_tx_err                               ,
    input      wire                 tl_tx_sop                               ,
    input      wire                 tl_tx_stream                            ,
    input      wire  [7:0]          tl_tx_valid                             ,
    output     wire                 tl_tx_wait                              ,
    output     wire  [95:0]         tl_tx_credits                            

);

// physical layer clock signals
   
    wire                            pl_pclk_user                            ;

    wire  [31:0]                    tl_int_pf0_msi_mask                     ;
    wire  [31:0]                    tl_int_pf1_msi_mask                     ;

    wire  [1:0]                     tl_int_msi_enable                       ;
    wire  [5:0]                     tl_int_msi_multi_enable                 ;

    wire  [1:0]                     tl_cfg_msix_enable                      ;
    wire  [1:0]                     tl_cfg_msix_function_mask               ;

    wire  [2:0]                     tl_int_vfmsi_enable                     ;
    wire  [31:0]                    tl_int_vfmsi_mask                       ;

    wire  [29:0]                    tl_vpd_addr                             ;
    wire  [1:0]                     tl_vpd_enable                           ;
    wire  [5:0]                     tl_vpd_status                           ;
    wire  [63:0]                    tl_vpd_wrdata                           ;
    wire  [1:0]                     tl_vpd_write                            ;

    wire  [11:0]                    tl_doe_control                          ;
    wire  [63:0]                    tl_doe_wrdata                           ;

    wire  [2:0]                     pinshare_grp0_out_sel              =3'd0;
    wire  [1:0]                     pinshare_grp1_out_sel              =2'd0;

    // clock and reset signals
    reg                             tl_por                                  ;
    reg                             tl_mperst                               ;
    wire                            tl_rdy                                  ;
    wire                            tl_rdy_conf                             ;
    reg                             tl_rst                                  ;
    reg                             tl_crst                                 ;
    wire                            tl_k_rst                                ;

    wire  [1:0]                     tl_flr_req                              ;

    // SCAN & DFT signals
    wire                            scan_clk                              =1;
    wire  [9:0]                     scan_in                               =0;
    wire  [9:0]                     scan_out                                ;
    wire                            scan_mode_n                           =1;
    wire                            scan_rst_n                            =1;
    wire                            scan_enable_n                         =1;
    wire                            scancompress_mode_n                   =1;
    wire                            mbist_mode_n                          =1;
    wire                            dft_jtag_tck                          =1;
    wire                            dft_jtag_trst_n                       =1;
    wire                            dft_jtag_tms                          =0;
    wire                            dft_jtag_tdi                          =0;
    wire                            dft_jtag_tdo                            ;

    // Test

    wire  [8:0]                     test_in_errinj_8_0_bits               =0;
    wire  [4:0]                     test_in_errinj_20_16_bits             =0;

    wire  [3:0]                     test_out_rxval                          ;
    wire  [15:0]                    test_out_txdatak                        ;
    wire  [3:0]                     test_out_txval                          ;

    wire  [255:0]                   pl_sideband                             ;

    //PIPE interface

  // all signals are hardwire below
  // serdes bonded interface
  wire                              cfg_power_on_rst_n                      ;
  wire    [1:0]                     cfg_pipe_lane_flip                      ;
  wire                              cfg_pcs_pipe_rst_n                      ;
  wire                              cfg_pcs_apb_rst_n                       ;
  wire    [1:0]                     cfg_pclk_source_sel                     ;
  wire    [3:0]                     cfg_pcie_lane_enable                    ;
  wire                              cfg_core_sram_init_done                 ;
  wire                              cfg_core_bypass                         ;
  wire                              serdes_osc_clk                          ;
  wire                              pl_pclk                                 ;
  // serdes bonded interface
  wire    [179:0]                   pl_sideband_in                          ;
  wire    [255:0]                   pl_sideband_out                         ;
  wire    [4:0]                     pl_pclk_rate                            ;
  wire    [3:0]                     pl_phystatus                            ;
  wire    [3:0]                     pl_powerdown                            ;
  wire    [2:0]                     pl_rate                                 ;
  wire    [127:0]                   pl_rxdata                               ;
  wire    [15:0]                    pl_rxdatak                              ;
  wire    [3:0]                     pl_rxdatavalid                          ;
  wire    [3:0]                     pl_rxelecidle                           ;
  wire    [3:0]                     pl_rxstandby                            ;
  wire    [3:0]                     pl_rxstartblock                         ;
  wire    [11:0]                    pl_rxstatus                             ;
  wire    [7:0]                     pl_rxsyncheader                         ;
  wire    [3:0]                     pl_rxvalid                              ;
  wire    [3:0]                     pl_txcompliance                         ;
  wire    [127:0]                   pl_txdata                               ;
  wire    [15:0]                    pl_txdatak                              ;
  wire    [3:0]                     pl_txdatavalid                          ;
  wire    [3:0]                     pl_txdetectrx                           ;
  wire    [3:0]                     pl_txelecidle                           ;
  wire    [3:0]                     pl_txstartblock                         ;
  wire    [7:0]                     pl_txsyncheader                         ;
  wire    [2:0]                     pl_width                                ;

  wire                              mac_phy_blockaligncontrol               ;
  wire    [2:0]                     mac_phy_txmargin                        ;
  wire                              mac_phy_txswing                         ;
  wire    [3:0]                     mac_phy_rxpolarity                      ;
  wire    [71:0]                    mac_phy_txdeemph                        ;
  wire    [11:0]                    mac_phy_rxpresethint                    ;
  wire    [23:0]                    mac_phy_fs                              ;
  wire    [23:0]                    mac_phy_lf                              ;
  wire    [19:0]                    mac_phy_local_pset_index                ;
  wire    [3:0]                     mac_phy_getlocal_pset_coef              ;
  wire    [3:0]                     mac_phy_rxeqeval                        ;
  wire    [3:0]                     mac_phy_rxeqinprogress                  ;
  wire    [3:0]                     mac_phy_invalid_req                     ;

  wire    [23:0]                    phy_mac_dirfeedback                     ;
  wire    [31:0]                    phy_mac_fomfeedback                     ;
  wire    [71:0]                    phy_mac_local_tx_pset_coef              ;
  wire    [3:0]                     phy_mac_local_tx_coef_valid             ;
  wire    [23:0]                    phy_mac_localfs                         ;
  wire    [23:0]                    phy_mac_locallf                         ;
  wire    [44:0]                    sideband_in_lane0                       ;
  wire    [44:0]                    sideband_in_lane1                       ;
  wire    [44:0]                    sideband_in_lane2                       ;
  wire    [44:0]                    sideband_in_lane3                       ;
 
  wire    [3:0]                     tl_cfg_vfregs_bit                       ;
  wire    [17:0]                    tl_cfg_pfregs_vfnums                    ;
  wire    [1:0]                     tl_cfg_pfregs_vfenable                  ;
  wire    [1:0]                     tl_cfg_pfregs_vfmse                     ;
 
// ====================================================================
// PCIE IP Internal Logic
// ====================================================================
  reg     [9:0]                     tclk_deskew_cal_lock_cnt                ;
  reg                               tclk_deskew_cal_lock_flag               ;
  reg     [2:0]                     tl_rdy_conf_reg                         ;
  wire                              common_reset_done                       ;
  wire                              rx0_reset_done,rx1_reset_done,rx2_reset_done,rx3_reset_done;
  wire                              tx0_reset_done,tx1_reset_done,tx2_reset_done,tx3_reset_done;
// count the tclk , delay times and wait ready
always@(posedge tl_clk_user or posedge tl_power_on_rst )
begin
    if(tl_power_on_rst) begin
        tclk_deskew_cal_lock_cnt  <= 10'd0;
    end else if((!tclk_deskew_cal_lock_cnt[9] )) begin
        tclk_deskew_cal_lock_cnt  <= tclk_deskew_cal_lock_cnt + 1'b1;
    end
end

always@(posedge tl_clk_user or posedge tl_power_on_rst )
begin
    if(tl_power_on_rst)begin 
        tclk_deskew_cal_lock_flag <= 1'b0;
    end

    else if(tclk_deskew_cal_lock_cnt[9] && common_reset_done && tx2_reset_done && rx2_reset_done && tx3_reset_done && rx3_reset_done)
    
    begin
        tclk_deskew_cal_lock_flag <= 1'b1;
    end
end

// set pcie ip tl_mperst signals
always@(posedge tl_clk_user or posedge tl_power_on_rst )
begin
    if(tl_power_on_rst)begin 
        tl_mperst <= 1'b1;
    end else if(!tclk_deskew_cal_lock_flag) begin
        tl_mperst <= 1'b1;
    end else  begin 
        tl_mperst <= 1'b0;
    end
end

// set pcie ip tl_por signals
always@(posedge tl_clk_user or posedge tl_power_on_rst )
begin
    if(tl_power_on_rst)begin
        tl_por <= 1'b1;
    end else if(!tclk_deskew_cal_lock_flag) begin
        tl_por <= 1'b1;
    end else begin
        tl_por <= 1'b0;
    end
end

// set pcie ip tl_rst signals, need pull up after tl_rdy
always@(posedge tl_clk_user or posedge tl_power_on_rst )
begin
    if(tl_power_on_rst)begin 
        tl_rst  <= 1'b1;
    end else if(!tclk_deskew_cal_lock_flag) begin
        tl_rst  <= 1'b1;
    end else if(tclk_deskew_cal_lock_flag & tl_rdy ) begin 
        tl_rst  <= 1'b0;
    end
end

// set pcie ip tl_crst signals, need pull up after tl_rdy_conf, at least 2 tl_clk cycle
always@(posedge tl_clk_user or posedge tl_power_on_rst )
begin
    if(tl_power_on_rst)begin 
        tl_rdy_conf_reg <= 3'd0;
    end else begin
        tl_rdy_conf_reg <= {tl_rdy_conf_reg[1:0],tl_rdy_conf};
    end
end

always@(posedge tl_clk_user or posedge tl_power_on_rst )
begin
    if(tl_power_on_rst)begin 
        tl_crst  <= 1'b1;
    end else if(!tclk_deskew_cal_lock_flag) begin
        tl_crst  <= 1'b1;
    end else if(tclk_deskew_cal_lock_flag & tl_rdy_conf_reg[2]  ) begin 
        tl_crst  <= 1'b0;
    end
end

// tl_clk_locked
always@(posedge tl_clk_user or posedge tl_power_on_rst )
begin
    if(tl_power_on_rst)begin 
        tl_clk_locked <= 1'b0;
    end else if(tclk_deskew_cal_lock_flag & !tl_crst & !tl_rst & !tl_por & !tl_mperst ) begin
        tl_clk_locked <= 1'b1;
    end else begin 
        tl_clk_locked <= 1'b0;
    end
end

assign tl_k_rst = 1'b0;

assign mac_phy_txmargin          = pl_sideband_out[20:18];
assign mac_phy_txswing           = pl_sideband_out[21];
assign mac_phy_blockaligncontrol = pl_sideband_out[23];
// per lane
assign mac_phy_txdeemph          = {pl_sideband_out[17:0],pl_sideband_out[64+17:64+0],pl_sideband_out[64*2+17:64*2+0],pl_sideband_out[64*3+17:64*3+0]};
assign mac_phy_rxpolarity        = {pl_sideband_out[22],pl_sideband_out[64+22],pl_sideband_out[64*2+22],pl_sideband_out[64*3+22]};
assign mac_phy_fs                = {pl_sideband_out[29:24],pl_sideband_out[64+29:64+24],pl_sideband_out[64*2+29:64*2+24],pl_sideband_out[64*3+29:64*3+24]};
assign mac_phy_lf                = {pl_sideband_out[35:30],pl_sideband_out[64+35:64+30],pl_sideband_out[64*2+35:64*2+30],pl_sideband_out[64*3+35:64*3+30]};
assign mac_phy_rxpresethint      = {pl_sideband_out[38:36],pl_sideband_out[64+38:64+36],pl_sideband_out[64*2+38:64*2+36],pl_sideband_out[64*3+38:64*3+36]};
assign mac_phy_rxeqeval          = {pl_sideband_out[39],pl_sideband_out[64+39],pl_sideband_out[64*2+39],pl_sideband_out[64*3+39]};
assign mac_phy_rxeqinprogress    = {pl_sideband_out[40],pl_sideband_out[64+40],pl_sideband_out[64*2+40],pl_sideband_out[64*3+40]};
assign mac_phy_invalid_req       = {pl_sideband_out[41],pl_sideband_out[64+41],pl_sideband_out[64*2+41],pl_sideband_out[64*3+41]};
assign mac_phy_getlocal_pset_coef= {pl_sideband_out[42],pl_sideband_out[64+42],pl_sideband_out[64*2+42],pl_sideband_out[64*3+42]};
assign mac_phy_local_pset_index  = {pl_sideband_out[47:43],pl_sideband_out[64+47:64+43],pl_sideband_out[64*2+47:64*2+43],pl_sideband_out[64*3+47:64*3+43]};
// to pcie_top
assign pl_sideband_in            = {sideband_in_lane3,sideband_in_lane2,sideband_in_lane1,sideband_in_lane0};
assign sideband_in_lane3         = {phy_mac_dirfeedback[5:0],phy_mac_fomfeedback[7:0],phy_mac_locallf[5:0],phy_mac_localfs[5:0],phy_mac_local_tx_pset_coef[17:0],phy_mac_local_tx_coef_valid[0]};
assign sideband_in_lane2         = {phy_mac_dirfeedback[11:6],phy_mac_fomfeedback[15:8],phy_mac_locallf[11:6],phy_mac_localfs[11:6],phy_mac_local_tx_pset_coef[35:18],phy_mac_local_tx_coef_valid[1]};
assign sideband_in_lane1         = {phy_mac_dirfeedback[17:12],phy_mac_fomfeedback[23:16],phy_mac_locallf[17:12],phy_mac_localfs[17:12],phy_mac_local_tx_pset_coef[53:36],phy_mac_local_tx_coef_valid[2]};
assign sideband_in_lane0         = {phy_mac_dirfeedback[23:18],phy_mac_fomfeedback[31:24],phy_mac_locallf[23:18],phy_mac_localfs[23:18],phy_mac_local_tx_pset_coef[71:54],phy_mac_local_tx_coef_valid[3]};

//debug

//Pin share signals

// ====================================================================
// PCIE IP Inst
// ====================================================================
PH1P_PHY_PCIE_V1#(
    .CFG_DNS                                 (CFG_DNS                              ),
    .CFG_TLAUXCLK_FR_USER                    (1'b0                                 ),
    .PCIE_CFG_QUICK_LINK                     (PCIE_CFG_QUICK_LINK                  ),
    .PCIE_CFG_TL_POS_EN                      (1'b0                                 ),
    .PCIE_CFG_PCLK_SOURCE_SEL                (PCIE_CFG_PCLK_SOURCE_SEL             ),
    .PCIE_CFG_PIPE_LANE_FLIP                 (PCIE_CFG_PIPE_LANE_FLIP              ),

    // GUI TAB1
    .PCIE_CFG_DEVICE_TYPE                    (PCIE_CFG_DEVICE_TYPE                 ),
    .PCIE_CFG_LINK_SPEED                     (PCIE_CFG_LINK_SPEED                  ),
    .PCIE_CFG_LINK_WIDTH                     (PCIE_CFG_LINK_WIDTH                  ),
    .PCIE_CFG_CONTROLLER_LOCATION            (PCIE_CFG_CONTROLLER_LOCATION         ),
    .PCIE_CFG_LANE_ENABLE                    (PCIE_CFG_LANE_ENABLE                 ),
    .PCIE_CFG_QUAD_LOCATION                  (4'b1000                              ),
    .PCIE_CFG_LANE0_LOCATION                 (4'b1000                              ),
    .PCIE_CFG_REF_CLK_LOCATION               (PCIE_CFG_REF_CLK_LOCATION            ),
    .PCIE_CFG_REF_CLK_FREQ                   (PCIE_CFG_REF_CLK_FREQ                ),
    .PCIE_CFG_TL_CLK_FREQ                    (PCIE_CFG_TL_CLK_FREQ                 ),

    // GUI TAB2
    .PCIE_CFG_PF0_ENABLE                     (PCIE_CFG_PF0_ENABLE                  ),
    .PCIE_CFG_PF1_ENABLE                     (PCIE_CFG_PF1_ENABLE                  ),
    .PCIE_CFG_MAX_PAYLOAD_SIZE               (PCIE_CFG_MAX_PAYLOAD_SIZE            ),
    .PCIE_CFG_EXT_TAG                        (PCIE_CFG_EXT_TAG                     ),
    .PCIE_CFG_SLOT_CLOCK                     (PCIE_CFG_SLOT_CLOCK                  ),
    .PCIE_CFG_FUNC_LVL_RESET                 (PCIE_CFG_FUNC_LVL_RESET              ),

    // GUI TAB3
    .PCIE_CFG_PF0_VENDOR_ID                  (PCIE_CFG_PF0_VENDOR_ID               ),
    .PCIE_CFG_PF0_DEVICE_ID                  (PCIE_CFG_PF0_DEVICE_ID               ),
    .PCIE_CFG_PF0_REV_NUM                    (PCIE_CFG_PF0_REV_NUM                 ),
    .PCIE_CFG_PF0_SUB_VENDOR_ID              (PCIE_CFG_PF0_SUB_VENDOR_ID           ),
    .PCIE_CFG_PF0_SUB_DEVICE_ID              (PCIE_CFG_PF0_SUB_DEVICE_ID           ),
    .PCIE_CFG_PF0_CLASS_CODE                 (PCIE_CFG_PF0_CLASS_CODE              ),
    .PCIE_CFG_PF1_VENDOR_ID                  (PCIE_CFG_PF1_VENDOR_ID               ),
    .PCIE_CFG_PF1_DEVICE_ID                  (PCIE_CFG_PF1_DEVICE_ID               ),
    .PCIE_CFG_PF1_REV_NUM                    (PCIE_CFG_PF1_REV_NUM                 ),
    .PCIE_CFG_PF1_SUB_VENDOR_ID              (PCIE_CFG_PF1_SUB_VENDOR_ID           ),
    .PCIE_CFG_PF1_SUB_DEVICE_ID              (PCIE_CFG_PF1_SUB_DEVICE_ID           ),
    .PCIE_CFG_PF1_CLASS_CODE                 (PCIE_CFG_PF1_CLASS_CODE              ),

    // GUI TAB4
    // Physical Bar
    .PCIE_CFG_PF0_BAR0_TYPE                  (PCIE_CFG_PF0_BAR0_TYPE               ),
    .PCIE_CFG_PF0_BAR0_64BIT                 (PCIE_CFG_PF0_BAR0_64BIT              ),
    .PCIE_CFG_PF0_BAR0_PREFETCHABLE          (PCIE_CFG_PF0_BAR0_PREFETCHABLE       ),
    .PCIE_CFG_PF0_BAR0_MASK                  (PCIE_CFG_PF0_BAR0_MASK               ),
    .PCIE_CFG_PF0_BAR1_TYPE                  (PCIE_CFG_PF0_BAR1_TYPE               ),
    .PCIE_CFG_PF0_BAR1_MASK                  (PCIE_CFG_PF0_BAR1_MASK               ),
    .PCIE_CFG_PF0_BAR2_TYPE                  (PCIE_CFG_PF0_BAR2_TYPE               ),
    .PCIE_CFG_PF0_BAR2_64BIT                 (PCIE_CFG_PF0_BAR2_64BIT              ),
    .PCIE_CFG_PF0_BAR2_PREFETCHABLE          (PCIE_CFG_PF0_BAR2_PREFETCHABLE       ),
    .PCIE_CFG_PF0_BAR2_MASK                  (PCIE_CFG_PF0_BAR2_MASK               ),
    .PCIE_CFG_PF0_BAR3_TYPE                  (PCIE_CFG_PF0_BAR3_TYPE               ),
    .PCIE_CFG_PF0_BAR3_MASK                  (PCIE_CFG_PF0_BAR3_MASK               ),
    .PCIE_CFG_PF0_BAR4_TYPE                  (PCIE_CFG_PF0_BAR4_TYPE               ),
    .PCIE_CFG_PF0_BAR4_64BIT                 (PCIE_CFG_PF0_BAR4_64BIT              ),
    .PCIE_CFG_PF0_BAR4_PREFETCHABLE          (PCIE_CFG_PF0_BAR4_PREFETCHABLE       ),
    .PCIE_CFG_PF0_BAR4_MASK                  (PCIE_CFG_PF0_BAR4_MASK               ),
    .PCIE_CFG_PF0_BAR5_TYPE                  (PCIE_CFG_PF0_BAR5_TYPE               ),
    .PCIE_CFG_PF0_BAR5_MASK                  (PCIE_CFG_PF0_BAR5_MASK               ),
    .PCIE_CFG_PF0_EXP_ROM_MASK               (PCIE_CFG_PF0_EXP_ROM_MASK            ),
    .PCIE_CFG_PF1_BAR0_TYPE                  (PCIE_CFG_PF1_BAR0_TYPE               ),
    .PCIE_CFG_PF1_BAR0_64BIT                 (PCIE_CFG_PF1_BAR0_64BIT              ),
    .PCIE_CFG_PF1_BAR0_PREFETCHABLE          (PCIE_CFG_PF1_BAR0_PREFETCHABLE       ),
    .PCIE_CFG_PF1_BAR0_MASK                  (PCIE_CFG_PF1_BAR0_MASK               ),
    .PCIE_CFG_PF1_BAR1_TYPE                  (PCIE_CFG_PF1_BAR1_TYPE               ),
    .PCIE_CFG_PF1_BAR1_MASK                  (PCIE_CFG_PF1_BAR1_MASK               ),
    .PCIE_CFG_PF1_BAR2_TYPE                  (PCIE_CFG_PF1_BAR2_TYPE               ),
    .PCIE_CFG_PF1_BAR2_64BIT                 (PCIE_CFG_PF1_BAR2_64BIT              ),
    .PCIE_CFG_PF1_BAR2_PREFETCHABLE          (PCIE_CFG_PF1_BAR2_PREFETCHABLE       ),
    .PCIE_CFG_PF1_BAR2_MASK                  (PCIE_CFG_PF1_BAR2_MASK               ),
    .PCIE_CFG_PF1_BAR3_TYPE                  (PCIE_CFG_PF1_BAR3_TYPE               ),
    .PCIE_CFG_PF1_BAR3_MASK                  (PCIE_CFG_PF1_BAR3_MASK               ),
    .PCIE_CFG_PF1_BAR4_TYPE                  (PCIE_CFG_PF1_BAR4_TYPE               ),
    .PCIE_CFG_PF1_BAR4_64BIT                 (PCIE_CFG_PF1_BAR4_64BIT              ),
    .PCIE_CFG_PF1_BAR4_PREFETCHABLE          (PCIE_CFG_PF1_BAR4_PREFETCHABLE       ),
    .PCIE_CFG_PF1_BAR4_MASK                  (PCIE_CFG_PF1_BAR4_MASK               ),
    .PCIE_CFG_PF1_BAR5_TYPE                  (PCIE_CFG_PF1_BAR5_TYPE               ),
    .PCIE_CFG_PF1_BAR5_MASK                  (PCIE_CFG_PF1_BAR5_MASK               ),
    .PCIE_CFG_PF1_EXP_ROM_MASK               (PCIE_CFG_PF1_EXP_ROM_MASK            ),

    // GUI TAB5
    .PCIE_CFG_PF0_VF_VER_ID                  (PCIE_CFG_PF0_VF_VER_ID               ),
    .PCIE_CFG_PF0_VF_TOTAL_NUM               (PCIE_CFG_PF0_VF_TOTAL_NUM            ),
    .PCIE_CFG_PF0_VF_OFFSIT                  (PCIE_CFG_PF0_VF_OFFSET               ),
    .PCIE_CFG_PF0_VF_DEVICE_ID               (PCIE_CFG_PF0_VF_DEVICE_ID            ),
    .PCIE_CFG_PF0_VF_DEPENDENCY_LINK         (PCIE_CFG_PF0_VF_DEPENDENCY_LINK      ),
    .PCIE_CFG_PF0_VF_PAGE_SIZE               (PCIE_CFG_PF0_VF_PAGE_SIZE            ),
    .PCIE_CFG_PF0_VF_SUB_DEVICE_ID           (PCIE_CFG_PF0_VF_SUB_DEVICE_ID        ),
    .PCIE_CFG_PF1_VF_VER_ID                  (PCIE_CFG_PF1_VF_VER_ID               ),
    .PCIE_CFG_PF1_VF_TOTAL_NUM               (PCIE_CFG_PF1_VF_TOTAL_NUM            ),
    .PCIE_CFG_PF1_VF_OFFSIT                  (PCIE_CFG_PF1_VF_OFFSET               ),
    .PCIE_CFG_PF1_VF_DEVICE_ID               (PCIE_CFG_PF1_VF_DEVICE_ID            ),
    .PCIE_CFG_PF1_VF_DEPENDENCY_LINK         (PCIE_CFG_PF1_VF_DEPENDENCY_LINK      ),
    .PCIE_CFG_PF1_VF_PAGE_SIZE               (PCIE_CFG_PF1_VF_PAGE_SIZE            ),
    .PCIE_CFG_PF1_VF_SUB_DEVICE_ID           (PCIE_CFG_PF1_VF_SUB_DEVICE_ID        ),

    // GUI TAB6
    // Virtual Bar
    .PCIE_CFG_PF0_VF_BAR0_TYPE               (PCIE_CFG_PF0_VF_BAR0_TYPE            ),
    .PCIE_CFG_PF0_VF_BAR0_64BIT              (PCIE_CFG_PF0_VF_BAR0_64BIT           ),
    .PCIE_CFG_PF0_VF_BAR0_PREFETCHABLE       (PCIE_CFG_PF0_VF_BAR0_PREFETCHABLE    ),
    .PCIE_CFG_PF0_VF_BAR0_MASK               (PCIE_CFG_PF0_VF_BAR0_MASK            ),
    .PCIE_CFG_PF0_VF_BAR1_TYPE               (PCIE_CFG_PF0_VF_BAR1_TYPE            ),
    .PCIE_CFG_PF0_VF_BAR1_MASK               (PCIE_CFG_PF0_VF_BAR1_MASK            ),
    .PCIE_CFG_PF0_VF_BAR2_TYPE               (PCIE_CFG_PF0_VF_BAR2_TYPE            ),
    .PCIE_CFG_PF0_VF_BAR2_64BIT              (PCIE_CFG_PF0_VF_BAR2_64BIT           ),
    .PCIE_CFG_PF0_VF_BAR2_PREFETCHABLE       (PCIE_CFG_PF0_VF_BAR2_PREFETCHABLE    ),
    .PCIE_CFG_PF0_VF_BAR2_MASK               (PCIE_CFG_PF0_VF_BAR2_MASK            ),
    .PCIE_CFG_PF0_VF_BAR3_TYPE               (PCIE_CFG_PF0_VF_BAR3_TYPE            ),
    .PCIE_CFG_PF0_VF_BAR3_MASK               (PCIE_CFG_PF0_VF_BAR3_MASK            ),
    .PCIE_CFG_PF0_VF_BAR4_TYPE               (PCIE_CFG_PF0_VF_BAR4_TYPE            ),
    .PCIE_CFG_PF0_VF_BAR4_64BIT              (PCIE_CFG_PF0_VF_BAR4_64BIT           ),
    .PCIE_CFG_PF0_VF_BAR4_PREFETCHABLE       (PCIE_CFG_PF0_VF_BAR4_PREFETCHABLE    ),
    .PCIE_CFG_PF0_VF_BAR4_MASK               (PCIE_CFG_PF0_VF_BAR4_MASK            ),
    .PCIE_CFG_PF0_VF_BAR5_TYPE               (PCIE_CFG_PF0_VF_BAR5_TYPE            ),
    .PCIE_CFG_PF0_VF_BAR5_MASK               (PCIE_CFG_PF0_VF_BAR5_MASK            ),
    .PCIE_CFG_PF1_VF_BAR0_TYPE               (PCIE_CFG_PF1_VF_BAR0_TYPE            ),
    .PCIE_CFG_PF1_VF_BAR0_64BIT              (PCIE_CFG_PF1_VF_BAR0_64BIT           ),
    .PCIE_CFG_PF1_VF_BAR0_PREFETCHABLE       (PCIE_CFG_PF1_VF_BAR0_PREFETCHABLE    ),
    .PCIE_CFG_PF1_VF_BAR0_MASK               (PCIE_CFG_PF1_VF_BAR0_MASK            ),
    .PCIE_CFG_PF1_VF_BAR1_TYPE               (PCIE_CFG_PF1_VF_BAR1_TYPE            ),
    .PCIE_CFG_PF1_VF_BAR1_MASK               (PCIE_CFG_PF1_VF_BAR1_MASK            ),
    .PCIE_CFG_PF1_VF_BAR2_TYPE               (PCIE_CFG_PF1_VF_BAR2_TYPE            ),
    .PCIE_CFG_PF1_VF_BAR2_64BIT              (PCIE_CFG_PF1_VF_BAR2_64BIT           ),
    .PCIE_CFG_PF1_VF_BAR2_PREFETCHABLE       (PCIE_CFG_PF1_VF_BAR2_PREFETCHABLE    ),
    .PCIE_CFG_PF1_VF_BAR2_MASK               (PCIE_CFG_PF1_VF_BAR2_MASK            ),
    .PCIE_CFG_PF1_VF_BAR3_TYPE               (PCIE_CFG_PF1_VF_BAR3_TYPE            ),
    .PCIE_CFG_PF1_VF_BAR3_MASK               (PCIE_CFG_PF1_VF_BAR3_MASK            ),
    .PCIE_CFG_PF1_VF_BAR4_TYPE               (PCIE_CFG_PF1_VF_BAR4_TYPE            ),
    .PCIE_CFG_PF1_VF_BAR4_64BIT              (PCIE_CFG_PF1_VF_BAR4_64BIT           ),
    .PCIE_CFG_PF1_VF_BAR4_PREFETCHABLE       (PCIE_CFG_PF1_VF_BAR4_PREFETCHABLE    ),
    .PCIE_CFG_PF1_VF_BAR4_MASK               (PCIE_CFG_PF1_VF_BAR4_MASK            ),
    .PCIE_CFG_PF1_VF_BAR5_TYPE               (PCIE_CFG_PF1_VF_BAR5_TYPE            ),
    .PCIE_CFG_PF1_VF_BAR5_MASK               (PCIE_CFG_PF1_VF_BAR5_MASK            ),

    // GUI TAB7
    .PCIE_CFG_PF0_INT_PIN                    (PCIE_CFG_PF0_INT_PIN                 ),
    .PCIE_CFG_PF1_INT_PIN                    (PCIE_CFG_PF1_INT_PIN                 ),

    .PCIE_CFG_PF0_MSI_ENABLE                 (PCIE_CFG_PF0_MSI_ENABLE              ),
    .PCIE_CFG_PF0_MSI_MME                    (PCIE_CFG_PF0_MSI_MME                 ),
    .PCIE_CFG_PF0_MSI_MASKING                (PCIE_CFG_PF0_MSI_MASKING             ),
    .PCIE_CFG_PF1_MSI_ENABLE                 (PCIE_CFG_PF1_MSI_ENABLE              ),
    .PCIE_CFG_PF1_MSI_MME                    (PCIE_CFG_PF1_MSI_MME                 ),
    .PCIE_CFG_PF1_MSI_MASKING                (PCIE_CFG_PF1_MSI_MASKING             ),

    // GUI TAB8 
    .PCIE_CFG_PF0_MSIX_ENABLE                (PCIE_CFG_PF0_MSIX_ENABLE             ),
    .PCIE_CFG_PF0_MSIX_TAB_SIZE              (PCIE_CFG_PF0_MSIX_TAB_SIZE           ),
    .PCIE_CFG_PF0_MSIX_TAB_OFFSET            (PCIE_CFG_PF0_MSIX_TAB_OFFSET         ),
    .PCIE_CFG_PF0_MSIX_TAB_BIR               (PCIE_CFG_PF0_MSIX_TAB_BIR            ),
    .PCIE_CFG_PF0_MSIX_PBA_OFFSET            (PCIE_CFG_PF0_MSIX_PBA_OFFSET         ),
    .PCIE_CFG_PF0_MSIX_PBA_BIR               (PCIE_CFG_PF0_MSIX_PBA_BIR            ),
    .PCIE_CFG_PF1_MSIX_ENABLE                (PCIE_CFG_PF1_MSIX_ENABLE             ),
    .PCIE_CFG_PF1_MSIX_TAB_SIZE              (PCIE_CFG_PF1_MSIX_TAB_SIZE           ),
    .PCIE_CFG_PF1_MSIX_TAB_OFFSET            (PCIE_CFG_PF1_MSIX_TAB_OFFSET         ),
    .PCIE_CFG_PF1_MSIX_TAB_BIR               (PCIE_CFG_PF1_MSIX_TAB_BIR            ),
    .PCIE_CFG_PF1_MSIX_PBA_OFFSET            (PCIE_CFG_PF1_MSIX_PBA_OFFSET         ),
    .PCIE_CFG_PF1_MSIX_PBA_BIR               (PCIE_CFG_PF1_MSIX_PBA_BIR            ),

    // GUI TAB9
    .PCIE_CFG_POWER_MGT_D1_SUPPORT           (PCIE_CFG_POWER_MGT_D1_SUPPORT        ),
    .PCIE_CFG_POWER_MGT_D2_SUPPORT           (PCIE_CFG_POWER_MGT_D2_SUPPORT        ),
    .PCIE_CFG_POWER_MGT_ASPM_L0_SUPPORT      (PCIE_CFG_POWER_MGT_ASPM_L0_SUPPORT   ),
    .PCIE_CFG_POWER_MGT_ASPM_L1_SUPPORT      (PCIE_CFG_POWER_MGT_ASPM_L1_SUPPORT   ),
    .PCIE_CFG_POWER_MGT_PME_D0_SUPPORT       (PCIE_CFG_POWER_MGT_PME_D0_SUPPORT    ),
    .PCIE_CFG_POWER_MGT_PME_D1_SUPPORT       (PCIE_CFG_POWER_MGT_PME_D1_SUPPORT    ),
    .PCIE_CFG_POWER_MGT_PME_D2_SUPPORT       (PCIE_CFG_POWER_MGT_PME_D2_SUPPORT    ),
    .PCIE_CFG_POWER_MGT_PME_D3HOT_SUPPORT    (PCIE_CFG_POWER_MGT_PME_D3HOT_SUPPORT ),
    .PCIE_CFG_POWER_MGT_PME_D3COLD_SUPPORT   (PCIE_CFG_POWER_MGT_PME_D3COLD_SUPPORT),
    .PCIE_CFG_AER_CAP_ENABLE                 (PCIE_CFG_AER_CAP_ENABLE              ),
    .PCIE_CFG_AER_ECRC_GEN_ENABLE            (PCIE_CFG_AER_ECRC_GEN_ENABLE         ),
    .PCIE_CFG_AER_ECRC_CHK_ENABLE            (PCIE_CFG_AER_ECRC_CHK_ENABLE         ),
    .PCIE_CFG_DSN_CAP_ENABLE                 (PCIE_CFG_DSN_CAP_ENABLE              ),
    .PCIE_CFG_DSN_NUM                        (PCIE_CFG_DSN_NUM                     ),
    .PCIE_CFG_EXTERNAL_REG_ENABLE            (PCIE_CFG_EXTERNAL_REG_ENABLE         ),
    .PCIE_CFG_EXTERNAL_FIRST_OFFSET          (PCIE_CFG_EXTERNAL_FIRST_OFFSET       )

) u_pcie_top
(
    // transcation layer clock signals
    .tl_clk_user                             (tl_clk_user                          ),
    .tl_clk_user_ce_n                        (tl_clk_user_ce_n                     ),

    // physical layer clock signals
    .pl_pclk_user                            (pl_pclk_user                         ),

    // other clock and reset signals
    .tl_clk_gate                             (tl_clk_gate                          ),
    .tl_clk_user_freq                        (PCIE_CFG_TL_CLK_FREQ                 ),
    .tl_power_on_rst                         (tl_power_on_rst                      ),
    .tl_por                                  (tl_por                               ),
    .tl_mperst                               (tl_mperst                            ),
    .tl_rdy                                  (tl_rdy                               ),
    .tl_rdy_conf                             (tl_rdy_conf                          ),
    .tl_rst                                  (tl_rst                               ),
    .tl_crst                                 (tl_crst                              ),
    .tl_k_rst                                (tl_k_rst                             ),

    .tl_flr_req                              (                                     ),

    // user apb configure signals

    .tl_cfg_pclk                             (tl_cfg_pclk                          ),
    .tl_cfg_prst                             (tl_cfg_prst                          ),
    .tl_cfg_penable                          (tl_cfg_penable                       ),
    .tl_cfg_psel                             (tl_cfg_psel                          ),
    .tl_cfg_pwrite                           (tl_cfg_pwrite                        ),
    .tl_cfg_paddr                            (tl_cfg_paddr                         ),
    .tl_cfg_pstrb                            (tl_cfg_pstrb                         ),
    .tl_cfg_pwdata                           (tl_cfg_pwdata                        ),
    .tl_cfg_pready                           (tl_cfg_pready                        ),
    .tl_cfg_prdata                           (tl_cfg_prdata                        ),
    .tl_cfg_pslverr                          (tl_cfg_pslverr                       ),

    // cfg direct access

    .tl_cfg_tcvc                             (tl_cfg_tcvc                          ),
    .tl_cfg_busdev                           (tl_cfg_busdev                        ),
    .tl_cfg_max_payload_size                 (tl_cfg_max_payload_size              ),
    .tl_cfg_max_read_request_size            (tl_cfg_max_read_request_size         ),
    .tl_cfg_current_link_speed               (tl_cfg_current_link_speed            ),
    .tl_cfg_negotiated_width                 (tl_cfg_negotiated_width              ),
    .tl_cfg_read_completion_boundary         (tl_cfg_read_completion_boundary      ),
    .tl_cfg_pfregs_cmd                       (tl_cfg_pfregs_cmd                    ),
    .tl_cfg_pf0_primary_bus                  (tl_cfg_pf0_primary_bus               ),
    .tl_cfg_pf1_primary_bus                  (tl_cfg_pf1_primary_bus               ),
  
    .tl_cfg_vfregs_bit_sel                   (3'd0                                 ),
    .tl_cfg_vfregs_bit                       (tl_cfg_vfregs_bit                    ),
    .tl_cfg_pfregs_vfnums                    (tl_cfg_pfregs_vfnums                 ),
    .tl_cfg_pfregs_vfenable                  (tl_cfg_pfregs_vfenable               ),
    .tl_cfg_pfregs_vfmse                     (tl_cfg_pfregs_vfmse                  ),
  
    // pf legacy int / msi

    .tl_int_status                           (tl_int_status                        ),

    .tl_int_pincontrol                       (tl_int_pincontrol                    ),
    .tl_int_pinstate                         (tl_int_pinstate                      ),

    .tl_int_msireq                           (2'd0                                 ),
    .tl_int_msinum                           (10'd0                                ),
    .tl_int_msiack                           (                                     ),
    .tl_int_msi_enable                       (tl_int_msi_enable                    ),
    .tl_int_msi_multi_enable                 (tl_int_msi_multi_enable              ),
    .tl_int_pf0_msi_pending                  (32'd0                                ),
    .tl_int_pf1_msi_pending                  (32'd0                                ),
    .tl_int_pf0_msi_mask                     (tl_int_pf0_msi_mask                  ),
    .tl_int_pf1_msi_mask                     (tl_int_pf1_msi_mask                  ),

    .tl_cfg_msix_enable                      (tl_cfg_msix_enable                   ),
    .tl_cfg_msix_function_mask               (tl_cfg_msix_function_mask            ),

    .tl_int_vfmsifid                         (16'd0                                ),
    .tl_int_vfmsinum                         (5'd0                                 ),
    .tl_int_vfmsireq                         (1'b0                                 ),
    .tl_int_vfmsiack                         (                                     ),
    .tl_int_vfmsi_enable_mask_sel            (8'd0                                 ),
    .tl_int_vfmsi_enable                     (tl_int_vfmsi_enable                  ),
    .tl_int_vfmsi_mask                       (tl_int_vfmsi_mask                    ),

    .pl_equ_phase                            (pl_equ_phase                         ),
    .tl_ltssm                                (tl_ltssm                             ),
    .pl_ltssm                                (pl_ltssm                             ),
    .pl_link_up                              (pl_link_up                           ),
    .pl_ltssm_enable                         (tl_ltssm_enable                      ),

    .pl_clkreq_in                            (1'b0                                 ),
    .tl_pm_l1ss_entack                       (4'd0                                 ),
    .tl_pm_refclk_rem                        (1'b0                                 ),
    .pl_clkreq_oen                           (                                     ),
    .tl_pm_l1ss_entreq                       (                                     ),
    .tl_pm_l1ss_status                       (                                     ),

    .pl_wake_in                              (1'b0                                 ),
    .tl_pm_auxpwr                            (1'b0                                 ),
    .tl_pm_data                              (20'd0                                ),
    .tl_pm_event                             (2'd0                                 ),
    .tl_pm_lx_control                        (3'd0                                 ),
    .pl_wake_oen                             (                                     ),
    .tl_pm_lx_status                         (                                     ),

    .tl_pm_bwchange_linkwidth_change_req     (1'b0                                 ),
    .tl_pm_bwchange_allowed_linkwidth        (4'b0                                 ),
    .tl_pm_bwchange_linkspeed_change_req     (1'b0                                 ),
    .tl_pm_bwchange_max_linkspeed            (3'b0                                 ),

    .tl_report_error_10_1_bits               (10'd0                                ),
    .tl_report_error_22_12_bits              (11'd0                                ),
    .tl_report_error_63_40_bits              (24'd0                                ),
    .tl_report_header                        (256'd0                               ),
    .tl_report_hotplug                       (10'd0                                ),
    .tl_report_latency                       (33'd0                                ),
    .tl_report_state_pf0_misc_control        (12'd0                                ),
    .tl_report_state_pf1_misc_control        (12'd0                                ),
    .tl_report_event                         (                                     ),
    .tl_report_vfstate_override_sel          (2'd0                                 ),
    .tl_report_vfstate_override_bit          (4'd0                                 ),
    
    .tl_rx_wait                              (tl_rx_wait                           ),
    .tl_rx_masknp                            (tl_rx_masknp                         ),
    .tl_rx_bardec                            (tl_rx_bardec                         ),
    .tl_rx_data                              (tl_rx_data                           ),
    .tl_rx_eop                               (tl_rx_eop                            ),
    .tl_rx_err                               (tl_rx_err                            ),
    .tl_rx_mchit                             (tl_rx_mchit                          ),
    .tl_rx_sop                               (tl_rx_sop                            ),
    .tl_rx_valid                             (tl_rx_valid                          ),

    .tl_tx_data                              (tl_tx_data                           ),
    .tl_tx_eop                               (tl_tx_eop                            ),
    .tl_tx_err                               (tl_tx_err                            ),
    .tl_tx_sop                               (tl_tx_sop                            ),
    .tl_tx_stream                            (tl_tx_stream                         ),
    .tl_tx_valid                             (tl_tx_valid                          ),
    .tl_tx_wait                              (tl_tx_wait                           ),
    .tl_tx_credits                           (tl_tx_credits                        ),

    .tl_cfg_xrdata                           (32'd0                                ),
    .tl_cfg_xready                           (1'b1                                 ),
    .tl_cfg_xaddr                            (                                     ),
    .tl_cfg_xenable                          (                                     ),
    .tl_cfg_xfid                             (                                     ),
    .tl_cfg_xstrb                            (                                     ),
    .tl_cfg_xwdata                           (                                     ),
    .tl_cfg_xwrite                           (                                     ),

    .tl_vpd_rddata                           (64'd0                                ),
    .tl_vpd_ready                            (2'd0                                 ),
    .tl_vpd_addr                             (tl_vpd_addr                          ),
    .tl_vpd_enable                           (tl_vpd_enable                        ),
    .tl_vpd_status                           (tl_vpd_status                        ),
    .tl_vpd_wrdata                           (tl_vpd_wrdata                        ),
    .tl_vpd_write                            (tl_vpd_write                         ),

    .tl_pm_obffcontrol                       (4'd0                                 ),
    .tl_pm_obffstatus                        (                                     ),

    .tl_ptm_in                               (68'd0                                ),
    .tl_ptm_out                              (                                     ),

    .tl_doe_rddata                           (64'd0                                ),
    .tl_doe_pf0_status                       (13'd0                                ),
    .tl_doe_pf1_status                       (13'd0                                ),
    .tl_doe_control                          (tl_doe_control                       ),
    .tl_doe_wrdata                           (tl_doe_wrdata                        ),

    .pinshare_grp0_out_sel                   (3'd0                                 ),
    .pinshare_grp1_out_sel                   (2'd0                                 ),

    .test_in_errinj_8_0_bits                 (9'd0                                 ),
    .test_in_errinj_20_16_bits               (5'd0                                 ),

    .test_out_rxval                          (test_out_rxval                       ),
    .test_out_txdatak                        (test_out_txdatak                     ),
    .test_out_txval                          (test_out_txval                       ),
    .scan_clk                                (scan_clk                             ),
    .scan_in                                 (scan_in                              ),
    .scan_out                                (scan_out                             ),
    .scan_mode_n                             (scan_mode_n                          ),
    .scan_rst_n                              (scan_rst_n                           ),
    .scan_enable_n                           (scan_enable_n                        ),
    .scancompress_mode_n                     (scancompress_mode_n                  ),
    .mbist_mode_n                            (mbist_mode_n                         ),
    .dft_jtag_tck                            (dft_jtag_tck                         ),
    .dft_jtag_trst_n                         (dft_jtag_trst_n                      ),
    .dft_jtag_tms                            (dft_jtag_tms                         ),
    .dft_jtag_tdi                            (dft_jtag_tdi                         ),
    .dft_jtag_tdo                            (dft_jtag_tdo                         ),
    .pl_sideband                             (pl_sideband                          ),
    .cfg_power_on_rst_n                      (cfg_power_on_rst_n                   ),
    .cfg_pipe_lane_flip                      (cfg_pipe_lane_flip                   ),
    .cfg_pcs_pipe_rst_n                      (cfg_pcs_pipe_rst_n                   ),
    .cfg_pcs_apb_rst_n                       (cfg_pcs_apb_rst_n                    ),
    .cfg_pclk_source_sel                     (cfg_pclk_source_sel                  ),
    .cfg_pcie_lane_enable                    (cfg_pcie_lane_enable                 ),
    .cfg_core_sram_init_done                 (cfg_core_sram_init_done              ),
    .cfg_core_bypass                         (cfg_core_bypass                      ),
    .serdes_osc_clk                          (serdes_osc_clk                       ),
    .pl_pclk                                 (pl_pclk                              ),
    .pl_sideband_in                          (pl_sideband_in                       ),
    .pl_sideband_out                         (pl_sideband_out                      ),
    .pl_pclk_rate                            (pl_pclk_rate                         ),
    .pl_phystatus                            (pl_phystatus                         ),
    .pl_powerdown                            (pl_powerdown                         ),
    .pl_rate                                 (pl_rate                              ),
    .pl_rxdata                               (pl_rxdata                            ),
    .pl_rxdatak                              (pl_rxdatak                           ),
    .pl_rxdatavalid                          (pl_rxdatavalid                       ),
    .pl_rxelecidle                           (pl_rxelecidle                        ),
    .pl_rxstandby                            (pl_rxstandby                         ),
    .pl_rxstartblock                         (pl_rxstartblock                      ),
    .pl_rxstatus                             (pl_rxstatus                          ),
    .pl_rxsyncheader                         (pl_rxsyncheader                      ),
    .pl_rxvalid                              (pl_rxvalid                           ),
    .pl_txcompliance                         (pl_txcompliance                      ),
    .pl_txdata                               (pl_txdata                            ),
    .pl_txdatak                              (pl_txdatak                           ),
    .pl_txdatavalid                          (pl_txdatavalid                       ),
    .pl_txdetectrx                           (pl_txdetectrx                        ),
    .pl_txelecidle                           (pl_txelecidle                        ),
    .pl_txstartblock                         (pl_txstartblock                      ),
    .pl_txsyncheader                         (pl_txsyncheader                      ),
    .pl_width                                (pl_width                             ) 

);

// ====================================================================
// Serdes Phy0 Inst 
// ====================================================================

         localparam          CMN_REFCLK_SEL      = 1'b0;
         localparam          CMN_PLL_REFCLK_SEL  = 4'b0000;
         localparam          TX_REFCLK_SEL       = 1'h0;
     
PH1P_PHY_HXT_V1 #(
    .TX_LANE_ENABLE                          (4'hf                                                    ),
    .RX_LANE_ENABLE                          (4'hf                                                    ),
    .TOP00_VLD                               ({CMN_REFCLK_SEL,27'h000020,PH1P_HXT_FAST_SIM,1'b0,1'h0,1'h1}),
    .TOP01_VLD                               (32'h0202                                                ),
    .TOP02_VLD                               (32'h84                                                  ),
    .ZCAL00_VLD                              (32'h04                                                  ),
    .ZCAL01_VLD                              ({16'h0,PH1P_HXT_FAST_SIM,12'h010,1'h0,PH1P_HXT_FAST_SIM,2'h3}),
    .ZCAL02_VLD                              (32'h1f25                                                ),
    .ZCAL03_VLD                              (32'h1f25                                                ),
    .ZCAL04_VLD                              (32'h1f25                                                ),
    .ZCAL05_VLD                              (32'h1f25                                                ),
    .ZCAL06_VLD                              (32'h342                                                 ),
    .CDRDRV_VLD                              (32'h0                                                   ),
    .REFCLK_CTL_VLD                          (32'h3f                                                  ),
    .JM_CTL_VLD                              (32'h0                                                   ),
    .CMN_PLL_CLOCK_VLD                       ({8'h5a,8'd76,8'h7,2'b00,2'b00,CMN_PLL_REFCLK_SEL}       ),
    .CMN_PLL_FRAC_N00_VLD                    (32'h0                                                   ),
    .CMN_PLL_FRAC_N01_VLD                    (32'h0                                                   ),
    .CMN_PLL_CAL00_VLD                       (32'h5300486                                             ),
    .CMN_PLL_TDC_CTL00_VLD                   (32'h0                                                   ),
    .CMN_PLL_TEST00_VLD                      (32'h260                                                 ),
    .ADC_BG_OSC00_VLD                        (32'h210c00                                              ),
    .PMA_QUAD_RSV_VLD                        (32'h0                                                   ),
    .CMN_DEBUG_0_VLD                         (32'h0                                                   ),
    .CMN_ILM_CTL_ADDR_VLD                    (32'h0                                                   ),
    .CMN_ILM_WR_PORT_VLD                     (32'h0                                                   ),
    .CMN_ILM_RD_TRIG_VLD                     (32'h0                                                   ),
    .LANE0_TX_DATA_FFE00_VLD                 (32'h7f01                                                ),
    .LANE0_TX_DATA_FFE01_VLD                 (32'h0                                                   ),
    .LANE0_TX_DATA_FFE02_VLD                 (32'h0                                                   ),
    .LANE0_TX_DATA_FFE03_VLD                 (32'h0                                                   ),
    .LANE0_TX_DATA_FFE04_VLD                 (32'h0                                                   ),
    .LANE0_TX_CLK_PATH00_VLD                 (32'h10145                                               ),
    .LANE0_TX_DCC_CTRL_VLD                   ({PH1P_HXT_FAST_SIM,31'h3425}                            ),
    .LANE0_TX_DRV_CTRL_VLD                   (32'h0                                                   ),
    .LANE0_TX_RCV_DET_CTL_VLD                (32'h1                                                   ),
    .LANE0_TX_PLL_MAIN_CTL_VLD               ({PH1P_HXT_FAST_SIM,31'h00040105}                        ),
    .LANE0_TX_PLL_LOOP_CTL_VLD               (32'h7036a7b                                             ),
    .LANE0_TX_FBDIV_CTL00_VLD                (32'h6000050                                             ),
    .LANE0_TX_FBDIV_CTL01_VLD                ({1'b0,PH1P_HXT_FAST_SIM,30'h05080000}                   ),
    .LANE0_TX_PLL_FRACN_CTL_VLD              (32'h0                                                   ),
    .LANE0_TX_PLL_SSC_FREQ_DIV_VLD           (32'h0                                                   ),
    .LANE0_TX_PLL_SSC_RNGE_VLD               (32'h0                                                   ),
    .LANE0_TX_PLL_TEST_CTL_VLD               (32'h40                                                  ),
    .LANE0_TX_GLBL_MISC00_VLD                (32'h123                                                 ),
    .LANE0_TX_GLBL_MISC01_VLD                (32'h0                                                   ),
    .LANE0_TX_RESERVE00_VLD                  (32'h0                                                   ),
    .LANE0_RX_GLOBAL_MISC_RESERVED00_VLD     (32'h10102                                               ),
    .LANE0_RX_LOS_ACJTAG00_VLD               (32'h3                                                   ),
    .LANE0_RX_AFE_TERM_ATT00_VLD             (32'h8f70010                                             ),
    .LANE0_RX_ATT_CTLE00_VLD                 (32'h701                                                 ),
    .LANE0_RX_ATT_CTLE01_VLD                 (32'h50                                                  ),
    .LANE0_RX_ATT_CTLE02_VLD                 (32'h5503452                                             ),
    .LANE0_RX_DFE_SUMMER_VDAC_IDAC00_VLD     (32'h11                                                  ),
    .LANE0_RX_DFE_SUMMER_VDAC_IDAC01_VLD     (32'h20202020                                            ),
    .LANE0_RX_DFE_SUMMER_VDAC_IDAC02_VLD     (32'h20202020                                            ),
    .LANE0_RX_DFE_SUMMER_VDAC_IDAC03_VLD     (32'h20202020                                            ),
    .LANE0_RX_DFE_SUMMER_VDAC_IDAC04_VLD     (32'h0                                                   ),
    .LANE0_RX_DFE_SUMMER_VDAC_IDAC05_VLD     (32'h0                                                   ),
    .LANE0_RX_DFE_SUMMER_VDAC_IDAC06_VLD     (32'h0                                                   ),
    .LANE0_RX_DFE_SUMMER_VDAC_IDAC07_VLD     (32'h0                                                   ),
    .LANE0_RX_CLK_PATH_WITH_PLL00_VLD        (32'h36261e0d                                            ),
    .LANE0_RX_CLK_PATH_WITH_PLL01_VLD        (32'h34030332                                            ),
    .LANE0_RX_CLK_PATH_WITH_PLL02_VLD        (32'h50c                                                 ),
    .LANE0_RX_CLK_PATH_WITH_PLL03_VLD        ({3'h0,PH1P_HXT_FAST_SIM,28'h600}                        ),
    .LANE0_RX_CLK_PATH_WITH_PLL04_VLD        ({1'b0,PH1P_HXT_FAST_SIM,30'h05080000}                   ),
    .LANE0_RX_PLL_FRACN_CTL_VLD              (32'h0                                                   ),
    .LANE0_RX_PLL_SSC_FREQ_DIV_VLD           (32'h0                                                   ),
    .LANE0_RX_PLL_SSC_RNGE_VLD               (32'h0                                                   ),
    .LANE0_RX_DESER_CDR00_VLD                (32'h3612203                                             ),
    .LANE0_RX_DESER_CDR02_VLD                (32'h1                                                   ),
    .LANE0_RX_DESER_CDR03_VLD                (32'h0                                                   ),
    .LANE0_RX_DESER_CDR04_VLD                (32'h0                                                   ),
    .LANE0_RX_DIG_CALI_1_VLD                 (32'h0                                                   ),
    .LANE0_RX_DIG_CALI_2_VLD                 (32'h0                                                   ),
    .LANE0_RX_DIG_CALI_3_VLD                 (32'h0                                                   ),
    .LANE0_RX_DIG_CALI_4_VLD                 (32'h0                                                   ),
    .LANE0_RX_DIG_CALI_5_VLD                 (32'h18000000                                            ),
    .LANE0_RX_DIG_CALI_6_VLD                 (32'h40001007                                            ),
    .LANE0_RX_DIG_CALI_7_VLD                 (32'h0                                                   ),
    .LANE0_RX_DIG_CALI_8_VLD                 (32'h0                                                   ),
    .LANE0_RX_DIG_CALI_9_VLD                 (32'h0                                                   ),
    .LANE0_RX_DIG_CALI_10_VLD                (32'h0                                                   ),
    .LANE0_RX_DIG_CALI_11_VLD                (32'h0                                                   ),
    .LANE0_RX_DIG_CALI_12_VLD                (32'h0                                                   ),
    .LANE0_RX_DIG_CALI_13_VLD                (32'h0                                                   ),
    .LANE0_RX_DIG_CALI_14_VLD                (32'h0                                                   ),
    .LANE0_TX_CLK_CTRL_0_VLD                 ({22'h80140,TX_REFCLK_SEL,9'h41}                         ),
    .LANE0_TX_RST_CTRL_0_VLD                 (32'hf                                                   ),
    .LANE0_LANE_PROTOCOL_VLD                 (32'h80                                                  ),
    .LANE0_TX_DATA_WIDTH_VLD                 (32'h128                                                 ),
    .LANE0_TX_ENC_EN_VLD                     (32'h40                                                  ),
    .LANE0_TX_DATA_CTRL_0_VLD                (32'h102                                                 ),
    .LANE0_TX_LBERT_CTRL_VLD                 (32'h205                                                 ),
    .LANE0_TX_LBERT_ERR_TRIG_VLD             (32'h0                                                   ),
    .LANE0_TX_LBERT_PATTERN_0_VLD            (32'h11111                                               ),
    .LANE0_TX_LBERT_PATTERN_1_VLD            (32'h0                                                   ),
    .LANE0_TX_LBERT_PATTERN_2_VLD            (32'h0                                                   ),
    .LANE0_TX_C16_PISO_CTRL_VLD              (32'h0                                                   ),
    .LANE0_TX_C16_DATA_CTRL_0_VLD            (32'h14000130                                            ),
    .LANE0_TX_C16_LBERT_CTRL_VLD             (32'h1                                                   ),
    .LANE0_TX_C16_LBERT_PATTERN_VLD          (32'h0                                                   ),
    .LANE0_TX_GEARBOX_CTL_VLD                (32'h38                                                  ),
    .LANE0_TX_PI_CTL_VLD                     (32'h3001                                                ),
    .LANE0_TX_DPLL_CTL_VLD                   (32'h14000                                               ),
    .LANE0_TX_PCSFIFO_STS_VLD                (32'h0                                                   ),
    .LANE0_TX_PWR_CTL_VLD                    ({28'h1028080,2'b0,PH1P_HXT_FAST_SIM,1'b0}               ),
    .LANE0_TX_PCIE_EQ_G1_VLD                 (32'h3f00                                                ),
    .LANE0_TX_PCIE_EQ_G2_VLD                 (32'h0                                                   ),
    .LANE0_TX_PCIE_EQ_G3_VLD                 (32'h0                                                   ),
    .LANE0_RX_CLK_CTRL_0_VLD                 (32'h80880029                                            ),
    .LANE0_RX_RST_CTRL_0_VLD                 (32'h3f                                                  ),
    .LANE0_RX_DATA_WIDTH_VLD                 (32'h128                                                 ),
    .LANE0_RX_ENC_EN_VLD                     (32'h800fe00                                             ),
    .LANE0_RX_DATA_CTRL_0_VLD                (32'h380                                                 ),
    .LANE0_RX_DATA_CTRL_1_VLD                (32'h1                                                   ),
    .LANE0_RX_GEARBOX_CTL_VLD                (32'h308                                                 ),
    .LANE0_RX_ALIGN_EN_CTRL_VLD              (32'h1007                                                ),
    .LANE0_RX_ALIGN_COMMA_MASK_VLD           (32'h1003ff                                              ),
    .LANE0_RX_ALIGN_COMMA_VLD                (32'hfa0305                                              ),
    .LANE0_RX_SKIP_CTRL_VLD                  (32'h2000                                                ),
    .LANE0_RX_SKIP1_PATTERN1_VLD             (32'h0                                                   ),
    .LANE0_RX_SKIP1_PATTERN2_VLD             (32'h0                                                   ),
    .LANE0_RX_SKIP2_PATTERN1_VLD             (32'h0                                                   ),
    .LANE0_RX_SKIP2_PATTERN2_VLD             (32'h0                                                   ),
    .LANE0_RX_SKIP_MARK_VLD                  (32'h0                                                   ),
    .LANE0_RX_SIPO_ALIGN_VLD                 (32'h74c                                                 ),
    .LANE0_RX_SIPO_STS_VLD                   (32'h0                                                   ),
    .LANE0_RX_LBERT_CTRL_VLD                 (32'h3205                                                ),
    .LANE0_RX_LBERT_ERRCNT_LATCH_VLD         (32'h0                                                   ),
    .LANE0_RX_C16_LBERT_CTRL_0_VLD           (32'h1                                                   ),
    .LANE0_RX_C16_LBERT_ERRCNT_LATCH_VLD     (32'h0                                                   ),
    .LANE0_RX_PWR_CTL_VLD                    ({28'h0028008,2'h0,PH1P_HXT_FAST_SIM,1'b0}               ),
    .LANE0_RX_EQ_CTL_VLD                     (32'h8                                                   ),
    .LANE0_MISC_CTL_0_VLD                    (32'h0                                                   ),
    .LANE0_MISC_CTL_1_VLD                    (32'h1c6c                                                ),
    .LANE0_PCS_TX_CTL_INT_VLD                (32'h0                                                   ),
    .LANE0_PCS_TX_STS_INT_VLD                (32'h0                                                   ),
    .LANE0_PCS_RX_CTL_INT_VLD                (32'h0                                                   ),
    .LANE0_PCS_RX_STS_INT_VLD                (32'h0                                                   ),
    .LANE0_DEBUG_IO_CTRL_VLD                 (32'h0                                                   ),
    .LANE0_DEBUG_CLK_CTRL_VLD                (32'h0                                                   ),
    .LANE1_TX_DATA_FFE00_VLD                 (32'h7f01                                                ),
    .LANE1_TX_DATA_FFE01_VLD                 (32'h0                                                   ),
    .LANE1_TX_DATA_FFE02_VLD                 (32'h0                                                   ),
    .LANE1_TX_DATA_FFE03_VLD                 (32'h0                                                   ),
    .LANE1_TX_DATA_FFE04_VLD                 (32'h0                                                   ),
    .LANE1_TX_CLK_PATH00_VLD                 (32'h10145                                               ),
    .LANE1_TX_DCC_CTRL_VLD                   ({PH1P_HXT_FAST_SIM,31'h3425}                            ),
    .LANE1_TX_DRV_CTRL_VLD                   (32'h0                                                   ),
    .LANE1_TX_RCV_DET_CTL_VLD                (32'h1                                                   ),
    .LANE1_TX_PLL_MAIN_CTL_VLD               ({PH1P_HXT_FAST_SIM,31'h00040105}                        ),
    .LANE1_TX_PLL_LOOP_CTL_VLD               (32'h7036a7b                                             ),
    .LANE1_TX_FBDIV_CTL00_VLD                (32'h6000050                                             ),
    .LANE1_TX_FBDIV_CTL01_VLD                ({1'b0,PH1P_HXT_FAST_SIM,30'h05080000}                   ),
    .LANE1_TX_PLL_FRACN_CTL_VLD              (32'h0                                                   ),
    .LANE1_TX_PLL_SSC_FREQ_DIV_VLD           (32'h0                                                   ),
    .LANE1_TX_PLL_SSC_RNGE_VLD               (32'h0                                                   ),
    .LANE1_TX_PLL_TEST_CTL_VLD               (32'h40                                                  ),
    .LANE1_TX_GLBL_MISC00_VLD                (32'h123                                                 ),
    .LANE1_TX_GLBL_MISC01_VLD                (32'h0                                                   ),
    .LANE1_TX_RESERVE00_VLD                  (32'h0                                                   ),
    .LANE1_RX_GLOBAL_MISC_RESERVED00_VLD     (32'h10102                                               ),
    .LANE1_RX_LOS_ACJTAG00_VLD               (32'h3                                                   ),
    .LANE1_RX_AFE_TERM_ATT00_VLD             (32'h8f70010                                             ),
    .LANE1_RX_ATT_CTLE00_VLD                 (32'h701                                                 ),
    .LANE1_RX_ATT_CTLE01_VLD                 (32'h50                                                  ),
    .LANE1_RX_ATT_CTLE02_VLD                 (32'h5503452                                             ),
    .LANE1_RX_DFE_SUMMER_VDAC_IDAC00_VLD     (32'h11                                                  ),
    .LANE1_RX_DFE_SUMMER_VDAC_IDAC01_VLD     (32'h20202020                                            ),
    .LANE1_RX_DFE_SUMMER_VDAC_IDAC02_VLD     (32'h20202020                                            ),
    .LANE1_RX_DFE_SUMMER_VDAC_IDAC03_VLD     (32'h20202020                                            ),
    .LANE1_RX_DFE_SUMMER_VDAC_IDAC04_VLD     (32'h0                                                   ),
    .LANE1_RX_DFE_SUMMER_VDAC_IDAC05_VLD     (32'h0                                                   ),
    .LANE1_RX_DFE_SUMMER_VDAC_IDAC06_VLD     (32'h0                                                   ),
    .LANE1_RX_DFE_SUMMER_VDAC_IDAC07_VLD     (32'h0                                                   ),
    .LANE1_RX_CLK_PATH_WITH_PLL00_VLD        (32'h36261e0d                                            ),
    .LANE1_RX_CLK_PATH_WITH_PLL01_VLD        (32'h34030332                                            ),
    .LANE1_RX_CLK_PATH_WITH_PLL02_VLD        (32'h50c                                                 ),
    .LANE1_RX_CLK_PATH_WITH_PLL03_VLD        ({3'h0,PH1P_HXT_FAST_SIM,28'h600}                        ),
    .LANE1_RX_CLK_PATH_WITH_PLL04_VLD        ({1'b0,PH1P_HXT_FAST_SIM,30'h05080000}                   ),
    .LANE1_RX_PLL_FRACN_CTL_VLD              (32'h0                                                   ),
    .LANE1_RX_PLL_SSC_FREQ_DIV_VLD           (32'h0                                                   ),
    .LANE1_RX_PLL_SSC_RNGE_VLD               (32'h0                                                   ),
    .LANE1_RX_DESER_CDR00_VLD                (32'h3612203                                             ),
    .LANE1_RX_DESER_CDR02_VLD                (32'h1                                                   ),
    .LANE1_RX_DESER_CDR03_VLD                (32'h0                                                   ),
    .LANE1_RX_DESER_CDR04_VLD                (32'h0                                                   ),
    .LANE1_RX_DIG_CALI_1_VLD                 (32'h0                                                   ),
    .LANE1_RX_DIG_CALI_2_VLD                 (32'h0                                                   ),
    .LANE1_RX_DIG_CALI_3_VLD                 (32'h0                                                   ),
    .LANE1_RX_DIG_CALI_4_VLD                 (32'h0                                                   ),
    .LANE1_RX_DIG_CALI_5_VLD                 (32'h18000000                                            ),
    .LANE1_RX_DIG_CALI_6_VLD                 (32'h40001007                                            ),
    .LANE1_RX_DIG_CALI_7_VLD                 (32'h0                                                   ),
    .LANE1_RX_DIG_CALI_8_VLD                 (32'h0                                                   ),
    .LANE1_RX_DIG_CALI_9_VLD                 (32'h0                                                   ),
    .LANE1_RX_DIG_CALI_10_VLD                (32'h0                                                   ),
    .LANE1_RX_DIG_CALI_11_VLD                (32'h0                                                   ),
    .LANE1_RX_DIG_CALI_12_VLD                (32'h0                                                   ),
    .LANE1_RX_DIG_CALI_13_VLD                (32'h0                                                   ),
    .LANE1_RX_DIG_CALI_14_VLD                (32'h0                                                   ),
    .LANE1_TX_CLK_CTRL_0_VLD                 ({22'h80140,TX_REFCLK_SEL,9'h41}                         ),
    .LANE1_TX_RST_CTRL_0_VLD                 (32'hf                                                   ),
    .LANE1_LANE_PROTOCOL_VLD                 (32'h80                                                  ),
    .LANE1_TX_DATA_WIDTH_VLD                 (32'h128                                                 ),
    .LANE1_TX_ENC_EN_VLD                     (32'h40                                                  ),
    .LANE1_TX_DATA_CTRL_0_VLD                (32'h102                                                 ),
    .LANE1_TX_LBERT_CTRL_VLD                 (32'h205                                                 ),
    .LANE1_TX_LBERT_ERR_TRIG_VLD             (32'h0                                                   ),
    .LANE1_TX_LBERT_PATTERN_0_VLD            (32'h11111                                               ),
    .LANE1_TX_LBERT_PATTERN_1_VLD            (32'h0                                                   ),
    .LANE1_TX_LBERT_PATTERN_2_VLD            (32'h0                                                   ),
    .LANE1_TX_C16_PISO_CTRL_VLD              (32'h0                                                   ),
    .LANE1_TX_C16_DATA_CTRL_0_VLD            (32'h14000130                                            ),
    .LANE1_TX_C16_LBERT_CTRL_VLD             (32'h1                                                   ),
    .LANE1_TX_C16_LBERT_PATTERN_VLD          (32'h0                                                   ),
    .LANE1_TX_GEARBOX_CTL_VLD                (32'h38                                                  ),
    .LANE1_TX_PI_CTL_VLD                     (32'h3001                                                ),
    .LANE1_TX_DPLL_CTL_VLD                   (32'h14000                                               ),
    .LANE1_TX_PCSFIFO_STS_VLD                (32'h0                                                   ),
    .LANE1_TX_PWR_CTL_VLD                    ({28'h1028080,2'b0,PH1P_HXT_FAST_SIM,1'b0}               ),
    .LANE1_TX_PCIE_EQ_G1_VLD                 (32'h3f00                                                ),
    .LANE1_TX_PCIE_EQ_G2_VLD                 (32'h0                                                   ),
    .LANE1_TX_PCIE_EQ_G3_VLD                 (32'h0                                                   ),
    .LANE1_RX_CLK_CTRL_0_VLD                 (32'h80880029                                            ),
    .LANE1_RX_RST_CTRL_0_VLD                 (32'h3f                                                  ),
    .LANE1_RX_DATA_WIDTH_VLD                 (32'h128                                                 ),
    .LANE1_RX_ENC_EN_VLD                     (32'h800fe00                                             ),
    .LANE1_RX_DATA_CTRL_0_VLD                (32'h380                                                 ),
    .LANE1_RX_DATA_CTRL_1_VLD                (32'h1                                                   ),
    .LANE1_RX_GEARBOX_CTL_VLD                (32'h308                                                 ),
    .LANE1_RX_ALIGN_EN_CTRL_VLD              (32'h1007                                                ),
    .LANE1_RX_ALIGN_COMMA_MASK_VLD           (32'h1003ff                                              ),
    .LANE1_RX_ALIGN_COMMA_VLD                (32'hfa0305                                              ),
    .LANE1_RX_SKIP_CTRL_VLD                  (32'h2000                                                ),
    .LANE1_RX_SKIP1_PATTERN1_VLD             (32'h0                                                   ),
    .LANE1_RX_SKIP1_PATTERN2_VLD             (32'h0                                                   ),
    .LANE1_RX_SKIP2_PATTERN1_VLD             (32'h0                                                   ),
    .LANE1_RX_SKIP2_PATTERN2_VLD             (32'h0                                                   ),
    .LANE1_RX_SKIP_MARK_VLD                  (32'h0                                                   ),
    .LANE1_RX_SIPO_ALIGN_VLD                 (32'h74c                                                 ),
    .LANE1_RX_SIPO_STS_VLD                   (32'h0                                                   ),
    .LANE1_RX_LBERT_CTRL_VLD                 (32'h3205                                                ),
    .LANE1_RX_LBERT_ERRCNT_LATCH_VLD         (32'h0                                                   ),
    .LANE1_RX_C16_LBERT_CTRL_0_VLD           (32'h1                                                   ),
    .LANE1_RX_C16_LBERT_ERRCNT_LATCH_VLD     (32'h0                                                   ),
    .LANE1_RX_PWR_CTL_VLD                    ({28'h0028008,2'h0,PH1P_HXT_FAST_SIM,1'b0}               ),
    .LANE1_RX_EQ_CTL_VLD                     (32'h8                                                   ),
    .LANE1_MISC_CTL_0_VLD                    (32'h0                                                   ),
    .LANE1_MISC_CTL_1_VLD                    (32'h1c6c                                                ),
    .LANE1_PCS_TX_CTL_INT_VLD                (32'h0                                                   ),
    .LANE1_PCS_TX_STS_INT_VLD                (32'h0                                                   ),
    .LANE1_PCS_RX_CTL_INT_VLD                (32'h0                                                   ),
    .LANE1_PCS_RX_STS_INT_VLD                (32'h0                                                   ),
    .LANE1_DEBUG_IO_CTRL_VLD                 (32'h0                                                   ),
    .LANE1_DEBUG_CLK_CTRL_VLD                (32'h0                                                   ),
    .LANE2_TX_DATA_FFE00_VLD                 (32'h7f01                                                ),
    .LANE2_TX_DATA_FFE01_VLD                 (32'h0                                                   ),
    .LANE2_TX_DATA_FFE02_VLD                 (32'h0                                                   ),
    .LANE2_TX_DATA_FFE03_VLD                 (32'h0                                                   ),
    .LANE2_TX_DATA_FFE04_VLD                 (32'h0                                                   ),
    .LANE2_TX_CLK_PATH00_VLD                 (32'h10145                                               ),
    .LANE2_TX_DCC_CTRL_VLD                   ({PH1P_HXT_FAST_SIM,31'h3425}                            ),
    .LANE2_TX_DRV_CTRL_VLD                   (32'h0                                                   ),
    .LANE2_TX_RCV_DET_CTL_VLD                (32'h1                                                   ),
    .LANE2_TX_PLL_MAIN_CTL_VLD               ({PH1P_HXT_FAST_SIM,31'h00040105}                        ),
    .LANE2_TX_PLL_LOOP_CTL_VLD               (32'h7036a7b                                             ),
    .LANE2_TX_FBDIV_CTL00_VLD                (32'h6000050                                             ),
    .LANE2_TX_FBDIV_CTL01_VLD                ({1'b0,PH1P_HXT_FAST_SIM,30'h05080000}                   ),
    .LANE2_TX_PLL_FRACN_CTL_VLD              (32'h0                                                   ),
    .LANE2_TX_PLL_SSC_FREQ_DIV_VLD           (32'h0                                                   ),
    .LANE2_TX_PLL_SSC_RNGE_VLD               (32'h0                                                   ),
    .LANE2_TX_PLL_TEST_CTL_VLD               (32'h40                                                  ),
    .LANE2_TX_GLBL_MISC00_VLD                (32'h123                                                 ),
    .LANE2_TX_GLBL_MISC01_VLD                (32'h0                                                   ),
    .LANE2_TX_RESERVE00_VLD                  (32'h0                                                   ),
    .LANE2_RX_GLOBAL_MISC_RESERVED00_VLD     (32'h10102                                               ),
    .LANE2_RX_LOS_ACJTAG00_VLD               (32'h3                                                   ),
    .LANE2_RX_AFE_TERM_ATT00_VLD             (32'h8f70010                                             ),
    .LANE2_RX_ATT_CTLE00_VLD                 (32'h701                                                 ),
    .LANE2_RX_ATT_CTLE01_VLD                 (32'h50                                                  ),
    .LANE2_RX_ATT_CTLE02_VLD                 (32'h5503452                                             ),
    .LANE2_RX_DFE_SUMMER_VDAC_IDAC00_VLD     (32'h11                                                  ),
    .LANE2_RX_DFE_SUMMER_VDAC_IDAC01_VLD     (32'h20202020                                            ),
    .LANE2_RX_DFE_SUMMER_VDAC_IDAC02_VLD     (32'h20202020                                            ),
    .LANE2_RX_DFE_SUMMER_VDAC_IDAC03_VLD     (32'h20202020                                            ),
    .LANE2_RX_DFE_SUMMER_VDAC_IDAC04_VLD     (32'h0                                                   ),
    .LANE2_RX_DFE_SUMMER_VDAC_IDAC05_VLD     (32'h0                                                   ),
    .LANE2_RX_DFE_SUMMER_VDAC_IDAC06_VLD     (32'h0                                                   ),
    .LANE2_RX_DFE_SUMMER_VDAC_IDAC07_VLD     (32'h0                                                   ),
    .LANE2_RX_CLK_PATH_WITH_PLL00_VLD        (32'h36261e0d                                            ),
    .LANE2_RX_CLK_PATH_WITH_PLL01_VLD        (32'h34030332                                            ),
    .LANE2_RX_CLK_PATH_WITH_PLL02_VLD        (32'h50c                                                 ),
    .LANE2_RX_CLK_PATH_WITH_PLL03_VLD        ({3'h0,PH1P_HXT_FAST_SIM,28'h600}                        ),
    .LANE2_RX_CLK_PATH_WITH_PLL04_VLD        ({1'b0,PH1P_HXT_FAST_SIM,30'h05080000}                   ),
    .LANE2_RX_PLL_FRACN_CTL_VLD              (32'h0                                                   ),
    .LANE2_RX_PLL_SSC_FREQ_DIV_VLD           (32'h0                                                   ),
    .LANE2_RX_PLL_SSC_RNGE_VLD               (32'h0                                                   ),
    .LANE2_RX_DESER_CDR00_VLD                (32'h3612203                                             ),
    .LANE2_RX_DESER_CDR02_VLD                (32'h1                                                   ),
    .LANE2_RX_DESER_CDR03_VLD                (32'h0                                                   ),
    .LANE2_RX_DESER_CDR04_VLD                (32'h0                                                   ),
    .LANE2_RX_DIG_CALI_1_VLD                 (32'h0                                                   ),
    .LANE2_RX_DIG_CALI_2_VLD                 (32'h0                                                   ),
    .LANE2_RX_DIG_CALI_3_VLD                 (32'h0                                                   ),
    .LANE2_RX_DIG_CALI_4_VLD                 (32'h0                                                   ),
    .LANE2_RX_DIG_CALI_5_VLD                 (32'h18000000                                            ),
    .LANE2_RX_DIG_CALI_6_VLD                 (32'h40001007                                            ),
    .LANE2_RX_DIG_CALI_7_VLD                 (32'h0                                                   ),
    .LANE2_RX_DIG_CALI_8_VLD                 (32'h0                                                   ),
    .LANE2_RX_DIG_CALI_9_VLD                 (32'h0                                                   ),
    .LANE2_RX_DIG_CALI_10_VLD                (32'h0                                                   ),
    .LANE2_RX_DIG_CALI_11_VLD                (32'h0                                                   ),
    .LANE2_RX_DIG_CALI_12_VLD                (32'h0                                                   ),
    .LANE2_RX_DIG_CALI_13_VLD                (32'h0                                                   ),
    .LANE2_RX_DIG_CALI_14_VLD                (32'h0                                                   ),
    .LANE2_TX_CLK_CTRL_0_VLD                 ({22'h80140,TX_REFCLK_SEL,9'h41}                         ),
    .LANE2_TX_RST_CTRL_0_VLD                 (32'hf                                                   ),
    .LANE2_LANE_PROTOCOL_VLD                 (32'h80                                                  ),
    .LANE2_TX_DATA_WIDTH_VLD                 (32'h128                                                 ),
    .LANE2_TX_ENC_EN_VLD                     (32'h40                                                  ),
    .LANE2_TX_DATA_CTRL_0_VLD                (32'h102                                                 ),
    .LANE2_TX_LBERT_CTRL_VLD                 (32'h205                                                 ),
    .LANE2_TX_LBERT_ERR_TRIG_VLD             (32'h0                                                   ),
    .LANE2_TX_LBERT_PATTERN_0_VLD            (32'h11111                                               ),
    .LANE2_TX_LBERT_PATTERN_1_VLD            (32'h0                                                   ),
    .LANE2_TX_LBERT_PATTERN_2_VLD            (32'h0                                                   ),
    .LANE2_TX_C16_PISO_CTRL_VLD              (32'h0                                                   ),
    .LANE2_TX_C16_DATA_CTRL_0_VLD            (32'h14000130                                            ),
    .LANE2_TX_C16_LBERT_CTRL_VLD             (32'h1                                                   ),
    .LANE2_TX_C16_LBERT_PATTERN_VLD          (32'h0                                                   ),
    .LANE2_TX_GEARBOX_CTL_VLD                (32'h38                                                  ),
    .LANE2_TX_PI_CTL_VLD                     (32'h3001                                                ),
    .LANE2_TX_DPLL_CTL_VLD                   (32'h14000                                               ),
    .LANE2_TX_PCSFIFO_STS_VLD                (32'h0                                                   ),
    .LANE2_TX_PWR_CTL_VLD                    ({28'h1028080,2'b0,PH1P_HXT_FAST_SIM,1'b0}               ),
    .LANE2_TX_PCIE_EQ_G1_VLD                 (32'h3f00                                                ),
    .LANE2_TX_PCIE_EQ_G2_VLD                 (32'h0                                                   ),
    .LANE2_TX_PCIE_EQ_G3_VLD                 (32'h0                                                   ),
    .LANE2_RX_CLK_CTRL_0_VLD                 (32'h80880029                                            ),
    .LANE2_RX_RST_CTRL_0_VLD                 (32'h3f                                                  ),
    .LANE2_RX_DATA_WIDTH_VLD                 (32'h128                                                 ),
    .LANE2_RX_ENC_EN_VLD                     (32'h800fe00                                             ),
    .LANE2_RX_DATA_CTRL_0_VLD                (32'h380                                                 ),
    .LANE2_RX_DATA_CTRL_1_VLD                (32'h1                                                   ),
    .LANE2_RX_GEARBOX_CTL_VLD                (32'h308                                                 ),
    .LANE2_RX_ALIGN_EN_CTRL_VLD              (32'h1007                                                ),
    .LANE2_RX_ALIGN_COMMA_MASK_VLD           (32'h1003ff                                              ),
    .LANE2_RX_ALIGN_COMMA_VLD                (32'hfa0305                                              ),
    .LANE2_RX_SKIP_CTRL_VLD                  (32'h2000                                                ),
    .LANE2_RX_SKIP1_PATTERN1_VLD             (32'h0                                                   ),
    .LANE2_RX_SKIP1_PATTERN2_VLD             (32'h0                                                   ),
    .LANE2_RX_SKIP2_PATTERN1_VLD             (32'h0                                                   ),
    .LANE2_RX_SKIP2_PATTERN2_VLD             (32'h0                                                   ),
    .LANE2_RX_SKIP_MARK_VLD                  (32'h0                                                   ),
    .LANE2_RX_SIPO_ALIGN_VLD                 (32'h74c                                                 ),
    .LANE2_RX_SIPO_STS_VLD                   (32'h0                                                   ),
    .LANE2_RX_LBERT_CTRL_VLD                 (32'h3205                                                ),
    .LANE2_RX_LBERT_ERRCNT_LATCH_VLD         (32'h0                                                   ),
    .LANE2_RX_C16_LBERT_CTRL_0_VLD           (32'h1                                                   ),
    .LANE2_RX_C16_LBERT_ERRCNT_LATCH_VLD     (32'h0                                                   ),
    .LANE2_RX_PWR_CTL_VLD                    ({28'h0028008,2'h0,PH1P_HXT_FAST_SIM,1'b0}               ),
    .LANE2_RX_EQ_CTL_VLD                     (32'h8                                                   ),
    .LANE2_MISC_CTL_0_VLD                    (32'h0                                                   ),
    .LANE2_MISC_CTL_1_VLD                    (32'h1c6c                                                ),
    .LANE2_PCS_TX_CTL_INT_VLD                (32'h0                                                   ),
    .LANE2_PCS_TX_STS_INT_VLD                (32'h0                                                   ),
    .LANE2_PCS_RX_CTL_INT_VLD                (32'h0                                                   ),
    .LANE2_PCS_RX_STS_INT_VLD                (32'h0                                                   ),
    .LANE2_DEBUG_IO_CTRL_VLD                 (32'h0                                                   ),
    .LANE2_DEBUG_CLK_CTRL_VLD                (32'h0                                                   ),
    .LANE3_TX_DATA_FFE00_VLD                 (32'h7f01                                                ),
    .LANE3_TX_DATA_FFE01_VLD                 (32'h0                                                   ),
    .LANE3_TX_DATA_FFE02_VLD                 (32'h0                                                   ),
    .LANE3_TX_DATA_FFE03_VLD                 (32'h0                                                   ),
    .LANE3_TX_DATA_FFE04_VLD                 (32'h0                                                   ),
    .LANE3_TX_CLK_PATH00_VLD                 (32'h10145                                               ),
    .LANE3_TX_DCC_CTRL_VLD                   ({PH1P_HXT_FAST_SIM,31'h3425}                            ),
    .LANE3_TX_DRV_CTRL_VLD                   (32'h0                                                   ),
    .LANE3_TX_RCV_DET_CTL_VLD                (32'h1                                                   ),
    .LANE3_TX_PLL_MAIN_CTL_VLD               ({PH1P_HXT_FAST_SIM,31'h00040105}                        ),
    .LANE3_TX_PLL_LOOP_CTL_VLD               (32'h7036a7b                                             ),
    .LANE3_TX_FBDIV_CTL00_VLD                (32'h6000050                                             ),
    .LANE3_TX_FBDIV_CTL01_VLD                ({1'b0,PH1P_HXT_FAST_SIM,30'h05080000}                   ),
    .LANE3_TX_PLL_FRACN_CTL_VLD              (32'h0                                                   ),
    .LANE3_TX_PLL_SSC_FREQ_DIV_VLD           (32'h0                                                   ),
    .LANE3_TX_PLL_SSC_RNGE_VLD               (32'h0                                                   ),
    .LANE3_TX_PLL_TEST_CTL_VLD               (32'h40                                                  ),
    .LANE3_TX_GLBL_MISC00_VLD                (32'h123                                                 ),
    .LANE3_TX_GLBL_MISC01_VLD                (32'h0                                                   ),
    .LANE3_TX_RESERVE00_VLD                  (32'h0                                                   ),
    .LANE3_RX_GLOBAL_MISC_RESERVED00_VLD     (32'h10102                                               ),
    .LANE3_RX_LOS_ACJTAG00_VLD               (32'h3                                                   ),
    .LANE3_RX_AFE_TERM_ATT00_VLD             (32'h8f70010                                             ),
    .LANE3_RX_ATT_CTLE00_VLD                 (32'h701                                                 ),
    .LANE3_RX_ATT_CTLE01_VLD                 (32'h50                                                  ),
    .LANE3_RX_ATT_CTLE02_VLD                 (32'h5503452                                             ),
    .LANE3_RX_DFE_SUMMER_VDAC_IDAC00_VLD     (32'h11                                                  ),
    .LANE3_RX_DFE_SUMMER_VDAC_IDAC01_VLD     (32'h20202020                                            ),
    .LANE3_RX_DFE_SUMMER_VDAC_IDAC02_VLD     (32'h20202020                                            ),
    .LANE3_RX_DFE_SUMMER_VDAC_IDAC03_VLD     (32'h20202020                                            ),
    .LANE3_RX_DFE_SUMMER_VDAC_IDAC04_VLD     (32'h0                                                   ),
    .LANE3_RX_DFE_SUMMER_VDAC_IDAC05_VLD     (32'h0                                                   ),
    .LANE3_RX_DFE_SUMMER_VDAC_IDAC06_VLD     (32'h0                                                   ),
    .LANE3_RX_DFE_SUMMER_VDAC_IDAC07_VLD     (32'h0                                                   ),
    .LANE3_RX_CLK_PATH_WITH_PLL00_VLD        (32'h36261e0d                                            ),
    .LANE3_RX_CLK_PATH_WITH_PLL01_VLD        (32'h34030332                                            ),
    .LANE3_RX_CLK_PATH_WITH_PLL02_VLD        (32'h50c                                                 ),
    .LANE3_RX_CLK_PATH_WITH_PLL03_VLD        ({3'h0,PH1P_HXT_FAST_SIM,28'h600}                        ),
    .LANE3_RX_CLK_PATH_WITH_PLL04_VLD        ({1'b0,PH1P_HXT_FAST_SIM,30'h05080000}                   ),
    .LANE3_RX_PLL_FRACN_CTL_VLD              (32'h0                                                   ),
    .LANE3_RX_PLL_SSC_FREQ_DIV_VLD           (32'h0                                                   ),
    .LANE3_RX_PLL_SSC_RNGE_VLD               (32'h0                                                   ),
    .LANE3_RX_DESER_CDR00_VLD                (32'h3612203                                             ),
    .LANE3_RX_DESER_CDR02_VLD                (32'h1                                                   ),
    .LANE3_RX_DESER_CDR03_VLD                (32'h0                                                   ),
    .LANE3_RX_DESER_CDR04_VLD                (32'h0                                                   ),
    .LANE3_RX_DIG_CALI_1_VLD                 (32'h0                                                   ),
    .LANE3_RX_DIG_CALI_2_VLD                 (32'h0                                                   ),
    .LANE3_RX_DIG_CALI_3_VLD                 (32'h0                                                   ),
    .LANE3_RX_DIG_CALI_4_VLD                 (32'h0                                                   ),
    .LANE3_RX_DIG_CALI_5_VLD                 (32'h18000000                                            ),
    .LANE3_RX_DIG_CALI_6_VLD                 (32'h40001007                                            ),
    .LANE3_RX_DIG_CALI_7_VLD                 (32'h0                                                   ),
    .LANE3_RX_DIG_CALI_8_VLD                 (32'h0                                                   ),
    .LANE3_RX_DIG_CALI_9_VLD                 (32'h0                                                   ),
    .LANE3_RX_DIG_CALI_10_VLD                (32'h0                                                   ),
    .LANE3_RX_DIG_CALI_11_VLD                (32'h0                                                   ),
    .LANE3_RX_DIG_CALI_12_VLD                (32'h0                                                   ),
    .LANE3_RX_DIG_CALI_13_VLD                (32'h0                                                   ),
    .LANE3_RX_DIG_CALI_14_VLD                (32'h0                                                   ),
    .LANE3_TX_CLK_CTRL_0_VLD                 ({22'h80140,TX_REFCLK_SEL,9'h41}                         ),
    .LANE3_TX_RST_CTRL_0_VLD                 (32'hf                                                   ),
    .LANE3_LANE_PROTOCOL_VLD                 (32'h80                                                  ),
    .LANE3_TX_DATA_WIDTH_VLD                 (32'h128                                                 ),
    .LANE3_TX_ENC_EN_VLD                     (32'h40                                                  ),
    .LANE3_TX_DATA_CTRL_0_VLD                (32'h102                                                 ),
    .LANE3_TX_LBERT_CTRL_VLD                 (32'h205                                                 ),
    .LANE3_TX_LBERT_ERR_TRIG_VLD             (32'h0                                                   ),
    .LANE3_TX_LBERT_PATTERN_0_VLD            (32'h11111                                               ),
    .LANE3_TX_LBERT_PATTERN_1_VLD            (32'h0                                                   ),
    .LANE3_TX_LBERT_PATTERN_2_VLD            (32'h0                                                   ),
    .LANE3_TX_C16_PISO_CTRL_VLD              (32'h0                                                   ),
    .LANE3_TX_C16_DATA_CTRL_0_VLD            (32'h14000130                                            ),
    .LANE3_TX_C16_LBERT_CTRL_VLD             (32'h1                                                   ),
    .LANE3_TX_C16_LBERT_PATTERN_VLD          (32'h0                                                   ),
    .LANE3_TX_GEARBOX_CTL_VLD                (32'h38                                                  ),
    .LANE3_TX_PI_CTL_VLD                     (32'h3001                                                ),
    .LANE3_TX_DPLL_CTL_VLD                   (32'h14000                                               ),
    .LANE3_TX_PCSFIFO_STS_VLD                (32'h0                                                   ),
    .LANE3_TX_PWR_CTL_VLD                    ({28'h1028080,2'b0,PH1P_HXT_FAST_SIM,1'b0}               ),
    .LANE3_TX_PCIE_EQ_G1_VLD                 (32'h3f00                                                ),
    .LANE3_TX_PCIE_EQ_G2_VLD                 (32'h0                                                   ),
    .LANE3_TX_PCIE_EQ_G3_VLD                 (32'h0                                                   ),
    .LANE3_RX_CLK_CTRL_0_VLD                 (32'h80880029                                            ),
    .LANE3_RX_RST_CTRL_0_VLD                 (32'h3f                                                  ),
    .LANE3_RX_DATA_WIDTH_VLD                 (32'h128                                                 ),
    .LANE3_RX_ENC_EN_VLD                     (32'h800fe00                                             ),
    .LANE3_RX_DATA_CTRL_0_VLD                (32'h380                                                 ),
    .LANE3_RX_DATA_CTRL_1_VLD                (32'h1                                                   ),
    .LANE3_RX_GEARBOX_CTL_VLD                (32'h308                                                 ),
    .LANE3_RX_ALIGN_EN_CTRL_VLD              (32'h1007                                                ),
    .LANE3_RX_ALIGN_COMMA_MASK_VLD           (32'h1003ff                                              ),
    .LANE3_RX_ALIGN_COMMA_VLD                (32'hfa0305                                              ),
    .LANE3_RX_SKIP_CTRL_VLD                  (32'h2000                                                ),
    .LANE3_RX_SKIP1_PATTERN1_VLD             (32'h0                                                   ),
    .LANE3_RX_SKIP1_PATTERN2_VLD             (32'h0                                                   ),
    .LANE3_RX_SKIP2_PATTERN1_VLD             (32'h0                                                   ),
    .LANE3_RX_SKIP2_PATTERN2_VLD             (32'h0                                                   ),
    .LANE3_RX_SKIP_MARK_VLD                  (32'h0                                                   ),
    .LANE3_RX_SIPO_ALIGN_VLD                 (32'h74c                                                 ),
    .LANE3_RX_SIPO_STS_VLD                   (32'h0                                                   ),
    .LANE3_RX_LBERT_CTRL_VLD                 (32'h3205                                                ),
    .LANE3_RX_LBERT_ERRCNT_LATCH_VLD         (32'h0                                                   ),
    .LANE3_RX_C16_LBERT_CTRL_0_VLD           (32'h1                                                   ),
    .LANE3_RX_C16_LBERT_ERRCNT_LATCH_VLD     (32'h0                                                   ),
    .LANE3_RX_PWR_CTL_VLD                    ({28'h0028008,2'h0,PH1P_HXT_FAST_SIM,1'b0}               ),
    .LANE3_RX_EQ_CTL_VLD                     (32'h8                                                   ),
    .LANE3_MISC_CTL_0_VLD                    (32'h0                                                   ),
    .LANE3_MISC_CTL_1_VLD                    (32'h1c6c                                                ),
    .LANE3_PCS_TX_CTL_INT_VLD                (32'h0                                                   ),
    .LANE3_PCS_TX_STS_INT_VLD                (32'h0                                                   ),
    .LANE3_PCS_RX_CTL_INT_VLD                (32'h0                                                   ),
    .LANE3_PCS_RX_STS_INT_VLD                (32'h0                                                   ),
    .LANE3_DEBUG_IO_CTRL_VLD                 (32'h0                                                   ),
    .LANE3_DEBUG_CLK_CTRL_VLD                (32'h0                                                   )

) u_hxt_top(
    .scan_rst_n                              (1'b1                                                    ),
    .scan_mode_n                             (1'b1                                                    ),
    .scan_clk                                (1'b1                                                    ),
    .scan_enable_n                           (1'b1                                                    ),
    .scancompress_mode                       (1'b0                                                    ),
    .scan_in                                 (10'd0                                                   ),
    .scan_out                                (                                                        ),
    .mbist_mode_n                            (1'b1                                                    ),
    .dft_jtag_tck                            (1'b1                                                    ),
    .dft_jtag_trst_n                         (1'b1                                                    ),
    .dft_jtag_tms                            (1'b0                                                    ),
    .dft_jtag_tdi                            (1'b0                                                    ),
    .dft_jtag_tdo                            (                                                        ),

    .apb4_clk_i                              (apb4_clk_i                                              ),
    .apb4_preset_i                           (apb4_preset_i                                           ),
    .apb4_psel_i                             (apb4_psel_i                                             ),
    .apb4_penable_i                          (apb4_penable_i                                          ),
    .apb4_pwrite_i                           (apb4_pwrite_i                                           ),
    .apb4_paddr_i                            (apb4_paddr_i                                            ),
    .apb4_pwdata_i                           (apb4_pwdata_i                                           ),
    .apb4_pstrb_i                            (apb4_pstrb_i                                            ),
    .apb4_pprot_i                            (apb4_pprot_i                                            ),
    .apb4_prdata_o                           (apb4_prdata_o                                           ),
    .apb4_pready_o                           (apb4_pready_o                                           ),
    .apb4_pslverr_o                          (apb4_pslverr_o                                          ),

    .jtag_tck                                (1'b1                                                    ),
    .jtag_tms                                (1'b0                                                    ),
    .jtag_tdi                                (1'b0                                                    ),
    .jtag_tdo                                (                                                        ),
    .jtag_tdo_en                             (                                                        ),
    .cmnresetdone                            (common_reset_done                                       ),
    .refclkout                               (                                                        ),
    .phy_reset                               (tl_power_on_rst                                         ),
    .phy_pipe_reset                          (1'b0                                                    ),
    .tx0_usr2clk                             (1'b1                                                    ),
    .rx0_usr2clk                             (1'b1                                                    ),
    .tx0_out2clk                             (                                                        ),
    .rx0_out2clk                             (                                                        ),
    .l0_resetmode_sel                        (1'b0                                                    ),
    .tx0_reset                               (1'b0                                                    ),
    .tx0_pma_reset                           (1'b0                                                    ),
    .tx0_pcs_reset                           (1'b0                                                    ),
    .tx0_pcsfifo_reset                       (1'b0                                                    ),
    .tx0_userrdy                             (1'b0                                                    ),
    .rx0_reset                               (1'b0                                                    ),
    .rx0_pma_reset                           (1'b0                                                    ),
    .rx0_pcs_reset                           (1'b0                                                    ),
    .rx0_pcsfifo_reset                       (1'b0                                                    ),
    .rx0_userrdy                             (1'b0                                                    ),
    .tx0_resetdone                           (tx0_reset_done                                          ),
    .rx0_resetdone                           (rx0_reset_done                                          ),
    .tx0_data                                (64'b0                                                   ),
    .tx0_ctrl0_data                          (8'b0                                                    ),
    .tx0_ctrl1_data                          (8'b0                                                    ),
    .tx0_ctrl2_data                          (8'b0                                                    ),
    .tx0_data_en                             (1'b0                                                    ),
    .tx0_header                              (3'b0                                                    ),
    .tx0_sequence                            (7'b0                                                    ),
    .tx0_8b10b_en                            (1'b0                                                    ),
    .rx0_gearboxslip                         (1'b0                                                    ),
    .rx0_slide                               (1'b0                                                    ),
    .rx0_8b10b_en                            (1'b0                                                    ),
    .rx0_gpon_en                             (1'b0                                                    ),
    .rx0_data                                (                                                        ),
    .rx0_ctrl0_data                          (                                                        ),
    .rx0_ctrl1_data                          (                                                        ),
    .rx0_ctrl2_data                          (                                                        ),
    .rx0_ctrl3_data                          (                                                        ),
    .rx0_header                              (                                                        ),
    .rx0_datavalid                           (                                                        ),
    .rx0_headervalid                         (                                                        ),
    .rx0_startofseq                          (                                                        ),
    .tx0_req                                 (1'b0                                                    ),
    .tx0_pstate                              (2'b0                                                    ),
    .tx0_rate                                (3'b0                                                    ),
    .tx0_detrx_req                           (1'b0                                                    ),
    .tx0_detrx_result                        (                                                        ),
    .tx0_ack                                 (                                                        ),
    .rx0_req                                 (1'b0                                                    ),
    .rx0_pstate                              (2'b0                                                    ),
    .rx0_rate                                (3'b0                                                    ),
    .rx0_ack                                 (                                                        ),
    .tx0_polarity                            (1'b0                                                    ),
    .tx0_eq_ctrl                             (2'b0                                                    ),
    .tx0_eq_pre                              (6'b0                                                    ),
    .tx0_eq_main                             (6'b0                                                    ),
    .tx0_eq_post                             (6'b0                                                    ),
    .tx0_eq_preset                           (5'b0                                                    ),
    .tx0_eq_getlocal_pset_coef               (1'b0                                                    ),
    .tx0_eq_local_tx_pset_coef               (                                                        ),
    .tx0_eq_local_tx_coef_valid              (                                                        ),
    .tx0_eq_localfs                          (                                                        ),
    .tx0_eq_locallf                          (                                                        ),
    .rx0_polarity                            (1'b0                                                    ),
    .rx0_adapt_cont                          (1'b0                                                    ),
    .rx0_adapt_in_prog                       (1'b0                                                    ),
    .rx0_adapt_req                           (1'b0                                                    ),
    .rx0_adapt_invalid_req                   (1'b0                                                    ),
    .rx0_adapt_ctrl                          (2'b0                                                    ),
    .rx0_adapt_ack                           (                                                        ),
    .rx0_adapt_fom                           (                                                        ),
    .rx0_txmain_dir                          (                                                        ),
    .rx0_txpost_dir                          (                                                        ),
    .rx0_txpre_dir                           (                                                        ),
    .tx1_usr2clk                             (1'b1                                                    ),
    .rx1_usr2clk                             (1'b1                                                    ),
    .tx1_out2clk                             (                                                        ),
    .rx1_out2clk                             (                                                        ),
    .l1_resetmode_sel                        (1'b0                                                    ),
    .tx1_reset                               (1'b0                                                    ),
    .tx1_pma_reset                           (1'b0                                                    ),
    .tx1_pcs_reset                           (1'b0                                                    ),
    .tx1_pcsfifo_reset                       (1'b0                                                    ),
    .tx1_userrdy                             (1'b0                                                    ),
    .rx1_reset                               (1'b0                                                    ),
    .rx1_pma_reset                           (1'b0                                                    ),
    .rx1_pcs_reset                           (1'b0                                                    ),
    .rx1_pcsfifo_reset                       (1'b0                                                    ),
    .rx1_userrdy                             (1'b0                                                    ),
    .tx1_resetdone                           (tx1_reset_done                                          ),
    .rx1_resetdone                           (rx1_reset_done                                          ),
    .tx1_data                                (64'b0                                                   ),
    .tx1_ctrl0_data                          (8'b0                                                    ),
    .tx1_ctrl1_data                          (8'b0                                                    ),
    .tx1_ctrl2_data                          (8'b0                                                    ),
    .tx1_data_en                             (1'b0                                                    ),
    .tx1_header                              (3'b0                                                    ),
    .tx1_sequence                            (7'b0                                                    ),
    .tx1_8b10b_en                            (1'b0                                                    ),
    .rx1_gearboxslip                         (1'b0                                                    ),
    .rx1_slide                               (1'b0                                                    ),
    .rx1_8b10b_en                            (1'b0                                                    ),
    .rx1_gpon_en                             (1'b0                                                    ),
    .rx1_data                                (                                                        ),
    .rx1_ctrl0_data                          (                                                        ),
    .rx1_ctrl1_data                          (                                                        ),
    .rx1_ctrl2_data                          (                                                        ),
    .rx1_ctrl3_data                          (                                                        ),
    .rx1_header                              (                                                        ),
    .rx1_datavalid                           (                                                        ),
    .rx1_headervalid                         (                                                        ),
    .rx1_startofseq                          (                                                        ),
    .tx1_req                                 (1'b0                                                    ),
    .tx1_pstate                              (2'b0                                                    ),
    .tx1_rate                                (3'b0                                                    ),
    .tx1_detrx_req                           (1'b0                                                    ),
    .tx1_detrx_result                        (                                                        ),
    .tx1_ack                                 (                                                        ),
    .rx1_req                                 (1'b0                                                    ),
    .rx1_pstate                              (2'b0                                                    ),
    .rx1_rate                                (3'b0                                                    ),
    .rx1_ack                                 (                                                        ),
    .tx1_polarity                            (1'b0                                                    ),
    .tx1_eq_ctrl                             (2'b0                                                    ),
    .tx1_eq_pre                              (6'b0                                                    ),
    .tx1_eq_main                             (6'b0                                                    ),
    .tx1_eq_post                             (6'b0                                                    ),
    .tx1_eq_preset                           (5'b0                                                    ),
    .tx1_eq_getlocal_pset_coef               (1'b0                                                    ),
    .tx1_eq_local_tx_pset_coef               (                                                        ),
    .tx1_eq_local_tx_coef_valid              (                                                        ),
    .tx1_eq_localfs                          (                                                        ),
    .tx1_eq_locallf                          (                                                        ),
                                                                                                        
    .rx1_polarity                            (1'b0                                                    ),
    .rx1_adapt_cont                          (1'b0                                                    ),
    .rx1_adapt_in_prog                       (1'b0                                                    ),
    .rx1_adapt_req                           (1'b0                                                    ),
    .rx1_adapt_invalid_req                   (1'b0                                                    ),
    .rx1_adapt_ctrl                          (2'b0                                                    ),
    .rx1_adapt_ack                           (                                                        ),
    .rx1_adapt_fom                           (                                                        ),
    .rx1_txmain_dir                          (                                                        ),
    .rx1_txpost_dir                          (                                                        ),
    .rx1_txpre_dir                           (                                                        ),
    .tx2_usr2clk                             (1'b1                                                    ),
    .rx2_usr2clk                             (1'b1                                                    ),
    .tx2_out2clk                             (                                                        ),
    .rx2_out2clk                             (                                                        ),
    .l2_resetmode_sel                        (1'b0                                                    ),
    .tx2_reset                               (1'b0                                                    ),
    .tx2_pma_reset                           (1'b0                                                    ),
    .tx2_pcs_reset                           (1'b0                                                    ),
    .tx2_pcsfifo_reset                       (1'b0                                                    ),
    .tx2_userrdy                             (1'b0                                                    ),
    .rx2_reset                               (1'b0                                                    ),
    .rx2_pma_reset                           (1'b0                                                    ),
    .rx2_pcs_reset                           (1'b0                                                    ),
    .rx2_pcsfifo_reset                       (1'b0                                                    ),
    .rx2_userrdy                             (1'b0                                                    ),
    .tx2_resetdone                           (tx2_reset_done                                          ),
    .rx2_resetdone                           (rx2_reset_done                                          ),
    .tx2_data                                (64'b0                                                   ),
    .tx2_ctrl0_data                          (8'b0                                                    ),
    .tx2_ctrl1_data                          (8'b0                                                    ),
    .tx2_ctrl2_data                          (8'b0                                                    ),
    .tx2_data_en                             (1'b0                                                    ),
    .tx2_header                              (3'b0                                                    ),
    .tx2_sequence                            (7'b0                                                    ),
    .tx2_8b10b_en                            (1'b0                                                    ),
    .rx2_gearboxslip                         (1'b0                                                    ),
    .rx2_slide                               (1'b0                                                    ),
    .rx2_8b10b_en                            (1'b0                                                    ),
    .rx2_gpon_en                             (1'b0                                                    ),
    .rx2_data                                (                                                        ),
    .rx2_ctrl0_data                          (                                                        ),
    .rx2_ctrl1_data                          (                                                        ),
    .rx2_ctrl2_data                          (                                                        ),
    .rx2_ctrl3_data                          (                                                        ),
    .rx2_header                              (                                                        ),
    .rx2_datavalid                           (                                                        ),
    .rx2_headervalid                         (                                                        ),
    .rx2_startofseq                          (                                                        ),
    .tx2_req                                 (1'b0                                                    ),
    .tx2_pstate                              (2'b0                                                    ),
    .tx2_rate                                (3'b0                                                    ),
    .tx2_detrx_req                           (1'b0                                                    ),
    .tx2_detrx_result                        (                                                        ),
    .tx2_ack                                 (                                                        ),
    .rx2_req                                 (1'b0                                                    ),
    .rx2_pstate                              (2'b0                                                    ),
    .rx2_rate                                (3'b0                                                    ),
    .rx2_ack                                 (                                                        ),
    .tx2_polarity                            (1'b0                                                    ),
    .tx2_eq_ctrl                             (2'b0                                                    ),
    .tx2_eq_pre                              (6'b0                                                    ),
    .tx2_eq_main                             (6'b0                                                    ),
    .tx2_eq_post                             (6'b0                                                    ),
    .tx2_eq_preset                           (5'b0                                                    ),
    .tx2_eq_getlocal_pset_coef               (1'b0                                                    ),
    .tx2_eq_local_tx_pset_coef               (                                                        ),
    .tx2_eq_local_tx_coef_valid              (                                                        ),
    .tx2_eq_localfs                          (                                                        ),
    .tx2_eq_locallf                          (                                                        ),
    .rx2_polarity                            (1'b0                                                    ),
    .rx2_adapt_cont                          (1'b0                                                    ),
    .rx2_adapt_in_prog                       (1'b0                                                    ),
    .rx2_adapt_req                           (1'b0                                                    ),
    .rx2_adapt_invalid_req                   (1'b0                                                    ),
    .rx2_adapt_ctrl                          (2'b0                                                    ),
    .rx2_adapt_ack                           (                                                        ),
    .rx2_adapt_fom                           (                                                        ),
    .rx2_txmain_dir                          (                                                        ),
    .rx2_txpost_dir                          (                                                        ),
    .rx2_txpre_dir                           (                                                        ),
    .tx3_usr2clk                             (1'b1                                                    ),
    .rx3_usr2clk                             (1'b1                                                    ),
    .tx3_out2clk                             (                                                        ),
    .rx3_out2clk                             (                                                        ),
    .l3_resetmode_sel                        (1'b0                                                    ),
    .tx3_reset                               (1'b0                                                    ),
    .tx3_pma_reset                           (1'b0                                                    ),
    .tx3_pcs_reset                           (1'b0                                                    ),
    .tx3_pcsfifo_reset                       (1'b0                                                    ),
    .tx3_userrdy                             (1'b0                                                    ),
    .rx3_reset                               (1'b0                                                    ),
    .rx3_pma_reset                           (1'b0                                                    ),
    .rx3_pcs_reset                           (1'b0                                                    ),
    .rx3_pcsfifo_reset                       (1'b0                                                    ),
    .rx3_userrdy                             (1'b0                                                    ),
    .tx3_resetdone                           (tx3_reset_done                                          ),
    .rx3_resetdone                           (rx3_reset_done                                          ),
    .tx3_data                                (64'b0                                                   ),
    .tx3_ctrl0_data                          (8'b0                                                    ),
    .tx3_ctrl1_data                          (8'b0                                                    ),
    .tx3_ctrl2_data                          (8'b0                                                    ),
    .tx3_data_en                             (1'b0                                                    ),
    .tx3_header                              (3'b0                                                    ),
    .tx3_sequence                            (7'b0                                                    ),
    .tx3_8b10b_en                            (1'b0                                                    ),
    .rx3_gearboxslip                         (1'b0                                                    ),
    .rx3_slide                               (1'b0                                                    ),
    .rx3_8b10b_en                            (1'b0                                                    ),
    .rx3_gpon_en                             (1'b0                                                    ),
    .rx3_data                                (                                                        ),
    .rx3_ctrl0_data                          (                                                        ),
    .rx3_ctrl1_data                          (                                                        ),
    .rx3_ctrl2_data                          (                                                        ),
    .rx3_ctrl3_data                          (                                                        ),
    .rx3_header                              (                                                        ),
    .rx3_datavalid                           (                                                        ),
    .rx3_headervalid                         (                                                        ),
    .rx3_startofseq                          (                                                        ),
    .tx3_req                                 (1'b0                                                    ),
    .tx3_pstate                              (2'b0                                                    ),
    .tx3_rate                                (3'b0                                                    ),
    .tx3_detrx_req                           (1'b0                                                    ),
    .tx3_detrx_result                        (                                                        ),
    .tx3_ack                                 (                                                        ),
    .rx3_req                                 (1'b0                                                    ),
    .rx3_pstate                              (2'b0                                                    ),
    .rx3_rate                                (3'b0                                                    ),
    .rx3_ack                                 (                                                        ),
    .tx3_polarity                            (1'b0                                                    ),
    .tx3_eq_ctrl                             (2'b0                                                    ),
    .tx3_eq_pre                              (6'b0                                                    ),
    .tx3_eq_main                             (6'b0                                                    ),
    .tx3_eq_post                             (6'b0                                                    ),
    .tx3_eq_preset                           (5'b0                                                    ),
    .tx3_eq_getlocal_pset_coef               (1'b0                                                    ),
    .tx3_eq_local_tx_pset_coef               (                                                        ),
    .tx3_eq_local_tx_coef_valid              (                                                        ),
    .tx3_eq_localfs                          (                                                        ),
    .tx3_eq_locallf                          (                                                        ),
    .rx3_polarity                            (1'b0                                                    ),
    .rx3_adapt_cont                          (1'b0                                                    ),
    .rx3_adapt_in_prog                       (1'b0                                                    ),
    .rx3_adapt_req                           (1'b0                                                    ),
    .rx3_adapt_invalid_req                   (1'b0                                                    ),
    .rx3_adapt_ctrl                          (2'b0                                                    ),
    .rx3_adapt_ack                           (                                                        ),
    .rx3_adapt_fom                           (                                                        ),
    .rx3_txmain_dir                          (                                                        ),
    .rx3_txpost_dir                          (                                                        ),
    .rx3_txpre_dir                           (                                                        ),
    .rx0_outclk                              (                                                        ), 
    .tx0_outclk                              (                                                        ),
    .rx1_outclk                              (                                                        ), 
    .tx1_outclk                              (                                                        ),
    .rx2_outclk                              (                                                        ), 
    .tx2_outclk                              (                                                        ),
    .rx3_outclk                              (                                                        ), 
    .tx3_outclk                              (                                                        ),        
    .tx0_pll_lock                            (                                                        ),
    .tx1_pll_lock                            (                                                        ),
    .tx2_pll_lock                            (                                                        ),
    .tx3_pll_lock                            (                                                        ),
    .rx0_pll_lock                            (                                                        ),
    .rx1_pll_lock                            (                                                        ),
    .rx2_pll_lock                            (                                                        ),
    .rx3_pll_lock                            (                                                        ),
    .rx0_pma_prbs_error                      (                                                        ),
    .rx1_pma_prbs_error                      (                                                        ),
    .rx2_pma_prbs_error                      (                                                        ),
    .rx3_pma_prbs_error                      (                                                        ),
    .tx0_pcsfifo_rd_halffull                 (                                                        ),
    .tx0_pcsfifo_rd_empty                    (                                                        ),
    .tx0_pcsfifo_wr_halffull                 (                                                        ),
    .tx0_pcsfifo_wr_full                     (                                                        ),
    .tx0_piso_pop_halffull                   (                                                        ),
    .tx0_piso_push_aempty                    (                                                        ),
    .tx0_piso_pop_empty                      (                                                        ),
    .tx0_piso_push_afull                     (                                                        ),
    .tx0_piso_push_halffull                  (                                                        ),
    .tx0_piso_push_full                      (                                                        ),
    .rx0_sipo_pop_halffull                   (                                                        ),
    .rx0_sipo_pop_aempty                     (                                                        ),
    .rx0_sipo_pop_empty                      (                                                        ),
    .rx0_sipo_push_afull                     (                                                        ),
    .rx0_sipo_push_halffull                  (                                                        ),
    .rx0_sipo_push_full                      (                                                        ),
    .rx0_rmfifo_high                         (                                                        ),
    .rx0_rmfifo_low                          (                                                        ),
    .rx0_rmfifo_overflow                     (                                                        ),
    .rx0_rmfifo_underflow                    (                                                        ),
    .rx0_wordrealign                         (                                                        ),
    .rx0_wordaligned                         (                                                        ),
    .rx0_rmfifo_corcnt                       (                                                        ),
    .rx0_sipo_align_lock                     (                                                        ),
    .tx0_dpll_lock                           (                                                        ),
    .tx0_pi_lock                             (                                                        ),
    .tx1_pcsfifo_rd_halffull                 (                                                        ),
    .tx1_pcsfifo_rd_empty                    (                                                        ),
    .tx1_pcsfifo_wr_halffull                 (                                                        ),
    .tx1_pcsfifo_wr_full                     (                                                        ),
    .tx1_piso_pop_halffull                   (                                                        ),
    .tx1_piso_push_aempty                    (                                                        ),
    .tx1_piso_pop_empty                      (                                                        ),
    .tx1_piso_push_afull                     (                                                        ),
    .tx1_piso_push_halffull                  (                                                        ),
    .tx1_piso_push_full                      (                                                        ),
    .rx1_sipo_pop_halffull                   (                                                        ),
    .rx1_sipo_pop_aempty                     (                                                        ),
    .rx1_sipo_pop_empty                      (                                                        ),
    .rx1_sipo_push_afull                     (                                                        ),
    .rx1_sipo_push_halffull                  (                                                        ),
    .rx1_sipo_push_full                      (                                                        ),
    .rx1_rmfifo_high                         (                                                        ),
    .rx1_rmfifo_low                          (                                                        ),
    .rx1_rmfifo_overflow                     (                                                        ),
    .rx1_rmfifo_underflow                    (                                                        ),
    .rx1_wordrealign                         (                                                        ),
    .rx1_wordaligned                         (                                                        ),
    .rx1_rmfifo_corcnt                       (                                                        ),
    .rx1_sipo_align_lock                     (                                                        ),
    .tx1_dpll_lock                           (                                                        ),
    .tx1_pi_lock                             (                                                        ),
    .tx2_pcsfifo_rd_halffull                 (                                                        ),
    .tx2_pcsfifo_rd_empty                    (                                                        ),
    .tx2_pcsfifo_wr_halffull                 (                                                        ),
    .tx2_pcsfifo_wr_full                     (                                                        ),
    .tx2_piso_pop_halffull                   (                                                        ),
    .tx2_piso_push_aempty                    (                                                        ),
    .tx2_piso_pop_empty                      (                                                        ),
    .tx2_piso_push_afull                     (                                                        ),
    .tx2_piso_push_halffull                  (                                                        ),
    .tx2_piso_push_full                      (                                                        ),
    .rx2_sipo_pop_halffull                   (                                                        ),
    .rx2_sipo_pop_aempty                     (                                                        ),
    .rx2_sipo_pop_empty                      (                                                        ),
    .rx2_sipo_push_afull                     (                                                        ),
    .rx2_sipo_push_halffull                  (                                                        ),
    .rx2_sipo_push_full                      (                                                        ),
    .rx2_rmfifo_high                         (                                                        ),
    .rx2_rmfifo_low                          (                                                        ),
    .rx2_rmfifo_overflow                     (                                                        ),
    .rx2_rmfifo_underflow                    (                                                        ),
    .rx2_wordrealign                         (                                                        ),
    .rx2_wordaligned                         (                                                        ),
    .rx2_rmfifo_corcnt                       (                                                        ),
    .rx2_sipo_align_lock                     (                                                        ),
    .tx2_dpll_lock                           (                                                        ),
    .tx2_pi_lock                             (                                                        ),
    .tx3_pcsfifo_rd_halffull                 (                                                        ),
    .tx3_pcsfifo_rd_empty                    (                                                        ),
    .tx3_pcsfifo_wr_halffull                 (                                                        ),
    .tx3_pcsfifo_wr_full                     (                                                        ),
    .tx3_piso_pop_halffull                   (                                                        ),
    .tx3_piso_push_aempty                    (                                                        ),
    .tx3_piso_pop_empty                      (                                                        ),
    .tx3_piso_push_afull                     (                                                        ),
    .tx3_piso_push_halffull                  (                                                        ),
    .tx3_piso_push_full                      (                                                        ),
    .rx3_sipo_pop_halffull                   (                                                        ),
    .rx3_sipo_pop_aempty                     (                                                        ),
    .rx3_sipo_pop_empty                      (                                                        ),
    .rx3_sipo_push_afull                     (                                                        ),
    .rx3_sipo_push_halffull                  (                                                        ),
    .rx3_sipo_push_full                      (                                                        ),
    .rx3_rmfifo_high                         (                                                        ),
    .rx3_rmfifo_low                          (                                                        ),
    .rx3_rmfifo_overflow                     (                                                        ),
    .rx3_rmfifo_underflow                    (                                                        ),
    .rx3_wordrealign                         (                                                        ),
    .rx3_wordaligned                         (                                                        ),
    .rx3_rmfifo_corcnt                       (                                                        ),
    .rx3_sipo_align_lock                     (                                                        ),
    .tx3_dpll_lock                           (                                                        ),
    .tx3_pi_lock                             (                                                        ),
    .refclk_extres_en                        (                                                        ),
     //analog pad    

      .rx0_n                                 (                                                        ),
      .rx0_p                                 (                                                        ),
      .tx0_n                                 (                                                        ),
      .tx0_p                                 (                                                        ),
      .rx1_n                                 (                                                        ),
      .rx1_p                                 (                                                        ),
      .tx1_n                                 (                                                        ),
      .tx1_p                                 (                                                        ),

      .rx2_n                                 (pcie_rx_n[1]                                            ),
      .rx2_p                                 (pcie_rx_p[1]                                            ),
      .tx2_n                                 (pcie_tx_n[1]                                            ),
      .tx2_p                                 (pcie_tx_p[1]                                            ),
      .rx3_n                                 (pcie_rx_n[0]                                            ),
      .rx3_p                                 (pcie_rx_p[0]                                            ),
      .tx3_n                                 (pcie_tx_n[0]                                            ),
      .tx3_p                                 (pcie_tx_p[0]                                            ),
       
    .rx_cdrclk_n                             (                                                        ),
    .rx_cdrclk_p                             (                                                        ),
    
    .ref0_clk_p                              (ref_pad_clk_p                                           ),
    .ref0_clk_n                              (ref_pad_clk_n                                           ),
    .ref1_clk_p                              (                                                        ),
    .ref1_clk_n                              (                                                        ),
    
    .groupclkout                             (                                                        ),
    .group0sigout                            (                                                        ),
    .group1sigout                            (                                                        ),
    .group2sigout                            (                                                        ),
    .group3sigout                            (                                                        ),
    .vdh_ready                               (                                                        ),
    .mcu_serdes_rxd                          (1'b0                                                    ),
    .mcu_serdes_txd                          (                                                        ),
    .mcu_phy_rst_sel                         (1'b0                                                    ),
    .mcu_phy_rst                             (1'b0                                                    ),
    .mcu_enable                              (1'b0                                                    ),
    .mcu_core_rst                            (1'b0                                                    ),
    .mcu_irq_o                               (                                                        ),
    .mcu_exchg_info_0                        (                                                        ),
    .mcu_sysrstreq                           (                                                        ),
    .cmn_pll_lock                            (                                                        ),
    .local_quad_rxclk                        (                                                        ),
    .other_quad_rxclk                        (                                                        ),
    .refclk_se                               (2'b11                                                   ),
    .pcie_osc_clk                            (serdes_osc_clk                                          ),
    .mac_phy_blockaligncontrol               (mac_phy_blockaligncontrol                               ),
    .mac_phy_txmargin                        (mac_phy_txmargin                                        ),
    .mac_phy_txswing                         (mac_phy_txswing                                         ),
    .mac_phy_powerdown                       (pl_powerdown[3:0]                                       ),
    .mac_phy_width                           (pl_width[1:0]                                           ),
    .mac_phy_pclk_rate                       (pl_pclk_rate[2:0]                                       ),
    .mac_phy_rate                            (pl_rate[1:0]                                            ),
    .mac_phy_txdata                          ({pl_txdata[31:0],pl_txdata[63:32],pl_txdata[95:64],pl_txdata[127:96]}                            ),
    .mac_phy_txdatak                         ({pl_txdatak[3:0],pl_txdatak[7:4],pl_txdatak[11:8],pl_txdatak[15:12]}                             ),
    .mac_phy_txdatavalid                     ({pl_txdatavalid[0],pl_txdatavalid[1],pl_txdatavalid[2],pl_txdatavalid[3]}                        ),
    .mac_phy_txsyncheader                    ({pl_txsyncheader[1:0],pl_txsyncheader[3:2],pl_txsyncheader[5:4],pl_txsyncheader[7:6]}            ),
    .mac_phy_txstartblock                    ({pl_txstartblock[0],pl_txstartblock[1],pl_txstartblock[2],pl_txstartblock[3]}                    ),
    .mac_phy_txelecidle                      ({pl_txelecidle[0],pl_txelecidle[1],pl_txelecidle[2],pl_txelecidle[3]}                            ),
    .mac_phy_txcompliance                    ({pl_txcompliance[0],pl_txcompliance[1],pl_txcompliance[2],pl_txcompliance[3]}                    ),
    .mac_phy_txdetectrx_loopback             ({pl_txdetectrx[0],pl_txdetectrx[1],pl_txdetectrx[2],pl_txdetectrx[3]}                            ),
    .mac_phy_rxpolarity                      (mac_phy_rxpolarity                                                                               ),
    .mac_phy_txdeemph                        (mac_phy_txdeemph                                                                                 ),
    .mac_phy_rxpresethint                    (mac_phy_rxpresethint                                                                             ),
    .mac_phy_fs                              (mac_phy_fs                                                                                       ),
    .mac_phy_lf                              (mac_phy_lf                                                                                       ),
    .mac_phy_local_pset_index                (mac_phy_local_pset_index                                                                         ),
    .mac_phy_getlocal_pset_coef              (mac_phy_getlocal_pset_coef                                                                       ),
    .mac_phy_rxeqeval                        (mac_phy_rxeqeval                                                                                 ),
    .mac_phy_rxeqinprogress                  (mac_phy_rxeqinprogress                                                                           ),
    .mac_phy_invalid_req                     (mac_phy_invalid_req                                                                              ),
    .mac_phy_rxstandby                       ({pl_rxstandby[0],pl_rxstandby[1],pl_rxstandby[2],pl_rxstandby[3]}                                ),
    .phy_mac_pclk                            (pl_pclk                                                                                          ),
    .phy_mac_rxdata                          ({pl_rxdata[31:0],pl_rxdata[63:32],pl_rxdata[95:64],pl_rxdata[127:96]}                            ),
    .phy_mac_rxdatak                         ({pl_rxdatak[3:0],pl_rxdatak[7:4],pl_rxdatak[11:8],pl_rxdatak[15:12]}                             ),
    .phy_mac_rxsyncheader                    ({pl_rxsyncheader[1:0],pl_rxsyncheader[3:2],pl_rxsyncheader[5:4],pl_rxsyncheader[7:6]}            ),
    .phy_mac_rxstartblock                    ({pl_rxstartblock[0],pl_rxstartblock[1],pl_rxstartblock[2],pl_rxstartblock[3]}                    ),
    .phy_mac_rxelecidle                      ({pl_rxelecidle[0],pl_rxelecidle[1],pl_rxelecidle[2],pl_rxelecidle[3]}                            ),
    .phy_mac_phystatus                       ({pl_phystatus[0],pl_phystatus[1],pl_phystatus[2],pl_phystatus[3]}                                ),
    .phy_mac_rxvalid                         ({pl_rxvalid[0],pl_rxvalid[1],pl_rxvalid[2],pl_rxvalid[3]}                                        ),
    .phy_mac_rxstatus                        ({pl_rxstatus[2:0],pl_rxstatus[5:3],pl_rxstatus[8:6],pl_rxstatus[11:9]}                           ),
    .phy_mac_rxdatavalid                     ({pl_rxdatavalid[0],pl_rxdatavalid[1],pl_rxdatavalid[2],pl_rxdatavalid[3]}                        ),
    .phy_mac_dirfeedback                     (phy_mac_dirfeedback                                                                              ),
    .phy_mac_fomfeedback                     (phy_mac_fomfeedback                                                                              ),
    .phy_mac_local_tx_pset_coef              (phy_mac_local_tx_pset_coef                                                                       ),
    .phy_mac_local_tx_coef_valid             (phy_mac_local_tx_coef_valid                                                                      ),
    .phy_mac_localfs                         (phy_mac_localfs                                                                                  ),
    .phy_mac_locallf                         (phy_mac_locallf                                                                                  ),
    .pcie_pclk_source_sel                    (cfg_pclk_source_sel                                                                              ),
    .pcie_pipe_lane_flip                     (cfg_pipe_lane_flip                                                                               ),
    .pcie_pipe_lane_enable                   ({cfg_pcie_lane_enable[0],cfg_pcie_lane_enable[1],cfg_pcie_lane_enable[2],cfg_pcie_lane_enable[3]}),
    .pcie_core_bypass                        (cfg_core_bypass                                                                                  ),
    .pcie_power_on_rst_n                     (cfg_power_on_rst_n                                                                               ),
    .pcie_pcs_pipe_rst_n                     (cfg_pcs_pipe_rst_n                                                                               ),
    .pcie_pcs_apb_rst_n                      (cfg_pcs_apb_rst_n                                                                                ),
    .pcie_core_sram_init_done                (cfg_core_sram_init_done                                                                          )
);

endmodule
