create_clock -name {sys_clk} -period 20.000 -waveform {0.000 10.000} [get_ports {sys_clk}]

derive_clocks
rename_clock -name {tl_clk_user} [get_clocks {u_top/u_pcie_pll_ep/ph1p_phy_pll_wrapper_Inst/u_PH1P_PHY_PLL.clkc[0]}]

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

create_generated_clock -name {cam_a_byte_clk} -source [get_ports {mipi_a_clk_hs_p}] -divide_by 4 -phase 0 [get_pins {u_top/u_csi_a/u_rx_phy/u_hs_clk_div.clkdivout}]
create_generated_clock -name {cam_b_byte_clk} -source [get_ports {mipi_b_clk_hs_p}] -divide_by 4 -phase 0 [get_pins {u_top/u_csi_b/u_rx_phy/u_hs_clk_div.clkdivout}]

# 两个相机的 clock lane 来自各自的晶振，与板载 50MHz→PLL 的 tl_clk_user/sys_clk、
# 以及 A/B 两路之间都没有固定相位关系；字节域↔tl_clk_user 的握手在 RTL 里靠 toggle
# 同步器（top 里 s_a_tgl/s_a_vs/... 三级打拍 + clk_activity + pulse2toggle），
# 所以这里按"异步时钟域"如实声明，否则 STA 会拿 5.332ns/16ns 两个无关周期去凑最近沿
# （实测预算只剩 0.004ns），报出与逻辑无关的 −6.8ns 假违规（TD DRC TMST-7700/5089）。
#
# =============================================================================
# DDR3 用户侧时钟（TD 报告里写作 u_ddr3_mc_0/usr_clk，100MHz）——「整帧搬进 DDR3」
# 与【推帧：DDR3 → 主机内存】两条通路的时钟域：
#   来源：al_ip/ddr3_mc_0/src/sdc/ddr3_mc_0.sdc 里
#         rename_clock -name usr_clk [...u_pll1/u_pll_inst.clkc[0]]
#   跨域做法（见 rtl/ep_side/ddr/ddr_frame_writer.v 与 ddr_frame_pusher.v 头部）：
#     · 数据：异步 FIFO（格雷码指针 + 2 级同步器），tl_clk_user ↔ usr_clk 两个方向
#       各一个（写 DDR 一个、从 DDR 读出来推帧一个）；
#     · 请求/基址：单比特电平 2 级同步 + 数据在整个请求期间保持不动；
#     · done/err：usr_clk 域电平 2 级同步回 tl_clk_user；
#     · AXI4 读写通道都在 usr_clk 域，接口时序由 IP 自带 sdc 约束。
#   两端时钟由各自的恢复/复位决定，没有固定相位关系，所以与相机段一样按
#   "异步时钟域"如实声明（否则 STA 会去凑 16ns/10ns 的最近沿，报假违规）。
#   通配写法：*usr_clk 既能匹配裸名 usr_clk，也能匹配 TD 报告里的
#   u_ddr3_mc_0/usr_clk（TD 的 get_clocks 支持通配，参考 TD 自带
#   ip/depot/QSGMII_over_SERDES_1.1/.../plugin_end.tcl 的 */inst/... 用法）。
# =============================================================================
set_clock_groups -asynchronous \
    -group [get_clocks {tl_clk_user sys_clk}] \
    -group [get_clocks {cam_a_clk_lane cam_a_byte_clk}] \
    -group [get_clocks {cam_b_clk_lane cam_b_byte_clk}] \
    -group [get_clocks {*usr_clk}]
