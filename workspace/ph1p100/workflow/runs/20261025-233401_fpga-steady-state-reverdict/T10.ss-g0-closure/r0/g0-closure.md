# G0-only 1080p30 收口复核（P3 `T10.ss-g0-closure`）

- run：`20261025-233401_fpga-steady-state-reverdict`；任务：`T10.ss-g0-closure`；开发 r0
- 硬门槛：**G0 = per-stream 77.76 MB/s ↔ `S_ss ≤ 6,250,000 cycles/frame` @187.5 MHz**（`6.25M × 30 = 187.5 MHz`）。
- **G25（97.20 MB/s）只作参考列**：不进入 headline、不用于降档；本报告不推荐 1600×900 等降档。
- 结论：**`G0_feasible_for_scope`**（范围严格限定，见 §1）。

## 1. G0 结论与 scope

**`G0_feasible_for_scope`** — 在下列范围内，1080p30 per-stream 的实测稳态帧间隔低于 G0 硬门槛：

| 维度 | scope |
|---|---|
| 内容 | comp 向量代理（1920×64 transform-domain 向量按 2 行块 `b mod 32` 平铺全帧）；**`proxy_not_worst`**，不是自然图像/最坏/全内容证明 |
| 口径 | slot-free（overlapped）流水线；4 帧背靠背；`S_ss=(S_23+S_34)/2` |
| sink | fast sim sink（请求 2 GHz/200 MB/s；实测导出约 93.8 MB/s），非真实 115200/PCIe |
| DDR | 行为级 256-bit PAXI（`AR_GAP=2/R_GAP=3/rdy=1`），无 MC/刷新/行切换/争用模型 |
| 核/路 | 单核单路、per-stream；双核 `c2s2=C` 只是 `assumed_from_single_core`，PAXI 共享/时序 `unproven` |
| 实现 | 无 TD/综合/布线/位流/板卡；187.5 MHz 只用既有闭点，未证明 192.642 MHz |

**关键数字**：R3（comp 代理、slot-free、fast sink）`S_ss = 5,928,286` cycles → **81.9799 MB/s / 31.628 fps**，G0 margin **+5.427%**；G25 margin **−15.66%**（仅参考）。A2（assumed comp 外推）仍为 **6,421,414 / 75.684 MB/s / −2.669%**，见 §5/§6；因此“全内容/最坏”仍 `not_proven`，本 verdict 只覆盖代理内容。

## 2. 运行矩阵与有效性（全部 4 帧实测）

| run | 内容 | pacing | sink | capture | `S_ss` | `S_23` / `S_34` | `L_cold` | `export_tail` | 有效 |
|---|---|---|---:|---|---:|---|---:|---:|---|
| R0 | smp 梯度 | slot-free | 187.5 MHz | 是 | 4,677,535 | 4,677,535 / 4,677,535 | 6,766,434 | 480,930×4 | V1/V3/V4/V5/V6 全 true |
| R1 | smp 梯度 | slot-free | 2 GHz | 是 | 4,677,531 | 4,677,531 / 4,677,531 | 6,365,664 | 80,160×4 | 全 true |
| R2 | smp 梯度 | strict-serial | 2 GHz | 是 | 6,365,622.5 | 6,365,622 / 6,365,623 | 6,365,664 | 80,160×4 | 计数/单调 true；V4 按设计不适用 |
| R3 | comp 代理 | slot-free | 2 GHz | 否 | **5,928,286** | 5,928,283 / 5,928,289 | 9,234,076 | 1,697,820×4 | V1/V3/V4/V5/V6 全 true |
| R4 | comp 代理 | strict-serial | 2 GHz | 否 | — | — | — | — | **未运行**（触发已满足 R2−R1=36.09%>1%，90-min 墙钟到顶）；serial 列只用 `assumed = R3 + (R2−R1) = 7,616,377.5` |
| v1 | comp 代理 | slot-free | 2 GHz | 否 | —（check-only，2M cycles 截断） | — | — | — | 修正后 `SS_VEC_MATCH bad=0 checked=518400`（91 s） |

- **R0 控制逐值复现 P1**：`t_rst=20`、`t_exp(1)=6,766,454`、`t_exp(2)=11,443,989`、`S_ss=4,677,535`、`exp_bytes=160,136`、`cap_bytes=160,312`、`cycles=20,801,058`、`cap=4/enc=4/exported=4/read=518400`、drop/dup/geom/err/wd=0 → `control_pass=true`（0 mismatch）。
- R1 与 R0 的 `S_ss` 差 4 cycles（0.0001%）：**sink 变快只缩短 tail（480,930→80,160）与 `L_cold`，稳态帧间隔不变**，常数 tail 在帧间差中抵消，`sink_limited=false`。
- R2 强制串行把 `S_ss` 拉到 6,365,622.5（+36.09%），其中包含相机串行化 + tail；V4 的“相机提前入槽”判据在 strict-serial 下按设计不适用（不是气泡）。
- R3 4 帧完整、`read=518400`、无 drop/dup/geom/err/wd、无 `SS_STALL`/超时；`sink_limited=false`（tail 恒定 1,697,820，<0.5·S_ss）。
- 每 run 独占 work 库/INI/日志，硬超时 2700 s；R0/R1/R2/R3 实际 937.6/1056.1/1111.9/1316.5 s，round1 `r3_frozen` 1326.1 s（22.1 min）；v1 91 s + 两次中止的 v1 试跑 258.3/434.9 s；累计仿真墙钟 **6532.4 s = 108.9 min**，在 round1 override **≤112 min** 内（round0 86.8 min；全尺寸 5/5）。R4 因预算未跑。

## 3. 串行 vs 交叠（G0 的口径依赖）

- **overlap gain（R2−R1）= 1,688,091.5 cycles = 36.09%**：strict-serial 的代价包含“相机 1.6M 不能与上一帧 core/导出重叠”，是 tail overlap 收益的上界（P1 慢 sink 的 tail 仅 480,930）。
- 因此 **G0 的通过依赖 slot-free/overlapped 流水线**：R3 的 5,928,286 是 slot-free 实测；strict-serial 的 comp 代理用 `R3 + (R2−R1) = 7,616,377.5`（assumed）→ 63.81 MB/s，G0 −17.95%。若要求严格串行，G0 不通过；本任务不把 serial 结果冒充 overlap。
- 梯度内容同口径：A1 overlapped 4,677,531 → 103.901 MB/s（G0 +33.62%）；A1 serial 6,365,622.5 → 76.348 MB/s（G0 −1.82%）。

## 4. G0 表（A1/A2/A3/代理 × c1s1/c1s2/c2s1/c2s2 × overlapped/serial）

完整 32 行见 `out/g0-table.csv`；G25 只作参考列。下表为 per-stream 容量（MB/s），`c1s1/c2s1/c2s2 = C`，`c1s2 = C/2`（每核一路，非 2C）：

| anchor | 口径 | S (cycles) | c1s1 | c1s2 | c2s1 | c2s2 | G0（c1s1）| G25 参考 |
|---|---|---:|---:|---:|---:|---:|---|---|
| A1 grad（measured） | overlapped | 4,677,531 | 103.901 | 51.950 | 103.901 | 103.901 | pass +33.62% | pass +6.89% |
| A1 grad（measured） | serial | 6,365,622.5 | 76.348 | 38.174 | 76.348 | 76.348 | **fail −1.82%** | fail −21.45% |
| A2 comp（assumed） | overlapped | 6,421,414.375 | 75.684 | 37.842 | 75.684 | 75.684 | **fail −2.67%** | fail −22.13% |
| A2 comp（assumed） | serial | 8,109,505.875 | 59.930 | 29.965 | 59.930 | 59.930 | fail −22.93% | fail −38.34% |
| A3 rand（assumed） | overlapped | 3,151,346.5 | 154.221 | 77.110 | 154.221 | 154.221 | pass +98.33% | pass +58.66% |
| A3 rand（assumed） | serial | 4,839,438.0 | 100.425 | 50.212 | 100.425 | 100.425 | pass +29.15% | pass +3.32% |
| **P comp 代理（measured）** | **overlapped** | **5,928,286** | **81.980** | **40.990** | **81.980** | **81.980** | **pass +5.43%** | fail −15.66% |
| P comp 代理（assumed serial） | serial | 7,616,377.5 | 63.810 | 31.905 | 63.810 | 63.810 | fail −17.95% | fail −34.35% |

- 双核 `c2s2` 的 per-stream 值只是 `assumed_from_single_core` + `paaxi_shared_unproven`；**aggregate 2C 不用于 per-stream**（负对照 NEG-05）。
- `c1s2` 在任何 measured 锚点都低于 G0（A1 51.95、代理 40.99），故“单核两路”在 per-stream G0 上不成立，除非另证两路共享后的实际单路容量。

## 5. 内容代理与字节级证据（`proxy_not_worst`）

1. **向量来源**：冻结 comp 向量 32×4800 B（`in.hex` SHA `edbfdeae…f9849`，decode 后与 `in.xform` 逐字节相同）。
2. **域转换**：`in.hex` 是 A1 PREP/PRED 后的 transform-domain；链上 `PREP_EN=PRED_EN=1`。若直接当像素注入，DUT 会再差分，核看到的不是该向量。`sim/prep_content.py` 用 P1 格式模型 `a1_ref.inverse_frame(...,1,1)` 逆变换成 packed RAW10 像素；DUT 再正向变换还原该向量。
3. **Python 自检**：`transform_frame(inverse_frame(tiled)) == tiled`，mismatch=0（2,592,000 B）；`raw_crc32=3613527589`、`xform_crc32=3038348232`。
4. **TB 自检（round1，同一 run）**：G0 run 已用冻结 TB `a565c6f2…` 重跑（`r3_frozen`），同一日志打印帧 1 `SS_VEC_MATCH bad=0 checked=518400 drv_groups=518400`、末行 `bad=0 checked=518400 drv_groups=2073600`；该检查只读 `tap_pix/raw_mem/vec_mem`，不驱动 DUT。
   - 旧 TB 的 r3 日志 `bad=691132` 是修正前自检每 3 个样本分组一次的差一 bug（TB-only），其 timing 与 r3_frozen 逐值相同（5,928,286 / 1,697,820 / 27,020,950），但**不再作为 G0 绑定证据**；旧 TB 已归档 `src/legacy/tb_ss_g0_89948303.v`。
5. **DUT 端到端**：R3 导出帧头 `raw_len=2,592,000`、`xform_len=2,592,000`、`raw_crc=3,613,527,589`、`xform_crc=3,038,348,232`、`header_crc` 自洽 → **DUT 实际喂给 core 的字节流就是平铺向量**（各字段与 Python 期望逐值相等）。
6. **跨带匹配**：相同块间距 153,600 B ≫ 核心 13-bit（8,192 B）距离窗口；相邻块内容不同，平铺不引入窗口内新匹配。
7. **局限（必须披露）**：合成斜坡、单内容类、无自然图像/低照/噪声；`proxy_not_worst`；真实图集仍 `not_proven`。本地 codec-throughput 复跑（不同 RTL 血统 core.v 79,788 B）给出 374,461 cycles/153,600 B = 2.438 c/B，比 P2 冻结 355,261（2.313 c/B）慢 5.1%，说明 A2 的“assumed”外推本身有 ≥5% 不确定性；R3 是本任务的直接实测。

## 6. 2.67% 差距菜单（A2 口径；只给路径，不实施）

冻结算术：`A2 6,421,414 − 6,250,000 = 171,414 cycles/帧（2.6694% of A2；2.859% of core 5,995,029.375）`；G0 所需时钟 `6,421,414×30 = 192.642 MHz`；G25 的 `240.803 MHz` 仅参考。

| id | 路径 | 收益 | 证据/风险 | 资源/时序 | 验证成本 | 实施 |
|---|---|---|---|---|---|---|
| M1 | tail overlap（slot-free 与 strict-serial 之差） | tail 上限 480,930 cycles/frame（P1 sink）；实测 serial 总代价 R2−R1=1,688,091.5（含相机串行化） | 当前 slot-free 已实现；strict-serial 会失去 | 2 RAW+2 CMP 槽已存在 | R1/R2 实测 | 0（已实现） |
| M2 | core cycles/B −171,414（−2.859%） | A2 6,421,414→6,250,000 | 需核级改动；本 run 禁止改 RTL | ERAM/面积未评估 | 新任务+TD+STA | 不实施 |
| M3 | 时钟 192.642 MHz（G0） | +2.74% vs 187.5 MHz 闭点 | 未跑 TD；Routed 时序 unproven | 未评估 | TD/STA+bitgen+板测 | 不实施 |
| M4 | 组合（overlap + core/clock） | 171,414 + tail | 叠加风险；核与时钟交互 | 未评估 | 新实现+TD+板测 | 不实施 |

- **不降档、不用 G25 主推**：不把 1600×900 作为 G0 的替代目标；G25 列只作风险提示。
- 菜单是“若 A2 口径成立”的最小路径；本任务实测 R3 已在代理内容上闭合 G0，故菜单不是当前必做项。
- **所需 sink 率**（`out/sink-needs.csv`）：冻结 raw 口径 `2,594,750 B/帧` → **77.84 MB/s@33.333 ms / 103.79 MB/s@25 ms**；R3 实测 payload `848,864 B/帧` → 25.47 / 33.95 MB/s；实测导出率 ≈93.7 MB/s（tail 1,697,820 恒定，`sink_limited=false`）。R1/R2 为 40,034 B/帧 → 1.20 / 1.60 MB/s。

## 7. 负对照（全部拒绝）

见 `out/negative-controls.json`：

1. **NEG-01 G25 驱动降档**：A2 c1s1 G0 fail/G25 fail 不得推导出“改 1600×900”主推荐。
2. **NEG-02 冷延迟当 `S_ss`**：`L_cold=6,766,434` → 71.83 MB/s < 77.76；`S_ss` 必须用 `t_exp(k+1)−t_exp(k)`。
3. **NEG-03 代理当 worst/all-content**：`proxy_not_worst`，不得写全内容证明。
4. **NEG-04 serial 当 overlap**：R2−R1=1,688,091.5>0，不得把 R2 的值填入 overlapped 列。
5. **NEG-05 aggregate 2C 当 per-stream**：c1s2 的 2C aggregate 可过而 per-stream C/2 不过。

## 8. 未证项与边界

- 全内容/自然图像/低照/噪声：`not_proven`；A2（assumed）仍失败，A3（assumed）通过，二者是假设包络，不是实测。
- 真实 UART（11,520 B/s）、PCIe/高速 sink、真实 DDR sustained/PAXI 仲裁/刷新/行切换：`unproven`；本任务 fast sink 是 sim-only。
- 双核共享 PAXI、Routed 时序、192.642 MHz、资源 marginal/conservative：`unproven`；本 run 0 次 TD/板级。
- R4（comp strict-serial）未运行：受 90 min 仿真墙钟约束；serial comp 列标 `assumed`，不影响 slot-free G0 的实测结论，但限制“严格串行也能过 G0”的说法。
- G2–G4 `not_applicable`（无综合/布线/bitgen/板卡）。

## 9. 产物

`out/runs.csv`、`out/runs.json`、`out/g0-table.csv`、`out/gap-menu.csv`、`out/sink-needs.csv`、`out/g0-verdict.json`、`out/content-proxy.json`、`out/content-proxy.md`、`out/negative-controls.json`、`out/check-outputs.json`；`input-verified.json`、`src/DIFF.md`、`src/tb_ss_g0.v`、`src/legacy/tb_ss_g0_89948303.v`、`sim/{run_g0.py,prep_content.py,verify_inputs.py,freeze.py,check_outputs.py}`、`sim/logs/*`、`sim/caps/*`、`result-r0.md`、`result-r1.md`、`lessons.md`、`manifest-r0.json`、`manifest-r1.json`。

## 10. round1 修订（2026-10-26；权威 scope）

- **TB 绑定**：G0 关键 run 已用冻结 TB `a565c6f2…` 重跑 `r3_frozen`（`sim/logs/r3_frozen.log`、`sim/caps/r3_frozen.{stats,hdr,evt}`）；同一 run `SS_VEC_MATCH bad=0 checked=518400 drv_groups=518400`（帧 1）/`2073600`（末行）。`S_ss=5,928,286`（±0.5% 内逐值相同）、band [5,928,283, 5,928,289]、计数/header CRC 全部重核；旧 TB `89948303…` 归档 `src/legacy/tb_ss_g0_89948303.v`，仅 R0–R2 timing 依 D1 复用。
- **scope（权威）**：comp 向量代理（transform-domain ramp 按 2 行块 `b mod 32` 平铺、`848,864 B/帧`、`proxy_not_worst`、单内容）/ **slot-free（overlapped）** / **实测 93.75 MB/s sim sink**（对本 proxy 不限速：tail 1,697,820 = 28.6% < 50%；**raw band 生产需求仍 ≥77.84 MB/s（G0）/ ≥103.79 MB/s（25 ms/tail 稳健），`not_proven`**）/ 行为 256-bit PAXI（无 MC/刷新/争用）/ 单核单路 / 187.5 MHz。**不外推**自然图像/全内容/双路/板级/真实 DDR/PCIe/RK；G2–G4 `not_applicable`。
- **R4**：`not_run`（触发条件已满足，90-min 墙钟到顶）；comp strict-serial 只写 `assumed = 7,616,377.5`（63.810 MB/s，G0 −17.94%），不得称 strict-serial 过 G0；headline 只覆盖 slot-free。
- **G25**：仅参考列，不降档；**A1 overlapped 取 R1 4,677,531**（P1 4,677,535 −4 cycles，0.0001%）。
- **headline**：`G0_feasible_for_scope` 为**临时**结论，待同一综合测试者对 `manifest-r1.json` + `r3_frozen` 复测后正式成立；若复测 `S_ss>6.25M` → `G0_not_closed`，`bad>0`/无法绑定 → `G0_not_proven`。
- **元数据修正**：`out/content-proxy.json` 的 `in.meta` 已修为 raw 330 B / `E98C9A1C…`；DIFF §4 sink 改 2 clk_a1/B≈93.75 MB/s、§5 `%02x`、§1 WD 12M、F5–F9 均按 D2 修正。
