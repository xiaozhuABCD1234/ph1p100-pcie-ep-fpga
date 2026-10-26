set bit "C:/Users/czz/AppData/Local/Temp/runa_p3/ph1p_pcie_integration_debug.bit"
set cwc "C:/Users/czz/AppData/Local/Temp/runa_p3/cw_pair/compiled.cwc"
set csv1 "C:/Users/czz/AppData/Local/Temp/runa_p3/cwc_sample1.csv"
set csv2 "C:/Users/czz/AppData/Local/Temp/runa_p3/cwc_sample2.csv"
set inst auto_created_cwc1
puts "C2_START t=[clock format [clock seconds] -format %H:%M:%S]"
puts "C2_BIT_FILE=[file isfile $bit] size=[file size $bit]"
puts "C2_DEV_BEFORE=[catch {read_device_id} d0] -> $d0"
set t0 [clock milliseconds]
set drc [catch {download -bit $bit -mode jtag -cable 0} dm]
set dt [expr {[clock milliseconds]-$t0}]
puts "C2_DL rc=$drc ms=$dt msg=$dm"
if {$drc != 0} {
  set t0 [clock milliseconds]
  set drc [catch {download -bit $bit -mode PROGRAM_SRAM -cable 0} dm]
  set dt [expr {[clock milliseconds]-$t0}]
  puts "C2_DL2 rc=$drc ms=$dt msg=$dm"
}
puts "C2_DEV_AFTER=[catch {read_device_id} d1] -> $d1"
puts "C2_CONFIG=[catch {config_chipwatcher $cwc} r] -> $r"
puts "C2_STATUS=[catch {report_cwc_status $inst} s] -> $s"
puts "C2_HWS=[catch {get_hw_cws *} h] -> $h"
set rc [catch {run_hw_cw $inst -trigger_now -cable 0} m]
puts "C2_RUN rc=$rc msg=$m"
if {$rc == 0} {
  puts "C2_WAIT=[catch {wait_on_hw_cw $inst -timeout 20 -cable 0} w] -> $w"
  puts "C2_STATE=[catch {check_cw_trigger $inst -cable 0} c] -> $c"
  puts "C2_CSV1=[catch {write_hw_cw_data $inst -csv_file $csv1} v] -> $v"
  puts "C2_CSV1_SIZE=[expr {[file isfile $csv1] ? [file size $csv1] : -1}] t=[clock format [clock seconds] -format %H:%M:%S]"
  after 11000
  puts "C2_RUN2=[catch {run_hw_cw $inst -trigger_now -cable 0} m2] -> $m2"
  puts "C2_WAIT2=[catch {wait_on_hw_cw $inst -timeout 20 -cable 0} w2] -> $w2"
  puts "C2_CSV2=[catch {write_hw_cw_data $inst -csv_file $csv2} v2] -> $v2"
  puts "C2_CSV2_SIZE=[expr {[file isfile $csv2] ? [file size $csv2] : -1}] t=[clock format [clock seconds] -format %H:%M:%S]"
}
puts "C2_END t=[clock format [clock seconds] -format %H:%M:%S]"