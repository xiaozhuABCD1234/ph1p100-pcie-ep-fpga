# =============================================================================
# T10.b19-cam-a r0 -- the ONE authorised SRAM (JTAG, volatile) download of the
# CAM_SEL=0 A candidate.  NO Flash / eflash write anywhere, NO retry.
#
# hwserver is auto-started by connect_cable with the frozen argument set used by
# the proven T10.b9..b18 flow.  cable 0 = on-board FTDI (JTAG A, UART B = COM8).
# Run with cwd = the td folder:
#   td_commands_prompt.exe <this script>
# =============================================================================
set srv 127.0.0.1:5555
set args_s {-r -s 5555 -f 12 -v -w 5556 -i 0}
set bit_file D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b19-cam-a/r0/td/a1_board.bit

if {![file exists $bit_file]} {
    puts "B19_DL_ABORT missing_bit=$bit_file"
    exit 2
}

if {[catch {connect_cable -host_name $srv -usr_args [list $args_s] -open} err]} {
    puts "B19_DL_ABORT connect_failed=$err"
    exit 3
}

if {[catch {read_device_id} id]} {
    puts "B19_DL_READ_WARN $id"
} else {
    puts "B19_DL_DEVICE=$id"
}

if {[catch {download -bit $bit_file -mode jtag -spd 7 -cable 0} derr]} {
    puts "B19_DL_ABORT download_failed=$derr"
    catch {connect_cable -close}
    exit 4
}
puts "B19_DL_OK mode=jtag(sram) bit=$bit_file"
catch {connect_cable -close}
exit 0
