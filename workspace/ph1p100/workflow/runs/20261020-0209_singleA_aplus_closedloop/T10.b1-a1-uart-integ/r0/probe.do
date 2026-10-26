run 4us
echo ===END===
examine -radix unsigned /tb_camera_a1_uart_top/st_raw_pub
examine -radix unsigned /tb_camera_a1_uart_top/st_enc
examine -radix unsigned /tb_camera_a1_uart_top/st_exp
examine -radix unsigned /tb_camera_a1_uart_top/dut/fstate
examine -radix unsigned /tb_camera_a1_uart_top/dut/u_a1/xlen_r
examine -radix unsigned /tb_camera_a1_uart_top/dut/u_a1/slen_r
examine -radix unsigned /tb_camera_a1_uart_top/dut/u_a1/dblk
examine -radix unsigned /tb_camera_a1_uart_top/dut/u_cmp_store/wr_active
quit -f
