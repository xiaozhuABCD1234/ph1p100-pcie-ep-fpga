# Read-only audit of a prepared candidate. No synthesis, bitgen or download.
if {[catch {
 import_device ph1_100p.db -package PH1P100SBG484 -speed 3
 if {![info exists capture_project]} {set capture_project ./camera_ddr_capture.al}
 if {![info exists capture_checkpoint]} {set capture_checkpoint ./camera_ddr_capture_Runs/phy_1/camera_ddr_capture_pr.db}
 open_project $capture_project
 import_db $capture_checkpoint
 update_timing -mode final
 write_verilog ./capture_routed.v
 set f [open ./capture_cdc_objects.txt w]
 foreach n {wgray rgray rq1_wgray rq2_wgray wq1_rgray wq2_rgray} {
  set pattern [format {u_ddrmc_test_top/u_capture/u_fifo/%s[*]} $n]
  puts $f "$n: [get_regs $pattern]"
 }
 close $f
 close_project
 puts "CAPTURE_CDC_AUDIT_EXPORTED"
} msg]} {puts stderr "CAPTURE_CDC_AUDIT_ERROR: $msg";exit 1}
exit 0
