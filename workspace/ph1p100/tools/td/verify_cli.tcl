# Read-only TD command registration check. Does not open or build a project.
set required {open_project import_device launch_runs wait_run bitgen report_timing_summary}
foreach name $required {
    if {[llength [info commands $name]] == 0} {
        puts stderr "TD_CLI_MISSING_COMMAND: $name"
        exit 1
    }
    puts "TD_CLI_COMMAND_OK: $name"
}
puts "TD_CLI_TCL_VERSION: [info patchlevel]"
puts "TD_CLI_OK"
exit 0
