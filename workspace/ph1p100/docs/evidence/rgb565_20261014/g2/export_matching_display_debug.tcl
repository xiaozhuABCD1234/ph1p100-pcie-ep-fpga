# Post-build export from the same selected database; no cable connection/download.
if {[catch {
 import_device ph1_100p.db -package PH1P100SBG484 -speed 3
 open_project ./camera_ddr_display.al
 import_db ./csi_checked_debug_pr.db
 if {[file exists ./camera_ddr_display.cwc]} {error "Preserve existing debug export"}
 report_cwc_status
 export_chipwatcher ./camera_ddr_display.cwc
 close_project
 if {![file exists ./camera_ddr_display.cwc]} {error "Missing ChipWatcher description"}
 puts "MATCHING_DISPLAY_CWC_EXPORTED_NO_DOWNLOAD"
} msg]} {puts stderr "DISPLAY_CWC_EXPORT_ERROR: $msg";exit 1}
exit 0
