# src/DIFF.md — `tb_ss_g0.v` 相对 P1 `tb_ss_anchor.v` 的允许差异

- 基线（只读）：`src/ref/tb_ss_anchor.v`，SHA256 `ddd9e02ca71aa3b81e86f4cc0f151498fd48bf9a4dbbcc042b59c97d9f15d1ff`（14,273 B，P1 r0 冻结件）。
- 派生 TB：`src/tb_ss_g0.v`。**12 个 DUT/模型源与 P1/b11 冻结副本逐字节相同**（见 `input-verified.json`，0 mismatch），本文件不改任何 DUT 行。
- 允许来源：dev-plan §10.4-2 的 CONTENT / PACING / SINK / CAPTURE / MAX_CYCLES / 向量映射 / 字节级自检 / 事件协议白名单；README 式边界差异（路径、打印）另列。
- **TB 版本说明（必须披露）**：R0–R3 使用的 TB SHA256 为 `89948303be78da2b4e2cbccbb70935d26825b518620c679ba9d959d3c950008e`；其后仅修正 TB 本地自检的分组计数差一错误（见 §7）并在帧 1 后加一条早打印，冻结 TB SHA256 为 `a565c6f25f5d8ac16ce8dd8042f35395c6018a23d1093448077b0e90b79bd3d0`（24,118 B）。自检只读、不驱动任何 DUT 信号（CONTENT=0 时整段不执行），故 R0–R2 与修正后 TB 行为逐字节等价；R3 的 DUT 结果由 DUT 自身导出的 `xform_crc/raw_crc` 独立证明，`v1` check-only 复跑在修正后 TB 上给出 `SS_VEC_MATCH bad=0`。

## 1. 参数与模式（白名单 A）

| 行（近似） | 内容 | 原因 |
|---|---|---|
| 21–36 | 新增 `CONTENT/PACING/SINK/CAPTURE`，`MAX_CYCLES=48,000,000` | dev-plan §10.4-2；P1 为 30,000,000 |
| 37 | `WD_LIMIT=12,000,000` | strict-serial 下“相机 1.6M + core 6.0M”可超过 P1 的 8M 门限；R3 `L_cold=9,234,076 > 8M` 会误触发；12M < MAX_CYCLES=48M，仅防真挂死。**round1 D2 白名单允许** |
| 45–49 | `clk_uart_f` 2 GHz + `wire clk_uart = SINK ? clk_uart_f : clk_a1` | SINK=1 快速 sink；SINK=0 与 P1 的 `.clk_uart(clk_a1)` 等价 |

**无影响论证**：SINK=0 时 `clk_uart` 就是 `clk_a1` 同一网络；CONTENT/PACING/CAPTURE 为 0 时分别走 P1 原文的 `smp`/slot-free/逐字节 `.dec`。R0 必须逐值复现 P1 4 帧统计，已通过。

## 2. CONTENT（白名单 B）

- `CONTENT=0`：`drive_frame` 内像素与 P1 完全相同（`smp` 函数、y=0..ROI_Y+H-1、g=0..CG-1、`tap_pix` 位序不变）。
- `CONTENT=1`：`raw_mem[0:518399]`（1920×1080 / 480 组每行）由 `sim/caps/comp_raw.hex` 通过 `$readmemh` 载入；ROI 组 `(y-ROI_Y, g-GX)` 直接输出；非 ROI 组输出 0（几何仍为每行 966 个 valid 组）。
- **为什么不是把 in.hex 直接当像素**：冻结 comp 向量 `in.hex` 是 **transform-domain** 字节（32×4800 B，A1 PREP/PRED 后的域）。链上 `camera_a1_uart_top` 的 `PREP_EN=PRED_EN=1`，若直接把 in.hex 当 raw 像素，DUT 会再做一次差分，核看到的就不是该向量，测得的 cycles/B 与冻结 comp 锚点无关。
- 正确处理：`sim/prep_content.py` 用 P1 格式模型 `a1_ref.inverse_frame(tiled,1920,1080,1,1)` 把“按 2 ROI 行块 b→b mod 32 平铺后的向量”逆变换成 packed RAW10 像素；DUT 的正向变换再还原出同一向量。字节级双向验证：
  1. Python：`transform_frame(inverse_frame(tiled)) == tiled`，mismatch=0（2,592,000 B）。
  2. TB：帧 1 从 `tap_pix` 按冻结 PREP/PRED 公式重建每个 5 B 组并与 `vec_mem` 比对（`SS_VEC_MATCH`）。
  3. DUT 端到端：R3 导出帧头 `raw_crc/xform_crc/raw_len/xform_len` 与 Python 期望逐值相等、`header_crc` 自洽（`pass=true`）。
- 跨带重复：相同块间距 153,600 B ≫ 核 13-bit（8,192 B）距离窗口；相邻块内容不同，故平铺不引入窗口内新匹配（`out/content-proxy.md`）。

**无影响论证**：raw_mem/vec_mem 只在 `drive_frame` 的 ROI 组选择中读；`CONTENT=0` 时 `$readmemh` 不执行、`raw_mem` 不参与。DUT 端口/参数/几何/DDR 模型均未改。

## 3. PACING（白名单 C）

| 行（近似） | 内容 |
|---|---|
| 245–251 | `task wait_exported(n)`：等 `st_exp >= n`（只读顶层计数） |
| 384–420 | 帧 k≥2 时先 `wait_exported(k-1)` + `SS_PACE frame=k mode=serial`，再 `wait_slot_free`，再 `drive_frame(k)` |

- `PACING=0`：P1 原文——帧 1/2 背靠背，帧 3/4 只等目标 RAW 槽 FREE（overlapped）。
- `PACING=1`：strict-serial 保守对照——下一帧必须等上一帧 `st_exported` 且槽空闲。R2−R1 即“强制串行”的代价。

**无影响论证**：等待循环只读 `st_exp`/`raw_slot_st`，只消耗仿真时间；`PACING=0` 时整段不执行。

## 4. SINK（白名单 D）

- `SINK=0`：`.clk_uart(clk_a1)`，P1 的 18.75 MB/s sim-only sink。
- `SINK=1`：`clk_uart` 为 2 GHz（周期 0.5 ns）→ 请求 200 MB/s（UART_DIV=1，10 cycles/B）。
- **实测口径（round1 修正）**：SINK=1 的 a1 域导出实测为 **2 clk_a1/B = 93.75 MB/s**（R3 tail 1,697,820 / 848,908 B 含 44 B 头；payload-only 93.7449 MB/s；R1/R2 80,160 / 40,034 B），不是 187.5 或 200 MB/s；报告按实测导出率/`export_tail` 给结论，不写 200 MB/s 已达成。
- 该 2 GHz 时钟只用于仿真；不声称 CDC/时序/真实 UART 可行。`dbg_byte_valid` 在 `uart_clk` 域产生，故捕获块改到 `posedge clk_uart`（SINK=0 时与 P1 的 `posedge clk_a1` 等价）。

**无影响论证**：DUT 源未改；仅 TB 提供不同 `clk_uart` 频率。R1 的 `S_ss` 与 R0 差 4 cycles（0.0001%），证明常数 tail 在帧间差中抵消。

## 5. CAPTURE（白名单 E）

- `CAPTURE=1`：P1 逐字节 `.dec`（`%02x\n`；P1 为 `%0d\n`，只是文本格式，字节计数与内容不变）。**round1 D2 白名单允许 `%02x`；P3 不与 P1 `.dec` 做逐字节比较。**
- `CAPTURE=0`：comp-like 不写逐字节 `.dec`；只把导出流的**前 256 B** 写入 `+HDR=` 文件并继续计数（`cap_bytes`）。前 44 B 即第 1 帧头，用于 DUT 端到端 CRC 自检。**round1 D2 白名单允许 `+HDR` 256 B（header CRC 必需）。**

**无影响论证**：只影响 TB 的 `$fwrite` 目标/文本；`cap_bytes` 仍按同一 `dbg_byte_valid` 计数。R0 的 `cap_bytes=160312` 逐值复现 P1。

## 6. 事件/统计/路径（白名单 F/G/H）

- `SS_EVT` 六类事件、`SS_META`、`SS_PACE`、`SS_STATS` 协议与 P1 相同；`SS_META` 末尾追加 `content/pacing/sink/capture`，`SS_STATS` 末尾追加 `content/pacing/sink/capture/vec_bad/vec_checked/drv_groups`；b11 前 16 字段顺序与数值不变（R0 已验证）。**round1 D2 白名单允许这些追加字段与 `SS_MODE`。**
- 新增 `SS_MODE`、`SS_VEC_MATCH bad=... checked=... drv_groups=...` 标记（已在此声明）。
- 路径寄存器 `[4095:0]` 与 P1 相同；`+STAT/+EVT/+DEC/+HDR/+RAW/+VEC` 全部绝对路径。
- 继承的 `B11_FULL_READ_DONE` 等待仍为 P1 原文 `2*129600`（仅信息标记）。

**无影响论证**：全部只读打印/文件位置；无 `force/deposit/release`，无对 `st_*`、`exported`、`wd_fires` 的写操作。

## 7. 字节级自检（白名单 G）与已知修正

- 帧 1 每 4 个同平面样本组成 1 个 40-bit 组：`{d3[1:0],d2[1:0],d1[1:0],d0[1:0],d3[9:2],d2[9:2],d1[9:2],d0[9:2]}`，与 `a1_ref.pack_samples`/`a1_frame_top` 的 `eb` 位序一致；索引 `(block mod 32)*960 + plane*240 + q`。
- **R0–R3 版本的差一错误**：原实现 `vn = vn + 1; if (vn == 3)` 在第 3 个样本（而非第 4 个）触发比较，导致每平面 320 而非 240 组、`checked=691,200` 且比对错位；R3 日志因此打印 `bad=691132`。这是 TB 本地只读自检的计数 bug，不影响任何 DUT 输入。
- **修正**：比较条件改为 `vn == 0`（2-bit 自然回绕，即每 4 个样本一次）。`v1` check-only 复跑（同一 raw/vec 文件，2,000,000 cycles 截断）给出 `SS_VEC_MATCH bad=0 checked=518400 drv_groups=518400`。该自检只读 `tap_pix/raw_mem/vec_mem`，不驱动任何 DUT 信号，因此对 R0–R3 的 DUT 行为无影响。
- R3 的内容等价性另有更强的 DUT 端到端证据：导出帧头 `xform_crc=3038348232`、`raw_crc=3613527589` 与 Python 期望逐值相等。

## 8. 明确未改项

- DUT 端口/参数/时钟（除 TB 提供的 `clk_uart` 频率）/复位/几何/`LINE_GAP=16`/`FRAME_GAP=400`/`UART_DIV=1`/DDR 模型 `#(.WORDS(524288),.AR_GAP(2),.R_GAP(3))` 全部未改。
- 12 个 DUT/模型源与 b11/P1 manifest 逐字节相同；**P3 未复制、未编译 `p2_a1_board_top.v`**（板级 top 缺依赖；manifest/input-verified 只登记 12 源）。
- 未改生产源码、P1/P2 冻结件、b11/b6/T08/T10、`workflow/tasks.json`、`docs`、`.agents`。

## 9. round1 归档、白名单与 F5–F8（2026-10-26）

- **旧 TB 归档**：R0–R2 使用的 TB `89948303be78da2b4e2cbccbb70935d26825b518620c679ba9d959d3c950008e`（23,894 B）已复制到 `src/legacy/tb_ss_g0_89948303.v` 并加入 `manifest-r1.json` artifacts。
- **精确 diff（旧→冻结 `a565c6f2…`，24,118 B）**：4 行 `if (vn0/1/2/3 == 2'd3)` → `2'd0`（字节级自检每 3 个样本分组一次的差一修正）；帧 1 `drive_frame(1)` 后新增一条 `SS_VEC_MATCH` 早打印（及 `$fwrite` 到 evt）。**无 DUT 驱动/端口/几何/时钟/复位/内容映射改动。**
- **R0–R2 TB-only 等价论证**：`CONTENT=0` 时自检段整段不执行、早打印只读；测试者用冻结 TB 独立重跑 R0，`stats`/`.dec` 与候选逐字节相同（881.5 s，0 Errors）。规划 D1 书面接受 R0–R2 timing 复用。
- **R3 重跑**：G0 run 用冻结 TB 重跑（`sim/logs/r3_frozen.log`、`sim/caps/r3_frozen.{stats,hdr,evt}`），同一 run 打印 `SS_VEC_MATCH bad=0 checked=518400 drv_groups=518400`（帧 1 早打印）与 `bad=0 checked=518400 drv_groups=2073600`（全 4 帧末打印）；旧 TB 的 r3 只作历史证据。
- **F7**：G0 表 A1 overlapped 取 R1 `4,677,531`，比 P1 A1 `4,677,535` 低 4 cycles（0.0001%），已在 `source` 列与报告注明。
- **F8（round2 修正）**：`sim/_repair.py` 是 round0 一次性编码修复脚本，已从 manifest 排除并在 notes 说明；**P3 未复制、未编译 `p2_a1_board_top.v`**；round0 的“只复制/哈希”表述已删除，与实际 copied/hashed 清单一致。
- **F5**：R4 触发条件（R2−R1=36.09% > 1%）已满足，但 90-min 墙钟到顶未跑；serial comp 只写 `assumed = 7,616,377.5`，不得称 strict-serial 过 G0。
- **F6**：v1 三次 check-only 曾复用同一日志名；round1 起新日志使用独立名（`r3_frozen.*`），最终 v1 证据保留 `sim/logs/v1.log`，历史 argv/rc/耗时保留在 `sim/commands.jsonl`。
- **round1 D2 白名单**：`WD_LIMIT 12M`、`%02x` `.dec`、`+HDR` 256 B、`SS_META/SS_STATS` 追加字段与 `SS_MODE`、帧 1 早打印与分组修正均获规划书面允许；DUT 驱动/几何/时钟/复位/内容映射仍禁止改动。
