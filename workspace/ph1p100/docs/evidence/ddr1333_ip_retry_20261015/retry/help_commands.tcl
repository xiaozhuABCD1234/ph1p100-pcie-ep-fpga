set f [open {D:/TD/work/csi2/_validation/iptool_retry_20261015_183510/help_commands.log} w]
puts $f [list GENERATION_COMMANDS [info commands *gen*] PARAM_COMMANDS [info commands *param*]]
foreach name {create_dialog create_iplib open_iplib import_ip info_ip} {
    set rc [catch {help -cmd $name} msg]
    puts $f [list $name $rc $msg]
    flush $f
}
close $f
exit 0
