# RunA P3 cwc_cli_probe - Phase B: real ChipWatcher readback via TD built-in Tcl
# Read-only on hardware: no download, no flash, no GUI automation. SRAM bitstream already loaded.
# Paths are ASCII (temp stage) to avoid non-ASCII file-path hazards; CSVs copied into the run dir afterwards.
set cwc  "C:/Users/czz/AppData/Local/Temp/runa_p3/compiled_debug.cwc"
set csv1 "C:/Users/czz/AppData/Local/Temp/runa_p3/cwc_sample1.csv"
set csv2 "C:/Users/czz/AppData/Local/Temp/runa_p3/cwc_sample2.csv"
puts "CWC_B_START cwc_exists=[file isfile $cwc] t=[clock format [clock seconds] -format %H:%M:%S]"

if {[catch {config_chipwatcher $cwc} r]} { puts "B_CONFIG_ERR: $r" } else { puts "B_CONFIG_OK: $r" }

if {[catch {get_hw_cws} r]} {
  puts "B_GET_HWS_ERR: $r"
  puts "B_GET_HWS_ERRINFO: $::errorInfo"
} else {
  puts "B_GET_HWS_OK: $r"
  set inst [lindex $r 0]
  puts "B_INSTANCE=$inst"
  if {[catch {get_cw_probes $inst} p]} {
    puts "B_PROBES_ERR: $p"
  } else {
    puts "B_PROBES_OK: $p"
  }
  puts "B_STATE1=[catch {check_cw_trigger $inst -cable 0} c1] -> $c1"
  puts "B_RUN1=[catch {run_hw_cw $inst -trigger_now -cable 0} r1] -> $r1"
  puts "B_WAIT1=[catch {wait_on_hw_cw $inst -timeout 20 -cable 0} w1] -> $w1"
  puts "B_STATE1B=[catch {check_cw_trigger $inst -cable 0} c1b] -> $c1b"
  puts "B_CSV1=[catch {write_hw_cw_data $inst -csv_file $csv1} v1] -> $v1"
  puts "B_CSV1_EXISTS=[file isfile $csv1] size=[expr {[file isfile $csv1] ? [file size $csv1] : -1}]"
  puts "B_SLEEP_12S t=[clock format [clock seconds] -format %H:%M:%S]"
  after 12000
  puts "B_RUN2=[catch {run_hw_cw $inst -trigger_now -cable 0} r2] -> $r2"
  puts "B_WAIT2=[catch {wait_on_hw_cw $inst -timeout 20 -cable 0} w2] -> $w2"
  puts "B_STATE2=[catch {check_cw_trigger $inst -cable 0} c2] -> $c2"
  puts "B_CSV2=[catch {write_hw_cw_data $inst -csv_file $csv2} v2] -> $v2"
  puts "B_CSV2_EXISTS=[file isfile $csv2] size=[expr {[file isfile $csv2] ? [file size $csv2] : -1}]"
}
puts "CWC_B_END t=[clock format [clock seconds] -format %H:%M:%S]"
