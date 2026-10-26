# =============================================================================
# T10.b5-a1-htab-pipe r0 -- the ONE authorised SRAM (JTAG, volatile) download of
# the r0 htab-pipe candidate.  NO Flash / eflash write anywhere in this script.
#
# Preconditions (checked by the dev role, not by this script):
#   * hwserver already running: hwserver -r -s 5555 -f 12 -v -w 5556 -i 0
#   * cable 0 = on-board FTDI, JTAG channel A, UART channel B = COM8
#   * the bit below passed 02_bitgen.tcl (fail-closed STA) and 03_cwc.tcl
# Usage:
#   td_commands_prompt.exe ./download_sram_r0.tcl      (cwd = this folder)
# =============================================================================
set srv 127.0.0.1:5555
set args_s {-r -s 5555 -f 12 -v -w 5556 -i 0}
set bit_file D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b5-a1-htab-pipe/r0/td/a1_board.bit

if {![file exists $bit_file]} {
    puts "R5_DL_ABORT missing_bit=$bit_file"
    exit 2
}

if {[catch {connect_cable -host_name $srv -usr_args [list $args_s] -open} err]} {
    puts "R5_DL_ABORT connect_failed=$err"
    exit 3
}

if {[catch {read_device_id} id]} {
    puts "R5_DL_READ_WARN $id"
} else {
    puts "R5_DL_DEVICE=$id"
}

if {[catch {download -bit $bit_file -mode jtag -spd 7 -cable 0} derr]} {
    puts "R5_DL_ABORT download_failed=$derr"
    catch {connect_cable -close}
    exit 4
}
puts "R5_DL_OK mode=jtag(sram) bit=$bit_file"
catch {connect_cable -close}
exit 0
