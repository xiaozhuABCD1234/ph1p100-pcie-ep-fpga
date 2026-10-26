# 交接：1080p30 G0 收口 + 四轮矩阵（`20261025-233401_fpga-steady-state-reverdict`，finished）

- 状态：**本轮完成（P1/P2/P3/P4 全部 PASS；P4 四轮矩阵 round0 PASS，P3 实际修复 2 轮）**。最终 headline：**`G0_feasible_for_scope`**（已收窄，见 §4）。
- 用户边界（2026-10-26）：“25%不是硬门槛，然后我希望还是做1080p30，不然和要求是不一样的”。因此 **G0（per-stream 77.76 MB/s ↔ `S_ss ≤ 6,250,000` cycles @187.5 MHz）是硬门槛**；**G25（97.20 MB/s）只作参考/风险提示**，不进入 headline、不用于降档；目标始终 1080p30，不降档。
- 本文件与 `final-summary.md` / `user-summary.md` 为最终收尾；P1–P3 的旧收尾已被本轮替换。

## 1. 完成 / 未完成

**完成**

1. P1 `T10.ss-steady-anchor`：4 帧实测分离 `L_cold` 与 `S_ss`，证明 b6 的 6,421,414 是冷启动延迟。
2. P2 `T10.ss-verdict-r1`：上轮 `infeasible` 降级 `not_proven`；G0/G25 分列；A1/A2/A3；DDR 5,332/6,400；UART；双核 per-stream；C1–C9。
3. P3 `T10.ss-g0-closure`：G0-only 收口；comp proxy slot-free 5,928,286 → G0 +5.427%；R2 strict-serial 6,365,622.5；R4 assumed 7,616,377.5；2 轮修复后 PASS。
4. P4 `T10.ss-4run-matrix`：4 个不同条件的全尺寸 4 帧矩阵（C1 raw slot-free/strict、C2 rand slot-free、comp proxy slot-free）；量化 slot-free 必要性与 sink 第二约束；R4 复现 P3 Δ=0；r0 PASS。
5. 每个包都有独立综合测试报告（P1/P2 各一、P3 同一测试者 r0→r2、P4 新测试者 r0）。

**未完成 / 不在本轮范围**

- 真实自然图像/低照/噪声/全帧最坏内容的 4 帧实测；所有内容均为合成/代理（`full_frame_raw_synthetic` / `proxy_not_natural` / `proxy_not_worst`）。
- 生产 slot-free 实现（真实 CMP 槽所有权/PAXI pacing）；R2 strict-serial 只是上界视图。
- 生产 sink ≥103.79 MB/s（冻结 TB 上限 93.75）；PCIe/真实 115200 未做。
- 双核共享 PAXI/4 客户仲裁/Routed 时序/资源落地（231/289）。
- b11 1176 读停点 H2/H4；板级/真实 DDR sustained/刷新/仲裁；RK。

## 2. 唯一候选 / manifest / 独立报告

| 包 | manifest（SHA256） | 独立报告 | 状态 |
|---|---|---|---|
| P1 | `T10.ss-steady-anchor/r0/manifest-r0.json` `39f3e3d6d115afbdcda9753b254f6971a10eb75df88d5718eb9ea5a247199f9a`（41） | `test-reports/T10.ss-steady-anchor-r0-integrated.md` | PASS r0 |
| P2 | `T10.ss-verdict-r1/r0/manifest-r0.json` `fd27c70f304f51ba0b0b022398acd46f1f5f43a32351acfc472dea12e034fad0`（34） | `test-reports/T10.ss-verdict-r1-r0-integrated.md` | PASS r0 |
| P3 | `T10.ss-g0-closure/r0/manifest-r2.json` `3c8377a484f42a132b6434cf975710662b8c92871d31bcdaabd9b8ba7aec4961`（82） | `test-reports/T10.ss-g0-closure-r2-integrated.md` | PASS r2；2 修复轮 |
| P4 | `T10.ss-4run-matrix/r0/manifest-r0.json` `d353c61adbc99eb14e9c6f2de44e1a45e99a59f292081e4b00311978ea6c6dd1`（68） | `test-reports/T10.ss-4run-matrix-r0-integrated.md` `887023ad…`（26,525 B） | PASS r0；1 轮 |

- P4 关键产物：`four-run-report.md` `3df707d6…`、`out/g0-verdict.json` `d0b2a91a…`、`out/four-run-table.csv` `940ece59…`、`out/runs-4.csv` `3641465d…`、`out/content-map.json` `c511dc2b…`、`out/gap-menu.csv` `c340499f…`。
- P1/P2/P3/P4 冻结件收尾未改；b11/T08/T10、生产源、`workflow/tasks.json`、`docs`、`work`、`.agents` 未改。

## 3. 实际结果

### 3.1 P1（4 帧，b11 几何，单一平滑梯度，18.75 MB/s sim sink，行为 DDR，per-stream）

| 量 | 值 |
|---|---:|
| `L_cold` / `L_frame` | 6,766,434 / 6,766,393 cycles |
| `S_ss` | **4,677,535 cycles**（band 0.00%） |
| `C_ss` / `fps` | **103.9009 MB/s / 40.0852** |
| G0 / G25 | **+33.6174% / +6.8939%**（G25 仅参考） |
| `export_tail` | 480,930×4 恒定；`sink_limited=false` |
| `startup_pct` | 44.66% |

### 3.2 P2（上轮 `infeasible` 的撤回/降级）

- **撤回**：6,421,414 当每帧吞吐（75.6843 / 29.199 / −2.6694%）；0%/25% 合判；1080p 排除 overhead 三档；6,400 当 1333 主口径。
- **降级**：系统级 `1080p30 per-stream` → **`not_proven`**（A1/A2 内容跨界）；A2 保守内容行仍 `infeasible`（G0 −2.6694%）。
- A1 **103.9009**（G0 +33.6174%、G25 +6.8939%）；A2 **75.6843**（assumed；comp 核级 81.067 是 core-only，不是 A2 链级；−2.6694%/−22.1355%）；A3 **154.2198**（assumed；+98.33%/+58.66%）；A4=b6 冷延迟 6,421,414，仅参照。
- DDR：**5,332 / 6,400** 双列；主路径 809.034 MB/s、gate 1,011.2925；required_eff **15.1732%/12.6412%**、gate_eff **18.9665%/15.8014%**。
- UART：真实 115200 = **11,520 B/s**（40,032 B→3.475 s，104.25×；2,594,706 B→225.235 s，6,757×）；sim sink 18.75 MB/s（1,628×）；`transport=not_proven`。
- 双核：`c2s2=C`（非 2C）；`assumed_from_single_core` + `paaxi_shared_unproven`；231/289；Routed unproven；永不 feasible。
- C1–C9 在 P2 `out/corrections.csv` / `verdict-r1.md`。

### 3.3 P3（G0-only 收口，comp proxy）

| run | 内容 | pacing | `S_ss` | 结论 |
|---|---|---|---:|---|
| R0 | smp 梯度 | slot-free | 4,677,535 | 逐值复现 P1 |
| R1 | smp 梯度 | slot-free | 4,677,531 | sink 变快只改 tail |
| R2 | smp 梯度 | strict-serial | 6,365,622.5 | overlap penalty 1,688,091.5（36.09%） |
| R3 | comp proxy | slot-free | **5,928,286** | 81.9799 MB/s；G0 **+5.4268%**；G25 −15.6586% 参考 |
| R4 | comp proxy | strict-serial | 未跑 | assumed 7,616,377.5（63.810 MB/s，G0 −17.94%） |

- R3 tail 1,697,820（28.6%），`sink_limited=false`；同 run `SS_VEC_MATCH bad=0`；header CRC 全对。
- P3 实际修复 **2 轮**（r0 FAIL engineering/G1 → r1 metadata FAIL → r2 PASS）。

### 3.4 P4（四轮矩阵，4 个不同条件）

| run | content | pacing | `S_ss` | `L_cold` | tail | sink_limited | `C` / G0 |
|---|---|---|---:|---:|---:|---|---|
| **R1** | C1 `f1080p_p1d1` 全帧 raw（81,707 B/帧） | slot-free | **4,677,970** | 6,449,446 | 163,506 (3.50%) | false | 103.891 / **+33.605%** → `G0_feasible_for_scope` |
| **R2** | C1 同 R1 | strict-serial | **6,449,405** | 6,449,446 | 163,506 (2.54%) | false | 75.356 / **−3.092%** → `G0_not_closed` |
| **R3** | C2 `f1080p_rand` 全帧 raw（2,594,706 B/帧） | slot-free | 5,189,503 | 11,476,032 | 5,700,448 (**109.85%**) | **true** | 93.651¹ / +20.435%¹ → **`G0_not_proven`** |
| **R4** | comp proxy（848,864 B/帧） | slot-free | **5,928,286** | 9,234,076 | 1,697,820 (28.64%) | false | 81.980 / **+5.427%** → `G0_feasible_for_scope` |

- **R2−R1 = 1,771,435 cycles（37.87% of R1）**：strict-serial 的 pacing penalty 上界（含相机串行化），不是纯 tail；R2 只作保守视图。
- **R3**：`S_ss` 与 2,594,706 B × 2 clk/B 的导出时间（5,189,412 cycles）几乎相等，是 **sink 服务间隔**，不是 DUT 容量；tail 109.85% ≥50% → `sink_limited=true` → `G0_not_proven`；实测导出 93.748 MB/s。
- **R4 复现 P3 R3**：`S_ss` Δ=0 cycles；`exp_bytes=3,395,456`、`cycles=27,020,950`、`SS_VEC_MATCH bad=0`、header CRC 全对；测试者独立重跑 1,234 s 亦 Δ=0。
- 内容自检：R1/R2/R3 `SS_RAW_MATCH bad=0 checked=518400`；R4 `SS_VEC_MATCH bad=0`；DUT `raw_crc` = `zlib.crc32(raw.bin)`（C1 1,020,842,313；C2 237,020,219）；header CRC 自洽。
- 预算：4 次全尺寸（940.4/1,087.5/1,383.6/1,330.0 s），总 4,741.5 s = **79.0 min ≤120**；全尺寸 4/5；0 TD/板卡。

## 4. 最终 headline 与 scope（已收窄）

**`G0_feasible_for_scope`**：在下列范围内，per-stream 1080p30 的实测稳态帧间隔低于硬门槛：

- 内容：**C1 全帧合成 packed RAW10**（`f1080p_p1d1`，81,707 B/帧，31.7:1）+ **P3 comp 代理**（848,864 B/帧，3.05:1）；C2 `f1080p_rand` raw band **`G0_not_proven`**（sink-limited）；全部 `full_frame_raw_synthetic` / `proxy_not_natural` / `proxy_not_worst`。
- 口径：**slot-free / overlapped**；`S_ss=(S_23+S_34)/2`；strict-serial 只作保守视图（R2 `G0_not_closed`）。
- sink：**实测 93.75 MB/s 冻结 sim sink**（2 clk_a1/B）；对 C1/comp 不限速；raw band 生产需求 **≥77.84 MB/s（G0）/ ≥103.79 MB/s（25 ms）仍 `not_proven`**；93.75 不得写成 ≥103.79。
- DDR：行为 256-bit PAXI（AR_GAP=2/R_GAP=3，无 MC/刷新/行切换/争用）。
- 核/路：**单核单路、per-stream**、187.5 MHz；双核 `c2s2=C` 只是 assumed，PAXI/时序 unproven；无 TD/板级。

**不是**自然图像/全内容/最坏/双路/板级证明；G25 仅参考、不降档。

## 5. 能说 / 不能说

| 能说 | 不能说 |
|---|---|
| C1 全帧合成 raw slot-free：G0 **+33.605%**；comp proxy slot-free：G0 **+5.427%**（R4 复现 P3 Δ=0） | 自然图像/全内容/最坏 1080p30 已过（内容全为合成/代理） |
| **slot-free 是 G0 的必要条件**：R2 strict-serial −3.092%，R2−R1 1,771,435（37.87%） | strict-serial C1/comp 过 G0（R2 `G0_not_closed`；P3 comp serial 仅 assumed） |
| **sink 是第二约束**：R3 tail 109.85%、`sink_limited=true` → `G0_not_proven`；生产 sink ≥77.84/103.79 单列 | C2 rand raw band G0 过（R3 算术 +20.4% 是 sink 服务率，不是 DUT 容量） |
| 平均 DDR 在 1333 下非瓶颈（15.17%）；UART 115200 仅诊断 | 双路 1080p30 已过（c2s2 assumed；共享 PAXI/Routed 未证） |
| 93.75 MB/s 对 C1/comp 不限速 | 93.75 MB/s 对 raw band 足够 / 生产 sink ≥103.79 已实现（未实现，`not_proven`） |
| P1 的 6.421M 是冷启动延迟；P2 的 infeasible 口径已撤回/降级 | 板级/真实 DDR/真实 115200/PCIe/RK 已通（本 run 全 0）；192.642/200 MHz 时序已证 |

## 6. 剩余风险与下一次

| # | 风险/未测 | 现状 | 下一次 |
|---|---|---|---|
| 1 | **真实自然/低照/噪声/最坏内容 4 帧** | 只有 C1/C2 合成 raw + comp 代理；A2 仍 assumed | **最高优先**：真实图集或全帧不可压缩 4 帧，替换/校准 A2/C2 |
| 2 | **生产 slot-free 实现** | R1/R4 是 TB slot-free；R2 是上界视图；真实 CMP 槽所有权/pacing 未做 | RTL/仿真：真实 slot-free 读/导出流水 + 槽所有权 |
| 3 | **生产 sink ≥103.79 MB/s** | 冻结 TB 上限 93.75；raw band tail 27.7 ms（83%）；PCIe 未做 | 高速 sink/PCIe 实测；`transport=not_proven` |
| 4 | **双核共享 PAXI/资源/时序** | c2s2=C assumed；231/289；Routed unproven；4 客户仲裁未实现 | 双核 Routed + 4 客户 PAXI + per-stream 实测 |
| 5 | **b11 1176 读停点/板级** | H2/H4 未定；本 run 不碰板卡；b13/b14 他人 in-flight | b11/b13 板级抓包判别；与离线结论独立 |
| 6 | **真实 DDR sustained/刷新/仲裁/RK** | 行为 PAXI；0 TD/板卡/RK | 板级/PAXI 计数 + RK 联调另开 run |

**恢复本 run（只读）**：

```text
使用 fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261025-233401_fpga-steady-state-reverdict；本轮目标：读取 P4 manifest-r0 与 r0 integrated 报告，确认 G0_feasible_for_scope 的收窄 scope（C1 全帧合成 raw + comp proxy / slot-free / 93.75 MB/s sim sink / 行为 DDR / 单核 187.5MHz / per-stream）与剩余风险；不重跑、不改 P1/P2/P3/P4 冻结件。
```

**下一主题（新 run，建议）**：

```text
执行：在 run 20261025-233401_fpga-steady-state-reverdict 的 P4 基础上，用真实/自然图集或全帧不可压缩内容做 1080p 4 帧链级稳态锚点（同 b11 几何/冻结 RTL/slot-free；sink 用可证明 ≥103.79 MB/s 的 fast sink 或记录 raw-band tail），替换/校准 A2/C2，并按 G0 硬门槛（77.76 MB/s / 6.25M cycles）重判 1080p30；只做 FPGA 侧离线仿真/模型，TD/综合/布线/bitgen/下载/Flash/板卡/COM/JTAG=0；先给范围、冻结输入与有界仿真预算。
```

## 7. 过程记录（不改写）

- **P4 r0 PASS，1 轮**；P3 实际修复 **2 轮**（r0 FAIL→r1 metadata FAIL→r2 PASS）；P2 0 修复轮。
- P2 期开发/测试调用超预算（约 58/50 vs 35/30）；P4 测试者约 45 calls（墙钟 55 min，调用超 35，已披露）；P4 开发 4 次全尺寸 79.0 min ≤120。
- P4 已披露偏差：① 预检 `chk_raw.log` 以 2M-cycle 超时 `pass=0`（设计内，非失败 run）；② `%TEMP%\opencode\dbg_comp.py` 653 B 只读调试脚本在写范围外（删除被环境拒绝）；③ 测试者未独立重实现 C1/C2 的 `xform_crc`（`raw_crc` 已独立复算）；④ `four-run-report.md`/`g0-verdict` 将 raw band 写成 2,594,750（正确 2,594,706，差 44 B header，不影响门槛）。
- P2 期非阻断观察（C4 舍入、报告表列、manifest 日志自指等）与 P3 OBS-1/2 保留原样，不改写。
- 0 TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK/PCIe；未改 P1/P2/P3/P4 冻结件、b11/T08/T10、生产源、`workflow/tasks.json`、`docs`。

## 8. 回退

- 回退 = 不采用 P4 的收窄结论；P1/P2/P3 冻结件仍可只读引用（P1 A1、P3 comp proxy）。
- 不得把 P4 的 C1/comp 结论外推到自然/全内容/双路/板级；不得用 G25 降档。

## 9. 边界

- 本 run 不改 `workflow/tasks.json`；**T10 仍 active/blocked，不置 done**；离线 PASS ≠ 双路系统/板级完成。
- 0 次 TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK；无真实 DDR/PCIe/RK 声明。
- 收尾文件：本文件 + `final-summary.md` + `user-summary.md` + `dispatch.json`（finished）+ `dev-plan.md`（finished）。
