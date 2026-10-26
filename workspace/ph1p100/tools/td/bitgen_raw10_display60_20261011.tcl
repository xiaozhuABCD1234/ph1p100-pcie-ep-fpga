# Run-specific candidate after routed STA review. No SRAM/Flash download.
if {[catch {
    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    open_project ./fpga_prj.al
    open_run phy_display60_20261011_174231
    update_timing -mode final
    report_timing_summary -file ./_evidence/raw10_display60_candidate_timing.rpt
    report_abnormal_timing_target -file ./_evidence/raw10_display60_candidate_abnormal.rpt
    bitgen -bit ./_evidence/raw10_891_gray_1080p60_20261011_174231.bit
    puts "RAW10_DISPLAY60_BIT_GENERATED_NO_DOWNLOAD"
    close_project
} msg]} {
    puts stderr "RAW10_DISPLAY60_BIT_ERROR: $msg"
    exit 1
}
exit 0
