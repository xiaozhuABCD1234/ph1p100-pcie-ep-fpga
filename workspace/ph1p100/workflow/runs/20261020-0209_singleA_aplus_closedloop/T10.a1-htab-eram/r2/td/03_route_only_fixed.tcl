# T10.a1-htab-eram r2-waive2: corrected route-only on the existing r2 synthesis.
# T: = r2/td, Y: = project root.  No synthesis, no RTL change, no bitgen.
# Fix vs r2-waive: import_device first so the launcher writes non-empty
# device_name/package_name, plus an early-failure check (no 1800 s poll).
set prj "a1_ht_r2"

import_device ph1_100p.db -package PH1P100SBG484 -speed 3
open_project ./${prj}.al
puts "PROJECT_OPENED"

if {[file exists ./${prj}_Runs/phy_1/.stop.f]} { file delete -force ./${prj}_Runs/phy_1/.stop.f }
if {[catch { reset_run phy_1 } e]} { puts "RESET_RUN_ERR $e" }
if {[catch { launch_runs { phy_1 } -jobs 4 } e]} { puts "PHY_LAUNCH_ERR $e" }

set scfg "./${prj}_Runs/phy_1/settings.cfg"
set rlog "./${prj}_Runs/phy_1/run.log"
set started 0
set failed 0
for {set i 0} {$i < 6} {incr i} {
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
if {$failed} { puts "A1_route_only_DONE"; exit }
if {!$started} {
  puts "OPT_PLACE_NOT_STARTED_12s"
  if {[file exists $rlog]} { set fh [open $rlog r]; puts [read $fh]; close $fh }
  puts "A1_route_only_DONE"
  exit
}

set route_start 0
set waited 0
while { (![file exists ./${prj}_Runs/phy_1/.opt_route.begin.f]) && ($waited < 1500) } {
  after 2000
  incr waited 2
  if {$waited % 60 == 0} { puts "WAIT_OPT_ROUTE ${waited}s" }
}
if {[file exists ./${prj}_Runs/phy_1/.opt_route.begin.f]} {
  set route_start 1
  set fh [open ./${prj}_Runs/phy_1/.stop.f w]
  puts $fh "stop before bitgen (r2-waive2)"
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
  if {[catch { report_timing_summary -file phy_timing_summary.rpt } e]} { puts "RPT_TS_ERR $e" }
  if {[catch { report_timing_status -file phy_timing_status.rpt } e]} { puts "RPT_TST_ERR $e" }
  if {[catch { report_area -io_info -file phy_area.rpt } e]} { puts "RPT_AREA_ERR $e" }
  if {[catch { report_timing -file phy_timing.rpt } e]} { puts "RPT_TIMING_ERR $e" }
  if {[catch { report_qor -step route -file route_after_import.qor } e]} { puts "RPT_QOR_ERR $e" }
  if {[catch { report_cdc -file cdc.rpt } e]} { puts "RPT_CDC_ERR $e" } else { puts "CDC_EXECUTED" }
  if {[catch { check_timing -verbose -file check_timing.rpt } e]} { puts "RPT_CHK_ERR $e" } else { puts "CHECK_TIMING_EXECUTED" }
  if {[catch { report_clock_utilization -file phy_clock_util.rpt } e]} { puts "RPT_CLK_ERR $e" }

  set pwns -99.0; set ptns -99.0; set hwns -99.0; set htns -99.0
  set ptf "./${prj}_Runs/phy_1/${prj}_pr.timing"
  if {[file exists $ptf]} {
    file copy -force $ptf ./phy_pr_timing.rpt
    set fh [open $ptf r]; set ptxt [read $fh]; close $fh
    if {[regexp {SWNS:\s*(-?[0-9.]+)ns} $ptxt -> w]} { set pwns $w }
    if {[regexp {STNS:\s*(-?[0-9.]+)ns} $ptxt -> w]} { set ptns $w }
    if {[regexp {HWNS:\s*(-?[0-9.]+)ns} $ptxt -> w]} { set hwns $w }
    if {[regexp {HTNS:\s*(-?[0-9.]+)ns} $ptxt -> w]} { set htns $w }
  } else { puts "PR_TIMING_MISSING" }
  puts "ROUTED_SWNS=$pwns ROUTED_STNS=$ptns ROUTED_HWNS=$hwns ROUTED_HTNS=$htns"

  foreach {src dst} {
    "${prj}_Runs/phy_1/${prj}_pr.timing" "phy_pr_timing_raw.rpt"
    "${prj}_Runs/phy_1/${prj}_phy.ts" "phy_timing_status_raw.rpt"
    "${prj}_Runs/phy_1/${prj}_phy.area" "phy_area_raw.rpt"
    "${prj}_Runs/phy_1/${prj}_chk.timing" "phy_check_timing_raw.rpt"
    "${prj}_Runs/phy_1/route.qor" "route_raw.qor"
    "${prj}_Runs/phy_1/route_flow.status" "route_flow.status"
  } {
    if {[file exists $src]} { file copy -force $src ./$dst }
  }
  if {[file exists ./cdc.rpt] && ([file size ./cdc.rpt] > 0)} { puts "CDC_FILE_OK" }
  if {[file exists ./check_timing.rpt] && ([file size ./check_timing.rpt] > 0)} { puts "CHECK_TIMING_FILE_OK" }
} else {
  puts "PHY_NO_PR_DB"
}
puts "A1_route_only_DONE"
exit
