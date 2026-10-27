# img_algo_top.sdc - T09.rk-align-algo module-level small-top constraints.
# The integration target domain for the three algorithms is the CSI byte clock
# (187.5 MHz = 5.333 ns, see fpga/csi2/pcie_integration/constraints).  This SDC
# constrains the module-level small top at that target; it does NOT relax or
# replace the main project's SDC (which is untouched).
# TD 6.2.3's SDC dialect is the same one the main project uses (create_clock /
# set_clock_groups); I/O delay commands are not used there either.
create_clock -name {algo_clk} -period 5.333 -waveform {0.000 2.667} [get_ports {clk}]
