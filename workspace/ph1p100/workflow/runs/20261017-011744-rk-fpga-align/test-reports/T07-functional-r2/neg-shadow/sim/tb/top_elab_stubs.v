// =============================================================================
//  top_elab_stubs.v — 仅本 run 仿真用的三个厂商 IP 端口桩（T07.rk-align-backend）
//
//  目的：让 ModelSim 能**真实例化** ph1p_pcie_ep_top 做顶层接线/编译/精化检查
//  （G1：顶层真实接入）。三个 IP（pcie_ep_core / pcie_pll_ep / ddr3_mc_0）是
//  厂商加密交付，ModelSim 无其原语库，本桩只给**端口方向**、不做任何功能。
//  ⇒ 本桩不进入候选 manifest，不参与 TD 综合；TD 综合/STA 用真 IP（al_ip/）。
//  端口方向按 ph1p_pcie_ep_top.v 里的实例连接与信号用途逐个对出。
// =============================================================================
`timescale 1ns/1ps

module pcie_pll_ep (
    input  wire        refclk,
    input  wire        reset,
    output wire        lock,
    output wire        clk0_out
);
endmodule

module pcie_ep_core #(
    parameter PH1P_HXT_FAST_SIM = 1'b1
)(
    input  wire        ref_pad_clk_p,
    input  wire        ref_pad_clk_n,
    input  wire [1:0]  pcie_rx_p,
    input  wire [1:0]  pcie_rx_n,
    output wire [1:0]  pcie_tx_p,
    output wire [1:0]  pcie_tx_n,
    input  wire        tl_clk_user,
    input  wire        tl_clk_user_ce_n,
    output wire        tl_clk_locked,
    output wire        tl_clk_gate,
    input  wire        tl_power_on_rst,
    input  wire        tl_cfg_pclk,
    input  wire        tl_cfg_prst,
    input  wire        tl_cfg_penable,
    input  wire        tl_cfg_psel,
    input  wire        tl_cfg_pwrite,
    input  wire [31:0] tl_cfg_paddr,
    input  wire [3:0]  tl_cfg_pstrb,
    input  wire [31:0] tl_cfg_pwdata,
    output wire        tl_cfg_pready,
    output wire [31:0] tl_cfg_prdata,
    output wire        tl_cfg_pslverr,
    input  wire        apb4_clk_i,
    input  wire        apb4_preset_i,
    input  wire        apb4_psel_i,
    input  wire        apb4_penable_i,
    input  wire        apb4_pwrite_i,
    input  wire [31:0] apb4_paddr_i,
    input  wire [31:0] apb4_pwdata_i,
    input  wire [3:0]  apb4_pstrb_i,
    input  wire [2:0]  apb4_pprot_i,
    output wire [31:0] apb4_prdata_o,
    output wire        apb4_pready_o,
    output wire        apb4_pslverr_o,
    output wire [7:0]  tl_cfg_tcvc,
    output wire [12:0] tl_cfg_busdev,
    output wire [2:0]  tl_cfg_max_payload_size,
    output wire [2:0]  tl_cfg_max_read_request_size,
    output wire [2:0]  tl_cfg_current_link_speed,
    output wire [3:0]  tl_cfg_negotiated_width,
    output wire        tl_cfg_read_completion_boundary,
    output wire [7:0]  tl_cfg_pfregs_cmd,
    input  wire [7:0]  tl_cfg_pf0_primary_bus,
    input  wire [7:0]  tl_cfg_pf1_primary_bus,
    output wire [1:0]  pl_equ_phase,
    output wire [4:0]  tl_ltssm,
    output wire [4:0]  pl_ltssm,
    output wire        pl_link_up,
    input  wire        tl_ltssm_enable,
    input  wire        tl_rx_wait,
    input  wire        tl_rx_masknp,
    output wire [47:0] tl_rx_bardec,
    output wire [255:0] tl_rx_data,
    output wire        tl_rx_eop,
    output wire [7:0]  tl_rx_err,
    output wire [9:0]  tl_rx_mchit,
    output wire        tl_rx_sop,
    output wire [7:0]  tl_rx_valid,
    input  wire [255:0] tl_tx_data,
    input  wire        tl_tx_eop,
    input  wire [7:0]  tl_tx_err,
    input  wire        tl_tx_sop,
    input  wire        tl_tx_stream,
    input  wire [7:0]  tl_tx_valid,
    output wire        tl_tx_wait,
    output wire [95:0] tl_tx_credits
);
    // 桩：只给常量，防止 X 传播；不做任何功能
    assign tl_clk_locked = 1'b1;
    assign tl_clk_gate   = 1'b0;
    assign pl_link_up    = 1'b1;
    assign tl_cfg_max_payload_size = 3'd0;    // 128B（与 pusher 固定载荷一致）
    assign tl_cfg_max_read_request_size = 3'd0;
    assign tl_cfg_current_link_speed = 3'd1;
    assign tl_cfg_negotiated_width = 4'd1;
    assign tl_rx_data = 256'd0;
    assign tl_rx_valid = 8'd0;
    assign tl_tx_wait = 1'b0;
    assign tl_tx_credits = 96'd0;
endmodule

module ddr3_mc_0 (
    input  wire        ref_clk,
    input  wire        sys_rst_n,
    output wire        apb_pclk,
    input  wire        apb_prst_n,
    output wire        apb_pready,
    input  wire        apb_psel,
    input  wire        apb_penable,
    input  wire        apb_pwrite,
    input  wire [15:0] apb_paddr,
    input  wire [31:0] apb_pwdata,
    output wire [31:0] apb_prdata,
    output wire        dhi_clk,
    output wire        cfg_clk,
    output wire        cfg_rst_n,
    output wire        ddrphy_rst_n,
    output wire        ddrphy_rdy,
    input  wire        axi_aclk,
    input  wire        axi_aresetn,
    input  wire [3:0]  axi_awid,
    input  wire [28:0] axi_awaddr,
    input  wire [7:0]  axi_awlen,
    input  wire [2:0]  axi_awsize,
    input  wire [1:0]  axi_awburst,
    input  wire        axi_awvalid,
    output wire        axi_awready,
    input  wire [255:0] axi_wdata,
    input  wire [31:0] axi_wstrb,
    input  wire        axi_wlast,
    input  wire        axi_wvalid,
    output wire        axi_wready,
    output wire [3:0]  axi_bid,
    output wire [1:0]  axi_bresp,
    output wire        axi_bvalid,
    input  wire        axi_bready,
    input  wire [3:0]  axi_arid,
    input  wire [28:0] axi_araddr,
    input  wire [7:0]  axi_arlen,
    input  wire [2:0]  axi_arsize,
    input  wire [1:0]  axi_arburst,
    input  wire        axi_arvalid,
    output wire        axi_arready,
    output wire [3:0]  axi_rid,
    output wire [255:0] axi_rdata,
    output wire [1:0]  axi_rresp,
    output wire        axi_rlast,
    output wire        axi_rvalid,
    input  wire        axi_rready,
    input  wire [1:0]  usr_ref_type,
    input  wire        usr_ref_req,
    output wire        usr_ref_ack,
    output wire        ecc_err_sig,
    output wire        ecc_err_mul,
    output wire        ctl_ram_rst_n,
    output wire        ctl_ram_cke,
    output wire        ddr_ck_p,
    output wire        ddr_ck_n,
    output wire        ddr_reset_n,
    output wire        ddr_cke,
    output wire        ddr_odt,
    output wire        ddr_cs_n,
    output wire        ddr_ras_n,
    output wire        ddr_cas_n,
    output wire        ddr_we_n,
    output wire [2:0]  ddr_ba,
    output wire [13:0] ddr_addr,
    inout  wire [3:0]  ddr_dqs_p,
    inout  wire [3:0]  ddr_dqs_n,
    inout  wire [31:0] ddr_dq,
    inout  wire [3:0]  ddr_dm
);
    assign dhi_clk = 1'b0;
    assign ddrphy_rdy = 1'b1;
    assign axi_awready = 1'b1;
    assign axi_wready = 1'b1;
    assign axi_bvalid = 1'b0;
    assign axi_arready = 1'b1;
    assign axi_rvalid = 1'b0;
endmodule
