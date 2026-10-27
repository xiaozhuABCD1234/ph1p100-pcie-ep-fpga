# 两包一次有界静态收尾：原授权必要交付

PROJECT_ROOT `D:/fpga/ph1p100`，OUTPUT_DIR `D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure`。本次沿用原两包任务与BATCH_SIZE1，不新增正式包、实验重试或实现修复轮。

## 授权与更正

原两包交付指令、两次“接着做”，以及 `user-feedback-readonly-recovery01.md` 中明确批准的完整问题“确认原开发角色状态及已有冻结产物，再按原范围续接；全部计数保留，不增加仿真、构建或下载预算”，已经涵盖整理已有结果、补真实manifest/交接这类必要可逆交付。主传输角色已复核此授权边界。先前 `dispatch-readonly-recovery01-blocked.json` 的重复确认问题由本派发取代，原审计事实和历史记录完整保留；不等待用户重复确认。

本次收尾每包最多**10次实际工具调用、15分钟**，从原角色实际收到本次具体任务起计；原角色若真实ID错误才按文件恢复，恢复角色继承同一收尾窗口剩余额度，不因换ID再得10次。记录真实开始/截止与本次累计，工具包装层及内部native操作保守合计；到限立即停止并交实际结果。此窗口仅收尾，不修改/回填旧21:02:49、19:55:19截止，不延长任何实验窗口，不追认历史超用合规。

## 共同禁止项与写域

- 只读/哈希、已有采集字节后处理、生成新的manifest/结果/交接/计数/影响与retest文件；**禁止RTL/TB/模型/原runner修改，禁止仿真、vlib/vlog/vsim、综合、构建、TD、位流、下载、盘符、硬件、COM、RK、外部消息/Git/删除**。T10故障累计仍3/3、compile仍4/4，不能第4次故障或第5次编译。
- 旧来源、旧manifest/报告/失败与编译库均不改、不重新生成。开发每包只写自己任务目录下 `static-closeout01/**`；如T08位于r1下，准确写域为 `T08.dual-local-closure/r1/static-closeout01/**`。不得运行会覆盖冻结根目录的旧生成器或绕过旧freeze脚本的deadline伪造“按原时窗完成”。可以在新收尾目录写专用metadata脚本，读取已完成日志/字节后生成真实当前时间的冻结文件；该脚本不能启动任何native实验工具。
- 先核对 `readonly-recovery01/audit.json`、原命令回执和当前SHA。一次审计角色/进程快照不能冒充当前作者停止声明；原作者从上下文核实自身活动已结束，恢复角色按回执、已知单次快照及当前自身无新活动如实说明证明边界。存在未解释源漂移/未终结命令/身份不明时必须blocked，不硬写ready。
- 未能恢复的历史调用数保留unknown和已知下界，不填0、不用新窗口覆盖。T08r0保守101/原60超用保留；T08r1已知compile2/case13；T10恢复前calls37、恢复后日志新增compile1/case2（累计compile4、case11、faults3），其他调用未完整记录不猜测。本次收尾准确实记，无实验计数增量。

## T08具体收尾（原开发优先）

原开发 `/root/fpga_dev_dual_local_180900`；读 `T08-repair-r1-plan.md`、r0 FAIL/fix/retest和 r1源码/compiled-source快照/13项case-result。一次审计已见r0漂移0、r1实际编译源漂移0，13/13局部结果声明成功（含有效变异拒绝），真实重叠证据存在。自行只读核实后生成：

`T08.dual-local-closure/r1/static-closeout01/{manifest-r1.json,result-r1.md,handoff.md,execution-accounting.json,change-impact.json,retest-r1.json,reuse-proposal-r1.json,source-map.json}`。

manifest绑定实际参与的r1源码/TB/环境/runner、对应编译源SHA、case/原始日志/字节、工具/参数、r0保护manifest与本run冻结指南、实际代码修复1和这次静态收尾的不同时间；排除可变ModelSim DB/WLF/缓存，明确排除项但不删除。保留r0报告、原edges测试者已用1/累计上限2及其修正后仅余1次的历史。局部不等于独立PASS。

允许ready_for_test的条件：实际来源与compiled快照一致，原F01/F02源码确已修、必需13类局部结果/真实F03重叠/CRC和安全回收证据完整且可定位，所有已发起命令有结束回执，真正停改/活动结束，输入无未解释漂移，唯一新manifest完整。否则生成blocked的同名manifest/报告并精确列缺项。不能仅因已有case-result pass而跳过来源/数据对应核对。

## T10具体收尾（原开发优先）

原开发 `/root/fpga_dev_dual_scheduler_180900`；读 `T10-resume01-input.md`、原r0与恢复目录回执/源码/strict checker文件、原完整验收清单。审计曾发现旧manifest有8项不符；本轮已定位为5项ModelSim库元数据变化/缺失及3项已获准修改的TB/runner文件，**三份DUT源码均不在旧manifest漂移清单**。不能将这8项误称DUT被换，也不能沿用旧manifest覆盖新TB/新执行。

第三次faults已有4个恢复帧的strict checker；双1080p已有2个不同身份帧的strict checker，明确eof/无尾、raw/xform/stream长度CRC和逐字节图案。只读核对这些实际数据和源码/命令对应，再新生成：

`T10.dual-aplus-scheduler/static-closeout01/{manifest-resume01.json,result-resume01.md,handoff.md,execution-accounting.json,source-map.json,retest.json,local-evidence-map.json}`。

新manifest精确绑定当前不变core/frame/scheduler、已修复的TB/runner/字节checker、原始命令与实际采集/metadata及控制授权；保留旧manifest为历史（包括其库项过度冻结导致的变化），本次明确把可变工作库与当前实际测试输入区分并列排除原因，不能删旧证据或假装修复历史SHA。

允许ready_for_test的条件：实现本身已完成，当前三份DUT与最终实际compile/运行来源可证明一致；第三次faults和full的结束/strict内容证据有效，停止修改/活动结束且新唯一manifest完整。开发局部证据的不足必须列给独立测试者：旧正常小参数在codec-cleanup前的结果不能直接充当新输入PASS；独立测试者须按原清单重新验证正常/奇数高/反压公平/容量/phase/错误身份/RID/RLAST/有效负对照等。安排这些既定独立检查属于原测试职责，不是要求tester补实现或替作者伪造局部结果。

如只读审查发现实际RTL/协议仍缺实现、真实来源无法绑定、或必须再改RTL/再跑开发实验才能提交候选，就冻结blocked和准确缺项，不把“已有full/faults”强行转换ready，也不启动本次未允许实验。无论ready或blocked都如实列工程/源限制、逐项已做/未做与证据可复用边界，不宣称G0/G1综合PASS。

## 原角色调用与实际ID失效恢复

主各先执行一次实际的具体静态收尾followup，不发进度询问或预防性探针。原ID未列live并不是原生ID错误。只有该实际工作调用返回明确unknown/not-found/无法续接ID错误时，才按既有文件恢复一个同职责静态收尾开发者：fork_turns=none，只传本文件/任务输入路径，工具返回新ID后登记old→new、原因和当前预算已用，不假称resume；不得借此恢复实验额度。API/quota/其他失败不是ID错误，不自动重试或换人。

开发只回当前真实元数据（task_ids/status/artifact_paths/manifest/test_input/lessons/blocked/retest、停止声明、当前/历史计数与实际ID映射）。两包独立，各自收尾可并行，写域不重叠。

## 冻结后的独立验收仍有原预算

T08 ready_for_test后续原唯一测试者 `/root/fpga_tester_dual_local_180900` 执行真正r1独立验收；其r1预算尚未开始：30调用/45分钟、compile2、case14，原edges同失败场景仅余1次，r0工具44/45、compile2/2、case20/20及r0 FAIL保留。仅该实际续接ID错误才按文件恢复tester并映射，不创建额外测试视角。测试新时间窗从实际派发开始，不能把r0窗口延长。

T10 ready_for_test后才首次新建一个与开发独立的综合测试者，沿原尚未消费预算45调用/60分钟、compile2、case20、小case300s/full600s。开发faults累计3/3不因进入测试而清零；测试者首次独立执行按原独立检查预算记账，不冒称开发第4次或复用开发PASS作独立验收。两者每任务每轮一份integrated报告，绑定新manifest，事实不全或实际失败如实FAIL/blocked。

若原计划门槛在上述现存验收预算内无法覆盖，须事前把精确缺项交原规划，不自动增加。没有新manifest/真实停止声明或implementation仍缺项就不能先派tester。所有PASS/FAIL/blocked回原规划，主不解释报告、修根因或自动再加一轮。父硬件任务/G2/3/4不升级。本次不再发送重复权限问题。
