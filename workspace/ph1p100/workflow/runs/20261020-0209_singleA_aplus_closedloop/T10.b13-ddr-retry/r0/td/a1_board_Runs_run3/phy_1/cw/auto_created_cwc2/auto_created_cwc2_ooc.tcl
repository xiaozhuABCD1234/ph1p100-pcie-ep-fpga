# This is a default Tcl file for ChipWatcher OOC flow.

import_device ph1_100p.db -package PH1P100SBG484

# Enable OOC (Out-of_Context) flow
set_param flow ooc_flow on

# Run synthesis flow
read_verilog -file "auto_created_cwc2_watcherInst.sv"
optimize_rtl
map_macro
map
pack

# Export area and database files
report_area -file auto_created_cwc2_gate.area
export_db -mode ooc auto_created_cwc2_ooc.db
exit

