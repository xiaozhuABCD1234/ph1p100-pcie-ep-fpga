# 主传输恢复入口（额度阻塞）

runtime：Codex
project_root：D:\fpga\ph1p100
run：D:\fpga\ph1p100\workflow\runs\20261024-221529_fpga-sim-integration-recovery
planner_id：/root/fpga_planner_sim_221529
state：blocked_quota
reason_code：QUOTA

原规划续接实际返回 usage limit，turn失败；主未重试、未另派角色、未读取完整技术材料。

待处理用户新增原话：接着做
路径：user-feedback-01-continue.md

已有返回（仅机械登记）：
- T08.sync-production-sim：round0 integrated PASS，actual_repair_rounds=0；报告test-reports/T08.sync-production-sim-r0-integrated.md。
- T10.a1-recovery-sim：开发blocked，stopped_modifying=true，active_commands=0；未派tester，实际修复0；problem_id=T10.a1-recovery-sim:SCOPE_CLARIFICATION:fixed-r5-descriptor-index。
- 第二包返回索引：T10.a1-recovery-sim/relay-metadata.json；证据T10.a1-recovery-sim/defect-evidence.json；manifest-r0.json。

恢复时先续真实原规划，传用户反馈01、第二包blocked元数据与证据路径及第一包PASS报告/角色ID，保持范围/计数/保护路径；原规划读取必要材料决定后续。原ID实际失效才按宿主规则文件恢复和登记真实新旧ID。不猜ID、不自动清零，不把当前状态写成完成。

用户可用入口：
$fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261024-221529_fpga-sim-integration-recovery；本轮目标：继续处理恢复仿真阻塞并完成原两项任务
