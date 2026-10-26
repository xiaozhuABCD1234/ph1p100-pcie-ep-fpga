# Run from the prepared project root so TD resolves all IP XML paths.
# Preserve the original routed database. No bit generation or hardware download.
# Options follow TD route.qor QOR-1301 and native phys_opt -help.
if {[catch {
 import_device ph1_100p.db -package PH1P100SBG484 -speed 3
 open_project ./camera_ddr_capture.al
 import_db ./camera_ddr_capture_Runs/phy_1/camera_ddr_capture_pr.db
 set_param route post_route_opt ultra
 set_param route postrt_opt_extra_round 4
 phys_opt -post_route -effort ultra
 update_timing -mode final
 report_timing_summary -file ./capture_timing.rpt
 report_timing_ignored -file ./capture_ignored.rpt -ep_num 50
 report_abnormal_timing_target -file ./capture_abnormal.rpt
 report_path_skew -file ./capture_skew.rpt -ep_num 20
 report_area -file ./capture.area
 report_route_status -drc -file ./capture_route_drc.rpt
 export_db ./capture_postroute_pr.db
 close_project
 puts "CAPTURE_POSTROUTE_RETURNED_CHECK_REPORTS_NO_BIT"
} msg]} {puts stderr "CAPTURE_POSTROUTE_ERROR: $msg";exit 1}
exit 0
