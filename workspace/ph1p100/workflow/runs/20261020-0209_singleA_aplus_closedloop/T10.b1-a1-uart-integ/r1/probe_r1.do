when -label fr {/tb_camera_a1_uart_top/tap_frame == 1} {echo "EV FRAME_START $now"}
when -label rst {/tb_camera_a1_uart_top/rst_n == 0} {echo "EV RST_LOW $now"}
when -label cmt {/tb_camera_a1_uart_top/dut/u_a1/frame_commit == 1} {echo "EV COMMIT $now"}
when -label abt {/tb_camera_a1_uart_top/dut/u_a1/frame_abort == 1} {echo "EV ABORT $now"}
when -label geo {/tb_camera_a1_uart_top/st_geom == 1} {echo "EV GEOM $now"}
when -label ex1 {/tb_camera_a1_uart_top/st_exp == 1} {echo "EV EXP1 $now"}
when -label ex2 {/tb_camera_a1_uart_top/st_exp == 2} {echo "EV EXP2 $now"}
when -label open {/tb_camera_a1_uart_top/dut/u_export/estate == 3} {echo "EV EPAY $now"}
run 4ms
echo ===DONE===
examine -radix unsigned /tb_camera_a1_uart_top/st_exp
examine -radix unsigned /tb_camera_a1_uart_top/st_enc
examine -radix unsigned /tb_camera_a1_uart_top/cap_bytes
quit -f
