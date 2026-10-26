# T02 runD read-only device identity probe. No download, no readback, no Flash.
# Connect to the existing local hwserver (never start/stop it), read only device id, close.
set _args {-r -s 5555 -f 12 -v -w 5556 -i 0}
if {[catch {connect_cable -host_name 127.0.0.1:5555 -usr_args [list $_args] -open} err]} {
    puts "T02_READ_ABORT connect_failed=$err"
    exit 3
}
if {[catch {read_device_id} id]} {
    puts "T02_READ_ABORT read_failed=$id"
    catch {connect_cable -close}
    exit 4
}
puts "T02_READ_DEVICE=$id"
catch {connect_cable -close}
exit 0
