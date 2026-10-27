# =============================================================================
# build.tcl - headless 编译（Anlogic TD 6.2 / Linux）
#   用法:  cd /home/xiaozhu/Projects/f9p_ph1p100_imx415x2 && td build.tcl
#   产物:  fpga_prj_Runs/best_result/fpga_prj.bit (+ _compress.bit)
#   日志:  log/td_*.log
# =============================================================================
import_device ph1_100p.db -package PH1P100SBG484 -speed 3
open_project {fpga_prj.al}

reset_runs { syn_1 }
launch_runs { syn_1 phy_1 } -jobs 4
wait_run syn_1 -quiet
wait_run phy_1 -quiet
save_best_bits

puts "==== BUILD DONE ===="
exit
