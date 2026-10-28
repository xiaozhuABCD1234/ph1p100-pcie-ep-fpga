# 标准 TD 工程重建脚本（工程根 = 本目录，源码/约束/IP 都在仓库内部）
#   用法（TD Release 2026.2，Windows）：
#     cd <本仓库检出根>
#     "%TD_BIN%/td_commands_prompt.exe" create_project.tcl
#   （Linux 包另可用 /opt/anlogic/TD_Release_2026.2_NL/bin/td.sh create_project.tcl </dev/null）
#   说明：只建工程 + 加源 + 综合/布线/出 bit；不下载、不写 Flash、不 reset/clean 旧工程。
create_project ph1p_pcie_ep_top ./ -family PH1 -device PH1P100SBG484 -speed 3 -force


# ---- FPGA 预处理：ROI 适配 + 三路并行算法 + 算法流→writer 时序转换 ----
add_files rtl/ep_side/img/algo/algo_rowwin_reader.v
add_files rtl/ep_side/img/algo/algo_rowwin3.v
add_files rtl/ep_side/img/algo/bayer_raw10_demosaic4.v
add_files rtl/ep_side/img/algo/rgb8_gray_stream.v
add_files rtl/ep_side/img/algo/gray8_gaussian3x3_stream.v
add_files rtl/ep_side/img/algo/gray8_he_cdfmin_frame.v
add_files rtl/ep_side/img/algo/algo_obuf.v
add_files rtl/ep_side/img/algo/img_algo_parallel_top.v
add_files rtl/ep_side/img/algo/csi_algo_roi_adapter.v
add_files rtl/ep_side/img/algo/algo_y8_to_legacy.v
add_files rtl/ep_side/img/ep_bar_win.v
add_files rtl/ep_side/img/img_regs.v
add_files rtl/ep_side/img/img_frame_src.v
add_files rtl/common/ph1p_pcie_case_param.v
add_files rtl/common/ph1p_pcie_rst_sync.v
add_files rtl/common/uart/bps_setting.v
add_files rtl/common/uart/pcie_uart.v
add_files rtl/common/uart/pcie_uprotocol.v
add_files rtl/common/uart/uart_cdc.v
add_files rtl/common/uart/uart_rx_setting.v
add_files rtl/common/uart/uart_tx_setting.v
add_files rtl/common/ubus2hxt_apb.v
add_files rtl/common/ubus2pcie_apb.v
add_files rtl/ep_side/pcie_ep_engine.v
add_files rtl/ep_side/pcie_ep_int_handle.v
add_files rtl/ep_side/ph1p_pcie_ep_top.v
add_files rtl/ep_side/ubus_bridge/ep_ubus_bridge.v
add_files rtl/ep_side/cam/clk_activity.v
add_files rtl/ep_side/cam/pulse2toggle.v
add_files rtl/ep_side/cam/auto_delay_ctl.v
add_files rtl/ep_side/cam/csi_rx_10bit_unpack.v
add_files rtl/ep_side/cam/csi_rx_byte_align.v
add_files rtl/ep_side/cam/csi_rx_clock_det.v
add_files rtl/ep_side/cam/csi_rx_hdr_ecc.v
add_files rtl/ep_side/cam/csi_rx_packet_handler.v
add_files rtl/ep_side/cam/csi_rx_word_align.v
add_files rtl/ep_side/cam/csi_rx_word_gear_box.v
add_files rtl/ep_side/cam/mipi_csi2_rx_ph1p.v
add_files rtl/ep_side/cam/rx_phy_ph1p.v
add_files rtl/ep_side/cam/sfifo.v
add_files rtl/ep_side/cam/wfifo.v
add_files rtl/ep_side/cam/ui_cfg_imx415.v
add_files rtl/ep_side/cam/ui_i2c.v
add_files rtl/ep_side/cam/ui_imx415_reg.v
# ---- 硬件同步曝光（A 主/B 从，共享 XHS/XVS）----
add_files rtl/ep_side/cam/sync_offline/sync_reset.v
add_files rtl/ep_side/cam/sync_offline/sync_sof_mailbox.v
add_files rtl/ep_side/cam/sync_offline/sync_sof_pair.v
add_files rtl/ep_side/cam/sync_offline/sync_start_ctrl.v
add_files rtl/ep_side/cam/sync_offline/sync_offline_top.v
add_files rtl/ep_side/cam/sync_frame_gate.v
add_files rtl/ep_side/cam/sync_i2c_config.v
# ---- raw10-rka1 迁入：checked 包层（T11 冻结版）+ checked PHY wrapper ----
add_files rtl/checked/csi_rx_packet_integrity.v
add_files rtl/checked/csi_rx_10bit_unpack_checked.v
add_files rtl/ep_side/cam/mipi_csi2_rx_ph1p_checked.v
# ---- DDR 通路 ----
add_files rtl/ep_side/ddr/ddr_frame_pusher.v
add_files rtl/ep_side/ddr/ddr_rd_arb2.v
add_files rtl/ep_side/ddr/utx_arb2.v
add_files rtl/ep_side/ddr/ddr_wr_arb.v
# 相机整帧（4K）直写 DDR3：CSI-2 -> 异步 FIFO -> AXI -> DDR3（旧写者，诊断/备用）
add_files rtl/ep_side/ddr/cam_ddr_writer.v
# T11: RAW10 -> R10F 写者（crc32_upd4.v 为其 include；crc16_upd4.v 为 checked 包层 include，不单独编译）
add_files rtl/ep_side/ddr/cam_r10f_writer.v
add_files constraints/ph1p_pcie_case_ep.adc
add_files constraints/ph1p_pcie_case_ep.sdc
add_files al_ip/pcie_ep_core/pcie_ep_core.xml
add_files al_ip/pcie_pll_ep/pcie_pll_ep.xml
add_files al_ip/ram/ram.xml
add_files al_ip/ddr3_mc_0/ddr3_mc_0.xml

top_module ph1p_pcie_ep_top

reset_runs { syn_1 }
launch_runs { syn_1 phy_1 } -jobs 4
wait_run syn_1 -quiet
wait_run phy_1 -quiet
save_best_bits

puts "==== CREATE+BUILD DONE (no download, no flash) ===="
