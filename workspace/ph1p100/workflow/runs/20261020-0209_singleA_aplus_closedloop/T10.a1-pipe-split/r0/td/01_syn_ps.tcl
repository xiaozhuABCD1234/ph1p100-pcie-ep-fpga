# =============================================================================
# T10.a1-pipe-split r0 -- session 1: synthesis inspection only (no route)
# RTL: core = rng1_r stage-1 registration (working tree), frame 18d51b1b, SDC 227dd39e.
# Strategy: syn retiming on (frozen group-1 strategy, no seed sweep).
# T: = this package r0/td ; Y: = project root (tools/td/td_env.ps1).
# No bitgen, no .bit, no download. Reports direct -file.
# =============================================================================
set PRJ_ROOT "Y:/upstream/ph1p100-pcie-ep-fpga"
set prj "a1_ps"
create_project $prj ./ -family PH1 -device PH1P100SBG484 -speed 3 -force
add_files $PRJ_ROOT/rtl/ep_side/codec/a1_frame_top.v
add_files $PRJ_ROOT/rtl/ep_side/codec/a1_deflate_core.v
add_files ./a1_eng_top.v
add_files ./a1_small_top.sdc
top_module a1_eng_top

# ---- frozen strategy: retiming on (group 1) ---------------------------------
if {[catch { set_param -run syn_1 rtl retiming on } e]} {
  puts "PS_SYN_PARAM_ERR $e"
  if {[catch { set_param rtl retiming on } e2]} { puts "PS_SYN_PARAM_FALLBACK_ERR $e2" } else { puts "PS_SYN_PARAM_FALLBACK_OK rtl retiming on" }
} else { puts "PS_SYN_PARAM_OK rtl retiming on" }

# ---- synthesis --------------------------------------------------------------
launch_runs { syn_1 } -jobs 4
if {[catch { wait_run syn_1 -quiet } e]} { puts "SYN_WAIT_ERR $e" }
set tf "./${prj}_Runs/syn_1/${prj}_gate.timing"
set af "./${prj}_Runs/syn_1/${prj}_gate.area"
if {[file exists $tf]} { file copy -force $tf ./syn_gate_timing_ps.rpt }
if {[file exists $af]} { file copy -force $af ./syn_gate_area_ps.rpt }

set syn_wns -99.0; set syn_tns -99.0; set syn_slice -1; set syn_eram -1
set syn_reg -1; set syn_dram -1
if {[file exists $tf]} {
  set fh [open $tf r]; set txt [read $fh]; close $fh
  if {[regexp {SWNS:\s*(-?[0-9.]+)ns} $txt -> w]} { set syn_wns $w }
  if {[regexp {STNS:\s*(-?[0-9.]+)ns} $txt -> w]} { set syn_tns $w }
}
if {[file exists $af]} {
  set fh [open $af r]; set atxt [read $fh]; close $fh
  if {[regexp {#slice\*\s+([0-9]+)} $atxt -> sl]} { set syn_slice $sl }
  if {[regexp {#eram\s+([0-9]+)} $atxt -> er]} { set syn_eram $er }
  if {[regexp {#reg\s+([0-9]+)} $atxt -> rg]} { set syn_reg $rg }
  if {[regexp {#dram lut\s+([0-9]+)} $atxt -> dr]} { set syn_dram $dr }
}
puts "PS_SYN_SWNS=$syn_wns PS_SYN_STNS=$syn_tns PS_SYN_SLICE=$syn_slice PS_SYN_ERAM=$syn_eram PS_SYN_REG=$syn_reg PS_SYN_DRAM=$syn_dram"

# ---- gate db: extra direct -file reports + netlist for the static scan ------
if {[catch { import_db ./${prj}_Runs/syn_1/${prj}_gate.db } e]} { puts "IMPORT_GATE_ERR $e" } else {
  if {[catch { update_timing -mode final } e]} { puts "UPDATE_TIMING_ERR $e" }
  if {[catch { report_timing_summary -file ./syn_gate_timing_summary.rpt } e]} { puts "RPT_TS_ERR $e" } else { puts "SYN_TIMING_SUMMARY_EXECUTED" }
  if {[catch { report_timing -file ./syn_gate_timing_paths.rpt } e]} { puts "RPT_TIMING_ERR $e" } else { puts "SYN_TIMING_EXECUTED" }
  if {[catch { report_area -io_info -file ./syn_gate_area_direct.rpt } e]} { puts "RPT_AREA_ERR $e" } else { puts "SYN_AREA_EXECUTED" }
  if {[catch { report_clock_utilization -file ./syn_gate_clock_utilization.rpt } e]} { puts "RPT_CLK_ERR $e" } else { puts "SYN_CLOCK_UTIL_EXECUTED" }
  if {[catch { write_verilog ./ps_gate_netlist.v } e]} { puts "WV_GATE_ERR $e" } else { puts "WV_GATE_OK" }
}
if {[catch { import_db ./${prj}_Runs/syn_1/${prj}_elaborate.db } e]} { puts "IMPORT_ELAB_ERR $e" } else {
  if {[catch { write_verilog ./ps_elab_netlist.v } e]} { puts "WV_ELAB_ERR $e" } else { puts "WV_ELAB_OK" }
}
puts "A1_PS_SYN_DONE"
exit
