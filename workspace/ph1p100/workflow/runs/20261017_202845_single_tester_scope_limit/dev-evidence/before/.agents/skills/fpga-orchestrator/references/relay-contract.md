# 主对话传输合同

主只读本合同、调用约定、简短dispatch及返回元数据。详细需求、计划、源码、报告和技术收尾以路径交对应角色读取。下列是文件/消息格式，不是自动执行程序；字段不授予额外权限。

## 规划者派发

`dispatch.json`由规划者写，主不从dev-plan提取或自选任务。字段保持简短：

| 字段 | 内容 |
|---|---|
| run_id / project_root / output_dir | 本run及实际绝对路径 |
| task_ids / batch_size | 规划确定的下一任务；默认1，用户明确大于1才定义批 |
| status / needs_user_input | ready / blocked / needs_user_input / finished及布尔值 |
| input_paths / write_scope / protected | 角色输入路径、允许范围与保护边界，可引用已写文件 |
| next_action | 固定操作、指定角色技能路径、输入路径、原角色槽位（续接时） |
| question_path / user_summary_path | 需原样转用户的问题或短总结，按状态提供 |

`next_action.operation`只使用本流程动作：新任务`spawn_agent`、开发冻结后`spawn_three_testers`、同任务续接`followup_task`、终止态`return_to_planner`或`relay_to_user`。`spawn_three_testers`/`return_to_planner`/`relay_to_user`是dispatch逻辑标签，不是工具名；主依调用约定分别直接发出三次spawn、续接真实原规划ID或原样转发文本。主保留系统要求的权限/路径检查；发现越界将原信息交原规划者，不自行改范围。

规划返回只含：`task_ids、dispatch_path、status、needs_user_input、question_path（适用时）、user_summary_path（适用时）`。详细计划/指南/索引路径放dispatch交开发和测试，不要求主读取正文。

## 开发与测试返回

开发返回：`task_ids、status、artifact_paths、manifest_path、test_input_paths、lessons_path（已有时）、blocked、retest（修复时）`。停止修改并冻结后才可返回`ready_for_test`。

测试每任务返回：`task_id、dimension、verdict（PASS/FAIL）、report_path、manifest_path、blocked、retest`。`dimension`只能是functional/engineering/system；报告第一行保持唯一`### 判定：PASS`或`### 判定：FAIL`。首轮round=0，修正轮1—3。

`blocked`为空或简短条件元数据（类别、缺失条件路径、`blocked/awaiting_hardware/needs_user_input`状态）；详细解释留文件。缺必需条件时判定FAIL，G层中区分`blocked/not_run/fail`，不能误称DUT实测失败。

`retest`由开发/测试给：`required_dimensions、report_paths、input_status（same/changed/drifted）、reuse_decision_paths`。FAIL维度必复测；受影响PASS维度续原测试者判断复测/证据复用。主只转发清单；清单缺失、矛盾或证据输入不同即交原角色补齐，不能自行推断。新manifest的最终三维判定由各对应测试者明确绑定，旧证据复用也由该测试者出具绑定依据。

## 固定状态流转

| 可观察状态 | 主的机械下一步 |
|---|---|
| 规划ready | 按dispatch新建本任务开发；用户明确合批时按规划批执行 |
| 开发ready_for_test且停止修改/manifest齐备 | 新建三测试并行，传同一manifest与计划路径 |
| 三维同候选PASS | 续接原规划，传矩阵/报告路径/轮数，由其更新与派发 |
| 同任务FAIL、blocked为空、实际修复轮数<3 | 续原开发传全部失败报告；新冻结后按角色影响清单续原测试 |
| blocked非空/需用户输入 | 立即续原规划准备条件或问题，主原样转用户；不消耗空转修复轮 |
| 三轮实际修复后仍FAIL | 续原规划，保留⚠未通过；下一独立任务由规划派发 |
| 缺输入/疑问/返回过长/状态矛盾 | 交原责任角色整理；范围验收归规划、实现归开发、复现报告归测试 |
| ID失效/跨会话恢复 | 原规划能续则续；否则新建同规划角色读文件恢复，登记新旧映射，再由其派发恢复方案 |
| 无多agent工具/额度不可用 | 如实记录blocked与待调度入口，不让主接管、不自动重试 |

默认新任务新开发与新三测试，不把上一任务对话转作下一任务；原规划负责本run连续派发和收尾。同任务修复才复用本任务原开发/测试。每批仅一个开发者、三测试各覆盖全批；轮数与逐任务判定分别记账。

原规划者读取详细报告完成任务记录、handoff、final-summary与用户短总结；主仅转发。开发维护lessons。任务状态和G层验证分账，离线子包完成不把父硬件任务置done，不降低必要验收。用户反馈逐字保存并按原路径传给责任角色。不得通过本合同扩展删除、外部写入、硬件操作、发布、外部消息或自动化授权。
