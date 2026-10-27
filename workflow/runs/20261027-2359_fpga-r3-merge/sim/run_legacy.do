cd D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-2359_fpga-r3-merge/sim/export_legacy
vsim work.tb_brd_export_r3 +SCEN=0 +NF=2 +HOST_MODEL=1
run -all
quit -f
