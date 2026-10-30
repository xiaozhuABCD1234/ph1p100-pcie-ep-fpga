# 4K（3840×2160）writer p_bad 调试结论

日期：2026-10-29 01:15（Asia/Shanghai）
分析对象：`fpga/rtl/ep_side/ddr/cam_r10f_writer.v` **HEAD 版**（commit 07325d21；板端 01:07 构建的 bitstream 所用的就是这一版）。
注意：工作树在 01:10 之后有并发改动（加 `pbad_rsn`、删 S_WAIT 的 `p_bad`、把 `p_bad` 从 `verdict_bad` 移除）。本文第 1~3 节按 HEAD 版行号；第 5 节单独评价这些改动。

结论分三级：**【实测/代码事实】**、**【仿真证据】**、**【推测】**。

---

## 0. 一句话结论

1. **`0xF4=0x01` 不是 S_WAIT 的假报警。** `verdict_snap` 的锁存沿恰好就是 `frame_close` 被置 1 的那一拍，采到的是**置位前**的 `p_bad`；S_WAIT 要到下一拍才把 `p_bad` 置 1，而那时 `rw_done_r` 已被清 0。已用仿真验证好帧的 `verdict_snap=0x20`。
2. **"gcnt 恰好 = 2,073,600" 与 "SKIP_ROWS=37 + 每帧 2192 行 + H=2160" 在 RTL 上不可能同时成立。** 按 RTL 逐拍算，窗口只有 **2155 行 = 2,068,800 组**，比 2,073,600 少 **4800 组**；0xF4 的 bit2（gcnt mismatch）本应为 1。
3. 因此 `0xF4=0x01` 与 gcnt 位=0 的这个组合，在 RTL 里只有一个自洽的解释：**889–891 行的"超预算组"分支**——`gcnt` 被 `pay_ok`（580 行）钳位在 `GROUP_TOTAL`，多出来的组被丢弃并置 `p_bad=1`，所以 gcnt 位天然为 0。这个解释要求 cam 侧实际入队 **>2,073,600** 组（用 `0x80 lat_push` 判定）。
4. **几何参数本身就是错的**：4K 有效图在 3864×2192 tap 里的物理原点是 **(12,16)**（见 `a1_raw_crop.v:22` 板测结论）。`X0=0` 取到左边 12 列 OB、丢掉右边 12 列有效像素；`SKIP_ROWS=37` 比物理原点 16 多跳 21 行，且 37+2160=2197>2192，必然少 5 行。正确值：`X0(物理)=12`（或新增 X_OFF=12、X0=0）、`SKIP_ROWS=16`、`Y0=0`。
5. **不要把 `p_bad` 简单从判据里删掉**（当前工作树的改法）：超预算帧的 gcnt 会被钳成"恰好相等"，删掉 p_bad 后这种几何错帧会被当成好帧发布。正确做法是把"超预算"升级成一等错误（`extra_drop != 0`）并把它暴露出来。

---

## 1. Q1：2192 行 / SKIP=37 / H=2160 下，gcnt 怎么可能等于 2,073,600？

### 1.1 RTL 逐拍（HEAD 行号）

- `line_evt = cam_in_line & ~in_line_d`（256 行），`cam_in_line` 来自 CSI 的 `O_in_line`——**每个 RAW10 长包（每条源行）一个 1 拍脉冲**（`csi_rx_packet_integrity.v:139`，只在 `raw_header && image_ok` 时置 1；`0x120` bad=0 ⇒ 所有行都 image_ok）。
- 每拍 `line_evt`：`x_cnt<=0; cur_grp<=0; frame_lines++`；若 `~first_line` 则 `y_cnt<=y_cnt+1`（304–312 行）。SOF 时 `y_cnt<=0, first_line<=1`（292–303 行）。
- 所以第一条行事件时 y=0，第 k 条行事件时 y=k−1（行事件 0 起算时 payload 期间 y=e）。**y_cnt 计的是"从 SOF 起的所有源行"，不是窗内行。**
- `y_img0 = Y0 + SKIP_ROWS = 0+37 = 37`（258 行）；`in_win` 的 y 条件是 `37 <= y_cnt < 37+2160 = 2197`（259–260 行）。
- 2192 条行事件 ⇒ y_cnt 只到 2191。窗口内行数 = **2192 − 37 = 2155**。
- x 窗口：`x_cnt` 每有效组 +4；X0=0、W=3840 ⇒ `0<=x<3840` 正好 **960 组/行**（3864 像素里只取前 3840，即含左 OB、丢右 12 列）。
- 整帧 gcnt 理论上限 = 2155×960 = **2,068,800**，比 `GROUP_TOTAL=3840*2160/4=2,073,600`（182 行）**少 4800 组**。

> **【代码事实】"第 37 行开始取 2160 行"与"总共 2192 行"不自洽：37+2160=2197>2192，缺 5 行。** SKIP_ROWS 不是"OB 行数/窗内偏移"，而是**源行的物理 y 原点**（类似 X0 的物理含义）；注释"帧头 embedded + 物理哑行 37"来自 1080p ROI 时代，4K 未复测（`docs/TEST_REPORT.md §3` 也这么写）。

### 1.2 那 0xF4 为什么显示 gcnt 相等？

2,068,800 ≠ 2,073,600，所以只要走正常计数，bit2 必为 1。**唯一能让 gcnt "恰好等于 GROUP_TOTAL"且 p_bad=1 的 RTL 路径**是：

- `pay_ok = (pay_written + 5) <= PAY_BYTES`（580 行）；
- 第 2,073,601 组到来时 `pay_ok=0`，走 `pop & is_grp & pay_room & ~pay_ok` 分支（889–891 行）：**丢弃该组、`p_bad<=1`、`extra_drop++`，而 `gcnt` 不再加**。
- 之后 EOF 仍可正常弹出（`p_eof_seen=1`），DMA 拍数仍是 `DMA_BEATS`，AXI 无错 ⇒ `verdict=0x01` 正好是"p_bad=1、其它位全 0"。

也就是说：**"gcnt 恰好等于总组数"不是几何正确的证据，反而是"被钳位"的指纹。** 但 cam 侧窗口按 2155 行只能给 2,068,800 组，**触发不了钳位**。所以二者必有一错：

- **可能 A（推测，优先验证）**：cam 侧实际入队 >2,073,600 组。即行边界计数在 4K 下坏了（少一个 line_evt 后 x_cnt 不归零、在 16384 组后 16 位回绕，重新落进 [0,3840) → 同一 y 下重复计组）。这正好是 `LINE_CHECK=0` 注释里承认的"4K 行分隔不可靠"，只是 LINE_CHECK 只屏蔽了行级判决，**没有保护 x/y 窗口计数本身**。
- **可能 B（推测）**：writer 实际看到 **2197 个行事件**（=37+2160），于是恰好 2160 行、gcnt 自然等于总量，p_bad 来自 900（帧内 SOF）或 897（EOF 带坏标记）。这要求 writer 行事件比 CSI 的 `line_count`（0x124=2192）多 5；按 `O_in_line` 的产生条件这不该发生，除非 0x124 与 writer 不是同一帧/同一版参数。
- **可能 C（推测）**：板端 bitstream 的 X0/SKIP/H 与当前源码不一致（例如实际 SKIP=32 或 H=2155）。当前 worktree 的 writer 在 01:10 被改过，01:07 的 bitstream 对应 HEAD，但建议用 `0xD0` 高 16 位在 EOF 时的值直接核对 writer 的 frame_lines。

### 1.3 板上一条命令就能判定（关键）

**先读 `0x80` = `lat_push`（cam 侧本帧实际入队组数）**：

| `0x80` | 结论 |
|---|---|
| > 2,073,600 | **可能 A 成立**：cam 侧多计 → 890 超预算钳位。查行计数（x 回绕/丢 line_evt）。 |
| == 2,073,600 且 `0x84 lat_drop=0`、`0x90 lat_ovf=0` | **可能 B 成立**：源确实给了 2160 行；查 `pbad_rsn` 的 bit3/bit2，并核对 writer frame_lines（`0xD0` 高 16 位在 EOF 时应等于多少）。 |
| < 2,073,600 | gcnt 不可能相等 → 0xF4 读的不是这一帧/这一版参数（可能 C）。 |

`0x84`=lat_drop、`0x90`=lat_ovf、`0x98`=lat_gcnt、`0x80`=lat_push（`dbg_frame` 位域见 1462–1469 行；`ep_bar_win.v` 0x80 起）。

---

## 2. Q2：p_bad 到底由哪一处置位？S_WAIT 会不会被采到？

### 2.1 时序（HEAD 行号，关键）

- `verdict_snap` 锁存条件（1182–1188）：`a_st==A_IDLE && rw_done_r && s_state==S_WAIT`。同一分支里：
  - `verdict_snap <= {…, p_bad}`（非阻塞，取**本拍沿之前**的 p_bad）；
  - `frame_close <= 1'b1`（1233 行）；
  - `rw_done_r <= 1'b0`（1232 行）。
- S_WAIT（922–927）：`if (frame_close) begin s_state<=S_SYNC; p_bad<=1'b1; end`。
- 时间线（T = 锁存拍）：
  - T：`rw_done_r=1, s_state=S_WAIT` → **采 p_bad（=0）**、置 frame_close、清 rw_done_r。
  - T+1 沿：S_WAIT 看到 frame_close → `s_state<=S_SYNC`、`p_bad<=1`。此时 rw_done_r 已是 0，**不会再锁存**。
  - 下一个 SOF：S_SYNC 的 `p_bad<=0`（841 行）。
- 结论：**第 925 行的 p_bad 不会被本帧的 verdict_snap 采到。** 它只是"离开 S_WAIT 后本帧作废"的标记，本身没有错；删掉它也无害（S_SYNC 本来就不放行），但**它不是本次 p_bad=1 的原因**。

**【仿真证据】**（iverilog，`/tmp/tb_wrap2.v`、`/tmp/tb_geom.v`，DUT=真实 RTL）：
- 几何正好（W=3840,H=2,SKIP=1,3 行源；窗内 2 行）：`gcnt=1920=GROUP_TOTAL, p_eof=1, p_bad=0`，**帧被发布**（`seq` 递增），`verdict_snap` 在下一帧读到 `0x20`。→ 好帧没有被 S_WAIT 污染。
- 8×4 小几何好帧同样发布，`seq` 递增。→ 再次证明 S_WAIT 的 p_bad 采不到。

### 2.2 与"eof=1、gcnt 位=0、beats 对、axi 无错"相容的置位点

| 行 | 分支 | 与观测是否相容 | 说明 |
|---|---|---|---|
| 862 | S_SYNC blk_locked | 否 | 进 S_SKIP，gcnt=0，且 skip 帧走 1148 分支，不产生这个 `verdict_snap` |
| 890 | S_PAY 超预算 | **是（最自洽）** | gcnt 被钳在总量，extra_drop>0；见 §1.2 |
| 897 | EOF 带 eof_bad | 可能（弱） | 需要 `abort_seen/cam_frame_abort` 或 `line_warn`；0x120 bad/crc/hdr 全 0 且 LINE_CHECK=0 屏蔽 line_warn，概率低；查 pbad_rsn[2] |
| 900 | 帧内又见 SOF | 可能 | 不打断计数，gcnt 仍可自然到总量；查 pbad_rsn[3] |
| 902 | tmo_hit | 否 | 会提前冻结 `pay_ep` → gcnt 短；或 EOF 未被弹出 → `p_eof_seen=0` |
| 935 | S_SKIP 见 SOF | 否 | 同 862 |

**判断**：`0xF4=0x01` 这个组合最像 **890（超预算）**；其次是 **900（帧内 SOF）**。二者用工作树里新加的 `pbad_rsn` 一读即分（见 §5）。`897` 只在异常 abort 时序下成立。**不是 S_WAIT。**

---

## 3. Q3：正确的修法（不是屏蔽）

1. **几何（必须改）**：见 §4。
2. **行计数鲁棒化（4K 必须）**：writer 的 x/y 窗口完全依赖 `cam_in_line` 边沿，而设计自己承认 4K 行分隔不可靠。建议加"源行长兜底"：新增参数 `SRC_GPQ=966`，当 `cur_grp` 达到 `SRC_GPQ` 仍未见到 `line_evt` 时，合成一次行结束（`x_cnt<=0; win_grp 收口; y_cnt++`），并把 `line_evt_miss` 计数暴露到诊断。这样单个丢边沿不会让 x_cnt 跨行累积/16 位回绕，也不会让同一 y 重复计组。
3. **判据语义（必须改）**：**保留 `p_bad`**；把"超预算"升级为一等错误：`verdict_bad |= (extra_drop != 0)`，并把 `extra_drop` 从内部寄存器暴露到诊断字（HEAD 里它默认根本读不到，这正是"p_bad=1 却查不到原因"的一个盲点）。
4. **锁存点语义（建议改）**：把判决锁存从 "`rw_done_r && s_state==S_WAIT`" 改成 "**`rw_done_r` 上升沿一次性锁存**"（与流状态机解耦），`frame_close` 仍只在 S_WAIT 发。这样不会因为状态机晚到而漏锁存/串帧，也让"本帧判据"与"下一帧"彻底分开。
5. **`verdict_snap` 的 bit5 是上一帧的 pub_ok（已发现）**：1185 行 `verdict_snap <= {2'b0, pub_ok, ...}` 与 `pub_ok <= ~verdict_bad` 在同一 always 块同一沿，非阻塞 ⇒ bit5 采到的是**上一帧**发布结果。所以"好帧第一帧 0xF4 读 0x00、第二帧才 0x20"。修复：在锁存表达式里直接用 `~verdict_bad`（当前帧）而不是 `pub_ok`。这也是看 0xF4 判断是否修好时容易误判的坑。
6. **双路 4K 带宽（重要背景）**：单路 4K30 需要 ~2.59M clk_ddr/帧（1.25 拍/组，占 33.3ms 的 ~78%）；A/B 同时 arm 时打包流水 + 单 DDR 写口 >100%，FIFO 只有 1024 组 ≈1.06 行，必然丢组/丢 EOF。验证时务必 `0x6C=1` 只开 A。若双路是目标，需要另做吞吐改造（降帧率/加大 FIFO/改仲裁），不是调判据能解决的。

---

## 4. Q4：4K 的 OB 与几何参数

已知（`a1_raw_crop.v:21-22`，板测几何推导）：IMX415 tap = **3864×2192**，主动区 **3840×2160**，物理原点 **(12,16)**；每行 966 组（=3864/4，WC=4830B，0x124 实测一致）。

- 水平：3864−3840 = 24 列 = 左 12 + 右 12。窗口必须从物理 x=12 开始、宽 3840：
  - 组号 3..962，共 **960 组**；`X0(物理)=12` 是 4 的倍数，满足要求。
  - **但注意语义**：`in_win` 与 R10F 头的 `roi_x` 现在共用 `X0`（259 行 / 536 行）。若直接把 X0 设成 12，头里会写 `roi_x=12`、`flags=2(CROPPED)`，而这是全幅有效图、语义应为 `roi_x=0/flags=0`。**推荐新增 `X_OFF`（=12）只用于窗口，X0 保持 0**（y 方向已经有 SKIP_ROWS 与 Y0 分离，x 方向缺这一层）。
- 垂直：2192−2160 = 32 行非有效（实测原点上边界 16 → 16 top + 16 bottom）。`SKIP_ROWS` 是**物理 y 原点**，所以 **SKIP_ROWS=16**（`Y0=0`）。窗口 y=[16,2176)，正好 2160 行，底 16 行 OB 不读。
  - 若按"24 行 OB"的说法：24≠32，剩下的 8 行是 dummy/embedded；不要用 OB 数量当 SKIP，必须用实测的物理原点 16。37 会多跳 21 行且 37+2160=2197>2192（少 5 行，4800 组）。
- 推荐最小参数改动（顶层 `ph1p_pcie_ep_top.v:115-119`）：

```verilog
localparam integer CAMDDR_W   = 3840;
localparam integer CAMDDR_H   = 2160;
localparam [15:0]  CAMDDR_X0  = 16'd0;    // 逻辑 ROI（进头）
localparam [15:0]  CAMDDR_XOFF= 16'd12;   // 新增：4K 左 OB 列（只用于窗口）
localparam [15:0]  CAMDDR_Y0  = 16'd0;
localparam [15:0]  CAMDDR_SKIP_ROWS = 16'd16;
```

writer 内（对应 HEAD 259–260 行）：

```verilog
parameter [15:0] X_OFF = 16'd0,
wire [15:0] x_img0 = X0 + X_OFF;
wire in_win = (x_cnt >= x_img0) && (x_cnt < (x_img0 + W16)) && ...
```

（若坚持不新增参数：把 `.X0(16'd12)` 也能拿到正确像素，但头字段会写成 roi_x=12/CROPPED，需知悉。）
Bayer 相位推导也应使用物理原点 `(X0+X_OFF, SKIP_ROWS+Y0)`（186–187 行）。

---

## 5. 对工作树里"并发改动"的评价（重要，避免误修）

01:10 之后 worktree 的改动方向：加 `pbad_rsn`、删 S_WAIT 的 `p_bad`、`verdict_bad` 去掉 `p_bad`（先加过 `ovf_seen` 又删掉，且 `ovf_seen` 一度未声明，若按那个中间态综合会得到隐式 1 位悬空网，务必确认最终文件里没有该标识符）。

- **删 S_WAIT 的 p_bad：无害，但不是根因**（见 §2.1）。不要把它当成"修好了"的依据。
- **把 p_bad 从 verdict_bad 删掉：危险。** 本次 0xF4=0x01 很可能是超预算钳位（§1.2）；删掉 p_bad 后这类帧 gcnt/beats/eof 都"对"，会被**发布成好帧**，而内容已经错行/重复。应改为 `verdict_bad |= (extra_drop != 0)`，并保留 p_bad（或至少保留 extra_drop 判据）。
- **`pbad_rsn` 很有价值**，请保留并读出：新版 `dbg_frame[255:224] = {22'd0, pbad_rsn[4:0], lat_wdt, lat_tmo, lat_pbad, lat_peof, lat_eb}` ⇒ `0xD0 = pbad_rsn<<5 | {lat_wdt,lat_tmo,lat_pbad,lat_peof,lat_eb}`。bit 定义：0=blk_locked、1=超预算、2=eof_bad、3=帧内 SOF、4=tmo。**读 0xD0 的 [9:5] 即可一锤定音。**
- 注意：加了 pbad_rsn 之后 `0xD0` 高 16 位不再是 writer 行计数，不能再用它判断 "2192 行"。

---

## 6. 板上验证清单（修好之后，只开 A：`0x6C=1`）

| 寄存器 | 期望 |
|---|---|
| `0x120` | good 持续增长、bad/hdr_err/crc_err = 0 |
| `0x124` | last_lines=2192、last_wc=4830（源没变） |
| `0x80` | `lat_push == 2,073,600` |
| `0x84` / `0x90` | lat_drop=0、lat_ovf=0（0x80 的 bit15 dbg_anomaly 应保持 0） |
| `0x98` | `lat_gcnt == 2,073,600` |
| `0xD0` | 低 16=966；**EOF 时高 16（writer frame_lines）应 = 2192**（若 ≠2192 说明行计数坏，按 §3.2 修） |
| `0xA0` / `0xAC` | seq 以 ~30/s 增长；len=10,371,072 |
| `0xF4` | 连续两帧好帧后 = `0x20`（**注意 bit5 是上一帧的，修 §3.5 后才是本帧**） |
| `0x184` | B 路同（如果开 B） |

若 `0xF4` 仍是 `0x01`：读 `0xD0[9:5]` → bit1=超预算（回到 §3.2 行计数）、bit3=帧内 SOF（查 `cam_vsync` 是否有额外 FS/毛刺，考虑 S_PAY 里把帧内 SOF 当作真正的帧边界处理而不是只置 p_bad）、bit2=eof_bad（查 abort_seen 的采样时序）、bit4=tmo（查 EOF 与 tmo 的相对时序）。

---

## 7. 仿真证据与可复现命令

环境没有 ModelSim，改用 iverilog（可用）。DUT 是真实 RTL，TB 在 `/tmp`（不入库）：

```bash
# 1) 好帧 / 短行 / 超预算对判据的影响
cd fpga
iverilog -g2005 -o /tmp/tb_geom.vvp -I rtl/ep_side/ddr /tmp/tb_geom.v rtl/ep_side/ddr/cam_r10f_writer.v
vvp /tmp/tb_geom.vvp
# 2) 复现 0x01 指纹：让 x_cnt 跨行不归零并 16 位回绕（同一 y 下多计组）
iverilog -g2005 -o /tmp/tb_wrap2.vvp -I rtl/ep_side/ddr /tmp/tb_wrap2.v rtl/ep_side/ddr/cam_r10f_writer.v
vvp /tmp/tb_wrap2.vvp
```

关键结果：
- 好帧（窗内正好 H 行）：`p_bad=0`、发布、`verdict_snap` 下一帧 0x20。
- 超预算（人为制造 x 回绕多计）：`verdict=01`、`p_bad=1`、`gcnt=1920==GROUP_TOTAL`、`beats=384/384`、`p_eof=1`、`extra_drop=616`。→ 与板端 `0xF4=0x01` 指纹完全一致，说明"gcnt 恰等"确实可以来自钳位而不是几何正确。

**附带发现（不是 4K 本次根因，但建议修）**：`clogb2()` 对 `DMA_BEATS=2^n` 返回 n，`BTL_CW=n` 装不下 2^n 本身；`localparam [BTL_CW-1:0] DMA_BEATS_S = DMA_BEATS;` 会截成 0（我第一次用 H=1 时 DMA_BEATS=256、BTL_CW=8，AXI 第 1 笔后直接进 A_RWD，帧永远不发布）。4K 的 DMA_BEATS=324,096 不触发，但小几何/仿真会被坑。改成 `clogb2(DMA_BEATS)+1` 或存 `DMA_BEATS-1`。

---

## 8. 推测 vs 证据一览

| 结论 | 级别 |
|---|---|
| S_WAIT 的 p_bad 采不到；好帧 verdict=0x20 | 代码时序 + 仿真（强） |
| 2192 行、SKIP=37、H=2160 ⇒ 窗口 2155 行 = 2,068,800 组 | 代码算术（强） |
| 37+2160=2197>2192，几何不自洽 | 算术（强） |
| 4K 有效图物理原点 (12,16)、X0=12/SKIP=16 | `a1_raw_crop.v:22` 板测几何 + 0x124 (12,16 推导)（强） |
| 0xF4=0x01 最可能是 890 超预算钳位 | 排除法 + 仿真指纹（中高，需 lat_push/pbad_rsn 确认） |
| cam 侧多计来自丢 line_evt 后 x_cnt 回绕 | 推测（机制已仿真复现；板上是否发生需 0x80 与 0xD0 验证） |
| 行事件实际 2197（可能 B） | 推测（与 0x124=2192 冲突，需同帧对照） |
