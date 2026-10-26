set cwc "C:/Users/czz/AppData/Local/Temp/runa_p3/compiled_debug.cwc"
set csv1 "C:/Users/czz/AppData/Local/Temp/runa_p3/cwc_sample1.csv"
set csv2 "C:/Users/czz/AppData/Local/Temp/runa_p3/cwc_sample2.csv"
set inst auto_created_cwc1
puts "CWC_B7_START t=[clock format [clock seconds] -format %H:%M:%S]"
puts "B7_CONFIG=[catch {config_chipwatcher $cwc} r] -> $r"
proc tryc {label script} { if {[catch {uplevel 1 $script} m]} { puts "B7_$label ERR: $m" } else { puts "B7_$label OK: $m" } }
tryc LISTCABLE {list_cable}
tryc CONNECT1 {connect_cable -host_name 127.0.0.1:5555 -open}
tryc CONNECT2 {connect_cable}
tryc HWS {get_hw_cws *}
tryc RUN {run_hw_cw $inst -trigger_now -cable 0}
tryc WAIT {wait_on_hw_cw $inst -timeout 20 -cable 0}
tryc STATE {check_cw_trigger $inst -cable 0}
tryc CSV1 {write_hw_cw_data $inst -csv_file $csv1}
puts "B7_CSV1_EXISTS=[file isfile $csv1] size=[expr {[file isfile $csv1] ? [file size $csv1] : -1}]"
after 11000
tryc RUN2 {run_hw_cw $inst -trigger_now -cable 0}
tryc WAIT2 {wait_on_hw_cw $inst -timeout 20 -cable 0}
tryc CSV2 {write_hw_cw_data $inst -csv_file $csv2}
puts "B7_CSV2_EXISTS=[file isfile $csv2] size=[expr {[file isfile $csv2] ? [file size $csv2] : -1}]"
puts "CWC_B7_END t=[clock format [clock seconds] -format %H:%M:%S]"