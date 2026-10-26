# DEFAULT-RELAY-V2 functional 静态复核输入

先读实际`.agents/skills/fpga-tester-functional/SKILL.md`。读取本run的dev-plan、request、candidate-manifest和implementation；以manifest的16个候选文件为唯一配置输入，原文件在baseline，差异在configuration.diff。不得递归派生。

按计划核对八条批准规则的配置语义及跨文件一致性，重点主仅传输、规划理解拆分/派发/收尾、默认新任务新DEV/三TEST、同任务FAIL原ID、同输入三维并行、blocked不空转、原话反馈与复测清单。必要规则无缺失/矛盾、不降低FPGA验收、不伪造通过才PASS。

只做配置静态复核，G0/G1适用，G2—G5因纯文档配置不适用；不得运行旧试任务、完整流程、压力情境或新建聊天，也不读无关生产源码/跑TD/板测。开发已停止修改。测试者仅写当前run的本维度报告/必要静态证据，不修改候选。

输出`test-reports/DEFAULT-RELAY-V2-r0-functional.md`，第一行唯一`### 判定：PASS`或`### 判定：FAIL`，按报告合同记录manifest路径/SHA、实际检查/命令与未运行边界。向主只回任务、维度、判定、报告绝对路径、manifest、blocked与续接元数据，不粘完整报告。发现输入漂移/缺条件直接回真实blocked，不自动三轮。
