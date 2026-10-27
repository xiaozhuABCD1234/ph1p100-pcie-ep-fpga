# 复核判定 r1：修正 P2 `T10.dual-aplus-service-verdict` 的 1080p30/双路结论

- run：`20261025-233401_fpga-steady-state-reverdict`；task：`T10.ss-verdict-r1`；round：`r0`；role：fpga-dev（离线模型/表格/报告；0 次 TD/综合/布线/bitgen/下载/Flash/板级/RK）
- 绑定输入（只读）：P1 `T10.ss-steady-anchor` manifest `39f3e3d6…9f9a`、`out/steady-state.json` `a0945e1f…`、`sim/caps/ss4.stats` `29bd3185…`、`sim/logs/run4.log` `dc215e0b…`
- 被复核冻结件：P2 manifest `5ed90500…36a6`、`feasibility-report.md` `82c2669e…`、旧 `out/scenarios.csv` `2d806599…`（43 行，byte-identical 回归复现）
- 本文件由 `model/render_report.py` 从冻结输入与规则生成；表内数值与 `out/*.csv` 同源，`model/check_outputs.py` 复核 CSV↔报告一致

## 0. 结论（先给 three-part headline，再给依据）

**1080p30 per-stream 的 claim 级结论 = `not_proven`。** 不是 `infeasible`，也不是 `feasible`。

- `G0`（nominal 0%，77.76 MB/s，per-stream）：A1（measured 梯度内容）**通过**（+33.6174%）；A2（assumed comp 外推）**未通过**（-2.6694%）→ **内容跨界**
- `G25`（设计裕量 1.25x，97.20 MB/s）：A1 **通过**（+6.8939%）；A2 **未通过**（-22.1355%）
- `content` = `not_proven_all_content`：只测了一种平滑梯度内容（smooth `smp` 图案）+ b11 几何 + 18.75 MB/s sim-only sink + 行为级 DDR；自然图像/低照/噪声未测

证据标签：`measured` = 冻结实测；`derived` = 由冻结公式算得；`assumed` = 无直接实测的模型假设；`unproven` = 无任何证据。

## 1. 对 P2 的修正摘要（撤回/保留与百分点）

| # | P2 原口径 | 处置 | 修正后（本包） | 百分点/数值变化 |
|---|---|---|---|---|
| C1 | b6 单帧 `cycles=6,421,414` 当每帧服务时间 → `75.684 MB/s / 29.199 fps / −2.6694%` | **撤回** | A1 稳态 `S_ss=4,677,535` → `103.9009 MB/s / 40.0852 fps` | G0 −2.6694% → **+33.6174%**；G25 −22.1355% → **+6.8939%** |
| C2 | 0% nominal 与 25% 设计裕量合判（链级 margin<0 → `infeasible`） | **撤回**（拆两 gate） | `G0`/`G25` 分列；`below_25` → `conditional`，不得写 `infeasible` | 1080p30 A1 双 gate 均过；A2 双 gate 均失 |
| C3 | DDR 峰值 6,400 MB/s（@1600）为主口径 | **修正** | 主线 1333 = **5,332 MB/s**；6,400 只作带标签回退列 | required_eff 12.6412% → **+15.1732%**；gate_eff 15.8014% → **+18.9665%** |
| C4 | 1080p 固定锚点、overhead 三档 `applies=false` | **撤回** | 1080p 用档位差平移 `S_ss+(tier−426,385)`；tier0 **+17.6152%**、primary **+6.8939%**、1e6 **-4.7828%** | 1080p 25% 非三档稳健 |
| C5 | “UART 导出”未限定生产/仿真 | **限定** | sim sink 18.75 MB/s；真实 115200 = 11,520 B/s（慢 1628×）；`export_tail=480,930` 恒定、`sink_limited=false`；`transport=not_proven` | 不得用 fast-sink 暗示 UART 可实时 |
| C6 | `overhead=426,385` 当独立实测；A2 当第二个全帧锚点 | **降级/披露** | overhead 为 assumed 且与 A4 循环（A2−A4=0.375 cycle）；A2 只标 `assumed` | 不得把 A2 当 6.42M 的独立证据 |
| C7 | 双核 per-stream=C 但结论易被 2C 聚合误读 | **保留表值+加边界** | `c2s2=C`（assumed_from_single_core）、`paaxi_shared_unproven=true`；2C 只用于 DDR/总量 | 双核 headline 最高 `not_proven`，永不 `feasible` |
| C8 | 单一 comp 内容基；无内容包络 | **扩展** | A1 measured / A2 assumed 保守 / A3 assumed 乐观；每行 `claim_status=not_proven_all_content` | 自然图像/低照未证，不得称“保证” |
| C9 | 前沿：1080p30 `fails_30`、25% 最大 23.36 fps、f_req 240.803 MHz | **修正** | A1：25% 最大 **32.068 fps**、f_req **175.408 MHz**；A2 仍 23.359 fps / 240.803 MHz | 1080p30 改单列 “measured-content 双 gate 过 / not_proven all content” |

**保留的 P2 结论（本次复核未推翻）**：per-stream 容量规则（`1c1s=C`、`1c2s=C/2`、`2c1s=C`、`2c2s=C`，永不用 2C 作 per-stream）；双核资源 marginal 231/300（余 69）、conservative 289/300（余 11）；单核 Routed 时序仅在 ≤187.5 MHz proven；双路 1080p30 的 DDR 平均带宽非瓶颈；43 行网格与旧判定算术本身（legacy 回归 **byte-identical**，见 §7）——**修正只来自规则/口径/输入**。

## 2. Q1：单帧延迟 vs 稳态吞吐（P1 已实测，本包只引用）

| 量 | 值 | 标签 | 说明 |
|---|---|---|---|
| `L_cold` | 6,766,434 cycles | measured | 冷启动单帧完成（与 b6 的 6,421,414 同类，不同几何/UART） |
| `S_2` / `S_23` / `S_34` | 4,677,535 / 4,677,535 / 4,677,535 | measured | 三间隔完全一致 |
| `S_ss` | **4,677,535 cycles**（band [4,677,535, 4,677,535]，spread 0.0000%） | measured | 主口径；非 knife-edge |
| `startup` / `startup_pct` | 2,088,899 / 44.6581% | derived | 冷启动占 44.66%，把 6.421M 当吞吐是实质性口径错误 |
| `S_avg2`（事件口径 / stats 含 2,000 drain） | 5,721,984.500 / 5,722,994 | derived | 两帧平均，**不是** `S_ss`；比稳态高 22.3% |
| b6 单帧 6,421,414 | `L_cold`（延迟） | measured 但**非吞吐** | 几何 CAM 3840×2160/ROI 960·540/LINE_GAP 40、1 GHz UART；与 b11 几何不可直接当帧间隔 |
| 导出尾巴 | 480,930 ×4 恒定；ideal 400,320（+80,590） | measured | 常数尾巴在帧间差抵消，`sink_limited=false`，`C_excl_export=C_ss`；**不得**无条件扣 400,320 |

结论：P2 的 6.421M/29.199 fps/−2.669% 是“单帧冷启动延迟当稳态吞吐”的产物；实测稳态为 `S_ss=4,677,535` → `103.9009 MB/s`、`40.0852 fps`。

## 3. Q2：两个 gate 与内容包络

### 3.1 内容锚点（1080p，cycles/frame）

| id | 名称 | cycles/frame | C（MB/s） | G0 margin | G25 margin | 标签 | 用途 |
|---|---|---:|---:|---:|---:|---|---|
| A1 | `grad_chain_ss` | 4,677,535 | 103.9009 | +33.6174% | +6.8939% | measured | 主锚点（唯一实测全帧） |
| A2 | `comp_core_scaled+overhead` | 6,421,414.375 | 75.6843 | -2.6694% | -22.1355% | assumed | 保守内容界（假设） |
| A3 | `rand_core_scaled+overhead` | 3,151,346.500 | 154.2198 | +98.3279% | +58.6623% | assumed | 乐观界（假设） |
| A4 | `b6 冷启动单帧` | 6,421,414 | n/a（延迟） | n/a | n/a | measured_but_not_throughput | 仅延迟参照，**不作吞吐** |

**强制披露**：A2 与 A4 数值几乎相同（6,421,414.375 vs 6,421,414）是**定义造成**的（overhead := 6,421,414 − 5,995,029.375），不是独立证据；A2 只能 `assumed`。A4 是单帧冷启动延迟，禁止进入任何容量/gate 计算（负对照 NC1）。

**A1 的外推边界（硬约束）**：A1 是**单内容（smooth `smp` 梯度）/单几何（b11 1920×1080）/18.75 MB/s sim sink/行为级 DDR/per-stream** 的链级锚点；`40.0852 fps`、`+6.8939%` **不得**外推自然图像/低照/噪声，**不得**外推双路 1080p30。两个 gate 的 77.76 / 97.20 MB/s 为冻结门槛，**未放宽**；`below_25` 一律写 `conditional`，永不写 `infeasible`。

### 3.2 gate 矩阵（c1s1/c1s2/c2s1/c2s2 × A1/A2/A3 × G0/G25 = 24 行，完整见 `out/gate-matrix.csv`）

| 锚点 | cores/streams | per-stream C | G0 77.76 | G0 | G25 97.20 | G25 | 行 verdict | 标签 |
|---|---|---:|---:|---|---:|---|---|---|
| A1 | c1s1 | 103.9009 | +33.6174% | pass | +6.8939% | pass | feasible | measured |
| A1 | c1s2 | 51.9504 | -33.1913% | fail | -46.5530% | fail | infeasible | measured |
| A1 | c2s1 | 103.9009 | +33.6174% | pass | +6.8939% | pass | conditional | measured |
| A1 | c2s2 | 103.9009 | +33.6174% | pass | +6.8939% | pass | conditional | measured |
| A2 | c1s1 | 75.6843 | -2.6694% | fail | -22.1355% | fail | infeasible | assumed |
| A2 | c1s2 | 37.8421 | -51.3347% | fail | -61.0678% | fail | infeasible | assumed |
| A2 | c2s1 | 75.6843 | -2.6694% | fail | -22.1355% | fail | infeasible | assumed |
| A2 | c2s2 | 75.6843 | -2.6694% | fail | -22.1355% | fail | infeasible | assumed |
| A3 | c1s1 | 154.2198 | +98.3279% | pass | +58.6623% | pass | feasible | assumed |
| A3 | c1s2 | 77.1099 | -0.8360% | fail | -20.6688% | fail | infeasible | assumed |
| A3 | c2s1 | 154.2198 | +98.3279% | pass | +58.6623% | pass | conditional | assumed |
| A3 | c2s2 | 154.2198 | +98.3279% | pass | +58.6623% | pass | conditional | assumed |

### 3.3 1080p30 headline（三段式，claim 级）

| 组合 | G0（77.76 MB/s） | G25（97.20 MB/s） | content | headline |
|---|---|---|---|---|
| c1s1（per-stream=C） | pass（+33.6174%） | pass（+6.8939%） | `not_proven_all_content` | **`not_proven`** |
| A2 内容基（保守） | fail（-2.6694%） | fail（-22.1355%） | 同上 | 同上（内容跨界） |
| c2s1/c2s2（双核） | pass（算术） | pass（算术） | 同上 | **`not_proven`**（`assumed_from_single_core` + `paaxi_shared_unproven`；**永不 feasible**） |

规则（`model/rules.json`）：A1/A2 的 G0 不一致 → `not_proven`；两者 G0 均失 → `infeasible`；均过但 G25 或资源/时序未证 → `conditional`；全过且资源/时序 proven → `feasible`（仅单核）。**本行任何组合都不得省略 content 一段。**

## 4. Q3：1080p 参与 overhead 三档（0 / 426,385 / 1,000,000）

| tier cycles | cycles/frame | C（MB/s） | G0 margin | G25 margin | G25 | 说明 |
|---:|---:|---:|---:|---:|---|---|
| 0 | 4,251,150 | 114.3220 | +47.0190% | +17.6152% | pass | 1080p 档位差平移（applies=true） |
| 426,385 | 4,677,535 | 103.9009 | +33.6174% | +6.8939% | pass | A1 实测锚点（主档） |
| 1,000,000 | 5,251,150 | 92.5512 | +19.0215% | -4.7828% | fail | 1080p 档位差平移（applies=true） |

- 1080p **必须**参与敏感性（P2 的 `applies=false` 撤回）：`Δ = tier − 426,385`，tier0 = S_ss−426,385，1e6 = S_ss+573,615。
- 结果：1080p 25% **非三档稳健**——只在 tier0 与 primary 过，保守档 1e6 跌破（-4.7828%）。
- “0-overhead/流水线隐藏 tail”判据：`Δ_req = S_ss − 5,000,000 = -322,465 cycles`（≤0）→ 主档 25% 已过；但要在保守档（1e6）也过，需再降 ≥ **251,150 cycles** 固定开销，或把时钟提到 ≥ **196.918 MHz**；常数导出尾巴（480,930）本身不是瓶颈，隐藏 tail 不改变 `S_ss`。

## 5. Q4：DDR 口径 1333（5,332）vs 1600（6,400）

| 口径 | DDR total | gate(1.25x) | required_eff | gate_eff |
|---|---:|---:|---:|---:|
| **1333 主线（5,332 MB/s）** | 809.034 MB/s | 1011.2925 MB/s | +15.1732% | +18.9665% |
| 1600 回退列（6,400 MB/s） | 同上 | 同上 | +12.6412% | +15.8014% |

- 显式公式：`peak_1333 = 1333e6 × 32/8 / 1e6 = 5,332 MB/s`（用户域 166.65 MHz × 32 B = 5,333 MB/s，同一量级）；`809.034/5,332 = +15.1732%`。**DOC-1 §8 的 1.2/2.33/3.4 GB/s 与 `data_rate×width/8` 不自洽**（1333 应 ≈5.332 GB/s），本包单列该差异、不采用、不改 gate。
- 结论：**平均带宽不是瓶颈**（15.17% of peak；含 25% gate 为 18.97%），但 `DDR sustained/刷新/行切换/仲裁/单 outstanding` 仍 **unproven**；`809.034` 是平均需求，不是 sustained 实测。

## 6. Q5：UART / 导出尾巴的性质

| 口径 | 字节率 | 40,032 B | 2,594,706 B | 相对 33.333 ms |
|---|---:|---:|---:|---:|
| 真实 115200 8N1 | 11,520 B/s | 3.475 s | 225.235 s | 104.25× / 6757× |
| b11/本 run sim sink（`UART_DIV=1`, `clk_uart=clk_a1`=187.5 MHz） | 18.75 MB/s | 2.135 ms | — | — |
| b6 sim sink（`clk_uart`=1 GHz） | 100 MB/s | 0.400 ms | — | — |

- 链级锚点覆盖“采集→RAW 槽→DDR 读→core→CMP→**sim-only fast sink**”。真实 115200 比 sim sink 慢 **1628×**（比 b6 sink 慢 8,688×），无法承载 1080p30 → `transport=not_proven`；生产路径必须是 PCIe/高速 sink。
- `export_tail = 480,930 cycles/frame` 四帧恒定（ideal 400,320，+80,590），`sink_limited=false` → 在 `S_ss` 中抵消，`C_excl_export = C_ss`；**不得**无条件扣 400,320。若真实 UART 限速，CMP 槽会反压 core，`S_ss` 不再成立。

## 7. Q6：双核 per-stream / 共享 PAXI / 资源 / 时序

- 容量规则不变：`c1s1=C`、`c1s2=C/2`、`c2s1=C`、`c2s2=C`（每核一路，**不是 2C**）。`2×C_ss = 207.8018 MB/s` 只作聚合（DDR/总量），**不得**与 155.52 MB/s 比较判 per-stream。
- `dual_core_capacity=assumed_from_single_core`、`paaxi_shared_unproven=true`（b11 的 `a1_ddr_arb2` 只覆盖“写 store + 读 reader”两客户，4 客户 256-bit 仲裁未实现/未测）。
- 资源：marginal 231/300（余 69）、conservative 289/300（余 11，3.67%）；Routed 双核时序 **unproven**（本 run 0 次 TD）。
- 因此双核行最高 `conditional`，claim headline 最高 `not_proven`，**永不 `feasible`**（`out/scenarios.csv` 中无任何 `cores=2` 行 verdict=feasible）。

## 8. Q7：其它口径/算术问题与修正后 verdict

| id | 问题 | 影响 |
|---|---|---|
| C1 | 冷启动单帧当稳态吞吐（6,421,414 → 29.199 fps） | G0/G25 方向性反转（−2.67%/−22.14% → +33.62%/+6.89%） |
| C2 | 0% 与 25% 合判（R2 链级 margin<0 → infeasible） | 把“25% 不够”误写成“nominal 不可行” |
| C3 | 1333 平台用 6,400 峰值 | required_eff/gate_eff 偏乐观（12.64%/15.80% vs 15.17%/18.97%） |
| C4 | 1080p `applies=false` | 掩盖 25% 在保守档跌破（−4.78%） |
| C5 | sim sink 当生产 UART | 真实 115200 仅 11,520 B/s（104×/6,757× 帧周期） |
| C6 | overhead 循环定义、A2≡A4 | A2 被误当独立实测证据 |
| C7 | 双核 2C 聚合易误读 | 双路误判可行 |
| C8 | 单一内容基、无 `claim_status` | “保证”越界；自然图像未证 |
| C9 | 前沿 f_req 240.803 MHz / 25% 最大 23.36 fps | A1 下应为 175.408 MHz / 32.068 fps（单内容） |

**修正后 verdict（1080p30，per-stream，单核）：**
- `G0`：A1 `+33.6174% pass` / A2 `-2.6694% fail`；`G25`：A1 `+6.8939% pass` / A2 `-22.1355% fail`；`content` = `not_proven_all_content`。
- 行级（A1 measured 内容基）：`c1s1` = `feasible`（资源 187/300、时序 187.5 proven），但 **`claim_status=not_proven_all_content`**，不得升级为系统 feasible；`c1s2` = `infeasible`（C/2 低于 nominal）；`c2s1/c2s2` = `conditional`（双核/PAXI unproven）。
- 系统级 headline：**`not_proven`**（既不是 `infeasible`，也不是 `feasible`；双路更不得 feasible）。

## 9. 推荐（comp 内容基一致规则）

| 角色 | scenario | nominal margin（主档） | G25 | 三档最差 nominal margin | 所需时钟 0% / 25% | 说明 |
|---|---|---:|---|---:|---|---|
| **主推荐** | `1600x900-30fps-c1s1-187.5MHz` | +36.1774% | pass | +21.0486% | 137.688 / 172.110 MHz | comp 基最大 30 fps 几何；保守档跌破 → **primary feasible / conservative conditional** |
| 备选 1 | `1440x810-30fps-c1s1-187.5MHz` | +64.5348% | pass | +42.9485% | 113.958 / 142.447 MHz | 三档稳健 |
| 备选 2 | `960x540-30fps-c1s2-187.5MHz` | +62.3257% | pass | +25.0622% | 57.754 / 72.193 MHz | 单核分时双流，per-stream=C/2 三档稳健 |
| 单列（不作推荐） | `1920x1080-30fps-c1s1-187.5MHz`（A1 单内容） | +6.8939% | -4.7828% | 140.326 / 175.408 MHz | **measured-content only / not_proven_all_content**；A2 同几何双 gate 均失，故不得压过 comp 基的 1600×900 |

- 内容基一致性：主推荐/备选全部是 comp 外推基（`affine_comp_tier`），与比较对象同源；1080p 只有 A1（grad）实测，**不得**因 A1 过 G25 就把 1080p30 提为主推荐。
- 1080p30 若只看 G0：A1 过、A2 失 → 仍不是 nominal-only，而是内容跨界；`below_25` 一律写 `conditional`，**不得**写 `infeasible`。

## 10. band / knife-edge / tier 依赖 / 什么会改变结论

- **band**：`S_23=S_34=4,677,535`，band `[4,677,535, 4,677,535]`，spread 0.0000% → **非 knife-edge**；A1 距 25% 阈值（5,000,000 cycles）尚有 322,465 cycles。
- **tier 依赖**：1080p 25% 只在 tier0/primary 过；tier 1e6 需 5,251,150 cycles（比 A1 多 573,615）→ 见 §4。
- **A2 缺口**：保守内容要过 G25 需从 6,421,414 降到 ≤5,000,000（−1,421,414 cycles，−22.1%）或把时钟提到 ≥240.803 MHz。
- 会改变结论的输入：① 全帧 comp/自然图像锚点（A2 变 measured，且 `S ≤ 5,000,000` → 1080p30 可升 `conditional`；`S > 6,250,000` → `infeasible`）；② 共享 PAXI 4 客户仲裁/DDR sustained 实测；③ 双核 Routed 时序与 conservative 289 落地；④ 固定开销削减 ≥251,150 cycles 或时钟 ≥196.918 MHz；⑤ 生产 sink（PCIe）替代 sim sink；⑥ 几何/内容变化（b6 几何+1 GHz UART 的 `L_cold` 6.42M–6.77M 差异不影响 `S_ss`）。

## 11. 关键数字核对表（`check_outputs.py` 逐行核对）

| 量 | 值 | 标签 | 来源 |
|---|---|---|---|
| P1 L_cold | 6,766,434 | measured | P1 steady-state.json |
| P1 S_ss | 4,677,535 | measured | P1 steady-state.json |
| P1 S_2 / S_23 / S_34 | 4,677,535 / 4,677,535 / 4,677,535 | measured | P1 steady-state.json |
| P1 band spread | 0.0000% | measured | P1 steady-state.json |
| P1 startup / startup_pct | 2,088,899 / 44.6581% | derived | P1 steady-state.json |
| P1 S_avg2 event / stats | 5,721,984.500 / 5,722,994 | derived | P1 steady-state.json (not S_ss) |
| P1 export_tail (per frame, x4) | 480,930 | measured | P1 steady-state.json; constant, sink_limited=false |
| A1 C_ss / fps | 103.9009 MB/s / 40.0852 fps | measured | P1 r0 measured S_ss |
| A1 margin G0 / G25 | +33.6174% / +6.8939% | derived | 103.9009 vs 77.76 / 97.20 |
| A1 f_req_0 / f_req_25 | 140.326 / 175.408 MHz | derived | 30*S_ss / 37.5*S_ss |
| A2 cycles / C_ss | 6,421,414.375 / 75.6843 MB/s | assumed | comp 2.312897 c/B x 2,592,000 B + 426,385 |
| A2 margin G0 / G25 | -2.6694% / -22.1355% | assumed | conservative content envelope |
| A3 cycles / C_ss | 3,151,346.500 / 154.2198 MB/s | assumed | rand 1.051297 c/B extrapolation |
| A3 margin G0 / G25 | +98.3279% / +58.6623% | assumed | optimistic content envelope |
| A2 vs A4 | 6,421,414.375 vs 6,421,414 (delta 0.375 cycle) | assumed | A2 is definitionally A4 + 0.375; not independent evidence |
| Gate demand G0 / G25 | 77.76 / 97.20 MB/s | derived | 2,592,000 B x 30 fps; 1.25x |
| S_ss at exactly 0% / 25% | 6,250,000 / 5,000,000 cycles | derived | 4.86e8/S thresholds |
| 1080p tier0 (S_ss-426,385) | 4,251,150 cycles / G0 +47.0190% / G25 +17.6152% | assumed | tier shift, 1080p participates |
| 1080p tier primary | 4,677,535 cycles / G0 +33.6174% / G25 +6.8939% | measured+assumed | A1 measured anchor, primary tier |
| 1080p tier 1e6 (S_ss+573,615) | 5,251,150 cycles / G0 +19.0215% / G25 -4.7828% | assumed | conservative overhead tier |
| 25% max 1080p fps A1 / A2 | 32.068 / 23.359 | derived | 1.875e8/(1.25*S) |
| A2 f_req_25 | 240.803 MHz | assumed | conservative-content clock |
| DDR total / gate | 809.034 / 1011.2925 MB/s | derived | 2R+2S, 20B/32B, CMP worst stored |
| required_eff @5332 / @6400 | 15.1732 / 12.6412 | derived | 809.034 / peak |
| gate_eff @5332 / @6400 | 18.9665 / 15.8014 | derived | 1,011.2925 / peak |
| UART 40,032 B @11,520 B/s | 3.475 s (104.25 x frame period) | derived | real 115200 8N1 |
| UART 2,594,706 B @11,520 B/s | 225.235 s (6757 x frame period) | derived | worst stored payload, real 115200 |
| sim sink vs real 115200 | 1628 x | derived | 18.75 MB/s / 11,520 B/s |
| export ideal vs measured tail | 400,320 / 480,930 cycles (+80,590) | measured | P1 export_tail constant |
| dual-core per-stream | c2s2 = C = 103.9009 MB/s (2C aggregate 207.8018 is not per-stream) | assumed | assumed_from_single_core; paaxi_shared_unproven |
| 1080p30 per-stream headline | not_proven | derived | A1 G0/G25 pass vs A2 G0/G25 fail |
| verdict counts (43 rows) | feasible 12 / conditional 25 / infeasible 6 | derived | out/scenarios.csv |
| primary recommendation | 1600x900-30fps-c1s1-187.5MHz | assumed | comp content basis, largest G25-passing 30 fps tier |
| alternates | 1440x810-30fps-c1s1-187.5MHz; 960x540-30fps-c1s2-187.5MHz | assumed | tier-robust, comp basis |

## 12. 未测 / not_proven 清单

- 内容：只测平滑梯度（A1）；自然图像/低照/噪声/全帧 comp 均未测 → `not_proven_all_content`。
- DDR：行为级 PAXI（AR_GAP/R_GAP，单拍，`rdy=1`），无 MC/刷新/行切换/争用 → sustained 与仲裁 unproven。
- 双核：无 Routed 构建、无 4 客户仲裁、`c2s2=C` 只是 `assumed_from_single_core`。
- 传输：sim sink 18.75 MB/s；真实 115200 仅诊断 → `transport=not_proven`；PCIe 未做。
- 时序/资源：单核 ≤187.5 MHz proven（b6/b10 routed），200 MHz 与双核 unproven；本 run 0 次 TD。
- 板级/RK/Flash：0；本包不声称系统完成。

## 13. 证据索引

- 输入：`inputs/frozen-inputs.json`、`input-verified.json`、`inputs/legacy/{calc.py,rules.json,frozen-inputs.json}`（P2 byte-identical 副本）
- 模型/规则/测试：`model/{calc.py,rules.json,test_calc.py,gen_tables.py,check_outputs.py,regress_legacy.py,render_report.py}`
- 表格：`out/{scenarios,content-anchors,gate-matrix,overhead-sensitivity,ddr-budget,corrections,frontier}.csv`、`out/summary.json`、`out/legacy-regression.json`
- 回归/TEST：`logs/{gen_tables,test_calc,check_outputs,regress_legacy}.out.txt`
- 冻结：`manifest-r0.json`（本文件与全部附件 SHA256）
