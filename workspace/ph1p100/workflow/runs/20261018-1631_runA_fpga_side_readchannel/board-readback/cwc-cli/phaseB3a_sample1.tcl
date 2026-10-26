# RunA P3 cwc_cli_probe - Phase B3a: sample 1 (config + instant trigger + CSV) in ONE session
# Read-only; no download, no flash, no GUI automation.
set cwc  "C:/Users/czz/AppData/Local/Temp/runa_p3/compiled_debug.cwc"
set inst auto_created_cwc1
set csv1 "C:/Users/czz/AppData/Local/Temp/runa_p3/cwc_sample1.csv"
puts "CWC_B3A_START t=[clock format [clock seconds] -format %H:%M:%S]"
puts "B3A_CONFIG=[catch {config_chipwatcher $cwc} r] -> $r"

proc show {label script} {
  if {[catch {uplevel 1 $script} r]} { puts "$label ERR: $r" } else { puts "$label OK: $r" }
}
show "B3A_HWS" {get_hw_cws $inst}
show "B3A_PROBES" {get_cw_probes $inst}
show "B3A_STATE_PRE" {check_cw_trigger $inst -cable 0}
show "B3A_RUN" {run_hw_cw $inst -trigger_now -cable 0}
show "B3A_WAIT" {wait_on_hw_cw $inst -timeout 20 -cable 0}
show "B3A_STATE_POST" {check_cw_trigger $inst -cable 0}
show "B3A_CSV" {write_hw_cw_data $inst -csv_file $csv1}
puts "B3A_CSV_EXISTS=[file isfile $csv1] size=[expr {[file isfile $csv1] ? [file size $csv1] : -1}]"
if {[file isfile $csv1]} {
  set f [open $csv1 r]
  set data [read $f]
  close $f
  puts "B3A_CSV_BEGIN"
  puts $data
  puts "B3A_CSV_END"
}
puts "CWC_B3A_END t=[clock format [clock seconds] -format %H:%M:%S]"
