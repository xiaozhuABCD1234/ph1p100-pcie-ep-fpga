# Checkpoint-specific diagnostic only. Run from the matching isolated project.
# No cable, SRAM programming, Flash programming or camera source changes.
if {[catch {
    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    open_project ./hdmi_diagnostic.al
    open_run phy_retry_1
    update_timing -mode final
    report_timing_summary -file ./candidate_final_timing.rpt
    report_abnormal_timing_target -file ./candidate_final_abnormal.rpt
    bitgen -bit D:/TD/work/csi2/prj/camera_peer/_evidence/hdmi_test_720p60_20261011.bit
    close_project
    puts "HDMI_720P60_DIAGNOSTIC_GENERATED_NO_DOWNLOAD"
} msg]} {
    puts stderr "HDMI_720P60_DIAGNOSTIC_ERROR: $msg"
    exit 1
}
exit 0
