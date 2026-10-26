# =============================================================================
# T10.b2-a1-uart-impl r4 -- single SRAM (JTAG, volatile) download of the r4
# UART-direct candidate.  NO Flash / eflash write anywhere in this script.
#
# Preconditions (verified by the dev role, not by this script):
#   * hwserver already running on 127.0.0.1:5555 (started 2026-10-24 17:05,
#     PID 77088, D:\anlogic\TD_Release_2026.2\bin\hwserver.exe)
#   * cable 0 = on-board FTDI channel B / COM8
# Usage:
#   td_commands_prompt.exe ./download_sram_r4.tcl      (cwd = this folder)
# =============================================================================
set srv 127.0.0.1:5555
set args_s {-r -s 5555 -f 12 -v -w 5556 -i 0}
set bit_file D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b2-a1-uart-impl/r4/td/a1_board.bit

if {![file exists $bit_file]} {
    puts "R4_DL_ABORT missing_bit=$bit_file"
    exit 2
}

if {[catch {connect_cable -host_name $srv -usr_args [list $args_s] -open} err]} {
    puts "R4_DL_ABORT connect_failed=$err"
    exit 3
}

if {[catch {read_device_id} id]} {
    puts "R4_DL_READ_WARN $id"
} else {
    puts "R4_DL_DEVICE=$id"
}

if {[catch {download -bit $bit_file -mode jtag -spd 7 -cable 0} derr]} {
    puts "R4_DL_ABORT download_failed=$derr"
    catch {connect_cable -close}
    exit 4
}
puts "R4_DL_OK mode=jtag(sram) bit=$bit_file"
catch {connect_cable -close}
exit 0
