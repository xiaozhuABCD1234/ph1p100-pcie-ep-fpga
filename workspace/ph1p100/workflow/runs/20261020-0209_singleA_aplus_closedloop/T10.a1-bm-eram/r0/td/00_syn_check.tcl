set PRJ_ROOT "Y:/upstream/ph1p100-pcie-ep-fpga"
create_project a1_bm_r0f ./ -family PH1 -device PH1P100SBG484 -speed 3 -force
add_files $PRJ_ROOT/rtl/ep_side/codec/a1_frame_top.v
add_files $PRJ_ROOT/rtl/ep_side/codec/a1_deflate_core.v
add_files ./a1_eng_top.v
add_files ./a1_small_top.sdc
top_module a1_eng_top
launch_runs { syn_1 } -jobs 4
wait_run syn_1 -quiet
set tf "./a1_bm_r0f_Runs/syn_1/a1_bm_r0f_gate.timing"
set af "./a1_bm_r0f_Runs/syn_1/a1_bm_r0f_gate.area"
if {[file exists $tf]} { file copy -force $tf ./syn_gate_timing.rpt }
if {[file exists $af]} { file copy -force $af ./syn_gate_area.rpt }
set syn_wns -99.0
if {[file exists $tf]} { set fh [open $tf r]; set txt [read $fh]; close $fh
  if {[regexp {SWNS:\s*(-?[0-9.]+)ns} $txt -> w]} { set syn_wns $w } }
puts "SYN_SWNS=$syn_wns"
if {[file exists $af]} { set fh [open $af r]; set atxt [read $fh]; close $fh
  regexp {#slice\*\s+([0-9]+)} $atxt -> sl; puts "SYN_SLICE=$sl"
  regexp {#eram\s+([0-9]+)} $atxt -> er; puts "SYN_ERAM=$er"
  regexp {#reg\s+([0-9]+)} $atxt -> rg; puts "SYN_REG=$rg" }
puts "A1_bm_syn_DONE"
exit
