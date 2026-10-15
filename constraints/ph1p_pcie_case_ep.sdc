create_clock -name {sys_clk} -period 20.000 -waveform {0.000 10.000} [get_ports {sys_clk}]

derive_clocks
rename_clock -name {tl_clk_user} [get_clocks {u_pcie_pll_ep/ph1p_phy_pll_wrapper_Inst/u_PH1P_PHY_PLL.clkc[0]}]

# =============================================================================
# MIPI CSI-2 软 PHY 字节时钟（IMX415 A/B 两路；此前完全没约束，收包核心不进 STA）
#
#   来源：相机 clock lane（差分输入脚 mipi_*_clk_hs_p/n）
#         → PH1P_LOGIC_IBUF_DIFF → PH1P_PHY_LCLK(DIV="4")
#         → PH1P_LOGIC_BUFG → 字节时钟 w_a_byte_clk / w_b_byte_clk
#   频率：1.5 Gbps/lane 的 MIPI 数据 → clock lane = 1.5Gbps/2 = 750MHz
#         → 字节时钟 = 750MHz/4 = 187.5MHz = 1.5Gbps/8
#         （与板测遥测 CKA=CKB=0xB2D 一致，见 doc/task3/实现方案_20261015.md）
#   注：÷4 已实现在 PH1P_PHY_LCLK 原语内（DIV="4"），故字节时钟 = clock lane ÷ 4；
#       写法照 TD 自带 MIPI_DPHY IP 模板 plugin_end.tcl 的 create_generated_clock。
# =============================================================================
create_clock -name {cam_a_clk_lane} -period 1.333 -waveform {0.000 0.667} [get_ports {mipi_a_clk_hs_p}]
create_clock -name {cam_b_clk_lane} -period 1.333 -waveform {0.000 0.667} [get_ports {mipi_b_clk_hs_p}]

create_generated_clock -name {cam_a_byte_clk} -source [get_ports {mipi_a_clk_hs_p}] -divide_by 4 -phase 0 [get_pins {u_csi_a/u_rx_phy/u_hs_clk_div.clkdivout}]
create_generated_clock -name {cam_b_byte_clk} -source [get_ports {mipi_b_clk_hs_p}] -divide_by 4 -phase 0 [get_pins {u_csi_b/u_rx_phy/u_hs_clk_div.clkdivout}]

# 两个相机的 clock lane 来自各自的晶振，与板载 50MHz→PLL 的 tl_clk_user/sys_clk、
# 以及 A/B 两路之间都没有固定相位关系；字节域↔tl_clk_user 的握手在 RTL 里靠 toggle
# 同步器（top 里 s_a_tgl/s_a_vs/... 三级打拍 + clk_activity + pulse2toggle），
# 所以这里按"异步时钟域"如实声明，否则 STA 会拿 5.332ns/16ns 两个无关周期去凑最近沿
# （实测预算只剩 0.004ns），报出与逻辑无关的 −6.8ns 假违规（TD DRC TMST-7700/5089）。
set_clock_groups -asynchronous \
    -group [get_clocks {tl_clk_user sys_clk}] \
    -group [get_clocks {cam_a_clk_lane cam_a_byte_clk}] \
    -group [get_clocks {cam_b_clk_lane cam_b_byte_clk}]
