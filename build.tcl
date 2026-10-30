set ROOT [file normalize [file dirname [info script]]]
cd $ROOT
# =============================================================================
# build.tcl - headless 编译（Anlogic TD 6.2 / Linux）
#   用法:  cd <本仓库检出根>
#          Linux:   <TD_BIN>/td.sh build.tcl
#          Windows: <TD_BIN>/td_commands_prompt.exe build.tcl
#   产物:  ph1p_pcie_ep_top_Runs/best_result/ph1p_pcie_ep_top.bit (+ _compress.bit)
#   日志:  log/td_*.log
# =============================================================================
import_device ph1_100p.db -package PH1P100SBG484 -speed 3
open_project {ph1p_pcie_ep_top.al}

reset_runs { syn_1 }
launch_runs { syn_1 phy_1 } -jobs 4
wait_run syn_1 -quiet
wait_run phy_1 -quiet
save_best_bits

puts "==== BUILD DONE ===="
exit
