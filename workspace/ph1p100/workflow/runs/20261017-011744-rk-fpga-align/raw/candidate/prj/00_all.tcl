# =============================================================================
#  00_all.tcl — T07.rk-align-backend：**单会话**全流程（建工程 → syn → phy → bit）
#
#  为什么需要它：TD 的 create_project 才把 device_name/package_name 放进会话变量，
#  launch_runs 用它们生成 run 目录里的 settings.cfg；如果换成「另一个会话 open_project
#  再 launch」，settings.cfg 里的设备/封装是空的，子流程报
#  "can't read device_name"（本 run 实测踩到，见 actual-commands.json）。
#  ⇒ 实际可跑的路径是本文件；01/02/03 分阶段脚本保留作参考与单步复跑预算。
#
#  仍然遵守：不执行 download_sram.tcl、不下载、不写 Flash、不 reset/clean 旧工程。
#  用法（工作目录 = 工程目录，路径用 subst 映射后的 ASCII 盘符）：
#     td_commands_prompt.exe <本脚本的绝对路径>
# =============================================================================

set PRJ_ROOT  "S:/fpga/csi2/pcie_integration"

create_project ph1p_pcie_integration ./ -family PH1 -device PH1P100SBG484 -speed 3 -force

# ---- 顶层与寄存器面 ----
add_files $PRJ_ROOT/rtl/ep_side/img/ep_bar_win.v
add_files $PRJ_ROOT/rtl/ep_side/img/img_regs.v
add_files $PRJ_ROOT/rtl/ep_side/img/img_frame_src.v
# ---- common ----
add_files $PRJ_ROOT/rtl/common/ph1p_pcie_case_param.v
add_files $PRJ_ROOT/rtl/common/ph1p_pcie_rst_sync.v
add_files $PRJ_ROOT/rtl/common/uart/bps_setting.v
add_files $PRJ_ROOT/rtl/common/uart/pcie_uart.v
add_files $PRJ_ROOT/rtl/common/uart/pcie_uprotocol.v
add_files $PRJ_ROOT/rtl/common/uart/uart_cdc.v
add_files $PRJ_ROOT/rtl/common/uart/uart_rx_setting.v
add_files $PRJ_ROOT/rtl/common/uart/uart_tx_setting.v
add_files $PRJ_ROOT/rtl/common/ubus2hxt_apb.v
add_files $PRJ_ROOT/rtl/common/ubus2pcie_apb.v
# ---- 引擎/顶层/桥 ----
add_files $PRJ_ROOT/rtl/ep_side/pcie_ep_engine.v
add_files $PRJ_ROOT/rtl/ep_side/pcie_ep_int_handle.v
add_files $PRJ_ROOT/rtl/ep_side/ph1p_pcie_ep_top.v
add_files $PRJ_ROOT/rtl/ep_side/ubus_bridge/ep_ubus_bridge.v
# ---- 相机 / CSI（peer 原样 + 本包 checked）----
add_files $PRJ_ROOT/rtl/ep_side/cam/clk_activity.v
add_files $PRJ_ROOT/rtl/ep_side/cam/pulse2toggle.v
add_files $PRJ_ROOT/rtl/ep_side/cam/auto_delay_ctl.v
add_files $PRJ_ROOT/rtl/ep_side/cam/csi_rx_10bit_unpack.v
add_files $PRJ_ROOT/rtl/ep_side/cam/csi_rx_byte_align.v
add_files $PRJ_ROOT/rtl/ep_side/cam/csi_rx_clock_det.v
add_files $PRJ_ROOT/rtl/ep_side/cam/csi_rx_hdr_ecc.v
add_files $PRJ_ROOT/rtl/ep_side/cam/csi_rx_packet_handler.v
add_files $PRJ_ROOT/rtl/ep_side/cam/csi_rx_word_align.v
add_files $PRJ_ROOT/rtl/ep_side/cam/csi_rx_word_gear_box.v
add_files $PRJ_ROOT/rtl/ep_side/cam/mipi_csi2_rx_ph1p.v
add_files $PRJ_ROOT/rtl/ep_side/cam/rx_phy_ph1p.v
add_files $PRJ_ROOT/rtl/ep_side/cam/sfifo.v
add_files $PRJ_ROOT/rtl/ep_side/cam/wfifo.v
add_files $PRJ_ROOT/rtl/ep_side/cam/ui_cfg_imx415.v
add_files $PRJ_ROOT/rtl/ep_side/cam/ui_i2c.v
add_files $PRJ_ROOT/rtl/ep_side/cam/ui_imx415_reg.v
add_files $PRJ_ROOT/rtl/checked/csi_rx_packet_integrity.v
add_files $PRJ_ROOT/rtl/checked/csi_rx_10bit_unpack_checked.v
add_files $PRJ_ROOT/rtl/ep_side/cam/mipi_csi2_rx_ph1p_checked.v
# ---- DDR 通路 ----
add_files $PRJ_ROOT/rtl/ep_side/ddr/ddr_frame_pusher.v
add_files $PRJ_ROOT/rtl/ep_side/ddr/ddr_wr_arb.v
add_files $PRJ_ROOT/rtl/ep_side/ddr/cam_ddr_writer.v
# T11：正式 RAW10→R10F 写者
add_files $PRJ_ROOT/rtl/ep_side/ddr/cam_r10f_writer.v
# ---- 约束 ----
add_files $PRJ_ROOT/constraints/ph1p_pcie_case_ep.adc
add_files $PRJ_ROOT/constraints/ph1p_pcie_case_ep.sdc
# ---- 匹配版本 IP ----
add_files $PRJ_ROOT/al_ip/pcie_ep_core/pcie_ep_core.xml
add_files $PRJ_ROOT/al_ip/pcie_pll_ep/pcie_pll_ep.xml
add_files $PRJ_ROOT/al_ip/ram/ram.xml
add_files $PRJ_ROOT/al_ip/ddr3_mc_0/ddr3_mc_0.xml

top_module ph1p_pcie_ep_top

# ---- 综合 ----
launch_runs { syn_1 } -jobs 4
wait_run syn_1 -quiet
# 报告命令要求会话里已 import netlist；失败不要中断流程（报告本体在 run 目录里）
if { [catch { report_area   -file syn_area.rpt }  e] } { puts "report_area(syn) skipped: $e" }
if { [catch { report_timing -file syn_timing.rpt } e] } { puts "report_timing(syn) skipped: $e" }

# ---- 布局布线 + bit ----
launch_runs { phy_1 } -jobs 4
wait_run phy_1 -quiet
if { [catch { report_area   -file phy_area.rpt }  e] } { puts "report_area(phy) skipped: $e" }
if { [catch { report_timing -file phy_timing.rpt } e] } { puts "report_timing(phy) skipped: $e" }
save_best_bits

puts "T07_ALL_DONE"

exit
