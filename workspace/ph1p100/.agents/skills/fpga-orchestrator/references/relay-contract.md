# 主对话传输合同

主只读本合同、调用约定、[有界规则](work-limits.md)、简短dispatch与返回元数据。完整需求、计划、源码、报告和技术收尾只传路径。这些是文件/消息格式，不是自动执行程序，字段不授予权限。

仅在用户明确调用fpga-orchestrator并要求执行/恢复后适用本合同。引用/解释/修改规则等不触发新链，已授权同run按原范围续接。入口与停止意图见主技能及有界规则。

## 规划派发

dispatch.json由原规划写，主不从dev-plan选任务。至少包含：

| 字段 | 内容 |
|---|---|
| run_id / project_root / output_dir | 本run及实际绝对路径 |
| task_ids / batch_size | 下一任务或用户明确批准批，默认1 |
| status / needs_user_input | ready / blocked / needs_user_input / finished及布尔值 |
| input_paths / write_scope / protected | 输入、允许路径与保护范围 |
| next_action / after_development | 固定操作、角色技能/输入路径；续接时真实原角色槽位 |
| scope_limits / execution_limits | 有界规则默认值或派发前冻结的有限覆盖值、理由及必要用户授权来源 |
| question_path / user_summary_path | 适用时供主原样转发 |

本轮默认1主要目标、最多4包、两级、每包最多5项语义步骤；超大需求的切片/余项、例外授权及角色停止预算按有界规则由规划记录，主不做范围判断。合批、新run或改ID不能绕限。

operation只用spawn_agent、spawn_single_tester、followup_task、return_to_planner、relay_to_user。这些是既有操作标签，按[宿主适配](runtime-calls.md)展开，不要求客户端存在同名工具：spawn_single_tester只新建一个测试子会话，return_to_planner续真实原规划，relay_to_user原样转文本。Codex沿用原生spawn/followup；OpenCode新建省sessionID、续接带真实sessionID。主保留权限/路径检查，越界原样交原规划，不改范围。

规划仅回task_ids、dispatch_path、status、needs_user_input及适用question_path/user_summary_path。有问题另附problem对象；详细计划留文件。

## 开发与综合测试返回

开发仅回task_ids、status、artifact_paths、manifest_path、test_input_paths、lessons_path（已有时）、blocked、retest（修复时）。停止修改、活动结束并冻结后才可ready_for_test。

综合测试每任务仅回task_id、dimension=integrated、dimension_results、verdict（PASS/FAIL）、report_path、manifest_path、blocked、retest。dimension_results覆盖functional/engineering/system的适用性、结果及G层，详细依据留报告。每任务每轮一份<task_id>-r<round>-integrated.md，首行唯一判定标题。round0首次验收，round1—3实际修复。

blocked为空或简短条件元数据，包含类别、缺项/恢复路径和blocked/awaiting_hardware/needs_user_input状态。必需门槛缺条件为FAIL；报告G层区分blocked/not_run/fail，不误称DUT已实测判坏。

retest由开发/综合测试给required_dimensions、required_checks、report_paths、input_status（same/changed/drifted）、reuse_decision_paths。失败与受影响项必须复测；未影响证据由同一综合测试者明确复用依据并绑定当前manifest。主只转清单，缺失/矛盾按有限返回机会处理，不猜影响，不拼不同输入PASS。

## 问题元数据与机会

problem须含problem_id、reason_code、new_information（布尔）、evidence_path、requested_action、resume_input_path；固定枚举、稳定身份及外部阻塞分类按有界规则。主仅在收到返回时按task_id+problem_id登记最多2次续原责任角色机会，不能用wait超时触发机会。

仅字段齐备、new_information=true、证据/恢复路径齐备且requested_action是原授权范围补充/整理，才机械followup_task续原角色。new_information=false、缺字段/矛盾、身份无法稳定归类或2次后仍同问题，交原规划blocked/备条件；规划不靠转交重置计数。外部工具/设备/资料/权限/API/额度缺失直接交规划，不走机会循环、不自动重试/扩权。到限后仅真实新用户输入或条件变化可由原规划明确恢复。实际实现修复单按round1—3，不伪装为返回机会。

## 固定状态流转

| 收到的可观察返回 | 主的机械下一步 |
|---|---|
| 规划ready | 按dispatch新建本任务开发或用户明确批准批 |
| 开发ready_for_test且停止修改/manifest齐备 | spawn_single_tester，只新建一综合测试者，传同输入 |
| 综合同候选PASS | 续原规划，传三维结果、报告路径与轮数 |
| 同任务FAIL、blocked为空且实际修复<3 | 续原开发；重新冻结后续本任务原综合测试者 |
| blocked非空/需输入/外部错误/角色主动停止 | 立即交原规划备条件，主原样转用户，不空转 |
| 三轮实际修复后仍FAIL | 原规划保留⚠未通过，决定本轮范围内独立后续包 |
| 疑问/无效/过长/矛盾/重复问题 | 按problem计数和固定条件续原责任角色或直接交原规划 |
| 实际工具报ID失效/跨会话恢复 | 原规划能续则续，否则新规划按文件恢复并登记新旧真实映射 |
| 多agent工具/额度不可用 | 如实blocked并给恢复入口，主不接管、不自动重试 |
| wait_agent等待超时，无返回 | 不检查、不催促、不判故障、不重试；继续只接收事件 |

默认每新任务新开发/新综合测试，不跨任务复用；同任务修复才续原ID。主不轮询状态、不扫描目录日志、不问进度；Codex的wait_agent单次<=60000ms仅等事件，OpenCode默认前台subagent等最终返回，具体边界见有界规则和宿主适配。

原规划读详细报告更新允许的任务记录、dispatch、handoff、final-summary和用户短总结；开发写lessons，主只转发。任务/G层分账，离线子包不把父硬件任务置done。用户反馈逐字保存并传路径。不得扩展删除、外部写入、硬件、发布、外部消息或自动化授权。
