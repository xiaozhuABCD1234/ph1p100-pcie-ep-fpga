# =============================================================================
#  03_phy.tcl — T07.rk-align-backend：布局布线（phy_1）+ 最终时序报告 + bit
#  用法：在工程目录里 td_commands_prompt.exe <本脚本>
#  说明：G2 要求最终实现 DB/STA/bit；本脚本只 save_best_bits（不下载、不写 Flash）。
# =============================================================================
open_project ph1p_pcie_integration.al

# 同 02_syn.tcl：新会话里显式给设备/封装，否则 settings.cfg 里为空
set device_name  PH1P100
set package_name SBG484
set speed        3

reset_runs phy_1
launch_runs phy_1 -jobs 4
wait_run phy_1 -quiet

report_area -file phy_area.rpt
report_timing -file phy_timing.rpt

save_best_bits

puts "T07_PHY_DONE"

exit
