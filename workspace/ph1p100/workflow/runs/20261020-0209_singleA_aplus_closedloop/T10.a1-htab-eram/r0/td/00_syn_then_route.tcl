# T10.a1-htab-eram r0 -- synth checkpoint + one route, no bitgen.
# T: = this package r0/td, Y: = project root (tools/td/td_env.ps1)
set PRJ_ROOT "Y:/upstream/ph1p100-pcie-ep-fpga"
create_project a1_ht_r0 ./ -family PH1 -device PH1P100SBG484 -speed 3 -force
add_files $PRJ_ROOT/rtl/ep_side/codec/a1_frame_top.v
add_files $PRJ_ROOT/rtl/ep_side/codec/a1_deflate_core.v
add_files ./a1_eng_top.v
add_files ./a1_small_top.sdc
top_module a1_eng_top

set tag "s1"
if {[info exists ::env(A1_TD_TAG)]} { set tag $::env(A1_TD_TAG) }

# ---------------------------------------------------------------- synthesis
launch_runs { syn_1 } -jobs 4
wait_run syn_1 -quiet
set tf "./a1_ht_r0_Runs/syn_1/a1_ht_r0_gate.timing"
set af "./a1_ht_r0_Runs/syn_1/a1_ht_r0_gate.area"
if {[file exists $tf]} { file copy -force $tf ./syn_gate_timing_$tag.rpt }
if {[file exists $af]} { file copy -force $af ./syn_gate_area_$tag.rpt }

set syn_wns -99.0; set syn_tns -99.0; set syn_slice -1; set syn_eram -1
set syn_reg -1; set syn_dram -1; set syn_core_eram -1
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
  if {[regexp {\|\s+u_core\s+\|a1_deflate_core\s+\|[0-9]+\s+\|[0-9]+\s+\|[0-9]+\s+\|([0-9]+)} $atxt -> ce]} { set syn_core_eram $ce }
}
puts "SYN_SWNS=$syn_wns SYN_STNS=$syn_tns SYN_SLICE=$syn_slice SYN_ERAM=$syn_eram SYN_CORE_ERAM=$syn_core_eram SYN_REG=$syn_reg SYN_DRAM=$syn_dram"

# Gate: WNS >= +0.5 ns (target +1.0), TNS >= 0, slice <= 71680, htab really moved
# to ERAM (core ERAM must exceed the bm16+cmem4=18 baseline; expect +4).
if { ($syn_wns >= 0.5) && ($syn_tns >= 0.0) && ($syn_slice > 0) && \
     ($syn_slice <= 71680) && ($syn_eram >= 25) && ($syn_core_eram >= 21) } {
  puts "SYN_GATE_OK launching phy_1"

  # ------------------------------------------------------------- physical
  if {[file exists ./a1_ht_r0_Runs/phy_1/.stop.f]} { file delete -force ./a1_ht_r0_Runs/phy_1/.stop.f }
  if {[catch { launch_runs { phy_1 } -jobs 4 } e]} { puts "PHY_LAUNCH_ERR $e" }

  # The default phy flow ends with bitgen.  This task is bitgen-not-run, so as
  # soon as the route step has started, place the flow stop marker: it is only
  # checked at the beginning of the next step (bitgen), which then halts before
  # executing.  The route step itself is unaffected and still exports *_pr.db.
  set waited 0
  while { (![file exists ./a1_ht_r0_Runs/phy_1/.opt_route.begin.f]) && ($waited < 1800) } {
    after 2000
    incr waited 2
  }
  if {[file exists ./a1_ht_r0_Runs/phy_1/.opt_route.begin.f]} {
    set fh [open ./a1_ht_r0_Runs/phy_1/.stop.f w]
    puts $fh "stop before bitgen (T10.a1-htab-eram)"
    close $fh
    puts "PHY_STOP_MARKER_SET"
  } else {
    puts "PHY_ROUTE_NOT_STARTED waited=${waited}s"
  }
  if {[catch { wait_run phy_1 -quiet } e]} { puts "PHY_WAIT_ERR $e" }

  set prdb "./a1_ht_r0_Runs/phy_1/a1_ht_r0_pr.db"
  if {[file exists $prdb]} {
    if {[catch { import_db $prdb } e]} { puts "IMPORT_DB_ERR $e" }
    if {[catch { update_timing -mode final } e]} { puts "UPDATE_TIMING_ERR $e" }
    if {[catch { report_timing_summary -file phy_timing_summary.rpt } e]} { puts "RPT_TS_ERR $e" }
    if {[catch { report_timing_status -file phy_timing_status.rpt } e]} { puts "RPT_TST_ERR $e" }
    if {[catch { report_area -io_info -file phy_area.rpt } e]} { puts "RPT_AREA_ERR $e" }
    if {[catch { report_timing -file phy_timing.rpt } e]} { puts "RPT_TIMING_ERR $e" }
    if {[catch { report_qor -step route -file route_after_import.qor } e]} { puts "RPT_QOR_ERR $e" }
    if {[catch { report_cdc -file cdc.rpt } e]} { puts "RPT_CDC_ERR $e" } else { puts "CDC_EXECUTED" }
    if {[catch { check_timing -verbose -file check_timing.rpt } e]} { puts "RPT_CHK_ERR $e" } else { puts "CHECK_TIMING_EXECUTED" }
    if {[catch { report_clock_utilization -file phy_clock_util.rpt } e]} { puts "RPT_CLK_ERR $e" }

    set pwns -99.0; set ptns -99.0; set hwns -99.0; set htns -99.0
    set ptf "./a1_ht_r0_Runs/phy_1/a1_ht_r0_pr.timing"
    if {[file exists $ptf]} {
      file copy -force $ptf ./phy_pr_timing.rpt
      set fh [open $ptf r]; set ptxt [read $fh]; close $fh
      if {[regexp {SWNS:\s*(-?[0-9.]+)ns} $ptxt -> w]} { set pwns $w }
      if {[regexp {STNS:\s*(-?[0-9.]+)ns} $ptxt -> w]} { set ptns $w }
      if {[regexp {HWNS:\s*(-?[0-9.]+)ns} $ptxt -> w]} { set hwns $w }
      if {[regexp {HTNS:\s*(-?[0-9.]+)ns} $ptxt -> w]} { set htns $w }
    }
    puts "ROUTED_SWNS=$pwns ROUTED_STNS=$ptns ROUTED_HWNS=$hwns ROUTED_HTNS=$htns"
    set rfs "./a1_ht_r0_Runs/phy_1/route_flow.status"
    if {[file exists $rfs]} { file copy -force $rfs ./route_flow.status; puts "ROUTE_FLOW_STATUS_COPIED" }
    set pqf "./a1_ht_r0_Runs/phy_1/a1_ht_r0_phy.area"
    if {[file exists $pqf]} { file copy -force $pqf ./phy_area_run.rpt }
  } else {
    puts "PHY_NO_PR_DB"
  }
} else {
  puts "SYN_GATE_STOP no_route (wns=$syn_wns tns=$syn_tns slice=$syn_slice eram=$syn_eram core_eram=$syn_core_eram)"
}
puts "A1_htab_r0_DONE"
exit
