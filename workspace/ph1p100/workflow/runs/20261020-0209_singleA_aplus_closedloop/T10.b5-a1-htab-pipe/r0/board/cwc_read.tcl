config_chipwatcher D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b5-a1-htab-pipe/r0/td/a1_board.cwc
foreach n {dbg_cap_frames dbg_enc_frames dbg_exported dbg_raw_pub dbg_errors} {
  if {[catch {puts "$n PROBE=[get_cw_probes $n]"} e]} { puts "$n PERR: $e" }
}
if {[catch {puts "READ=[read_cwc_data]"} e]} { puts "READ_ERR: $e" }
exit
