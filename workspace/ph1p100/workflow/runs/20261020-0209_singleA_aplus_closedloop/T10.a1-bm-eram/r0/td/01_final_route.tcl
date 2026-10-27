set PRJ_ROOT "Y:/upstream/ph1p100-pcie-ep-fpga"
create_project a1_bm_r0f ./ -family PH1 -device PH1P100SBG484 -speed 3 -force
add_files $PRJ_ROOT/rtl/ep_side/codec/a1_frame_top.v
add_files $PRJ_ROOT/rtl/ep_side/codec/a1_deflate_core.v
add_files ./a1_eng_top.v
add_files ./a1_small_top.sdc
top_module a1_eng_top
launch_runs { syn_1 } -jobs 4
wait_run syn_1 -quiet
set tf "./a1_bm_r0f_Runs/syn_1/a1_bm_r0f_gate.timing"
set af "./a1_bm_r0f_Runs/syn_1/a1_bm_r0f_gate.area"
set tag "s2"; if {[info exists ::env(A1_TD_TAG)]} { set tag $::env(A1_TD_TAG) }
if {[file exists $tf]} { file copy -force $tf ./syn_gate_timing_$tag.rpt }
if {[file exists $af]} { file copy -force $af ./syn_gate_area_$tag.rpt }
set syn_wns -99.0; set syn_slice -1
if {[file exists $tf]} { set fh [open $tf r]; set txt [read $fh]; close $fh
  if {[regexp {SWNS:\s*(-?[0-9.]+)ns} $txt -> w]} { set syn_wns $w } }
if {[file exists $af]} { set fh [open $af r]; set atxt [read $fh]; close $fh
  regexp {#slice\*\s+([0-9]+)} $atxt -> syn_slice
  regexp {#eram\s+([0-9]+)} $atxt -> er; puts "SYN_ERAM=$er"
  regexp {#reg\s+([0-9]+)} $atxt -> rg; puts "SYN_REG=$rg"
  regexp {#dram\s+([0-9]+)} $atxt -> dr; puts "SYN_DRAM=$dr" }
puts "SYN_SWNS=$syn_wns"; puts "SYN_SLICE=$syn_slice"
if { ($syn_wns >= 1.0) && ($syn_slice > 0) && ($syn_slice <= 71680) } {
    puts "SYN_GATE_OK launching phy_1"
    if {[catch { launch_runs { phy_1 } -jobs 4 } e]} { puts "PHY_LAUNCH_ERR $e" }
    if {[catch { wait_run phy_1 -quiet } e]} { puts "PHY_WAIT_ERR $e" }
    if {[catch { import_db ./a1_bm_r0f_Runs/phy_1/a1_bm_r0f_pr.db } e]} { puts "IMPORT_DB_ERR $e" }
    if {[catch { update_timing -mode final } e]} { puts "UPDATE_TIMING_ERR $e" }
    if {[catch { report_timing_summary -file phy_timing_summary.rpt } e]} { puts "RPT_TS_ERR $e" }
    if {[catch { report_timing_status -file phy_timing_status.rpt } e]} { puts "RPT_TST_ERR $e" }
    if {[catch { report_area -io_info -file phy_area.rpt } e]} { puts "RPT_AREA_ERR $e" }
    if {[catch { report_qor -step route -file route_after_import.qor } e]} { puts "RPT_QOR_ERR $e" }
    if {[catch { report_cdc -file cdc.rpt } e]} { puts "RPT_CDC_ERR $e" }
    if {[catch { check_timing -verbose -file check_timing.rpt } e]} { puts "RPT_CHK_ERR $e" }
    if {[catch { report_clock_utilization -file phy_clock_util.rpt } e]} { puts "RPT_CLK_ERR $e" }
} else { puts "SYN_GATE_STOP no_route (wns=$syn_wns slice=$syn_slice)" }
puts "A1_bm_r0_DONE"
exit
