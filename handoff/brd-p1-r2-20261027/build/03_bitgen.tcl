# =============================================================================
# 03_bitgen.tcl -- T11.BRD.P1 r2 single bitgen (NO download, NO Flash)
#
# Run after 02_route.tcl, from the repository root:
#   td_commands_prompt.exe -f handoff/brd-p1-r2-20261027/build/03_bitgen.tcl
#
# Gate (frozen order):
#   * 0 violated setup AND hold endpoints
#   * setup WNS >= +0.003 ns (>= +0.05 normal, +0.003..+0.05 thin margin)
#   * hold WNS >= 0, period check WNS >= 0
# The script fails closed and produces NO bit if the gate fails.
# This is the teammate's build gate; r0's -2.273 ns / 79 endpoints are history.
# =============================================================================
if {[catch {
    set BRD_REPO_ROOT [pwd]
    cd $BRD_REPO_ROOT/handoff/brd-p1-r2-20261027/build

    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    open_project ./brd_board.al
    import_db ./brd_board_Runs/phy_1/brd_board_pr.db
    update_timing -mode final
    report_timing_summary -file ./candidate_timing.rpt
    report_timing_ignored  -file ./candidate_ignored.rpt -ep_num 50
    report_abnormal_timing_target -file ./candidate_abnormal.rpt
    report_path_skew -file ./candidate_skew.rpt -ep_num 40
    if {[catch { report_cdc -file ./candidate_cdc.rpt } e]} { puts "report_cdc skipped: $e" }

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
    set gated 0
    if {$sw < 0.003 || $hw < 0 || $pw < 0 || $st != 0 || $ht != 0} {
        error "STA rejects bit generation: setup=$sw/$st hold=$hw/$ht period=$pw (need setup>=+0.003, 0 endpoints)"
    }
    if {$sw < 0.05} { set gated 1 } else { set gated 0 }
    set fh [open ./candidate_abnormal.rpt r]
    set abnormal [read $fh]
    close $fh
    if {[regexp {End Point:} $abnormal]} { error "Abnormal timing endpoints remain" }

    puts "BRD_BITGEN_STA_SETUP=$sw/$st HOLD=$hw/$ht PERIOD=$pw THIN_MARGIN=$gated"
    bitgen -bit ./brd_board.bit
    close_project
    puts "BRD_BIT_GENERATED_NO_DOWNLOAD"
} msg]} {
    puts stderr "BRD_BITGEN_ERROR: $msg"
    exit 1
}
exit 0
