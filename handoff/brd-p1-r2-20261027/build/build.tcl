# =============================================================================
# build.tcl -- T11.BRD.P1 r2 one-session convenience flow (NO download, NO Flash)
#
# Run on the teammate machine from the repository root:
#   td_commands_prompt.exe -f handoff/brd-p1-r2-20261027/build/build.tcl
#
# synth -> route -> final STA gate -> bitgen, all in one TD session.  The
# phased entries 01..04 are the authoritative per-phase scripts (and 03/04 can
# be re-run after a review).  This file exists so a teammate can reproduce the
# whole build with one command; it never downloads and never writes Flash.
# =============================================================================
if {[catch {
    set BRD_REPO_ROOT [pwd]
    if {![file exists "$BRD_REPO_ROOT/handoff/brd-p1-r2-20261027/filelist.tcl"]} {
        error "run from the repository root (pwd=$BRD_REPO_ROOT)"
    }
    cd $BRD_REPO_ROOT/handoff/brd-p1-r2-20261027/build

    create_project brd_board ./ -family PH1 -device PH1P100SBG484 -speed 3 -force
    source $BRD_REPO_ROOT/handoff/brd-p1-r2-20261027/filelist.tcl
    top_module brd_integrated_top

    launch_runs { syn_1 } -jobs 4
    wait_run syn_1 -quiet
    if {[catch { report_timing_summary -file ./syn_timing_summary.rpt } e]} { puts "syn report skipped: $e" }

    launch_runs { phy_1 } -jobs 4
    wait_run phy_1 -quiet
    if {[catch { report_timing_summary -file ./routed_timing.rpt } e]} { puts "route report skipped: $e" }

    import_db ./brd_board_Runs/phy_1/brd_board_pr.db
    update_timing -mode final
    report_timing_summary -file ./candidate_timing.rpt
    report_timing_ignored  -file ./candidate_ignored.rpt -ep_num 50
    report_abnormal_timing_target -file ./candidate_abnormal.rpt
    if {[catch { report_cdc -file ./candidate_cdc.rpt } e]} { puts "report_cdc skipped: $e" }

    set fh [open ./candidate_timing.rpt r]
    set timing [read $fh]
    close $fh
    if {![regexp {SWNS: ([-+0-9.]+)ns, STNS: ([-+0-9.]+)ns} $timing unused sw st]} { error "Missing setup timing status" }
    if {![regexp {HWNS: ([-+0-9.]+)ns, HTNS: ([-+0-9.]+)ns} $timing unused hw ht]} { error "Missing hold timing status" }
    if {![regexp {Period Check WNS: ([-+0-9.]+)ns} $timing unused pw]} { error "Missing period timing status" }
    set gated 0
    if {$sw < 0.003 || $hw < 0 || $pw < 0 || $st != 0 || $ht != 0} {
        error "STA rejects bit generation: setup=$sw/$st hold=$hw/$ht period=$pw"
    }
    if {$sw < 0.05} { set gated 1 }
    puts "BRD_BITGEN_STA_SETUP=$sw/$st HOLD=$hw/$ht PERIOD=$pw THIN_MARGIN=$gated"
    bitgen -bit ./brd_board.bit
    close_project
    puts "BRD_BUILD_DONE_NO_DOWNLOAD"
} msg]} {
    puts stderr "BRD_BUILD_ERROR: $msg"
    exit 1
}
exit 0
