///////////////////////////////////////////////////////////////////////////////
//  ph1p_pcie_ep_top_dbg.v - T11.runB-debug-rtl debug-build top wrapper
//
//  ONLY used by the debug build entry: tools/pcie_integration/td/00_all_debug.tcl
//  Overrides DBG_CTRL_DEFAULT_EN=1'b1 into ph1p_pcie_ep_top -> ep_bar_win, so
//  the debug bit resets with CTRL bit0(enable)/bit5(ddr_en)=1 ONLY (TX / push /
//  doorbell domain stays 0). Production 00_all does NOT compile this file and
//  keeps defaults 0 (behaviour unchanged).
//  Port list mechanically generated from ph1p_pcie_ep_top.v port block by
//  run debug-rtl/gen_dbg_top.ps1 (single source of truth; passthrough u_top).
//
//  Expected CWC probe path (P2 confirms by elaboration, write back probe-map):
//    ph1p_pcie_ep_top_dbg/u_top/u_pcie_ep_engine/u_ep_bar_win/dbg_bank[287:0]
//    and dbg_bank_word0..dbg_bank_word8
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module ph1p_pcie_ep_top_dbg (
    input      wire                      ref_pad_clk_p                           ,
    input      wire                      ref_pad_clk_n                           ,
    input      wire  [1:0]               pcie_rx_p                               ,
    input      wire  [1:0]               pcie_rx_n                               ,
    output     wire  [1:0]               pcie_tx_p                               ,
    output     wire  [1:0]               pcie_tx_n                               ,
    input      wire                      user_int_trigger                        ,
    input      wire                      sys_clk                                 ,
    input      wire                      pcie_mperst                             ,
    input      wire                      pcie_power_on_rst                       ,
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

    ph1p_pcie_ep_top #(
        .DBG_CTRL_DEFAULT_EN (1'b1)
    ) u_top (
        .ref_pad_clk_p(ref_pad_clk_p),
        .ref_pad_clk_n(ref_pad_clk_n),
        .pcie_rx_p(pcie_rx_p),
        .pcie_rx_n(pcie_rx_n),
        .pcie_tx_p(pcie_tx_p),
        .pcie_tx_n(pcie_tx_n),
        .user_int_trigger(user_int_trigger),
        .sys_clk(sys_clk),
        .pcie_mperst(pcie_mperst),
        .pcie_power_on_rst(pcie_power_on_rst),
        .mipi_a_clk_hs_p(mipi_a_clk_hs_p),
        .mipi_a_clk_hs_n(mipi_a_clk_hs_n),
        .mipi_a_data_hs_p(mipi_a_data_hs_p),
        .mipi_a_data_hs_n(mipi_a_data_hs_n),
        .mipi_b_clk_hs_p(mipi_b_clk_hs_p),
        .mipi_b_clk_hs_n(mipi_b_clk_hs_n),
        .mipi_b_data_hs_p(mipi_b_data_hs_p),
        .mipi_b_data_hs_n(mipi_b_data_hs_n),
        .cam_a_mclk(cam_a_mclk),
        .cam_a_xclr_n(cam_a_xclr_n),
        .cam_a_scl(cam_a_scl),
        .cam_a_sda(cam_a_sda),
        .cam_b_mclk(cam_b_mclk),
        .cam_b_xclr_n(cam_b_xclr_n),
        .cam_b_scl(cam_b_scl),
        .cam_b_sda(cam_b_sda),
        .txd(txd),
        .debug_led(debug_led),
        .ddr_ck_p(ddr_ck_p),
        .ddr_ck_n(ddr_ck_n),
        .ddr_reset_n(ddr_reset_n),
        .ddr_cke(ddr_cke),
        .ddr_odt(ddr_odt),
        .ddr_cs_n(ddr_cs_n),
        .ddr_ras_n(ddr_ras_n),
        .ddr_cas_n(ddr_cas_n),
        .ddr_we_n(ddr_we_n),
        .ddr_ba(ddr_ba),
        .ddr_addr(ddr_addr),
        .ddr_dqs_p(ddr_dqs_p),
        .ddr_dqs_n(ddr_dqs_n),
        .ddr_dq(ddr_dq),
        .ddr_dm(ddr_dm)
    );

endmodule
