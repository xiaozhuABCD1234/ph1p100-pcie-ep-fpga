# =============================================================================
# 00_all.tcl - T10.a1-eng-freeze P4 small-top G2 build (a1_frame_top + a1_deflate_core)
#   Single TD session: create -> syn -> phy -> reports -> bits.
#   Usage (cwd = project dir, ASCII subst drive):
#     td_commands_prompt.exe X:/00_all.tcl
#   No download, no Flash, no production project touched.
# =============================================================================

set PRJ_ROOT "Y:/upstream/ph1p100-pcie-ep-fpga"

create_project a1_eng_freeze ./ -family PH1 -device PH1P100SBG484 -speed 3 -force

add_files $PRJ_ROOT/rtl/ep_side/codec/a1_frame_top.v
add_files $PRJ_ROOT/rtl/ep_side/codec/a1_deflate_core.v
add_files ./a1_eng_top.v
add_files ./a1_small_top.sdc
top_module a1_eng_top

# ---- synthesis ----
launch_runs { syn_1 } -jobs 4
wait_run syn_1 -quiet
if { [catch { report_area   -file syn_area.rpt }  e] } { puts "report_area(syn) skipped: $e" }
if { [catch { report_timing -file syn_timing.rpt } e] } { puts "report_timing(syn) skipped: $e" }

# ---- place & route ----
launch_runs { phy_1 } -jobs 4
wait_run phy_1 -quiet
if { [catch { report_area   -file phy_area.rpt }  e] } { puts "report_area(phy) skipped: $e" }
if { [catch { report_timing -file phy_timing.rpt } e] } { puts "report_timing(phy) skipped: $e" }
if { [catch { report_timing_summary -file phy_timing_summary.rpt } e] } { puts "report_timing_summary skipped: $e" }
if { [catch { report_timing_status  -file phy_timing_status.rpt } e] } { puts "report_timing_status skipped: $e" }
if { [catch { report_clock_utilization -file phy_clock_util.rpt } e] } { puts "report_clock_utilization skipped: $e" }

# ---- CDC / timing sanity (record command availability, do not fake) ----
if { [catch { report_cdc -file cdc.rpt } e] } { puts "report_cdc skipped: $e" }
if { [catch { check_timing -file check_timing.rpt } e] } { puts "check_timing skipped: $e" }

save_best_bits

puts "A1_TD_DONE"
exit
