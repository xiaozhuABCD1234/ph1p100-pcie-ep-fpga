if {[catch {
 import_device ph1_100p.db -package PH1P100SBG484 -speed 3
 open_project ./camera_ddr_display.al
 import_db ./rgb332_refined_pr.db
 update_timing -mode final
 report_clock_summary -file ./hdmi_clocks.rpt
 set targets [get_cells {*O_hdmi*syn_2*}]
 set f [open ./hdmi_targets.txt w]
 puts $f $targets
 puts $f [get_pins {*O_hdmi*syn_2*}]
 puts $f [get_clocks *]
 close $f
 if {[llength $targets] == 0} {error "No HDMI pad endpoints selected"}
 report_timing_path -to $targets -ep_num 100 -path_num 3 -file ./hdmi_data_paths.rpt
 close_project
 puts "HDMI_ROUTED_AUDIT_REPORTS_READY"
} msg]} {puts stderr "HDMI_ROUTED_AUDIT_ERROR: $msg";exit 1}
exit 0
