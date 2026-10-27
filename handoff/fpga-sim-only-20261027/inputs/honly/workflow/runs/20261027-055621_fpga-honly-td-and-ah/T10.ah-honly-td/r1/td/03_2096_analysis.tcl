# =============================================================================
# 03_2096_analysis.tcl - ANALYSIS-ONLY tightened-clock check.  NOT a 209.6 MHz
# routed result and must never be reported as one.
#
# What it does: re-open the SAME routed database produced by 02_route.tcl, replace
# the 5.333 ns clock constraint by 4.777 ns (209.6 MHz) and re-run timing
# analysis only.  No placement, no routing, no bitgen, no database write.
#
# Round r1: analysis-only, only after a routed DB exists.  cwd = r1/td/run-route1; invoke:
#   D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe ./03_2096_analysis.tcl
# =============================================================================
set prj "a1_ah"
set prdb "./${prj}_Runs/phy_1/${prj}_pr.db"

puts "AH_2096_ANALYSIS_ONLY=1 NOTE=not_a_routed_209.6MHz_result"
if {![file exists "./${prj}.al"]} { puts "AH_2096_NO_PROJECT"; exit 1 }
open_project ./$prj.al
if {![file exists $prdb]} { puts "AH_2096_NO_PR_DB path=$prdb"; exit 1 }
import_db $prdb

# same name/source as the 187.5 MHz constraint -> replaces it; still one clock.
if {[catch { create_clock -name clk -period 4.777 -waveform {0.000 2.3885} [get_ports clk] } e]} {
  puts "AH_2096_CLOCK_ERR $e"
  puts "AH_2096_SKIPPED_NO_CLOCK_OVERRIDE"
  exit 1
} else {
  puts "AH_2096_CLOCK_APPLIED period_ns=4.777 waveform={0.000 2.3885}"
}
update_timing -mode final
if {[catch { report_timing_summary -file ./analysis_2096_timing_summary.rpt } e]} { puts "AH_2096_RPT_TS_ERR $e" }
if {[catch { report_timing -file ./analysis_2096_timing.rpt } e]} { puts "AH_2096_RPT_TIMING_ERR $e" }
puts "AH_2096_NO_BITGEN=1 AH_2096_NO_DB_WRITE=1"

if {![file exists ./analysis_2096_timing_summary.rpt]} { puts "AH_2096_REPORT_MISSING"; exit 1 }
puts "AH_2096_ANALYSIS_COMPLETE"
exit 0