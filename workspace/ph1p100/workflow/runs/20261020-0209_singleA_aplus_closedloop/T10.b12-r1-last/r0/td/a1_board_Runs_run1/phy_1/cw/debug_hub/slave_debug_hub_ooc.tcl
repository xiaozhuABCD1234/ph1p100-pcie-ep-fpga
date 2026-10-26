# This is a default Tcl file for ChipWatcher OOC flow.

import_device ph1_100p.db -package PH1P100SBG484

# Enable OOC (Out-of_Context) flow
set_param flow ooc_flow on

# Run synthesis flow
read_verilog -file "debug_hub_wrapper.sv"
optimize_rtl
map_macro
map
pack

# Export area and database files
report_area -file slave_debug_hub_gate.area
export_db -mode ooc slave_debug_hub_ooc.db
exit

