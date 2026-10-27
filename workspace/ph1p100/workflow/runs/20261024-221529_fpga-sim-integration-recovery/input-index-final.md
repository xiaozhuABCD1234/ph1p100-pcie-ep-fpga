# 最终输入与交付索引

原需求request.md和两次用户原话“接着做”均保留；当前执行已finished。统一任务板仍workflow/tasks.json，run仅保存控制/证据，不另立全局板。原108项规划输入和全部原始r0/resume01保持SHA；原指南/index属于已验输入，不覆盖。

采用版本：

|用途|最终采用路径（相对本run）|身份/独立报告|
|---|---|---|
|双路真实生产派生overlay|T08.sync-production-sim/manifest-r0.json，candidate及source-to-overlay.json|manifest6d9d9805...；T08 r0 integrated PASS|
|描述符修复副本|T10.a1-uart-descriptor-fix/candidate/a1_uart_export.v|SHA0f3ae49e...；同包r0 PASS，原错误3dad065f...只作反例|
|中止/溢出修复副本|T10.a1-abort-cdc-fix/candidate/camera_a1_uart_top.v|SHA5d0f9a00...；同包r0 PASS，原b1041676...只作反例|
|原恢复任务最终DUT|recovery-dut-binding-resume02.json，绑定top+exporter+原六项|两项相对原始改变；不改原8项路径|
|原恢复完整测试输入|T10.a1-recovery-sim/resume02/manifest-resume02.json|SHA628579ea...；原恢复r0 integrated PASS，未继承依赖PASS|
|四包所有完整SHA与报告|candidate-binding-final.json、delivery-index.md|逐manifest/报告/候选的准确绝对路径|
|最终口径|fpga-design-guide-final.md、final-summary.md、handoff.md|G0/G1与所有未测边界|
|全部有限账|budget-ledger-final.json|原文件指针与开发/综合测试累计账，问题机会1/0不清零|

已有成果/所有者：T08/descriptor/abort各独立开发与单一综合测试者，原恢复始终同开发/root/fpga_dev_recovery_221529、唯一tester/root/fpga_tester_recovery_221529。全部真实角色ID见handoff及finished dispatch；没有跨任务复用测试角色、没有派生子代理。

保护范围继续包括生产树、原输入、旧run、其他worktree、D:\TD、D:\fpga_work、板候选/bit/CWC/DB、共享盘符及docs junction。所有新产物在D:\fpga\ph1p100下；工作树原dirty/删除/untracked不清理、不提交或推送。当前没有待用户确认项；旧question和额度blocked记录被后续授权澄清/真实继续及最终PASS取代，保留历史不删除。

未完成的是本轮之外的物理实现/上板/性能、旧AR在reset瞬间尚未完成的额外交错；不影响已冻结离线目标的PASS，不能据其升级父硬件G层或父T任务done。
