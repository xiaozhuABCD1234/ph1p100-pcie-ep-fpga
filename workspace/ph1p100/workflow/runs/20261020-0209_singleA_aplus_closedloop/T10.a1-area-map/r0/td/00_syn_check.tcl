# =============================================================================
# 00_syn_check.tcl - T10.a1-area-map r0 session 1: synthesis-only resource
# checkpoint.  cmem single write port (ERAM mapping experiment); 187.5 MHz SDC;
# no route, no bitgen, no download.  A1_TD_TAG names the copied timing report.
# =============================================================================
set PRJ_ROOT "Y:/upstream/ph1p100-pcie-ep-fpga"

create_project a1_am_r0 ./ -family PH1 -device PH1P100SBG484 -speed 3 -force

add_files $PRJ_ROOT/rtl/ep_side/codec/a1_frame_top.v
add_files $PRJ_ROOT/rtl/ep_side/codec/a1_deflate_core.v
add_files ./a1_eng_top.v
add_files ./a1_small_top.sdc
top_module a1_eng_top

launch_runs { syn_1 } -jobs 4
wait_run syn_1 -quiet

set tag "s1"
if { [info exists ::env(A1_TD_TAG)] } { set tag $::env(A1_TD_TAG) }
set tf "./a1_am_r0_Runs/syn_1/a1_am_r0_gate.timing"
if { [file exists $tf] } { file copy -force $tf ./syn_gate_timing_$tag.rpt }
set syn_wns -99.0
if { [file exists $tf] } {
    set fh [open $tf r]
    set txt [read $fh]
    close $fh
    if { [regexp {SWNS:\s*(-?[0-9.]+)ns} $txt -> w] } { set syn_wns $w }
}
puts "SYN_SWNS=$syn_wns"

set af "./a1_am_r0_Runs/syn_1/a1_am_r0_gate.area"
if { [file exists $af] } {
    set fh [open $af r]
    set atxt [read $fh]
    close $fh
    set sl -1
    set er -1
    set rg -1
    regexp {#slice\*\s+([0-9]+)} $atxt -> sl
    regexp {#eram\s+([0-9]+)} $atxt -> er
    regexp {#reg\s+([0-9]+)} $atxt -> rg
    puts "SYN_SLICE=$sl"
    puts "SYN_ERAM=$er"
    puts "SYN_REG=$rg"
}
puts "A1_am_r0_syn_DONE"
exit
