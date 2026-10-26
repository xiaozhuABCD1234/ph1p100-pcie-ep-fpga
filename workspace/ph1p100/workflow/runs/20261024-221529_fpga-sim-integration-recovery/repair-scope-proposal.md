# 阻塞处理与有界修复提案（待用户确认，不执行）

日期2026-10-25，原run/原规划继续。`user-feedback-01-continue.md` 原话“接着做”用于恢复额度中断后的原规划处理，未将先前“固定八项DUT RTL只读”的恢复仿真包改为RTL开发。本文件把必要变化具体化供确认；不是补丁、不解除任何保护、不启动新角色。

## 已核对的缺陷与影响

`T10.a1-recovery-sim/defect-evidence.json`：clean输入4个不同good帧，cap/raw_pub/enc=4，完整exported=2，无drop/geom/error/duplicate；前两包各73B，严格zlib/四CRC/原像素正确。第三包offset146开始，offset151 flags为X，后续ID/长度/CRC未知。实际clean仅一次，exit0/TB CASE_PASS被严格checker拒绝。

固定 `inputs/a1-r5/src/a1_uart_export.v` 第88行只有 `dq[0:1]` 两项，第89行两位dq_wr/dq_rd，第192/220行按2bit加1递增，第三次下标2越界。源码与第三包症状直接吻合；尚无独立综合测试者验收，不将开发定位写成独立PASS或完整根因已穷尽。

同一队列还存在必须纳入修复验证的邻接情况：dq_cnt在入队和出队分支分别被非阻塞赋值（193/221行），同拍发生时后赋值覆盖前赋值。该项目前是静态发现的潜在计数问题，不伪称已有动态复现；不扩到编码核心/DDR布局/吞吐。

## 拟新增第三正式包

ID=`T10.a1-uart-descriptor-fix`，状态blocked_scope_authorization；计入本run正式包，合计3/4，不重命名T10.a1-recovery-sim、不清零任何计数。一个主要结果：可循环、计数一致的两项描述符队列修正候选。两级、四语义步骤、batch1：

1. 只在本run新包目录建立a1_uart_export.v候选副本和最小差异；dq_wr/dq_rd改为1bit或显式模2回绕，dq_cnt继续2bit。索引只在各自真正接受事件时变化；reset全部归零。
2. dq_cnt集中用accepted_push/pop二事件更新：10加1、01减1、00/11保持。pop使用原estate==E_IDLE且旧count非0；push使用旧count<2。保持现有满队列拒入并st_err加1，包括full+pop同拍仍拒本次新描述符；不擅自改变对外容量/错误/所有权策略。
3. 真实模块测试空/单项/满、同拍push/pop、full+pop、reset排空；至少12个不同ID顺序导出跨多次回绕，逐字节/无X、四CRC、严格zlib/无尾垃圾；旧RTL在第三描述符用例必须被拒；独立完整camera_a1_uart_top clean至少4帧全部正确，不只检查前两帧。
4. 形成唯一manifest、差异和适用G2证据，停止修改，再由一个新独立综合测试者验收；通过后只把修正文件和其余7项原SHA组为新不可变DUT输入，交原规划恢复原恢复仿真任务。

### 三维、G层与有限执行预算（确认后才能派发）

functional：上述真实队列正反向/边界、12描述符和4帧完整管道；engineering：G0/G1输入/编译/真实模块、适用单模块G2最终route STA/CDC/资源绑定；system：全程隔离副本、格式/CRC/时钟/生产/板候选保护。

G2拟用可综合单模块wrapper把clk/uart_clk接同一187.5MHz（真实模块现有合同），W1920/H1080/UART_DIV434/HB_DIV0；匹配PH1P100SBG484-3，最终routed setup/hold WNS>=0、TNS=0、无未说明时钟/CDC例外、资源在器件内。约束与环境绑定候选，不用旧G2拼新RTL。此G2只证明修正导出模块，不证明完整生产系统迁入；整机G2仍另轮。禁止为PASS降频或删门槛。

开发每次≤60调用/90分钟，综合测试≤40调用/60分钟；读取/搜索60s、单编译/仿真300s、TD会话实际1800s；TD最多首次+一次有新证据纠正（最多2会话），bitgen/CWC/download/Flash=0。无TD可用独占本地进程控制则blocked，不干预别人进程/GUI/盘符。新包每任务round0，最多三轮实际修复；原恢复包旧次数仍原样保留。

允许写域仅 `OUTPUT_DIR/T10.a1-uart-descriptor-fix/**`；测试只写对应test-reports。inputs/、原8项RTL、生产树、旧run、板候选、约束/IP/共享DB均只读。不能在修复后自动写回生产。

## 原恢复包的具体恢复条件

新包得到独立PASS及修正DUT manifest后，续真实原开发 `/root/fpga_dev_recovery_221529`，保留原task_id/round0尚未综合验收/实际修复0/problem机会0和历史编译1/clean实跑1/启动失败1。新输入身份必须changed，旧clean和前两帧不能拼为新PASS；此前搜索3轮属于旧证据，换输入后仅新差异问题按有界规则，不盲重试原缺陷。

本规划将中写注入定义明确为“外部至少一笔真实AW/W接受、尚未完整发布”。W8/H2 RAW20B只有一个DDR字，不具备此前置条件；恢复时给两类reset采用W32/H2（RAW80B，至少3个256bit字），独立clean校准同几何，非压缩性不同图案确保压缩流也跨多个DDR字，并由注入命中断言检查而不是估计时刻。其余baseline/坏帧/overflow可保持W8/H2。生产默认几何/协议不改。

五case全部重编译/实跑、严格zlib/四CRC/epoch/无重复/无尾垃圾/计数和真实overflow、≤4good且≥2完整正确恢复、最后good FE后≤1,000,000 clk_a1门槛不变。DDR模型保留已接受旧响应；reset不能替模型清队列。tester尚未建立，开发新候选ready_for_test后才新派一个。

## 用户待确认的唯一范围变化

是否允许上述新第三包，仅在本run隔离副本修复 `a1_uart_export.v` 的描述符队列、取得独立G0/G1/单模块G2后重新冻结，续跑原恢复仿真？确认不包含生产迁入、板卡、下载/Flash、吞吐优化、外部消息或自动监控。用户拒绝则保留当前1包PASS/1包blocked，停止。
