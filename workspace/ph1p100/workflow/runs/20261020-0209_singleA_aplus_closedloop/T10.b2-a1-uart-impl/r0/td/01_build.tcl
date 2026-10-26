# =============================================================================
# T10.b2-a1-uart-impl r0 -- session 1: synthesis + first route attempt.
# P1 RTL (r3 hashes, verified) + P2 board top/constraints/bridge/PLL.
# Strategy: syn retiming on + route post_route_opt ultra (same frozen group as
# T10.a1-pipe-split). No seed sweep, no clock change, no multicycle relax.
# Stop marker is set before bitgen; bitgen is a separate, single attempt.
# T: = this package r0/td ; Y: = project root (tools/td/td_env.ps1).
# =============================================================================
set PRJ_ROOT "Y:/upstream/ph1p100-pcie-ep-fpga"
set prj "a1_board"
create_project $prj ./ -family PH1 -device PH1P100SBG484 -speed 3 -force

# ---- frozen P1 A1 chain (hashes bound in the manifest) ---------------------
add_files Y:/fpga/csi2/src/a1/a1_raw_crop.v
add_files Y:/fpga/csi2/src/a1/a1_ddr_slot_store.v
add_files Y:/fpga/csi2/src/a1/a1_ddr_arb2.v
add_files Y:/fpga/csi2/src/a1/a1_uart_export.v
add_files Y:/fpga/csi2/src/a1/camera_a1_uart_top.v
add_files Y:/fpga/csi2/src/mem/capture_async_fifo.v
add_files $PRJ_ROOT/rtl/ep_side/codec/a1_frame_top.v
add_files $PRJ_ROOT/rtl/ep_side/codec/a1_deflate_core.v

# ---- P2 wrapper / bridge / PLL --------------------------------------------
add_files ./src/p2_a1_board_top.v
add_files ./src/p2_ddrmc_shell.v
add_files ./src/p2_ddr_bridge.v
add_files ./src/p2_a1_pll.v

# ---- camera front end (copied board-verified tree) ------------------------
add_files ./src/f9p_camera_display_core.v
add_files ./src/cam_preview_capture.v
add_files ./src/camera/uisrc/03_ip/mipi_phy_ph1p/rx_phy_ph1p.v
add_files ./src/camera/uisrc/03_ip/mipi_csi_2/csi_rx_hdr_ecc.v
add_files ./src/camera/uisrc/03_ip/mipi_csi_2/csi_rx_byte_align.v
add_files ./src/camera/uisrc/03_ip/mipi_csi_2/csi_rx_clock_det.v
add_files ./src/camera/uisrc/03_ip/mipi_csi_2/auto_delay_ctl.v
add_files ./src/camera/uisrc/03_ip/mipi_csi_2/csi_rx_word_align.v
add_files ./src/camera/uisrc/03_ip/mipi_csi_2/csi_rx_word_gear_box.v
add_files ./src/camera/uisrc/03_ip/mipi_csi_2/csi_rx_packet_integrity.v
add_files ./src/camera/uisrc/03_ip/mipi_csi_2/csi_rx_10bit_unpack_checked.v
add_files ./src/camera/uisrc/03_ip/mipi_csi_2/sfifo.v
add_files ./src/camera/uisrc/03_ip/mipi_csi_2/wfifo.v
add_files ./src/camera/uisrc/03_ip/mipi_csi_2/mipi_csi2_rx_ph1p.v
add_files ./src/camera/uisrc/03_ip/ui_imx415_cfg/ui_i2c.v
add_files ./src/camera/uisrc/03_ip/ui_imx415_cfg/ui_imx415_reg.v
add_files ./src/camera/uisrc/03_ip/ui_imx415_cfg/ui_cfg_imx415.v
add_files ./src/camera/uisrc/01_rtl/uart_tx.v
add_files ./src/camera/uisrc/01_rtl/pulse2toggle.v
add_files ./src/camera/uisrc/01_rtl/clk_activity.v
add_files ./src/camera/uisrc/01_rtl/dbg_uart.v
add_files ./src/camera/uisrc/03_ip/vtc/uivtc.v
add_files ./src/camera/uisrc/03_ip/tpg/uitpg.v
add_files ./src/camera/uisrc/03_ip/alip/ui_HDMI_TX/ui_HDMI_TX.v
add_files ./src/camera/uisrc/03_ip/alip/ui_HDMI_TX/hdmi_phy_warpper.v
add_files ./src/camera/uisrc/03_ip/alip/ui_HDMI_TX/lane_lvds_10_1.v
add_files ./src/camera/uisrc/03_ip/alip/ui_HDMI_TX/hdmi_tx_controller_wrapper.enc.v
add_files ./src/camera/uisrc/01_rtl/raw10_display60_clocks.v
add_files ./src/camera/uisrc/01_rtl/camera_startup.v
add_files ./src/camera/uisrc/03_ip/raw10_clocks/raw10_clocks.xml
add_files ./src/camera/uisrc/03_ip/ui_pll/ui_pll.xml

# ---- board MCU / DDR IP ---------------------------------------------------
add_files ./src/vendor/rtl/usr_mcu_srcs/usr_mcu_apb_decoder.v
add_files ./src/vendor/rtl/usr_mcu_srcs/usr_mcu_apb_gpio.v
add_files ./src/vendor/rtl/usr_mcu_srcs/usr_mcu_apb_uart.v
add_files ./src/vendor/rtl/usr_mcu_srcs/usr_mcu_core/usr_mcu_core.v
add_files ./src/vendor/rtl/usr_mcu_srcs/usr_mcu_core/usr_mcu_core_alu.v
add_files ./src/vendor/rtl/usr_mcu_srcs/usr_mcu_core/usr_mcu_core_csr.v
add_files ./src/vendor/rtl/usr_mcu_srcs/usr_mcu_core/usr_mcu_core_decoder.v
add_files ./src/vendor/rtl/usr_mcu_srcs/usr_mcu_core/usr_mcu_core_mem2apb.v
add_files ./src/vendor/rtl/usr_mcu_srcs/usr_mcu_core/usr_mcu_core_reg2mem.v
add_files ./src/vendor/rtl/usr_mcu_srcs/usr_mcu_core/usr_mcu_core_regfile_dram.v
add_files ./src/vendor/rtl/usr_mcu_srcs/usr_mcu_core/usr_mcu_core_tcm.v
add_files ./src/vendor/rtl/usr_mcu_srcs/usr_mcu_wrapper.v
add_files ./src/vendor/ip/ddrmc_x32/ddrmc_x32.xml

# ---- board pins / timing --------------------------------------------------
add_files ./board_p2.adc
add_files ./p2_board.sdc
top_module p2_a1_board_top

# ---- frozen strategy: retiming on, ultra post-route opt -------------------
if {[catch { set_param -run syn_1 rtl retiming on } e]} {
  puts "P2_SYN_PARAM_ERR $e"
  if {[catch { set_param rtl retiming on } e2]} { puts "P2_SYN_PARAM_FALLBACK_ERR $e2" } else { puts "P2_SYN_PARAM_FALLBACK_OK rtl retiming on" }
} else { puts "P2_SYN_PARAM_OK rtl retiming on" }
foreach {p v} {post_route_opt ultra postrt_opt_loc 20 postrt_opt_extra_round 4} {
  if {[catch { set_param -run phy_1 route $p $v } e]} { puts "P2_ROUTE_PARAM_ERR $p=$v : $e" } else { puts "P2_ROUTE_PARAM_OK $p=$v" }
}

# ---- synthesis -------------------------------------------------------------
launch_runs { syn_1 } -jobs 4
if {[catch { wait_run syn_1 -quiet } e]} { puts "SYN_WAIT_ERR $e" }
set tf "./${prj}_Runs/syn_1/${prj}_gate.timing"
set af "./${prj}_Runs/syn_1/${prj}_gate.area"
if {[file exists $tf]} { file copy -force $tf ./syn_gate_timing.rpt }
if {[file exists $af]} { file copy -force $af ./syn_gate_area.rpt }

set syn_wns -99.0; set syn_tns -99.0; set syn_slice -1; set syn_eram -1
set syn_reg -1
if {[file exists $tf]} {
  set fh [open $tf r]; set txt [read $fh]; close $fh
  if {[regexp {SWNS:\s*(-?[0-9.]+)ns} $txt -> w]} { set syn_wns $w }
  if {[regexp {STNS:\s*(-?[0-9.]+)ns} $txt -> w]} { set syn_tns $w }
}
if {[file exists $af]} {
  set fh [open $af r]; set atxt [read $fh]; close $fh
  if {[regexp {#slice\*\s+([0-9]+)} $atxt -> sl]} { set syn_slice $sl }
  if {[regexp {#eram\s+([0-9]+)} $atxt -> er]} { set syn_eram $er }
  if {[regexp {#reg\s+([0-9]+)} $atxt -> rg]} { set syn_reg $rg }
}
puts "P2_SYN_SWNS=$syn_wns P2_SYN_STNS=$syn_tns P2_SYN_SLICE=$syn_slice P2_SYN_ERAM=$syn_eram P2_SYN_REG=$syn_reg"

# ---- physical: route step (no bitgen inside the run) ----------------------
if {[file exists ./${prj}_Runs/phy_1/.stop.f]} { file delete -force ./${prj}_Runs/phy_1/.stop.f }
if {[catch { launch_runs { phy_1 } -jobs 4 } e]} { puts "PHY_LAUNCH_ERR $e" }

set waited 0
while { (![file exists ./${prj}_Runs/phy_1/.opt_route.begin.f]) && ($waited < 3000) } {
  after 2000
  incr waited 2
  if {$waited % 120 == 0} { puts "P2_WAIT_OPT_ROUTE ${waited}s" }
}
if {[file exists ./${prj}_Runs/phy_1/.opt_route.begin.f]} {
  set fh [open ./${prj}_Runs/phy_1/.stop.f w]
  puts $fh "stop before bitgen (T10.b2-a1-uart-impl r0)"
  close $fh
  puts "P2_PHY_STOP_MARKER_SET waited=${waited}s"
} else {
  puts "P2_PHY_ROUTE_NOT_STARTED waited=${waited}s"
}
if {[catch { wait_run phy_1 -quiet } e]} { puts "PHY_WAIT_ERR $e" }

set prdb "./${prj}_Runs/phy_1/${prj}_pr.db"
if {[file exists $prdb]} {
  if {[catch { import_db $prdb } e]} { puts "IMPORT_DB_ERR $e" }
  if {[catch { update_timing -mode final } e]} { puts "UPDATE_TIMING_ERR $e" }
  if {[catch { report_timing_summary -file ./routed_timing_summary.rpt } e]} { puts "RPT_TS_ERR $e" } else { puts "TIMING_SUMMARY_EXECUTED" }
  if {[catch { report_timing_status -file ./routed_timing_status.rpt } e]} { puts "RPT_TST_ERR $e" } else { puts "TIMING_STATUS_EXECUTED" }
  if {[catch { report_area -io_info -file ./routed_area.rpt } e]} { puts "RPT_AREA_ERR $e" } else { puts "AREA_EXECUTED" }
  if {[catch { report_timing -file ./routed_timing.rpt } e]} { puts "RPT_TIMING_ERR $e" } else { puts "TIMING_EXECUTED" }
  if {[catch { report_qor -step route -file ./routed_qor.rpt } e]} { puts "RPT_QOR_ERR $e" } else { puts "QOR_EXECUTED" }
  if {[catch { check_timing -verbose -file ./routed_check_timing.rpt } e]} { puts "RPT_CHK_ERR $e" } else { puts "CHECK_TIMING_EXECUTED" }
  if {[catch { report_clock_utilization -file ./routed_clock_utilization.rpt } e]} { puts "RPT_CLK_ERR $e" } else { puts "CLOCK_UTIL_EXECUTED" }
  if {[catch { report_cdc -file ./cdc_not_available.rpt } e]} { puts "RPT_CDC_UNAVAILABLE $e" } else { puts "CDC_EXECUTED_UNEXPECTED" }
  if {[catch { report_param -file ./params_after.tcl } e]} { puts "RPT_PARAM_AFTER_ERR $e" } else { puts "PARAM_AFTER_EXECUTED" }
  if {[catch { write_verilog ./routed_netlist.v } e]} { puts "WV_ROUTED_ERR $e" } else { puts "WV_ROUTED_OK" }

  set pwns -99.0; set ptns -99.0; set hwns -99.0; set htns -99.0
  set pvf -1; set ptot -1
  set ptf "./${prj}_Runs/phy_1/${prj}_pr.timing"
  if {[file exists $ptf]} {
    file copy -force $ptf ./phy_pr_timing_flow.rpt
    set fh [open $ptf r]; set ptxt [read $fh]; close $fh
    if {[regexp {SWNS:\s*(-?[0-9.]+)ns} $ptxt -> w]} { set pwns $w }
    if {[regexp {STNS:\s*(-?[0-9.]+)ns} $ptxt -> w]} { set ptns $w }
    if {[regexp {HWNS:\s*(-?[0-9.]+)ns} $ptxt -> w]} { set hwns $w }
    if {[regexp {HTNS:\s*(-?[0-9.]+)ns} $ptxt -> w]} { set htns $w }
    if {[regexp {SWNS\s+(-?[0-9.]+)ns,\s+STNS\s+(-?[0-9.]+)ns,\s+([0-9]+) Viol Endpoints,\s+([0-9]+) Total Endpoints} $ptxt -> _a _b vf tot]} { set pvf $vf; set ptot $tot }
  } else { puts "PR_TIMING_MISSING" }
  puts "P2_ROUTED_SWNS=$pwns P2_ROUTED_STNS=$ptns P2_ROUTED_HWNS=$hwns P2_ROUTED_HTNS=$htns P2_ROUTED_VIOL_EP=$pvf P2_ROUTED_TOTAL_EP=$ptot"

  if {[file exists ./${prj}_Runs/phy_1/route_flow.status]} { file copy -force ./${prj}_Runs/phy_1/route_flow.status ./route_flow.status }
  if {[file exists ./${prj}_Runs/phy_1/place_flow.status]} { file copy -force ./${prj}_Runs/phy_1/place_flow.status ./place_flow.status }
  if {[file exists ./${prj}_Runs/phy_1/${prj}_phy.area]} { file copy -force ./${prj}_Runs/phy_1/${prj}_phy.area ./phy_area_run.rpt }
  if {[file exists ./${prj}_Runs/phy_1/${prj}_pr.bit]} { puts "BIT_PRESENT_UNEXPECTED" } else { puts "NO_BIT_FILE" }
} else {
  puts "PHY_NO_PR_DB"
}
puts "P2_BUILD_DONE"
exit
