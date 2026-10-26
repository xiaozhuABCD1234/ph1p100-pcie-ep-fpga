# T10.a1-bm-prefetch r2-waive -- read-only report pass on the already routed DB.
# No synthesis, no route, no bitgen, no RTL/DB modification.  All reports are
# written directly by the tool (-file) into T:/ and archived afterwards.
import_device ph1_100p.db -package PH1P100SBG484 -speed 3
open_project ./a1_bp_r2.al
puts "PROJECT_OPENED"
if {[catch { import_db ./a1_bp_r2_Runs/phy_1/a1_bp_r2_pr.db } e]} { puts "IMPORT_DB_ERR $e" } else { puts "DB_IMPORTED" }
if {[catch { update_timing -mode final } e]} { puts "UPDATE_TIMING_ERR $e" } else { puts "UPDATE_TIMING_OK" }

if {[catch { report_timing_summary -file routed_timing_summary.rpt } e]} { puts "RPT_TS_ERR $e" } else { puts "TIMING_SUMMARY_EXECUTED" }
if {[catch { report_timing_status -file routed_timing_status.rpt } e]} { puts "RPT_TST_ERR $e" } else { puts "TIMING_STATUS_EXECUTED" }
if {[catch { check_timing -verbose -file routed_check_timing.rpt } e]} { puts "RPT_CHK_ERR $e" } else { puts "CHECK_TIMING_EXECUTED" }
if {[catch { report_clock_utilization -file routed_clock_utilization.rpt } e]} { puts "RPT_CLK_ERR $e" } else { puts "CLOCK_UTIL_EXECUTED" }
if {[catch { report_timing -file routed_timing.rpt } e]} { puts "RPT_TIMING_ERR $e" } else { puts "TIMING_EXECUTED" }
if {[catch { report_area -io_info -file routed_area.rpt } e]} { puts "RPT_AREA_ERR $e" } else { puts "AREA_EXECUTED" }
if {[catch { report_qor -step route -file routed_qor.rpt } e]} { puts "RPT_QOR_ERR $e" } else { puts "QOR_EXECUTED" }
if {[catch { report_clocks -file routed_clocks.rpt } e]} { puts "RPT_CLOCKS_UNAVAILABLE $e" } else { puts "REPORT_CLOCKS_EXECUTED" }

# Directed enumeration of the bm/htab ERAM clk2q start points.  Each variant is
# guarded; the verbatim error is kept so coverage limits stay evidence.
if {[catch { report_timing -from [get_pins -hierarchical {*bm_a*}] -file directed_bm_a_pins.rpt } e]} { puts "DIRECTED_BMA_PINS_UNAVAILABLE $e" } else { puts "DIRECTED_BMA_PINS_EXECUTED" }
if {[catch { report_timing -from [get_cells -hierarchical {*bm_a*}] -file directed_bm_a_cells.rpt } e]} { puts "DIRECTED_BMA_CELLS_UNAVAILABLE $e" } else { puts "DIRECTED_BMA_CELLS_EXECUTED" }
if {[catch { report_timing -from [get_pins -hierarchical {*bm_b*}] -file directed_bm_b_pins.rpt } e]} { puts "DIRECTED_BMB_PINS_UNAVAILABLE $e" } else { puts "DIRECTED_BMB_PINS_EXECUTED" }
if {[catch { report_timing -from [get_pins -hierarchical {*htab*}] -file directed_htab_pins.rpt } e]} { puts "DIRECTED_HTAB_PINS_UNAVAILABLE $e" } else { puts "DIRECTED_HTAB_PINS_EXECUTED" }
if {[catch { report_timing -max_paths 3000 -file routed_timing_top3000.rpt } e]} { puts "TOP3000_UNAVAILABLE $e" } else { puts "TOP3000_EXECUTED" }
foreach f {routed_timing_summary.rpt routed_check_timing.rpt routed_clock_utilization.rpt routed_timing.rpt directed_bm_a_pins.rpt directed_bm_a_cells.rpt directed_bm_b_pins.rpt directed_htab_pins.rpt routed_timing_top3000.rpt} {
  if {[file exists ./$f]} { puts "FILE_OK $f [file size ./$f]" } else { puts "FILE_MISSING $f" }
}
puts "A1_BMPREFETCH_r2waive_reports_DONE"
exit
