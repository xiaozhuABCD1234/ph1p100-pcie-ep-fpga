# WFLOW-V2：按原图收敛为主对话传输流程

本轮为配置修订，BATCH_SIZE=1，只有一个可验收工作包`WFLOW-V2`。规划已完成，状态`ready`。本文件供开发和测试角色读取；主对话只读取同目录`dispatch.json`，不解读本文件来拆任务或选择下一项。

PROJECT_ROOT=`C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道`。
OUTPUT_DIR=`PROJECT_ROOT/workflow/runs/20261016_130619_relay_workflow_revision`。

## 需求和退出条件

保留完整泳道图及上轮截图的主结构：接收需求路径→规划者理解并拆任务→每任务一个新开发者→三个维度测试并行→同任务FAIL续接原开发/测试者，最多三轮实际修正→状态反馈→下一任务新代理→收尾。只有用户明确指定批大小大于1，才使用截图中的每批一个开发者、每维度一个测试者覆盖全批扩展。

用户补充原话：`当然规划子智能体还要做把需求拆分成拆分任务的任务，还是要对这个工作流再详细对齐下防止偏差`。因此理解原始需求、任务拆分、ID归属、依赖、顺序、范围和验收全部属于规划者。主对话不选题、不拆任务、不读详细计划/源码/技术报告、不评估技术影响、不编写技术总结或队友决策文本。

本轮完成的含义：七技能及相关默认入口一致；薄派发契约可用；三个测试角色对同一配置候选各自PASS。不能因此宣称FPGA、旧试任务或整机完成。原图逐步对照和现存差异见`alignment.md`。

## 唯一工作包

| task_id | 问题/产物 | 工作树/写范围 | 依赖 | functional验收 | engineering验收 | system验收 | 必要G层 | 状态/下一动作 |
|---|---|---|---|---|---|---|---|---|
| WFLOW-V2 | 修订七技能、默认入口、调用/报告契约、说明和两任务启动说明；交付配置清单及冻结manifest | 当前项目，仅下列白名单；不创建新工作树、不提交/push | 本计划、指南、对齐文件齐备 | 原图各步骤/职责/转换条件一致；需求拆分归规划；FAIL分类、反馈转发与状态案例完整 | 七SKILL frontmatter/链接/路径/实际工具参数正确；保护范围不变；同候选SHA绑定 | 两任务隔离调度烟测：FAIL原ID续接、PASS下一任务新ID、三维并行、blocked不空转、用户原话转发、恢复 | G0配置合同、G1文档/状态机验证；G2—G5硬件不适用 | ready；派唯一fpga-dev |

## 允许写范围及保护

所有路径相对PROJECT_ROOT；未列路径只读。开工先重新核对已有修改和路径链接，不回退、不清理、不覆盖并发更改。此前git状态已有大量dirty/untracked，不能视为本轮创建。

- `.agents/skills/fpga-orchestrator/SKILL.md`
- `.agents/skills/fpga-planner/SKILL.md`
- `.agents/skills/fpga-design-guide/SKILL.md`
- `.agents/skills/fpga-dev/SKILL.md`
- `.agents/skills/fpga-tester-functional/SKILL.md`
- `.agents/skills/fpga-tester-engineering/SKILL.md`
- `.agents/skills/fpga-tester-system/SKILL.md`
- `.agents/skills/fpga-orchestrator/references/codex-calls.md`
- `.agents/skills/fpga-orchestrator/references/report-contract.md`
- `.agents/skills/fpga-orchestrator/references/project-context.md`：仅角色读取边界/导航文字，不改已有FPGA技术事实。
- 可新增`.agents/skills/fpga-orchestrator/references/relay-contract.md`集中定义薄派发/返回字段，不新增第八技能或常驻角色。
- `AGENTS.md`：只修订`## 后续任务的默认工作流`起的工作流段；其前的删除禁令、DeepSeek完整块逐字保留。
- `workflow/FPGA多智能体工作流_使用说明.md`
- `workflow/AI协作与工具接入.md`：仅角色约定和开始/恢复/收尾指令等与默认流程冲突处；不修改DeepSeek权限或工具接入事实。
- `workflow/AGENTS接入片段.md`：修复过时的“未改根AGENTS/角色不要求多代理/主助手最终核验”入口。
- `workflow/README.md`：只修订默认调度提示和5.1中执行角色文字，G层/工程门槛不变。
- `workflow/runs/20261016_121011_trial_task_design/new-chat-prompt.md`：保留原启动正文作为历史，顶部加当前V2入口说明；可另建同目录`new-chat-prompt-v2.md`供以后复制，两个原任务的技术范围、ID和依赖不擅改。
- 本OUTPUT_DIR内开发交付、manifest、局部检查、lessons、报告、隔离烟测、收尾/用户短说明文件。规划者文档如需实质调整，转回原规划者；不要开发者静默重写验收。

禁止修改`workflow/tasks.json`及生产RTL/IP/约束/模型/parallel源码、D盘工程、其他工作树、全局Codex配置和其他聊天文件。禁止执行旧两试任务，禁止下载/Flash/发布/自动监控/队友消息。禁止删除；历史报告和失败产物保留。

## 开发步骤（同一开发者顺序完成，不再拆代理）

1. 读本run需求、指南、索引及alignment；识别现有文件与并发变化。保存本轮涉及文件的基线SHA和根AGENTS受保护前缀；不为本配置任务展开FPGA生产源码、完整历史报告或原试任务实现。
2. 修订主技能：只读薄dispatch和返回元数据；按固定动作调用工具、登记真实ID、追加固定调度日志、原样转发用户反馈。详细计划/技术判定/文件编写交子角色。删除主“读dev-plan后自行选任务/分组/分析影响/写技术收尾”的职责。保留必要权限、写范围和工具安全检查，不承诺无判断自动执行。
3. 修订规划技能和设计指南：明确原始需求理解→拆成独立可验收任务→依赖顺序→三维门槛→ready/blocked→dispatch；默认每任务新开发/测试代理；批次扩展只在用户指定>1时启用。规划者负责后续计划矛盾、缺输入、范围变化、状态整理及收尾材料，不增加总管角色。
4. 修订开发及三测试技能：上下文只带当前任务/批次路径；同任务修正才followup原ID；所有细节落文件，返回短控制元数据。缺输入/问题转对应原角色；测试者不修生产文件。开发者负责技术影响和重测输入；测试者独立确认复测/证据复用。
5. 建立统一薄契约，采用指南中的字段和确定性转发规则。原报告首条PASS/FAIL保留；新增失败分类/条件/修正可行性元数据，阻塞不能机械耗尽三轮。统计和交接由原规划者或开发者写，主只转发现成摘要/路径。
6. 同步调用参考、根入口、使用说明、角色约定及旧试任务启动入口；标注观察到的原图规则与FPGA/本宿主必要适配。保留项目任务板唯一主源，run的dispatch只作本轮控制入口。
7. 做与文档配置相关的局部检查，交付`implementation.md`、`candidate-manifest.json`及简短`dev-result.json`。manifest列真实修改/新增文件及SHA，确认停止修改后通知可测试。开发自查不称独立三维PASS。

## 三个独立测试角色的本轮验收

三个测试者读同一冻结manifest和本计划，各写`test-reports/WFLOW-V2-r0-<dimension>.md`（修正后r1—r3新文件）。不运行TD/ModelSim/板卡、旧A/B实现或整仓历史回归。

### functional：流程语义及角色案例

逐项核对alignment的步骤均有对应配置；检查主不拆分/解释技术内容、规划者实际拆分、一个开发者、三个固定维度、子角色不递归派生。用文档角色案例验证：原始模糊需求交规划者；细计划不给主；开发缺输入回原规划；测试复现疑问回原测试者；验收合同冲突回原规划；用户反馈原话传回原角色；第三轮未过保留⚠；硬件不适用须预先决定；blocked与DUT实际fail分开。检查无强制PASS、无外部授权扩大、无全局任务板第二主源。

### engineering：格式、路径、参数与候选完整性

七SKILL.md有合法frontmatter和对应name/description，准确相对链接可解析；绝对路径使用实际根，中文/空格路径安全。比对当前`collaboration`实际schema：`spawn_agent(task_name,message,fork_turns)`，`followup_task(target,message)`，`wait_agent(timeout_ms)`，`list_agents`；不出现可执行虚假Agent/subagent_type/run_in_background/resume参数，也不扫描.claude缓存猜ID。历史对照文字允许保留但须明示不可执行。不得擅自指定模型/推理设置。仅主调用多代理工具，role禁递归。核对受保护AGENTS前缀和tasks.json不变，报告绑定实际候选和本轮变更；不将已dirty文件的全量差异冒充本轮改动。

### system：隔离双任务调度烟测

在本OUTPUT_DIR下隔离目录建立小型状态/转发轨迹，任务名用`SMOKE-A/SMOKE-B`，不运行原T03.trial-A/B代码。检查以下断言：A开发后3测试同输入；A一次可修复FAIL调用A原DEV及原TEST；A全PASS后B用不同的新DEV及新三TEST；B缺设备/工具时立即等待条件，修正轮数不增长、不重复三次；独立任务可由规划者输出下一dispatch，依赖任务保持blocked；用户含歧义原话逐字交原角色；输入漂移不拼旧PASS；ID失效明确新旧映射/交接，不假称resume；返回正文超长/无判定/状态矛盾回原角色整理。

烟测可以是只读推演或隔离小脚本驱动固定控制数据。合成ID必须标`synthetic`，不得冒充真实API执行。本轮真实角色ID由主登记；系统测试者不为烟测再派代理。报告区分“契约烟测通过”与“真实两开发任务执行”，本轮后者未运行。

通过阈值：以上必需案例全部满足；无根角色越界、无错误ID续接、无失真PASS、无受保护文件改动、无无条件三轮空转。发现真实缺陷给路径/触发/期望及报告，交本包原开发者修正。

## 修正、停止和交接

首次验收round=0；可修复配置缺陷才进入1—3轮实际修正。同任务复用原DEV/TEST；主把三报告路径及原始反馈转交，不自己判技术影响。缺工具/资料/授权/设备、输入漂移、报告格式问题不自动消耗修正轮；原责任角色给条件和路由。行政格式纠正最多一次无变化重试，仍矛盾则转原规划者/用户，避免无限循环。

测试期间候选停止写入。候选变更后FAIL维度必须复测；其他维度由原测试者确认新输入上的复测或证据复用，重新出具绑定当前manifest的结果；主不拼接新旧PASS。三轮后未过保留⚠和依赖状态，不能降低门槛。外部条件未变不反复启动角色。

并发改动、白名单外必要修改、需求/验收矛盾：保留证据，转本run原规划者；已授权独立工作继续。缺工具不能偷偷主亲自实施。回退只提供本轮明确文件的差异/恢复材料，不自动reset或清理其他修改。

三维结果齐备后，原规划者或开发者依据报告写本run`closure.md`和`user-summary.md`（用户短说明建议3—5句），统计首次/1/2/3轮通过、⚠未过、blocked/awaiting条件及恢复入口；主只转发现成摘要和路径。只在满足本包全部要求时称本包完成。
