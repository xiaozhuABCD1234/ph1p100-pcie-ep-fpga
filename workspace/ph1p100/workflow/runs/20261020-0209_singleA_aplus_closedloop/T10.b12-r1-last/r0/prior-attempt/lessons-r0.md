# T10.b12-r1-last r0 — lessons（可复用：根因 / 触发 / 修正 / 验证入口）

- 任务：修 R1（FIFO 拒收/背压丢 LAST 后 RAW writer 成为孤儿，槽不归还、后续好帧全被拒）
- 只改 2 个文件：`camera_a1_uart_top.v`、`a1_ddr_slot_store.v`；v4 225 B、reader/bridge/arbiter/crop 全冻结

## 1. 可复用根因

1. **“只计数”不是错误处理**：CDC FIFO 写端在 `wvalid && !wready` 时只加 `fifo_ovf_cnt`，没有生成帧级 loss-abort。丢 LAST 后下游 `wr_last` 永不到达，slot 永久 WRITE。教训：**任何帧内 beat 丢失都必须转成显式 abort 请求，并 sticky 到被下游真正接收**。
2. **消费端不消费“无主 beat”会造成 head-of-line 死锁**：`fifo_ready` 在“无 SOF/无活动帧/非 abort”时保持 0，残留数据 beat 卡住 FIFO 头，排在它后面的 abort beat 永远进不来。教训：**错误路径上也要保证每个 beat 都能被消费（只丢弃、不写入、不发布）**。
3. **abort 必须严格压过同拍写**：abort 与 `wr_valid/wr_last` 在同一 always 块内独立赋值时，同拍 LAST+abort 可能仍发布坏帧；`wr_begin_ready` 还要求 `!wr_active`，使 abort 当拍的 begin 被误拒。教训：**用 `!wr_abort` 门控 accept，并把 `abort_now` 纳入 `begin_ready`；写侧用 abort > begin > 数据 的优先级链**。
4. **skid 里的 LAST 是隐蔽时序洞**：上游在 LAST beat **进入 skid** 时就清 `raw_active`，而 store 接受它还要 1 拍以上。这期间到达的 abort beat 看到 `raw_active=0` 就不通知 store，却无条件清 `skid_valid`，把 LAST 丢掉 → 仍留孤儿 writer。教训：**abort 条件应覆盖 `raw_active | begin_pend | skid_valid`；store 侧 `abort_now=wr_abort && wr_active` 保证对空闲 store 无副作用**。

## 2. 触发条件（做回归时必须覆盖）

- FIFO 满时被拒收的 beat 恰好是 **LAST**（不是只丢中间 beat）；
- 拒收发生在 **SOF**（同帧数据先到 FIFO 头 → 死锁路径）；
- 背压释放后**先排空**再输入两个完整好帧（不要在同拍混入）；
- store 侧：同拍 LAST+abort、同拍 begin+abort（有/无第二个 FREE 槽）、满槽（READY+WRITE）并发、中写复位；
- 正常路径必须有 0 abort/0 drop 的负对照（P1 三黄金、b9 nofree/rdy、两帧集成）。

## 3. 修正要点（本次采用）

- clk_cam：`else if (fifo_wvalid && !fifo_wready) abort_hold <= 1'b1;`（sticky，直到 abort beat 被接收）；`fifo_ovf_cnt` 只在 `crop_valid && !fifo_wready` 增加。
- A1：`fifo_ready` 末尾 `else 1'b1`；写分支改为 `raw_active && !skip_frame`（stray beat 只丢不写）。
- A1 abort：`if (raw_active || begin_pend || skid_valid) raw_abort <= 1'b1;`。
- store：`abort_now`/`begin_now` 两个 wire；`accept` 加 `!wr_abort`；`wr_begin_ready` 加 `(!wr_active || abort_now)`；写侧用 `abort_now&&begin_now / abort_now / begin_now` 优先级链替换原来互相独立的 begin/abort 块。

## 4. 验证入口（下轮直接复用）

| 用途 | 入口 |
|---|---|
| R1 反例（clean+loss，冻结检查器） | `r0/sim/run_r1.py --src <changed-src> --out <dir> --tag <t> --tb-dir r1-b11` |
| SOF 被拒 / head-of-line | `r0/sim/run_t7.py`（`sim/tb_r1_sof.sv` + `check_t7.py`） |
| store 定向 T3–T6 | `r0/sim/run_b12.py b`（`tb_store_r1.v` 的 `last_abort/begin_abort/mid_reset/full_slot`） |
| b9 store 回归 | 同上 `raw_smoke_*` 与 `raw_full_*`（smoke 计数应与 b9 基线逐项相同） |
| P1/v4/full/read 九例 | `r0/sim/run_b12.py a` |
| 三帧小几何 | `r0/sim/T10/run_multi_b12.py`（`T10_SRC`/`T10_OUT` 环境变量可切换源与输出） |

## 5. 本轮踩过的坑（避免重复）

- **ModelSim `-modelsimini` 必须用正斜杠路径**，否则 Tcl 把 `D:\...` 当成 `{...}` 字面量 → `vsim-7`。
- **Verilog task 里引用模块级变量要先声明**（`last_id` 放到 task 之前），vlog 报 `vlog-2730`。
- **跨模块 TB 的读回顺序不能假设**：`oldest_slot` 用 `slot_seq` 与 `rd_expect` 配对，abort/begin 序列会改变 `pub_tgl` 奇偶，读回可能反序。校验应按 `rd_id` 取图案，而不是按调用顺序。
- **`tb_raw_store` 需要 `capture_async_fifo` 与 `cam_diag_mailbox`**（`p2_ddr_bridge` 的子模块），单独编译 store TB 时必须带上。
- **冻结的 b10 三帧 TB 未驱动 v4 新增输入 `i_dbg_bridge`**：状态包扩展字段为 4 态 `z`，与 b11 基线逐字节相同（非 R1 回归）。判断“帧字节是否变化”应看帧包 sha256，不要用 `int()` 直接解析整条 wire。
