foreach name {open_project import_device launch_runs wait_run bitgen report_timing_summary create_ip get_ips get_property set_property generate_target} {
 if {[llength [info commands $name]] == 0} {puts stderr "MISSING $name"; exit 1}
 puts "REGISTERED $name"
}
puts "TCL_VERSION [info patchlevel]"
puts "READ_ONLY_CLI_PROBE_OK"
exit 0