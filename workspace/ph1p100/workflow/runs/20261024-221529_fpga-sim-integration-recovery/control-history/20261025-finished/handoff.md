# 恢复交接（2026-10-25）

> 当前状态更正：按用户既有“接着做”继续必要可逆隔离修复，无需同一许可再次确认。当前dispatch=`dispatch-dq-fix-r0.json`；当前合同=`planner-amendment-authorized-dq-fix.md`。第三包ready，三正式包/上限4；TD/bit/下载/Flash=0，G2 not_run。下文待确认/确认恢复文本仅留历史，不再执行等待分支。规划澄清机会1、所有实际修复/命令历史保留。

本run=`D:\fpga\ph1p100\workflow\runs\20261024-221529_fpga-sim-integration-recovery`，PROJECT_ROOT=`D:\fpga\ph1p100`，runtime=Codex，batch1。当前dispatch=`dispatch-blocked-closeout.json`；历史dispatch.json和dispatch-t10-r0.json以及原计划/指南保持字节不变以保全已测manifest。

真实角色：规划 `/root/fpga_planner_sim_221529`；T08开发 `/root/fpga_dev_sync_221529`、综合测试 `/root/fpga_tester_sync_221529`；T10开发 `/root/fpga_dev_recovery_221529`、tester尚无。不得猜ID/假resume。T08 round0独立PASS、实际修复0；T10开发blocked、尚未首轮综合、实际修复0。

稳定problem=`T10.a1-recovery-sim:SCOPE_CLARIFICATION:fixed-r5-descriptor-index`；证据`T10.a1-recovery-sim/defect-evidence.json`；元数据/全部22输入索引为`relay-metadata.json`；原manifest-r0.json及所有失败记录保留。问题补充机会0，T10源码读取3轮、compile1、clean1、载入前失败1的历史不清零。计划额度中断/恢复见relay-resume-quota.md、user-feedback-01-continue.md及主relay-state；当前角色未再触发API错误。

具体缺陷/拟修复/门槛/预算：repair-scope-proposal.md；待用户答复：question-recovery-dut-scope.md。新第三包提案计入3/4，未开发、未测试、未改变8项DUT只读范围。用户确认后才生成ready dispatch，按原工作流新包新开发/一个新综合测试；纠正DUT独立通过后续真实原恢复开发，保留原包ID/轮数，绑定changed新输入，全部故障重新验证。输入或权限未确认不能自动重试blocked包。

准确用户恢复文本（确认修复时）：

`$fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261024-221529_fpga-sim-integration-recovery；本轮目标：同意 repair-scope-proposal.md 的单文件描述符队列隔离修复范围，修复独立验收后续跑原恢复仿真；保留所有计数，不写生产/板候选、不下载/Flash。`

全局任务源workflow/tasks.json仅追加本轮离线证据/状态，保留其他会话字段和父硬件状态，不以本run立替代任务板。生产RTL/旧run/探索work/D:\TD/D:\fpga_work/板候选/共享盘符/docs junction/其他工作树全保护。原生产未改变即回退；不能删除失败证据或混用r4/P2/r5身份。
