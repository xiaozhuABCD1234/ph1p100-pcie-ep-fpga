# RunA P3 cwc_cli_probe - Phase B4: enumerate watcher/probe object names (single session)
# Read-only; no download, no flash, no GUI automation.
set cwc  "C:/Users/czz/AppData/Local/Temp/runa_p3/compiled_debug.cwc"
set d1   "C:/Users/czz/AppData/Local/Temp/runa_p3/export_chipwatcher.txt"
set d2   "C:/Users/czz/AppData/Local/Temp/runa_p3/export_probe_config.txt"
puts "CWC_B4_START t=[clock format [clock seconds] -format %H:%M:%S]"
puts "B4_CONFIG=[catch {config_chipwatcher $cwc} r] -> $r"
proc show {label script} {
  if {[catch {uplevel 1 $script} r]} { puts "$label ERR: $r" } else { puts "$label OK: $r" }
}
show "B4_HWS_ALL"    {get_hw_cws *}
show "B4_HWS_VERB"   {get_hw_cws auto_created_cwc1 -verbose}
show "B4_PROBES_STAR" {get_cw_probes *}
show "B4_PROBES_SLASH" {get_cw_probes auto_created_cwc1/*}
show "B4_PROBES_NOCASE" {get_cw_probes * -nocase}
show "B4_EXPORT_CW" {export_chipwatcher $d1}
show "B4_EXPORT_PROBES" {export_chipprobe_config $d2}
foreach f [list $d1 $d2] {
  puts "B4_FILE $f exists=[file isfile $f] size=[expr {[file isfile $f] ? [file size $f] : -1}]"
  if {[file isfile $f]} {
    set fh [open $f r]; set data [read $fh]; close $fh
    puts "B4_FILE_BEGIN $f"
    puts $data
    puts "B4_FILE_END $f"
  }
}
puts "CWC_B4_END t=[clock format [clock seconds] -format %H:%M:%S]"
