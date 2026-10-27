cd {D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/sim/prep}
vsim work.tb_brd_g1_top +SCEN=0 +PREP=1 +PRED=1
run -all
quit -f
