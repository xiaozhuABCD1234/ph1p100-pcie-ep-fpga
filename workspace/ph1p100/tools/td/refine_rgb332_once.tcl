# One bounded native attempt for the RGB332 DDR-IP path reported by QOR-1301.
# Preserve the original database, constraints, and first-route reports.
# No bit generation or hardware download; re-audit this new DB before use.
if {[catch {
 import_device ph1_100p.db -package PH1P100SBG484 -speed 3
 open_project ./camera_ddr_display.al
 import_db ./csi_checked_debug_pr.db
 set_param route post_route_opt ultra
 set_param route postrt_opt_extra_round 4
 phys_opt -post_route -effort ultra
 fix_hold
 update_timing -mode final
 report_timing_summary -file ./refined_timing.rpt
 report_timing_ignored -file ./refined_ignored.rpt -ep_num 50
 report_abnormal_timing_target -file ./refined_abnormal.rpt
 report_path_skew -file ./refined_skew.rpt -ep_num 20
 report_area -file ./refined.area
 report_route_status -drc
 export_db ./rgb332_refined_pr.db
 close_project
 puts "RGB332_REFINEMENT_RETURNED_CHECK_REPORTS_NO_BIT"
} msg]} {puts stderr "RGB332_REFINEMENT_ERROR: $msg";exit 1}
exit 0
