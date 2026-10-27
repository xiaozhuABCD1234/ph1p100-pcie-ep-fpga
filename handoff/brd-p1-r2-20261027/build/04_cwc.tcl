# =============================================================================
# 04_cwc.tcl -- T11.BRD.P1 r2 single ChipWatcher export (NO download, NO cable)
#
# Run after 03_bitgen.tcl, from the repository root:
#   td_commands_prompt.exe -f handoff/brd-p1-r2-20261027/build/04_cwc.tcl
# Requires the bit produced by 03; the debug bit must be byte-identical,
# otherwise the script fails closed.
# =============================================================================
if {[catch {
    set BRD_REPO_ROOT [pwd]
    cd $BRD_REPO_ROOT/handoff/brd-p1-r2-20261027/build

    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    open_project ./brd_board.al
    import_db ./brd_board_Runs/phy_1/brd_board_pr.db
    if {[file exists ./brd_board.cwc]} { error "Preserve existing debug export" }
    report_cwc_status
    if {![file exists ./brd_board.bit]} { error "Missing brd_board.bit from the single bitgen" }
    if {[file exists ./cw/compiled.cwc] || [file exists ./cw/compiled.bit]} {
        error "Preserve existing compiled debugger artifacts"
    }
    setup_debugger -prj brd_board
    if {![file exists ./cw/compiled.cwc] || ![file exists ./cw/compiled.bit]} {
        error "Missing paired debugger output"
    }
    set fh [open ./cw/compiled.cwc r]
    set cwc_text [read $fh]
    close $fh
    if {![regexp {<phy_eram } $cwc_text]} { error "Missing physical ERAM readback mapping" }
    if {[regexp {<logic_eram [^>]+/>} $cwc_text]} { error "Incomplete logical ERAM readback mapping" }
    set fh [open ./brd_board.bit rb]
    set parent_bit [read $fh]
    close $fh
    set fh [open ./cw/compiled.bit rb]
    set debug_bit [read $fh]
    close $fh
    if {$parent_bit ne $debug_bit} { error "Debugger bit changed: review artifacts before use" }
    file copy ./cw/compiled.cwc ./brd_board.cwc
    report_cwc_status
    close_project
    puts "BRD_CWC_EXPORTED_NO_DOWNLOAD"
} msg]} {
    puts stderr "BRD_CWC_ERROR: $msg"
    exit 1
}
exit 0
