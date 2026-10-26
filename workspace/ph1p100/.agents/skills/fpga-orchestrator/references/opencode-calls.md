# OpenCode 2.0.28 原生调用

此适配只改变宿主调用，固定角色链与 [传输合同](relay-contract.md)、[有界规则](work-limits.md)、[报告约定](report-contract.md)不变。不要套用旧版 OpenCode task/task_id/subagent_type，也不使用 Codex collaboration/fork_turns/wait_agent。实际工具 schema 优先。

## 显式入口与共用文件

在本项目目录打开 OpenCode，使用能写调度文件的主会话（例如 Build），输入：

```text
/fpga-orchestrator 执行：<本轮明确需求>
/fpga-orchestrator 恢复：<原run绝对路径>；本轮目标：<目标>
```

也可明确要求“使用 fpga-orchestrator skill 执行：需求”。本版原生 skill 加载参数为 `{"id":"fpga-orchestrator"}`；选择/加载技能但只讨论规则不启动角色链。

`.opencode/opencode.json` 的 skills 仅指向原 `.agents/skills`；命令文件只加载共用主技能；三个 `.opencode/agents/fpga-{planner,dev,tester}.md` 只引用对应角色技能并禁止递归 subagent。不安装 MCP，不复制技能，不调整全局权限/模型。

主技能 `metadata["opencode/autoinvoke"]="false"` 关闭 OpenCode 自动选用引导，Codex 仍用原 agents/openai.yaml。2.0.28 通过独立 command 文件提供斜杠入口，不依赖文档较新版本的 opencode/slash 元数据。

## 新建角色与续接

原生工具名为 **subagent**，以下 JSON 是工具输入，不是 shell 命令：

```json
{
  "agent": "fpga-planner",
  "description": "规划本轮 FPGA 任务",
  "prompt": "你是规划角色，不派生代理。实际项目根、原话需求/request.md、OUTPUT_DIR、技能和设计指南的绝对路径、用户约束均按本次真实值提供。理解并有限拆分，写完整计划和简短dispatch；仅向主返回元数据，详细内容留文件。",
  "background": false
}
```

新任务开发用 agent=`fpga-dev`，开发冻结并停止后综合测试用 agent=`fpga-tester`。新角色**省略 sessionID**，不沿用上个任务 ID。只给实际输入路径、角色技能、范围和用户原话，新子会话从干净上下文开始；不传完整聊天历史，不指定用户未要求的 model。

返回为 `sessionID`、`status`、`output`。即时记录真实 sessionID 为 PLANNER_ID/DEV_ID/TEST_ID，并记录 runtime=opencode；`completed` 只表示角色结束，角色的 PASS/FAIL/blocked 从简短 output 元数据取，不能把 completed 当 PASS。

同任务修复/复测或原规划下一轮，传回该角色真实 sessionID：

```json
{
  "agent": "fpga-dev",
  "description": "修复本任务第1轮",
  "sessionID": "<本任务原DEV_ID，须替换为实际返回值>",
  "prompt": "原样转发原允许范围、全部未通过报告绝对路径、原话反馈和本轮round。读取报告修复，更新lessons，停止修改后冻结新manifest并返回复测清单；缺条件直接blocked。",
  "background": false
}
```

同一角色续接时保持 agent 与原角色一致，不用换 agent 在同一个子会话混装开发和测试。传输合同的 followup_task/return_to_planner 标签映射为此调用；spawn_single_tester 映射为一次省 sessionID 的 fpga-tester 调用。

## 返回、等待和恢复

本流程默认前台执行，subagent 原生等待角色最终返回，主不另做监控。不存在可照抄的 wait_agent/send_message；同任务补充机会只在角色已返回后续接，不能用重复 subagent 请求催促运行中角色。background=false 不是执行超时；工具、搜索、命令与无进展上限仍由角色自行落实。

若实际运行返回 running，只接收真实完成通知，不轮询会话/日志、不 sleep、不重发任务。没有最终返回就不伪造结果。工具/角色不可用、权限/额度或条件缺失按既有 blocked 分支处理，不主接管、不自动重试或扩权。

OpenCode 只允许当前父会话续它的子会话。换父会话或从 Codex 恢复时，以原 run 的计划、交接、manifest、报告和计数为依据，由当前宿主规划恢复，记录新旧真实 ID/宿主映射，不能重置已用机会、轮数或任务范围，也不称跨宿主 resume。具体路径用本次实际值，不扫描缓存猜 ID。

原有 PowerShell/rg 命令可继续复用，但通过 OpenCode 实际 shell/read/write 工具执行，遵守其真实参数和权限；不把 functions.exec/exec_command 当 OpenCode 工具。主仍只读短 dispatch/返回元数据、机械写 request/main-log，详细材料和报告只转路径。

根 AGENTS 的删除及完整 DeepSeek 约束保留。OpenCode 适配不自动接入或放宽 Codex 专属 worker 的原生执行条款；未有兼容授权/工具时该可选辅助不用，正式三个子角色仍由 OpenCode 原生运行。

## 核对来源

- [官方技能文档](https://opencode.ai/docs/skills/)：项目技能及显式/自动调用元数据；版本差异以本地接口和下列 tag 源码为准。
- [v2.0.28 subagent 工具](https://github.com/anomalyco/opencode/blob/v2.0.28/packages/core/src/tool/plugin/subagent.ts)：真实输入/输出、新建/续接、前台等待、父子限制。
- [v2.0.28 skill 工具](https://github.com/anomalyco/opencode/blob/v2.0.28/packages/core/src/tool/plugin/skill.ts)及[技能解析](https://github.com/anomalyco/opencode/blob/v2.0.28/packages/core/src/config/plugin/skill-file.ts)：id 与 autoinvoke。
- [v2.0.28 命令加载](https://github.com/anomalyco/opencode/blob/v2.0.28/packages/core/src/config/plugin/command.ts)：.opencode/commands、subagent=false、原样参数展开。
