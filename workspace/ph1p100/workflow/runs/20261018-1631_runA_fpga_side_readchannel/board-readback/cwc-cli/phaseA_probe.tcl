# RunA P3 cwc_cli_probe - Phase A: enumerate TD 2026.2 built-in ChipWatcher Tcl commands
# Read-only: no download, no flash, no GUI automation.
puts "CWC_A_START"
proc probe {label script} {
  if {[catch {uplevel 1 $script} r]} {
    puts "PROBE $label ERR: $r"
  } else {
    puts "PROBE $label OK: $r"
  }
}
puts "TCL_VERSION=[info patchlevel]"
probe "info_cw_commands" {lsort [info commands *cw*]}
probe "info_cwc_commands" {lsort [info commands *cwc*]}
probe "info_chip_commands" {lsort [info commands *chip*]}
probe "info_hw_commands" {lsort [info commands *hw*]}
probe "help_get_hw_cws" {get_hw_cws -help}
probe "help_get_cw_probes" {get_cw_probes -help}
probe "help_run_hw_cw" {run_hw_cw -help}
probe "help_wait_on_hw_cw" {wait_on_hw_cw -help}
probe "help_write_hw_cw_data" {write_hw_cw_data -help}
probe "help_check_cw_trigger" {check_cw_trigger -help}
probe "help_export_chipwatcher" {export_chipwatcher -help}
probe "help_report_cwc_status" {report_cwc_status -help}
probe "help_open_hw_manager" {open_hw_manager -help}
probe "get_hw_cws_bare" {get_hw_cws}
puts "CWC_A_END"
