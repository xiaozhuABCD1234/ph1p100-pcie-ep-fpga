# TMST-7700 detail enumeration, place-stage comparator (G follow-up, run 20261017_182621).
# Uses the place checkpoint to discriminate which HIGH checks exist before routing
# (the flow reported 1 SEVERE at its place-stage checker). Private copy only.
if {[catch {
    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    open_project ./camera_ddr_display.al
    import_db ./csi_checked_place.db
    if {[catch {update_timing -mode final} uerr]} {
        puts "TMST7700_PLACE_UPDATE_TIMING_WARN: $uerr"
    }
    check_timing -file ./tmst7700_detail_1333_place.rpt -verbose
    puts "TMST7700_PLACE_CHECKTIMING_RETURNED"
    close_project
    puts "TMST7700_PLACE_DONE"
} msg]} {puts stderr "TMST7700_PLACE_ERROR: $msg";exit 1}
exit 0
