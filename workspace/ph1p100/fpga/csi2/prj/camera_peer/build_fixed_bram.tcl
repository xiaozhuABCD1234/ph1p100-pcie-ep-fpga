# Preserve upstream syn_1/phy_1 results. Create new runs, no reset or deletion.
if {[catch {
    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    open_project ./fpga_prj.al
    create_run -constrset constraint_1 syn_fix_2
    create_run -constrset constraint_1 -syn_run syn_fix_2 phy_fix_2
    launch_runs {syn_fix_2 phy_fix_2} -jobs 2
    wait_run syn_fix_2 -quiet
    wait_run phy_fix_2 -quiet
    save_best_bits
    puts "CAMERA_FIXED_COMMANDS_RETURNED_CHECK_LOGS"
    close_project
} msg]} {
    puts stderr "CAMERA_FIXED_TCL_ERROR: $msg"
    exit 1
}
exit 0
