# 两包描述符实现闭合：有界实际修改派发

实际根 `D:/fpga/ph1p100`；run不变；BATCH_SIZE1；仍只有T08.dual-local-closure与T10.dual-aplus-scheduler两个正式包。原开发分别 `/root/fpga_dev_dual_local_180900`、`/root/fpga_dev_dual_scheduler_180900`，双方已结束静态收尾且active_commands=0，分别续原角色，不跨任务复用。

## 决策与轮次

规划读取两包static-closeout01的结果、manifest/source-map、计数、retest与静态反例，并核对对应实际源码。两反例均由真实可达的合法握手/状态转换构成：T08 mode2在空闲边缘同时收到切mode1和pub，会按旧mode建立offer又按新mode本地读回释放，之后转回mode2可出现已释放身份；T10组合优先级cmp_sel会在slot1描述符stall期间因slot0被ACK回收再完成而切到slot0。两者违反本轮已冻结的所有权/ready-valid合同，属于原任务必要实现修正，不是新增功能、硬件、协议或重复许可事项。

本文件是**新的真实RTL修正派发**，不是静态窗口的延长或借静态改代码。旧10次/15分钟静态窗口已结束，0实验增量保留；旧实验窗口、超用和累计计数不回写。预算只为这两个新定位实现缺陷及其受影响验证有限分配，低于原每次派发上限；没有为旧同失败命令增加重试额度。

T08：保留r0 integrated FAIL、已做实际实现修复round1。当前仍未有r1 integrated，新增模式修正是r1提交前的第二段实现闭合，不伪造r1 FAIL或r2验收；后续仍由原tester出r1 integrated。T10：尚无独立integrated round0，本次为提交首次验收前的实现闭合，不记验收后round1，不声称发生独立失败。后续首次tester仍round0。两者最多3轮实际验收修复的历史规则不被此处改写。

## T08：模式/发布/offer生命周期（五步）

输入：`T08.dual-local-closure/r1/static-closeout01/{manifest-r1.json,mode-publication-risk.md,result-r1.md,retest-r1.json,execution-accounting.json}`、原r0报告和r1源码/13项局部结果。只写 `T08.dual-local-closure/r1/mode-fix02/**`；此前所有r0/r1源码、静态交接/manifest/结果均只读。

1. 验证静态manifest与基准SHA，将需修改模块/环境/新TB放本新目录，未变文件可直接只读引用，建立准确源映射。
2. 修改实际dual_local_closure所有权裁决：切模式要求本拍也没有A/B新pub，且held/sent/offer/pending/outstanding/reader状态满足真正空闲；新pub与mode请求同拍时保留原模式和pub，拒绝/计数该次mode请求，不丢合法pub。离开mode2后不保留能重新露出的旧offer；返回mode2时只呈现实际held且未移交的新身份。原F01的stall字段保持、同拍take/refill和F02的ext_take排斥释放必须继续成立。不得靠禁用模式切换、屏蔽pub或解除槽保护规避。
3. 新建真实合法接口驱动反例/矩阵，覆盖A/B、两slot、2→1和1→2与pub同拍、两路同拍pub、无pub空闲切换、busy/held/offer/AR/R在途拒切、消费/释放后再切而无phantom/重复描述符。旧源码应由同一合同检查暴露反例，修正源码必须通过；只允许隔离旧fixture，不修改原证据。禁止force held/cs状态来替代可达刺激。
4. 在新输入上局部验证修正矩阵、原edges/同拍AR-release、真实read-overlap、正常/饱和、drain/LOCK/reset、默认关闭与B释放负对照。可用一个有限矩阵进程组合相邻握手检查；不得重命名旧失败case绕次数。旧I2C特定引脚错误类可提复用，最终由原tester绑定新manifest决定。
5. 新冻结 `mode-fix02/manifest-mode-fix02.json`、结果/命令/输入SHA/影响/retest/复用提案/lessons/实际本次与历史计数；结束活动并停改才ready_for_test，否则真实blocked。不能把旧13个局部pass直接拼作新模块全通过。

开发本次≤30实际工具调用/60分钟、compile≤2、case进程≤12，定向矩阵与受影响检查优先。tester原r1尚未开始的30调用/45分钟、compile2、case14不变；建议14进程覆盖：新模式矩阵1、原edges1、所有camera/slot/status矩阵1、overlap1、normal1、case10–15共6、contract1、legacy1、B释放mutant1。总14；具体组合由原tester按新manifest确定，不得遗漏门槛或超过预算。

## T10：CMP输出描述符stall保持（五步）

输入：`T10.dual-aplus-scheduler/static-closeout01/{manifest-resume01.json,source-map.json,result-resume01.md,retest.json,execution-accounting.json}`及当前真实三份DUT/已有捕获。只写 `T10.dual-aplus-scheduler/cmp-stall-fix01/**`，不得改先前candidate/静态冻结/脚本/证据。

1. 核对冻结三DUT，复制/引用到新唯一源闭包，仅新scheduler overlay允许行为修改；core/frame SHA必须继续分别6797db05…35bb/c8b24775…a65b。
2. 实现CMP呈现身份寿命：cmp_valid拉起后，所有cmp_*身份/slot/长度/CRC/prep/pred在cmp_ready=0时保持到握手；其他CMP槽ACK、再分配、真实编码完成不能改变当前offer。握手只将实际呈现slot置READING，另一READY正确保留；同拍commit/take/refill和reset取消符合原合同，不增加完整帧缓存或修改codec/RAW/CRC。
3. 用真实core与native DDR模型、合法CMP ACK形成slot0 READING、slot1 READY且stall，ACK0后编码第三帧至slot0 READY；检查stall身份不变、之后两个完成的source和实际字节对应且单次导出。覆盖相反可达顺序、同拍ACK/commit/take、两个CMP持有造成背压、ACK错身份拒绝。旧实际源码须由同一检查暴露该反例；不可force内部cs或用stub编码器冒充真实完成。
4. 局部仅跑该新增名义握手场景的旧反例/修正矩阵、小参数正常多帧、默认1920x1080 A/B双帧内容/metadata及有效输出身份或跨word负对照，严格zlib/逆变换/长度CRC对应新源。**本开发者不得再跑原faults suite、其改名等价或重新注入原完整故障序列**；已用3/3保持，不增加第4次。此新增CMP名义反压/ACK场景是不同根因与不同刺激，独立记账；不得夹带旧故障重试。
5. 停改/活动结束，新冻结 `cmp-stall-fix01/manifest-cmp-stall-fix01.json`、结果/影响/retest/源映射/复用提案/lessons/实际本次历史计数。若仍有未实现合同或来源不清，blocked，不交半实现给tester；不能声称独立PASS。

开发本次≤30工具调用/60分钟、compile≤2、case进程≤5，建议旧CMP反例1、修正矩阵1、小参数名义多帧1、默认full AB1、有效负对照1。编译列表可包含隔离重命名旧fixture与新DUT，并独占工作库；不能编译/运行旧目录库覆盖历史。核/变换/DDR/恢复等不变项证据只作复用提案，不由开发把历史pass绑定到新scheduler。

之后仍是首次新建**一个**独立综合测试者，原未用45调用/60分钟、compile2/case20、小case300s/full600s不变。独立检查完整原清单加CMP新反例，fresh正常/odd/prep、公平/满CMP/接口stall、容量/phase、错误身份及AXI错误/drain/LOCK/reset、全尺寸严格还原和有效负对照。必要原故障类由独立tester按其原计划首次覆盖，另记独立验收次数；这不重置或增加原开发的faults3/3，不把开发第4次改名成测试。若原预算无法覆盖事先交规划，不自动增额。

## 共同边界、停止与历史账

开发窗口从本派发实际续接计60分钟、由角色开工登记准确绝对截止；此新真实实现窗口不修改旧窗口时间或合规性。读搜60s、编译/小case/局部静态300s，只有T10 full600s；真实进程timeout与cycle watchdog，安全终止仅本角色拥有进程。单问题最多3轮读取，同失败命令原计数累计最多首次+1次有新证据纠正重试、2次无进展或任一上限即停。T08原tester_edges已失败1次，原tester修正输入只剩1次；开发自己的命令史独立保留。

T08已知累计开发：calls125（含r0超用101、r1前静态16、静态8）、compile6、case32；本次加本次实际量，最大calls155/compile8/case44，不说旧125符合旧预算。T10历史完整calls未知，保留原37、恢复期已知13native+8wrapper、静态9及unknown总计，不填0；compile4、case11、faults3；本次最多追加compile2/新名义case5，账为compile最多6/case最多16，原faults仍3，旧实验cap4/4耗尽的历史不追认。新预算来自原范围必要真实实现闭合派发，不是旧静态或旧故障命令重试。

双方静态问题的PERMISSION_MISSING/INPUT_CONFLICT只标当时静态窗口不允许改实现；不意味着人类尚未授权原范围必要修复。本次明确切换到真实修改派发，保留两个稳定problem_id，不用新ID抹问题：T08 `T08.dual-local-closure:PERMISSION_MISSING:mode-publication-stale-offer`；T10 `T10.dual-aplus-scheduler:INPUT_CONFLICT:cmp-descriptor-stall`。补充机会不增加/不重置，不把实现轮当格式机会。

禁止TD/硬件/盘符/COM/RK/位流/下载/Flash/外部消息/Git/批量删除；不改共享协议/几何/频率、上板候选、对方任务目录。G0/G1必要，G2/3/4仍not_run/awaiting_hardware；开发完成不等于独立验收，父任务不置done。

各开发一旦ready或blocked都回原规划，传真实manifest/结果/stop flags/retest及新旧账；主不直接解释技术报告或自动增实验。原规划核对后再派相应独立验收，T08原tester优先、T10首次新tester。只有实际角色调用报ID失效才按文件恢复映射，禁止预防性新建和借换ID重置余额。不得在本次之前的静态窗口偷改源或倒填此次开始时间。
