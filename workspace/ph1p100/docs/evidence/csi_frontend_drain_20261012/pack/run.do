onerror {quit -code 1 -f}
vsim -voptargs=+acc work.tb_guarded_pack
run -all
quit -f
