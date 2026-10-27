# RunA P3 cwc_cli_probe - Phase B2: readback with explicit instance name (auto_created_cwc1)
# Read-only; no download, no flash, no GUI automation. Instance confirmed by config_chipwatcher (KIT-1004).
set inst auto_created_cwc1
set csv1 "C:/Users/czz/AppData/Local/Temp/runa_p3/cwc_sample1.csv"
set csv2 "C:/Users/czz/AppData/Local/Temp/runa_p3/cwc_sample2.csv"
puts "CWC_B2_START inst=$inst t=[clock format [clock seconds] -format %H:%M:%S]"
if {[catch {get_hw_cws $inst} r]} { puts "B2_GET_HWS_ERR: $r" } else { puts "B2_GET_HWS_OK: $r" }
if {[catch {get_cw_probes $inst} p]} { puts "B2_PROBES_ERR: $p" } else { puts "B2_PROBES_OK: $p" }

proc trig {} {
  global inst
  if {[catch {run_hw_cw $inst -trigger_now -cable 0} m]} {
    puts "B2_RUN_V1_ERR: $m"
    if {[catch {run_hw_cw $inst -trigger_now} m2]} { puts "B2_RUN_V2_ERR: $m2" } else { puts "B2_RUN_V2_OK: $m2" }
  } else { puts "B2_RUN_V1_OK: $m" }
}
proc waitit {} {
  global inst
  if {[catch {wait_on_hw_cw $inst -timeout 20 -cable 0} w]} {
    puts "B2_WAIT_V1_ERR: $w"
    if {[catch {wait_on_hw_cw $inst -timeout 20} w2]} { puts "B2_WAIT_V2_ERR: $w2" } else { puts "B2_WAIT_V2_OK: $w2" }
  } else { puts "B2_WAIT_V1_OK: $w" }
}
proc st {} {
  global inst
  if {[catch {check_cw_trigger $inst -cable 0} c]} { puts "B2_STATE_V1_ERR: $c" } else { puts "B2_STATE_V1_OK: $c" }
}
proc dump {csv tag} {
  global inst
  if {[catch {write_hw_cw_data $inst -csv_file $csv} v]} { puts "B2_CSV_${tag}_V1_ERR: $v" } else { puts "B2_CSV_${tag}_V1_OK: $v" }
  puts "B2_CSV_${tag}_EXISTS=[file isfile $csv] size=[expr {[file isfile $csv] ? [file size $csv] : -1}]"
}

trig
waitit
st
dump $csv1 "1"
puts "B2_SLEEP_12S t=[clock format [clock seconds] -format %H:%M:%S]"
after 12000
trig
waitit
st
dump $csv2 "2"
puts "CWC_B2_END t=[clock format [clock seconds] -format %H:%M:%S]"
