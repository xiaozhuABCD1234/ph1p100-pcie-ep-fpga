# RunA B1: SRAM download of current candidate bit (PH1P100 EP integration)
# SRAM ONLY - never flash.  -mode jtag == PROGRAM SRAM (volatile).
# bit path supplied via env var RUNA_BIT (avoids non-ASCII argv mangling)
# bit sha256(expected, verified via PowerShell before launch):
#   e81d353b284cb4e99ec86bcd7d511691cda187254f801c4832916f0000692b9a
# size expected 5224023
set bit_file $::env(RUNA_BIT)
set expect_size 5224023
set srv 127.0.0.1:5555
set args_s {-r -s 5555 -f 12 -v -w 5556 -i 0}

puts "RUNA_DL_START bit=$bit_file"
if {![file isfile $bit_file]} { puts "RUNA_DL_ABORT bit_file_missing"; exit }
set sz [file size $bit_file]
puts "RUNA_DL_BIT_SIZE=$sz"
if {$sz != $expect_size} { puts "RUNA_DL_ABORT size_mismatch expected=$expect_size"; exit }

set ok 0
if {![catch {connect_cable -host_name $srv -usr_args [list $args_s] -open} err]} {
  puts "RUNA_DL_CONNECT_OK variant=host_name+usr_args"
  set ok 1
} else {
  puts "RUNA_DL_CONNECT_V1_FAIL: $err"
}
if {!$ok} {
  if {![catch {connect_cable -host_name $srv -open} err]} {
    puts "RUNA_DL_CONNECT_OK variant=host_name"
    set ok 1
  } else {
    puts "RUNA_DL_CONNECT_V2_FAIL: $err"
  }
}
puts "RUNA_DL_CABLE_CONNECTED=$ok"
if {!$ok} { puts "RUNA_DL_END result=connect_failed"; exit }

set rc [catch {download -bit $bit_file -mode jtag -spd 7 -cable 0} derr]
puts "RUNA_DL_DOWNLOAD_RC=$rc"
puts "RUNA_DL_DOWNLOAD_MSG=$derr"

if {$rc == 0} {
  if {[catch {read_device_id} id]} {
    puts "RUNA_DL_DEVICE_ID_FAIL: $id"
  } else {
    puts "RUNA_DL_DEVICE_ID=$id"
  }
}
catch {connect_cable -close}
puts "RUNA_DL_CABLE_CLOSED"
if {$rc == 0} { puts "RUNA_DL_END result=ok" } else { puts "RUNA_DL_END result=download_error" }
exit
