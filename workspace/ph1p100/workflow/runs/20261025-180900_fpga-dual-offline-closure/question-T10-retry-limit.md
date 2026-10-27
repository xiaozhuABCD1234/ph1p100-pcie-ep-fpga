T10 的 RTL 已做出，但故障复跑因测试台路径截断缺少元数据；目前尚未验收。是否允许原开发修正路径后，仅额外复跑这一个故障场景1次（累计从2次增至3次），并在原剩余预算内补完1080p和其余必要验证？其他上限不变，T08继续执行。

需要确认是因为本项目的 [fpga-planner技能](D:/fpga/ph1p100/.agents/skills/fpga-planner/SKILL.md)引用的[有界规则](D:/fpga/ph1p100/.agents/skills/fpga-orchestrator/references/work-limits.md)明确要求：“同一失败命令最多首次加1次重试”。T10已用满这2次，不能自动增加第三次。
