set bit "C:/Users/czz/AppData/Local/Temp/runa_p3/ph1p_pcie_integration_debug.bit"
set cwc "C:/Users/czz/AppData/Local/Temp/runa_p3/cw_pair/compiled.cwc"
set csv1 "C:/Users/czz/AppData/Local/Temp/runa_p3/cwc_sample1.csv"
set csv2 "C:/Users/czz/AppData/Local/Temp/runa_p3/cwc_sample2.csv"
set inst auto_created_cwc1
puts "C3_START t=[clock format [clock seconds] -format %H:%M:%S]"
puts "C3_DEV=[catch {read_device_id} d0] -> $d0"
set t0 [clock milliseconds]
set drc [catch {download -bit $bit -mode jtag -cable 0} dm]
set dt [expr {[clock milliseconds]-$t0}]
puts "C3_DL rc=$drc ms=$dt msg=$dm"
puts "C3_DEV2=[catch {read_device_id} d1] -> $d1"
puts "C3_CONFIG=[catch {config_chipwatcher $cwc} r] -> $r"
puts "C3_HWS=[catch {get_hw_cws *} h] -> $h"
set rc [catch {run_hw_cw $inst -trigger_now -cable 0} m]
puts "C3_RUN rc=$rc msg=$m"
if {$rc == 0} {
  puts "C3_WAIT=[catch {wait_on_hw_cw $inst -timeout 20 -cable 0} w] -> $w"
  puts "C3_STATE=[catch {check_cw_trigger $inst -cable 0} c] -> $c"
  puts "C3_CSV1=[catch {write_hw_cw_data $inst -csv_file $csv1} v] -> $v"
  puts "C3_CSV1_SIZE=[expr {[file isfile $csv1] ? [file size $csv1] : -1}] t=[clock format [clock seconds] -format %H:%M:%S]"
  after 11000
  puts "C3_RUN2=[catch {run_hw_cw $inst -trigger_now -cable 0} m2] -> $m2"
  puts "C3_WAIT2=[catch {wait_on_hw_cw $inst -timeout 20 -cable 0} w2] -> $w2"
  puts "C3_CSV2=[catch {write_hw_cw_data $inst -csv_file $csv2} v2] -> $v2"
  puts "C3_CSV2_SIZE=[expr {[file isfile $csv2] ? [file size $csv2] : -1}] t=[clock format [clock seconds] -format %H:%M:%S]"
  foreach f [list $csv1 $csv2] {
    if {[file isfile $f]} {
      set fh [open $f r]; set data [read $fh]; close $fh
      puts "C3_CSV_HEAD $f len=[string length $data]"
      set lines [split $data "\n"]
      puts "C3_CSV_LINES=[llength $lines]"
      for {set i 0} {$i < 3 && $i < [llength $lines]} {incr i} { puts "C3_CSV_ROW $i: [string range [lindex $lines $i] 0 400]" }
    }
  }
}
puts "C3_END t=[clock format [clock seconds] -format %H:%M:%S]"