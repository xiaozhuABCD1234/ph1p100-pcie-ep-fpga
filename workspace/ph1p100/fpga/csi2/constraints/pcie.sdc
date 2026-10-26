# =============================================================================
#  时钟约束 —— PCIe EP
#  来源：官方 12_pcie_gen2x2\prj\case_ep\constraints\ph1p_pcie_case_ep.sdc
# =============================================================================

create_clock -name {sys_clk} -period 20.000 -waveform {0.000 10.000} [get_ports {sys_clk}]

derive_clocks

# TODO(D3)：把下面的 PLL 实例路径改成你生成的 PLL IP 的实际层次
#   官方路径示例：u_pcie_pll_ep/ph1p_phy_pll_wrapper_Inst/u_PH1P_PHY_PLL.clkc[0]
#   你自己的大概长这样：u_pll/<wrapper>_Inst/u_PH1P_PHY_PLL.clkc[0]
#   生成 PLL 后用 ChipViewer / 综合日志确认层次名
# rename_clock -name {tl_clk_user} [get_clocks {u_pll/PLACEHOLDER_Inst/u_PH1P_PHY_PLL.clkc[0]}]
