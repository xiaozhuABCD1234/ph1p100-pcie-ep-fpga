# T10.a1-eng-freeze small-top constraints (test-only, not production)
# Single clock domain: clk = 187.5 MHz (period 5.333 ns), per fpga-design-guide.md §4.
# I/O are intentionally left unconstrained at this block-level small top; they are
# internal SoC ports, not package pins. No false_path / multicycle is used.

create_clock -name {clk} -period 5.333 -waveform {0.000 2.667} [get_ports {clk}]
