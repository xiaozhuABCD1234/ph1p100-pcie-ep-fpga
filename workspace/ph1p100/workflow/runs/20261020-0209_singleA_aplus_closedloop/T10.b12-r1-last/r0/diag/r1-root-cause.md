# T10.b12-r1-last — R1 根因与修复前后对照（W1 / W2）

- run：`20261020-0209_singleA_aplus_closedloop`；任务 `T10.b12-r1-last`；父 T10 保持 blocked
- 源基线：`T10.b11-aplus-read/r0/changed-src`（v4 225 B + F_WAIT 看门狗，9 文件哈希见 b11 manifest）
- 独立反例输入：`work/b10-gap-sim-20261025-132023`（只读，未修改）
- 本文件所有数字均来自本包 `r0/sim/cases/**` 的真实 ModelSim 运行，命令与日志见 `r0/sim/logs/**`、`r0/sim/sim-results-b12-*.json`

## 1. 现象（b11 r0 冻结源，本轮亲自复现）

同一冻结 TB/检查器（`r0/sim/indep/tb_r1_loss.sv` + `check_r1.py`，参数 CAM 40x8、ROI(4,2) 32x2、
每 ROI 16 组/80 B、`FIFO_AW=2`（真实 4 项）、相机 25 MHz、A1/UART 187.5 MHz、`UART_DIV=4`、
STS_DIV=0，唯一故障注入是外部 DDR AW/W ready 背压）：

| 观察 | b11 r0 冻结源 | b12 修复后 |
|---|---|---|
| clean 控制（T1） | PASS（135 B 物理 UART，四 CRC + 严格 zlib） | PASS |
| 故障帧 SOF 被接受 / writer 启动 | 1 / 1 | 1 / 1 |
| 故障窗口拒收组数（含 LAST） | **7（含 1 个 LAST）** | **7（含 1 个 LAST）** |
| 释放背压后 writer | **仍为 1（孤儿 writer）** | **0（已 abort）** |
| 故障槽终态 | **slot0=WRITE(1)** | **slot0=FREE(0)** |
| `raw_abort_cnt` / `raw_drop` | **0 / 0** | **1 / 1** |
| 后续两个好帧 | **`begin_deny=2`，恢复包 0** | 恢复包 2，`begin_deny=0` |
| 解码源序列 | `[11]`（仅 clean 前导） | **`[11,1000,1001]`**，帧 ID 1/2/3 互不相同 |
| 终态 `rawpub/enc/exp` | 1 / 1 / 1 | **3 / 3 / 3** |
| 观察窗口 | 151,559 A1 周期（与独立反例完全一致） | 31,559 A1 周期即完成恢复 |
| checker 结论 | **DUT_FAIL_VALID**（4 条未来判据全部不满足） | **PASS** |

b11 例的 checker 失败项（`r0/sim/cases/r1b11/loss/result.json`）：
`recovery criterion failed`、`RAW-slot release / good-frame recovery`、
`exact recovery source sequence`、`fault RAW slot not FREE`。
与独立反例（`work/b10-gap-sim-20261025-132023/r1-loss/result.md`）逐项一致：
`writer_final=1`、`slot0=WRITE`、`raw_abort_cnt=0`、`begin_deny=2`。

## 2. 三条机制（代码级）

### (a) clk_cam 拒收只计数，从不请求 abort

b11 `camera_a1_uart_top.v` 的 clk_cam 块只有：

```verilog
if (fifo_wvalid && fifo_wready && fifo_wabort) abort_hold <= 1'b0;
else if (crop_abort)                          abort_hold <= 1'b1;
if (fifo_wvalid && !fifo_wready) fifo_ovf_cnt <= fifo_ovf_cnt + 32'd1;   // 只计数
```

crop 本身没有 abort（`crop_abort=0`，几何/ROI 正确），所以**唯一能产生 abort 的路径不会启动**。
一旦被拒收的是 LAST，store 永远等不到 `wr_last`。

### (b) A1 侧无主数据 beat 不被消费 → head-of-line 死锁

b11 `fifo_ready` 组合逻辑在「非 SOF、非 skip_frame、非 abort、`raw_active=0`」时保持 0。
即使 (a) 修好，abort beat 也排在已入 FIFO 的数据 beat 之后；如果队头 beat 没有 owner，
它永远出不去，abort beat 就永远推不进来（b10 注释声称已消费，代码没有该 else 分支）。

### (c) store 的 abort 不压过同拍写，begin+abort 同拍无「释放旧槽 + 接收新帧」语义

b11 `a1_ddr_slot_store.v` 的 begin 与 abort 是两个独立 if，`accept` 不含 `!wr_abort`：

```verilog
wire accept = wr_active && ddr_ready && wr_valid;       // 同拍 wr_abort 也照写
assign wr_begin_ready = rst_n && ddr_ready && !wr_active && free_valid;  // abort 同拍不接受新帧
```

后果：同拍 `wr_last+wr_abort` 仍可能发布坏帧；abort 同拍的新 SOF 被误拒（之后还要再等一帧）。

### (d) 复现链的时序（b11，`r0/sim/cases/r1b11/loss/trace.txt`）

1. cycle 7380：seed100 SOF 被 FIFO 接受，writer 启动，slot0=WRITE；
2. 第 16 组（LAST）`valid=1 / ready=0 / FIFO full=1` → 拒收；故障窗口内共拒收 7 组（含 LAST）；
3. 释放背压后 FIFO/skid/DDR 排空，writer **仍活动**、`nbytes=45/80`、slot0=WRITE、`raw_abort_cnt=0`；
4. 两个完整好帧（seed1000/1001）的 SOF 均被 FIFO 接受，但 RAW begin 被拒（`begin_deny=2`）；
5. cycle 151559 终态：`rawpub=enc=exp=1`、writer=1、slot0=WRITE、恢复包 0。

## 3. 修复（只改 2 文件，见 `r0/rtl-diff-r0.patch`）

1. **clk_cam sticky loss-abort**（dev-plan §3.1）：任何 `fifo_wvalid && !fifo_wready` 的 beat
   （SOF/中间/LAST 任一拍）都置 `abort_hold<=1`，保持到 abort beat 真正被 FIFO 接收；
   `fifo_ovf_cnt` 保留但只统计 `crop_valid && !fifo_wready`（重试的 abort beat 不算数据丢失）。
2. **A1 无主 stray beat 消费**（§3.2）：`fifo_ready` 末尾增加 `else 1'b1`；正常帧每个 beat
   仍走 `raw_active -> skid_free`，P1 三黄金逐字节不变即为功能等价证据。
3. **store abort 压倒同拍写 / abort+begin 同拍**（§3.3）：
   `abort_now = wr_abort && wr_active`、`begin_now = wr_begin && wr_begin_ready`；
   `accept` 加 `!wr_abort`（同拍 LAST 不写、不 flush、不发布）；`wr_begin_ready` 加
   `(!wr_active || abort_now)`；写侧优先级改为 `abort+begin > abort > begin > 数据`，
   同拍时旧槽 `S_FREE`、新槽 `S_WRITE`、装载新 id/seq、清零 wcnt/pack_r/nbytes/waddr、
   `st_dropped++`、`st_abort_cnt++`。

不变式：坏帧不发布；槽不泄漏（abort 后 `wr_active=0`，或同拍被新 begin 接管）；
好帧字节不变；v4 225 B 不变；无新增 CDC（`abort_hold`/`fifo_ovf_cnt` 留 clk_cam，
store 改动留 clk_a1，无新增跨域信号）。

## 4. 修复后定向证据（摘要，明细见 result-r0.md §4）

| 用例 | 关键数字 |
|---|---|
| T2 恢复 | `rejects=7`、`last_reject=1`、`rawdrop=1`、`raw_abort_cnt=1`、`begin_deny=0`、`post_release_writer=0`、`slot0=0`、`rawpub=exp=3`、源序列 `[11,1000,1001]`、405 B 三帧四 CRC+严格 zlib |
| T3 同拍 LAST+abort | `pub=0 drop=1 abort=1`、无 DDR 写、槽 FREE、下一帧发布并读回 10 字 |
| T4 同拍 begin+abort | 有 FREE 槽：旧槽 FREE + 新帧 begin、`wr_slot=1`、仅一个 WRITE；无 FREE 槽：`begin_ready=0`、仅 abort、随后 begin 成功；三次读回逐字节 |
| T5 中写复位 | `wr_active=0`、两槽 FREE、计数清零、`rd_open_ready=0`（无 ghost READY）、下一帧发布/读回 |
| T6 满槽并发 | slot0 READY 保持、只释放 slot1、slot0 读回逐字节、`dup=0`、下一帧复用 slot1 |
| T7 SOF 拒收 | `sof_reject=1`、`last_reject=2`、释放后 32 周期排空（`writer=0`、`raw_abort_cnt=1`、槽 FREE）、seed300 单帧 135 B 四 CRC+严格 zlib、`exp=1` |
