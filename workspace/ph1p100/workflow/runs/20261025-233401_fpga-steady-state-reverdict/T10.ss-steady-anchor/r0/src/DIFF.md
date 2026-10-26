# src/DIFF.md — `tb_ss_anchor.v` 相对 b11 冻结 TB 的允许差异

- 基线（只读参照）：`src/ref/tb_b11_full.v`，SHA256 `e278cea5ad49d05a2cdddb2c27ed0b6353774cfa7a4a495b7366f917754ac699`（8,612 B），取自 b11 `CANDIDATE-MANIFEST-b11-aplus-read-r0.json` 的 `sim` 组。
- 派生 TB：`src/tb_ss_anchor.v`（283 行）。DUT/模型源 12 个文件与 b11 manifest **逐字节相同**（`input-verified.json`，0 mismatch），本文件不改任何 DUT 行。
- 允许来源：`fpga-design-guide.md` §3.2 白名单 1–8。以下逐条给出**文件、行号、原因**和“对 DUT 行为无影响”的论证。白名单外**没有**功能性差异（注释/别名/仅打印不计行为差异；见 §10 边界说明）。

## 1. `FRAMES` 参数与按帧门槛（白名单 1）

| 行 | 内容 | 原因 |
|---:|---|---|
| 31 | `parameter integer FRAMES = 4,` | 新增帧数参数；控制 run 由 `-gFRAMES=2` 覆盖 |
| 35 | `localparam integer RAW_WORDS = 129600;` | 只读常量（= 1080p 一帧 RAW 字数），用于 read 事件与最终门槛，避免魔数漂移 |
| 125–129 | `wire ss_pass = ... (st_cap==FRAMES) ... (st_read==FRAMES*RAW_WORDS) ...` | “最终门槛改为 FRAMES”；同时把 `raw_drop/cmp_drop/cap` 纳入 TB 自身 pass 汇总 |
| 244–245 | `drive_frame(1); drive_frame(2);` | 任务新增帧号实参（见 §2/§3） |
| 246, 254 | `if (FRAMES >= 3)` / `if (FRAMES >= 4)` | 仅当帧数足够时才执行第 3/4 帧 pacing；`FRAMES=2` 时整块跳过 |
| 266 | `while ((st_exp < FRAMES) && ...)` | 原 `while ((st_exp < 2) ...)` 改为按 `FRAMES` 排空 |
| 268–271 | stats 行末尾追加 `frames=<FRAMES> ss_pass=<0|1>` | 白名单 7（前 16 字段与顺序不变，见 §7） |
| 280 | `B11_FULL_RESULT pass=%0d", ss_pass ? 1 : 0` | 原内联 2 帧表达式改为统一 `FRAMES` 门槛 |

**无影响论证**：`FRAMES` 只决定驱动几个帧和排空条件；当 `-gFRAMES=2` 时 `FRAMES==2`，块 246/254 被常量折叠跳过，`while (st_exp < FRAMES)` 与 b11 的 `while (st_exp < 2)` 等价，`ss_pass` 的额外项在控制运行中全为真。因此 2 帧控制必须逐值复现 b11 统计（已由 `out/control-2frame.json` 验证；不通过即 `control_mismatch`）。

> 继承的 `B11_FULL_READ_DONE` 等待（263 行）**保持 b11 原文 `2*129600` 不变**，仅为日志信息标记；4 帧 run 的最终门槛在 125–129 与 268–271 行，不依赖该标记。

## 2. `SS_EVT` 事件打印（白名单 2）

全部是**只读**采样，不驱动 DUT：

| 行 | 内容 |
|---:|---|
| 137–166 | 既有 `always @(posedge clk_a1)` 块内新增事件检测：`st_pub`(143–147)、`st_read` 首次跨 `129600*k`(148–155)、`st_enc`(156–160)、`st_exp`(161–166) |
| 199–202 | `drive_frame` 内 `t_sof[k]` + `SS_EVT kind=sof` |
| 216–219 | 最后一行驱动后 `t_cam_end[k]` + `SS_EVT kind=cam_end` |
| 231–233, 241–242, 248–251, 256–259, 272–273 | 事件/元数据同时写 `+EVT=` 文件与 stdout |

事件文本严格为 `SS_EVT t=<cycles> kind=<sof|cam_end|pub|read|enc|exp> frame=<k> n=<count>`（设计指南 §2.1）。`SS_META`/`SS_PACE`/`SS_STATS` 是 TB-only 辅助标记，仅打印只读值（`t_rst`、pacing 时刻、统计摘要），已在设计指南 §8 允许的“新标记必须写进 DIFF.md”下声明。

**无影响论证**：这些语句只读顶层 `st_*` 输出与只读内部观测（`dut.raw_slot_st`、`dut.wd_fires`），没有任何 `force`/`deposit`/对 DUT 端口的赋值；`$display`/`$fwrite` 不消耗仿真时间。事件在既有 posedge 块中比较“上一拍采样值”，所有同类事件统一滞后 1 个 `clk_a1` 周期，**差值（L_cold/S_2/S_23/S_34）精确**；绝对 t 相对计数器翻转可能 +1 cycle，已在 `out/steady-state.md` 注明。

## 3. 第 3/4 帧 slot-free pacing（白名单 3）

| 行 | 内容 |
|---:|---|
| 183–191 | `task wait_slot_free(input integer slot)`：等待目标 RAW 槽 `slot_st==2'b00 (S_FREE)` |
| 246–253 | 第 3 帧：`wait_slot_free(0)` + `SS_PACE frame=3 slot=0` + `drive_frame(3)` |
| 254–261 | 第 4 帧：`wait_slot_free(1)` + `SS_PACE frame=4 slot=1` + `drive_frame(4)` |

观测方法：`dut.raw_slot_st` 是 `camera_a1_uart_top` 内 `u_raw_store.st_slot_st` 的**只读**观测线（`a1_ddr_slot_store.v` 中 `assign st_slot_st = {26'd0, slot_seq[1], slot_seq[0], slot_st[1], slot_st[0]}`），因此 `[1:0]`=slot0 状态、`[3:2]`=slot1 状态，`0`=FREE。等待发生在 `drive_frame` **之前**，确保第 k 帧 `e_sof` 时 `wr_begin_ready` 的 `free_valid` 已为真，避免 `raw_begin_deny` 整帧丢弃。`SS_PACE` 同时记录 `read`（应 ≥`129600*(k-2)`）与 `slot_st`，供 V5 复核。

**无影响论证**：只读内部状态，不改 `a1_ddr_slot_store`/`a1_raw_crop`/top 的任何信号；`wait_slot_free` 只消耗仿真时间（在 TB 初始块），不产生 DUT 输入。`FRAMES=2` 时两个块不执行，控制 run 的时序与 b11 完全一致。

## 4. 每帧 watchdog（白名单 4）

| 行 | 内容 |
|---:|---|
| 36 | `localparam integer WD_LIMIT = 8000000;` |
| 167–173 | `(cycles - last_exp_t) > WD_LIMIT` → `SS_STALL frame=<next> ...`、`B11_FULL_RESULT pass=0`、`$finish` |

**无影响论证**：只读 `st_exp/st_read/st_enc` 与 TB 自己的 `cycles`。watchdog 仅在“8,000,000 cycles 内 `st_exp` 未递增”时触发（正常 4 帧的帧间隔远小于该值），触发即主动结束并按 partial 保存日志事件，不会写出伪造的 4 帧统计。

## 5. `MAX_CYCLES`（白名单 5）

| 行 | 内容 |
|---:|---|
| 32 | `parameter integer MAX_CYCLES = 30000000`（b11 为 `60000000`） |

**无影响论证**：只影响 TB 的绝对超时保护（30M cycles ≈ 160 ms 仿真时间；4 帧预期 ≈ 20–22M）；控制 run 远未触及。

## 6. 路径寄存器加宽（白名单 6）

| 行 | 内容 |
|---:|---|
| 113–115 | `reg [4095:0] stat_path/dec_path/evt_path`（b11 仅 `stat_path[1023:0]`） |
| 231–233 | `$value$plusargs("STAT=%s"/"DEC=%s"/"EVT=%s", ...)` |
| 234–235 | `fd = $fopen(dec_path,"w"); fs = $fopen(stat_path,"w");` |

**无影响论证**：只影响 TB 文件路径字符串容量与打开位置；本任务 `sim/caps/` 绝对路径 >128 B，b11 的 128 B 寄存器会截断。路径只由 `run_ss.py` 传入，DUT 无文件接口。

## 7. 统计行追加字段（白名单 7）

| 行 | 内容 |
|---:|---|
| 268–271 | 前 16 字段与顺序保持 b11：`cap enc exported exp_bytes raw_pub raw_drop cmp_drop geom err read dup cap_bytes cycles wd ar r`；末尾追加 `frames=<FRAMES> ss_pass=<0|1>` |

**无影响论证**：仅改 `$fwrite` 文本格式与追加实参；`st_cap...n_ar,n_r` 的取值/来源不变。控制 run 用**前 16 字段**逐值比对，`frames/ss_pass` 不参与 b11 控制门槛。

## 8. `$fopen` 目标改为本任务 `sim/caps/` 绝对路径（白名单 8）

见 §6 的 231–235 行；实际路径由 `sim/run_ss.py` 的 `+STAT/+DEC/+EVT` 传入：
`.../T10.ss-steady-anchor/r0/sim/caps/{ss2,ss4}.{stats,dec,evt}`。
**无影响论证**：只改输出文件位置；`$fopen("w")` 截断旧文件，统计内容与 b11 同构。

## 9. 明确未改项（禁止项核对）

- DUT 端口/参数/时钟/复位/几何/内容函数：`tb_ss_anchor.v` 的实例化（55–110 行）与 `driver` 的 `smp`/`drive_frame` 像素序列（193–222 行）与 b11 相同，仅任务增加 `k` 实参和事件采样。
- `FRAME_GAP=400`、`LINE_GAP=16`、`UART_DIV=1`、DDR 模型 `#(.WORDS(524288), .AR_GAP(2), .R_GAP(3))`、`clk_cam/clk_a1/clk_ddr` 生成、复位 20/40 周期：未改。
- 无 `$deposit`/`force`/`release`；无对 `st_*` 计数、`exported` 来源、`wd_fires` 的写操作。
- `p2_a1_board_top.v` 只复制/哈希，**不编译**（板级 top 缺依赖）；`tb_b11_full.v` 只作 `src/ref/` 参照，不编译。

## 10. 行为边界与复核方法

- 本 DIFF 之外的文本差异仅为注释、`RAW_WORDS` 别名、事件打印和 `FRAMES` 相关行；无白名单外**功能性**改动。综合测试者可按本表逐条核对；任何未列出的赋值/时序/参数改动都应判 FAIL。
- 控制（`-gFRAMES=2`）是白名单正确性的机械证据：`cycles=11445988`、`cap_bytes=80156`、`exp_bytes=80068`、`read=259200`、`cap=2/enc=2/exported=2`、`raw_drop=0/cmp_drop=0/wd=0` 必须逐值相等。
- 4 帧事件与 `S_ss` 的复算方法与负对照见 `sim/run_ss.py`、`out/steady-state.md`、`out/selfcheck.json`。
