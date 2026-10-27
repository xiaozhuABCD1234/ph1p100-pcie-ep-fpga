# DEFAULT-RELAY-V2 system 静态复核输入

先读实际`.agents/skills/fpga-tester-system/SKILL.md`。读取本run的dev-plan、request、candidate-manifest和implementation；静态检查manifest的16个候选文件及baseline/diff。不得递归派生。

按计划核对项目根AGENTS新对话默认入口→主技能→规划dispatch链是否静态可达且一致，四份角色说明/旧可选片段是否仍冲突；检查默认新角色/同任务续接、跨会话文件恢复/真实新旧ID、无工具不主接管、不递归、不扩权、用户原话和原规划收尾。仅本项目生效，明确此次未实际创建新聊天或运行完整流程，静态入口/边界一致才PASS。

G0/G1适用；G2—G5硬件/整机因纯文档配置不适用。不得实际新建聊天、跑旧试任务/完整流程/压力情境或无关生产/TD/板测。开发已停止修改。只写当前run本维度报告/必要静态证据，不修改候选。

输出`test-reports/DEFAULT-RELAY-V2-r0-system.md`，第一行唯一`### 判定：PASS`或`### 判定：FAIL`，按报告合同写manifest路径/SHA、实际静态检查/命令、未运行范围。向主只回任务、维度、判定、报告绝对路径、manifest、blocked与续接元数据，不粘完整报告。输入漂移/缺条件直接真实blocked，不自动三轮。
