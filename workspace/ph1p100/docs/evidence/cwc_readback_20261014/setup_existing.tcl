# Official post-bitgen setup, using byte-identical copies of the existing bit/BID.
# No synthesis, routing, bitgen, hardware connection or download.
if {[file exists ./cw/compiled.cwc] || [file exists ./cw/compiled.bit]} {
    error "Preserve existing setup output"
}
set parent_root D:/TD/work/csi2/prj/camera_rgb565_20261014_140836
if {[catch {
    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    open_project $parent_root/camera_ddr_display.al
    import_db $parent_root/csi_checked_debug_pr.db
    setup_debugger -prj camera_ddr_display
    if {![file exists ./cw/compiled.cwc] || ![file exists ./cw/compiled.bit]} {
        error "Missing paired debugger artifacts"
    }
    puts "OFFICIAL_SETUP_EXISTING_BIT_BID_SUCCESS_NO_BUILD_NO_DOWNLOAD"
} msg]} {
    puts stderr "CWC_SETUP_ERROR: $msg"
    exit 1
}
exit 0
