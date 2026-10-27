# =============================================================================
# 01_synth.tcl - T10.ah-honly-td (Line B) r1: 187.5 MHz synthesis, run 1 of 1 (lifetime TD launch 2 of 3).
#
# LEASE STATUS: GRANTED (v2, holder-agnostic).  r2-ruling.md §2-§3 (2026-10-27
# 09:30) grants this round: 0 TD processes AND INT.P4/td, INT.P4/r3 and
# 20261027-0726_fpga-board-integration/T11.BRD.P1/td all quiet for >= 20 min.
# Re-verified immediately before this run in r1/preflight-r1.json.  T: belongs to
# the board-integration run and is never remapped/forced by this task.
# If another TD session appears during the window: do not kill it, let the running
# command finish, start no second session; a single-seat conflict (RUN-8008 /
# PRJ-5303 / PRJ-8806) is recorded as TOOL_UNAVAILABLE, never as a DUT defect.
## Quota (frozen, r0-ruling 搂2.3): 1 synth, <=2 route (2nd only after a failed 1st,
# with the parameter difference written down), 0 bitgen, 0 CWC, 0 download,
# 0 Flash, 0 board, 0 network.  No false_path / multicycle / clock group / IO
# exception.
#
# DUT: synthfix revision of the H-only candidate, ABSOLUTE READ-ONLY paths.
#   core      T10.ah-honly-synthfix/r0/changed-src/a1_deflate_core.v
#             85,221 B  d2960cfe0111b7b61aff281e3f16427834dda26107f37867d5c7c89ac346aad8
#   frame_top T10.ah-honly-synthfix/r0/changed-src/a1_frame_top.v
#             29,207 B  4afc26e246fbae4e32c5ab7e88dffb496048d10966c5ee42b290b3e71f60e30a
#             (byte-identical to the H-only r1 file; unchanged)
# previous DUT: H-only r1 core 8acd20b2...b17b, rejected by TD with HDL-8007
# (multiple drivers on cmem_lo).  synthfix manifest 034777c5...e510, tester PASS.
# The local copy in D:/fpga/repos/ph1p100-pcie-ep-fpga is still NOT a source
# (the diff is not migrated there).
## Execution (recovery round): cwd = r1/td/run-syn1, invoke
#   D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe ./01_synth.tcl
# (a copy of this file is placed in that run directory; the project and all
# reports are created relative to the process cwd, so nothing overwrites r0
# preparation evidence).
# =============================================================================
set prj "a1_ah"
create_project $prj ./ -family PH1 -device PH1P100SBG484 -speed 3 -force

# build-only wrapper (NOT a candidate RTL file)
add_files D:/fpga/ph1p100/workflow/runs/20261027-055621_fpga-honly-td-and-ah/T10.ah-honly-td/r1/td/a1_ah_eng_top.v
# synthfix candidates (read-only, SHA 4afc26e2...e30a / d2960cfe...aad8)
add_files D:/fpga/ph1p100/workflow/runs/20261027-055621_fpga-honly-td-and-ah/T10.ah-honly-synthfix/r0/changed-src/a1_frame_top.v
add_files D:/fpga/ph1p100/workflow/runs/20261027-055621_fpga-honly-td-and-ah/T10.ah-honly-synthfix/r0/changed-src/a1_deflate_core.v
add_files D:/fpga/ph1p100/workflow/runs/20261027-055621_fpga-honly-td-and-ah/T10.ah-honly-td/r1/td/a1_ah_small_top.sdc
top_module a1_ah_eng_top

launch_runs { syn_1 } -jobs 4
if {[catch { wait_run syn_1 -quiet } e]} { puts "AH_SYN_WAIT_ERR $e" }

set rd "./${prj}_Runs/syn_1"
set tf "$rd/${prj}_gate.timing"
set af "$rd/${prj}_gate.area"
set fs "$rd/flow.status"
if {[file exists $tf]} { file copy -force $tf ./syn_gate_timing.rpt }
if {[file exists $af]} { file copy -force $af ./syn_gate_area.rpt }
if {[file exists $fs]} { file copy -force $fs ./syn_flow.status }

# ---- defaults are deliberately sentinel values, never plausible numbers ----
set s_wns -99.0
set s_tns -99.0
set s_hwns -99.0
set s_htns -99.0
set s_period -99.0
set s_fe -1
set s_hfe -1
set s_tot -1
set s_cov "n/a"
set s_io -1
set s_eram -1
set s_cwc -1
set s_reg -1
set s_slice -1
set s_dsp -1

if {[file exists $tf]} {
  set fh [open $tf r]; set txt [read $fh]; close $fh
  if {[regexp {SWNS:\s*(-?[0-9.]+)ns} $txt -> w]} { set s_wns $w }
  if {[regexp {STNS:\s*(-?[0-9.]+)ns} $txt -> w]} { set s_tns $w }
  if {[regexp {HWNS:\s*(-?[0-9.]+)ns} $txt -> w]} { set s_hwns $w }
  if {[regexp {HTNS:\s*(-?[0-9.]+)ns} $txt -> w]} { set s_htns $w }
  if {[regexp {Period Check WNS:\s*(-?[0-9.]+)ns} $txt -> w]} { set s_period $w }
  if {[regexp {STA coverage\s*:\s*([0-9.]+)} $txt -> w]} { set s_cov $w }
  if {[regexp {Max\s*:\s*SWNS\s+-?[0-9.]+ns,\s*STNS\s+-?[0-9.]+ns,\s*([0-9]+)\s+Viol Endpoints,\s*([0-9]+)\s+Total Endpoints} $txt -> v tot]} {
    set s_fe $v
    set s_tot $tot
  }
}
# flow.status is authoritative for endpoint statistics and overrides the header.
set s_fe_fs -1
set s_hfe_fs -1
set s_tns_ps "n/a"
if {[file exists $fs]} {
  set fh [open $fs r]; set ftxt [read $fh]; close $fh
  if {[regexp {Setup\s*:\s*WNS\s+(-?[0-9]+)ps\s+TNS\s+(-?[0-9]+)ps\s+NUM_FEPS\s+([0-9]+)} $ftxt -> wps tps nfe]} {
    set s_fe_fs $nfe
    set s_tns_ps "$tps ps"
  }
  if {[regexp {Hold\s*:\s*WNS\s+(-?[0-9]+)ps\s+TNS\s+(-?[0-9]+)ps\s+NUM_FEPS\s+([0-9]+)} $ftxt -> hw ht hn]} {
    set s_hfe_fs $hn
  }
}
if {$s_fe_fs >= 0} { set s_fe $s_fe_fs }
if {[file exists $af]} {
  set fh [open $af r]; set atxt [read $fh]; close $fh
  if {[regexp {#IO\s+([0-9]+)} $atxt -> v]} { set s_io $v }
  if {[regexp {#eram\s+([0-9]+)} $atxt -> v]} { set s_eram $v }
  if {[regexp {#fifo20k\s+([0-9]+)} $atxt -> v]} { set s_cwc $v }
  if {[regexp {#reg\s+([0-9]+)} $atxt -> v]} { set s_reg $v }
  if {[regexp {#slice\*\s+([0-9]+)} $atxt -> v]} { set s_slice $v }
  if {[regexp {#dsp\s+([0-9]+)} $atxt -> v]} { set s_dsp $v }
}
set s_eram_cwc [expr {$s_eram + $s_cwc}]

puts "AH_SYN_TOP=a1_ah_eng_top AH_SYN_DEVICE=PH1P100SBG484 AH_SYN_SPEED=3 AH_SYN_PERIOD_NS=5.333"
puts "AH_SYN_SWNS=$s_wns AH_SYN_STNS=$s_tns AH_SYN_HWNS=$s_hwns AH_SYN_HTNS=$s_htns"
puts "AH_SYN_PERIOD_WNS=$s_period AH_SYN_TNS_PS='$s_tns_ps' AH_SYN_COVERAGE=$s_cov"
puts "AH_SYN_VIOL_ENDPOINTS=$s_fe AH_SYN_HOLD_VIOL_ENDPOINTS=$s_hfe_fs AH_SYN_TOTAL_ENDPOINTS=$s_tot"
puts "AH_SYN_VIOL_ENDPOINTS_FLOWSTATUS=$s_fe_fs"
puts "AH_SYN_IO=$s_io AH_SYN_ERAM=$s_eram AH_SYN_CWC=$s_cwc AH_SYN_ERAM_CWC=$s_eram_cwc AH_SYN_REG=$s_reg AH_SYN_SLICE=$s_slice AH_SYN_DSP=$s_dsp"

# exit 0 only when the three authoritative reports exist
if {![file exists $tf] || ![file exists $af] || ![file exists $fs]} {
  puts "AH_SYN_REPORT_MISSING timing=[file exists $tf] area=[file exists $af] flow=[file exists $fs]"
  exit 1
}
puts "AH_SYN_RUN_COMPLETE"
exit 0