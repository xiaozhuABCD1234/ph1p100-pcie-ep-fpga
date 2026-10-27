# 宿主调用适配

工作流主体、角色技能、dispatch、报告、任务/修复/返回机会上限共用一份，不随客户端改变。只有当前用户明确执行/恢复才启用；选择客户端不等于新增任务或授权。

| 实际宿主/工具 | 本次只读的调用约定 | 显式入口 |
|---|---|---|
| Codex，提供 collaboration.spawn_agent/followup_task | [Codex 调用](codex-calls.md) | `$fpga-orchestrator 执行：需求`；恢复沿用原格式 |
| OpenCode 2.0.28，提供 subagent(agent, description, prompt, sessionID?, background?) | [OpenCode 调用](opencode-calls.md) | `/fpga-orchestrator 执行：需求`；或明确要求“使用 fpga-orchestrator skill 执行/恢复” |

按实际工具 schema 选择，不同时加载两套调用模板，不在 OpenCode 虚构 collaboration/wait_agent/fork_turns，也不在 Codex 调用 OpenCode subagent。其他版本须以真实 schema 为准；不支持所需创建/续接时如实 blocked，不以主接管、假工具或 shell 脚本冒充子智能体。

dispatch 中 `spawn_agent`、`spawn_single_tester`、`followup_task`、`return_to_planner` 是既有操作标签：新建角色、只新建一个测试者、续原角色、交原规划。Codex 按原模板展开；OpenCode 按其原生 subagent 展开。标签不要求同名原生工具，角色分工和次数不变。

主只接收返回，不扫描或询问进度。Codex 使用 <=60 秒的 wait_agent 事件等待；OpenCode 默认前台 subagent 等待最终返回，不需要另造等待或轮询工具。角色执行/命令预算继续按 [有界规则](work-limits.md)，不虚构 OpenCode 支持 timeout_ms 等未提供参数。

ID 记录实际 runtime、角色和工具返回 ID。同一 OpenCode 父会话只能续它自己的子会话；跨客户端或换父会话时用原 run 文件恢复、新建当前宿主角色并登记新旧 ID/宿主映射，不尝试冒充续原会话。不要预防性探测旧 ID。

OpenCode 的 `.opencode/agents/` 只是三个原角色的薄入口，职责从 `.agents/skills/` 读取，不复制一套 FPGA 规则。入口配置不修改全局模型、权限、默认 Agent 或已运行会话。
