# 既有授权澄清与第三包冻结（2026-10-25）

用户已明确要求两项仿真，并以 `user-feedback-01-continue.md` 的“接着做”授权必要、可逆的隔离修复。此前将继续限定为“只恢复规划”并再次请求确认不当；现撤销此等待状态。`question-recovery-dut-scope.md`、`dispatch-blocked-closeout.json` 和旧修复提案的“待批准/TD门槛”仅保留历史，由本文件及 `dispatch-dq-fix-r0.json` 取代，不再向用户提相同许可。

仍同run、1目标、3/4正式包、两级、batch1。T08原round0 PASS不变；T10.a1-recovery-sim仍保留fixed-r5缺陷blocked历史，等待修正输入；原开发仍 `/root/fpga_dev_recovery_221529`，tester尚无。原任务compile1/clean实跑1/载入前失败1、实际修复0保留。稳定problem ID不改；本次原规划权限澄清补充机会为**1**，不算实现修复，不重置其他账。

## T10.a1-uart-descriptor-fix（ready）

唯一结果：仿真副本中两项描述符队列循环和计数正确的修正RTL。新开发、一个新的独立综合测试者；本包round0首次验收，不复用其他任务角色。真实生产文件/原8项冻结RTL及已验候选继续只读。

四语义步骤：
1. 在 `OUTPUT_DIR/T10.a1-uart-descriptor-fix/` 新建副本，仅允许对 `candidate/a1_uart_export.v` 的dq索引/占用计数及直接相关reset/事件声明做最小差异。其余7项RTL沿 `inputs/a1-r5/src/` 的SHA直接引用。1bit读写索引（或显式模2）在真实接受事件回绕；dq_cnt保留2bit。
2. 将count集中按accepted_push/pop二事件更新：10加1、01减1、00/11不变。pop=旧estate IDLE且旧count非0，push=desc_push且旧count<2；满队列拒新描述符并st_err加1的策略保持，包括full+pop仍拒该次push。数据顺序/CRC/帧格式/DDR/时钟/UART握手及编码核不得改。
3. 真实导出模块测试空/单项/满、同拍push/pop、full+pop、queued reset/新epoch、至少12个不同ID跨多次回绕，逐字节/严格zlib/四CRC/无X/无重复/无尾垃圾；真实camera_a1_uart_top集成clean至少4帧全部完整正确。目标相邻count问题先用定向测试复现，不能仅凭静态推测扩改。旧RTL第三描述符反例和同拍事件反例应被目标断言拒绝，不能以编译失败充负对照。
4. 保存局部实际命令/参数/日志/差异，冻结唯一manifest及源映射，停止修改且active_commands=0后返回ready_for_test。该manifest提供修正文件与原7项SHA组成的完整待恢复DUT输入，不能覆盖原输入。

### 三维与G层

functional：上述真实DUT队列边界、多次回绕、reset/epoch、完整管道及有效反例全部实际运行，Errors0、明确PASS/mismatch0、严格包内容正确；不能只信TB计数/exit0。engineering：原7项SHA不变、唯一改动差异仅队列、同拍事件/位宽/reset静态审查、实际超时/独占库/工具绑定、manifest前后漂移0。system：副本隔离、原输入/生产/板候选/其他会话零写入，不改变对外协议或容量策略。

本包是原仿真目标的隔离RTL修复与回归，必要门槛G0/G1。**G2=not_run，TD/综合/route/bitgen/CWC/download/Flash=0**，与本轮原硬件权限保持一致。旧提案擅自加入的TD及单模块G2不执行。本PASS不证明修正RTL可上板或生产时序合格；将来生产迁入仍需完整真实G2/CDC/资源/候选绑定及硬件资格，不能拼旧结果。G3/G4/G5本仿真包N/A。

### 写域与有限预算

开发仅本包目录；测试仅 `test-reports/T10.a1-uart-descriptor-fix/**` 和 `<task_id>-r<round>-integrated.md`。不写原inputs/、生产/upstream/fpga/tools、旧run、docs junction、TD/板候选/共享盘符/其他工作树；无删除/消息/监控。

开发每派发≤45 calls/60分钟；独立测试≤40 calls/45分钟。读取/搜索实际60s，单编译/单case实际300s且TB watchdog；同失败命令首次+一次新证据纠正，搜索≤3轮，连续2轮无进展或缺工具/权限/额度即blocked。全量compile每派发≤2；每冻结case首次+一次必要纠正，不盲重试。round0后仅真实FAIL允许原开发/原tester最多3轮实际修复，不扩大队列修复写域。

## 修复通过后的原恢复包

返回本原规划，核独立PASS/manifest，再续真实原恢复开发；不是自动新建/改名恢复任务。原实际修复0、规划澄清机会1和全部历史命令计数保留；新输入标changed，旧前两帧不拼PASS。原T10已有60分钟/45calls开发、45分钟/40calls综合测试预算不变，首次综合仍round0。

中写定义冻结为外部真实AW/W至少一笔接受且未完整发布；两类reset用W32/H2（RAW80B，≥3个256bit字），先跑同几何clean；压缩输入选择非压缩性种子并断言多字前置条件。其余baseline/坏帧/overflow可W8/H2。生产默认几何不变。保留真实DDR延迟响应，不能模型reset偷偷清除旧请求。

原五case全部重新实跑：注入命中、epoch/严格zlib/四CRC/零重复/零尾、坏帧和真实overflow的计数/整帧拒绝、≤4good且≥2完整正确恢复、最后good FE后≤1,000,000 clk_a1。其后一个新综合测试者独立验收。若需修改第二个RTL或其他接口/硬件权限，先证据化交原规划，当前不预先扩到那些事项。
