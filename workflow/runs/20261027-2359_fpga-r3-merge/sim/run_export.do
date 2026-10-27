cd {D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-2359_fpga-r3-merge/sim/export_s2_h0}
vsim work.tb_brd_export_r3 +SCEN=2 +NF=2 +HOST_MODEL=0
run -all
quit -f
