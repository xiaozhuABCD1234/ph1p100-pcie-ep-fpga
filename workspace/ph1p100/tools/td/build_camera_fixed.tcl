# Preserve upstream syn_1/phy_1 results. Create new runs, no reset or deletion.
if {[catch {
    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    open_project ./fpga_prj.al
    create_run -constrset constraint_1 syn_pad_1
    create_run -constrset constraint_1 -syn_run syn_pad_1 phy_pad_1
    launch_runs {syn_pad_1 phy_pad_1} -jobs 2
    wait_run syn_pad_1 -quiet
    wait_run phy_pad_1 -quiet
    save_best_bits
    puts "CAMERA_FIXED_COMMANDS_RETURNED_CHECK_LOGS"
    close_project
} msg]} {
    puts stderr "CAMERA_FIXED_TCL_ERROR: $msg"
    exit 1
}
exit 0
