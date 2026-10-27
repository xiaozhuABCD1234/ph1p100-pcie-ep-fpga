if {[catch {
 import_device ph1_100p.db -package PH1P100SBG484 -speed 3
 open_project ./camera_ddr_display.al
 import_db ./csi_checked_debug_pr.db
 export_cwc ./camera_ddr_display.cwc
 close_project
 puts "RGB565_CWC_EXPORTED"
} msg]} {puts stderr "RGB565_CWC_ERROR: $msg";exit 1}
exit 0
