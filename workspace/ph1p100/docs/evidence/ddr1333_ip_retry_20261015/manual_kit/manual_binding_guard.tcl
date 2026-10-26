# This marker is emitted only when the private generator is loaded.
foreach required_var {IP_INSTALL_PATH IP_EXPORT_PATH IP_COMPONENT_NAME} {
    if {![info exists $required_var]} {error "Missing IPTool context: $required_var"}
}
set expected_depot [file normalize {D:/TD/work/csi2/_validation/ddr1333_ip_20261015_190248/depot}]
if {![string equal -nocase [file normalize $IP_INSTALL_PATH] $expected_depot]} {
    error "Private generator binding mismatch; stop before generation"
}
# The launcher supplies the export path. Refuse redirected generation/context.
if {![string equal -nocase [file normalize $IP_EXPORT_PATH] [file normalize {D:/TD/work/csi2/_validation/ddr1333_ip_20261015_190248/output}]]} {
    error "Private export path mismatch; stop before generation"
}
if {$IP_COMPONENT_NAME ne "ddrmc_1333"} {
    error "Private component name mismatch; expected ddrmc_1333"
}
set binding_file [open {D:/TD/work/csi2/_validation/ddr1333_ip_20261015_190248/gui_depot_binding.log} w]
puts $binding_file [list PRIVATE_DDR1333_GENERATOR_BOUND $IP_INSTALL_PATH $IP_EXPORT_PATH $IP_COMPONENT_NAME]
close $binding_file
