# RunA P3: SRAM download of debug candidate bit (PH1P100 EP integration, CWC debug)
# SRAM ONLY - never flash/efuse/SPI/svf.  -mode jtag == PROGRAM SRAM (volatile).
# bit path supplied via env var RUNA_P3_BIT (ASCII path only; avoids non-ASCII argv mangling)
# expected sha256: 2385CDEDAE1D9985687360AF77341183517E34CB18BE9CAD0229291593411873
# expected size  : 5224027
set bit_file $::env(RUNA_P3_BIT)
set expect_size 5224027
set srv 127.0.0.1:5555
set args_s {-r -s 5555 -f 12 -v -w 5556 -i 0}
set expect_id PH1P100

puts "RUNA_P3_DL_START bit=$bit_file"
if {![file isfile $bit_file]} { puts "RUNA_P3_DL_ABORT bit_file_missing"; exit 2 }
set sz [file size $bit_file]
puts "RUNA_P3_DL_BIT_SIZE=$sz"
if {$sz != $expect_size} { puts "RUNA_P3_DL_ABORT size_mismatch expected=$expect_size"; exit 2 }

set ok 0
if {![catch {connect_cable -host_name $srv -usr_args [list $args_s] -open} err]} {
  puts "RUNA_P3_CONNECT_OK variant=host_name+usr_args"
  set ok 1
} else {
  puts "RUNA_P3_CONNECT_V1_FAIL: $err"
}
if {!$ok} {
  if {![catch {connect_cable -host_name $srv -open} err]} {
    puts "RUNA_P3_CONNECT_OK variant=host_name"
    set ok 1
  } else {
    puts "RUNA_P3_CONNECT_V2_FAIL: $err"
  }
}
puts "RUNA_P3_CABLE_CONNECTED=$ok"
if {!$ok} { puts "RUNA_P3_DL_END result=connect_failed"; exit 3 }

set id ""
if {[catch {read_device_id} id]} {
  puts "RUNA_P3_PRE_DEVICE_ID_FAIL: $id"
  catch {connect_cable -close}
  puts "RUNA_P3_DL_END result=read_device_id_failed"
  exit 4
} else {
  puts "RUNA_P3_PRE_DEVICE_ID=$id"
}
if {[string first $expect_id $id] < 0} {
  puts "RUNA_P3_DL_ABORT device_id_mismatch expect=$expect_id got=$id"
  catch {connect_cable -close}
  puts "RUNA_P3_DL_END result=device_id_mismatch"
  exit 5
}

set rc [catch {download -bit $bit_file -mode jtag -spd 7 -cable 0} derr]
puts "RUNA_P3_DOWNLOAD_RC=$rc"
puts "RUNA_P3_DOWNLOAD_MSG=$derr"

if {$rc == 0} {
  if {[catch {read_device_id} id2]} {
    puts "RUNA_P3_POST_DEVICE_ID_FAIL: $id2"
  } else {
    puts "RUNA_P3_POST_DEVICE_ID=$id2"
  }
}
catch {connect_cable -close}
puts "RUNA_P3_CABLE_CLOSED"
if {$rc == 0} { puts "RUNA_P3_DL_END result=ok" } else { puts "RUNA_P3_DL_END result=download_error" }
exit [expr {$rc == 0 ? 0 : 6}]
