# DEFAULT-RELAY-V2 交接

本轮已完成：用户批准的《FPGA 多智能体工作流——主对话仅作传输》已同步为本比赛项目默认配置。任务状态complete，round0三维静态复核PASS，实际修正轮0，无blocked、无待用户输入。

## 默认入口和下一次启动

项目根：`C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道`。

以后在该项目目录开启本地新对话并布置任务，按根`AGENTS.md`进入`.agents/skills/fpga-orchestrator/SKILL.md`。主仅原样转发、机械日志和固定分支；规划者读材料理解需求、拆任务并给薄dispatch；默认每任务新开发与新三测试；同任务FAIL续原角色，最多三轮实际修复，缺条件不空转；PASS或终态回原规划者更新/派发/收尾，主原样转发总结。用户明确批大小大于1时才使用批准的批次扩展。必要权限及范围检查继续有效。

新需求使用新run和新任务角色。只有恢复本run未完成事项才尝试其实际原ID；本run已无待实现/待验项，不需自动恢复开发。跨会话不能保证这些代理仍可续，失效时按文件交接由规划者恢复并记录映射，不假称resume。

## 候选及证据

冻结manifest：同目录`candidate-manifest.json`；SHA256=`2b81f3b9c65f28cc30bf2cb3f7e65a47ef54cddb1c5595b39cf368e873d3cc14`；冻结时间`2026-10-16T19:18:42.8295789+08:00`。16个候选配置，三维均声明input_status=same；规划收尾没有重新执行检查或修改候选/manifest。

| 维度 | round0判定 | 报告（本目录相对） | 真实角色ID |
|---|---|---|---|
| functional | PASS | test-reports/DEFAULT-RELAY-V2-r0-functional.md | /root/relay_default_test_functional |
| engineering | PASS | test-reports/DEFAULT-RELAY-V2-r0-engineering.md | /root/relay_default_test_engineering |
| system | PASS | test-reports/DEFAULT-RELAY-V2-r0-system.md | /root/relay_default_test_system |

开发ID=`/root/relay_default_dev_t1`；原规划ID=`/root/relay_v2_planner`。开发产物：`implementation.md`、`candidate-manifest.json`、`test-dispatch.json`、`lessons-learned.md`；回退材料：`baseline/`、`baseline-index.json`、`configuration.diff`。回退前须核对后续修改，只准备明确文件差异，不自动reset、清理或删除。

本轮只更新项目默认指令、七技能及相关references/workflow说明；三独立报告覆盖流程/角色一致性、技能格式/本地链接/实际参数、默认入口与权限/恢复边界。G0配置合同、G1静态一致性通过；G2—G5硬件/整机层按计划不适用。

本run的dev-plan和dispatch已从待执行状态更新为收尾状态；这两项是运行控制记录。冻结manifest/报告仍记录验收时输入，后续不能将收尾控制记录冒充另一配置候选的旧PASS。

## 未运行及保护

没有试跑完整工作流、实际创建新聊天验证加载、执行旧两项试任务或进行FPGA/TD/下载/Flash/板测/长稳/整机操作；静态PASS不证明这些行为或硬件通过。没有修改`workflow/tasks.json`或把父工程任务置done，没有改变全局配置、扩大外部消息/发布授权。删除禁令、DeepSeek边界及无关已有修改保留。

下一动作仅为主原样转发`user-summary.md`；本次配置任务无下一开发/测试派发。
