# T07.rk-align-backend 仿真编译文件清单（ModelSim / vlog）
#
# 说明：所有路径相对**本文件所在目录**（sim/）。
# run_sim.ps1 会把它展开成绝对路径清单（abs.f）再交给 vlog。
#
# 用法：
#   vlib work
#   vlog +define+MIPI_PHY_SIM_STUB -f compile_checked.f
#
# MIPI_PHY_SIM_STUB：旁路厂商 serdes PHY/位对齐（ModelSim 无原语库），
# 包层输入由 TB 直接注入；见 rtl/ep_side/cam/mipi_csi2_rx_ph1p_checked.v。

# ---- 顶层与 IP 端口桩（仅仿真；不进候选 manifest）----
tb/top_elab_stubs.v

# ---- round2 差分 oracle 参考（只读原源的**重命名副本**；仅测试用，不进综合）----
tb/csi_rx_packet_integrity_ref.v

# ---- 本方 checked 包层（T07 从 internal src 逐字节引入）----
../rtl/checked/csi_rx_packet_integrity.v
../rtl/checked/csi_rx_10bit_unpack_checked.v

# ---- 相机 / CSI ----
../rtl/ep_side/cam/mipi_csi2_rx_ph1p_checked.v
../rtl/ep_side/cam/csi_rx_hdr_ecc.v
../rtl/ep_side/cam/csi_rx_word_align.v
../rtl/ep_side/cam/csi_rx_word_gear_box.v
../rtl/ep_side/cam/csi_rx_byte_align.v
../rtl/ep_side/cam/csi_rx_clock_det.v
../rtl/ep_side/cam/csi_rx_packet_handler.v
../rtl/ep_side/cam/csi_rx_10bit_unpack.v
../rtl/ep_side/cam/rx_phy_ph1p.v
../rtl/ep_side/cam/sfifo.v
../rtl/ep_side/cam/wfifo.v
../rtl/ep_side/cam/pulse2toggle.v
../rtl/ep_side/cam/clk_activity.v
../rtl/ep_side/cam/auto_delay_ctl.v
../rtl/ep_side/cam/ui_i2c.v
../rtl/ep_side/cam/ui_cfg_imx415.v
../rtl/ep_side/cam/ui_imx415_reg.v
../rtl/ep_side/cam/sync_offline/sync_reset.v
../rtl/ep_side/cam/sync_offline/sync_sof_mailbox.v
../rtl/ep_side/cam/sync_offline/sync_sof_pair.v
../rtl/ep_side/cam/sync_offline/sync_start_ctrl.v
../rtl/ep_side/cam/sync_offline/sync_offline_top.v
../rtl/ep_side/cam/sync_frame_gate.v
../rtl/ep_side/cam/sync_i2c_config.v

# ---- DDR / 推帧 / 寄存器面 ----
../rtl/ep_side/ddr/ddr_frame_pusher.v
../rtl/ep_side/ddr/ddr_rd_arb2.v
../rtl/ep_side/ddr/utx_arb2.v
../rtl/ep_side/ddr/cam_ddr_writer.v
# T11: RAW10->R10F writer (crc32_upd4.v is its include, not compiled separately)
../rtl/ep_side/ddr/cam_r10f_writer.v
../rtl/ep_side/ddr/ddr_wr_arb.v
# ---- hardware JPEG codec ----
../rtl/ep_side/codec/cstream_reader.v
../rtl/ep_side/codec/cstream_writer.v
../rtl/ep_side/codec/dct1d8.v
../rtl/ep_side/codec/dct2d8.v
../rtl/ep_side/codec/line2block.v
../rtl/ep_side/codec/jpeg_quant_zz.v
../rtl/ep_side/codec/jpeg_huff_tab.v
../rtl/ep_side/codec/jpeg_huff_enc.v
../rtl/ep_side/codec/jpeg_enc.v
../rtl/ep_side/codec/jpeg_frame.v
../rtl/ep_side/img/ep_bar_win.v
../rtl/ep_side/img/img_frame_src.v

# ---- 引擎 / 顶层 / 桥 ----
../rtl/ep_side/pcie_ep_engine.v
../rtl/ep_side/pcie_ep_int_handle.v
../rtl/ep_side/ph1p_pcie_ep_top.v
../rtl/ep_side/ubus_bridge/ep_ubus_bridge.v

# ---- common ----
../rtl/common/ph1p_pcie_rst_sync.v
../rtl/common/ph1p_pcie_case_param.v
../rtl/common/TLP_FMT_TYPE.v
../rtl/common/BDF.v
../rtl/common/ubus2hxt_apb.v
../rtl/common/ubus2pcie_apb.v
../rtl/common/uart/pcie_uart.v
../rtl/common/uart/bps_setting.v
../rtl/common/uart/pcie_uprotocol.v
../rtl/common/uart/uart_cdc.v
../rtl/common/uart/uart_rx_setting.v
../rtl/common/uart/uart_tx_setting.v
../rtl/ep_side/ddr/ddr_frame_readback_checker.v

# ---- T11.runB-debug-rtl：debug 顶层包装（仅 debug 构建入口 00_all_debug 使用；
#      此处纳入编译仅做语法检查，无 TB 例化；不改任何既有 TB 行为）----
../rtl/ep_side/debug/ph1p_pcie_ep_top_dbg.v

# B01 closedloop production integration
../rtl/ep_side/ddr/closedloop/ddr_closedloop_readback.v
../rtl/ep_side/img/algo/algo_obuf.v
../rtl/ep_side/img/algo/algo_rowwin3.v
../rtl/ep_side/img/algo/algo_rowwin_reader.v
../rtl/ep_side/img/algo/bayer_raw10_demosaic4.v
../rtl/ep_side/img/algo/csi_algo_roi_adapter.v
../rtl/ep_side/img/algo/gray8_gaussian3x3_frame.v
../rtl/ep_side/img/algo/gray8_gaussian3x3_stream.v
../rtl/ep_side/img/algo/gray8_he_cdfmin_frame.v
../rtl/ep_side/img/algo/img_algo_parallel_top.v
../rtl/ep_side/img/algo/rgb8_gray_stream.v
../rtl/ep_side/debug/ph1p_pcie_ep_top_closedloop.v
