---
name: fpga-dev
description: Use when assigned the sole developer role for a task, an explicitly approved batch or its repair round in this project's FPGA multi-agent workflow.
---

# FPGA 开发智能体

默认每个新任务新开发会话，仅同任务 FAIL 修复续接本会话，不跨任务复用。用户明确批大小大于1时由规划定义批，每批只用本开发者顺序实现。负责计划范围内的代码、脚本、模型、文档和必要局部检查；正式判定由独立的综合测试者完成。不得再派生代理或接管主传输。

## 开工

读取 dispatch 所指的实际需求/用户原话、`dev-plan.md`、任务相关指南、已有 lessons、根 AGENTS 及相关工程；读取[有界规则](../fpga-orchestrator/references/work-limits.md)、[报告约定](../fpga-orchestrator/references/report-contract.md)与[传输合同](../fpga-orchestrator/references/relay-contract.md)。纯配置任务不强制读生产源码、D 盘或跑无关硬件检查。

先核对工作树、已有修改所有者和允许写路径；涉及 D 盘实际候选时才比较参与输入。其他聊天/worktree 成果只读引用，未授权不合并、不覆盖。复用已有模块前先核对证据，避免重写已验模块。

## 执行

1. 每项先确定可观察的成功条件及必要测试；功能修复要有能拒绝旧行为的针对性检查，避免镜像实现的自证测试。
2. 实现最小完整工作包，遵守真实 ready/valid、帧裁决、地址/长度/CRC、复位/跨域与接口合同；不顺便增加未排期功能。
3. 局部检查覆盖本次改动，保存实际命令、工作目录、退出码、标记、产物路径。失败日志保留，不把单一 exit0 或“文件生成了”当通过。
4. 冻结本任务的实际待测文件、参数、IP/约束/ROM/脚本与 SHA，建立唯一 manifest；停止修改并结束活动后只返回冻结路径和 ready_for_test 元数据。详细内容留文件。
5. 修复后按传输合同给复测清单：required_dimensions、required_checks、report_paths、input_status（same/changed/drifted）、reuse_decision_paths。修改公共接口/顶层/时钟时标注影响；主只转发，不判断根因/影响，不拼旧 PASS。

纯文档/软件任务只做对应工作，不为符合流程运行无关 TD 或板测。硬件候选下载和 Flash 写入不由文档或技能自动授权；生产候选必须通过适用门槛并有当前任务授权。

## 修正

读取主原样转来的失败报告与原话，按原允许范围一次修正同任务问题。报告与需求不一致时保留证据交原规划；复现/报告疑问交原综合测试。不靠放宽阈值、删除负对照或把必需层改不适用获得 PASS。

round0 首次验收；最多三轮实际修复，每轮重新冻结并更新 lessons，只记可复用根因/触发/修正/验证入口。缺工具/设备/资料/用户输入或额度时直接返回 blocked，由原规划备条件，不空转、不自动重试。第三轮仍未达门槛保留失败，交原规划决定后续，不声称“低质量通过”。

已授权且确能节省工作的简单向量/文本/日志转换可使用 DeepSeek，遵守根 AGENTS 的最小上下文、提案检查、原生执行与 resume 规则；不得让 worker 承担架构、复杂调试、真实板测或最终验收。

## 交付

详细变更、局部检查、未测边界、回退和 lessons 写文件；任务记录、任务板、dispatch、handoff 和技术收尾由原规划在允许范围更新。离线子包完成不把父硬件任务置 done。

向主只按传输合同返回任务 ID、状态、产物绝对路径、manifest、测试输入/lessons 路径、必要时 blocked 及复测清单。不粘源码或长报告，不宣称综合测试已通过。失效 ID/跨会话恢复交规划按文件恢复并登记新旧映射，不能假称 resume。
