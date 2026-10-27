# SWUG105 sections 4.1.1, 4.1.3, 4.1.11-14. Run from camera_peer directory.
# This script builds only. It never connects a cable or programs a board.
if {[catch {
    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    open_project ./fpga_prj.al
    puts "CAMERA_PROJECT_OPENED"
    launch_runs {syn_1 phy_1} -jobs 2
    wait_run syn_1 -quiet
    wait_run phy_1 -quiet
    save_best_bits
    puts "CAMERA_BUILD_COMMANDS_RETURNED_CHECK_LOGS"
    close_project
} msg]} {
    puts stderr "CAMERA_BUILD_TCL_ERROR: $msg"
    exit 1
}
exit 0
