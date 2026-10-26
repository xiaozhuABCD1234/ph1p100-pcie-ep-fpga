# T10.a1-adler-smem r0-route -- route-only on the existing r0 synthesis
# (a1_adler_smem.al, syn_1 = candidate core 611ad704 / frame cc330814, SDC 227dd39e).
# Planner-approved one-time waiver of the +0.3 ns pre-route synth gate
# (dispatch-adler-smem-route.json); the final gate stays
# Routed WNS/TNS/HWNS/HTNS >= 0, 0 violating endpoints, resources in device.
# No synthesis, no RTL change, no bitgen, no .bit, no download.
set prj "a1_adler_smem"

import_device ph1_100p.db -package PH1P100SBG484 -speed 3
open_project ./${prj}.al
puts "PROJECT_OPENED"

# route-only integrity: the r0 synthesis checkpoint must already exist
if {[file exists ./${prj}_Runs/syn_1/${prj}_gate.db]} { puts "SYN_CHECKPOINT_PRESENT" } else { puts "SYN_CHECKPOINT_MISSING" }
set scfg_syn "./${prj}_Runs/syn_1/settings.cfg"
if {[file exists $scfg_syn]} {
  set fh [open $scfg_syn r]; set st [read $fh]; close $fh
  set dev "?"; set pkg "?"
  if {[regexp {set device_name\s+(\S+)} $st -> d]} { set dev $d }
  if {[regexp {set package_name\s+(\S+)} $st -> p]} { set pkg $p }
  puts "SYN_SETTINGS_CHECK device=$dev package=$pkg"
}

if {[file exists ./${prj}_Runs/phy_1/.stop.f]} { file delete -force ./${prj}_Runs/phy_1/.stop.f }
if {[catch { reset_run phy_1 } e]} { puts "RESET_RUN_ERR $e" }
if {[catch { launch_runs { phy_1 } -jobs 4 } e]} { puts "PHY_LAUNCH_ERR $e" }

# 10 s early-failure check: settings.cfg must carry device/package, run.log must not
# report PRJ-8001, and place must start.
set scfg "./${prj}_Runs/phy_1/settings.cfg"
set rlog "./${prj}_Runs/phy_1/run.log"
set started 0
set failed 0
for {set i 0} {$i < 5} {incr i} {
  after 2000
  if {[file exists $scfg]} {
    set fh [open $scfg r]; set st [read $fh]; close $fh
    set dev "?"; set pkg "?"
    if {[regexp {set device_name\s+(\S+)} $st -> d]} { set dev $d }
    if {[regexp {set package_name\s+(\S+)} $st -> p]} { set pkg $p }
    puts "SETTINGS_CHECK device=$dev package=$pkg"
  }
  if {[file exists $rlog]} {
    set fh [open $rlog r]; set rl [read $fh]; close $fh
    if {[string match *PRJ-8001* $rl]} { set failed 1; puts "PHY_EARLY_FAIL PRJ-8001"; break }
  }
  if {[file exists ./${prj}_Runs/phy_1/.opt_place.begin.f]} { set started 1; puts "OPT_PLACE_STARTED"; break }
}
if {$failed} { puts "A1_ADLERSMEM_r0route_DONE"; exit }
if {!$started} {
  puts "OPT_PLACE_NOT_STARTED_10s"
  if {[file exists $rlog]} { set fh [open $rlog r]; puts [read $fh]; close $fh }
  puts "A1_ADLERSMEM_r0route_DONE"
  exit
}

# Drop the stop marker as soon as route begins: the phy flow checks it at the start
# of the next step (bitgen), which then halts before executing.  Route is unaffected
# and still exports the routed *_pr.db.
set waited 0
while { (![file exists ./${prj}_Runs/phy_1/.opt_route.begin.f]) && ($waited < 1500) } {
  after 2000
  incr waited 2
  if {$waited % 60 == 0} { puts "WAIT_OPT_ROUTE ${waited}s" }
}
if {[file exists ./${prj}_Runs/phy_1/.opt_route.begin.f]} {
  set fh [open ./${prj}_Runs/phy_1/.stop.f w]
  puts $fh "stop before bitgen (T10.a1-adler-smem r0-route route-only)"
  close $fh
  puts "PHY_STOP_MARKER_SET waited=${waited}s"
} else {
  puts "PHY_ROUTE_NOT_STARTED waited=${waited}s"
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
  if {[catch { check_timing -verbose -file ./routed_check_timing.rpt } e]} { puts "RPT_CHK_ERR $e" } else { puts "CHECK_TIMING_EXECUTED" }
  if {[catch { report_clock_utilization -file ./routed_clock_utilization.rpt } e]} { puts "RPT_CLK_ERR $e" } else { puts "CLOCK_UTIL_EXECUTED" }
  if {[catch { report_timing -file ./routed_timing.rpt } e]} { puts "RPT_TIMING_ERR $e" } else { puts "TIMING_EXECUTED" }
  if {[catch { report_qor -step route -file ./routed_qor.rpt } e]} { puts "RPT_QOR_ERR $e" } else { puts "QOR_EXECUTED" }
  if {[catch { report_exceptions -file ./routed_exceptions.rpt } e]} { puts "RPT_EXC_ERR $e" } else { puts "EXCEPTIONS_EXECUTED" }
  # TD Release_2026.2 has no report_cdc: the attempt is kept verbatim so the absence
  # is evidence, not an assumption.  Static single-clock CDC evidence is collected
  # separately (clock summary + check_timing + cdc-static.md); never called report_cdc.
  if {[catch { report_cdc -file ./cdc_not_available.rpt } e]} { puts "RPT_CDC_UNAVAILABLE $e" } else { puts "CDC_EXECUTED_UNEXPECTED" }
  if {[catch { report_clocks -file ./routed_clocks.rpt } e]} { puts "RPT_CLOCKS_UNAVAILABLE $e" } else { puts "REPORT_CLOCKS_EXECUTED" }

  set pwns -99.0; set ptns -99.0; set hwns -99.0; set htns -99.0
  set ptf "./${prj}_Runs/phy_1/${prj}_pr.timing"
  if {[file exists $ptf]} {
    file copy -force $ptf ./phy_pr_timing_flow.rpt
    set fh [open $ptf r]; set ptxt [read $fh]; close $fh
    if {[regexp {SWNS:\s*(-?[0-9.]+)ns} $ptxt -> w]} { set pwns $w }
    if {[regexp {STNS:\s*(-?[0-9.]+)ns} $ptxt -> w]} { set ptns $w }
    if {[regexp {HWNS:\s*(-?[0-9.]+)ns} $ptxt -> w]} { set hwns $w }
    if {[regexp {HTNS:\s*(-?[0-9.]+)ns} $ptxt -> w]} { set htns $w }
  } else { puts "PR_TIMING_MISSING" }
  puts "ROUTED_SWNS=$pwns ROUTED_STNS=$ptns ROUTED_HWNS=$hwns ROUTED_HTNS=$htns"

  if {[file exists ./${prj}_Runs/phy_1/route_flow.status]} { file copy -force ./${prj}_Runs/phy_1/route_flow.status ./route_flow.status }
  if {[file exists ./${prj}_Runs/phy_1/place_flow.status]} { file copy -force ./${prj}_Runs/phy_1/place_flow.status ./place_flow.status }
  if {[file exists ./${prj}_Runs/phy_1/${prj}_phy.area]} { file copy -force ./${prj}_Runs/phy_1/${prj}_phy.area ./phy_area_run.rpt }
  if {[file exists ./${prj}_Runs/phy_1/${prj}_pr.bit]} { puts "BIT_PRESENT_UNEXPECTED" } else { puts "NO_BIT_FILE" }
} else {
  puts "PHY_NO_PR_DB"
}
puts "A1_ADLERSMEM_r0route_DONE"
exit
