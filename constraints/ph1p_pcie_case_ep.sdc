create_clock -name {sys_clk} -period 20.000 -waveform {0.000 10.000} [get_ports {sys_clk}]

derive_clocks
rename_clock -name {tl_clk_user} [get_clocks {u_pcie_pll_ep/ph1p_phy_pll_wrapper_Inst/u_PH1P_PHY_PLL.clkc[0]}]
