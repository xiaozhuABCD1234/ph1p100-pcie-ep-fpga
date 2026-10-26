config_chipwatcher D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b5-a1-htab-pipe/r0/td/a1_board.cwc
foreach n {auto_created_cwc1 auto_created_cwc2} {
  if {[catch {puts "$n PROBES=[get_cw_probes $n]"} e]} { puts "$n ERR: $e" }
}
exit
