# =============================================================================
# T10.a1-qor-retime r0 -- strategy group 2: performance mapping / placement QoR
# RTL/SDC FROZEN: core 35ea7364...0942, frame 18d51b1b...1cbe, SDC 227dd39e...6311.
# Only synthesis/implementation strategy changes; no RTL/SDC edit, no seed sweep.
# T: = this package r0/td/g2 ; Y: = project root (tools/td/td_env.ps1).
# Fixed strategy (TD 2026.2 own QoR suggestions for this design, recorded):
#   syn  : set_param -run syn_1 gate map_mode logic_level_prior   (QOR-1002 gate suggestion)
#          set_param -run syn_1 gate map_strategy 2
#   place: set_param -run phy_1 place logic_level_opt on          (QOR-1002 place suggestion)
#          set_param -run phy_1 place effort high                  (place_qor_suggestion.tcl)
#          set_param -run phy_1 place opt_timing ultra
# route step stays default (post_route_opt auto); no retiming in this group.
# bitgen not run: stop marker dropped when opt_route begins; no .bit, no download.
# =============================================================================
set PRJ_ROOT "Y:/upstream/ph1p100-pcie-ep-fpga"
set prj "a1_qor_g2"
create_project $prj ./ -family PH1 -device PH1P100SBG484 -speed 3 -force
add_files $PRJ_ROOT/rtl/ep_side/codec/a1_frame_top.v
add_files $PRJ_ROOT/rtl/ep_side/codec/a1_deflate_core.v
add_files ./a1_eng_top.v
add_files ./a1_small_top.sdc
top_module a1_eng_top

# ---- fixed strategy group 2: performance map/place QoR ----------------------
foreach {p v} {map_mode logic_level_prior map_strategy 2} {
  if {[catch { set_param -run syn_1 gate $p $v } e]} { puts "G2_SYN_PARAM_ERR gate $p=$v : $e" } else { puts "G2_SYN_PARAM_OK gate $p=$v" }
}
foreach {p v} {logic_level_opt on effort high opt_timing ultra} {
  if {[catch { set_param -run phy_1 place $p $v } e]} { puts "G2_PLACE_PARAM_ERR $p=$v : $e" } else { puts "G2_PLACE_PARAM_OK $p=$v" }
}
if {[catch { report_param -file ./params_g2_before.tcl } e]} { puts "G2_REPORT_PARAM_ERR $e" } else { puts "G2_REPORT_PARAM_OK" }

# ---- synthesis --------------------------------------------------------------
launch_runs { syn_1 } -jobs 4
if {[catch { wait_run syn_1 -quiet } e]} { puts "SYN_WAIT_ERR $e" }
set tf "./${prj}_Runs/syn_1/${prj}_gate.timing"
set af "./${prj}_Runs/syn_1/${prj}_gate.area"
if {[file exists $tf]} { file copy -force $tf ./syn_gate_timing_g2.rpt }
if {[file exists $af]} { file copy -force $af ./syn_gate_area_g2.rpt }

set syn_wns -99.0; set syn_tns -99.0; set syn_slice -1; set syn_eram -1
set syn_reg -1; set syn_dram -1; set syn_core_eram -1
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
  if {[regexp {#dram lut\s+([0-9]+)} $atxt -> dr]} { set syn_dram $dr }
  if {[regexp {\|\s+u_core\s+\|a1_deflate_core\s+\|[0-9]+\s+\|[0-9]+\s+\|[0-9]+\s+\|([0-9]+)} $atxt -> ce]} { set syn_core_eram $ce }
}
puts "G2_SYN_SWNS=$syn_wns G2_SYN_STNS=$syn_tns G2_SYN_SLICE=$syn_slice G2_SYN_ERAM=$syn_eram G2_SYN_CORE_ERAM=$syn_core_eram G2_SYN_REG=$syn_reg G2_SYN_DRAM=$syn_dram"

# ---- physical: route step (default post_route_opt) --------------------------
if {[file exists ./${prj}_Runs/phy_1/.stop.f]} { file delete -force ./${prj}_Runs/phy_1/.stop.f }
if {[catch { launch_runs { phy_1 } -jobs 4 } e]} { puts "PHY_LAUNCH_ERR $e" }

set waited 0
while { (![file exists ./${prj}_Runs/phy_1/.opt_route.begin.f]) && ($waited < 2700) } {
  after 2000
  incr waited 2
  if {$waited % 120 == 0} { puts "G2_WAIT_OPT_ROUTE ${waited}s" }
}
if {[file exists ./${prj}_Runs/phy_1/.opt_route.begin.f]} {
  set fh [open ./${prj}_Runs/phy_1/.stop.f w]
  puts $fh "stop before bitgen (T10.a1-qor-retime r0 g2)"
  close $fh
  puts "G2_PHY_STOP_MARKER_SET waited=${waited}s"
} else {
  puts "G2_PHY_ROUTE_NOT_STARTED waited=${waited}s"
}
if {[catch { wait_run phy_1 -quiet } e]} { puts "PHY_WAIT_ERR $e" }

set prdb "./${prj}_Runs/phy_1/${prj}_pr.db"
if {[file exists $prdb]} {
  if {[catch { import_db $prdb } e]} { puts "IMPORT_DB_ERR $e" }
  if {[catch { update_timing -mode final } e]} { puts "UPDATE_TIMING_ERR $e" }

  # ---- required routed reports, written directly by the tool (-file) --------
  if {[catch { report_timing_summary -file ./routed_timing_summary.rpt } e]} { puts "RPT_TS_ERR $e" } else { puts "TIMING_SUMMARY_EXECUTED" }
  if {[catch { report_timing_status -file ./routed_timing_status.rpt } e]} { puts "RPT_TST_ERR $e" } else { puts "TIMING_STATUS_EXECUTED" }
  if {[catch { report_area -io_info -file ./routed_area.rpt } e]} { puts "RPT_AREA_ERR $e" } else { puts "AREA_EXECUTED" }
  if {[catch { report_timing -file ./routed_timing.rpt } e]} { puts "RPT_TIMING_ERR $e" } else { puts "TIMING_EXECUTED" }
  if {[catch { report_qor -step route -file ./routed_qor.rpt } e]} { puts "RPT_QOR_ERR $e" } else { puts "QOR_EXECUTED" }
  if {[catch { check_timing -verbose -file ./routed_check_timing.rpt } e]} { puts "RPT_CHK_ERR $e" } else { puts "CHECK_TIMING_EXECUTED" }
  if {[catch { report_clock_utilization -file ./routed_clock_utilization.rpt } e]} { puts "RPT_CLK_ERR $e" } else { puts "CLOCK_UTIL_EXECUTED" }
  # TD Release_2026.2 has no report_cdc: the attempt is kept verbatim so the
  # absence is evidence, not an assumption; static single-clock evidence only.
  if {[catch { report_cdc -file ./cdc_not_available.rpt } e]} { puts "RPT_CDC_UNAVAILABLE $e" } else { puts "CDC_EXECUTED_UNEXPECTED" }
  if {[catch { report_timing -max_paths 1000 -file ./routed_timing_top.rpt } e]} { puts "TOPN_UNAVAILABLE $e" } else { puts "TOPN_EXECUTED" }
  if {[catch { report_param -file ./params_g2_after.tcl } e]} { puts "RPT_PARAM_AFTER_ERR $e" } else { puts "PARAM_AFTER_EXECUTED" }
  if {[catch { write_verilog ./g2_routed_netlist.v } e]} { puts "WV_ROUTED_ERR $e" } else { puts "WV_ROUTED_OK" }

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
  puts "G2_ROUTED_SWNS=$pwns G2_ROUTED_STNS=$ptns G2_ROUTED_HWNS=$hwns G2_ROUTED_HTNS=$htns G2_ROUTED_VIOL_EP=$pvf G2_ROUTED_TOTAL_EP=$ptot"

  if {[file exists ./${prj}_Runs/phy_1/route_flow.status]} { file copy -force ./${prj}_Runs/phy_1/route_flow.status ./route_flow.status }
  if {[file exists ./${prj}_Runs/phy_1/place_flow.status]} { file copy -force ./${prj}_Runs/phy_1/place_flow.status ./place_flow.status }
  if {[file exists ./${prj}_Runs/phy_1/${prj}_phy.area]} { file copy -force ./${prj}_Runs/phy_1/${prj}_phy.area ./phy_area_run.rpt }
  if {[file exists ./${prj}_Runs/phy_1/${prj}_pr.bit]} { puts "BIT_PRESENT_UNEXPECTED" } else { puts "NO_BIT_FILE" }

  # ---- gate + elaborate netlists for the static cross-domain check -----------
  if {[catch { import_db ./${prj}_Runs/syn_1/${prj}_gate.db } e]} { puts "IMPORT_GATE_ERR $e" } else {
    if {[catch { write_verilog ./g2_gate_netlist.v } e]} { puts "WV_GATE_ERR $e" } else { puts "WV_GATE_OK" }
  }
  if {[catch { import_db ./${prj}_Runs/syn_1/${prj}_elaborate.db } e]} { puts "IMPORT_ELAB_ERR $e" } else {
    if {[catch { write_verilog ./g2_elab_netlist.v } e]} { puts "WV_ELAB_ERR $e" } else { puts "WV_ELAB_OK" }
  }
} else {
  puts "PHY_NO_PR_DB"
}
puts "A1_QOR_G2_DONE"
exit
