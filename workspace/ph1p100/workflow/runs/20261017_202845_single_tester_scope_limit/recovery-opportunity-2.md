# 最后同范围恢复清单：返回补充机会2/2
task_id：CFG-SINGLE-TESTER-LIMITS；plan_revision=2；recovery_revision=2。
problem_id：CFG-SINGLE-TESTER-LIMITS:NO_PROGRESS:local-static-deadline；reason_code=NO_PROGRESS。
已用机会2/最多2；实际实现修复round仍0。只续原DEV，无新任务/角色，无配置阈值变更。

## 已核实的新信息与正确口径
A/B实际PASS；C实际完成HEAD匹配、分支匹配、19精确配置路径diff --check，均正常。C的check-ignore -v --no-index针对三个新增叶文件实际exit1、未超时、stdout/stderr空；失败发生在后续NEW_TESTER_EXACT_NEGATED_WHITELIST断言要求输出必须含父目录否定规则。
[Git check-ignore官方文档](https://git-scm.com/docs/git-check-ignore)明确：无匹配时不输出且路径不被忽略；exit1表示给定路径均未被忽略；verbose用于显示匹配模式，并非必须输出父目录白名单。
[Git gitignore官方文档](https://git-scm.com/docs/gitignore)明确：末尾斜杠模式只匹配目录，否定模式用于重新包含路径。因此不能要求查询叶文件时必然显示目录否定行。此前A已验证.gitignore只追加精确tester目录例外；C现有命令同时证明三个新文件没有被忽略。
原C报告保持FAIL及原失败断言，不覆盖、不伪改旧证据。新报告写明这是检查工具的额外断言口径错误，与当前配置可见性失败区分；真实“未忽略/可列出”门槛保持，不删门槛/不改配置。

## 仅完成剩余工作
1. 不重跑A/B、HEAD/branch、diff --check、check-ignore或旧整段脚本。复用A/B和C已完成命令的真实证据，引用其路径/SHA及范围；只改dev-evidence内检查辅助入口/结果解释，不修改19份候选配置。
2. 证明19份配置与A/B验证时相同：用已有应用/检查快照SHA；若没有完整SHA快照，按原config-updates.json和apply-config.ps1实际确定的目标字节与当前精确19文件比较。此为证据绑定，不能用时间戳代替内容或重做已通过语义检查。无法建立相同输入依据直接blocked。
3. 只补一条尚未执行的Git可见性查询：`git -c core.fsmonitor=false -c core.quotepath=false --no-pager ls-files --others --exclude-standard -- .agents/skills/fpga-tester/SKILL.md .agents/skills/fpga-orchestrator/references/work-limits.md .agents/skills/fpga-orchestrator/agents/openai.yaml`。要求exit0且规范化输出集合恰为这三个精确新文件；记录stdout/stderr/退出码，不只数行。不加文件、不git add、不提交。命令若失败/超时立即停，不重复。
4. 保存`dev-evidence/recovery-static-c-completion.json`和summary，记录旧verbose命令是not_ignored证据、原额外断言错误、唯一新可见性结果及未改变候选的依据。导出candidate.diff（原16份before对当前，加三新增文件完整文本）；可用已有Python原生文本diff逻辑，避免再做不必要Git扫描。候选diff只能包含这19配置路径。
5. 建立candidate-manifest.json：绑定19配置、当前request/计划/指南/tester-input/trigger-docs、两个恢复清单、实际新旧复用证据/summary/diff的SHA，HEAD和本包写列表。本次规划/测试输入有附录更新，必须用当前SHA；不将旧timeout/C失败删改为PASS。更新dev-notes事实与未测边界，停止修改后才ready_for_test，供唯一综合tester独立静态验收。

## 最后停止条件
原30工具调用/45分钟角色预算和原300秒静态上限不扩大。C已有记录剩余290.079秒；本次仅剩余工作主动限180秒（不重置/增加300上限），每个原生命令最多60秒且取剩余预算较小值。沿用上次已证明有效的隐藏原生子进程、文件重定向和有限等待/安全停止方式，不用旧Start-Job或async Result包装。
任何剩余检查失败、输入漂移、证据无法绑定、超时或无进展，立即保留配置和日志返回blocked/candidate_frozen=false；第2机会已用尽，不再自动派原DEV回答同问题，即使new_information=true也不能再开第3机会。原规划届时收尾并给用户规则正文，明确未冻结/未独立复核。实际综合测试之后若发现独立实现缺陷，仍按原round1—3账处理，不能拿修复轮继续本已耗尽返回问题。

