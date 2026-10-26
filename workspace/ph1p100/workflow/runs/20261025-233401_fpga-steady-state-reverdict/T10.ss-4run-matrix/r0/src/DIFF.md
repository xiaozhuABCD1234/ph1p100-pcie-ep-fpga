# src/DIFF.md — `tb_ss_4run.v` 相对 P3 `tb_ss_g0.v` 的允许差异

- 基线（只读）：`src/ref/tb_ss_g0.v`，SHA256 `a565c6f25f5d8ac16ce8dd8042f35395c6018a23d1093448077b0e90b79bd3d0`（24,118 B，P3 r2 冻结件）。
- P3 自身相对 P1 的白名单差异见 `src/ref/DIFF-P3.md`（SHA256 `d2c9f5c9cb0ad2da85c410c37e81b8c6fa2e71bf906bdd3f6642c7ac17789664`）；本文件只列 **P3→P4** 的增量。
- 派生 TB：`src/tb_ss_4run.v`（25,593 B，SHA256 `7f5cc29405001e4a5da868e8129819e0068715965999c7e81082e38e20947f81`）。
- **12 个 DUT/模型源与 P1 manifest 逐字节相同**（`input-verified.json`：`copied_src_mismatch=[]`，0 mismatch）；本文件不改任何 DUT 行，未复制/未编译 `p2_a1_board_top.v`。
- 允许来源：dev-plan §11.4 的 ①CONTENT 扩展 ②RAWFILE plusarg ③PACING ④SINK ⑤CAPTURE ⑥MAX_CYCLES ⑦事件/自检 ⑧独立路径/日志名。第 ⑨ 项 `raw_bad/raw_checked` 是 ⑦ `SS_STATS` 追加字段的一部分。

## 1. 模块名与头注释

| 位置 | 内容 | 原因 |
|---|---|---|
| 第 1–19 行 | `tb_ss_g0.v` → `tb_ss_4run.v`；模块名 `tb_ss_g0` → `tb_ss_4run`；头注释改为 P3 派生血统 | 新任务独立 TB，避免与 P3 冻结文件同名 |
| 参数 `CONTENT` | 注释扩展为 0=smp、1=comp、2=C1 raw40、3=C2 raw40 | dev-plan §11.4-① |

**无影响论证**：仅名称/注释；DUT 实例、参数、端口、几何、时钟、复位全部保持 P3 原文。

## 2. CONTENT=2/3 全帧 raw 映射（白名单 ①，§11.4-①）

- 新增分支：`CONTENT >= 2` 时 `raw_mem[0:518399]` 由 `+RAW40=<file>` 通过 `$readmemh` 载入（518,400 行 40-bit `{b4,b3,b2,b1,b0}`）。
- 驱动：`idx = (y-ROI_Y)*480 + (g-GX)`；ROI 组输出 `tap_pix`，非 ROI 组输出 `40'd0`；几何仍为 CAM 3864×2192 / ROI 972/556 / 每行 966 个 valid 组。
- **bit 顺序**：`b0..b3 = p0..p3[9:2]`，`b4 = {p3[1:0],p2[1:0],p1[1:0],p0[1:0]}`，与 `a1_ref.pack_samples` 和 P1 TB `smp()` 的 `tap_pix` 拼接完全一致；40-bit 组按 `{b4,b3,b2,b1,b0}` 载入。
- 与 P3 `CONTENT=1` 共用同一 `raw_mem`/`idx` 结构；区别只是数据来源与自检类型。

**无影响论证**：`CONTENT=0/1` 时 `$readmemh` 不执行该文件、`raw_mem` 读取路径与 P3 逐行相同；`CONTENT=2/3` 只改变 TB 产生的 `tap_pix` 数据源，DUT 端口/参数/几何/时钟/复位/`LINE_GAP`/`FRAME_GAP` 未改。

## 3. 字节级 raw 自检 `SS_RAW_MATCH`（白名单 ⑦，§11.4-⑦）

- 帧 1 对每个 ROI 组：从 `tap_pix` 拆出 `b0..b4`，按 §2 的位序展开为 4 个 10-bit 样本，再按同一规则重新打包为 `rg2`；`tap_pix = rg2` 驱动 DUT。
- `if (rg2 !== raw_mem[idx]) raw_bad++`；`if (tap_pix !== raw_mem[idx]) raw_bad++`；`raw_checked++`。
- 打印 `SS_RAW_MATCH bad=... checked=... drv_groups=...`（帧 1 后与 4 帧末各一次），并追加到 `+EVT` 文件。
- 该检查证明：位序展开/重打包与冻结 packing 一致、ROI 组恰好覆盖 518,400 组且索引正确、40-bit 总线无截断；**不单独证明源文件本身**。源文件完整性由两条独立证据证明：
  1. `sim/prep_content.py`：`raw.bin → raw40.hex → 逐字节解码`，C1/C2 mismatch 均为 0；
  2. DUT 导出帧头：`raw_len=2,592,000`、`raw_crc = zlib.crc32(raw.bin)`、`xform_crc = crc32(transform_frame(raw.bin))` 逐值相等（R1/R2/R3 均 `header_pass=true`，见 `out/runs.json` 的 `header_check`）。

**无影响论证**：自检代码只在 `CONTENT>=2 && k==1` 时读 `tap_pix/raw_mem`，不写任何 DUT 信号；`SS_RAW_MATCH` 只是打印/计数。

## 4. 统计行/事件追加（白名单 ⑦）

- `SS_META`/`SS_STATS`/`SS_MODE`/`SS_EVT`/`SS_PACE` 协议不变；`SS_STATS` 在 P3 追加字段之后再加 `raw_bad=%0d raw_checked=%0d`。
- b11 前 **16** 字段顺序与数值不变；P3 的 `content/pacing/sink/capture/vec_bad/vec_checked/drv_groups` 顺序不变。
- `CONTENT=0/1` 时 `raw_bad=0 raw_checked=0`，不影响 P3 已有字段。

**无影响论证**：全部为只读打印/文件写入。

## 5. 未改项（逐项声明）

- DUT 端口/参数/内部逻辑：0 修改；12 源与 P1 manifest 逐字节相同。
- 几何：`CAM_W=3864, CAM_H=2192, ROI_X=972, ROI_Y=556, W=1920, H=1080`；`LINE_GAP=16`、`FRAME_GAP=400`、`UART_DIV=1`。
- 时钟：`clk_cam=187.5 MHz`、`clk_a1=187.5 MHz`、`clk_ddr=200 MHz`；`SINK=0/1` 的 `clk_uart` 选择与 P3 相同。
- 复位：释放前 20 / 释放后 40 个 `clk_a1`，与 P3 相同。
- `PACING`：slot-free（P1）与 strict-serial 的实现与 P3 逐行相同——本任务未改 pacing 逻辑。
- `CAPTURE`：`1` 逐字节 `.dec`（`%02x`）、`0` 只在 `+HDR` 写前 256 B；与 P3 相同。
- `MAX_CYCLES=48,000,000`、`WD_LIMIT=12,000,000`、`ss_pass` 判据、`wait_slot_free`/`wait_exported`、继承的 `B11_FULL_READ_DONE` 等待均与 P3 相同。
- DDR 模型：`p2_paxi_model_b11 #(.WORDS(524288), .AR_GAP(2), .R_GAP(3))`，未改。
- 无 `force/deposit/release`，无对 `st_*`/`exported`/`wd_fires` 的写操作。

## 6. 运行配置（本任务实际使用）

| run | CONTENT | PACING | SINK | CAPTURE | plusarg |
|---|---|---|---|---|---|
| R1 | 2 (C1 raw40) | 0 slot-free | 1 | 0 (+HDR) | `+RAW40=content/raw40_p1d1.hex` |
| R2 | 2 (C1 raw40) | 1 strict-serial | 1 | 0 | `+RAW40=content/raw40_p1d1.hex` |
| R3 | 3 (C2 raw40) | 0 slot-free | 1 | 0 | `+RAW40=content/raw40_rand.hex` |
| R4 | 1 (comp proxy) | 0 slot-free | 1 | 0 | `+RAW=content/comp_raw.hex +VEC=content/comp_vec.hex` |

- 运行前额外做了一次 **非全尺寸** 预检（`CONTENT=2, FRAMES=1, MAX_CYCLES=2,000,000`，86 s），只用于确认 raw 路径/自检，不参与四轮矩阵计数。
- Paths/logs：`+STAT/+EVT/+HDR` 均为本任务 `sim/caps/` 下独立文件名；工作库/INI/日志独占 `%TEMP%\opencode\ss-4run\`。
