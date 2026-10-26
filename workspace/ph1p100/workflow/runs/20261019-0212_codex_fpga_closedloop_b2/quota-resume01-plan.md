# 额度中断后的原角色恢复入口
实际用户新增指令=request-followup-04.md“继续做”；中断原文=dev-error-production-timing-continuation01.md。原开发真实ID=/root/fpga_dev_closedloop_b01，继续同run、同B01两任务，不换角色/任务或清零计数。原规划只读已知恢复材料，没有检查当前开发进度/可变候选，没有假定活动已结束或额度已恢复。

## 权威输入和状态
原生产续接计划/ledger/dispatch分别为production-timing-continuation01-plan.md、production-timing-continuation01-ledger.json、dispatch-production-timing-continuation01.json；其中工程写范围、验收、有限预算和硬件边界完整继承。handoff.md是更早历史，其低计数/未授权描述已由后续明确授权和生产续接覆盖，不能拿来重置。
最后已验证账只提供下界：生产已用3、总上限6（后续编号4/5/6）；T06联合编译已用6、总上限8；controller5/6、oracle3/6、injection3/6等按最后真实attempt-counts-verified。额度中断后实际新增了什么未知，由原开发核对，不按3/6或6/8直接假定剩余。独立综合r0、实际修复和补充机会的最后已知值均未发生/0；主没有新建tester，不能伪造综合结论。

## 第一阶段只做原开发自己的恢复核账
本次接到followup后，先用自身上下文、此前实际工具会话/执行文件和自有PID记录核对，最多10工具/10分钟，计入原生产续接的150工具/240分钟累计预算，不能当新的一份150/240。
1. 依据自己的真实argv/cwd/输出路径/PID/创建时间/启动和截止时间识别本角色已启动的进程。仅查已知自有PID/会话，不扫描无关应用/其他聊天，不凭PID相同或同为当前用户就杀进程；PID重用要核对创建时间和命令。
2. 自有原生构建/仿真仍运行时，接回真实可用工具session或原有控制器，沿用原始启动时刻计算的deadline与原attempt编号；接回/收取已有输出不启动新attempt。quota间隔不能重置3600秒/600秒。到期只按已落实的控制方式终止可证明属于本次的PID树，保留实际退出/超时。不能证明所有权/原截止点或会话已经不可控制时，返回TOOL_CONTROL_MISSING/INPUT_CONFLICT，不猜ID、不杀他人。
3. 若已结束，先读其真实exit/完成标记/非空产物/输入SHA和工程报告。正常完成、超时、失败、仅目录创建、命令是否真正启动分别记录；有未确认的attempt占用要保留“未知”并停止新构建，不能假定未消耗。
4. 汇总实际attempt4–6是否已启动/完成、T06/G1新增调用、已用工具与实际工作/自有命令时间。额度断开期间的未知区间单独列出；不凭感觉填0或满额，不把未工作的额度等待当成重置授权。无法可靠确定剩余时先返回核账结果，禁止盲目长构建。
5. 核查当前源修改、与最后冻结/自己的prechange副本的关系、已有manifest是否真正冻结及活动是否结束。若已经存在同输入的完成结果，先复核/收取，不能重新做一遍。已冻结文件保持历史，不覆盖失败证据。

将audit结果版本化写到C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2/recovery01/B01/timing-continuation01/quota-resume01/：activity-check.json、attempt-reconciliation.json、resume-decision.md（可等价命名但返回准确路径）。最小字段：own session/PID身份依据、原start/deadline/current状态、实际attempt/exit/产物、源码/manifest身份、已用与剩余预算、下一条确定动作。不要发环境/凭据或无关进程信息。

## 核账清楚后继续原授权必要工作
若无未决自有活动/漂移/计数冲突且原预算仍有剩余，直接按原生产时序计划继续，不必再问用户是否继续：
- 原HE-state→row-bank反压路径、真正弹性边界与native hold修复策略保持；不改原时钟/IP/SDC门槛、不绕计数。
- 生产累计仍最多6，每完整生产会话3600秒/CWC后处理600秒；局部每TB300秒，读取60秒，未来SRAM下载120秒。所有执行遵守原始owned PID控制和实际deadline。
- 仅必要失败/受影响项验证，未变成功证据绑定复用；不重复已完成且同输入的G1或生产构建。原G1累计上限不扩。
- 本次时序续接原150工具/240分钟只扣实际核账确认的剩余，恢复核账也计入。工具/时间已耗尽或无法重建可靠账，返回原规划，不自行扩预算。
- 必要G1/G2/STA/CDC/资源/CWC与输入身份全满足、全部活动结束/停止修改并冻结新manifest后才ready_for_test。届时主首次创建一个综合tester覆盖B01；当前未确认状态不能派测试。
- 用户此前当前在场/可配合、多上板偏好保持。合格候选独立综合通过后优先T02，必要人工动作给具体可审查步骤并只停依赖处；不重问已授权SRAM许可。不下载已知rejected或未资格候选，不接PCIe/RK，不写Flash、不推送、不批量删除。

## API/额度再失败时
用户本次真实“继续做”授权一次原角色续接尝试，不能据此宣称额度恢复。若实际原生followup或该角色再收到额度/API错误，立即保存真实错误并交原规划，reason_code按QUOTA/API_ERROR；不自动再次followup，不切换ID/宿主/模型绕额度，不调worker替代原角色，不循环检查账户。只有后续真实新增用户输入或外部条件变化再由原规划处理。
同一额度阻塞problem_id固定B01:QUOTA:provider-usage-limit；关联原T06/T09 timing问题保留。额度事件不是实现修复轮、不是编译/生产成功；中断前已实际启动的native命令照实计数，不因API错误抹掉。

## 角色返回
成功按开发合同返回task_ids/status/artifact_paths/manifest_path/test_input_paths/lessons/blocked/retest，附本次核账准确路径。若只完成核账便发现外部阻塞或原额度不足，同样给精确problem和最后实际结果，不声称已停止所有活动，除非责任角色已经核实。原规划不开发/测试/接管，主不监控。
