# Read-only calculation using installed PH1P PLL wizard procedures.
# Does not generate IP, open a project, alter installed files or build hardware.
# The dependency declarations are ignored; only their Tcl calculation procs run.
proc set_param {args} {}
set IP_DEVICE PH1P100SBG484
source D:/downlaod/ip/depot/PLLF6F1D0P0_1.1/Dependency.tcl
set enables {1 1 1 0 0 0 0 0}
set freqs {74.25 371.25 27 100 100 100 100 100}
set units {MHz MHz MHz MHz MHz MHz MHz MHz}
set phases {0 0 0 0 0 0 0 0}
set phase_units {deg deg deg deg deg deg deg deg}
foreach config {{NORMAL 0 0} {NORMAL 2 0} {NOCOMP -1 1}} {
    lassign $config mode feedback fractional
    puts "WIZARD_CALC_CONFIG $config"
    if {[catch {
        set divs [Calc_Dividers 50 $feedback $mode $enables $freqs $units $phases $phase_units 0 $fractional $feedback 1]
        puts "DIVIDERS $divs"
        set psc [lrange $divs 0 7]
        set vco [lindex $divs 8]
        set div [lindex $divs 10]
        set mul [lindex $divs 11]
        set frac [Calc_VCO_Fractional_auto 50 $mul $div $vco $fractional $enables $freqs $units $psc $feedback $mode]
        puts "FRACTIONAL_RESULT $frac"
        set actual [Calc_ActualFreq [lindex $frac 0] 1 $psc $psc]
        puts "ACTUAL_MHZ $actual"
        set bandwidth [get_BandWidth [lindex $divs 9]]
        set_error_disp [lindex $frac 0] 0 [lindex $divs 9] $fractional 0 $actual 0 [lindex $actual 0] $enables $feedback [lindex $frac 3] {*}[lrange $psc 0 6] $bandwidth
        puts "WIZARD_PARAM_ERROR_FLAG $IP_GEN_PARAM_ERROR_FLAG BANDWIDTH $bandwidth MESSAGE $IP_GEN_PARAM_ERROR_MSG"
        if {$mode eq "NOCOMP"} {
            if {$IP_GEN_PARAM_ERROR_FLAG} {error $IP_GEN_PARAM_ERROR_MSG}
            foreach got [lrange $actual 0 2] target [lrange $freqs 0 2] {
                if {abs($got-$target) > 0.000001} {error "Frequency mismatch $got / $target"}
            }
            puts "RAW10_PLL_WIZARD_CALC_PASS"
        }
    } msg]} {
        puts stderr "WIZARD_CALC_ERROR $msg"
        exit 1
    }
}
puts "WIZARD_CALC_ONLY_NO_IP_GENERATED"
exit 0
