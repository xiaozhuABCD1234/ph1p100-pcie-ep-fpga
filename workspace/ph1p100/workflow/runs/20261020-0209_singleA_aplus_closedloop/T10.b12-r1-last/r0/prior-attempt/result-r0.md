# T10.b12-r1-last r0 — 开发结果（R1 丢 LAST / 孤儿 writer 修复）

- run：`20261020-0209_singleA_aplus_closedloop`；任务：**T10.b12-r1-last**（批大小 1）
- 父任务 T10 **保持 blocked**；本包不关闭 T10
- 状态：**ready_for_test**（R1 修复 + 全部仿真回归通过；构建结果见 §6；板级 **blocked**：FTDI 不在位）
- 唯一源改动：`camera_a1_uart_top.v`、`a1_ddr_slot_store.v`（其余 7 个 changed-src 与 b11 r0 逐字节相同，见 `rtl-diff-r0.patch`）
- 冻结 v4 225 B / 55 字段、reader FSM、bridge、arbiter、crop、44 B 帧头与 CRC 全部未动

## 1. 交付物

| 项 | 路径 |
|---|---|
| 根因与前后对照 | `r0/diag/r1-root-cause.md` |
| 唯一 diff | `r0/rtl-diff-r0.patch`（2 文件；7 文件无 hunk） |
| 候选源 | `r0/changed-src/**`（9 文件） |
| 仿真入口/证据 | `r0/sim/**`、`r0/sim/sim-results-b12.json`、`r0/sim/run-b11|run-b12|run-t7|run-t7-b11|T10|T10-b11/**` |
| 构建 | `r0/td/**`（1 bitgen + 1 CWC） |
| 板级 | `r0/board/ftdi-preflight.log`（仅预检，0 下载） |
| Manifest / 哈希 | `CANDIDATE-MANIFEST-b12-r1-last-r0.json`、`r0/artifact-hashes.txt` |
| 经验 | `r0/lessons-r0.md` |

## 2. R1 复现（W1，未改 RTL）

冻结独立 TB/检查器（逐字节复制，未放宽判据）对 **b11 r0 冻结源**：

- clean 控制 **PASS**（135 B 物理 UART，四 CRC + 严格 zlib）
- loss 例 **DUT_FAIL_VALID**：cycle 7600 LAST `valid=1/ready=0`、FIFO `full=1`，故障窗口拒收 **7 组（含 LAST）**；释放背压后 cycle 9813 `writer=1 nbytes=45/80 slot0=WRITE raw_abort_cnt=0`；两好帧 `begin_deny=2`；cycle 151559 终态 `rawpub=1 exp=1`，恢复包 0。
- 证据：`r0/sim/run-b11/{summary.json,loss/result.json,loss/trace.txt}`

机制三条（clk_cam 只计数不 abort、A1 无主 beat 不消费导致 head-of-line、store abort 不压过同拍写且 begin+abort 无释放语义）+ 一条 skid/LAST 时序洞，详见 `r0/diag/r1-root-cause.md`。

## 3. R1 修复（W2，只改 2 文件）

1. `camera_a1_uart_top.v` clk_cam：`fifo_wvalid && !fifo_wready` → `abort_hold<=1`（sticky 至 abort beat 被 FIFO 接收）；`fifo_ovf_cnt` 保留且只统计真实数据丢失。
2. `camera_a1_uart_top.v` A1：`fifo_ready` 增加 `else 1'b1`（无主 stray beat 只消费）；写分支改为 `raw_active && !skip_frame`；abort beat 判定扩展为 `raw_active || begin_pend || skid_valid`。
3. `a1_ddr_slot_store.v`：`abort_now`/`begin_now`；`accept` 加 `!wr_abort`；`wr_begin_ready` 加 `(!wr_active || abort_now)`；写侧 abort > begin > 数据 优先级链（abort+begin 同拍释放旧槽并接收新帧）。
- 不变式：坏帧不发布（abort 压过同拍 LAST）、槽不泄漏、好帧字节不变、v4 包不变、无新增 CDC。

## 4. 定向与回归（W3，全部实跑）

| 用例 | 结果 | 证据 |
|---|---|---|
| **T1** clean 控制（独立 TB） | **PASS** | `sim/run-b12/clean/result.json` |
| **T2** 7 组拒收含 LAST → 两好帧恢复 | **PASS**（`raw_abort_cnt=1`、`rawdrop=1`、`writer_final=0`、槽 FREE、`begin_deny=0`、源序列 `[11,1000,1001]`、3 帧四 CRC+严格 zlib、周期 31559） | `sim/run-b12/loss/result.json` |
| **T3** 同拍 LAST+abort | **PASS**（`pub=0 drop=1 abort=1`，槽 FREE，下一帧发布/读回） | `sim/sim-results-b12.json: store_last_abort` |
| **T4** 同拍 begin+abort | **PASS**（有 FREE 槽：旧槽 FREE + 新帧 begin、仅一个 WRITE；无 FREE 槽：begin 被拒、仅 abort，随后 begin 成功） | `store_begin_abort` |
| **T5** 中写复位 | **PASS**（`wr_active=0`、两槽 FREE、计数清零、下一帧发布/读回、无 X） | `store_mid_reset` |
| **T6** 满槽并发 | **PASS**（slot0 READY + slot1 WRITE 丢 LAST → 只释放 slot1，slot0 读回逐字节，下一帧用 slot1） | `store_full_slot` |
| **T7** SOF 被拒变体 | **PASS**（`sof_reject=1`、`t7_drain=31` 周期释放、无 head-of-line；b11 同例 **DUT_FAIL_VALID**：`Fatal: T7_STORE_STILL_WRITING`） | `sim/run-t7/case2/result.json`、`sim/run-t7-b11/case2/result.json` |
| **T8** b9 `CASE=abort` | **PASS**（smoke `cyc=2565`、full `beats=558401 cyc=2550292`，与 b9 基线逐项相同） | `sim/sim-results-b12.json: raw_smoke_abort/raw_full_abort` |
| **T9** b9 `nofree`/`rdy`/`full2` | **PASS**（smoke `7520/3390/4781` 周期与 b9 基线相同；full `full2` = 259200 字/1036800 beat/`cyc=5020472`） | `raw_smoke_*`/`raw_full_full2` |
| **T10** 三帧小几何 | **PASS（数据通路）**：3 帧 ID1/2/3、源 111/222/333、帧字节与 b10 黄金三帧 **sha256 相同**、四 CRC+严格 zlib+独立参考全过、22 个 v4 状态包全部严格在帧间、帧包内 `z` 字节 0 | `sim/T10/triple/result.json`（`check_v4_frames.py`） |
| P1 三黄金 | **逐字节一致**：micro8x2 `fa513a2b…`、mid64x8 `ee61e620…`、full_grad `b992a8ad…` | `sim/caps/*.dec` |
| v4 包 | **PASS**：`packets=3 bad=0 len=225 ver=4 fields=55` | `sim/logs/sim_status_v4.log` |
| 集成两帧（真核 1920×1080） | **PASS**：`enc=2 exported=2 read=259200 dup=0 err=0 wd=0`；bridge `ar=261704 r=261704 rlast=261704 stale=0 block=0`（757 s） | `sim/logs/sim_full.log` |
| b11 read 九例 | one/multi/bp/late/stray/dup/full/reset 全 `pass=1 bad=0`；`read_full` 129600/129600 | `sim/sim-results-b12.json` |
| 计数 | 正常路径 `raw_drop/raw_abort_cnt=0`（P1、b9、v4、read 九例均 0） | 同上 |

**T10 的 v4 说明（非 R1 回归）**：冻结的 b10 三帧 TB 早于 v4 状态包，未驱动 v4 新增输入 `i_dbg_bridge`，状态包扩展字段（24 B/包）与 XOR 字节为 4 态 `z`；**同一 TB 在 b11 冻结源上产生逐字节相同的 550 个 `z`**（`sim/T10-b11/triple`），与本次修复无关；v4 包本身由 `tb_status_v4`（全输入驱动）判定 pass=1。因此 T10 采用 v4 感知检查器逐包验证：帧包内 `z=0`、四 CRC/严格 zlib/参考全过、状态包全部在帧间。

## 5. 复测清单（交综合测试者）

- required_dimensions：`functional`、`engineering`、`system`
- required_checks：
  1. `python -B r0/sim/run_r1.py --src r0/changed-src --out <新目录> --tag t --tb-dir r1-b12` → clean/loss 均 PASS（T1/T2）
  2. `python -B r0/sim/run_t7.py` → `T7_STATUS PASS`；如需负对照，对 b11 changed-src 复跑应 `DUT_FAIL_VALID`
  3. `python -B r0/sim/run_b12.py a b` → 全部 ok（v4/read 九例/P1 三黄金/full/定向 T3–T6/b9 回归）
  4. `python -B r0/sim/T10/run_multi_b12.py` + `check_v4_frames.py` → 3 帧字节 sha256 与 b10 黄金相同、帧包 `z=0`
  5. 构建：`r0/td/{a1_board.bit,a1_board.cwc,a1_board_inst.bid,cw/compiled.bit}` 与 `CANDIDATE-MANIFEST-b12-r1-last-r0.json` 一致；Routed 0 违例
  6. 板级：FTDI 0403:6042 当前不在位 → 只核对 `board/ftdi-preflight.log`（0 下载 / 0 COM8）
- report_paths：`r0/diag/r1-root-cause.md`、`r0/result-r0.md`、`r0/sim/sim-results-b12.json`、`r0/td/routed_qor.rpt`、`r0/td/routed_timing_status.rpt`
- input_status：**changed**（相对 b11 r0：2 个 changed-src 文件 + 构建/TB 输入路径）
- reuse_decision_paths：`r0/sim/r1-b11/*`（冻结反例 TB/检查器，只读复制）、`r0/sim/T10/*`（冻结三帧 TB/严格解析器，只读复制）

**不让继承的旧 PASS**：b11 的 read 九例/P1/v4 结论本轮全部重跑；b10 三帧结论改为“帧字节相同 + v4 状态包另行判定”。

## 6. 构建（W4）

`@@TD@@`

## 7. 板级（W5，条件执行）

- 预检（`Get-PnpDevice -PresentOnly`，未打开 COM8）：**FTDI 0403:6042 不在位**，无任何 FTDI 设备，COM3/COM4 为板载串口。
- 因此 `board=blocked`、`board_blocked_reason=FTDI_0403:6042_absent`、**下载 0 次、COM8 打开 0 次、不重试**。
- 证据：`r0/board/ftdi-preflight.log`。本包**不宣称任何板级结论**。

## 8. 未测边界与风险

- T1/T2/T7 为缩小几何（32×2、FIFO 深 4、相机 25 MHz、STS_DIV=0），不证明满速/512 深 FIFO 下的触发概率。
- b9 store 回归 full 尺寸 = 1920×1080 写读逐字节，但仍是行为 DDR 模型，不是真实 DDR/PAXI。
- 三帧 T10 的状态包扩展字段受冻结 TB（未驱动 `i_dbg_bridge`）限制为 4 态 `z`；数据通路已独立验证。
- 1176 读响应停点仍为 H2/H4，本包未触碰、未猜修。
- 板级未执行（FTDI 不在位）。

## 9. 预算与命令

- 开发用时 `@@MINUTES@@` 分钟（预算 120）；TD 会话 1 次（综合 1 次、布线 1 次、bitgen 1、CWC 1）；下载 0（预算 1，未用）；Flash 0。
- 命令/退出码：`r0/sim/run-b11/commands.json`、`r0/sim/run-b12/commands.json`、`r0/sim/run-t7/{compile,simulate-t7,check-t7}.log`、`r0/td/build_console_b12.log`、`r0/td/bitgen_console_b12.log`、`r0/td/cwc_console_b12.log`。
