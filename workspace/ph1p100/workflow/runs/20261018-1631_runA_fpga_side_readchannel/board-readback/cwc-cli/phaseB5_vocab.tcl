# RunA P3 cwc_cli_probe - Phase B5: vocabulary + watcher-object variants for run_hw_cw
# Read-only; no download, no flash, no GUI automation.
set cwc  "C:/Users/czz/AppData/Local/Temp/runa_p3/compiled_debug.cwc"
puts "CWC_B5_START t=[clock format [clock seconds] -format %H:%M:%S]"
puts "B5_CONFIG=[catch {config_chipwatcher $cwc} r] -> $r"
foreach pat {*cable* *probe* *device* *download* *jtag* *run* *wr* *trig* *hw*} {
  if {[catch {lsort [info commands $pat]} l]} { puts "B5_CMDS $pat ERR: $l" } else { puts "B5_CMDS $pat = $l" }
}
proc try {label script} {
  if {[catch {uplevel 1 $script} m]} { puts "B5_$label ERR: $m" } else { puts "B5_$label OK: $m" }
}
try V1 {run_hw_cw auto_created_cwc1_trigger -trigger_now -cable 0}
try V2 {run_hw_cw * -trigger_now -cable 0}
try V3 {run_hw_cw [get_hw_cws] -trigger_now -cable 0}
try V4 {run_hw_cw auto_created_cwc1 -trigger_now}
try V5 {run_hw_cw auto_created_cwc1 -cable 0 -trigger_now}
try V6 {check_cw_trigger auto_created_cwc1_trigger -cable 0}
try V7 {report_cwc_status auto_created_cwc1}
try V8 {check_cw_trigger * -cable 0}
puts "CWC_B5_END t=[clock format [clock seconds] -format %H:%M:%S]"
