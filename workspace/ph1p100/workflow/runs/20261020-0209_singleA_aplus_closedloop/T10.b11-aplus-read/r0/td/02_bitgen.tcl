# =============================================================================
# T10.b2-a1-uart-impl r0 -- single bitgen attempt (NO download, NO Flash).
# Opens the same routed database, re-checks final STA, then generates one .bit.
# Fails closed on negative/missing setup, hold or period status.
# =============================================================================
if {[catch {
    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    open_project ./a1_board.al
    import_db ./a1_board_Runs/phy_1/a1_board_pr.db
    update_timing -mode final
    report_timing_summary -file ./candidate_timing.rpt
    report_timing_ignored -file ./candidate_ignored.rpt -ep_num 50
    report_abnormal_timing_target -file ./candidate_abnormal.rpt
    report_path_skew -file ./candidate_skew.rpt -ep_num 40

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
    set fh [open ./candidate_abnormal.rpt r]
    set abnormal [read $fh]
    close $fh
    if {[regexp {End Point:} $abnormal]} { error "Abnormal timing endpoints remain" }

    puts "P2_BITGEN_STA_SETUP=$sw/$st HOLD=$hw/$ht PERIOD=$pw"
    bitgen -bit ./a1_board.bit
    close_project
    puts "P2_CANDIDATE_BIT_GENERATED_NO_DOWNLOAD"
} msg]} {
    puts stderr "P2_BITGEN_ERROR: $msg"
    exit 1
}
exit 0
