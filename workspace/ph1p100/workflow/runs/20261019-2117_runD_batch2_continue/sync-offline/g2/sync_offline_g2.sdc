# T08 offline small-top G2 constraints (standalone, not a board candidate).
# Three real clocks: ctrl 50 MHz, camera A SOF 187.5 MHz, camera B SOF 187.5 MHz.
create_clock -name {clk_ctrl} -period 20.000 -waveform {0.000 10.000} [get_ports {clk_ctrl}]
create_clock -name {clk_a} -period 5.333 -waveform {0.000 2.667} [get_ports {clk_a}]
create_clock -name {clk_b} -period 5.333 -waveform {0.000 2.667} [get_ports {clk_b}]

# The two camera SOF clocks are independent oscillators; ctrl is a separate
# 50 MHz domain. CDC is by toggle mailbox + 2FF synchronizers, so the three
# domains are asynchronous by design (not a blanket false_path exemption).
set_clock_groups -asynchronous \
    -group [get_clocks {clk_ctrl}] \
    -group [get_clocks {clk_a}] \
    -group [get_clocks {clk_b}]

# I/O timing for the standalone carrier (virtual 2 ns board delay assumption,
# documented as synthetic; this is not a hardware timing claim).
set_input_delay -clock clk_ctrl 2.000 [get_ports {start abort_req prereq_ok req_ready rsp_valid rsp_ok}]
set_input_delay -clock clk_a 1.000 [get_ports {sof_a}]
set_input_delay -clock clk_b 1.000 [get_ports {sof_b}]
set_output_delay -clock clk_ctrl 2.000 [all_outputs]
set_false_path -from [get_ports {rst_n}]
