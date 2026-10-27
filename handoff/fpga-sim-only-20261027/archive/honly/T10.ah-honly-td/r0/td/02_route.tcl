# =============================================================================
# 02_route.tcl - T10.ah-honly-td (Line B) conditional place & route.
#
# NOT EXECUTED in round r0.  Run only after 01_synth.tcl has produced a gate DB
# and only when the TD lease is granted to this task.  Quota: <=2 route runs, the
# 2nd only after a failed 1st and only with its parameter difference written down
# (no seed sweep).  No bitgen, no CWC, no download, no Flash, no board.
#
# cwd must be this directory; invoke:
#   D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe ./02_route.tcl
# =============================================================================
set prj "a1_ah"
set gate "./${prj}_Runs/syn_1/${prj}_gate.db"
set prdb "./${prj}_Runs/phy_1/${prj}_pr.db"

if {![file exists "./${prj}.al"]} { puts "AH_ROUTE_NO_PROJECT"; exit 1 }
open_project ./$prj.al
if {![file exists $gate]} { puts "AH_ROUTE_NO_GATE_DB path=$gate"; exit 1 }

import_db $gate
launch_runs { phy_1 } -jobs 4
if {[catch { wait_run phy_1 -quiet } e]} { puts "AH_ROUTE_WAIT_ERR $e" }

if {[file exists $prdb]} {
  import_db $prdb
  update_timing -mode final
  if {[catch { report_timing_summary -file ./routed_timing_summary.rpt } e]} { puts "AH_ROUTE_RPT_TS_ERR $e" } else { puts "AH_ROUTE_TS_EXECUTED" }
  if {[catch { report_timing_status -file ./routed_timing_status.rpt } e]} { puts "AH_ROUTE_RPT_TST_ERR $e" } else { puts "AH_ROUTE_TST_EXECUTED" }
  if {[catch { report_area -io_info -file ./routed_area.rpt } e]} { puts "AH_ROUTE_RPT_AREA_ERR $e" } else { puts "AH_ROUTE_AREA_EXECUTED" }
  if {[catch { report_timing -file ./routed_timing.rpt } e]} { puts "AH_ROUTE_RPT_TIMING_ERR $e" } else { puts "AH_ROUTE_TIMING_EXECUTED" }
  if {[catch { report_qor -step route -file ./routed_qor.rpt } e]} { puts "AH_ROUTE_RPT_QOR_ERR $e" } else { puts "AH_ROUTE_QOR_EXECUTED" }
  if {[catch { report_clock_utilization -file ./routed_clock_utilization.rpt } e]} { puts "AH_ROUTE_RPT_CLK_ERR $e" } else { puts "AH_ROUTE_CLK_EXECUTED" }
  # check_timing: TD exposes one of these names depending on the build; try both
  # and record which one worked instead of silently skipping the check.
  if {[catch { check_timing -verbose -file ./routed_check_timing.rpt } e]} {
    puts "AH_ROUTE_CHECK_TIMING_CMD1_ERR $e"
    if {[catch { report_check_timing -file ./routed_check_timing.rpt } e2]} {
      puts "AH_ROUTE_CHECK_TIMING_UNAVAILABLE $e2"
    } else { puts "AH_ROUTE_CHECK_TIMING_VIA_REPORT_EXECUTED" }
  } else { puts "AH_ROUTE_CHECK_TIMING_EXECUTED" }
  # single-clock design: report_cdc is still run so the claim is evidenced
  if {[catch { report_cdc -file ./routed_cdc.rpt } e]} { puts "AH_ROUTE_RPT_CDC_ERR $e" } else { puts "AH_ROUTE_CDC_EXECUTED" }
  puts "AH_ROUTE_PRDB=$prdb AH_ROUTE_NO_BITGEN=1 AH_ROUTE_NO_CWC=1 AH_ROUTE_NO_DOWNLOAD=1"
} else {
  puts "AH_ROUTE_NO_PR_DB path=$prdb"
}

if {![file exists ./routed_timing_summary.rpt]} { puts "AH_ROUTE_TIMING_SUMMARY_MISSING"; exit 1 }
puts "AH_ROUTE_RUN_COMPLETE"
exit 0