foreach c {get_cw_probes get_vpi_probes read_cwc_data read_cwc_reg report_cwc_status} {
  if {[catch {puts "$c => [$c]"} e]} { puts "$c ERR: $e" }
}
exit
