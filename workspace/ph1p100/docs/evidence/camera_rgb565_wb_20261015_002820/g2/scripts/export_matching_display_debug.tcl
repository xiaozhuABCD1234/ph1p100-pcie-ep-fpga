# Post-build export from the same selected database; no cable connection/download.
if {[catch {
 import_device ph1_100p.db -package PH1P100SBG484 -speed 3
 open_project ./camera_ddr_display.al
 import_db ./csi_checked_debug_pr.db
 if {[file exists ./camera_ddr_display.cwc]} {error "Preserve existing debug export"}
 report_cwc_status
 # Match the installed DefaultFlow.tcl post-bitgen setup. Plain export_chipwatcher
 # omits physical ERAM mappings and cannot provide offline waveform readback.
 if {![file exists ./camera_ddr_display.bit] || ![file exists ./camera_ddr_display_inst.bid]} {
  error "Missing matching bit/BID from native bitgen"
 }
 if {[file exists ./cw/compiled.cwc] || [file exists ./cw/compiled.bit]} {
  error "Preserve existing compiled debugger artifacts"
 }
 setup_debugger -prj camera_ddr_display
 if {![file exists ./cw/compiled.cwc] || ![file exists ./cw/compiled.bit]} {
  error "Missing paired debugger output"
 }
 set fh [open ./cw/compiled.cwc r]
 set cwc_text [read $fh]
 close $fh
 if {![regexp {<phy_eram } $cwc_text]} {error "Missing physical ERAM readback mapping"}
 if {[regexp {<logic_eram [^>]+/>} $cwc_text]} {error "Incomplete logical ERAM readback mapping"}
 set fh [open ./camera_ddr_display.bit rb]
 set parent_bit [read $fh]
 close $fh
 set fh [open ./cw/compiled.bit rb]
 set debug_bit [read $fh]
 close $fh
 if {$parent_bit ne $debug_bit} {error "Debugger bit changed: review artifacts before use"}
 file copy ./cw/compiled.cwc ./camera_ddr_display.cwc
 close_project
 if {![file exists ./camera_ddr_display.cwc]} {error "Missing ChipWatcher description"}
 puts "MATCHING_DISPLAY_CWC_EXPORTED_NO_DOWNLOAD"
} msg]} {puts stderr "DISPLAY_CWC_EXPORT_ERROR: $msg";exit 1}
exit 0
