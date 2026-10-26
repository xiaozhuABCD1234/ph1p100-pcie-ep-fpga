config_chipwatcher D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b5-a1-htab-pipe/r0/td/a1_board.cwc
connect_cable -host_name 127.0.0.1:5555 -open
foreach c {
 {set_cwc auto_created_cwc1 -trigger {dbg_cap_frames[0]}}
 {set_cwc -trigger dbg_cap_frames[0]}
 {set_cwc auto_created_cwc1 dbg_cap_frames[0]}
 {set_cwc auto_created_cwc1 -trigger dbg_cap_frames[0] -edge rising}
} { if {![catch {eval $c} e]} { puts "OK: $c" } else { puts "ERR: $c -> $e" } }
catch {connect_cable -close}
exit
