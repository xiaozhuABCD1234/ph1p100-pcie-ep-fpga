# =============================================================================
# 01_synth.tcl -- T11.BRD.P1 r1 synthesis only (NO download, NO Flash)
#
# Run on the TEAMMATE machine from the repository root:
#   td_commands_prompt.exe -f handoff/brd-p1-r1-20261027/build/01_synth.tcl
#
# Creates brd_board in build/, sources the guarded repo-relative filelist,
# launches syn_1 and writes reports.  It never downloads anything.
# =============================================================================
if {[catch {
    set BRD_REPO_ROOT [pwd]
    if {![file exists "$BRD_REPO_ROOT/handoff/brd-p1-r1-20261027/filelist.tcl"]} {
        error "run from the repository root (pwd=$BRD_REPO_ROOT)"
    }
    cd $BRD_REPO_ROOT/handoff/brd-p1-r1-20261027/build

    create_project brd_board ./ -family PH1 -device PH1P100SBG484 -speed 3 -force
    source $BRD_REPO_ROOT/handoff/brd-p1-r1-20261027/filelist.tcl
    top_module brd_integrated_top

    launch_runs { syn_1 } -jobs 4
    wait_run syn_1 -quiet

    if {[catch { report_area   -file ./syn_area.rpt }           e]} { puts "report_area skipped: $e" }
    if {[catch { report_timing -file ./syn_timing.rpt }         e]} { puts "report_timing skipped: $e" }
    if {[catch { report_timing_summary -file ./syn_timing_summary.rpt } e]} { puts "report_timing_summary skipped: $e" }

    close_project
    puts "BRD_SYNTH_DONE"
} msg]} {
    puts stderr "BRD_SYNTH_ERROR: $msg"
    exit 1
}
exit 0
