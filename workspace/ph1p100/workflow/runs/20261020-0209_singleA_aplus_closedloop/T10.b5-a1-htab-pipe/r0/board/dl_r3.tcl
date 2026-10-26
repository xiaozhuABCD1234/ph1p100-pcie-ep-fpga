set BIT {D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b2-a1-uart-impl/r3/td/a1_board.bit}
if {[catch {connect_cable -host_name 127.0.0.1:5555 -open} e]} { puts "CONNFAIL: $e"; exit 4 }
if {[catch {download -bit $BIT -mode jtag -spd 7 -cable 0} e]} { puts "DLFAIL: $e"; exit 5 }
puts "DLOK"
exit 0
