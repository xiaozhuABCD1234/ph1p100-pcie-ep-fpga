# T10.a1-bm-prefetch r2-waive -- route-only on the existing r2 synthesis (a1_bp_r2.al, syn_1).
# Planner-approved one-time waiver of the +0.5 ns pre-route synth gate; the final gate is
# Routed WNS/TNS/HWNS/HTNS >= 0, 0 violations, resources in device.
# No synthesis, no RTL change, no bitgen, no .bit, no download.
# Harness carried over from the hit-pipe r0 route-only run: import_device first (non-empty
# settings.cfg device/package), 12 s early-failure check, stop marker before bitgen.
set prj "a1_bp_r2"
set outdir "../r2-waive"

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
if {$failed} { puts "A1_BMPREFETCH_r2waive_route_DONE"; exit }
if {!$started} {
  puts "OPT_PLACE_NOT_STARTED_12s"
  if {[file exists $rlog]} { set fh [open $rlog r]; puts [read $fh]; close $fh }
  puts "A1_BMPREFETCH_r2waive_route_DONE"
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
  puts $fh "stop before bitgen (T10.a1-bm-prefetch r2-waive route-only)"
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
  if {[catch { report_timing_summary -file ${outdir}/routed_timing_summary.rpt } e]} { puts "RPT_TS_ERR $e" } else { puts "TIMING_SUMMARY_EXECUTED" }
  if {[catch { report_timing_status -file ${outdir}/routed_timing_status.rpt } e]} { puts "RPT_TST_ERR $e" }
  if {[catch { report_area -io_info -file ${outdir}/routed_area.rpt } e]} { puts "RPT_AREA_ERR $e" } else { puts "AREA_EXECUTED" }
  if {[catch { check_timing -verbose -file ${outdir}/routed_check_timing.rpt } e]} { puts "RPT_CHK_ERR $e" } else { puts "CHECK_TIMING_EXECUTED" }
  if {[catch { report_clock_utilization -file ${outdir}/routed_clock_utilization.rpt } e]} { puts "RPT_CLK_ERR $e" } else { puts "CLOCK_UTIL_EXECUTED" }
  if {[catch { report_timing -file ${outdir}/routed_timing.rpt } e]} { puts "RPT_TIMING_ERR $e" } else { puts "TIMING_EXECUTED" }
  if {[catch { report_qor -step route -file ${outdir}/routed_qor.rpt } e]} { puts "RPT_QOR_ERR $e" }
  if {[catch { report_exceptions -file ${outdir}/routed_exceptions.rpt } e]} { puts "RPT_EXC_ERR $e" } else { puts "EXCEPTIONS_EXECUTED" }
  if {[catch { report_cdc -file ${outdir}/cdc_not_available.rpt } e]} { puts "RPT_CDC_UNAVAILABLE $e" } else { puts "CDC_EXECUTED_UNEXPECTED" }
  if {[catch { report_clocks -file ${outdir}/routed_clocks.rpt } e]} { puts "RPT_CLOCKS_UNAVAILABLE $e" } else { puts "REPORT_CLOCKS_EXECUTED" }

  # ---- directed enumeration of bm/htab ERAM clk2q start points --------------
  # TD is not assumed to support -from with hierarchical pin patterns; every
  # attempt is guarded and its failure message kept verbatim so the coverage
  # (and its limits) is evidence, not an assumption.
  set ok 0
  if {!$ok} {
    if {[catch { report_timing -from [get_pins -hierarchical {*bm_a*}] -max_paths 400 -file ${outdir}/routed_timing_bm_a_pins.rpt } e]} {
      puts "DIRECTED_BMA_PINS_UNAVAILABLE $e"
    } else { set ok 1; puts "DIRECTED_BMA_PINS_EXECUTED" }
  }
  if {!$ok} {
    if {[catch { report_timing -from [get_cells -hierarchical {*bm_a*}] -max_paths 400 -file ${outdir}/routed_timing_bm_a_cells.rpt } e]} {
      puts "DIRECTED_BMA_CELLS_UNAVAILABLE $e"
    } else { set ok 1; puts "DIRECTED_BMA_CELLS_EXECUTED" }
  }
  set ok2 0
  if {[catch { report_timing -from [get_pins -hierarchical {*htab*}] -max_paths 400 -file ${outdir}/routed_timing_htab_pins.rpt } e]} {
    puts "DIRECTED_HTAB_PINS_UNAVAILABLE $e"
  } else { set ok2 1; puts "DIRECTED_HTAB_PINS_EXECUTED" }
  if {!$ok2} {
    if {[catch { report_timing -from [get_cells -hierarchical {*htab*}] -max_paths 400 -file ${outdir}/routed_timing_htab_cells.rpt } e]} {
      puts "DIRECTED_HTAB_CELLS_UNAVAILABLE $e"
    } else { puts "DIRECTED_HTAB_CELLS_EXECUTED" }
  }
  # Whole-design worst-path dump (no filter) as the fallback coverage source.
  if {[catch { report_timing -max_paths 1000 -file ${outdir}/routed_timing_top1000.rpt } e]} { puts "TOP1000_UNAVAILABLE $e" } else { puts "TOP1000_EXECUTED" }

  set pwns -99.0; set ptns -99.0; set hwns -99.0; set htns -99.0
  set ptf "./${prj}_Runs/phy_1/${prj}_pr.timing"
  if {[file exists $ptf]} {
    file copy -force $ptf ${outdir}/phy_pr_timing_flow.rpt
    set fh [open $ptf r]; set ptxt [read $fh]; close $fh
    if {[regexp {SWNS:\s*(-?[0-9.]+)ns} $ptxt -> w]} { set pwns $w }
    if {[regexp {STNS:\s*(-?[0-9.]+)ns} $ptxt -> w]} { set ptns $w }
    if {[regexp {HWNS:\s*(-?[0-9.]+)ns} $ptxt -> w]} { set hwns $w }
    if {[regexp {HTNS:\s*(-?[0-9.]+)ns} $ptxt -> w]} { set htns $w }
  } else { puts "PR_TIMING_MISSING" }
  puts "ROUTED_SWNS=$pwns ROUTED_STNS=$ptns ROUTED_HWNS=$hwns ROUTED_HTNS=$htns"

  foreach {src dst} {
    "${prj}_Runs/phy_1/${prj}_pr.timing"      "phy_pr_timing_raw.rpt"
    "${prj}_Runs/phy_1/${prj}_phy.ts"         "phy_timing_status_raw.rpt"
    "${prj}_Runs/phy_1/${prj}_phy.area"       "phy_area_raw.rpt"
    "${prj}_Runs/phy_1/route.qor"             "route_raw.qor"
    "${prj}_Runs/phy_1/route_flow.status"     "route_flow.status"
    "${prj}_Runs/phy_1/run.log"               "phy_run.log"
    "${prj}_Runs/phy_1/place_flow.status"     "place_flow.status"
  } {
    if {[file exists $src]} { file copy -force $src ${outdir}/$dst }
  }
  if {[file exists ./${prj}_Runs/phy_1/.stop.f]} { puts "STOP_MARKER_PRESENT" }
  if {[file exists ./${prj}_Runs/phy_1/${prj}_pr.bit]} { puts "BIT_PRESENT_UNEXPECTED" } else { puts "NO_BIT_FILE" }
} else {
  puts "PHY_NO_PR_DB"
}
puts "A1_BMPREFETCH_r2waive_route_DONE"
exit
