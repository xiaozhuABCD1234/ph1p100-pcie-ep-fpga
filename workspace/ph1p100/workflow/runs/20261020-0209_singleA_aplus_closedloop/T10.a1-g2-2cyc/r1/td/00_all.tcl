# =============================================================================
# 00_all.tcl - T10.a1-g2-2cyc r0: one TD session, syn_1 + conditional phy_1.
# Same a1_eng_top and 187.5 MHz SDC. No bitgen, no download, no seed change.
# =============================================================================
set PRJ_ROOT "Y:/upstream/ph1p100-pcie-ep-fpga"

create_project a1_g2_r1 ./ -family PH1 -device PH1P100SBG484 -speed 3 -force

add_files $PRJ_ROOT/rtl/ep_side/codec/a1_frame_top.v
add_files $PRJ_ROOT/rtl/ep_side/codec/a1_deflate_core.v
add_files ./a1_eng_top.v
add_files ./a1_small_top.sdc
top_module a1_eng_top

launch_runs { syn_1 } -jobs 4
wait_run syn_1 -quiet

set tag "s2"
if { [info exists ::env(A1_TD_TAG)] } { set tag $::env(A1_TD_TAG) }
set tf "./a1_g2_r1_Runs/syn_1/a1_g2_r1_gate.timing"
if { [file exists $tf] } { file copy -force $tf ./syn_gate_timing_$tag.rpt }
set syn_wns -99.0
if { [file exists $tf] } {
    set fh [open $tf r]
    set txt [read $fh]
    close $fh
    if { [regexp {SWNS:\s*(-?[0-9.]+)ns} $txt -> w] } { set syn_wns $w }
}
puts "SYN_SWNS=$syn_wns"

if { $syn_wns >= 0.0 } {
    puts "SYN_TIMING_OK launching phy_1"
    launch_runs { phy_1 } -jobs 4
    wait_run phy_1 -quiet
    if { [catch { open_run phy_1 } e] } { puts "open_run(phy) skipped: $e" }
    if { [catch { report_timing_summary -file phy_timing_summary.rpt } e] } { puts "report_timing_summary skipped: $e" }
    if { [catch { report_timing_status  -file phy_timing_status.rpt } e] } { puts "report_timing_status skipped: $e" }
    if { [catch { report_area            -file phy_area.rpt } e] } { puts "report_area(phy) skipped: $e" }
    if { [catch { report_clock_utilization -file phy_clock_util.rpt } e] } { puts "report_clock_utilization skipped: $e" }
    if { [catch { report_cdc -file cdc.rpt } e] } { puts "report_cdc skipped: $e" }
    if { [catch { report_timing -file phy_timing.rpt } e] } { puts "report_timing skipped: $e" }
    if { [catch { check_timing -file check_timing.rpt } e] } { puts "check_timing skipped: $e" }
} else {
    puts "SYN_WNS_NEG stop_before_route"
}

puts "A1_TD_g2_r0_DONE"
exit
