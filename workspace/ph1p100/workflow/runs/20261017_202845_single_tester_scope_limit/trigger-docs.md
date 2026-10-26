# 显式触发方案及官方依据（plan_revision=2）
本轮选择复用项目内现有fpga-orchestrator Skill，不新建重复编排器，不安装/配置MCP，不改全局配置。

## 依据
- [OpenAI Build skills](https://learn.chatgpt.com/docs/build-skills)：项目技能可放在仓库.agents/skills；显式调用与按description隐式匹配分开。agents/openai.yaml设置policy.allow_implicit_invocation: false后，关闭隐式调用，显式$skill调用仍可用；本地技能变更一般自动检测，未更新时可重启客户端。
- [OpenAI Model Context Protocol](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)：MCP连接工具/其他系统信息，服务器描述工具并处理请求。当前需求是复用规则和控制启动条件，现有项目Skill足够；这是结合需求作出的方案选择，并非官方声称MCP不能编排。将来确需真实工具服务时可另评估MCP，本轮无服务实现/安装/运行。

## 唯一默认入口与触发
以现有`.agents/skills/fpga-orchestrator/SKILL.md`为唯一入口，新增其`agents/openai.yaml`最小有效内容：
```yaml
policy:
  allow_implicit_invocation: false
```
不添加虚构MCP依赖、工具名、图标、界面字段或定时器。现有orchestrator目录已在.gitignore白名单，YAML自然可见；只需本包原先约定的fpga-tester目录白名单，不另放宽.agents。

标准执行输入：`$fpga-orchestrator 执行：<本轮明确需求>`。
标准恢复输入：`$fpga-orchestrator 恢复：<原run绝对路径>；本轮目标：<目标>`。
用户也可从技能选择器显式选择此Skill并给出明确执行/恢复指令。仅选中/提到技能但要求解释、查看、比较、修改工作流规则，不能据此启动工程工作流；引号、代码示例和转述中的触发文本也不算执行指令。

根AGENTS工作流段改为条件入口：只有当前用户明确调用上述Skill并要求执行/恢复时，才加载主传输工作流并创建角色；普通问答、报错解释、资料讨论和工作流规则编辑均按一般任务处理，不自动进入本套规划→开发→测试链。根删除禁令/DeepSeek等通用项目约束仍适用，其他适用通用技能/工具不因本规则禁用。已明确启动的同一run继续其已授权范围，不因中途问状态/规则或新增配置要求重新开链；用户明确停止/退出时停止派发并交代恢复入口。

当前run已有授权且正在完成这次配置修改；新增显式触发规则管后续入口，不要求用户重发触发词，不借讨论触发设计/生产/旧试任务。

## 静态验收与展示
验收只证明条件入口、description、YAML字段/值、文档示例和链接一致且文件可跟踪，不声称已验证客户端选择器加载、普通聊天运行或MCP执行。引用或解释“$fpga-orchestrator”的例子不得被实现为执行门槛满足。
收尾原规划生成本run`workflow-rules-for-user.md`，给可原样展示的完整精简规则正文，包含触发/非触发、Skill选择理由和上面两条官方来源，以及此前所有数值规则；user-summary.md引用/提示该正文。主原样展示正文，不自行改写。

