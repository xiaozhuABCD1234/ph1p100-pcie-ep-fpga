# Run in camera_peer; preserve all earlier source/build evidence.
# Stop at route/timing: do not generate or download a bit on failed timing.
if {[catch {
    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    open_project ./fpga_prj.al
    set stamp [clock format [clock seconds] -format %Y%m%d_%H%M%S]
    set syn_name "syn_seq_$stamp"
    set phy_name "phy_seq_$stamp"
    create_run -constrset constraint_1 $syn_name
    create_run -constrset constraint_1 -syn_run $syn_name $phy_name
    launch_runs $syn_name
    wait_run $syn_name -quiet
    launch_runs -step route $phy_name
    wait_run $phy_name -quiet
    open_run $phy_name
    update_timing -mode final
    report_timing_summary -file "./_evidence/${phy_name}_timing.rpt"
    report_area -file "./_evidence/${phy_name}.area"
    puts "RAW10_ROUTE_RETURNED_CHECK_LOGS $syn_name $phy_name"
    close_project
} msg]} {
    puts stderr "RAW10_SEQUENCE_TCL_ERROR: $msg"
    exit 1
}
exit 0
