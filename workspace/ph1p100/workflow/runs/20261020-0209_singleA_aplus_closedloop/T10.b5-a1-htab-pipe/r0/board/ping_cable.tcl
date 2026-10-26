# =============================================================================
# T10.b5-a1-htab-pipe r0 -- read-only cable probe (NO download, NO Flash).
# Confirms hwserver on 127.0.0.1:5555 and cable 0 are reachable before the one
# authorised SRAM download.
# =============================================================================
set srv 127.0.0.1:5555
if {[catch {connect_cable -host_name $srv} err]} {
    puts "R5_PING_ABORT connect_failed=$err"
    exit 3
}
if {[catch {read_device_id} id]} {
    puts "R5_PING_READ_WARN $id"
} else {
    puts "R5_PING_DEVICE=$id"
}
catch {connect_cable -close}
puts "R5_PING_DONE"
exit 0
