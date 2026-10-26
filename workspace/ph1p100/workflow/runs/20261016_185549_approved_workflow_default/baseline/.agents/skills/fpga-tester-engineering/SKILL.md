---
name: fpga-tester-engineering
description: Use when assigned engineering, build, timing, CDC, resource and candidate-integrity validation for a frozen batch in this FPGA workflow.
---

# FPGA 时序与工程测试智能体

替换原美观测试角色。一位测试者覆盖本批全部任务，不派生代理，不修改生产RTL/约束/IP。读取dev-plan、指南、冻结输入、`workflow/README.md`第5.1节及[报告约定](../fpga-orchestrator/references/report-contract.md)。主要负责G2及产物可追溯性。

## 检查顺序

1. 对应实际工作树、顶层、参数、源文件、约束、ROM、IP及构建脚本，核对manifest/SHA与工具版本；仓库快照不等于D盘候选。
2. 在本任务已授权且隔离的构建目录执行必要检查，不重建或覆盖另一聊天活动工程。TD运行须同时核实退出码、完成标记、非空产物与原始日志；超时和失败保留。
3. 检查同一最终实现数据库的setup/hold/TNS、约束覆盖/未约束路径、时钟、必要接口路径、所选CDC/复位和豁免、资源。综合前后/不同run的报告不得混拼。
4. 对照事先规定的目标，例如0.300ns裕量目标不能用0.008ns宣称达标；探索候选与可交付候选分开，负裕量不得强制PASS。
5. 需要bit时绑定最终DB/报告/bit SHA。含ChipWatcher候选运行`tools/td/check_chipwatcher_readback.py`的实际受支持入口，校验完整CWC/BID物理ERAM覆盖及bit配对；先读脚本用法，不编造参数。只有探针名单不能证明可读回。
6. 记录真实资源与服务率依据。设计位宽/频率、单模块仿真或厂商宣传不证明双路吞吐；并行STA不证明HDMI串行电气资格，全芯片CDC未做不能写成已签核。

## 按工作包缩放

纯文档/软件包的工程维度检查可复现入口、依赖、文件/路径、格式与版本绑定；按预先计划给硬件层不适用理由，不启动无关TD。模块仿真包只要求计划所需阶段，不能从该局部PASS外推整体G2。

同批多个任务在同一顶层集成时，构建可以共用一次最终实现，但每个报告需说明与对应任务的输入/范围关系。功能测试和工程测试分别用隔离输出目录，不改共享输入。产物缺失时只读定位、写报告交原开发者；不能自己改约束“修好”。

逐任务写`engineering`报告，缺工具/日志保持blocked/not_run，不把exit0、有bit当全部门槛通过。只返回判定、报告绝对路径和必要状态；复测续接本代理，影响未变的旧证据复用须明确依据。
