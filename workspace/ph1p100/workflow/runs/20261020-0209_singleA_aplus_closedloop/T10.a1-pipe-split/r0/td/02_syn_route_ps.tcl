# =============================================================================
# T10.a1-pipe-split r0 -- session 2: synthesis + the single route attempt
# RTL: core = rng1_r stage-1 registration (working tree), frame 18d51b1b, SDC 227dd39e.
# Frozen strategy group 1: syn retiming on + route post_route_opt ultra (phys_opt
# -post_route -effort high).  No seed sweep, no clock change, no false path,
# no multicycle, no bitgen (stop marker dropped when opt_route begins).
# T: = this package r0/td ; Y: = project root (tools/td/td_env.ps1).
# =============================================================================
set PRJ_ROOT "Y:/upstream/ph1p100-pcie-ep-fpga"
set prj "a1_ps"
create_project $prj ./ -family PH1 -device PH1P100SBG484 -speed 3 -force
add_files $PRJ_ROOT/rtl/ep_side/codec/a1_frame_top.v
add_files $PRJ_ROOT/rtl/ep_side/codec/a1_deflate_core.v
add_files ./a1_eng_top.v
add_files ./a1_small_top.sdc
top_module a1_eng_top

# ---- frozen strategy group 1: retiming + phys_opt ---------------------------
if {[catch { set_param -run syn_1 rtl retiming on } e]} {
  puts "PS_SYN_PARAM_ERR $e"
  if {[catch { set_param rtl retiming on } e2]} { puts "PS_SYN_PARAM_FALLBACK_ERR $e2" } else { puts "PS_SYN_PARAM_FALLBACK_OK rtl retiming on" }
} else { puts "PS_SYN_PARAM_OK rtl retiming on" }
foreach {p v} {post_route_opt ultra postrt_opt_loc 20 postrt_opt_extra_round 4} {
  if {[catch { set_param -run phy_1 route $p $v } e]} { puts "PS_ROUTE_PARAM_ERR $p=$v : $e" } else { puts "PS_ROUTE_PARAM_OK $p=$v" }
}
if {[catch { report_param -file ./params_ps_before.tcl } e]} { puts "PS_REPORT_PARAM_ERR $e" } else { puts "PS_REPORT_PARAM_OK" }

# ---- synthesis --------------------------------------------------------------
launch_runs { syn_1 } -jobs 4
if {[catch { wait_run syn_1 -quiet } e]} { puts "SYN_WAIT_ERR $e" }
set tf "./${prj}_Runs/syn_1/${prj}_gate.timing"
set af "./${prj}_Runs/syn_1/${prj}_gate.area"
if {[file exists $tf]} { file copy -force $tf ./syn_gate_timing_ps.rpt }
if {[file exists $af]} { file copy -force $af ./syn_gate_area_ps.rpt }

set syn_wns -99.0; set syn_tns -99.0; set syn_slice -1; set syn_eram -1
set syn_reg -1; set syn_dram -1
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
}
puts "PS_SYN_SWNS=$syn_wns PS_SYN_STNS=$syn_tns PS_SYN_SLICE=$syn_slice PS_SYN_ERAM=$syn_eram PS_SYN_REG=$syn_reg PS_SYN_DRAM=$syn_dram"

# ---- physical: route step (includes phys_opt -post_route) -------------------
if {[file exists ./${prj}_Runs/phy_1/.stop.f]} { file delete -force ./${prj}_Runs/phy_1/.stop.f }
if {[catch { launch_runs { phy_1 } -jobs 4 } e]} { puts "PHY_LAUNCH_ERR $e" }

set waited 0
while { (![file exists ./${prj}_Runs/phy_1/.opt_route.begin.f]) && ($waited < 2700) } {
  after 2000
  incr waited 2
  if {$waited % 120 == 0} { puts "PS_WAIT_OPT_ROUTE ${waited}s" }
}
if {[file exists ./${prj}_Runs/phy_1/.opt_route.begin.f]} {
  set fh [open ./${prj}_Runs/phy_1/.stop.f w]
  puts $fh "stop before bitgen (T10.a1-pipe-split r0)"
  close $fh
  puts "PS_PHY_STOP_MARKER_SET waited=${waited}s"
} else {
  puts "PS_PHY_ROUTE_NOT_STARTED waited=${waited}s"
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
  # TD Release_2026.2 has no report_cdc: keep the attempt verbatim as evidence.
  if {[catch { report_cdc -file ./cdc_not_available.rpt } e]} { puts "RPT_CDC_UNAVAILABLE $e" } else { puts "CDC_EXECUTED_UNEXPECTED" }
  if {[catch { report_timing -max_paths 1000 -file ./routed_timing_top.rpt } e]} { puts "TOPN_UNAVAILABLE $e" } else { puts "TOPN_EXECUTED" }
  if {[catch { report_param -file ./params_ps_after.tcl } e]} { puts "RPT_PARAM_AFTER_ERR $e" } else { puts "PARAM_AFTER_EXECUTED" }
  if {[catch { write_verilog ./ps_routed_netlist.v } e]} { puts "WV_ROUTED_ERR $e" } else { puts "WV_ROUTED_OK" }

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
  puts "PS_ROUTED_SWNS=$pwns PS_ROUTED_STNS=$ptns PS_ROUTED_HWNS=$hwns PS_ROUTED_HTNS=$htns PS_ROUTED_VIOL_EP=$pvf PS_ROUTED_TOTAL_EP=$ptot"

  if {[file exists ./${prj}_Runs/phy_1/route_flow.status]} { file copy -force ./${prj}_Runs/phy_1/route_flow.status ./route_flow.status }
  if {[file exists ./${prj}_Runs/phy_1/place_flow.status]} { file copy -force ./${prj}_Runs/phy_1/place_flow.status ./place_flow.status }
  if {[file exists ./${prj}_Runs/phy_1/${prj}_phy.area]} { file copy -force ./${prj}_Runs/phy_1/${prj}_phy.area ./phy_area_run.rpt }
  if {[file exists ./${prj}_Runs/phy_1/${prj}_pr.bit]} { puts "BIT_PRESENT_UNEXPECTED" } else { puts "NO_BIT_FILE" }

  # ---- gate + elaborate netlists for the retiming static cross-domain check --
  if {[catch { import_db ./${prj}_Runs/syn_1/${prj}_gate.db } e]} { puts "IMPORT_GATE_ERR $e" } else {
    if {[catch { write_verilog ./ps_gate_netlist.v } e]} { puts "WV_GATE_ERR $e" } else { puts "WV_GATE_OK" }
  }
  if {[catch { import_db ./${prj}_Runs/syn_1/${prj}_elaborate.db } e]} { puts "IMPORT_ELAB_ERR $e" } else {
    if {[catch { write_verilog ./ps_elab_netlist.v } e]} { puts "WV_ELAB_ERR $e" } else { puts "WV_ELAB_OK" }
  }
} else {
  puts "PHY_NO_PR_DB"
}
puts "A1_PS_ROUTE_DONE"
exit
