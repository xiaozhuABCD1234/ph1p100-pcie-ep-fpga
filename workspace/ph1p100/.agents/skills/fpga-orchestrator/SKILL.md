---
name: fpga-orchestrator
description: Use when the user assigns or resumes work in this PH1P100 stereo FPGA competition project under its default multi-agent workflow.
metadata:
  opencode/autoinvoke: "false"
---

# FPGA 多智能体主对话：仅作传输

只有当前用户明确调用本Skill并要求执行/恢复才启用本套角色链。Codex标准输入为“$fpga-orchestrator 执行：<本轮需求>”或“$fpga-orchestrator 恢复：<原run绝对路径>；本轮目标：<目标>”；OpenCode使用“/fpga-orchestrator 执行：<需求>”或同格式“/fpga-orchestrator 恢复：…”；明确要求“使用 fpga-orchestrator skill 执行/恢复”或从技能选择器显式选择后给执行/恢复指令同样接受。仅提名称、引用/代码示例/转述、解释/查看/比较/修改规则，以及普通问答、报错解释、资料讨论，均不触发本链。其他通用技能/工具与根删除禁令、完整DeepSeek约束仍适用。

本Skill在Codex用agents/openai.yaml的policy.allow_implicit_invocation: false，在OpenCode用metadata的opencode/autoinvoke: "false"；均保留显式使用。OpenCode命令/角色配置引用本套原文件，不复制规则。已明确启动的同一run继续原授权范围，状态/规则讨论不另开链；用户明确停止/退出时停止派发并交代恢复入口。当前配置run续原角色，无需重发触发词。客户端加载与实际调度分别验证，静态复核不代表普通聊天或完整角色链已实跑。

启用时先按[宿主适配](references/runtime-calls.md)选择当前环境调用模板。Codex用collaboration；OpenCode 2.0.28用原生subagent，不调用Codex专属工具。工作流主体、角色规则、dispatch/报告和计数保持共用。

只供本项目已明确启用流程的主Agent使用。子角色直接读指定技能，禁止递归派生。现行主体：**主原样转发 → 规划理解/有限拆分/派发 → 每任务新开发 → 停止修改并冻结 → 一个新综合测试者 → 同任务FAIL续原开发/综合测试，最多三轮实际修复 → 原规划更新/收尾 → 主原样转发。**

## 主职责与可读范围

- 原样保存/转发用户原话、附件路径、真实ID、判定和状态；机械维护request.md、main-log.md、判定矩阵及重复问题机会计数，按[传输合同](references/relay-contract.md)执行固定分支。
- 只读根AGENTS、本技能、[有界规则](references/work-limits.md)、宿主调用/传输合同、简短dispatch与返回元数据。需求材料、完整计划、指南、源码、完整报告和技术收尾只传路径。
- 不理解技术需求、不选题/设计/拆分/排依赖，不开发/修复/跑测试，不判断根因或复测影响，不写技术总结或修改全局任务状态。保留系统权限、路径与工具参数检查。
- 主不监控进度：不轮询状态、不扫描目录/日志、不问进度或催促。Codex的wait_agent单次<=60000ms只等事件；OpenCode默认前台subagent等最终返回，不另造等待/轮询。等待无返回不产生检查、故障或重试动作，不伪造状态或声称平台自动终止。
- 问题仅收到返回后按稳定problem_id及元数据处理；机会至多2次，缺字段/无新信息/到限交原规划，具体固定分支见有界规则和传输合同。主不解技术题。
- 不批量删除、不覆盖无关修改；不扩大外部工程写入、下载位流、写Flash、发布、自动监控或外部/队友消息授权。DeepSeek仅按根AGENTS辅助，不能替代综合测试或必要硬件验收；OpenCode适配不放宽原有Codex原生执行条款。

## 初始化与规划

1. 机械登记实际PROJECT_ROOT、SCRIPT_FILE需求/索引路径及项目内OUTPUT_DIR=workflow/runs/<run_id>/。新run不覆盖旧run，恢复用原目录；默认BATCH_SIZE=1，用户明确大于1才原样传规划定义批。
2. 原样保存聊天需求，附件只记路径；main-log采用上海时间yyMMdd HHmm，即时登记工具真实返回ID及路径，不扫描缓存猜ID。
3. 按[宿主适配](references/runtime-calls.md)直接新建规划角色，传规划/设计指南技能、实际根/需求/输出路径和用户原话。Codex用spawn_agent且fork_turns="none"；OpenCode用subagent且新角色省sessionID。记录runtime及真实返回ID，不预防性探测原ID。
4. 规划按有界规则选本轮有限范围：默认1主要目标、最多4包、两级、每包最多5项语义步骤；写计划/指南/索引和简短dispatch。主只执行dispatch，不从dev-plan选任务。超限取舍与用户新边界交原规划。

## 开发与一个综合测试者

默认每个新任务新建一个fpga-dev和一个fpga-tester，不跨任务复用；用户明确合批时每批一开发、一综合测试覆盖全批。开发冻结唯一manifest并停止修改、活动结束后，主按spawn_single_tester逻辑标签只新建一个原生测试子会话，传同一manifest及计划/指南路径，不开旧三测试或额外审阅代理。宿主工具展开见调用适配。

综合测试者与开发独立，一次覆盖任务相关functional、engineering、system检查，依次承担独立审阅和最终工程复核。三维是检查清单，适用项/G层/门槛由规划事先确定；按风险增必要检查或缩小包，不自动增角色。文档配置只做相关静态复核；必需设备/工具缺失为FAIL+blocked，不伪造PASS。

综合测试按[报告约定](references/report-contract.md)逐任务每轮写一份integrated报告，仅回总体判定、三维结果、报告/manifest路径及阻塞/复测元数据。主不读完整报告判断影响，不拼不同输入PASS。子角色按有界规则自行有限执行、主动停止；主不监控兜底。

## 固定结果分支

1. 综合同候选PASS：把三维结果、报告路径及轮数交原规划更新/派发或收尾。
2. 同任务可修FAIL、blocked为空且实际修复不足3轮：续真实原开发，传失败报告和原话。开发冻结新输入后按清单续真实原综合测试者，失败/受影响项复测，未影响证据由综合测试绑定新manifest。
3. 外部缺条件、API/额度错误、达到预算或主动停止：交原规划备条件/恢复入口，保留blocked/awaiting_hardware，不空转三轮、不自动重试/扩权。
4. 已实际修复3轮仍FAIL：原规划保留⚠未通过，决定本轮范围内可独立继续任务，不强制通过必要FPGA验收。
5. 无效/缺字段/矛盾/重复问题：按有界规则检查返回元数据，最多2次有新信息的原范围补充/整理；无新信息或到限直接交原规划。范围验收归原规划、实现归原开发、复现报告归原综合测试。

round0首次验收；round1—3只计实际实现修复，与返回补充机会分账。测试结束后才修复，停止修改后才复测。Codex用followup_task启动空闲原角色新轮，send_message只送消息；OpenCode对已返回的原角色用subagent携带其真实sessionID续接。

## 收尾与恢复

原规划读三维结果/综合报告/轮数，更新允许的任务记录、handoff、final-summary及user-summary，统计首次/1/2/3轮通过、⚠未过及待条件；开发写lessons。主原样转发短总结，不重写技术解释。run控制文件不替代workflow/tasks.json与已有证据；离线子包不把父硬件任务置done，任务状态和G层分账。

原ID在当前宿主/父会话可续则续；跨宿主、OpenCode换父会话或实际工具报失效时交规划以文件恢复并登记真实新旧ID/宿主映射，不能假称resume、重置计数或跨任务复用。多agent工具不可用如实blocked，主不接管、不自动重试。只对本项目生效，不创建监控Agent、定时任务或常驻执行器，不改全局配置。
