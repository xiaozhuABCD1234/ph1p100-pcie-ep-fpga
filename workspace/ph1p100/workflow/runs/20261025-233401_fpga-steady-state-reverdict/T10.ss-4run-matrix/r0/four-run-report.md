# P4 四轮稳态矩阵报告（`T10.ss-4run-matrix` r0）

- run：`20261025-233401_fpga-steady-state-reverdict`；任务：`T10.ss-4run-matrix`；日期：2026-10-26
- 状态：`ready_for_test`；`stopped_modifying=true`；`active_commands=0`
- 数据面：4 个全尺寸 4 帧 run（R1–R4），同一冻结 RTL、同一几何、同一 TB 血统；R4 与 P3 R3 逐值复现
- **Headline：`G0_feasible_for_scope`**（C1 全帧 raw slot-free + P3 comp proxy）；C2 raw-band 为 `G0_not_proven`（sink-limited）；C1 strict-serial 为 `G0_not_closed`（−3.09%）。G25 仅参考列，不降档。

## 1. 结论摘要

| 问题 | 本轮实测答案 |
|---|---|
| C1 全帧 raw（可压缩）slot-free 是否过 G0？ | **过**：`S_ss=4,677,970`、`C=103.8912 MB/s`、G0 `+33.6050%`（G25 参考 `+6.8840%`） |
| C1 strict-serial 的 pacing 代价？ | `R2−R1=1,771,435 cycles`（R1 的 **37.865%**）；R2 `S_ss=6,449,405` → G0 **−3.0918%**（`G0_not_closed`） |
| C2 不可压缩 raw 的 sink 压力？ | `tail=5,700,448`（`S_ss` 的 **109.85%**）、`sink_limited=true`、实测导出 **93.748 MB/s**；`S_ss=5,189,503` 只是 sink 服务间隔，**不判 G0** → `G0_not_proven` |
| R4 是否复现 P3 R3？ | **逐值复现**：`S_ss=5,928,286`（delta **0 cycles**，band `[5,928,283, 5,928,289]`）、`exp_bytes=3,395,456`、`cycles=27,020,950` 与 P3 `r3_frozen.stats` 相同；`SS_VEC_MATCH bad=0 checked=518400`、header CRC `pass=true` |
| 单帧冷延迟 vs 稳态 | R1 `L_cold=6,449,446` 比 `S_ss` 高 **37.87%**；用 `L_cold` 当吞吐只有 75.36 MB/s（<77.76），再次证明冷延迟不可当 `S_ss` |
| 93.75 MB/s sink 是否等于生产 sink？ | **不是**。冻结 TB 上限 93.75 MB/s（2 `clk_a1`/B）；raw band 生产需求 ≥**77.84 MB/s**（G0，33.3 ms）/**≥103.79 MB/s**（25 ms/tail 稳健），93.75 **不能**当作 ≥103.79 |

## 2. 方法与可复现性

### 2.1 TB 派生与冻结

- 基线：P3 冻结 TB `src/ref/tb_ss_g0.v`，SHA256 `a565c6f2…bd3d0`（24,118 B）。
- 派生：`src/tb_ss_4run.v`，SHA256 `7f5cc294…7f81`（25,593 B）；增量仅 CONTENT 2/3、`+RAW40`、`SS_RAW_MATCH`、`raw_bad/raw_checked` 追加（见 `src/DIFF.md`）。
- 12 个 DUT/模型源与 P1 manifest 逐字节相同（`input-verified.json`：`copied_src_mismatch=[]`）；DUT 0 修改；`p2_a1_board_top.v` 未复制/未编译。
- 独立工作库/INI/日志：`%TEMP%\opencode\ss-4run\`；全尺寸 vsim 4 次，单次硬超时 2700 s。

### 2.2 内容（全部为合成/代理，不是自然图像）

| id | 源 | 几何/格式 | 每帧导出 | 标签 |
|---|---|---|---:|---|
| C1 | P3 上游包 `f1080p_p1d1/raw.bin`（`061b0dfc…f8d`） | 1920×1080 packed RAW10，518,400×5 B | 81,707 B（31.7:1） | `full_frame_raw_synthetic` / `proxy_not_natural` / `proxy_not_worst` |
| C2 | 同 run `f1080p_rand/raw.bin`（`8fe204b7…ad5`） | 同上 | 2,594,706 B（stored，0.999:1） | 同上 |
| C3–C7 | P3 `in.hex`/`in.meta`/`in.xform`/`comp_raw.hex`/`comp_vec.hex` | 32×4800 B transform-domain comp 向量 | 848,864 B（3.05:1） | `proxy_not_natural` / `proxy_not_worst` |

- Python：`raw.bin → raw40_{p1d1,rand}.hex`（518,400 行 × 40-bit `{b4,b3,b2,b1,b0}`），每行 SHA 与字节均记录；解码回 `raw.bin` mismatch **0**（C1/C2），模型正/逆变换 round-trip mismatch **0**；文件 SHA 见 `out/content-map.json`。
- TB：`SS_RAW_MATCH bad=0 checked=518400`（R1/R2/R3 同 run）；`SS_VEC_MATCH bad=0 checked=518400`（R4 同 run）。
- **端到端更强证据**：DUT 导出帧头与 Python 期望逐值相等（R1/R2：`raw_crc=1,020,842,313`、`xform_crc=2,646,913,462`、`raw_len=xform_len=2,592,000`；R3：`raw_crc=237,020,219`、`xform_crc=2,461,842,624`；R4：`raw_crc=3,613,527,589`、`xform_crc=3,038,348,232`），`header_crc` 自洽。

### 2.3 四轮配置（4 个不同条件）

| run | content | pacing | sink | capture | 目的 |
|---|---|---|---|---|---|
| R1 | C1 raw40 | slot-free | SINK=1 | 0 (+HDR) | 全帧 raw 生产路径；G0 |
| R2 | C1 raw40（同 R1） | strict-serial | SINK=1 | 0 | pacing 代价；R2−R1 |
| R3 | C2 raw40 | slot-free | SINK=1 | 0 | 不可压缩 raw 的 sink 压力 |
| R4 | C3–C7 comp | slot-free | SINK=1 | 0 | P3 对照/复现性 |

> R1/R2 同内容同 sink，才可把差值归因于 pacing；R4 与 P3 R3 同为 comp proxy/slot-free/SINK=1/CAPTURE=0。

## 3. 四轮结果

### 3.1 主表（`out/four-run-table.csv`）

| row | content | pacing | `S_ss` | band | `L_cold` | tail mean | tail/`S_ss` | sink-limited | `C_ss` MB/s | G0 margin | G25 ref | G0 |
|---|---|---|---:|---|---:|---:|---:|---|---:|---:|---:|---|
| **R1** | C1 | slot-free | **4,677,970** | 4,677,973 / 4,677,967 | 6,449,446 | 163,506 | 3.50% | false | 103.8912 | **+33.6050%** | +6.8840% | `G0_feasible_for_scope` |
| **R2** | C1 | strict-serial | **6,449,405** | 6,449,404 / 6,449,406 | 6,449,446 | 163,506 | 2.54% | false | 75.3558 | **−3.0918%** | −22.4735% | `G0_not_closed` |
| **R3** | C2 | slot-free | **5,189,503** | 5,189,503 / 5,189,503 | 11,476,032 | 5,700,448 | **109.85%** | **true** | 93.6506* | +20.4354%* | −3.6517%* | `G0_not_proven` |
| **R4** | comp | slot-free | **5,928,286** | 5,928,283 / 5,928,289 | 9,234,076 | 1,697,820 | 28.64% | false | 81.9799 | +5.4268% | −15.6586% | `G0_feasible_for_scope` |
| P3 对照 | comp | slot-free | 5,928,286 | — | 9,234,076 | 1,697,820 | 28.64% | false | 81.9799 | +5.4268% | −15.6586% | （P3 `G0_feasible_for_scope`） |

\* R3 的 `C_ss=93.6506` 是按 raw 2,592,000 B/帧折算的链路容量等价（`4.86e8/S_ss`）；按实际导出流 2,594,706 B/帧计，sink 服务率为 **93.748 MB/s**。两者都只是 **sink 服务率**，不是 DUT 服务能力；`tail/ S_ss > 100%` 是两 CMP 槽流水（`t_enc(k)` 早于 `t_exp(k-1)`）造成的等待，不是负 tail。按冻结规则 tail > 50% → `sink_limited`，不得作为 G0 证据。

### 3.2 计数/有效性（全部 4 run）

`cap=4 enc=4 exported=4 read=518400`；`raw_drop=cmp_drop=dup=geom=err=wd=0`；`ss_pass=1`、`B11_FULL_RESULT pass=1`；`SS_RAW_MATCH`/`SS_VEC_MATCH bad=0`；`header_pass=true`、`header_crc_ok=true`。R1/R3/R4 的 V4（相机不排队）为 true、`capacity_is_lower_bound=false`；R2 为 strict-serial by construction（V4 不适用）。

### 3.3 预算

| run | vsim 墙钟 |
|---|---:|
| R1 | 940.4 s |
| R2 | 1,087.5 s |
| R3 | 1,383.6 s |
| R4 | 1,330.0 s |
| 合计 | **4,741.5 s = 79.0 min**（≤120 min；全尺寸 4/5） |
| 预检（非全尺寸，FRAMES=1 / 2M cycles） | 86 s |

## 4. 因子分析

### 4.1 content（C1 vs comp vs C2）

- C1 全帧 raw 是**高度可压缩**的合成梯度（81,707 B/帧，31.7:1），链上 `S_ss=4.678M`，与 P1 的 smp 梯度 `4.6775M` 几乎相同（+435 cycles，0.009%）→ 在这类内容上 core/链时间对压缩后大小不敏感。
- comp proxy（848,864 B/帧，3.05:1）`S_ss=5.928M`，比 C1 慢 **1,250,316 cycles（+26.7%）**；这说明 content anchor 对 G0 结论有实质影响，不能把 C1 的 +33.6% 外推到 comp/自然图像。
- C2（stored，2,594,706 B/帧）链时间由 **sink 导出**支配（见 4.3），不是 core 能力。

### 4.2 pacing（R2−R1）

- `R2−R1 = 1,771,435 cycles`（R1 的 **37.865%**，R2 的 27.466%），把 C1 的 G0 从 **+33.60%** 拉到 **−3.09%**（差 199,405 cycles，3.0918%）。
- 该差值**不是纯 tail**：strict-serial 在上一帧 `st_exported` 后才开始下一帧相机驱动，因此还包含约 1.61M cycles 的相机串行化；报告将其标为 pacing penalty 的**上界**，不声称纯 tail 成本。R1 的 tail 仅 163,506 cycles（3.5%），说明 slot-free 已把 tail 隐藏。
- R2 的 `S_2`/`S_23`/`S_34`（6,449,404/4/6）一致，R2 自身是稳态；它的失败是**口径**（strict-serial 保守）而非不稳定。

### 4.3 sink（R3 与 93.75 MB/s 上限）

- 冻结 TB 的导出实测为 **2 `clk_a1`/B = 93.75 MB/s**（R1/R2/R4 的 `measured_export_MBps` 为 93.697/93.697/93.745）；这是 `a1_uart_export` 的 holding-register 交接上限，SINK=1 的 2 GHz 请求也只能到 93.75。
- R3：每帧 2,594,706 B → 串行导出 **5,189,412 cycles = 27.68 ms**（33.33 ms 的 **83.0%**）；实测 `S_ss=5,189,503` 与导出时间几乎相等（+91 cycles），说明 sink 连续饱和，`tail` 包含等待上一帧导出的 5.70M cycles（109.85% `S_ss`）。
- 口径说明：`C_ss=93.6506` 用 raw 2,592,000 B/帧折算；按实际导出流 2,594,706 B/帧计，sink 服务率为 93.748 MB/s；二者都只描述 sink，不描述 DUT 服务能力。
- 按规划规则（tail > 50% → sink-limited；sink-limited 值不得当 G0 证据）：R3 = **`G0_not_proven`**。其 `S_ss=5,189,503`（算术上 <6.25M）只代表 93.65 MB/s 的 sink 服务率，不代表 DUT 容量。
- **生产 sink 需求（单列，不用 93.75 冒充）**：raw band 2,594,750 B/帧 → **≥77.84 MB/s**（G0/33.33 ms）/ **≥103.79 MB/s**（25 ms/tail 稳健）。93.75 < 103.79，因此冻结 TB 无法做“同内容 + ≥103.79”的生产级 sink 实验；严格条件保持 `not_proven`，需新 TB/导出 RTL/PCIe（超出 P4 白名单）。
- R4 的 comp 内容 848,864 B/帧 → 导出 1,697,728 cycles = 9.05 ms（33.3 ms 的 27.2%），tail 1,697,820（28.64%）< 50%，`sink_limited=false`，93.75 MB/s 对 proxy 足够。

### 4.4 R4 对照与 TB 可信度

- R4 的 `S_ss=5,928,286` 与 P3 R3 **0 cycles 差**；`S_2/S_23/S_34` band 6 cycles、`exp_bytes=3,395,456`、`cycles=27,020,950`、`SS_VEC_MATCH bad=0 checked=518400`、header CRC 全部一致。
- 结论：P4 派生 TB 对 comp 路径与 P3 冻结 TB 行为等价；R4 作为新 TB 的 trust anchor 通过（±0.5% 门槛远未触边）。

## 5. G0 判定与 headline

| run | 内容 | 判定 | 依据 |
|---|---|---|---|
| R1 | C1 full-frame raw（slot-free） | **`G0_feasible_for_scope`** | `4,677,970 ≤ 6,250,000`；`+33.6050%` |
| R2 | C1 strict-serial | `G0_not_closed` | `6,449,405 > 6,250,000`；gap 199,405（−3.0918%）；保守 pacing 视图 |
| R3 | C2 rand raw band | `G0_not_proven` | sink-limited（tail 109.85%）；sink-limited `S_ss` 不是 G0 证据；生产 sink ≥103.79 未做 |
| R4 | comp proxy | `G0_feasible_for_scope` | `5,928,286 ≤ 6,250,000`；`+5.4268%`；复现 P3 R3 |

**Headline：`G0_feasible_for_scope`**，scope 必须写全：

- per-stream 1080p30；C1 = 全帧合成 packed RAW10（`full_frame_raw_synthetic`，非自然、非最坏）+ slot-free + 实测 93.75 MB/s sim sink；
- comp proxy = 848,864 B/帧 transform-domain 代理（`proxy_not_worst`，非全内容）；
- C2 raw band = `G0_not_proven`（sink-limited；生产 sink 需求 ≥77.84/103.79 MB/s 单列）；
- strict-serial R2 = 保守 pacing 视图，不用于 slot-free 结论；
- 行为级 256-bit PAXI（无 MC/刷新/争用）、单核/单路、187.5 MHz；
- **不外推**自然图像/低照/噪声/全内容/双路/板级/真实 DDR/真实 UART/PCIe/RK。

G25 仅参考：R1 `+6.8840%`、R4 `−15.6586%`、R2 `−22.4735%`、R3 `−3.6517%`。**没有**因 G25 做任何降档；也没有用 aggregate 2C（见负对照）。

## 6. 负对照（`out/negative-controls.json`，8/8 拒绝）

| id | 名称 | 结果 |
|---|---|---|
| NEG-01 | `RAW_AS_NATURAL` | 拒绝：C1/C2 是合成全帧 RAW，不是自然图像 |
| NEG-02 | `RAW_AS_WORST` | 拒绝：C2 是 stored/不可压缩 raw，但不是全内容最坏证明 |
| NEG-03 | `SINK_LIMITED_AS_G0` | 拒绝：R3 `S_ss=5,189,503` 算术过线，但 tail 109.85% → `G0_not_proven` |
| NEG-04 | `SERIAL_AS_OVERLAP` | 拒绝：R2−R1=1,771,435，serial 只进 serial 列 |
| NEG-05 | `COLD_LATENCY_AS_THROUGHPUT` | 拒绝：R1 `L_cold=6,449,446` → 75.355 MB/s < 77.76 |
| NEG-06 | `G25_DOWNGRADE` | 拒绝：G25 仅参考，未降档 |
| NEG-07 | `AGGREGATE_2C` | 拒绝：R1 c1s2 aggregate 103.891 过线而 per-stream 51.946 不过 |
| NEG-08 | `CONTENT_MAP_MISMATCH` | 拒绝：TB `bad=0`；Python raw→hex→bytes mismatch C1/C2 均为 0 |

## 7. 差距菜单（`out/gap-menu.csv` 摘要）

| id | 路径 | 证据/量 | 状态 |
|---|---|---|---|
| M1 | tail overlap（slot-free） | R2−R1=1,771,435（上界） | 已实现 |
| M2 | core cycles −171,414（2.859%） | A2 6,421,414→6,250,000 | 未实施 |
| M3 | clock 192.642 MHz（G0） | +2.74% vs 187.5 | 未实施/TD 未做 |
| M4 | 组合 | 需逐项验证 | 未实施 |
| M5 | 生产 sink ≥77.84/≥103.79 MB/s | 93.75 上限不足 103.79 | 未实施（新 TB/RTL） |
| M6 | 自然/低照/最坏内容语料 | 无自然语料 | 未实施 |

## 8. 边界与未证项

- **内容**：C1/C2 是合成的全帧 packed RAW10（分别高度可压缩/不可压缩）；comp 是 transform-domain 代理；**没有自然图像/低照/噪声/最坏内容**，所有结论只对应 `full_frame_raw_synthetic`/`proxy_not_worst`。
- **sink**：93.75 MB/s 是仿真上限；真实 115200 UART 只有 11,520 B/s；生产路径（PCIe/高速 sink）与 ≥103.79 MB/s 未做，`transport=not_proven`。
- **DDR**：`p2_paxi_model_b11` 是行为级 256-bit 单拍模型，无 MC/刷新/行切换/多客户争用；DDR sustained 未证。
- **实现**：单核、单路、187.5 MHz；无 TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK；双核共享 PAXI、Routed 时序、资源余量仍 `unproven`。
- **pacing**：R2 是 strict-serial 保守对照，其差值含相机串行化，不是纯 tail 成本；生产 slot-free 实现未做 RTL 改动。
- **R3**：`tail > S_ss` 是 2 CMP 槽流水等待，不是负 tail；其 `S_ss` 不能作为 DUT 服务能力。

## 9. 证据文件

- `input-verified.json`：P1/P2/P3 manifest、P3 TB/DIFF、7 个内容源 SHA；12 DUT 源 0 mismatch；prepared raw40 SHA
- `out/content-map.json`：内容几何/packing/映射/SHA/CRC/round-trip
- `out/runs-4.csv`、`out/four-run-table.csv`：逐 run 与四轮表
- `out/g0-verdict.json`、`out/negative-controls.json`、`out/gap-menu.csv`
- `sim/caps/{r1..r4}.{stats,evt,hdr}`、`sim/logs/{r1..r4}.log`、`sim/commands.jsonl`
- `sim/prep_content.py`、`sim/run_4run.py`、`src/tb_ss_4run.v`、`src/DIFF.md`
- `result-r0.md`、`lessons.md`、`manifest-r0.json`
