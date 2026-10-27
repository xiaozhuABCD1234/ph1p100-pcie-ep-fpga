# 02_route.tcl - INT.P4 conditional route (route_max=1). Only valid if synth passed.
# NOT RUN in r0: TD rejected the design at MapIO (IO > 286) in synthesis, so no gate
# database exists.  Kept as the frozen entry for the next round with a board shell.
set prj "int_p4"
open_project ./$prj.al
import_db ./${prj}_Runs/syn_1/${prj}_gate.db
launch_runs { phy_1 } -jobs 4
wait_run phy_1 -quiet
if {[file exists ./${prj}_Runs/phy_1/${prj}_pr.db]} {
  import_db ./${prj}_Runs/phy_1/${prj}_pr.db
  update_timing -mode final
  report_timing_summary -file ./routed_timing_summary.rpt
  report_timing_status -file ./routed_timing_status.rpt
  report_area -io_info -file ./routed_area.rpt
} else { puts "INT_ROUTE_NO_PR_DB" }
exit