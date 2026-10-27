# 可选 AGENTS 接入片段

本项目根AGENTS.md已设置默认入口；本片段同步2026-10-17现行规则。迁移时只合并工作流段，必须保留原删除禁令、完整DeepSeek块及其他约束。仅本项目，不改全局或增加外部动作授权。统一正文见[有界规则](../.agents/skills/fpga-orchestrator/references/work-limits.md)。

```markdown
## 项目研发工作流

只有当前用户明确调用本Skill并要求执行/恢复才启用本套角色链。Codex用$fpga-orchestrator，OpenCode用/fpga-orchestrator，后接“执行：<本轮需求>”或“恢复：<原run绝对路径>；本轮目标：<目标>”；明确要求“使用 fpga-orchestrator skill 执行/恢复”或技能选择后给执行/恢复指令同样接受。仅提名称、引用/代码示例/转述、解释/查看/比较/修改规则，以及普通问答、报错解释或资料讨论，均不触发本链。其他通用技能/工具与根删除禁令、完整DeepSeek约束仍适用。

Codex用agents/openai.yaml的policy.allow_implicit_invocation: false，OpenCode用Skill metadata的opencode/autoinvoke: "false"，均保留显式使用。OpenCode项目入口/三个角色薄配置引用原.agents/skills，不复制规则、不改全局配置。先按.agents/skills/fpga-orchestrator/references/runtime-calls.md选择真实调用模板。已明确启动的同一run继续原授权范围，状态/规则讨论不另开链；用户明确停止/退出时停止派发并交代恢复入口。客户端加载与完整角色链分别验证，不夸大验证范围。

明确启用后的主Agent先读.agents/skills/fpga-orchestrator/SKILL.md；子角色直接读指定技能，禁止递归派生。主仅原样存/转用户原话、路径、真实ID、判定和状态，机械留档并按简短dispatch执行；不理解需求/选题/设计/拆分/排依赖，不读原材料/完整计划/源码/报告，不开发/测试/判断根因或影响/写技术总结。保留系统权限和路径检查。

固定链：主原样传输→原规划理解/有限拆分/dispatch→每任务新开发→停止修改并冻结manifest→一个新综合测试者→同任务FAIL续原开发/综合测试、最多三轮实际修复→原规划更新/收尾→主原样转发。

默认本轮1主要可验收目标、最多4正式包（含ready/blocked/依赖）、两级需求→工作包，每包1主要结果/最多5项语义步骤；机械动作不另建包/代理。超限原规划依用户优先级、依赖顺序、需求出现顺序取最小闭环，最多3条后续主题加需求路径、不自动续做；无法闭环只交1范围冻结包，不冒充父目标完成。用户明确本轮新有限值才可记录覆盖，合批/新run/改ID不能绕限；默认批大小1，用户明确合批时每批一开发、一综合测试覆盖全批。

综合测试与开发独立，三维为functional/engineering/system检查清单；相关验收/G层/阈值及不适用理由由规划事先选择。文档/模型不用无关硬件流程，必要真实DUT、最终STA/CDC/资源/候选绑定和真实硬件/恢复/稳定性能检查不因节约取消。风险增大先增加必要检查或缩小包，不自动增加角色；独立审阅和最终工程复核由同一综合测试者依次承担。

开发停止修改/活动结束并冻结后，spawn_single_tester只新建一个原生综合测试子会话，工具按宿主适配展开。每任务每轮一份integrated报告，返回dimension=integrated及三维结果。旧三个领域tester只作历史/检查参考，旧调度/并行/分维报告语句不生效。round0首次验收，round1—3最多三轮实际修复；同任务续原真实ID，复测失败/受影响项，未影响证据由综合测试绑定新manifest，不拼不同输入PASS。

主不监控进度、不轮询状态/扫描日志/问进度或催促；Codex的wait_agent单次<=60000ms只等事件，OpenCode默认前台subagent等最终返回，不另造等待/轮询，等待无返回不检查/判故障/重试。真实ID来自当前宿主工具返回，跨宿主/OpenCode换父会话或实际失效交原规划按文件恢复与真实ID/宿主映射，不重置计数；失联无返回不伪造状态或称平台自动终止。

角色按.agents/skills/fpga-orchestrator/references/work-limits.md自行有界执行：每次派发/续接默认30次工具调用，规划15分钟、开发/综合测试45分钟；单问题3轮搜索/读取，同失败命令首次+1次有新证据重试，连续2次无进展主动blocked。启动前落实读搜60秒/局部静态仿真5分钟/构建30分钟的实际deadline或安全终止，yield不是超时，无法安全控制不启动。规划可提前冻结有限执行预算并说明理由，角色不自行扩。此为角色合同，不保证平台硬限。

问题返回须带稳定problem_id、reason_code、new_information、evidence_path、requested_action、resume_input_path。主只收到返回后记task_id+problem_id，最多2次有新信息且字段/证据/恢复路径齐备的原范围补充/整理机会；无新信息/缺字段矛盾/到限交原规划blocked，转交不重置，外部资料/设备/工具/权限/API/额度阻塞直接备条件，不自动重试/扩权。机会与三轮实际修复分账，主不解题。到限后须真实新输入或条件变化由原规划明确恢复。

PASS、三轮未过或blocked由原规划读报告/轮数更新允许记录/dispatch及handoff/final-summary/用户短总结，主原样转发，开发写lessons。workflow/tasks.json及证据/交接是主源，run不另立任务板；任务与G层分账，离线子包不将父硬件任务置done。必要验收不放宽。

Codex的collaboration直接调用，不放functions.exec，fork_turns="none"传技能/输入路径，空闲原角色新轮用followup_task。OpenCode 2.0.28用subagent(agent/description/prompt)，新角色省sessionID，原角色返回后续接带真实sessionID。不跨宿主套工具名、不读缓存猜ID。无多agent工具如实blocked，主不接管。

DeepSeek遵守根AGENTS完整块的最小上下文/提案检查/原生执行/resume边界，不替代综合测试或真实硬件。禁止批量删除、不覆盖无关修改；不扩大外部工程写入、下载位流、Flash、发布、自动监控或外部/队友消息权限，不改全局配置。
```
