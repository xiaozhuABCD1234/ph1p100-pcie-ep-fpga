set f [open {"""+(r/'diagnostic_trace.log').as_posix()+"""} w]
puts $f "IPTOOL_DIAGNOSTIC_ENTERED"
flush $f
puts $f [lsort [info commands *ip*]]
puts $f [lsort [info commands *dialog*]]
if {[llength [info commands help]]} {
 set rc [catch {help generate_ipinst} msg]
 puts $f [list HELP_GENERATE_RC $rc $msg]
}
puts $f "IPTOOL_DIAGNOSTIC_EXIT"
close $f
exit 0
