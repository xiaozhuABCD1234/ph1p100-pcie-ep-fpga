# Run from a NEW isolated directory containing the matching RTL and SDC.
# Synthesis only: no board pin assignment, PnR, bitgen or download.
if {[catch {
    if {[file exists raw12_unpack.al]} {error "Use a fresh directory; preserve old runs"}
    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    create_project raw12_unpack ./ -family ph1 -device PH1P100SBG484 -speed -3
    add_files ./csi2_raw12_unpack.v
    add_files ./raw12_unpack.sdc
    top_module csi2_raw12_unpack
    launch_runs syn_1
    wait_run syn_1 -quiet
    open_run syn_1
    report_area -file ./raw12_unpack.area
    close_project
    puts "RAW12_SYN_COMMANDS_RETURNED_CHECK_LOGS"
} msg]} {
    puts stderr "RAW12_SYN_TCL_ERROR: $msg"
    exit 1
}
exit 0
