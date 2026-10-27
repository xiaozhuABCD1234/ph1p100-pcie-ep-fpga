# 原 T10.a1-recovery-sim 续接01开发结果

状态 **blocked**，不是 ready_for_test。runtime=Codex，原开发 `/root/fpga_dev_recovery_221529`，task_id 不变，首份综合验收仍 round0，实际实现修复轮0。当前唯一调度 `dispatch-recovery-resume01.json`、状态增补 `planner-resume01-recovery.md` 和 DUT 选择 `recovery-dut-binding-resume01.json` 均绑定于新 manifest。旧 r0、原 blocked manifest、修复 PASS 候选与全部八项 DUT 未修改。

## 真实重跑结果

本次一次全量 compile，累计原任务两次，未使用本派发第二次 compile。直接引用 binding 指定八项 RTL：exporter SHA 为 `0f3ae49ee19cc69348024e4fbe25cd3766dfec2cd8435f34f2b117bf313ba097`，其余七项沿原冻结身份，未编译原坏 exporter。独占工作库为本目录 lib；ModelSim Intel FPGA Edition10.5b、Python3.11.5。vlog Errors0 / Warnings0；精化保留固定 top 中 u_cmp_store 漏接 st_read_words/st_dup_words 的三条已说明观察输出告警，未屏蔽，不影响控制/数据输入。

| 场景 | 实际参数 | 完整正确包 | 结果 |
|---|---|---:|---|
| clean | W8/H2、FIFO_AW2 | 4/4，292字节 | 局部PASS |
| clean32 | W32/H2、FIFO_AW4 | 4/4，540字节 | 局部PASS |
| raw-midwrite-reset | W32/H2、FIFO_AW4 | 新epoch4/4，540字节 | 局部PASS |
| encoded-midwrite-reset | W32/H2、FIFO_AW4 | 新epoch4/4，540字节 | 局部PASS |
| bad-frame | W8/H2、FIFO_AW2 | 0 | 实际FAIL，恢复门槛未满足 |
| overflow | W8/H2、FIFO_AW2准备代码 | — | not_run，发现第二处受保护RTL缺陷后停止 |

所有场景各单独进程；五次实际仿真各一次，无重试；退出码均0，但坏帧的 Fatal/严格语义失败明确拒绝，不能凭exit0判通过。实际耗时依次3.735、4.969、3.250、3.860、22.641秒，均由 subprocess 300秒控制和TB cycle watchdog同时约束；无超时终止。命令的 argv/cwd/PID/退出码/时间分别保存在各目录 console.command.json，编译在 vlib/vlog.command.json。

两种 clean 全部四个不同源帧依序完整导出，拒绝了旧第三描述符越界行为，未复用 descriptor-fix 或旧 r0 的成功证据。CAM_W=W+8、CAM_H8、ROI(4,2)、H2、UART_DIV4、PREP/PRED1、HB_DIV0。W32 的 camera FIFO 深度16，W8 深度4；它们都是合法测试参数，不改变DUT源码或生产默认几何。W32 RAW为80B，RAW store每DDR字装4组即20B有效载荷，实际4个DDR字；压缩流实际91B，占3个DDR字。地址沿真实RAW_BASE0/CMP_BASE131072和固定slot布局，单位是256bit word。

RAW复位精确命中 cycle133：外部raw AW/W各已接受1笔，rawpub0、RAW写slot仍活动；编码复位命中 cycle1203：raw AW/W4笔、cmp AW/W1笔、enc0、CMP写slot仍活动。均在negedge采样已接受状态后复位，无估计FRAME_CYC。复位分别在cycle157/1227观察所有相关统计清零、四个slot释放；新epoch1种子1100..1103不同于故障前11/12。每个reset送4个good输入，全部4个完整正确导出，最终FE后10015周期完成，小于1,000,000界限。无重复读、旧epoch输出、未知字节或尾垃圾，严格zlib EOF/unused_data/unconsumed_tail、四CRC、独立源RAW逐字节均通过。RAW源正在复位期间的剩余半帧使释放后geom增加1，这是被丢弃的复位跨界输入；复位断言期计数清零与后续计数分别记录，没有要求复位后永久保持零。

DDR模型只以真实paired AW/W保存、AR接受时快照数据、延迟R并保持至握手，采用周期stall。DUT reset只门控新请求，内存与已接受响应完全保留。两次reset命中时pending/rvalid实际均0；因此本次证明了保留模型结构及不同epoch字节恢复，**没有**声称已覆盖“reset时仍有未完成旧AR”的额外触发条件。未运行内容不充覆盖。

## 第二处固定DUT缺陷

bad-frame在ROI首行刻意少最后一个camera group，真实crop产生短行错误，cycle128：`crop_abort=1`，但 `crop_valid=0`、FIFO的 `w_valid=0`、`w_ready=1`。不是FIFO满导致丢abort，abort令牌本身未被写使能。`camera_a1_uart_top.v` 第113/114附近将 w_valid 仅接 crop_valid，虽然 w_data 包含 crop_abort；crop的错误分支只设置out_abort，不设置out_valid。第169..174行的RAW abort处理只在FIFO真正读到e_abort时执行。实测 ABORT_FIFO_ACCEPT=0、RAW_ABORT=0。

故障观察cycle658已经有2个RAW group进入半帧，raw_active1、raw_wcnt2、slot0 WRITE、geom增加1、rawpub/enc/exp均0。后续四个good种子1000..1003已经全部送入；新的SOF因真实 `!raw_active` 前置条件被阻塞，FIFO后续满并拒绝11个crop beat。最终FE后完整等待1,000,000 A1周期，recovered/exported/enc/rawpub仍0；cycle1,050,979记录最终状态，明确 `Fatal: RECOVERY_BOUND_FAIL`。这不是cycle watchdog或实际300秒超时，也不应把检查器通用“fatal/watchdog”标签误读为watchdog实际触发。

精确证据是 `defect-evidence-resume01.json`、bad-frame下trace/stats/capture/console/result。原描述符问题的修正输入条件已满足；这是不同根因，稳定新problem为 `T10.a1-recovery-sim:SCOPE_CLARIFICATION:crop-abort-cdc-loss`。修复需要触及第二个受保护RTL，超出本resume的TB/model/checker写域；按dispatch立即停止，不force内部状态、不复位坏帧轮来掩盖失败、不放宽门槛、不重跑同输入、不继续overflow仿真。

## 负对照、保护与工程边界

三个检查器负对照实际运行并拒绝：CRC/zlib全部有效的clean旧源包冒充epoch1恢复；RAW reset证据inject_hit删除；encoded reset证据inject_hit删除。前者因源/epoch逐字节不匹配被拒，后两者因fault trigger absent被拒。见local-result.json。收集器因新增clean32后需要以case_id选择两个reset分支，已修正这一纯结果收集索引；该改动不改变任何实际编译、仿真或DUT输入。

108规划冻结输入、binding八DUT、原r0的35项产物及原manifest、修复manifest/index在本次各运行前后均哈希相同；见protection-before/after和各case result。仿真环境/TB/checker/runner/INI/do/工具/命令/所有产物都纳入新唯一manifest。所有读取/静态命令均带拥有的Job实际60秒控制；仿真/编译实际300秒控制；所有拥有的子进程均已wait结束，active_commands0。

本次仅resume01写入。无批量或单文件删除、无生产/TD/硬件/下载/Flash/共享盘符/他人进程操作，无代理派生。G0/G1整体未满足；G2=not_run，G3/G4/G5=N/A沿原规划，不提升父硬件任务。

## 历史账与恢复入口

原账保留：21工具调用、compile1、clean真实仿真1、设计载入前失败1、故障仿真0、实际修复0、规划澄清补充机会1。本次最终账在execution-ledger-resume01.json；本次compile1，新增clean两种几何各1、raw reset1、encoded reset1、bad-frame1、overflow0，启动失败0、重试0。原任务累计compile2；累计clean3（原W8旧DUT1、本次W8和W32各1），故障3；不把改DUT依赖包的修复算入本任务实现修复。

原规划应登记新的abort跨CDC丢失条件，准备授权范围内修正及新的不可变DUT绑定，再明确原任务恢复路径和计数。当前准确入口为 `dispatch-recovery-resume01.json`、本报告和新manifest。旧r0/纠正后DUT/本次失败证据全部保留；回退无需改变生产或板候选。Changed-input复测必须覆盖失败坏帧、未运行overflow和受影响两种clean/两种reset及负对照，由后续一个新综合测试者独立验收，不能拼不同DUT的PASS。
