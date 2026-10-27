# Run from D:/TD/work/csi2/prj/camera_peer. No bit generation or download here.
if {[catch {
    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    open_project ./fpga_prj.al
    set stamp [clock format [clock seconds] -format %Y%m%d_%H%M%S]
    set syn_name "syn_stable_$stamp"
    set phy_name "phy_stable_$stamp"
    create_run -constrset constraint_1 $syn_name
    create_run -constrset constraint_1 -syn_run $syn_name $phy_name
    puts "RAW10_STABLE_RUNS $syn_name $phy_name"
    launch_runs $syn_name
    wait_run $syn_name -quiet
    launch_runs -step route $phy_name
    wait_run $phy_name -quiet
    open_run $phy_name
    update_timing -mode final
    report_timing_summary -file "./_evidence/${phy_name}_timing.rpt"
    report_timing_ignored -file "./_evidence/${phy_name}_ignored.rpt" -ep_num 50
    report_abnormal_timing_target -file "./_evidence/${phy_name}_abnormal.rpt"
    report_area -file "./_evidence/${phy_name}.area"
    puts "RAW10_STABLE_ROUTE_RETURNED_CHECK_REPORTS $syn_name $phy_name"
    close_project
} msg]} {
    puts stderr "RAW10_STABLE_TCL_ERROR: $msg"
    exit 1
}
exit 0
