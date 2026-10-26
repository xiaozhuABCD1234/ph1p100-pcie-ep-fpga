# Isolated synthesis clock target, NOT a board/interface timing sign-off.
# 594 Mbps/lane, 8 bits/lane per byte-clock cycle -> 74.25 MHz.
create_clock -name {byte_clk} -period 13.468 [get_ports {I_clock}]
