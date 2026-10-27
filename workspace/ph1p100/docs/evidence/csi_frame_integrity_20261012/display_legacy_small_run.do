onerror {quit -code 1 -f}
vsim -voptargs=+acc work.tb_ddr_display
run -all
quit -f
