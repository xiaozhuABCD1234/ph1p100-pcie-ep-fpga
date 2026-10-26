# 输入与现有成果索引

核对日期2026-10-16。本轮仅只读代码/文档/工作树状态和计算文件SHA，未执行A/B、软件回归、仿真或硬件操作。哈希为本轮读到的版本；新对话开工必须重新核对，不据此断言其他聊天已停止。

| 输入 | 准确路径或入口 | 采用内容 / 状态 |
|---|---|---|
| 用户需求 | 当前目录`request.md` | 两项适中任务、本轮只设计、新对话执行 |
| 项目约束 | PROJECT_ROOT/AGENTS.md | 主只调度、固定角色、禁止批量删除、DeepSeek边界 |
| 工作流角色 | PROJECT_ROOT/.agents/skills/fpga-{orchestrator,planner,design-guide,dev,tester-functional,tester-engineering,tester-system}/SKILL.md | 新对话按角色读取；规划者已读planner/design-guide及相关入口 |
| 调度与报告 | PROJECT_ROOT/workflow/FPGA多智能体工作流_使用说明.md；.agents/skills/fpga-orchestrator/references/report-contract.md | 两批串行、三维并行、原代理最多三轮 |
| 现状主源 | PROJECT_ROOT/README.md、CODEX_HANDOFF.md、workflow/tasks.json | T03/T04 ready，父任务验收仍有缺口；本次不更新任务板 |
| 整合结论 | PROJECT_ROOT/docs/DeepSeek独立检测与现行方案整合_2026-10-16.md §3 | 已记录非压缩拒收缺口和压缩adapter缺口 |
| R10F来源 | PROJECT_ROOT/parallel/frame/frame_contract.py；parallel/docs/帧与元数据接口合同_2026-10-15.md | 已有非压缩参考，不覆盖；复用字段/CRC/向量 |
| 现有样例 | PROJECT_ROOT/parallel/evidence/frame_contract_20261015/ | 8×4、64×48，packed/u16le四份bin；result.json仅历史证据 |
| 历史探测 | PROJECT_ROOT/docs/evidence/parallel_integration_20261016/cross_track.json | 已有codec/flags/phase拒收与BPR1直接接入不成立的探测，不冒充本轮复跑 |
| BPR1来源 | CODEC_ROOT/tools/bayer_codec/codec.py、README.md、test_codec.py；CODEC_ROOT/docs/superpowers/specs/2026-10-15-bayer-codec-reference-design.md | 标准库核心已实现；不复制重写，不运行会向其tmp写入的现有CLI测试 |

PROJECT_ROOT=`C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道`；CODEC_ROOT=`C:/Users/czz/.codex/worktrees/bayer-codec-reference/FPGA创新设计赛道`。表中路径相对各明确根展开。

主工作树分支`codex/ddr-timing-margin`，HEAD=`1306014271505044c6c30db2b8bc8f419f09a819`；有已有dirty/untracked材料。CODEC_ROOT分支`codex/bayer-codec-reference`，HEAD=`1994131589466af7713c1641d34a16d7d3931e63`；codec.py为已跟踪文件，另有未提交行组合/高斯/C2H等成果，实际聊天所有者未确认。全部只读，禁止合并或覆盖。

## 关键文件SHA256（新对话冻结依据）

| 根 / 文件 | SHA256 |
|---|---|
| PROJECT_ROOT / parallel/frame/frame_contract.py | CBF0BA87248818E86647E2BAC4BE881B8227FCF3FC1D7A90607E14C8E81CF4DB |
| PROJECT_ROOT / parallel/docs/帧与元数据接口合同_2026-10-15.md | 9D1D29880338554C244A8A15377567EDE5EE15B1FF56B19501D0A6DE29988C7F |
| PROJECT_ROOT / parallel/evidence/frame_contract_20261015/frame_8x4_packed.bin | 64BC78D3A45831FE3EF1AECAC70E17751CB9F5AB5161FA1AD230E9EEC60B04C8 |
| PROJECT_ROOT / parallel/evidence/frame_contract_20261015/frame_8x4_u16le.bin | 9EA9F5547DC9B9FF4AC46FFA19EA2D42C1B2827693B08BA558DA6B5A534B6697 |
| PROJECT_ROOT / parallel/evidence/frame_contract_20261015/frame_64x48_packed.bin | 5CCDC8515FE2E38CA072B9D1C948577B141FE5B50E9E8F3CB841A50B065B461E |
| PROJECT_ROOT / parallel/evidence/frame_contract_20261015/frame_64x48_u16le.bin | E27EB7C8401AD618C03125A26A36C7F0AEA5F3536949A344FAFCF3524937D4E1 |
| CODEC_ROOT / tools/bayer_codec/codec.py | 94CC65FABF4C62E0F89E84A5CD2979D9844B398715BD1F17A9513FE5CAA8BD7D |
| CODEC_ROOT / tools/bayer_codec/test_codec.py | D535247330FFFD7D280DBF7D51E77A5B60EA7EF591ABCFF658C746188FE6A215 |
| CODEC_ROOT / docs/superpowers/specs/2026-10-15-bayer-codec-reference-design.md | 777990130307ED5CC5110608D6814645ADFA9E5201A8ACDA99BE8585105AF24A |

外部依赖为只读CODEC_ROOT，并非独立打包交付；复跑需同一codec.py字节、显式codec-root和新run manifest。路径缺失/哈希变化则B暂停，由规划者核对新版本或报告blocked，不静默使用别处同名模块。现有源由原聊天保留；本试运行不承担恢复/合并外部工作树。
