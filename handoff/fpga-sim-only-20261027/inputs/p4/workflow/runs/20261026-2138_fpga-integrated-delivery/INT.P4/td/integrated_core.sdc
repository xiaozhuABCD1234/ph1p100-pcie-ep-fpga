# INT.P4 integrated delivery constraints (test-only, not production)
# Single clock domain: clk = 187.5 MHz (period 5.333 ns), fpga-design-guide.md section 10.
# I/O are internal SoC ports (capture, DDR, descriptor face), not package pins and not
# a board top; no false_path / multicycle / clock exception is used.
create_clock -name {clk} -period 5.333 -waveform {0.000 2.667} [get_ports {clk}]