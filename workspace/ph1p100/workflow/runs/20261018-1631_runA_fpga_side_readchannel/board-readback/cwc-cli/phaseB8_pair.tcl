set pair "C:/Users/czz/AppData/Local/Temp/runa_p3/cw_pair/compiled.cwc"
set orig "C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261018-1631_runA_fpga_side_readchannel/debug-fix/prj/ph1p_pcie_integration_Runs/phy_1/cw/compiled.cwc"
set csv1 "C:/Users/czz/AppData/Local/Temp/runa_p3/cwc_sample1.csv"
set csv2 "C:/Users/czz/AppData/Local/Temp/runa_p3/cwc_sample2.csv"
set inst auto_created_cwc1
puts "CWC_B8_START t=[clock format [clock seconds] -format %H:%M:%S]"
puts "B8_PAIR_FILE=[file isfile $pair] ORIG_FILE=[file isfile $orig]"
set done 0
foreach {tag path} [list PAIRED $pair ORIG $orig] {
  if {$done} { break }
  puts "B8_TRY $tag path=$path"
  puts "B8_$tag_CONFIG=[catch {config_chipwatcher $path} r] -> $r"
  puts "B8_$tag_STATUS=[catch {report_cwc_status $inst} s] -> $s"
  puts "B8_$tag_HWS=[catch {get_hw_cws *} h] -> $h"
  set rc [catch {run_hw_cw $inst -trigger_now -cable 0} m]
  puts "B8_$tag_RUN rc=$rc msg=$m"
  if {$rc == 0} {
    puts "B8_$tag_WAIT=[catch {wait_on_hw_cw $inst -timeout 20 -cable 0} w] -> $w"
    puts "B8_$tag_STATE=[catch {check_cw_trigger $inst -cable 0} c] -> $c"
    puts "B8_$tag_CSV1=[catch {write_hw_cw_data $inst -csv_file $csv1} v] -> $v"
    puts "B8_CSV1_EXISTS=[file isfile $csv1] size=[expr {[file isfile $csv1] ? [file size $csv1] : -1}] t=[clock format [clock seconds] -format %H:%M:%S]"
    after 11000
    puts "B8_$tag_RUN2=[catch {run_hw_cw $inst -trigger_now -cable 0} m2] -> $m2"
    puts "B8_$tag_WAIT2=[catch {wait_on_hw_cw $inst -timeout 20 -cable 0} w2] -> $w2"
    puts "B8_$tag_CSV2=[catch {write_hw_cw_data $inst -csv_file $csv2} v2] -> $v2"
    puts "B8_CSV2_EXISTS=[file isfile $csv2] size=[expr {[file isfile $csv2] ? [file size $csv2] : -1}] t=[clock format [clock seconds] -format %H:%M:%S]"
    set done 1
  }
}
puts "CWC_B8_END t=[clock format [clock seconds] -format %H:%M:%S]"