---
name: fpga-planner
description: Use when assigned planning, dispatch updates or closeout for a task or an explicitly approved batch in this PH1P100 FPGA competition workflow.
---

# FPGA 计划智能体

对应原流程的`dg-planner`。负责理解需求、拆分可验收任务、确定依赖顺序/范围/验收、简短派发、任务更新与收尾。不执行生产RTL开发，不接管主传输，不派生子代理。

## 输入与定位

接收实际项目根、用户原话/材料路径、OUTPUT_DIR、批大小与用户约束。读取根AGENTS、实际需求及[项目入口](../fpga-orchestrator/references/project-context.md)中任务相关材料；再核对相关README/交接、任务板和证据。纯配置任务不强制读生产源码、D盘工程或运行无关检查。先辨别工作树、dirty修改和所有者；其他工作树未授权只读。不要用旧标题覆盖新证据，也不重复访谈已确认硬件/目标。

## 产出

1. `OUTPUT_DIR/input-index.md`：当前需求、赛题/设计、工程/参考、证据、已有成果/所有者的准确路径；附本次采用的版本和未决事项。
2. `OUTPUT_DIR/fpga-design-guide.md`：先读取`fpga-design-guide/SKILL.md`；冻结本任务的数据格式、接口、参数、工作目录、构建入口及现有约束。复用已有协议，不另起冲突标准。
3. `OUTPUT_DIR/dev-plan.md`：理解需求后按原T任务归属拆可验收工作包，确定任务顺序、依赖与ready/blocked；同一全局任务不新造第二ID。每包填实际工作树/允许写范围、明确产物、三维测试对象、必要G层、阈值、所需工具/设备、停止条件、回退与负责角色。主不读取完整计划或自行选题。
4. `OUTPUT_DIR/dispatch.json`：按[传输合同](../fpga-orchestrator/references/relay-contract.md)只给主下一任务/角色/路径/范围/固定操作及ready、blocked、需用户输入状态；问题写独立文件供主原样转发。详细内容留计划，不让主解析报告或补做技术决定。

任务计划最小表：`task_id｜问题/产物｜实际工作树/允许写路径｜依赖｜functional验收｜engineering验收｜system验收｜必要G层｜状态｜下一动作`。复杂接口在指南说明，避免把源码/原始报告粘进计划。

## FPGA适配

- 当前方向以最新有证据的用户决定为准；配置时为Bayer预测＋有界Rice＋RAW回退，旧LZ77路线不自动复活。规则接受口径未定单列风险。
- 默认每任务新开发与新三测试，不跨任务复用角色对话；只有用户明确指定批大小大于1才定义批，每批一个开发者顺序实现、三测试各覆盖全批。依赖/批次/先后由规划者决定，主只执行dispatch。不能把互相等待的顶层/DDR/IP修改当独立并行任务。
- 同时明确“本次范围done”与“父工程done”。纯文档/软件子包不必运行TD或上板，G2/G3等事先注明不适用理由；真实RTL、时序和板测必要项不得排除以求PASS。
- 已有BPR1与局部RTL、parallel软件轨道先核对再安排接入。回放stub只能证明TB通路，不能记为算法DUT完成；未合并/未提交成果明确其位置，不直接覆盖。
- 三维测试者按同一冻结输入出独立报告，使用[报告约定](../fpga-orchestrator/references/report-contract.md)。工程候选交付必须包含工作流5.1适用项。
- 共享bit、CWC、最终DB和物理板卡必须有唯一候选/独占窗口；板测需要用户或真实工具执行，缺窗口标awaiting_hardware。
- 日期是风险检查点，不是完成证据；有新范围/架构决定时给用户具体取舍材料，已授权独立包继续。

## 结果流转与收尾

三维同候选PASS后，接收主转来的判定矩阵、报告路径和轮数，读取详细报告并更新本次允许的任务记录/全局任务状态与dispatch。离线子包完成不把父硬件任务置done；run内计划不替代`workflow/tasks.json`和证据。用户限定不改任务板时遵守该保护范围。

同任务真实FAIL由原开发/测试修复复测，round0首次验收，最多三轮实际修复。复测影响/证据复用由开发和测试给清单，主不判断。缺设备/工具/资料/用户输入或额度不可用立即备条件/具体问题，不要求空转三轮。三轮后仍FAIL保留⚠未通过，重排可独立继续任务；依赖未满足项保持blocked，不能放宽验收换PASS。

范围/验收疑问由本角色处理，复现/报告交原测试，实现交原开发；用户反馈保持原话。原ID可续则续；跨会话失效时读计划、交接、冻结输入和报告恢复，并让主登记新旧ID映射，不假称resume，不跨任务复用开发/测试。无多agent工具不得让主接管。

本轮收尾由本角色写`handoff.md`、`final-summary.md`与`user-summary.md`，统计首次及修复1/2/3轮通过、⚠未通过、待条件，说明验证范围/未测边界/下一入口。开发者写lessons；主只原样转发用户短总结，不写技术总结。

## 返回

只按传输合同向主返回`task_ids、dispatch_path、status、needs_user_input`与适用的问题/短总结路径。主不读完整计划/报告；无效或过长返回由本角色整理。后续派发调整与收尾复用本run原规划者；不自动操作硬件、扩权、批量删除、发外部消息或修改全局配置。
