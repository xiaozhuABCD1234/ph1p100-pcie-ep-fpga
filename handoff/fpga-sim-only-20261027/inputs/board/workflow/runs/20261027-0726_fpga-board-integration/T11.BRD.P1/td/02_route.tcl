# =============================================================================
# 02_route.tcl -- T11.BRD.P1 place & route only (one TD session, no download)
#   Opens the project created by 01_synth.tcl and launches phy_1.
#   Fails closed if the synthesised run directory is missing.
# =============================================================================
if {[catch {
    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    open_project ./brd_board.al

    if {![file exists ./brd_board_Runs/syn_1]} { error "missing syn_1 (run 01_synth.tcl first)" }

    launch_runs { phy_1 } -jobs 4
    wait_run phy_1 -quiet

    if {[catch { report_area   -file ./phy_area.rpt }   e]} { puts "report_area skipped: $e" }
    if {[catch { report_timing -file ./phy_timing.rpt } e]} { puts "report_timing skipped: $e" }
    if {[catch { report_timing_summary -file ./routed_timing.rpt } e]} { puts "report_timing_summary skipped: $e" }

    close_project
    puts "BRD_ROUTE_DONE"
} msg]} {
    puts stderr "BRD_ROUTE_ERROR: $msg"
    exit 1
}
exit 0
