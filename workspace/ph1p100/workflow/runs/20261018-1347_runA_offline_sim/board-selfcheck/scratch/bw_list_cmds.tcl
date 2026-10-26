puts "BW_TCL_BEGIN"
puts "tcl_version=[info patchlevel]"
puts "cwd=[pwd]"
puts "commands_begin"
foreach c [lsort [info commands]] { puts $c }
puts "commands_end"
puts "BW_TCL_END"
exit 0
