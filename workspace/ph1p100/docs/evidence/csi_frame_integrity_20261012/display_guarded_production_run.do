onerror {quit -code 1 -f}
vsim -voptargs=+acc -gSW=960 -gSH=540 -gPRODUCTION=1 work.tb_ddr_display
run -all
quit -f
