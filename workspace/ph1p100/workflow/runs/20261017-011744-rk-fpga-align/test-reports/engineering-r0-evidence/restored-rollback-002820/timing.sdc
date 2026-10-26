# RAW10 all-pixel 4K30: 891 Mbps/lane DDR, clock lane 445.5 MHz.

create_clock -name {sys_clk50m} -period 20.000 -waveform {0.000 10.000} [get_ports {sys_clk50m}]

create_clock -name {mipi_a_clk_hs} -period 2.244669 -waveform {0.000000 1.1223345} [get_ports {mipi_a_clk_hs_p}]

create_clock -name {mipi_b_clk_hs} -period 2.244669 -waveform {0.000000 1.1223345} [get_ports {mipi_b_clk_hs_p}]

create_generated_clock -name {mipi_a_byte_clk} -source [get_ports {mipi_a_clk_hs_p}] -divide_by 4 [get_pins {u_camera/u_csi_a/u_rx_phy/u_hs_clk_div.clkdivout}]


rename_clock -name {pclkx1} [get_clocks {u_camera/X_ui_pll/ph1p_phy_pll_wrapper_Inst/u_PH1P_PHY_PLL.clkc[0]}]

rename_clock -name {pclkx5} [get_clocks {u_camera/X_ui_pll/ph1p_phy_pll_wrapper_Inst/u_PH1P_PHY_PLL.clkc[1]}]

rename_clock -name {mclk27} [get_clocks {u_camera/X_ui_pll/ph1p_phy_pll_wrapper_Inst/u_PH1P_PHY_PLL.clkc[2]}]

# I2C state/data logic uses sys_clk50m enables; no fabric clock domain.
# HDMI clocks remain related. CSI domains are independent external clocks.

rename_clock -name {ddr_user} [get_clocks {u_ddrmc_test_top/u_ddrmc_x32/usr_clk}]
set_clock_groups -asynchronous -group {sys_clk50m pclkx1 pclkx5 mclk27} -group {ddr_user} -group {mipi_a_clk_hs mipi_a_byte_clk} -group {mipi_b_clk_hs}

# Registered monotonic enable -> first falling-edge MCLK synchronizer only.

# The second stage and output gate remain timed. No pixel/serial data exception.

set_false_path -from [get_clocks {sys_clk50m}] -through [get_nets {u_camera/u_camera_startup/enable_request}] -to [get_clocks {mclk27}]

derive_clocks

# SWUG105 PDF81-82: bus skew remains active despite asynchronous clock groups.
set_path_skew -from [get_regs {u_ddrmc_test_top/u_capture/u_fifo/wgray[*]}] -to [get_regs {u_ddrmc_test_top/u_capture/u_fifo/rq1_wgray[*]}] 4.000
set_path_skew -from [get_regs {u_ddrmc_test_top/u_capture/u_fifo/rgray[*]}] -to [get_regs {u_ddrmc_test_top/u_capture/u_fifo/wq1_rgray[*]}] 4.000

# Display FIFO crosses independent DDR and fractional pixel PLL domains.
set_path_skew -from [get_regs {u_ddrmc_test_top/u_capture/u_display_fifo/wgray[*]}] -to [get_regs {u_ddrmc_test_top/u_capture/u_display_fifo/rq1_wgray[*]}] 4.000
set_path_skew -from [get_regs {u_ddrmc_test_top/u_capture/u_display_fifo/rgray[*]}] -to [get_regs {u_ddrmc_test_top/u_capture/u_display_fifo/wq1_rgray[*]}] 4.000
