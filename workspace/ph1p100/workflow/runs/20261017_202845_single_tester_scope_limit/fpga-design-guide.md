# 本轮冻结配置合同
plan_revision：2；显式触发细则及官方依据见trigger-docs.md，原数值规则不变。
task_id：CFG-SINGLE-TESTER-LIMITS；仅本项目工作流配置同步。

1. 只有明确调用fpga-orchestrator并要求执行/恢复才启用责任链；普通问答、讨论/引用/修改规则不自动进入。其agents/openai.yaml关闭隐式调用，入口description和根AGENTS同步；复用项目Skill，不新建MCP/全局入口。启用后固定责任链：主原样传输 → 原规划理解/有限拆分/dispatch → 每任务新开发 → 停止修改并冻结manifest → 一个新综合测试者 → 同任务FAIL续原开发/综合测试，round1—3 → 原规划更新/收尾 → 主原样转发。子角色不派生；默认BATCH_SIZE=1，明确合批也不扩大需求边界。
2. 三维是检查清单，不再是三个角色。functional/engineering/system的适用检查和G层由规划事先选择，综合测试者统一核验；高风险增加必要检查/证据，不自动增加角色。缺必需条件为FAIL并blocked，不能改不适用求PASS。独立指测试者独立于开发，不声称三个独立视角。
3. 唯一新技能：`.agents/skills/fpga-tester/SKILL.md`。三个旧tester技能保留，标历史兼容/领域检查参考，frontmatter及顶部说明当前默认不独立派发，旧调度/并行/报告语句无现行执行效力；相关专业检查仍供综合测试按需引用，不一律读全三份。
4. 综合报告每任务每轮一份`<task_id>-r<round>-integrated.md`；首行唯一PASS/FAIL，内含三维适用性、检查结果及G层。返回dimension=integrated、dimension_results、总体verdict、report_path、manifest_path、blocked、retest。retest覆盖失败/受影响项，未影响证据须由同一综合测试者明确绑定新manifest。
5. 统一有界规则唯一正文放orchestrator/references/work-limits.md，各现行角色链接；主只读派发/返回字段执行，不能监控进度。防循环为角色遵循约定；工具实际支持的超时才是强制机制，不保证平台对失联角色自动停止或自动回报。
6. 当前包仅G0配置合同及G1静态一致性，工程检查为路径/格式/哈希/白名单/差异范围，系统检查为入口/传输/修复与恢复合同一致性。G2—G5不适用：无RTL、构建、候选、板卡或发布改动。
已冻结：上列与dev-plan数值、允许范围、tester-input；待确认：无；不适用：像素、码流、硬件接口、时钟和板测参数。

