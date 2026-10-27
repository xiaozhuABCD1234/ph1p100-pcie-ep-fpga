# Run only from one prepared camera capture project. No hardware download.
# Recheck final timing before producing a candidate; fail closed on bad/missing STA.
if {[catch {
    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    if {![info exists display_project]} {set display_project ./camera_ddr_display.al}
    if {![info exists display_checkpoint]} {set display_checkpoint ./camera_ddr_display_Runs/phy_1/camera_ddr_display_pr.db}
    open_project $display_project
    # Explicit exported checkpoint avoids project-manager run status ambiguity.
    import_db $display_checkpoint
    update_timing -mode final
    report_timing_summary -file ./candidate_timing.rpt
    report_timing_ignored -file ./candidate_ignored.rpt -ep_num 50
    report_abnormal_timing_target -file ./candidate_abnormal.rpt
    report_path_skew -file ./candidate_skew.rpt -ep_num 20
    set fh [open ./candidate_timing.rpt r]
    set timing [read $fh]
    close $fh
    if {![regexp {SWNS: ([-+0-9.]+)ns, STNS: ([-+0-9.]+)ns} $timing unused sw st]} {
        error "Missing setup timing status"
    }
    if {![regexp {HWNS: ([-+0-9.]+)ns, HTNS: ([-+0-9.]+)ns} $timing unused hw ht]} {
        error "Missing hold timing status"
    }
    if {![regexp {Period Check WNS: ([-+0-9.]+)ns} $timing unused pw]} {
        error "Missing period timing status"
    }
    if {$sw < 0 || $hw < 0 || $pw < 0 || $st != 0 || $ht != 0} {
        error "STA rejects bit generation: setup=$sw/$st hold=$hw/$ht period=$pw"
    }
    set fh [open ./candidate_skew.rpt r]
    set skew [read $fh]
    close $fh
    if {[regexp -all {(?m)^[0-9]+,  set_path_skew} $skew] != 4} {
        error "Missing two-FIFO bidirectional Gray bus skew constraints"
    }
    set values [regexp -all -inline {(?m)^Slack +: ([-+0-9.]+)ns} $skew]
    if {[llength $values] < 8} {error "Missing Gray bus skew results"}
    foreach {line slack} $values {if {$slack < 0} {error "Gray bus skew violation"}}
    set fh [open ./candidate_abnormal.rpt r]
    set abnormal [read $fh]
    close $fh
    if {[regexp {End Point:} $abnormal]} {error "Abnormal timing endpoints remain"}
    # Native preflight must also verify input hashes and exported Gray/sync boundaries.
    bitgen -bit ./camera_ddr_display.bit
    close_project
    puts "CAMERA_DDR_DISPLAY_CANDIDATE_GENERATED_NO_DOWNLOAD"
} msg]} {
    puts stderr "CAMERA_DDR_DISPLAY_CANDIDATE_ERROR: $msg"
    exit 1
}
exit 0
