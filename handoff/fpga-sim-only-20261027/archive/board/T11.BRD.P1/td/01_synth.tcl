# =============================================================================
# 01_synth.tcl -- T11.BRD.P1 synthesis only (one TD session, no download)
#   create_project + guarded filelist + launch syn_1 + reports
# Run from the td dir with td_commands_prompt.exe (see tools/board_integration/run_td.ps1)
# =============================================================================
if {[catch {
    set PRJ brd_board
    create_project $PRJ ./ -family PH1 -device PH1P100SBG484 -speed 3 -force

    source ./filelist.tcl

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
