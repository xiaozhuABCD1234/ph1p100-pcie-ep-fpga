# 标准 TD 工程重建脚本（工程根 = 本目录，源码/约束/IP 都在工程内部）
#   用法:  cd <工程根> && /opt/anlogic/TD_Release_2026.2_NL/bin/td.sh create_project.tcl </dev/null
create_project ph1p_pcie_ep_top ./ -family PH1 -device PH1P100SBG484 -speed 3 -force

add_files rtl/ep_side/img/ep_bar_win.v
add_files rtl/ep_side/img/img_regs.v
add_files rtl/ep_side/img/img_frame_src.v
add_files rtl/ep_side/img/cam_fb_writer.v
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
add_files rtl/ep_side/ddr/ddr_frame_writer.v
add_files rtl/ep_side/ddr/ddr_frame_pusher.v
# 相机整帧（4K）直通 DDR3：CSI-2 → 异步 FIFO → AXI 写 DDR3，不过片内 fb[]
add_files rtl/ep_side/ddr/cam_ddr_writer.v
# 两条整帧写 DDR3 通路共用一个 AXI 写口，只在两边都空闲时换手
add_files rtl/ep_side/ddr/ddr_wr_mux.v
add_files constraints/ph1p_pcie_case_ep.adc
add_files constraints/ph1p_pcie_case_ep.sdc
add_files al_ip/pcie_ep_core/pcie_ep_core.xml
add_files al_ip/pcie_pll_ep/pcie_pll_ep.xml
add_files al_ip/ram/ram.xml
# 板载 DDR3L 控制器（IP 自带 src/adc、src/sdc，注册 xml 后由 TD 带进
# IpADCList / IpSDCList，与 al_ip/pcie_ep_core 同一种注册方式）
add_files al_ip/ddr3_mc_0/ddr3_mc_0.xml

top_module ph1p_pcie_ep_top

reset_runs { syn_1 }
launch_runs { syn_1 phy_1 } -jobs 4
wait_run syn_1 -quiet
wait_run phy_1 -quiet
save_best_bits

