# 技能目录重建说明（2026-10-20）

## 背景

`2026-10-20` 凌晨路径整理时，项目根 `.agents/` 与根 `.git` 元数据从工作树消失（`.git` 仅剩空 `refs/`、`worktrees/`）。恢复时 OpenCode 技能注册表先移除了 `fpga-design-guide`、`fpga-dev`、`fpga-planner`、`fpga-tester`、`fpga-tester-engineering/functional/system`，随后 `fpga-orchestrator` 也失效。

用户要求：找到所需技能/资源路径，重建链接，并按既定工作流继续原目标。

## 来源与重建方式

| 文件 | 来源 | 说明 |
|---|---|---|
| `fpga-orchestrator/SKILL.md` | 本会话 2026-10-20 加载的现行正文（逐字重写） | 含单一综合测试者、有限拆分、主不监控、有限返回机会 |
| `fpga-orchestrator/references/work-limits.md` | 本会话 2026-10-20 读取的现行正文（逐字重写） | 唯一有界规则正文 |
| `fpga-orchestrator/references/relay-contract.md` | 本会话读取的现行正文（逐字重写） | 传输合同 |
| `fpga-orchestrator/references/opencode-calls.md` | 本会话读取的现行正文（逐字重写） | OpenCode 2.0.28 调用 |
| `fpga-orchestrator/references/runtime-calls.md` | 本会话读取的现行正文（逐字重写） | 宿主适配 |
| `fpga-orchestrator/references/report-contract.md` | 按现行 integrated 报告规则重写 | 原 integrated 版本丢失；旧三测试版本不适用 |
| `fpga-orchestrator/references/codex-calls.md` | 从 `workflow/runs/20261017_202845_single_tester_scope_limit/dev-evidence/before/.agents/skills` 复制 | Codex 专用，未改 |
| `fpga-orchestrator/references/project-context.md` | 从 `workflow/runs/20261017-011744-rk-fpga-align/backup/restore-check-v2/tracked/.agents/skills` 复制 | 项目入口参考 |
| `fpga-planner/SKILL.md` | 以旧版结构为基础，按现行 AGENTS/有界规则重写 | 改为一个综合测试者、4 包/两级/5 步 |
| `fpga-dev/SKILL.md` | 以旧版结构为基础，按现行规则重写 | 改为一个综合测试者、冻结 manifest |
| `fpga-tester/SKILL.md` | 新写：合并旧三个领域 tester 的检查清单 + 现行 integrated 合同 | 原 integrated 文件丢失；旧三分维不再默认派发 |
| `fpga-tester-{functional,engineering,system}/SKILL.md` | 从 2026-10-17 快照复制 | 按根 AGENTS 保留为历史/专业检查参考 |
| `fpga-design-guide/SKILL.md` | 从 2026-10-17 快照复制 | 只把“三个测试维度”改为“三类检查维度” |

## 验证

- `.opencode/opencode.json` 的 `skills` 仍指向 `.agents/skills`，无需改配置。
- `.opencode/agents/fpga-{planner,dev,tester}.md` 引用的三个路径均已存在。
- 恢复后 OpenCode 注册表重新出现 `fpga-tester` 等技能；`fpga-orchestrator` 已补回 YAML frontmatter 与 `opencode/autoinvoke: "false"`。

## 注意

- 根 `.git` 元数据仍未恢复；本轮不以提交/推送为验收项。不要伪造 git 状态。
- 本目录重建不新增硬件、下载、Flash、发布或外部消息授权。
