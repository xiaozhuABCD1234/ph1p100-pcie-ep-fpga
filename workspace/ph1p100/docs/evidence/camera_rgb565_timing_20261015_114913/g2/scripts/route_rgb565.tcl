# Resume the exact freshly synthesized checkpoint after project-manager
# launch_runs fails before creating a physical run. No relaxed constraints.
if {[catch {
 import_device ph1_100p.db -package PH1P100SBG484 -speed 3
 open_project ./camera_ddr_display.al
 load_run_param -run phy_1
 import_db ./camera_ddr_display_Runs/syn_1/camera_ddr_display_gate.db
 commit_param -step place
 # Match TD's generated physical flow: MARK_DEBUG trace logic is inserted
 # after gate import, as well as the synthesis-stage debugger preparation.
 insert_debugger
 # SWUG200 PDF19: user uncertainty adds to the default jitter allowance.
 # Implementation-only reserve; no PLL/clock period/SDC/pin changes.
 foreach clock_name {ddr_user mipi_a_byte_clk pclkx1} {
  set reserve_clock [get_clocks $clock_name]
  if {[llength $reserve_clock] != 1} {error "Reserve clock missing/ambiguous: $clock_name"}
  set_clock_uncertainty -setup 0.300 $reserve_clock
 }
 puts "IMPLEMENTATION_SETUP_RESERVE_APPLIED_NS_0.300"
 place
 export_db ./csi_checked_place.db
 commit_param -step route
 route
 update_timing -mode final
 report_timing_summary -file ./implementation_guard_timing.rpt
 # Restore the original user setup uncertainty (0); keep default jitter.
 foreach clock_name {ddr_user mipi_a_byte_clk pclkx1} {
  set reserve_clock [get_clocks $clock_name]
  if {[llength $reserve_clock] != 1} {error "Nominal clock missing/ambiguous: $clock_name"}
  set_clock_uncertainty -setup 0.000 $reserve_clock
 }
 puts "IMPLEMENTATION_SETUP_RESERVE_CLEARED_FOR_NOMINAL_SIGNOFF"
 update_timing -mode final
 report_timing_summary -file ./capture_timing.rpt
 report_timing_ignored -file ./capture_ignored.rpt -ep_num 50
 report_abnormal_timing_target -file ./capture_abnormal.rpt
 report_path_skew -file ./capture_skew.rpt -ep_num 20
 report_area -file ./capture.area
 report_route_status -drc -file ./capture_route_drc.rpt
 export_db ./csi_checked_debug_pr.db
 close_project
 puts "RGB565_ROUTE_RETURNED_CHECK_REPORTS_NO_BIT"
} msg]} {puts stderr "RGB565_ROUTE_ERROR: $msg";exit 1}
exit 0
