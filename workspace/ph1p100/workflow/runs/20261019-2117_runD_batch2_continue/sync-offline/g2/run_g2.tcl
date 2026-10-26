# T08 offline small-top G2: one TD session, synthesis + place/route + reports.
# Standalone carrier only. No download, no Flash, no bit/CWC board claim.
set G2   [file normalize [file dirname [info script]]]
set ROOT [file normalize [file join $G2 ../../../../..]]
set RTL  [file join $ROOT upstream ph1p100-pcie-ep-fpga rtl ep_side cam sync_offline]

create_project sync_offline_g2 ./ -family PH1 -device PH1P100SBG484 -speed 3 -force
# Standalone carrier: pin locations are synthetic/auto and this project is never
# downloaded. Allow the flow's bitgen stage to pass without an ADC pin claim.
set_param bitgen unconstr_io on

add_files [file join $RTL sync_offline_top.v]
add_files [file join $RTL sync_reset.v]
add_files [file join $RTL sync_sof_mailbox.v]
add_files [file join $RTL sync_sof_pair.v]
add_files [file join $RTL sync_start_ctrl.v]
add_files $ROOT/workflow/runs/20261019-2117_runD_batch2_continue/sync-offline/g2/sync_offline_g2.v
add_files $ROOT/workflow/runs/20261019-2117_runD_batch2_continue/sync-offline/g2/sync_offline_g2.sdc

top_module sync_offline_g2

puts "T08_G2_SYN_START"
launch_runs { syn_1 } -jobs 4
wait_run syn_1 -quiet
if { [catch { report_area   -file syn_area.rpt }  e] } { puts "report_area(syn) skipped: $e" }
if { [catch { report_timing -file syn_timing.rpt } e] } { puts "report_timing(syn) skipped: $e" }

puts "T08_G2_PHY_START"
launch_runs { phy_1 } -jobs 4
wait_run phy_1 -quiet

if { [catch { report_area              -file phy_area.rpt }     e] } { puts "report_area(phy) skipped: $e" }
if { [catch { report_timing            -file phy_timing.rpt }   e] } { puts "report_timing(phy) skipped: $e" }
if { [catch { report_timing_status     -file phy_status.ts }    e] } { puts "report_timing_status skipped: $e" }
if { [catch { report_timing_summary    -file phy_summary.timing } e] } { puts "report_timing_summary skipped: $e" }
if { [catch { report_timing_exception  -file phy_exception.timing } e] } { puts "report_timing_exception skipped: $e" }
if { [catch { report_clock_utilization -file phy_clock_utilization.txt } e] } { puts "report_clock_utilization skipped: $e" }

puts "T08_G2_DONE"
exit
