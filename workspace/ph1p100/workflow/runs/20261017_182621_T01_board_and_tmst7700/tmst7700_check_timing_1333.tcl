# TMST-7700 detail enumeration (G follow-up, run 20261017_182621).
# Executed against a PRIVATE COPY of the DDR1333 routed project; the original
# candidate is never opened or written. No bitgen, no hardware, no flow re-run.
# Recipe mirrors the frozen bitgen resume body (import_device -> open_project ->
# import_db <pr db> -> update_timing -mode final), then adds check_timing.
if {[catch {
    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    open_project ./camera_ddr_display.al
    import_db ./csi_checked_debug_pr.db
    update_timing -mode final
    check_timing -file ./tmst7700_detail_1333.rpt -verbose
    puts "TMST7700_CHECKTIMING_RETURNED"
    if {[catch {report_drc -file ./tmst7700_drc_1333.txt} drcerr]} {
        puts "TMST7700_REPORT_DRC_WARN: $drcerr"
    } else {
        puts "TMST7700_REPORT_DRC_RETURNED"
    }
    close_project
    puts "TMST7700_DETAIL_DONE"
} msg]} {puts stderr "TMST7700_DETAIL_ERROR: $msg";exit 1}
exit 0
