# =============================================================================
# P2 board timing constraints (T10.b2-a1-uart-impl r0)
# Derived from the board-verified camera_csi_integrity timing.sdc; the A1 chain
# and the 187.5 -> dhi_clk bridge are added.  The frozen small-top SDC 227dd39e
# is untouched; this is a P2 copy.
#
# Real asynchronous crossings (recorded, not generic false paths):
#   * MIPI-A byte clock (111.375 MHz, recovered from the clock lane) <-> 187.5 MHz
#     A1 domain: capture_async_fifo (Gray pointers + 2FF), A1 crop source domain.
#   * 187.5 MHz A1 <-> dhi_clk DDR user: p2_ddr_bridge Gray-pointer FIFOs.
#   * HDMI pclkx1/pclkx5 and mclk27 vs the camera/A1/DDR domains: separate PLL
#     outputs used only by the display / sensor control paths.
#   * The startup MCLK enable handshake remains the only 50 MHz -> mclk27 path.
# =============================================================================

create_clock -name {sys_clk50m} -period 20.000 -waveform {0.000 10.000} [get_ports {sys_clk50m}]

create_clock -name {mipi_a_clk_hs} -period 2.244669 -waveform {0.000000 1.1223345} [get_ports {mipi_a_clk_hs_p}]

create_clock -name {mipi_b_clk_hs} -period 2.244669 -waveform {0.000000 1.1223345} [get_ports {mipi_b_clk_hs_p}]

create_generated_clock -name {mipi_a_byte_clk} -source [get_ports {mipi_a_clk_hs_p}] -divide_by 4 [get_pins {u_camera/u_csi_a/u_rx_phy/u_hs_clk_div.clkdivout}]

rename_clock -name {pclkx1} [get_clocks {u_camera/X_ui_pll/ph1p_phy_pll_wrapper_Inst/u_PH1P_PHY_PLL.clkc[0]}]

rename_clock -name {pclkx5} [get_clocks {u_camera/X_ui_pll/ph1p_phy_pll_wrapper_Inst/u_PH1P_PHY_PLL.clkc[1]}]

rename_clock -name {mclk27} [get_clocks {u_camera/X_ui_pll/ph1p_phy_pll_wrapper_Inst/u_PH1P_PHY_PLL.clkc[2]}]

# A+ 187.5 MHz (50 MHz / 3 * 90 / 8, exactly 5.333 ns)
rename_clock -name {clk_a1} [get_clocks {u_a1_pll/u_pll/u_PH1P_PHY_PLL.clkc[0]}]

rename_clock -name {ddr_user} [get_clocks {u_ddrmc_test_top/u_ddrmc_x32/usr_clk}]

set_clock_groups -asynchronous \
    -group {sys_clk50m pclkx1 pclkx5 mclk27 clk_a1} \
    -group {ddr_user} \
    -group {mipi_a_clk_hs mipi_a_byte_clk} \
    -group {mipi_b_clk_hs}

# Registered monotonic enable -> first falling-edge MCLK synchronizer only.
set_false_path -from [get_clocks {sys_clk50m}] -through [get_nets {u_camera/u_camera_startup/enable_request}] -to [get_clocks {mclk27}]

# Board asynchronous inputs: power-on reset and the UART RX start-bit input.
# Both are real asynchronous pins (no source-synchronous data relationship).
set_false_path -from [get_ports {sys_rst_n}]
set_false_path -from [get_ports {usr_uart_rxd}]

# Gray-pointer bus skew for the P1 cam->A1 FIFO and the three bridge FIFOs.
set_path_skew -from [get_regs {u_a1/u_cam_fifo/wgray[*]}] -to [get_regs {u_a1/u_cam_fifo/rq1_wgray[*]}] 4.000
set_path_skew -from [get_regs {u_a1/u_cam_fifo/rgray[*]}] -to [get_regs {u_a1/u_cam_fifo/wq1_rgray[*]}] 4.000
set_path_skew -from [get_regs {u_bridge/u_wf/wgray[*]}] -to [get_regs {u_bridge/u_wf/rq1_wgray[*]}] 4.000
set_path_skew -from [get_regs {u_bridge/u_wf/rgray[*]}] -to [get_regs {u_bridge/u_wf/wq1_rgray[*]}] 4.000
set_path_skew -from [get_regs {u_bridge/u_af/wgray[*]}] -to [get_regs {u_bridge/u_af/rq1_wgray[*]}] 4.000
set_path_skew -from [get_regs {u_bridge/u_af/rgray[*]}] -to [get_regs {u_bridge/u_af/wq1_rgray[*]}] 4.000
set_path_skew -from [get_regs {u_bridge/u_rf/wgray[*]}] -to [get_regs {u_bridge/u_rf/rq1_wgray[*]}] 4.000
set_path_skew -from [get_regs {u_bridge/u_rf/rgray[*]}] -to [get_regs {u_bridge/u_rf/wq1_rgray[*]}] 4.000

# I/O timing:
#   * DDR3 pins are constrained by the generated DDR IP SDC (write/read levelling).
#   * MIPI-A/B input sampling uses the PHY internal IDELAY (manual tap 46) and the
#     soft PHY; no external source-synchronous setup/hold relationship exists.
#   * HDMI output is source-synchronous through the OSERDES/PHY wrapper.
#   * UART TX is a 115.2 kbaud free-running output; no external clock reference.

derive_clocks
