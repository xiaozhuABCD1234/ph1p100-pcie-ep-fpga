when -label fr {/tb_camera_a1_uart_top/tap_frame == 1} {echo "EV FRAME_START"}
when -label rst {/tb_camera_a1_uart_top/rst_n == 0} {echo "EV RST_LOW"}
when -label cmt {/tb_camera_a1_uart_top/dut/u_a1/frame_commit == 1} {echo "EV COMMIT"}
when -label abt {/tb_camera_a1_uart_top/dut/u_a1/frame_abort == 1} {echo "EV ABORT"}
when -label geo {/tb_camera_a1_uart_top/st_geom == 1} {echo "EV GEOM"}
when -label ex1 {/tb_camera_a1_uart_top/st_exp >= 32'd1} {echo "EV EXP1"}
when -label ex2 {/tb_camera_a1_uart_top/st_exp >= 32'd2} {echo "EV EXP2"}
when -label op {/tb_camera_a1_uart_top/dut/u_export/estate >= 32'd3} {echo "EV EPAY"}
run 4ms
echo ===DONE===
examine -radix unsigned /tb_camera_a1_uart_top/st_exp
examine -radix unsigned /tb_camera_a1_uart_top/st_enc
examine -radix unsigned /tb_camera_a1_uart_top/cap_bytes
quit -f
