# Read-only audit of a prepared candidate. No synthesis, bitgen or download.
if {[catch {
 import_device ph1_100p.db -package PH1P100SBG484 -speed 3
 if {![info exists display_project]} {set display_project ./camera_ddr_display.al}
 if {![info exists display_checkpoint]} {set display_checkpoint ./camera_ddr_display_Runs/phy_1/camera_ddr_display_pr.db}
 open_project $display_project
 import_db $display_checkpoint
 update_timing -mode final
 write_verilog ./capture_routed.v
 set f [open ./capture_cdc_objects.txt w]
 foreach fifo {u_fifo u_display_fifo} {
  foreach n {wgray rgray rq1_wgray rq2_wgray wq1_rgray wq2_rgray} {
   set pattern [format {u_ddrmc_test_top/u_capture/%s/%s[*]} $fifo $n]
   puts $f "$fifo/$n: [get_regs $pattern]"
  }
 }
 close $f
 close_project
 puts "CAPTURE_CDC_AUDIT_EXPORTED"
} msg]} {puts stderr "CAPTURE_CDC_AUDIT_ERROR: $msg";exit 1}
exit 0
