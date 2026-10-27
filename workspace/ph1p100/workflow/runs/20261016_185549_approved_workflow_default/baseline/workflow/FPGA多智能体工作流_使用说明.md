# FPGA 多智能体工作流：截图原架构的 Codex 适配版

2026-10-16。依据用户提供16张截图中可辨识内容合并去重，再按用户后续要求适配。截图显示的是HTML幻灯片多智能体开发提示词；未出现的原技能正文没有假装从截图还原，本项目配套技能按其原角色重新编写。

## 以后怎么用

已将默认入口写入根[AGENTS.md](../AGENTS.md)。以后在这个项目直接布置任务即可，例如：

> 继续T10的行级压缩组合，复用现有BPR1软件和已有RTL，按默认工作流逐项验收。本次不改DDR/IP候选。

> 核对T03的R10F与BPR1接入合同，交付双方可用的字段表、样例和验收清单，不做硬件下载。

> 继续上次run，从原dev-plan、main-log和失败报告恢复，优先复用仍可定位的原开发/测试智能体。

无需每次指定代理个数或粘贴长提示词。主提示词就是[fpga-orchestrator/SKILL.md](../.agents/skills/fpga-orchestrator/SKILL.md)，可以直接检查完整正文；显式调用名为`$fpga-orchestrator`。项目`.agents/skills`是Codex支持的本地技能位置，变更未出现在选择器时可重启Codex；当前会话也可按准确文件路径读取。[官方技能说明](https://learn.chatgpt.com/docs/build-skills)

本次交付配置与技能，不因编写流程而下载FPGA、运行TD、修改RTL或自动推进其他聊天。也没有建立无人值守的定时执行器。

配置校验、原代理续接与七项角色情境复核见[验证记录](FPGA多智能体工作流_验证记录_2026-10-16.md)。

## 原主体逐项保留

| 截图原结构 | 本项目保留/适配 |
|---|---|
| 主Agent只调度，不开发/测试/视觉验证 | 主Codex只调度，不开发/跑验证，代码与技术判断交对应角色 |
| 原素材只传路径，不读大段内容 | 需求/赛题/工程材料由规划者读取，主调度只传路径 |
| 只收路径、ID和PASS/FAIL | 保留；增加必要的待硬件/阻塞元数据，真实G层结果仍在报告 |
| 初始化OUTPUT_DIR、SCRIPT_FILE、BATCH_SIZE，默认1 | 原变量保留；输出改为每次任务独立run目录 |
| main-log.md、dev-plan.md、设计指南、lessons-learned.md | 名称与分工保留；设计指南改为fpga-design-guide.md |
| Phase1规划，生成计划/规范/公共页面框架 | 同一规划阶段，输出计划/规范/已有工程输入索引；生产RTL由开发者修改 |
| 每批仅一个开发Agent，按顺序完成 | 完整保留；页面换为可验收FPGA工作包 |
| 布局/美观/动画三个测试Agent并行，各测本批全部页面 | 数量与调度保留，改为功能/工程/系统三个维度 |
| 第一时间记开发和测试ID，同批修复resume原Agent | 保留；直接记Codex工具返回ID，用followup_task续接 |
| 最多三轮修正、失败维度原测试者重测本批 | 保留；影响已PASS维度的共享修改也续接原测试者，防止拼接旧结果 |
| 全PASS为✅，第三轮仍FAIL为⚠，继续下一批 | 分支/循环保留；FPGA的⚠明确为未通过，依赖任务等待，独立任务继续 |
| 每批状态更新、反馈，最后通过轮数统计 | 保留；原“强制通过”栏改为“⚠未通过/待条件”，不虚报硬件验收 |
| yyMMdd HHmm日志，精确到分钟 | 格式保留，采用Asia/Shanghai |

只有“第三轮失败也低质量通过”不能成为FPGA功能、时序或安全的通过结论；它在相同流程节点保留为警告/未通过。没有改成主助手包办或换另一种协作架构。

```mermaid
flowchart TD
    M[主智能体：初始化/调度/留档] --> P[计划智能体]
    P --> D[每批一个开发智能体]
    D --> F[功能测试]
    D --> E[时序与工程测试]
    D --> S[上板与系统测试]
    F --> C[汇总每任务三维判定与路径]
    E --> C
    S --> C
    C -->|有未通过且修正不足3轮| R[续接原开发者修正]
    R --> T[续接原测试者复测]
    T --> C
    C -->|全通过或达到轮数上限| U[更新状态/反馈]
    U -->|还有独立可执行批次| D
    U -->|本轮收束| Z[统计/交接/收尾]
```

## 配套技能逐一替换

| 截图角色/技能 | 本项目Codex技能 | 实际职责 |
|---|---|---|
| 主智能体提示词 | [fpga-orchestrator](../.agents/skills/fpga-orchestrator/SKILL.md) | 保持调度架构、批次、ID与三轮闭环 |
| dg-planner | [fpga-planner](../.agents/skills/fpga-planner/SKILL.md) | 核对现状、已有成果、任务依赖与验收 |
| dg-gray-slide-designer | [fpga-design-guide](../.agents/skills/fpga-design-guide/SKILL.md) | 像素/码流/握手/队列/时钟及证据约定，不新增常驻角色 |
| dg-slide-dev | [fpga-dev](../.agents/skills/fpga-dev/SKILL.md) | 实现/局部检查/冻结输入、按报告修正 |
| dg-slide-tester-layout | [fpga-tester-functional](../.agents/skills/fpga-tester-functional/SKILL.md) | 数据、协议、算法、边界与故障拒绝 |
| dg-slide-tester-beauty | [fpga-tester-engineering](../.agents/skills/fpga-tester-engineering/SKILL.md) | 工程、最终STA/CDC、资源、bit/CWC与输入绑定 |
| dg-slide-tester-animation | [fpga-tester-system](../.agents/skills/fpga-tester-system/SKILL.md) | FPGA/RK接口、上板、恢复、长稳与整链路指标 |

子角色技能由主调度按真实绝对路径传给对应代理，不要求虚构一个已注册的`subagent_type`。角色任务模板见[Codex调用对照](../.agents/skills/fpga-orchestrator/references/codex-calls.md)，统一报告见[报告约定](../.agents/skills/fpga-orchestrator/references/report-contract.md)。

原`Agent/resume/TaskOutput/Grep`的调用语法和`.claude`缓存扫描均已换为当前实际工具；保留其调度含义。[官方多智能体说明](https://developers.openai.com/api/docs/guides/responses-multi-agent)

## 本项目具体从哪里接

沿用`workflow/tasks.json`的T01—T14，F工作包只作现行策略映射。规划者每次核对[项目入口](../.agents/skills/fpga-orchestrator/references/project-context.md)，不能把本说明的配置日期当最新进度。

当前复用方向包括BPR1软件/局部RTL、parallel共享向量/算法参考、固定块/TLP和RK离线工具；DDR1333生成入口与颜色板验保持原边界。真实RAW、压缩行组合/回退/CRC、三算法真实DUT、PCIe硬核适配与实收各自形成小工作包。已有他人工作树成果先读验收记录，不能只看当前分支就重复建设。

本次不改任务板状态、不合并另一工作树、不换当前位流，也不改既有全局skills或Codex配置。既有工作流中“主助手亲自执行/复核”的角色约定已同步到开发/测试角色，以保持主只调度。`.gitignore`仅为这七个项目技能新增精确白名单，其他`.agents`内容仍排除。

## 每次任务产生的文件

```text
workflow/runs/<run_id>/
  main-log.md                  主调度的阶段、ID、判定与时间
  input-index.md               规划者的需求/来源/已有成果索引
  dev-plan.md                  本次工作包、依赖、验收和调度状态
  fpga-design-guide.md         本次采用的工程接口与设计约定
  lessons-learned.md           开发者的修正经验；首次需要时创建
  test-reports/
    <task_id>-r0-functional.md
    <task_id>-r0-engineering.md
    <task_id>-r0-system.md
    ...                        每轮新报告，旧失败证据保留
```

这些目录在真实任务开工时创建，没有预建大量空任务。输入/DB/bit等原始证据继续引用现有`docs/evidence`或隔离工程，不搬运大文件来凑数量。

每次收尾给出首次通过、修正1/2/3轮通过、未通过、待硬件/工具统计，以及下一入口。软件子包能完成自己的范围；父任务的板验、双路和整机验收不会因此自动完成。

## 效率与恢复

- 默认每批1个可验收包；三个测试维度围绕同一个产物，按范围缩小检查，避免无关整仓回归或反复跑TD。
- 主调度保持轻上下文，原开发者与测试者保留本批问题脉络；结果按文件留档，减少重复解释和重建背景。
- 一项失败不堵住所有无依赖工作；共享顶层/约束/队列/帧合同仍按依赖顺序集成。
- 同会话优先原ID续接；跨会话代理不存在时明确交接重建，不声称复活旧代理。下一次任务从文件状态恢复。
- 本流程不会扩展删除、下载、发布或外部消息权限；缺少多智能体工具时报告不能运行当前架构，保留计划，不偷偷改成主助手亲自开发。
