# OpenCode b9 静默问题审查（2026-10-25）

结论：b9 确有状态包与描述符出队互锁，已对未修改的真实 exporter 做最小离线复现；同时仍包含描述符队列越界和同拍计数覆盖问题。优先修这几处并验证帧间仲裁。当前板上是否恰好处于此互锁，尚无寄存器/波形实证。帧内强插 177 B 状态包不是本问题的首选方案。

## 输入与验证范围

- 审查候选：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b9-rawstore/r0/`。
- 原 exporter SHA256：`dae0d47fc791fcc8993ccc7efc97c10dfef139cc684404e7a073689372561312`。
- 磁盘 bit SHA256：`950b6e4a867cf1aa87d11c4f084607f4254a82d335f5ed10891dcf74b66a5a06`；磁盘校验不等同于读回确认板上身份。
- 本次只读工程并新增本审查目录的 TB、运行脚本、报告和仿真产物。未改 b9 源码/manifest/bit，未访问 COM/JTAG，未综合、下载或写 Flash。
- 两个只读审查代理分别核对 exporter/协议与 DDR/覆盖。DeepSeek 仅整理所给的少量日志事实；代码判断、仿真和结论由 Codex 验证。

## 已确认问题

### 1. 状态包/帧队列互锁

`changed-src/a1_uart_export.v`：

- L299：到期置 `sts_want=1`。
- L302–303：发状态要求 `estate=E_IDLE` 且 `dq_cnt=0`。
- L335：出队发帧要求 `dq_cnt!=0` 且 `!sts_want`。

因此 `E_IDLE / S_IDLE / sts_want=1 / dq_cnt>0` 无法发状态，也无法取下一帧。新 tick 仍只维持 pending。第一帧可以已经完成，UART 本身也可以完全空闲。

最小复现通过正常输入送两帧（每帧 1 B 载荷，44 B 头），在第一帧发送期间让状态定时到期；缩短分频仅用于加速，未强制或修改 DUT 内部状态。实际结果：

```text
sts_div=64 exported=1 errors=0 estate=0 sstate=0 sts_want=1 dq_cnt=1 tx_busy=0 bytes=45 later_bytes=45
REPRO_CONFIRMED unchanged_b9_status_queue_deadlock
sts_div=0 exported=2 errors=0 estate=0 sstate=0 sts_want=0 dq_cnt=0 tx_busy=0 bytes=90 later_bytes=90
CONTROL_CONFIRMED same_two_frames_complete_without_status
```

第一种情形在额外观察的 3,000 个时钟中零进展；仅关闭状态功能的对照完成两帧。完整来源和日志见 `results.json`、`sim_sts_64.log`、`sim_sts_0.log`。这证明代码缺陷及可达性，不证明真实 DDR/板级全部正确，也不代替当前板上状态观测。

修法：在帧边界统一仲裁 `status_due = sts_tick || sts_want`。状态可以在描述符队列非空时获得优先权；有状态获准时禁止帧出队。保持最后一个已装入 UART 的字节发送完成后再交接，不打断 UART 字节。不能只删 L303 的队列为空条件，否则 tick 当拍 `sts_want` 仍是旧值，两个状态机可能同时启动。实际 accepted-pop 必须与统一仲裁一致，不能另按旧状态算计数。

### 2. 两项描述符队列缺陷仍在 b9

- L138 数组为 `dq[0:1]`，L139 指针 2 位，L279/L344 自增；第三次访问使用下标 2，超出数组。
- L280 和 L345 在同一 always 中分别给 `dq_cnt` 非阻塞赋值。同拍 push/pop 时后面的减法覆盖加法，计数不能保持。

应采用 1 位环绕指针，按真正 accepted-push/pop 集中更新计数，并明确满队列同拍出入的策略。此前独立通过的 `20261024-221529_fpga-sim-integration-recovery/T10.a1-uart-descriptor-fix/candidate/a1_uart_export.v` 提供该局部修复依据，但它与 b9 的状态 v3 扩展不同，不能整文件盲目覆盖。

### 3. 满尺寸默认地址布局重叠

根复核 `camera_a1_uart_top.v` L31–43、L112–115、L412–414、L482–483 及 `a1_ddr_slot_store.v` L150/L160 后确认：板顶未覆盖默认 W/H/BASE 参数，每个 RAW 槽占 129,600 个 256-bit word，CMP_BASE 却为 131,072。以下为 word 地址，非字节地址：

| 槽 | 起始 | 结束（含） |
|---|---:|---:|
| RAW0 | 0 | 129599 |
| RAW1 | 129600 | 259199 |
| CMP0 | 131072 | 212156 |
| CMP1 | 212157 | 293241 |

RAW1 与两个 CMP 槽重叠。这是明确的多槽数据完整性缺陷，不足以证明本次 UART 静默就是它造成。应在再上板前给 RAW/CMP 四槽分配互不相交的完整空间，核对真实 DDR 地址单位/容量，并加 elaboration 或仿真区间断言及双槽并发读写用例。不能直接用小几何无重叠测试替代。

### 其他待验证缺口

- b9 FIFO 拒收像素时仅递增 `fifo_ovf_cnt`（top L273–283），没有对该帧产生新的 loss-abort；LAST 丢失可能留下未关闭 writer。L397 在 LAST 尚在 skid 时即清 raw_active，也应纳入 abort/LAST 同拍与背压用例。上一轮独立修复的 holding/loss/pending 与 abort 优先逻辑尚未等价移植。
- bridge L154–167 将 `wf_pop` 寄存后同时返回 W_IDLE，下一拍可能在 FIFO 实际消费前根据旧 `wf_rvalid` 再启动。需加“单个写入后停输入”和 AW/W 独立背压的真实 bridge 用例，断言外部写握手次数/地址/数据保持。现有 TB 不应只数 store 端提交。
- bridge 的 `ar_pending` 等待 R 握手，无丢响应超时出口；复位后响应 FIFO 又直接接 `paxi_rvalid`（L110–119）。需验证旧 AR/R 在业务复位后如何排空或隔离；不能直接加清 busy 的超时，把迟到响应误交新会话。本审查未对这几条跑动态复现，勿标成已在板上证实的原因。

## 对截图结论的修正

- `p2_a1_board_top.v` L417–419 的 LED0 是不受 `a1_rst_n` 复位的自由计数器位：闪烁说明该时钟有活动，不能证明 A1 业务复位已释放。
- L420 的 LED1 仅表示累计 `exported!=0`；它不是接收端确认，也不证明目前仍在导出。
- L421–424 的 LED2 是 `errors/raw_drop/cmp_drop/geom_err` 的或，不能只凭灯判定 `errors!=0`。
- L425 的 LED3 仅表示累计 `cap_frames!=0`。实际亮灭还需结合板级极性。
- 已有 `captures_b9b/com8_150s.bin` 是 26,550 B，150 个 177 B v3 包，解析 XOR 全对；所以早期“下载后一直无状态包”的结论已过时。该时段 `cap_frames/raw_pub/enc_frames/exported=0`，与之后 LED 情况不能混为同一状态。
- 最新 `captures_pwr2/com8_60s.bin` 确为 0 B。它证明该采集窗口静默，无法单独区分逻辑互锁、业务复位或物理链路问题。

## 为什么不直接帧内强插

现协议是 44 B 头后紧跟恰好 `stream_len` 字节载荷。`board/decode_frame.py` 按此截取并校验 CRC、解压。插入 177 B 会改变接收载荷并使 CRC/解压失败；独立状态解析器仅扫描状态包，未执行载荷还原。压缩载荷可自然出现 `A5 5A`，只找 magic 不能提供无歧义复用。

若仅启动现状态 FSM 而不暂停帧 FSM，两者还会竞争同一 `tx_byte_r` 并各自推进索引。要支持帧内复用，必须明确传输封装、类型/长度/校验、转义或分块规则，并同时修改接收端。这是另一项协议变更。

## 建议的执行顺序和验收

1. 冻结 b9 当前 bit/源文件/日志，记录剩余下载次数；先保留板上现场。现有 CWC 可对已映射计数器取两次值确认增量，但文件中未映射 `estate/sstate/sts_want/dq_cnt/raw_wr_state/raw_rd_state/a1_busy`，不能承诺直接读出任意内部状态。
2. 在新隔离候选中修复统一帧间仲裁、队列指针和计数更新，保留 177 B v3 格式及 A1U1 帧格式。
3. 离线必测：状态请求在发送中到期且下一帧排队；tick 与出队同拍；状态发送期间持续排队；至少 12 描述符跨多次环绕；同拍出入队；复位后恢复。对未修版本保留失败反例。另检查满尺寸四槽地址不交叠、bridge 单写/独立背压及丢 LAST 后恢复，避免修完 UART 才撞上下一处已知缺口。
4. 验收要求：帧字节/长度/CRC 不变；无丢帧/重排或未知描述符；待发状态在安全帧边界获得发送；状态不插进长帧；持续运行无静默互锁。新增 status-enabled 连续流用例，不能只复用 status-only 和 status-disabled 的孤立用例。
5. 合并后用同一冻结候选重跑相关恢复矩阵和必要工程检查。此前20例恢复仿真与 b9 的源文件、DDR bridge 和 status 功能不同，不能给 b9 继承 PASS；旧 AR 在复位时仍未完成的边界原本也未覆盖。
6. 若准备继续用最后一次下载，应在离线和工程检查完成后，带上 `estate/sstate/sts_want/dq_cnt/uart_busy` 及必要 DDR 等待信号的诊断，保证一次试验能区分原因；按用户原授权执行。下载与 COM 打开顺序可复用已成功的先下载后监听方案。板上要求连续完整帧可校验、状态持续可达，并在故障后恢复，不能只看 LED 或累计计数非零。

## 可直接交给 OpenCode 的任务文字

> 先保持当前板上现场。审查 `a1_uart_export.v` 的状态仲裁：L302–303 要求队列为空才能发状态，L335 又用 `!sts_want` 阻止队列出队，存在 pending-status + 非空队列互锁。Codex 已在 `D:/fpga/ph1p100/work/b9-opencode-audit-20261025` 用未改 b9 RTL 复现，并用关闭状态功能的同输入对照完成两帧。请先在新隔离候选中修复统一帧间仲裁，并移植已独立通过的描述符队列1位指针及同拍出入队计数修复，保留 b9 的 v3 状态字段，勿整文件覆盖。不要先做帧内强插。补上状态开启的连续多帧、tick 同拍仲裁、至少12描述符环绕、同拍push/pop及恢复仿真；旧版本应失败、新候选应通过，帧CRC和状态XOR正确。通过后再完成相关工程检查，按剩余下载授权安排一次有足够探针的板测。若现有CWC缺内部状态须明确说明，不把未映射信号当成可直接读回。请更新交接区分代码已确认、仿真已复现和板上仍待确认。

复现命令：`python D:/fpga/ph1p100/work/b9-opencode-audit-20261025/run_repro.py`。
