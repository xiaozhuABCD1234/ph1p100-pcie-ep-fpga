onerror {quit -code 1 -f}
vsim -voptargs=+acc -gLINE_BYTES=4800 work.tb_csi_integrity
run -all
quit -f
