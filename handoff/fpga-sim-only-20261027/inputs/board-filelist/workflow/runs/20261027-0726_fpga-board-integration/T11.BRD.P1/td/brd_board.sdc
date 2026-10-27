# =============================================================================
# brd_board.sdc -- T11.BRD.P1 board timing constraints
#
# Base: fpga/csi2/pcie_integration/constraints/ph1p_pcie_case_ep.sdc (board
# proven PCIe/DDR/camera constraints), plus the T11.BRD additions:
#   * clk_core = 150.000 MHz (brd_a1_core_pll: 50/3*90/10), renamed from the
#     same PH1P PLL wrapper clock b18 used for its 187.5 MHz A1 clock.
#   * Gray-pointer bus skew for the two camera capture FIFOs and the three
#     bridge FIFOs (guide 4.1 C1/C2/C3).
#   * the two allowed false paths: pcie_power_on_rst (R14 async input) and
#     user_int_trigger (async key, synchronised in RTL).
# Forbidden by the frozen guide and NOT used here: any set_false_path or
# set_multicycle_path on an internal data path.
# =============================================================================
create_clock -name {sys_clk} -period 20.000 -waveform {0.000 10.000} [get_ports {sys_clk}]

derive_clocks
rename_clock -name {tl_clk_user} [get_clocks {u_pcie_pll_ep/ph1p_phy_pll_wrapper_Inst/u_PH1P_PHY_PLL.clkc[0]}]

# ---- T11.BRD: P4 core clock, 150.000 MHz (6.667 ns) ----
rename_clock -name {clk_core} [get_clocks {u_core_pll/u_pll/u_PH1P_PHY_PLL.clkc[0]}]

# ---- MIPI CSI-2 recovered byte clocks (A/B), unchanged from the base SDC ----
create_clock -name {cam_a_clk_lane} -period 1.333 -waveform {0.000 0.667} [get_ports {mipi_a_clk_hs_p}]
create_clock -name {cam_b_clk_lane} -period 1.333 -waveform {0.000 0.667} [get_ports {mipi_b_clk_hs_p}]

create_generated_clock -name {cam_a_byte_clk} -source [get_ports {mipi_a_clk_hs_p}] -divide_by 4 -phase 0 [get_pins {u_csi_a/u_rx_phy/u_hs_clk_div.clkdivout}]
create_generated_clock -name {cam_b_byte_clk} -source [get_ports {mipi_b_clk_hs_p}] -divide_by 4 -phase 0 [get_pins {u_csi_b/u_rx_phy/u_hs_clk_div.clkdivout}]

# ---- asynchronous clock groups ----
# Every crossing between these groups is a recorded CDC structure (guide 4.1):
#   C1/C2 capture_async_fifo (Gray + 2FF), C3 bridge WF/AF/RF (Gray + 2FF),
#   C4..C7 stable-hold + toggle mailboxes.  clk_core has no combinational or
#   registered data path to sys_clk / tl_clk_user / the camera or DDR domains
#   other than those structures, so it is listed as its own group.
set_clock_groups -asynchronous \
    -group [get_clocks {tl_clk_user sys_clk clk_core}] \
    -group [get_clocks {cam_a_clk_lane cam_a_byte_clk}] \
    -group [get_clocks {cam_b_clk_lane cam_b_byte_clk}] \
    -group [get_clocks {*usr_clk}]

# ---- the only two allowed asynchronous input false paths ----
set_false_path -from [get_ports {pcie_power_on_rst}]
set_false_path -from [get_ports {user_int_trigger}]

# ---- Gray-pointer bus skew (C1/C2/C3) ----
set_path_skew -from [get_regs {u_datapath/u_fe_a/u_cam_fifo/wgray[*]}] -to [get_regs {u_datapath/u_fe_a/u_cam_fifo/rq1_wgray[*]}] 4.000
set_path_skew -from [get_regs {u_datapath/u_fe_a/u_cam_fifo/rgray[*]}] -to [get_regs {u_datapath/u_fe_a/u_cam_fifo/wq1_rgray[*]}] 4.000
set_path_skew -from [get_regs {u_datapath/u_fe_b/u_cam_fifo/wgray[*]}] -to [get_regs {u_datapath/u_fe_b/u_cam_fifo/rq1_wgray[*]}] 4.000
set_path_skew -from [get_regs {u_datapath/u_fe_b/u_cam_fifo/rgray[*]}] -to [get_regs {u_datapath/u_fe_b/u_cam_fifo/wq1_rgray[*]}] 4.000
set_path_skew -from [get_regs {u_datapath/u_bridge/u_wf/wgray[*]}] -to [get_regs {u_datapath/u_bridge/u_wf/rq1_wgray[*]}] 4.000
set_path_skew -from [get_regs {u_datapath/u_bridge/u_wf/rgray[*]}] -to [get_regs {u_datapath/u_bridge/u_wf/wq1_rgray[*]}] 4.000
set_path_skew -from [get_regs {u_datapath/u_bridge/u_af/wgray[*]}] -to [get_regs {u_datapath/u_bridge/u_af/rq1_wgray[*]}] 4.000
set_path_skew -from [get_regs {u_datapath/u_bridge/u_af/rgray[*]}] -to [get_regs {u_datapath/u_bridge/u_af/wq1_rgray[*]}] 4.000
set_path_skew -from [get_regs {u_datapath/u_bridge/u_rf/wgray[*]}] -to [get_regs {u_datapath/u_bridge/u_rf/rq1_wgray[*]}] 4.000
set_path_skew -from [get_regs {u_datapath/u_bridge/u_rf/rgray[*]}] -to [get_regs {u_datapath/u_bridge/u_rf/wq1_rgray[*]}] 4.000

derive_clocks
