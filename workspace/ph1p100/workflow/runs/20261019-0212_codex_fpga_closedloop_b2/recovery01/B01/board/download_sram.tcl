# B01 volatile SRAM entry. Execute only in the separately dispatched board task
# after the integrated reports bind the exact frozen manifest.
set bit_file [file normalize [file join [file dirname [info script]] .. candidate current.bit]]
if {![file isfile $bit_file]} { puts "B01_SRAM_ABORT bit_missing"; exit 2 }
set args_s {-r -s 5555 -f 12 -v -w 5556 -i 0}
if {[catch {connect_cable -host_name 127.0.0.1:5555 -usr_args [list $args_s] -open} err]} {
    puts "B01_SRAM_ABORT connect_failed=$err"; exit 3
}
if {[catch {read_device_id} id]} {puts "B01_SRAM_ABORT identity_failed=$id";catch {connect_cable -close};exit 4}
puts "B01_SRAM_DEVICE=$id"
if {[string first PH1P100 $id]<0} {puts "B01_SRAM_ABORT wrong_device";catch {connect_cable -close};exit 5}
set rc [catch {download -bit $bit_file -mode jtag -spd 7 -cable 0} err]
puts "B01_SRAM_DOWNLOAD_RC=$rc message=$err"
catch {connect_cable -close}
if {$rc!=0} {puts "B01_SRAM_FAIL";exit 6}
puts "B01_SRAM_PASS"
exit 0
