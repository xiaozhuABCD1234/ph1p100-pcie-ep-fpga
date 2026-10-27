# INT.P4 integrated delivery: isolated synthesis (round2).
# Quota (planner-granted, dispatch.td_policy): 3 additional synth this round,
# lifetime cap 6 (r0/r1 used 3).  No bitgen, no CWC, no download, no Flash.
#
# Project lives only in workflow/runs/<run>/INT.P4/td.  All RTL is referenced by
# absolute read-only path.  Top is the SYNTHESIS-ONLY harness
# (tools/integrated_delivery/synth/integrated_delivery_synth_wrap.v) which
# instantiates the frozen integrated_delivery_top unchanged and replaces the
# ~2800 off-chip pins with on-chip capture / DDR / descriptor / PCIe / monitor
# models, so TD MapIO can map the design inside the 286-pin device.
# No pin, ADC or timing exception is fabricated; IO timing stays unconstrained
# (recorded G2 gap).  See the harness header for the coverage boundary.
#
# r2 changes vs r1:
#   * the r2 derived timing variants are compiled (bayer_raw10_demosaic4_p4.v,
#     img_algo_parallel_top_p4.v);
#   * the reported violation count is the REAL "Viol Endpoints" statistic from
#     flow.status / the timing report (r1 counted printed "Slack : -" lines and
#     reported 10 instead of 330).  The printed-path count is still emitted,
#     clearly labelled as `INT_SYN_PRINTED_PATHS`, never as the endpoint count.
set prj "int_p4"
create_project $prj ./ -family PH1 -device PH1P100SBG484 -force
# ------------- frozen candidate (same files the simulation binds) -------------
add_files D:/fpga/ph1p100/fpga/csi2/src/integrated_delivery/integrated_delivery_top.v
add_files D:/fpga/ph1p100/fpga/csi2/src/integrated_delivery/integrated_input_processing_top.v
add_files D:/fpga/ph1p100/fpga/csi2/src/integrated_delivery/raw10_sample_vector_to_packed.v
add_files D:/fpga/ph1p100/fpga/csi2/src/integrated_delivery/frame_good_publish_cancel.v
add_files D:/fpga/ph1p100/fpga/csi2/src/integrated_delivery/aplus_pcie_egress_adapter.v
add_files D:/fpga/ph1p100/fpga/csi2/src/integrated_delivery/dual_channel_capture_scheduler.v
# r2 timing-only derived variants (base img/** stays read-only)
add_files D:/fpga/ph1p100/fpga/csi2/src/integrated_delivery/bayer_raw10_demosaic4_p4.v
add_files D:/fpga/ph1p100/fpga/csi2/src/integrated_delivery/img_algo_parallel_top_p4.v
add_files D:/fpga/ph1p100/fpga/csi2/src/integrated_delivery/algo_rowwin3_p4.v
add_files D:/fpga/ph1p100/fpga/csi2/src/integrated_delivery/gray8_gaussian3x3_stream_p4.v
# b20 r0 A+ core, read-only candidate paths
add_files D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b20-a-timing/r0/changed-src/a1_frame_top.v
add_files D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b20-a-timing/r0/changed-src/a1_deflate_core.v
add_files D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b20-a-timing/r0/changed-src/a1_ddr_slot_store.v
add_files D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b20-a-timing/r0/changed-src/a1_ddr_arb2.v
# 10 frozen img sources (read-only; all ten are compiled)
add_files D:/fpga/ph1p100/fpga/csi2/src/img/algo_obuf.v
add_files D:/fpga/ph1p100/fpga/csi2/src/img/algo_rowwin3.v
add_files D:/fpga/ph1p100/fpga/csi2/src/img/algo_rowwin_reader.v
add_files D:/fpga/ph1p100/fpga/csi2/src/img/bayer_raw10_demosaic4.v
add_files D:/fpga/ph1p100/fpga/csi2/src/img/gray8_gaussian3x3_frame.v
add_files D:/fpga/ph1p100/fpga/csi2/src/img/gray8_gaussian3x3_stream.v
add_files D:/fpga/ph1p100/fpga/csi2/src/img/gray8_he_cdfmin_frame.v
add_files D:/fpga/ph1p100/fpga/csi2/src/img/img_algo_parallel_top.v
add_files D:/fpga/ph1p100/fpga/csi2/src/img/img_algo_top_g2.v
add_files D:/fpga/ph1p100/fpga/csi2/src/img/rgb8_gray_stream.v
# ------------- synthesis-only harness (not a board shell) --------------------
add_files D:/fpga/ph1p100/tools/integrated_delivery/synth/integrated_delivery_synth_wrap.v
add_files ./integrated_core.sdc
top_module integrated_delivery_synth_wrap
launch_runs { syn_1 } -jobs 4
if {[catch { wait_run syn_1 -quiet } e]} { puts "INT_SYN_WAIT_ERR $e" }
set tf "./${prj}_Runs/syn_1/${prj}_gate.timing"
set af "./${prj}_Runs/syn_1/${prj}_gate.area"
set fs "./${prj}_Runs/syn_1/flow.status"
if {[file exists $tf]} { file copy -force $tf ./syn_gate_timing.rpt }
if {[file exists $af]} { file copy -force $af ./syn_gate_area.rpt }
if {[file exists $fs]} { file copy -force $fs ./syn_flow.status }

set syn_wns   -99.0
set syn_tns   -99.0
set syn_hwns  -99.0
set syn_htns  -99.0
set syn_period -99.0
set syn_viol  -1
set syn_totep -1
set syn_printed -1
set syn_cov    "n/a"
set syn_io     -1
set syn_eram   -1
set syn_cwc    -1
set syn_reg    -1
set syn_slice  -1
set syn_dsp    -1

if {[file exists $tf]} {
  set fh [open $tf r]; set txt [read $fh]; close $fh
  if {[regexp {SWNS:\s*(-?[0-9.]+)ns} $txt -> w]} { set syn_wns $w }
  if {[regexp {STNS:\s*(-?[0-9.]+)ns} $txt -> w]} { set syn_tns $w }
  if {[regexp {HWNS:\s*(-?[0-9.]+)ns} $txt -> w]} { set syn_hwns $w }
  if {[regexp {HTNS:\s*(-?[0-9.]+)ns} $txt -> w]} { set syn_htns $w }
  if {[regexp {Period Check WNS:\s*(-?[0-9.]+)ns} $txt -> w]} { set syn_period $w }
  if {[regexp {STA coverage\s*:\s*([0-9.]+)} $txt -> w]} { set syn_cov $w }
  # real endpoint statistics from the report header
  if {[regexp {Max\s*:\s*SWNS\s+-?[0-9.]+ns,\s*STNS\s+-?[0-9.]+ns,\s*([0-9]+)\s+Viol Endpoints,\s*([0-9]+)\s+Total Endpoints} $txt -> v tot]} {
    set syn_viol $v
    set syn_totep $tot
  }
  # helper metric only: how many paths the report prints (NOT an endpoint count)
  set syn_printed 0
  foreach {- v} [regexp -all -inline {Slack\s*:\s*(-[0-9.]+)\s*ns} $txt] {
    incr syn_printed
  }
}
# flow.status is the authoritative statistics source; it overrides the report
# header when present so both are cross-checked in the console log.
set syn_viol_fs -1
set syn_tns_ps  "n/a"
if {[file exists $fs]} {
  set fh [open $fs r]; set ftxt [read $fh]; close $fh
  if {[regexp {Setup\s*:\s*WNS\s+(-?[0-9]+)ps\s+TNS\s+(-?[0-9]+)ps\s+NUM_FEPS\s+([0-9]+)} $ftxt -> wps tps nfe]} {
    set syn_viol_fs $nfe
    set syn_tns_ps  "$tps ps"
  }
  if {[regexp {Hold\s*:\s*WNS\s+(-?[0-9]+)ps\s+TNS\s+(-?[0-9]+)ps\s+NUM_FEPS\s+([0-9]+)} $ftxt -> hw ht hn]} {
    set syn_hviol $hn
  }
}
if {$syn_viol_fs >= 0} { set syn_viol $syn_viol_fs }
if {[file exists $af]} {
  set fh [open $af r]; set atxt [read $fh]; close $fh
  if {[regexp {#IO\s+([0-9]+)} $atxt -> v]} { set syn_io $v }
  if {[regexp {#eram\s+([0-9]+)} $atxt -> v]} { set syn_eram $v }
  if {[regexp {#fifo20k\s+([0-9]+)} $atxt -> v]} { set syn_cwc $v }
  if {[regexp {#reg\s+([0-9]+)} $atxt -> v]} { set syn_reg $v }
  if {[regexp {#slice\*\s+([0-9]+)} $atxt -> v]} { set syn_slice $v }
  if {[regexp {#dsp\s+([0-9]+)} $atxt -> v]} { set syn_dsp $v }
}
set syn_eram_cwc [expr {$syn_eram + $syn_cwc}]
puts "INT_SYN_SPEED=default INT_SYN_COVERAGE=$syn_cov"
puts "INT_SYN_SWNS=$syn_wns INT_SYN_STNS=$syn_tns INT_SYN_HWNS=$syn_hwns INT_SYN_HTNS=$syn_htns"
puts "INT_SYN_PERIOD_WNS=$syn_period INT_SYN_TNS_PS='$syn_tns_ps'"
puts "INT_SYN_VIOL_ENDPOINTS=$syn_viol INT_SYN_VIOL_ENDPOINTS_FLOWSTATUS=$syn_viol_fs INT_SYN_TOTAL_ENDPOINTS=$syn_totep"
puts "INT_SYN_PRINTED_PATHS=$syn_printed"
puts "INT_SYN_IO=$syn_io INT_SYN_ERAM=$syn_eram INT_SYN_CWC=$syn_cwc INT_SYN_ERAM_CWC=$syn_eram_cwc INT_SYN_REG=$syn_reg INT_SYN_SLICE=$syn_slice INT_SYN_DSP=$syn_dsp"
if {![file exists $tf]} { puts "INT_SYN_TIMING_MISSING"; exit 1 }
if {![file exists $af]} { puts "INT_SYN_AREA_MISSING"; exit 1 }
if {$syn_viol < 0} { puts "INT_SYN_ENDPOINT_COUNT_MISSING"; exit 1 }
puts "INT_SYN_RUN_COMPLETE"
exit 0
