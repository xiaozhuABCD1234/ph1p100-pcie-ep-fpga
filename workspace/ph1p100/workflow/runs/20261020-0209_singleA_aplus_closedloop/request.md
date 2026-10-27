# 本轮用户需求（原样保存）

## 入口

用户显式选择了本项目的 /fpga-orchestrator 入口。以下是参数原文，原样保存与转发：

执行：推进单A真实输入的 A+ 压缩闭环。

## 参数原文

本次需求：
1. 优先完成 T10 A+ 压缩 RTL 独立闭环。
2. 在推进第1项时，同步准备真实输入参数和 RAW 样例。
3. 前述必要条件验收后，紧接着完成单A实际采集、DDR、A+压缩、保存、读回及PC独立还原闭环。

完整需求文件：
C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\docs\planning\2026-10-20-fpga-priorities\01_OpenCode启动需求_单A_Aplus闭环.md

请将该文件作为完整用户需求交给规划读取，按项目工作流先规划和冻结，再派开发与独立综合测试，不要只给建议后结束。

C不纳入本轮；RK/PCIe主机实机、真实双路和G4长稳后置。不推送、不写Flash；如涉板仅SRAM，遵守文件中的次数限制。

遵守默认最多4个正式工作包；无法合理覆盖三项时，由规划明确本轮最小可交付切片和剩余内容，不硬塞、不自动扩轮、不把部分完成宣称为全部完成。

先用当前 OpenCode 的原生 skill 工具加载 fpga-orchestrator（2.0.28 的参数是 {"id":"fpga-orchestrator"}）；必要时直接读取项目根下 .agents/skills/fpga-orchestrator/SKILL.md。

只有参数明确要求“执行”或“恢复”才启动角色链。参数为空、只讨论/查看/修改规则时不启动，也不把选择本命令本身当执行需求。本命令在当前主会话运行，不把主传输者另派成子代理。

按共享 Skill 及 references/opencode-calls.md 执行：主只原样传输和机械留档，规划理解并有限拆分，每任务新开发和一个新综合测试者，同任务修复续真实原 sessionID；主不监控，子角色自行有界停止。继承根 AGENTS 的约束及当前客户端实际权限，不扩大授权，不使用 Codex 专属工具名。

## 机械登记

- 记录时间（上海）：261020 0209
- 完整需求文件（仅记路径，未由主读取内容）：C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\docs\planning\2026-10-20-fpga-priorities\01_OpenCode启动需求_单A_Aplus闭环.md
- 文件存在性检查：True；字节数 9719
- 项目根：C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道
- run 输出目录：C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261020-0209_singleA_aplus_closedloop
