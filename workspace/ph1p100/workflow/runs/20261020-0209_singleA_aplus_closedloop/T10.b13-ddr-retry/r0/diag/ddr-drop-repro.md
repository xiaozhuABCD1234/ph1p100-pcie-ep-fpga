# T10.b13-ddr-retry r0 — 丢 R 复现与修复前后证据

日期：2026-10-25；run `20261020-0209_singleA_aplus_closedloop`；包 `T10.b13-ddr-retry r0`

## 1. 板级既有证据（冻结，H4）

`T10.b12-r1-last/r1/board/captures2/status_v4.txt`（150 包，bad_xor=0）：

- `slot0=READING`、`slot1=READY`，两槽各 2,592,000 B
- store AR=883、PAXI AR=883、PAXI R=882、`rlast=882`、stale=0、`ar_pending=1`、`af_rvalid=0`、`ddr_rdy=1`
- `raw_rd_state=rd_state=R_RW rd_armed=1`、`raw_rd_idx=882`、`raw_rd_words=129,600`、`rd_wait_cycles=0xFFFFFFFF`（饱和）
- `raw_pub=2`、`enc=0`、`exported=0`；cap/crop 增量各 4,470，`crop_short=0`、`crop_geom_err=0`

结论：DDR 接受第 883 个 AR 后永不返回 R；A1 侧 1:1 平衡（AR 883 / R 882），不是 A1 丢响应。停点从 1176 变为 882 → 偶发丢响应，不是固定地址。

## 2. 单元级复现（tb_b13_store_retry，真实 `a1_ddr_slot_store` + `a1_ddr_arb2`）

DDR 模型：AR 接受后按 `drop_left/drop_word` 决定是否吞掉该 AR 的 R（永不返回），日志
`TB13_DROP ar=<n> addr=<word> cycle=<t>`。

- 未加超时前（b12 源，`RETRY_EN=0`）：命中丢 R 后停在 `R_RW`，`rd_idx` 冻结、无 `rd_close`、无导出（与板级 H4 同构，见 b12 源单测基线）。
- 加超时/重试后（`RETRY_EN=1`，`TIMEOUT_N=64/GUARD_N=128` 缩短版）：
  - `TB13_TIMEOUT idx=8 wait=32 words=32` → 第 8 个字丢 R，8192/64 拍后超时；`rd_idx` 回 0
  - `TB13_GUARD cycles=129 ar=0 open_ready=0 ok=1` → 保护窗内无 AR、`rd_open_ready=0`
  - 重试从 word 0 重读，32/32 字逐字节等于影子内存（`bad=0`）
  - `B13_STORE_RESULT case=retry pass=1 timeout=1 retry=1 giveup=0 bad=0`
  - `case=budget pass=1 timeout=3 retry=2 giveup=1`：第 1 帧每次 AR 都丢 R → 3 次超时、2 次重试、放弃并释放槽；下一好帧正常导出

## 3. 整链（真实 camera_a1_uart_top + a1_ddr_arb2 + p2_ddr_bridge + PAXI 模型）

`tb_b13_chain.sv`（64×8 ROI，生产默认 `TIMEOUT_N=8192`、`GUARD_N=32768`，bridge guard 65536 clk_ddr）：

| 用例 | 结果 |
|---|---|
| clean（无丢 R） | 导出 1 帧，`exp_bytes=666`，四 CRC+zlib+独立参考全过，timeout/retry/giveup/stale=0；v5 状态包 241 B 解析通过 |
| drop1（word 16 丢 R） | `timeout=1 retry=1 giveup=0`，`MODEL_DROP_R addr=16 occ=1`；**但整流不完成**：2,000,000 拍看门狗触发，`read_words=16`、`enc=0`、`exported=0` |
| late1（word 16 的 R 晚 12000 拍） | `timeout=1 retry=1 stale_guard=1`（晚到 R 被吞掉并计数，未进入重试数据流），但同样卡在看门狗 |
| three_f2（3 帧，第 2 帧丢 1 R） | `timeout=1 retry=1`，仅导出 1 帧后看门狗 |
| budget（第 1 帧每次 AR 丢 R） | 期望 3/2/1；实测 `timeout=1 retry=1` 后即卡死（未达 3 次） |

### 3.1 卡死定位（现场探针）

在 drop1 用例 7 ms 处采样：

```
raw_rd_state=1(R_AR) armed=0 arvalid=1 arready=0 rd_idx=0
arb_busy=0 owner=0 last=0 m0ar=1 m1ar=0 sarready=0
br_sarready=0 af_wready=0 af_rvalid=1 arpend=1 parvalid=0
model: rpend=0 pq_cnt=0 rvalid=1(held) n_ar=36 n_rhs=34 drop_this=0
br: paxi_rready=0 prvalid=1 srv=1 rf_rvalid=1 rf_pop=0 s_load=0
```

即：超时后 store 回到 `R_AR` 等重试 AR；bridge 的 A1 侧 skid 里压着一个 R（`s_rvalid_r=1`），
而 store 只在 `R_RW` 拉高 `rready`，无法排空；RF 因此不能被 pop → `paxi_rready=0` →
PAXI 上已返回的 R 不能完成 → `ar_pending` 不清 → AF 不排空 → `s_arready=0` →
重试 AR 永远不被接受。**循环等待（重试后死锁）**。

本轮已尝试并在源码中保留的两处修正：

1. `p2_ddr_bridge.v`：purge/guard 期间 `s_arready=0`（`A1_GUARD_N=70000 clk_a1`，>65536 clk_ddr），
   避免重试 AR 在 bridge guard 内被 `af_pop_purge` 丢掉（这是首轮 1 次超时后立刻二次超时的原因）。
   修正后 drop1 只超时 1 次（不再 3 次），证明该修正有效。
2. `camera_a1_uart_top.v`：删除重复的 `raw_stale_guard` 线网声明（ModelSim 拒绝，TD 静默接受）。

残余死锁属于 bridge A1 侧 skid/RF 与 store `R_AR` 的握手，需在下一轮把「重试前的 R 只能被丢弃、
不得进入 RF/skid」做成结构保证（例如 store 在 `R_AR/R_GUARD` 也持续 `rready` 但丢弃，或 bridge
在 store 未处于 `R_RW` 时直接吞 R 并计数），而不是靠 guard 窗口的时间余量。

## 4. 结论（r0 首轮，已被 §5 取代）

- 单元级超时/重试/预算/保护窗语义已按冻结规格工作（T2/T6/T7/T5 的 store 侧）。
- 整链在丢 R 后**不能完成重试导出**，属 dev-plan §8 的停止条件（"T2/T3 重试后仍不能导出"）。
- 因此**不 bitgen、不下载**；板级只做 FTDI 预检（见 `r0/board/README-preflight.md`）。

## 5. b13b 续跑：死锁与重放修复（2026-10-25 晚）

首轮 §3.1 的循环等待已按"结构保证"修掉，并在修复过程中又暴露并修掉一个 AF 写口风暴。
只改 `a1_ddr_slot_store.v` 与 `p2_ddr_bridge.v`；不放松超时/重试预算，不改 A+/帧格式。

### 5.1 修复 1：store 排空模式（`a1_ddr_slot_store.v`）

```verilog
wire rd_drain = RETRY_EN && ((rd_state == R_AR) || (rd_state == R_GUARD));
assign ddr_rready = (rd_state == R_RW) || rd_drain;
```

- 超时后 store 在 `R_AR/R_GUARD` 持续拉高 `rready`，把 bridge RF/skid 中属于已中止尝试的 R
  **消费并丢弃**；数据只在 `R_RW` 锁存，因此 `rd_data/rd_valid/rd_idx/st_read_words` 不可能被污染。
- `RETRY_EN=0`（压缩槽）完全保持 b12 行为（`rd_drain=0`）。
- 这切断了 `skid → rf_pop → paxi_rready → ar_pending → AF → s_arready` 的循环等待。

### 5.2 修复 2：bridge 整个 abort/guard 窗口静默排空（`p2_ddr_bridge.v`）

```verilog
wire a1_drain_win = a1_purge_act || a1_ar_hold_act;   // 不只是 4 拍 purge
wire s_load = rf_rvalid && (!s_rvalid_r || s_rready) && !a1_drain_win;
wire rf_pop = s_load || (a1_drain_win && rf_rvalid);
```

- 原实现只在 4 拍 `a1_purge` 内排空；guard 期间仍会把 RF 装进 skid，若 store 此时不接收，
  又回到同样的循环等待。现在整个 A1 guard 窗口都不装载 skid、持续排空 RF。
- 与 5.1 组合后，"重试前残留 R"不再依赖时间余量，而是结构上不可能进入重试数据流。

### 5.3 修复 3：AF 写口必须用 AR 握手限定（`p2_ddr_bridge.v`）

把 `u_af` 的 `w_valid` 从裸请求电平 `s_arvalid` 改为握手限定：

```verilog
assign af_push = s_arvalid && s_arready;
capture_async_fifo u_af ( .w_valid(af_push), ... );
```

- 这是 b13b 新增 `s_arready` guard 门控后暴露的真实缺陷：store 的 `arvalid` 在 `R_AR`
  会一直保持到被接受（本包 guard 内 ~37k 拍），而 FIFO 的 `w_valid` 原来接的是请求电平，
  于是 AF 每个时钟被写入同一地址，深度 16 的 AF 充满 `addr0` 副本。
- 现象（修复前 drop1 探针）：重试读 32 字里前 19 字全是 word0，`dup_words=18`，
  压缩流长度 374 B ≠ 黄金 666 B（帧被导出但 CRC 失败）。
- 修复后 drop1/late1/three/budget/clean 全 PASS（见 `sim-results-b13-chain.json`）。

### 5.4 修复后整链结果（生产默认参数 TIMEOUT_N=8192/GUARD_N=32768）

| 用例 | 结果 |
|---|---|
| clean | exported=1，exp_bytes=666，四 CRC+zlib+独立参考全过，timeout/retry/giveup/stale=0 |
| drop1（word 16 丢 R） | timeout=1 retry=1 giveup=0，exported=1，另存字节等于黄金，四 CRC+zlib 全过 |
| late1（晚 12000 拍） | timeout=1 retry=1 stale_guard=1，exported=1，晚到 R 未进入重试流 |
| three_f2（3 帧，第 2 帧丢 R） | 3 帧全导出、ID 不同、四 CRC+zlib 全过；计数 1/1/0，第 1/3 帧 stale=0 |
| budget（首帧每次 AR 丢 R） | timeout=3 retry=2 giveup=1；该帧不发布/不导出、槽 FREE；下一好帧导出 |

### 5.5 测试台修正（非放宽判据）

- `tb_b13_chain.sv`：`dq_end`（结束时刻描述符队列深度）取代 `max_dq` 作为"队列空"判据；
  `max_dq` 是全过程峰值，正常导出 1 帧必然出现瞬时 dq=1，原判据恒失败。帧/CRC/zlib 判据未改。
- `tb_b13_chain.sv`：状态包节奏 `STA_DIV` 由 10000 改为 25000。v5 包 241 B × 10 bit × UART_DIV=4
  = 9640 拍，10000 的节奏把 UART 占满，帧边界永远被 status 抢走（clean 小帧恰好在首个状态包前导出，
  掩盖了问题）。板上 STS_DIV=1 s（241 B @115200 ≈ 21 ms），不存在该饱和。
- `check_b13.py`：只改 dq 判据（`max_dq>=0` 观测 + `dq_end==0`），帧/CRC/zlib/参考判据原样。
- `check_t7.py` / `check_multi_b12.py`：只补 `indep/indep` 的 sys.path，并把 multi 的 v4 状态包常量
  更新为 v5（241 B/59 字段/VER=5）；帧判据未改。

### 5.6 1080p 全帧丢 R 暴露的第二个死锁：A+ 孤儿输出字

64×8 整链全过之后，按 T12 做 1920×1080 全帧、word 60000 丢 1 个 R，发现**重试永不启动**：

- store：`rd_state=R_GUARD(5)`、`guard_cnt=0`、`retry_used=0`，`rd_open_ready=1`（等待 top 重开）；
- top：`fstate=F_IDLE`、`a1_can_start=0`，原因是 `a1_out_valid=1`；
- cmp store：`wr_active=0`、两槽 FREE、`cmp_wr_ready=0`；
- A+ 核：`istate=I_IDLE`、`frame_active=0`、`killed=1`、`svalid=1`。

即：超时后 `cmp_abort` 已经释放压缩槽（`wr_active=0`），但 A+ 核在帧级 abort 之后仍会再吐出/残留一个打包输出字
（`svalid=1`）。`a1_out_ready = cmp_wr_ready`，而 `cmp_wr_ready = wr_active && ...=0`，这个孤儿字永远不能被消费，
`a1_out_valid` 恒 1 → `a1_can_start=0` → raw 重试永不打开。64×8 只是碰巧在 abort 前把最后一个字消耗掉，所以没暴露。

修复（`camera_a1_uart_top.v`，不改 A+ 核）：

```verilog
reg cmp_abort_pend; reg [4:0] orphan_drain_cnt;
wire orphan_drain = cmp_abort_pend || (orphan_drain_cnt != 0);
assign a1_out_ready = cmp_wr_ready || orphan_drain;      // 消费孤儿字
... u_cmp_store .wr_valid (a1_out_valid && !orphan_drain) // 但绝不写槽
// cmp_abort 后 orphan_drain_cnt<=16，覆盖 deflate 尾巴
```

- 孤儿字只完成 A+ 核的 `out_ready` 握手并被丢弃，不进入 cmp store（`wr_valid` 被门控），不产生描述符，不发布半帧。
- 16 拍尾窗后 `a1_out_valid=0`，`cmp_abort` 释放槽，`F_IDLE` 立即重开同一 raw 帧。

### 5.7 结论

- 丢 1 个 R → 8192 拍超时 → 清读通路 → 32768 拍保护窗 → 重试同一帧 → **完整导出**；
  晚到 R 只被吞掉计数；3 次尝试预算耗尽时释放槽、不发布半帧；下一帧恢复。
- 整链功能门槛通过，进入重建与板级。

