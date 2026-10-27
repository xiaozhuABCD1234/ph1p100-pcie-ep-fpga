# T10 原开发：capacity后只做最终静态冻结

原角色 `/root/fpga_dev_dual_scheduler_180900`，原任务 `T10.dual-aplus-scheduler`。PROJECT_ROOT `D:/fpga/ph1p100`；run `D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure`。读fpga-dev/现行有界合同和 `dispatch-T10-continue03-static.json`、`T10-capacity-error01.md`、`continue03-recovery-plan.md`。用户真实新“接着做”在 `user-feedback-continue03.md`，允许本次同ID/同模型必要静态收尾；没有换模型或再跑实验授权。

原 `cmp-stall-fix01` 候选、TB、runner、fixture、编译/evidence/旧result一律只读。本次只写该目录下新 `static-closeout02/**`，最多10保守工具调用/15分钟，实际收到后先记录start/deadline，读搜/静态命令60秒。有界记录自己的调用与owned process，不扫描/终止他人命令。

严禁修改RTL/TB/runner/算法/参数、生成新仿真输入、编译、仿真、构建、TD/硬件/盘符/下载/Flash/Git、faults第4次。禁止运行现有finish.py或旧run.py；它们不是本次冻结入口。可自己写纯读取/哈希/已有文件字节后处理/manifest/报告脚本，但不能调用外部实验或改旧文件。新写脚本也属于这10调用预算，不包装实验绕限。

需要完成：

1. 从你自己原native上下文恢复cmp-stall-fix01实际调用账。旧37、恢复期已知13native/8wrapper、静态9及所有历史保留；缺失项继续unknown，不能凭commands.jsonl行数冒充工具总数或填0。原窗口21:44:26.9726768至22:44:26.9726768已经结束，capacity error原文保留，不倒改deadline/旧冻结时间。本次新静态账独列。
2. 校验6项实际编译源/两个core固定SHA、源码差异、现有命令结束回执和已有24帧/2负对照证据。规划此时复核compiled输入及三个checker回执无漂移；你仍需核对可重现依赖和最终绑定。现有compile1/case5已满5，faults增量0，总3/3；已知累计compile5/case16。完整历史calls未知如实写；原CMP-stall问题的实际修复和capacity中断不同问题，不改根因ID来清账。
3. 在新目录生成 `manifest-cmp-stall-fix01.json`、`execution-accounting.json`、source/evidence映射、result/handoff/retest及必要lessons。manifest绑定完整实际DUT/TB/生成/检查脚本/参数/源闭包、只读实际命令和关键已有证据以及新静态说明，排除易变ModelSim库DB，不把旧DB元数据当不可变源码。用真实当前冻结时间，清楚区分开发局部和未启动的独立验收；原绝对路径runner含旧deadline，需要独立测试者复制/适配自己的写域，不能让其运行写入冻结输入。
4. 最后从自己的真实上下文确认停止修改、所有自己活动命令已结束，写作者stopflags，不让规划或脚本替你猜。若命令状态无法确认，或hash/闭包缺口不能闭合，返回blocked；不得靠新实验补缺。都齐备才ready_for_test回原规划，不自行派测试者。

尚无独立T10 integrated round0，post-acceptance实际修复0，不发明FAIL/round1。下一次首次独立验收原预留45调用/60分钟/2compile/20cases仍未消耗，本次不能挪用。开发24帧、48.46MB/s TB100MHz服务率不等于双路155.52MB/s实时或板上性能；G2/3/4继续not_run/awaiting_hardware。

返回task_ids/status/artifact_paths/manifest_path/test_input_paths/lessons_path/blocked/retest、stopped_modifying和active_commands、本静态实际计数与原历史账。再次capacity/API/额度错误直接交原规划，不自动重试、换模型或创建替代。
