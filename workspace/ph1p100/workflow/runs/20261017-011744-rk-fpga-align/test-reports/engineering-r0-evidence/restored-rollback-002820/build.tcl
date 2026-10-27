if {[catch {
import_device ph1_100p.db -package PH1P100SBG484 -speed 3
create_project camera_ddr_display ./ -family ph1 -device PH1P100SBG484 -speed -3
add_files ./capture_async_fifo.v
add_files ./gray_frame_pack_guarded.v
add_files ./camera_ddr_display_guarded.v
add_files ./ddr_capture_check.v
add_files ./ddr_frame_store.v
add_files ./ddrmc_display_top.v
add_files ./cam_preview_capture.v
add_files ./f9p_camera_display_core.v
add_files ./camera_ddr_display_top.v
add_files ./camera/uisrc/03_ip/mipi_phy_ph1p/rx_phy_ph1p.v
add_files ./camera/uisrc/03_ip/mipi_csi_2/csi_rx_hdr_ecc.v
add_files ./camera/uisrc/03_ip/mipi_csi_2/csi_rx_byte_align.v
add_files ./camera/uisrc/03_ip/mipi_csi_2/csi_rx_clock_det.v
add_files ./camera/uisrc/03_ip/mipi_csi_2/auto_delay_ctl.v
add_files ./camera/uisrc/03_ip/mipi_csi_2/csi_rx_word_align.v
add_files ./camera/uisrc/03_ip/mipi_csi_2/csi_rx_word_gear_box.v
add_files ./camera/uisrc/03_ip/mipi_csi_2/csi_rx_packet_integrity.v
add_files ./camera/uisrc/03_ip/mipi_csi_2/csi_rx_10bit_unpack_checked.v
add_files ./camera/uisrc/03_ip/mipi_csi_2/sfifo.v
add_files ./camera/uisrc/03_ip/mipi_csi_2/wfifo.v
add_files ./camera/uisrc/03_ip/mipi_csi_2/mipi_csi2_rx_ph1p.v
add_files ./camera/uisrc/03_ip/ui_imx415_cfg/ui_i2c.v
add_files ./camera/uisrc/03_ip/ui_imx415_cfg/ui_imx415_reg.v
add_files ./camera/uisrc/03_ip/ui_imx415_cfg/ui_cfg_imx415.v
add_files ./camera/uisrc/01_rtl/uart_tx.v
add_files ./camera/uisrc/01_rtl/pulse2toggle.v
add_files ./camera/uisrc/01_rtl/clk_activity.v
add_files ./camera/uisrc/01_rtl/dbg_uart.v
add_files ./camera/uisrc/03_ip/vtc/uivtc.v
add_files ./camera/uisrc/03_ip/tpg/uitpg.v
add_files ./camera/uisrc/03_ip/alip/ui_HDMI_TX/ui_HDMI_TX.v
add_files ./camera/uisrc/03_ip/alip/ui_HDMI_TX/hdmi_phy_warpper.v
add_files ./camera/uisrc/03_ip/alip/ui_HDMI_TX/lane_lvds_10_1.v
add_files ./camera/uisrc/03_ip/alip/ui_HDMI_TX/hdmi_tx_controller_wrapper.enc.v
add_files ./camera/uisrc/01_rtl/raw10_display60_clocks.v
add_files ./camera/uisrc/01_rtl/camera_startup.v
add_files ./camera/uisrc/03_ip/raw10_clocks/raw10_clocks.xml
add_files ./camera/uisrc/03_ip/ui_pll/ui_pll.xml
add_files ./vendor/rtl/usr_mcu_srcs/usr_mcu_apb_decoder.v
add_files ./vendor/rtl/usr_mcu_srcs/usr_mcu_apb_gpio.v
add_files ./vendor/rtl/usr_mcu_srcs/usr_mcu_apb_uart.v
add_files ./vendor/rtl/usr_mcu_srcs/usr_mcu_core/usr_mcu_core.v
add_files ./vendor/rtl/usr_mcu_srcs/usr_mcu_core/usr_mcu_core_alu.v
add_files ./vendor/rtl/usr_mcu_srcs/usr_mcu_core/usr_mcu_core_csr.v
add_files ./vendor/rtl/usr_mcu_srcs/usr_mcu_core/usr_mcu_core_decoder.v
add_files ./vendor/rtl/usr_mcu_srcs/usr_mcu_core/usr_mcu_core_mem2apb.v
add_files ./vendor/rtl/usr_mcu_srcs/usr_mcu_core/usr_mcu_core_reg2mem.v
add_files ./vendor/rtl/usr_mcu_srcs/usr_mcu_core/usr_mcu_core_regfile_dram.v
add_files ./vendor/rtl/usr_mcu_srcs/usr_mcu_core/usr_mcu_core_tcm.v
add_files ./vendor/rtl/usr_mcu_srcs/usr_mcu_wrapper.v
add_files ./vendor/ip/ddrmc_x32/ddrmc_x32.xml
add_files ./board.adc
add_files ./timing.sdc
add_files ./ddr_display_read.v
add_files ./gray_display_pixels.v
top_module camera_ddr_display_top
set_strategy -run phy_1 TimingHigh
launch_runs syn_1
wait_run syn_1 -quiet
launch_runs -step route phy_1
wait_run phy_1 -quiet
import_db ./camera_ddr_display_Runs/phy_1/camera_ddr_display_pr.db
update_timing -mode final
report_timing_summary -file ./capture_timing.rpt
report_timing_ignored -file ./capture_ignored.rpt -ep_num 50
report_abnormal_timing_target -file ./capture_abnormal.rpt
report_path_skew -file ./capture_skew.rpt -ep_num 20
report_area -file ./capture.area
close_project
puts "CAPTURE_ROUTE_RETURNED_CHECK_REPORTS"
} msg]} {puts stderr "CAPTURE_BUILD_ERROR: $msg";exit 1}
exit 0
