# Checkpoint-specific candidate generation after independently reviewed STA.
# Run only with the matching archived sources; no download or Flash operation.
if {[catch {
    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    open_project ./fpga_prj.al
    open_run phy_stable_20261010_234257
    update_timing -mode final
    report_timing_summary -file ./_evidence/raw10_candidate_final_timing.rpt
    report_abnormal_timing_target -file ./_evidence/raw10_candidate_final_abnormal.rpt
    bitgen -bit ./_evidence/raw10_891_gray_1080p30_20261010_234257.bit
    puts "RAW10_CANDIDATE_BIT_GENERATED_NO_DOWNLOAD"
    close_project
} msg]} {
    puts stderr "RAW10_CANDIDATE_ERROR: $msg"
    exit 1
}
exit 0
