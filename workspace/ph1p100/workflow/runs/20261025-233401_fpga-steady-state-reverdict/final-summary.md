# 最终总结：1080p30 G0 收口 + 四轮矩阵（`20261025-233401_fpga-steady-state-reverdict`，finished）

- 结论一句话：**在“C1 全帧合成 packed RAW10 或 P3 comp 代理 + slot-free + 93.75 MB/s sim sink + 行为 DDR + 单核 187.5 MHz + per-stream”范围内，1080p30 G0 硬门槛通过：R1 4,677,970 cycles（103.891 MB/s、G0 +33.605%）、R4 5,928,286 cycles（81.980 MB/s、G0 +5.427%）。** strict-serial 不通过（R2 6,449,405、G0 −3.092%）；不可压缩 raw band 被 93.75 MB/s sink 限速（R3 tail 109.85%、`G0_not_proven`）。自然图像/全内容/最坏/双路/板级仍未证。
- 用户边界：**G0（77.76 MB/s ↔ `S_ss ≤ 6,250,000` @187.5 MHz）硬门槛；G25（97.20 MB/s）仅参考、不降档**；目标 1080p30。
- 范围：FPGA 侧离线仿真/模型/报告；0 次 TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK/PCIe。
- 四个包：P1/P2/P3/P4 均 PASS；P3 实际修复 2 轮，P4 r0 一轮 PASS。

## 1. 目标与最终状态

| 包 | 任务 | 结果 |
|---|---|---|
| P1 | `T10.ss-steady-anchor` | r0 PASS；4 帧 `L_cold=6,766,434`、`S_ss=4,677,535`；A1=103.9009 MB/s |
| P2 | `T10.ss-verdict-r1` | r0 PASS；上轮 `infeasible` 降级 `not_proven`；G0/G25 分列、A1/A2/A3、DDR/UART、C1–C9 |
| P3 | `T10.ss-g0-closure` | r0 FAIL→r1 FAIL(metadata)→r2 PASS；comp proxy 5,928,286 → G0 +5.427% |
| P4 | `T10.ss-4run-matrix` | **r0 PASS**；四轮矩阵：C1 slot-free 4,677,970（+33.605%）、C1 strict 6,449,405（−3.092%）、C2 rand 5,189,503（sink-limited → `G0_not_proven`）、comp 5,928,286（+5.427%，复现 P3 Δ=0） |

## 2. P1：单帧延迟 vs 稳态

| 量 | 值 | 标签 |
|---|---:|---|
| `L_cold` / `L_frame` | 6,766,434 / 6,766,393 | measured |
| `S_ss` | **4,677,535**（band 0.00%） | measured |
| `C_ss` / `fps` | **103.9009 MB/s / 40.0852** | derived |
| G0 / G25 | **+33.6174% / +6.8939%** | derived |
| `export_tail` | 480,930×4；`sink_limited=false` | measured |
| `startup_pct` | 44.66% | derived |

b6 的 6,421,414 是冷启动单帧，不是每帧稳态；A1 单内容/单几何/18.75 MB/s sim sink/行为 DDR/per-stream，不外推。

## 3. P2：上轮 `infeasible` 的撤回/降级

- **撤回**：6,421,414 当吞吐（75.6843 / 29.199 / −2.6694%）；0%/25% 合判；1080p 排除 overhead 三档；6,400 作 1333 主口径。
- **降级**：系统级 `1080p30 per-stream` → **`not_proven`**（A1/A2 内容跨界）；A2 行仍 `infeasible`（G0 −2.6694%）。
- A1 **103.9009**（G0 +33.6174%、G25 +6.8939%）；A2 **75.6843**（assumed；comp 核级 81.067 是 core-only，不是 A2 链级；−2.6694%/−22.1355%）；A3 **154.2198**（assumed；+98.33%/+58.66%）；A4=b6 冷延迟 6,421,414，仅参照。
- DDR：**5,332 / 6,400** 双列；主路径 809.034 MB/s、gate 1,011.2925；required_eff **15.1732%/12.6412%**、gate_eff **18.9665%/15.8014%**。
- UART：真实 115200 = **11,520 B/s**（40,032 B→3.475 s，104.25×；2,594,706 B→225.235 s，6,757×）；sim sink 18.75 MB/s（1,628×）；`transport=not_proven`。
- 双核：`c2s2=C`（非 2C）；`assumed_from_single_core` + `paaxi_shared_unproven`；231/289；Routed unproven；永不 feasible。
- C1–C9：P2 `out/corrections.csv` / `verdict-r1.md`。

## 4. P3：comp proxy 的 G0 收口

| run | 内容 | pacing | `S_ss` | 结论 |
|---|---|---|---:|---|
| R0 | smp 梯度 | slot-free | 4,677,535 | 逐值复现 P1 |
| R1 | smp 梯度 | slot-free | 4,677,531 | sink 变快只改 tail |
| R2 | smp 梯度 | strict-serial | 6,365,622.5 | overlap penalty 1,688,091.5（36.09%） |
| R3 | comp proxy | slot-free | **5,928,286** | 81.9799 MB/s；G0 **+5.4268%**；G25 −15.6586% 参考 |
| R4 | comp proxy | strict-serial | 未跑 | assumed 7,616,377.5（63.810 MB/s，G0 −17.94%） |

- R3 tail 1,697,820（28.6%），`sink_limited=false`；同 run `SS_VEC_MATCH bad=0`；header CRC 全对。
- P3 实际修复 **2 轮**（r0 FAIL engineering/G1 → r1 metadata FAIL → r2 PASS）；manifest-r2 `3C8377A4…`（82 artifacts）。

## 5. P4：四轮矩阵（4 个不同条件）

### 5.1 主表

| run | content | pacing | `S_ss` | `L_cold` | tail | sink_limited | `C` / G0 |
|---|---|---|---:|---:|---:|---|---|
| **R1** | C1 `f1080p_p1d1` 全帧 raw（81,707 B/帧） | slot-free | **4,677,970** | 6,449,446 | 163,506 (3.50%) | false | 103.891 / **+33.605%** → `G0_feasible_for_scope` |
| **R2** | C1 同 R1 | strict-serial | **6,449,405** | 6,449,446 | 163,506 (2.54%) | false | 75.356 / **−3.092%** → `G0_not_closed` |
| **R3** | C2 `f1080p_rand` 全帧 raw（2,594,706 B/帧） | slot-free | 5,189,503 | 11,476,032 | 5,700,448 (**109.85%**) | **true** | 93.651¹ / +20.435%¹ → **`G0_not_proven`** |
| **R4** | comp proxy（848,864 B/帧） | slot-free | **5,928,286** | 9,234,076 | 1,697,820 (28.64%) | false | 81.980 / **+5.427%** → `G0_feasible_for_scope` |

¹ R3 的 `C/margin` 是按 2,592,000 B/帧折算的 **sink 服务率等价**；该行 `G0_not_proven`，不得把 +20.4% 当 G0 余量。

### 5.2 矩阵结论

- **slot-free 是 G0 的必要条件**：R2−R1 = **1,771,435 cycles（37.87% of R1）**；R2 从 +33.605% 跌到 **−3.092%**。R2 是 strict-serial 的**保守上界**（含相机串行化），不是纯 tail。
- **sink 是第二约束**：R3 `S_ss` 与 2,594,706 B × 2 clk/B 的导出时间（5,189,412 cycles）几乎相等；tail 109.85% ≥50% → `sink_limited=true` → **`G0_not_proven`**；实测导出 93.748 MB/s；生产 sink 需求 **≥77.84 MB/s（G0）/ ≥103.79 MB/s（25 ms）**，冻结 TB 上限 93.75，**不得写成 ≥103.79**。
- **内容**：C1 全帧合成 raw（81,707 B/帧，31.7:1）slot-free **+33.605%**；comp proxy（848,864 B/帧，3.05:1）**+5.427%**；C2 stored raw band 被 sink 支配（`G0_not_proven`）；自然图像/全内容/最坏未测。
- **R4 对照**：`S_ss` Δ=0 cycles（P3 R3 5,928,286）；`exp_bytes=3,395,456`、`cycles=27,020,950`、`SS_VEC_MATCH bad=0`、header CRC 全对；测试者独立重跑 1,234 s 亦 Δ=0 → 新 TB 可信。
- 内容自检：R1/R2/R3 `SS_RAW_MATCH bad=0 checked=518400`；R4 `SS_VEC_MATCH bad=0`；DUT `raw_crc` = `zlib.crc32(raw.bin)`（C1 1,020,842,313；C2 237,020,219）；header CRC 自洽。
- 预算：4 次全尺寸 4,741.5 s = **79.0 min ≤120**；全尺寸 4/5；0 TD/板卡。

## 6. 最终 headline 与 scope（已收窄）

**`G0_feasible_for_scope`**：

- 内容：**C1 全帧合成 packed RAW10**（`f1080p_p1d1`）+ **P3 comp 代理**；C2 `f1080p_rand` raw band **`G0_not_proven`**；全部 `full_frame_raw_synthetic` / `proxy_not_natural` / `proxy_not_worst`。
- 口径：**slot-free / overlapped**；`S_ss=(S_23+S_34)/2`；strict-serial 只作保守视图（R2 `G0_not_closed`）。
- sink：**实测 93.75 MB/s 冻结 sim sink**；对 C1/comp 不限速；raw band 生产需求 **≥77.84/103.79 MB/s 仍 `not_proven`**；93.75 不得写成 ≥103.79。
- DDR：行为 256-bit PAXI（无 MC/刷新/行切换/争用）。
- 核/路：**单核单路、per-stream、187.5 MHz**；双核 `c2s2=C` 只是 assumed；无 TD/板级。

**不是**自然图像/全内容/最坏/双路/板级证明；G25 仅参考、不降档。

## 7. 能说 / 不能说

**能说**

1. C1 全帧合成 raw slot-free：G0 **+33.605%**；comp proxy slot-free：G0 **+5.427%**（R4 复现 P3 Δ=0）。
2. **slot-free 是 G0 的必要条件**：R2 strict-serial **−3.092%**，R2−R1 1,771,435（37.87%）。
3. **sink 是第二约束**：R3 tail 109.85%、`sink_limited=true` → `G0_not_proven`；生产 sink ≥77.84/103.79 单列。
4. 平均 DDR 在 1333 下非瓶颈（15.17%）；UART 115200 仅诊断。
5. 93.75 MB/s 对 C1/comp 不限速。

**不能说**

1. 自然图像/低照/噪声/全内容/最坏 1080p30 已过（内容全为合成/代理）。
2. strict-serial C1/comp 过 G0（R2 `G0_not_closed`；P3 comp serial 仅 assumed）。
3. C2 rand raw band G0 过（R3 算术 +20.4% 是 sink 服务率，不是 DUT 容量）。
4. 双路 1080p30 已过（c2s2 assumed；共享 PAXI/Routed 未证）。
5. 93.75 MB/s 对 raw band 足够 / 生产 sink ≥103.79 已实现（未实现，`not_proven`）。
6. 板级/真实 DDR/真实 115200/PCIe/RK 已通（本 run 全 0）；192.642/200 MHz 时序已证。

## 8. 剩余风险与下一轮

| # | 风险/未测 | 现状 | 下一步 |
|---|---|---|---|
| 1 | 真实自然/低照/噪声/最坏内容 4 帧 | 只有 C1/C2 合成 raw + comp 代理；A2 assumed | **最高优先**：真实图集或全帧不可压缩 4 帧，替换/校准 A2/C2 |
| 2 | 生产 slot-free 实现 | R1/R4 是 TB slot-free；R2 是上界视图；真实 CMP 槽所有权/pacing 未做 | RTL/仿真：真实 slot-free 读/导出流水 + 槽所有权 |
| 3 | 生产 sink ≥103.79 MB/s | 冻结 TB 上限 93.75；raw band tail 27.7 ms（83%）；PCIe 未做 | 高速 sink/PCIe 实测；`transport=not_proven` |
| 4 | 双核共享 PAXI/资源/时序 | c2s2=C assumed；231/289；Routed unproven；4 客户仲裁未实现 | 双核 Routed + 4 客户 PAXI + per-stream 实测 |
| 5 | b11 1176 读停点/板级 | H2/H4 未定；本 run 不碰板卡；b13/b14 他人 in-flight | b11/b13 板级抓包判别；与离线结论独立 |
| 6 | 真实 DDR sustained/刷新/仲裁/RK | 行为 PAXI；0 TD/板卡/RK | 板级/PAXI 计数 + RK 联调另开 run |

**恢复本 run（只读）**：

```text
使用 fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261025-233401_fpga-steady-state-reverdict；本轮目标：读取 P4 manifest-r0 与 r0 integrated 报告，确认 G0_feasible_for_scope 的收窄 scope 与剩余风险；不重跑、不改 P1/P2/P3/P4 冻结件。
```

**下一主题（新 run）**：

```text
执行：在 run 20261025-233401_fpga-steady-state-reverdict 的 P4 基础上，用真实/自然图集或全帧不可压缩内容做 1080p 4 帧链级稳态锚点（同 b11 几何/冻结 RTL/slot-free；sink 用可证明 ≥103.79 MB/s 的 fast sink 或记录 raw-band tail），替换/校准 A2/C2，并按 G0 硬门槛（77.76 MB/s / 6.25M cycles）重判 1080p30；只做 FPGA 侧离线仿真/模型，TD/综合/布线/bitgen/下载/Flash/板卡/COM/JTAG=0；先给范围、冻结输入与有界仿真预算。
```

## 9. G 层、证据与复现

| 包 | G0 | G1 | G2 | G3 | G4 |
|---|---|---|---|---|---|
| P1 | pass | pass | n/a | n/a | n/a |
| P2 | pass | pass | n/a | n/a | n/a |
| P3 | pass | pass | n/a | n/a | n/a |
| P4 | pass（P1–P3/内容源/68 artifacts 0 mismatch） | pass（4 run 可复算；R4 独立重跑 Δ=0；8 负对照） | n/a | n/a | n/a |

- 关键哈希：P1 `39F3E3D6…`、P2 `FD27C70F…`、P3 `3C8377A4…`、P4 `D353C61A…`；P4 `four-run-report` `3DF707D6…`、`g0-verdict` `D0B2A91A…`。
- P4 复现（cwd=`T10.ss-4run-matrix/r0`）：`sim/run_4run.py` compile/r1–r4/analyze；命令/超时/日志在 `sim/commands.jsonl`；tester 独立 R4 重跑 1,234 s。

## 10. 过程记录（不改写）

- **P4 r0 PASS，1 轮**；P3 实际修复 **2 轮**（r0 FAIL→r1 metadata FAIL→r2 PASS）；P2 0 修复轮。
- P2 开发/测试调用超预算（约 58/50 vs 35/30）；P4 测试者约 45 calls（墙钟 55 min，调用超 35，已披露）；P4 开发 4 次全尺寸 79.0 min ≤120。
- P4 已披露偏差：① 预检 `chk_raw.log` 以 2M-cycle 超时 `pass=0`（设计内）；② `%TEMP%\opencode\dbg_comp.py` 653 B 只读脚本在写范围外（删除被拒）；③ 测试者未独立重实现 C1/C2 的 `xform_crc`（`raw_crc` 已独立复算）；④ `four-run-report.md`/`g0-verdict` 将 raw band 写成 2,594,750（正确 2,594,706，差 44 B header，不影响门槛）。
- P2 期非阻断观察（C4 舍入、报告表列、manifest 日志自指等）与 P3 OBS-1/2 保留原样，不改写。
- 0 TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK/PCIe；未改 P1/P2/P3/P4、b11/T08/T10、生产源、`workflow/tasks.json`、`docs`。

## 11. 边界

- 不改 `workflow/tasks.json`；T10 仍 active/blocked，不置 done；离线 PASS ≠ 双路系统/板级完成。
- 不声称真实 DDR sustained、真实 UART/PCIe、RK、板级、192.642/200 MHz 时序。
