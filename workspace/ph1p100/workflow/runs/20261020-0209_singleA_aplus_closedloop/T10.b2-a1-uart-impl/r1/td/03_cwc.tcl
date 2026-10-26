# =============================================================================
# T10.b2-a1-uart-impl r0 -- single ChipWatcher (CWC) export, paired with the
# same bitgen database. NO download, NO Flash, no cable access.
# Requires the bit/BID produced by 02_bitgen.tcl; the compiled debug bit must be
# byte-identical to that parent bit.
# =============================================================================
if {[catch {
    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    open_project ./a1_board.al
    import_db ./a1_board_Runs/phy_1/a1_board_pr.db
    if {[file exists ./a1_board.cwc]} { error "Preserve existing debug export" }
    report_cwc_status -file ./cwc_status_before.rpt
    if {![file exists ./a1_board.bit]} { error "Missing a1_board.bit from the single bitgen" }
    if {[file exists ./cw/compiled.cwc] || [file exists ./cw/compiled.bit]} {
        error "Preserve existing compiled debugger artifacts"
    }
    setup_debugger -prj a1_board
    if {![file exists ./cw/compiled.cwc] || ![file exists ./cw/compiled.bit]} {
        error "Missing paired debugger output"
    }
    set fh [open ./cw/compiled.cwc r]
    set cwc_text [read $fh]
    close $fh
    if {![regexp {<phy_eram } $cwc_text]} { error "Missing physical ERAM readback mapping" }
    if {[regexp {<logic_eram [^>]+/>} $cwc_text]} { error "Incomplete logical ERAM readback mapping" }
    set fh [open ./a1_board.bit rb]
    set parent_bit [read $fh]
    close $fh
    set fh [open ./cw/compiled.bit rb]
    set debug_bit [read $fh]
    close $fh
    if {$parent_bit ne $debug_bit} { error "Debugger bit changed: review artifacts before use" }
    file copy ./cw/compiled.cwc ./a1_board.cwc
    report_cwc_status -file ./cwc_status_after.rpt
    close_project
    puts "P2_MATCHING_CWC_EXPORTED_NO_DOWNLOAD"
} msg]} {
    puts stderr "P2_CWC_EXPORT_ERROR: $msg"
    exit 1
}
exit 0
