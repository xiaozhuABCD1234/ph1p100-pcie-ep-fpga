# T08 原唯一综合测试者：quota后续原r1剩余验收

只续你 `/root/fpga_tester_dual_local_180900`，原任务 `T08.dual-local-closure`、formal round1，实际修复1。PROJECT_ROOT `D:/fpga/ph1p100`；run `D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure`。读fpga-tester及现行有界/报告合同，按 `dispatch-T08-continue03.json`、`continue03-recovery-plan.md`，保留原 `T08-integrated-r1-input.md` 的完整技术检查。用户新原话和本次真正恢复依据见 `user-feedback-continue03.md`；不是自动quota重试或模型切换。

唯一manifest `T08.dual-local-closure/r1/mode-fix02/manifest-mode-fix02.json`，SHA256 `38e0615341330aa5b8f1e0e1f9ecf4e169abbdc6bc4856912b9e4f929bdfcce3`。规划已再次核314文件无漂移，但你仍需前后校验实际输入。开发全部只读；r0 FAIL不变，没有r1综合判定，不能以开发自检代验收。

## 先恢复账，再运行剩余项

你的原 `r1/integrated-mode-fix02/window-start.json` 是22:09:16至22:54:16窗口，原30保守calls/2compile/14case；usage limit原生中断保留。规划只见window-start和input-review两文件，没有实验回执；这不是你消耗为零的证明。

先用原上下文恢复这次r1已用的functions.exec、nested native、wait等保守合计，已启动编译/case、同失败命令次数、original_edges是否已启动。写 `r1/integrated-mode-fix02/continue03/recovered-accounting.json`，列逐调用证据/已知下界与可证明上界、无法恢复项及真实错误，不凭文件数编数字。最多4次静态核账调用；若原计数已知，这些也占原r1总30。若核账无法确证剩余，或calls已满，停止实验，4次静态核账只作必要交接账并保留超用/unknown，回blocked与最小缺项；不要请求自己增加预算。

计数确证后，只能用 `30-原r1已用-本次已用` calls、`2-原r1实际compile` compile、`14-原r1实际case` case。不得重置为30/2/14，不得重跑已有效的同manifest独立证据。`tb_tester_edges` 全任务仅余最多1次纠正输入尝试，若中断turn已经启动则扣除；无法确定启动次数就不能再跑。启动前静态查新源/参数/库/路径。每个实际case都记账，失败/路径错误也不归零。

旧22:54:16deadline保留为已过期。现在收到本followup时记录新的实际接续起点和+30分钟日历截止，保证编译/局部/单case实际timeout300秒，读搜60秒，循环两次无进展即停。新日历窗口仅用于原剩余验收，不恢复实验次数，不回填旧窗口/抹超时；实际旧活动时长和无法恢复的时间字段如实列账。新调用上限仍是原r1总30减已用，必要收尾至少留足空间。API/额度再失败直接blocked交规划，不自动再试，不换模型，不探测其他角色。

## 原14进程必要清单保持

模式/发布矩阵、原edges一次、全部camera/slot/status矩阵、真实overlap(case16)、normal六对、case10–15六项、contract、legacy、有效B释放误送A变异。case15与独立contract不可省。先读取你已保存的输入审阅，不重复无目的读取大文本；原清单要求独立实际R字节/CRC/RAW图案/尾零/身份/AR-R所有权oracle，不只看开发PASS或ModelSim exit0。旧I2C1–9只准逐源/时钟/参数/刺激/影响映射后复用你自己r0证据，绑定新manifest。

不要运行/导入开发 `run_mode_fix.py`（旧guard且会写冻结local）。在自己r1域独立编译实际79项闭包及所需TB，记录新实际编译输入；库/INI/cwd/log也必须在自己域。自己的新断言、oracle、变异拷贝可修改，开发RTL/TB/runner绝不能修改。有效同输入证据一旦已有，复用其hash/条件，不重复实验。

只写 `test-reports/T08.dual-local-closure/r1/**` 和 `test-reports/T08.dual-local-closure-r1-integrated.md`。需要的资源/时间不足或数据缺口，真实FAIL/blocked并列最小缺项；无DUT新证据不要伪称实测判坏或PASS。正式报告首行唯一PASS或FAIL，functional/engineering/system同候选，r0FAIL/实际修复1/历史44calls2compile20cases及开发超用都保留，G2/3/4继续not_run/awaiting_hardware。

停止自己修改、确认自己活动命令结束，回原合同元数据+原r1/本恢复/累计真实计数、manifest/report/retest/稳定problem。全部交原规划，不自动续开发、新建测试者或进入r2。
