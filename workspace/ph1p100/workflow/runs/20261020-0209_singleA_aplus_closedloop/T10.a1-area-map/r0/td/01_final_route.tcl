# =============================================================================
# 01_final_route.tcl - T10.a1-area-map r0 session 2: final synthesis + the one
# authorized route at 187.5 MHz.  Refuses to launch phy_1 unless the gate-stage
# slice count is <= 71680 and SWNS >= 0.  No bitgen, no download, no seed sweep.
# =============================================================================
set PRJ_ROOT "Y:/upstream/ph1p100-pcie-ep-fpga"

create_project a1_am_r0f ./ -family PH1 -device PH1P100SBG484 -speed 3 -force

add_files $PRJ_ROOT/rtl/ep_side/codec/a1_frame_top.v
add_files $PRJ_ROOT/rtl/ep_side/codec/a1_deflate_core.v
add_files ./a1_eng_top.v
add_files ./a1_small_top.sdc
top_module a1_eng_top

launch_runs { syn_1 } -jobs 4
wait_run syn_1 -quiet

set tag "s2"
if { [info exists ::env(A1_TD_TAG)] } { set tag $::env(A1_TD_TAG) }
set tf "./a1_am_r0f_Runs/syn_1/a1_am_r0f_gate.timing"
if { [file exists $tf] } { file copy -force $tf ./syn_gate_timing_$tag.rpt }
set syn_wns -99.0
if { [file exists $tf] } {
    set fh [open $tf r]
    set txt [read $fh]
    close $fh
    if { [regexp {SWNS:\s*(-?[0-9.]+)ns} $txt -> w] } { set syn_wns $w }
}
puts "SYN_SWNS=$syn_wns"

set af "./a1_am_r0f_Runs/syn_1/a1_am_r0f_gate.area"
set syn_slice -1
if { [file exists $af] } {
    set fh [open $af r]
    set atxt [read $fh]
    close $fh
    regexp {#slice\*\s+([0-9]+)} $atxt -> syn_slice
    puts "SYN_SLICE=$syn_slice"
    set er -1
    regexp {#eram\s+([0-9]+)} $atxt -> er
    puts "SYN_ERAM=$er"
    set rg -1
    regexp {#reg\s+([0-9]+)} $atxt -> rg
    puts "SYN_REG=$rg"
}

if { ($syn_wns >= 0.0) && ($syn_slice > 0) && ($syn_slice <= 71680) } {
    puts "SYN_GATE_OK launching phy_1"
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
    puts "SYN_GATE_STOP no_route (wns=$syn_wns slice=$syn_slice)"
}

puts "A1_am_r0_final_DONE"
exit
