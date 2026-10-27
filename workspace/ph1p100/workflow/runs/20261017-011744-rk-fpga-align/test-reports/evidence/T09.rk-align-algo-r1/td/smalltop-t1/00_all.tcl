# =============================================================================
#  00_all.tcl - T09.rk-align-algo module-level small top (G2 build vehicle
#  img_algo_top_g2, which contains the real parallel organisation
#  img_algo_parallel_top plus a thin pin-level wrapper).
#  Single-session flow: create_project -> syn -> phy -> bit.
#  Device/package/speed match the main project (PH1P100SBG484 speed 3).
#  No IP, no DDR/PCIe; minimal pin constraints (the rest auto-placed).
#  Does NOT download, write Flash or touch other projects.
#  Usage (cwd = the TD project dir; S:/ is the mapped project root):
#     td_commands_prompt.exe 00_all.tcl
# =============================================================================

set PRJ_ROOT  "S:/fpga/csi2/src/img"
set CONS_ROOT "S:/tools/algo/td"

create_project ph1p_algo_smalltop ./ -family PH1 -device PH1P100SBG484 -speed 3 -force

add_files $PRJ_ROOT/algo_rowwin_reader.v
add_files $PRJ_ROOT/algo_rowwin3.v
add_files $PRJ_ROOT/algo_obuf.v
add_files $PRJ_ROOT/bayer_raw10_demosaic4.v
add_files $PRJ_ROOT/gray8_gaussian3x3_stream.v
add_files $PRJ_ROOT/gray8_he_cdfmin_frame.v
add_files $PRJ_ROOT/rgb8_gray_stream.v
add_files $PRJ_ROOT/img_algo_parallel_top.v
add_files $PRJ_ROOT/img_algo_top_g2.v

add_files $CONS_ROOT/img_algo_top.sdc
add_files $CONS_ROOT/img_algo_top.adc

top_module img_algo_top_g2

launch_runs { syn_1 } -jobs 4
wait_run syn_1 -quiet
if { [catch { report_area   -file syn_area.rpt }  e] } { puts "report_area(syn) skipped: $e" }
if { [catch { report_timing -file syn_timing.rpt } e] } { puts "report_timing(syn) skipped: $e" }

launch_runs { phy_1 } -jobs 4
wait_run phy_1 -quiet
if { [catch { report_area   -file phy_area.rpt }  e] } { puts "report_area(phy) skipped: $e" }
if { [catch { report_timing -file phy_timing.rpt } e] } { puts "report_timing(phy) skipped: $e" }
save_best_bits

puts "T09_ALGO_ALL_DONE"

exit
