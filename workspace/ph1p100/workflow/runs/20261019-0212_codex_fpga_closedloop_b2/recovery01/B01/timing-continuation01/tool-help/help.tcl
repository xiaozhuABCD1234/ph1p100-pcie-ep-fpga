foreach c {fix_hold phys_opt set_run_options set_run_option set_option launch_runs} {
 puts "HELP_BEGIN $c"
 if {[catch {help $c} msg]} {puts "HELP_ERROR $msg"}
 puts "HELP_END $c"
}
exit
