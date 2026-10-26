# 本轮输入索引

PROJECT_ROOT=`C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道`。
OUTPUT_DIR=`PROJECT_ROOT/workflow/runs/20261016_130619_relay_workflow_revision`。
规划角色=`/root/relay_v2_planner`；仅计划和本目录文件写入，没有改技能、生产工程或运行旧试任务。

## 采用输入

| 输入 | 路径（PROJECT_ROOT相对，外部图片见单独索引） | 用途/边界 |
|---|---|---|
| 用户本轮原话/约束 | `workflow/runs/20261016_130619_relay_workflow_revision/request.md` | 调整流程；主传输，工作交子角色；不执行旧试任务 |
| 最新用户补充 | 本会话主调度转发原文，已逐字记dev-plan | 规划者必须理解原始需求并拆任务、依赖、顺序和验收 |
| 图片准确路径 | 本run`images.md` | 完整图+16截图全部已读取；1/4视觉重复；原七技能正文未提供 |
| 图像对齐 | 本run`alignment.md` | O观察/A适配分开；逐步输入/输出/职责/转换及现有差异 |
| 根默认约束 | `AGENTS.md` | 删除禁令、DeepSeek完整块及当前工作流；前两者不得改 |
| 项目技能 | `.agents/skills/fpga-*/SKILL.md`中的七项 | 全部读取；按本轮计划修订 |
| 技能参考 | `.agents/skills/fpga-orchestrator/references/{project-context,codex-calls,report-contract}.md` | 仅本流程导航/调用/报告口径，未扩读生产源码 |
| 默认说明/角色 | `workflow/FPGA多智能体工作流_使用说明.md`、`workflow/AI协作与工具接入.md`、`workflow/AGENTS接入片段.md`、`workflow/README.md`相关角色处 | 处理默认入口矛盾；不改工程验收/G层或扩权限 |
| 原两试任务设计 | `workflow/runs/20261016_121011_trial_task_design/{request,dev-plan,new-chat-prompt}.md` | 已读任务单/启动说明；A/B范围保留，只更新启动入口 |
| 旧执行目录元数据 | `workflow/runs/20261016_124321_trial_execution/trial-artifacts/{trial-state.json,README.md}` | 仅核对状态矛盾；不读实现/完整报告、不运行、不写 |

## 现状及保护

实际cwd即PROJECT_ROOT，根目录检查未显示LinkType/Target；本轮涉及已存在文件亦未显示链接。开发仍须在写前核对当前路径/并发变化。

规划读取时git显示`.gitignore`、CODEX_HANDOFF、README、若干docs、workflow角色/任务板等dirty，`.agents`、AGENTS、parallel、workflow/runs等untracked。所有者不能从git状态确认，按其他聊天/用户已有成果保护；本轮不reset、不提交、不批量清理，不把所有未提交差异认成本轮结果。

需求入口说两试任务已设计未执行，但当前旧目录元数据显示A=`developing`、B=`blocked_dependency`，README还列候选/manifest和开发检查路径。这里只确认文件存在且状态口径不一致；不推断已完成/未完成真实执行，也不启动追赶或改旧状态。本轮“只修配置、不执行旧任务”的最新范围清楚，不构成本轮阻塞。未来启动时由原规划者核对该旧run有效状态，不能直接从头覆盖。

以下SHA256是规划读取时基线，开发前如漂移须保留并发变化而非覆盖。未记录的文件按实际新增/只读分开。

| 文件 | SHA256 |
|---|---|
| AGENTS.md | e86924922f9413b6bb7c7c1b9091700e88e7b35a41f8bf68a1ed7bbcfc2f48bc |
| .agents/skills/fpga-orchestrator/SKILL.md | ac9199f69e4546b8e9c263026f8ef47b4ee4d8df85a132dd7b60a84e3c5635e2 |
| .agents/skills/fpga-planner/SKILL.md | f112deecdcfa4159793e697bee374e299a64af4a8fbaf5f2bdf9fa3611ec5ccf |
| .agents/skills/fpga-design-guide/SKILL.md | 4aeee01e9221f7f76b983e60c9438dfa11f30c7b184ec36336f8c260c1f11e2a |
| .agents/skills/fpga-dev/SKILL.md | 2731b94f810406484126b7b13cecc5b8695effeb8afb29c15b240952b552ce75 |
| .agents/skills/fpga-tester-functional/SKILL.md | 76cb223d9090c0daea43acdc24a9ded73530b2d9e8ddd38a1a3f5ed43634a9af |
| .agents/skills/fpga-tester-engineering/SKILL.md | 928df3bb856c467c602eba264ed97649ab66b4fecb21c20eb5fb51d08a4954d9 |
| .agents/skills/fpga-tester-system/SKILL.md | 375af1a84072e1f1695bb7ec43268e26fae6e4295dbdd2d6dccb4140d125771c |
| .agents/skills/fpga-orchestrator/references/codex-calls.md | b589e74e18bcfaf27e81a2ba14b599895037335845697869b7e9f2ecdc7f1bf4 |
| .agents/skills/fpga-orchestrator/references/project-context.md | 956082ff2c42cfb9814d385ea88a1c2d7aaf3cd3fa97b5158f656545b391f387 |
| .agents/skills/fpga-orchestrator/references/report-contract.md | 601734685e9b37d85671f8a96038b22086ab039892ce62421602ff4325175c64 |
| workflow/FPGA多智能体工作流_使用说明.md | c43fc9dda52ff3970f33a674fef0d38fbf724577d2104502a7779d0ccf919efa |
| workflow/AI协作与工具接入.md | c176ae5f7f264ce9c2e9fcda0af68af1a991c23fd799213f302d43d6a0953199 |
| workflow/AGENTS接入片段.md | e5c074c7f3f11e9957b7bac428add0bb01056b902e7bd6a67ba8344d43a3c920 |
| workflow/README.md | 17de88cc169a498acacebd8804c58fb51ec37ed48939e10963afc9aa4e7917db |
| workflow/runs/20261016_121011_trial_task_design/new-chat-prompt.md | 3c14b73828ec98cdb599e2b0657190092f295e661c03a41ff0b3c0f02049e697 |
| workflow/tasks.json（禁止改） | 013be484e210d106b79c87cb91a9f9cce01ffc45ddc5d8ed6a9af729781b4003 |

无缺图/缺输入。本轮设计已可派发；实现和三个独立验收尚未执行，不能预填通过。
