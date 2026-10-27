run 6us
echo ===MEM===
examine -radix hex /tb_camera_a1_uart_top/u_ddr/mem(0)
examine -radix hex /tb_camera_a1_uart_top/u_ddr/mem(1)
examine -radix hex /tb_camera_a1_uart_top/u_ddr/mem(2)
examine -radix hex /tb_camera_a1_uart_top/u_ddr/mem(3)
echo ===STORE===
examine -radix unsigned /tb_camera_a1_uart_top/dut/u_raw_store/waddr
examine -radix unsigned /tb_camera_a1_uart_top/dut/u_raw_store/rd_idx
examine -radix unsigned /tb_camera_a1_uart_top/dut/u_raw_store/rd_words
examine -radix unsigned /tb_camera_a1_uart_top/dut/grp_sent
quit -f
