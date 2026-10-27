onerror {quit -code 1 -f}
vsim -voptargs=+acc work.tb_csi_frontend_drain
run -all
quit -f
