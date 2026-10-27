if {[catch {
 import_device ph1_100p.db -package PH1P100SBG484 -speed 3
 create_project ram_probe ./ -family ph1 -device PH1P100SBG484 -speed 3
 add_files ./probe_camera_ram.v
 top_module probe_camera_ram
 launch_runs syn_1
 wait_run syn_1 -quiet
 open_run syn_1
 report_area -file ./probe.area
 close_project
 puts "RAM_PROBE_RETURNED_CHECK_AREA"
} msg]} {puts stderr "RAM_PROBE_TCL_ERROR: $msg"; exit 1}
exit 0
