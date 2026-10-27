# =============================================================================
#  02_syn.tcl — T07.rk-align-backend：综合（syn_1）+ 面积/时序报告
#  用法：在工程目录里 td_commands_prompt.exe <本脚本>
# =============================================================================
open_project ph1p_pcie_integration.al

# 分阶段（新会话 open_project）时 TD 不会自己补设备/封装变量，必须显式给：
# 否则 launch_runs 生成的 settings.cfg 里 device_name/package_name 为空，
# 子流程 import_device 会报 "can't read device_name"。
set device_name  PH1P100
set package_name SBG484
set speed        3

reset_runs syn_1
launch_runs syn_1 -jobs 4
wait_run syn_1 -quiet

# 面积/资源报告（落到工程目录的报告文件里）
report_area -file syn_area.rpt
report_timing -file syn_timing.rpt

puts "T07_SYN_DONE"

exit
