# 一次只读恢复核查结论

授权入口 `user-feedback-readonly-recovery01.md`；本次只做一次原生角色快照、一次相关本机进程快照及本run必要回执/冻结哈希核对，没有向原角色追问进度、没有followup/spawn、没有仿真/编译/TD/硬件或源文件修改。完整机器证据为本目录 `native-role-snapshot.json`、`process-snapshot.json`、`audit.json`。

## 角色与活动证据

本次 `collaboration.list_agents` 仅列 `/root` 与 `/root/fpga_plan_dual_offline` running，三个原开发/测试ID未列为live。该事实不能替代followup_task实际ID错误；本次没有做探针式续接，也不擅自宣称永久失效或创建替代角色。一次针对本run实际harness/native命令行的本机快照匹配活动进程0。相关已记录native命令均有结束回执；这只能证明所记录命令结束及快照时未匹配活动，不能冒充作者的新停改声明/新manifest。

## T08已有成果与缺项

原r0 manifest的参与文件漂移0，r0独立FAIL仍有效且保留。r1目录已有真实修复源码、compiled-source快照、2次compile及13个case结束回执；13个case-result都声明成功，包含原edges、矩阵、真实read-overlap、受影响case0/10–15、contract、legacy、B-release误送A变异拒绝。当前r1源与实际compiled-source快照漂移0。overlap-result记录每路3个新SOF和每路1个其他槽pub位于实际AR至末R窗口，并有后续6对good的开发证据。

这些均为开发局部结果，不是r1独立验收。r1没有manifest-r1.json、最终预算/影响/retest/交接文件及作者新停止声明。原freeze_r1.py仍有21:02:49绝对截止断言，现已超时；本次不得删改该保护、回填更早时间或把规划审计快照冒充作者冻结。

历史调用账已在r1/historical-execution-accounting.json恢复并披露：开发r0外层40exec+1wait+内部60native，保守合计101，超过原60上限；原产物曾漏记。保留这一历史不合规，不能靠改计数口径/新角色/新manifest消除。r1当前完整工具计数仍缺作者最终回执，不能填0。已知r1 compile2/3、case13/14；这些计数余额不意味着已过绝对截止后仍可实验。

## T10已有成果与缺项

恢复目录的authorisation和commands.jsonl表明新增compile1、case2已实际结束：第三次faults在19:01完成、有metadata/events及checker文件；W1920/H1080的A/B双帧在19:08:47完成，TB_DONE cmp2/rel2、Errors0/Warnings0，有实际码流与checker文件。faults累计3/3已经用完，不能追加第4次；compile累计4/4，case累计11/20。不得仍按恢复前的faults2/compile3/case9计账。

但原development-state/result-r0/recovery仍是18:37恢复前文本；当前原manifest-r0有8项参与文件哈希不符，没有新manifest-resume01.json或最终预算/停止/影响/未测项回执。旧manifest不能绑定新执行结果，新结果不能自动推成G0/G1或独立PASS。原开发19:55:19截止已过，剩余case名义余额不授予新执行时窗；完整calls累计未收齐，未知不编造。任何未完成正常回归/负对照/身份覆盖应由静态交接如实列明，不能仅凭两项结束回执认定全部完成。

## 可机械恢复条件与最小请求

两包都有可复用的实际产物，当前首先缺的是**作者静态收尾和新唯一manifest**，而不是再跑一次已有场景。当前授权是“一次只读恢复核查”，未延长开发绝对截止；规划不能直接把已过期窗口解释成可继续写冻结/报告的余量，也不能创建替代原角色。因此当前blocked/needs_user_input，停止空等，问题见question-static-closeout01.md。

准备的最小有限动作：用户明确允许每包一次仅静态收尾窗口（每包最多10次实际工具调用、15分钟，独立记账并保留旧账），只整理现有回执/源码哈希/局部结果/不足、生成新冻结及停止声明/回传，不改RTL/TB、不运行任何仿真/编译/构建/下载，不调整faults3和compile4等实验累计上限。先向各原开发派具体收尾任务；仅当该次真实工作调用原生报告ID失效时，才按文件恢复静态角色、登记新旧ID，不能预防性替换。原唯一tester同理，不假称resume。

静态收尾不能强制ready_for_test：若作者无法证明必要局部检查完整，或不能验证自身没有未结束活动，须冻结blocked回执和准确未测清单。只有唯一manifest/停止声明及必要输入完整后，才使用各任务原先尚未开始的相应独立验收预算，不新增其上限；否则将真实缺口交用户，不让tester接管未完成开发。T08已完成实际代码修复1，但r1独立验收未开始；T10实际验收修复轮仍0。任务板和父硬件状态不升级，G2/3/4仍未验。

本次审计仅保存静态证据和决定，不更新实验预算、不抹历史错误、不更改候选。不得再次轮询角色/进程以替代用户答复或实际回传。
