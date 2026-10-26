import_db ./route_db/a1_hp_r0_pr.db
update_timing -mode final
report_clock_utilization -file ./tester_clock_util.rpt
check_timing -verbose -file ./tester_check_timing.rpt
report_timing_summary -file ./tester_timing_summary.rpt
report_timing -file ./tester_timing.rpt
puts "TESTER_REPORTS_DONE"
exit
