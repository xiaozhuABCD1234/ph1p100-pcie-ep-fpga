# Run only from one prepared standalone DDR probe project. No hardware download.
# Recheck final timing before producing a candidate; fail closed on bad/missing STA.
if {[catch {
    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    open_project ./ddr_frame_probe.al
    # Explicit exported checkpoint avoids project-manager run status ambiguity.
    import_db ./ddr_frame_probe_Runs/phy_1/ddr_frame_probe_pr.db
    update_timing -mode final
    report_timing_summary -file ./candidate_timing.rpt
    report_timing_ignored -file ./candidate_ignored.rpt -ep_num 50
    report_abnormal_timing_target -file ./candidate_abnormal.rpt
    set fh [open ./candidate_timing.rpt r]
    set timing [read $fh]
    close $fh
    if {![regexp {SWNS: ([-+0-9.]+)ns, STNS: ([-+0-9.]+)ns} $timing unused sw st]} {
        error "Missing setup timing status"
    }
    if {![regexp {HWNS: ([-+0-9.]+)ns, HTNS: ([-+0-9.]+)ns} $timing unused hw ht]} {
        error "Missing hold timing status"
    }
    if {![regexp {Period Check WNS: ([-+0-9.]+)ns} $timing unused pw]} {
        error "Missing period timing status"
    }
    if {$sw < 0 || $hw < 0 || $pw < 0 || $st != 0 || $ht != 0} {
        error "STA rejects bit generation: setup=$sw/$st hold=$hw/$ht period=$pw"
    }
    bitgen -bit ./ddr_frame_probe.bit
    close_project
    puts "DDR_FRAME_CANDIDATE_GENERATED_NO_DOWNLOAD"
} msg]} {
    puts stderr "DDR_FRAME_CANDIDATE_ERROR: $msg"
    exit 1
}
exit 0
