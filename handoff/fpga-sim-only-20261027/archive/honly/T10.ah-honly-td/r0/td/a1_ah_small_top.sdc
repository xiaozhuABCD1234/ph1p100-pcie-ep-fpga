# T10.ah-honly-td (Line B) block-level build-only constraints (test-only, not production).
# Single clock domain: clk = 187.5 MHz (period 5.333 ns, half period 2.667 ns),
# per fpga-design-guide.md §3.2.  This top is an internal SoC block, not a pin-level
# board shell, so its I/O are intentionally left unconstrained (known, recorded gap).
# No false_path, no multicycle, no clock group, no generated clock, no IO exception.

create_clock -name {clk} -period 5.333 -waveform {0.000 2.667} [get_ports {clk}]