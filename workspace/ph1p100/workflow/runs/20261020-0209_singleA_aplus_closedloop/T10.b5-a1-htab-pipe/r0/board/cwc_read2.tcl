config_chipwatcher D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b5-a1-htab-pipe/r0/td/a1_board.cwc
if {[catch {connect_cable -host_name 127.0.0.1:5555 -open} e]} { puts "CONNFAIL: $e" }
if {[catch {puts "READ=[read_cwc_data]"} e]} { puts "READ_ERR: $e" }
catch {connect_cable -close}
exit
