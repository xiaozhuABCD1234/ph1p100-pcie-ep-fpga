# P4 放行与 `sink_limited` 口径澄清 — `T10.ss-g0-prod-verdict`

- run：`20261026-143924_fpga-1080p30-g0-production`；日期：2026-10-26
- 依据：P1 r1b PASS（`manifest-r1` `e306ed42…`）、P2 r1 文档重绑 PASS（`manifest-r1` `803d3efb…`）、P3 r0 PASS（`manifest-r0` `de8a5cff…`）
- 适用：P4 新开发/新测试者；0 sim / 0 TD / 0 板卡；不改 P1/P2/P3 候选与报告。

## 1. 依赖与输入（已满足）

| 包 | 状态 | manifest | 关键结论 |
|---|---|---|---|
| P1 `T10.ss-g0-prod-content` | PASS r1b | `e306ed42…`（70 artifacts） | N `S_ss=7,475,240`（−16.3906%）；L `S_ss=6,986,952`（−10.5475%）；两类 `bottleneck_attribution=core_interval` |
| P2 `T10.ss-g0-prod-coregap` | PASS r1 | `803d3efb…`（49 artifacts） | `closable_at_187_5=conditional`；A+H 6,008,078 / 2.3179 c/B / +4.027%；包络 45.034%；单 H 6,260,648（−0.17%）；224.3 MHz 仅 0.006%；双核 per-stream 不变 |
| P3 `T10.ss-g0-prod-sink` | PASS r0 | `de8a5cff…`（5 artifacts） | comp 需求 50.32/64.69 @33.33 ms、67.09/86.25 @25 ms，均 <93.75；raw band 25 ms 需 103.788、93.75 不足；生产 sink 未证 |

## 2. `sink_limited` 口径澄清（P4 headline 的依据）

**问题**：冻结规则 `sink_limited = tail_frac ≥ 50%` 原是为 P4 四轮矩阵设计的「sink 是否支配帧间隔」代理。P1 自然内容的 L 类 `tail_frac=61.7249%`，但其 sink 忙碌率 `export_time/S_ss = 4,312,600/6,986,952 = 61.72%`——sink 有 38% 的空闲，帧间隔由 core 决定；按原代理会把「可量化的 core 缺口」误标成「容量不可证」。

**澄清（不改变任何数值/门槛/G25）**：

- `tail_frac ≥ 50%` 仍是**诊断旗标**，必须报告；
- 作为 **G0 的 `G0_not_proven` 阻断条件**，用 **sink 忙碌率**判定：`busy = export_time / S_ss ≥ 0.95`（sink 在 ≥95% 的帧间隔内持续服务，才视为实际 gate）；否则实际瓶颈不是 sink，若 `S_ss>6.25M` 应判 **`G0_not_closed`**（有实测缺口）。
- 不用 `export_time ≥ core_interval` 作判据：在 sink 背压时 core 的 `t_enc` 也被拖慢（R3 的 `core_interval≈5,189,503` 与 export 几乎相等），该比较会把「sink 背压导致的 core 变慢」误判成 core-bound；忙碌率能干净分开。

**对 P1 的机械重评（数值不变）**：

| 类 | S_ss | tail_frac | export_time | busy=export/S_ss | 新判定 |
|---|---:|---:|---:|---:|---|
| N | 7,475,240 | 44.8783% | 3,354,672 | 44.88% | **`G0_not_closed`**（−16.3906%） |
| L | 6,986,952 | 61.7249% | 4,312,600 | 61.72% | **`G0_not_closed`**（−10.5475%） |

- **run headline = `G0_not_closed`**（两类均有实测缺口；不是 `G0_not_proven`，更不是 feasible）。
- **向后兼容**：P4 四轮矩阵 R3（rand）busy = 5,189,412/5,189,503 = **99.998%** → 仍 `sink_limited=true`/`G0_not_proven`；R1/R2/R4 busy = 3.50%/2.54%/28.64% → 不受影响。故本澄清**不改变任何历史判定**。
- P1/P3 报告里的 headline 仍是 `G0_not_proven`（P2 的 headline 已是 `G0_not_closed`；它们按当时冻结的 50% 代理写）；**P4 必须显式写明本澄清并说明「run 级 headline 由 P1 的 L `not_proven` 修正为 `not_closed`；数值/证据未变，P1 报告不被改写」**。不得静默覆盖。

## 3. P4 交付要求

### 3.1 必写六条（逐条引用数值与来源）

1. 当前 core + 187.5 MHz **不能**闭合自然内容：N 7,475,240 vs 6,250,000（−16.3906%）、L 6,986,952（−10.5475%）；两类 core-bound。
2. A+H = 6,008,078 / 2.3179 c/B / +4.027% 是**唯一 187.5 MHz 算术闭合**，但包络 **45.034%** → `conditional`，**不是 G0 closure、不是 implemented**；单 H 6,260,648（−0.17%）仍不够。
3. 仅提时钟 209.6/224.3 MHz 不在 b11 时序能力内（WNS +0.015 ns @187.5 ≈188.0 MHz；224.3 仅 0.006% 算术余量）；D/E 行不是可行路径。
4. 双核不提高 per-stream（7,476,245 不变；ERAM 231–289/300、时序 unproven）。
5. P3：93.75 对实测 comp 有余量（最紧 L@25 ms 86.25，占 92.0%）；raw band ≥103.79 **未实现/未证**，只对 RAW fallback；不得把 93.75 说成 103.79。
6. 用户坚持 1080p30、**不降档**；需要决定：① 投入 core 结构改版（A+H，原型 + TD + 板级）；② 换核/换算法；③ 接受 `G0_not_closed` 边界。**降档需用户明确，P4 不主推。**

### 3.2 scope tuple（写死）

`content` = P1 自然场景/低照图像派生 Bayer（`proxy_not_natural_raw`/`not_sensor_raw`/`proxy_not_worst`/`display_referred`，**非传感器 RAW**）；`pacing` = TB `wait_slot_free`（非生产自由跑）；`sink` = 93.75 MB/s TB 代理（非生产 sink）；`DDR` = 行为级 256-bit PAXI；`core/clock` = 单核 187.5 MHz；`stream` = 单路。

### 3.3 能与不能说

- **能说**：合成/自然代理内容 + TB slot-free + 93.75 sink 下，自然内容 4 帧实测失败且 gap 可量化；core 是主约束；sink 不是；A+H 是有条件候选；当前 187.5 MHz 不可闭合。
- **不能说**：G0 已闭合/feasible；A+H 已实现；自然/全内容/最坏内容通过；真实传感器 RAW；生产 sink ≥103.79；真实 DDR/PCIe/UART sustained；板级/bit/Flash；双路；RK/NPU；用 G25 降档；用 P4 合成 C1 的 `G0_feasible_for_scope` 覆盖自然内容。

### 3.4 交付物

`g0-production-verdict.json`（headline/scope/six statements/per-class/rejection list）、`result-r0.md`、`handoff.md`、`final-summary.md`、`user-summary.md`、`manifest-r0.json`（全 artifact、`stopped_modifying=true`、`active_commands=0`、`evidence_rounds` 全 0）。handoff/final-summary 由 P4 起草，P4 PASS 后原规划复核并正式收尾。

### 3.5 验收 D1–D10

D1 绑定 P1 r1b/P2-r1/P3-r0 三 manifest 并复算 SHA；D2 headline=`G0_not_closed`；D3 六条齐全且数值/来源正确；D4 A+H 只写 conditional/arithmetic，不写 closure；D5 时钟/双核/P3 三条边界正确；D6 scope tuple + 能说/不能说 + 剩余风险 + 恢复入口；D7 G25 仅参考、不降档；D8 不把代理/合成当自然/全内容，不声称板级/真实 DDR/RK；D9 `sink_limited` 澄清被显式写明并解释 L 的重分类；D10 0 sim/0 TD/0 板卡、写范围合规、候选哈希稳定。

## 4. 预算与角色

| 角色 | calls | wall | sim |
|---|---:|---:|---:|
| P4 开发（新） | ≤25 | ≤45 min | 0 |
| P4 测试（新） | ≤25 | ≤25 min | 0 |

- 新开发 + 新测试者，不复用 P1/P2/P3；只写 `T10.ss-g0-prod-verdict/**` 与 `test-reports/T10.ss-g0-prod-verdict*`。
- P4 PASS 后：原规划更新 dispatch 为 finished，复核 handoff/final-summary/user-summary，写收尾记录；本 run 不再开新包。

## 5. 剩余风险（P4 必须列）

- 自然内容仍为图像派生代理，无传感器 RAW/噪声/光学；L 无噪声注入；最坏/全内容未证。
- A+H 的 45% 包络来自未实现的 matcher/emit 结构估算；B/C 无 matcher 证据；任何实现需原型 + TD + 4 帧复测。
- 生产 pacing、生产 sink、真实 DDR sustained、板级、双路均未测；本轮结论只覆盖声明 scope。
- P2 r1 采用原地覆盖 r0 的 7 个文档文件（OBS-8）；P4 以 r1 为准，不得声称 r0 可复现。
