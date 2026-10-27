# =============================================================================
# T10.b2-a1-uart-impl r4 -- route-only continuation.
#
# Why this file exists: 01_build.tcl finished synthesis successfully (gate
# timing SWNS +0.256 ns, 0 failing endpoints, ERAM 72) but TD's wait_run
# reported "Run syn_1 failed" / "exited unexpectedly" and the script took its
# fail-closed exit before launching phy_1.  The same TD quirk happened in r3
# (build_console_r3d.log) and a plain re-run was the accepted workaround there.
# Here the completed synth database is re-used instead of re-synthesising, so
# the positive gate result is not thrown away.
#
# Guards: the stored gate report must still show SWNS >= 0 and zero failing
# endpoints, otherwise this script refuses to route.  Bitgen is still a separate
# single attempt (02_bitgen.tcl); this script stops the flow before bitgen.
# =============================================================================
set prj "a1_board"
open_project ./${prj}.al

# The r3 flow always had a device context because create_project was used.  A
# bare open_project leaves device_name/package_name empty in phy_1/settings.cfg
# (observed at 17:43: `can't read "device_name"`), so import the device first.
if {[catch { import_device ph1_100p.db -package PH1P100SBG484 -speed 3 } e]} {
    puts "R4R_DEVICE_IMPORT_ERR $e"
    exit 1
}
puts "R4R_DEVICE_IMPORT_OK ph1_100p.db PH1P100SBG484 speed 3"

set tf "./${prj}_Runs/syn_1/${prj}_gate.timing"
if {![file exists $tf]} {
    puts "R4R_ABORT no_gate_timing"
    exit 1
}
set fh [open $tf r]; set txt [read $fh]; close $fh
set syn_wns -99.0; set syn_tns -99.0
if {[regexp {SWNS:\s*(-?[0-9.]+)ns} $txt -> w]} { set syn_wns $w }
if {[regexp {STNS:\s*(-?[0-9.]+)ns} $txt -> w]} { set syn_tns $w }
if {![regexp {SWNS:?\s*(-?[0-9.]+)ns,\s*STNS:?\s*(-?[0-9.]+)ns,\s*([0-9]+) Viol Endpoints,\s*([0-9]+) Total Endpoints} $txt -> _a _b vf tot]} {
    set vf -1; set tot -1
}
puts "R4R_SYN_SWNS=$syn_wns R4R_SYN_STNS=$syn_tns R4R_SYN_VIOL_EP=$vf R4R_SYN_TOTAL_EP=$tot"
if {$syn_wns < 0 || $vf != 0} {
    puts "R4R_SYN_GATE_REJECT"
    exit 1
}

foreach {p v} {post_route_opt ultra postrt_opt_loc 40 postrt_opt_extra_round 12} {
  if {[catch { set_param -run phy_1 route $p $v } e]} { puts "R4R_ROUTE_PARAM_ERR $p=$v : $e" } else { puts "R4R_ROUTE_PARAM_OK $p=$v" }
}

if {[file exists ./${prj}_Runs/phy_1/.stop.f]} { file delete -force ./${prj}_Runs/phy_1/.stop.f }
foreach rc {reset_runs reset_run} {
  if {[catch {$rc phy_1} e]} { puts "R4R_${rc}_ERR $e" } else { puts "R4R_${rc}_OK"; break }
}
if {[catch { launch_runs { phy_1 } -jobs 4 } e]} { puts "R4R_PHY_LAUNCH_ERR $e" }

set waited 0
while { (![file exists ./${prj}_Runs/phy_1/.opt_route.begin.f]) && ($waited < 3000) } {
  after 2000
  incr waited 2
  if {$waited % 120 == 0} { puts "R4R_WAIT_OPT_ROUTE ${waited}s" }
}
# Stop the flow before bitgen; bitgen is a single separate attempt.
if {[file exists ./${prj}_Runs/phy_1/.opt_route.begin.f]} {
  set fh [open ./${prj}_Runs/phy_1/.stop.f w]
  puts $fh "stop before bitgen (T10.b2-a1-uart-impl r4)"
  close $fh
  puts "R4R_PHY_STOP_MARKER_SET waited=${waited}s"
} else {
  puts "R4R_PHY_ROUTE_NOT_STARTED waited=${waited}s"
}
if {[catch { wait_run phy_1 -quiet } e]} { puts "R4R_PHY_WAIT_ERR $e" }

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
  puts "R4R_ROUTED_SWNS=$pwns R4R_ROUTED_STNS=$ptns R4R_ROUTED_HWNS=$hwns R4R_ROUTED_HTNS=$htns R4R_ROUTED_VIOL_EP=$pvf R4R_ROUTED_TOTAL_EP=$ptot"

  if {[file exists ./${prj}_Runs/phy_1/route_flow.status]} { file copy -force ./${prj}_Runs/phy_1/route_flow.status ./route_flow.status }
  if {[file exists ./${prj}_Runs/phy_1/place_flow.status]} { file copy -force ./${prj}_Runs/phy_1/place_flow.status ./place_flow.status }
  if {[file exists ./${prj}_Runs/phy_1/${prj}_phy.area]} { file copy -force ./${prj}_Runs/phy_1/${prj}_phy.area ./phy_area_run.rpt }
  if {[file exists ./${prj}_Runs/phy_1/${prj}_pr.bit]} { puts "BIT_PRESENT_UNEXPECTED" } else { puts "NO_BIT_FILE" }
} else {
  puts "R4R_PHY_NO_PR_DB"
}
puts "R4R_BUILD_DONE"
exit
