cd D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-2359_fpga-r3-merge/sim/export_neg
vsim work.tb_brd_neg_both +SCEN=0 +NF=1 +HOST_MODEL=0
run -all
quit -f
