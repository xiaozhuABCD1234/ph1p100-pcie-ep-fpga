onerror {quit -code 1 -f}
vsim -voptargs=+acc work.tb_csi_integrity
run -all
quit -f
