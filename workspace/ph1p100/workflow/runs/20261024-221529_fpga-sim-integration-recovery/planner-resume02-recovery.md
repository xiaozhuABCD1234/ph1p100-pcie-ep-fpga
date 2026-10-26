# 原恢复仿真续接02：最终组合DUT（2026-10-25）

本run四正式包/上限4、两级、batch1，禁止第五包。T08、descriptor-fix、abort-cdc-fix均round0独立综合PASS，实际修复均0；原 `T10.a1-recovery-sim` 仍须本次changed组合输入的首轮独立验收，不能以依赖包报告直接升PASS。

## 已核验修复与唯一输入

第四包报告 `test-reports/T10.a1-abort-cdc-fix-r0-integrated.md`、manifest SHA=`db84411dfdcf979b1fc5f6a25e11812f90f0834896a8b76787b85cd434fa5dcd`、index SHA=`804bd7139e11337f537100bc1f0f573ea302cc14ffe7959430aae3168af606ae`。独立20项矩阵在两异步比例全部通过、88包严格核对（80恢复输入），每项4good均恢复4包，最大10,042 A1周期；原top有效反例、17checker反例、764保护项零漂移。单top窄差异和7项保留SHA已审。其G0/G1通过不外推STA/硬件/性能。

`recovery-dut-binding-resume02.json` 固定本次8RTL：top=`5d0f9a001747168db39e07a10cfa417a25be797ae4013d07c3990d623310772a`；exporter=`0f3ae49ee19cc69348024e4fbe25cd3766dfec2cd8435f34f2b117bf313ba097`；其余6项原SHA。两项相对原始DUT改变，仅top相对resume01改变。以实际SHA推导，不依赖index缺省布尔字段。所有8项只读，不从活动树取同名文件。

## 续接与历史计数

续真实原开发 `/root/fpga_dev_recovery_221529` 到 `T10.a1-recovery-sim/resume02/**`；旧根r0、resume01、所有依赖包候选/证据和8RTL禁止修改。保留旧blocked及两个稳定problem：descriptor-index澄清机会1、crop-abort-cdc-loss机会0，两个修正输入条件均已满足。原任务累计42calls、2compile、3clean、3fault（raw reset/encoded reset/bad各1）、载入前失败1；实际验收后实现修复0、尚无tester。续接02是新输入后首次验收准备，不重置历史/新造任务。

## 原包工作与可复用资产

继续原包四语义步骤，全部为测试代码/模型/runner、证据和冻结，不允许再改DUT。优先从已冻结第四包 `tb_recovery.sv`、`ddr_recovery_model.sv`、`check_recovery.py`、`run_abort.py`、`run_final_matrix.py` 复制到resume02，按本绑定和独占输出路径改接；先记录复制前后SHA和仅路径/适配差异。可读旧resume01定位失败，不能复用其成功日志。当前新候选case必须全部真实重新执行。

复跑第四包已经验证的20项矩阵，即两异步比例（cam14ns/A1 5.333ns，cam3.7ns/A1 5.333ns；相位分别1.7/0.91ns）的 clean、clean32、raw-midwrite-reset、encoded-midwrite-reset、bad-frame、overflow、full-abort、pending-reset、sof-abort、last-skid-abort。后四是已完成修复的受影响边界回归，不另建工作包。原top负对照可再以同8模块仅还原top编译运行一次，必须命中目标断言，不能编译失败充反例；checker继续拒绝旧epoch/删除inject_hit/CRC/截断/重复/尾垃圾等有效变异。

保持W8/H2 FIFO_AW2；clean32和中写reset W32/H2 FIFO_AW4；UART_DIV4、PREP/PRED1、HB_DIV0、ROI(4,2)、CAM_W=W+8/H8。RAW80B在真实slot store为4个DDR字（每字有效20B），压缩流长度按实际测量，不预设91B作为成功条件。两类中写reset必须外部RAW/CMP AW/W已接受且相应完整帧未发布，不能把内部计数或估计时刻当命中。

每故障最多4good输入、至少2个正确完整恢复、最后good FE后≤1,000,000 A1周期；实际统计必须分别列先前合法前缀与故障后恢复，不能把合法前缀误当坏帧发布或当恢复数。坏行/丢beat/abort-SOF碰撞帧必须不发布；真实FIFO满/拒收和drop/error计数命中，pending/holding/目的RAW槽释放真实观察。每包严格源字节、zlib EOF及无unused/unconsumed、四CRC、零重复/旧epoch/尾垃圾。

DDR模型保留已接受的内存与延迟响应，DUT reset不可暗清模型。第四包两中写reset实际pending/rvalid=0，因此额外“reset瞬间仍有旧AR未完成”边界尚未覆盖；本次不添加新目标，若同样未命中应在最终报告明确保留该限制，不声称完整所有复位交错已证明。

functional=真实组合8RTL全部规定矩阵和独立字节/反例；engineering=编译精化/窄测试差异、时钟/reset/CDC/stall观测、实际超时和manifest绑定/前后漂移0；system=模型限制、候选隔离和真实故障恢复边界。必要G0/G1；G2 not_run，G3/4/5本离线包N/A，TD/综合/route/bit/CWC/download/Flash/生产写回=0。编译告警逐项说明，不能只以exit0/CASE_PASS判结果。

## 预算与独立验收

开发本次≤45calls/60分钟、全量compile≤2（当前DUT与可选原top负对照，或有新证据的编译纠正；累计历史2+本次≤2，即≤4）；每冻结case首次+最多一次新证据纠正，不盲重跑。读取/搜索实际60s，单编译/仿真实际300s+TB watchdog；新问题最多3搜索轮，连续2轮无进展或缺工具/权限/额度直接blocked。历史命令/失败次数保留。

本次唯一冻结 `resume02/manifest-resume02.json`，包含DUT binding/SHA、全部测试输入/复制差异/参数/工具/真实命令/前后保护audit及累计ledger；停止修改且active_commands=0才ready_for_test。随后一个新独立综合测试者（原恢复包从未派tester），本次≤45calls/60分钟，两个compile上限，完整独立重建/20项重跑、不同判据及有效反例，唯一 `test-reports/T10.a1-recovery-sim-r0-integrated.md`。测试预算比原40calls/45分钟的有限覆盖仅用于20项受影响CDC边界矩阵、源/槽独立观测，无新增角色/包/硬件权限。

同候选PASS回原规划四包收束；真实未blocked FAIL才续原开发/该tester，round1—3最多3轮实际修复，仅测试允许写域。又需额外RTL或第五包时保留具体证据交原规划在4包边界内收束，不自造包/改ID/新run绕限，不询问已授权的同类隔离动作。
