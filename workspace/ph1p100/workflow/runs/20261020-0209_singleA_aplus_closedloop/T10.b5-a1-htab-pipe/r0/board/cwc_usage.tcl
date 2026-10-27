foreach c {set_cwc config_chipwatcher read_cwc_data enable_prcwc} {
  if {[catch {$c} e]} { puts "$c USAGE_ERR: $e" } else { puts "$c OK" }
}
exit
