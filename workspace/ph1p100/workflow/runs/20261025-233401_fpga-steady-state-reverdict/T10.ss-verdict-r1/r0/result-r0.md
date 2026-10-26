# 结果：`T10.ss-verdict-r1` r0（P2 可行性判定的稳态锚点复核与修正）

- run：`20261025-233401_fpga-steady-state-reverdict`；task：`T10.ss-verdict-r1`；round：`r0`；role：fpga-dev（离线模型/表格/报告）
- 依赖：P1 `T10.ss-steady-anchor` r0 **PASS**，manifest `39f3e3d6d115afbdcda9753b254f6971a10eb75df88d5718eb9ea5a247199f9a`；`out/steady-state.json` `a0945e1f60d9…`
- 被复核件：P2 `T10.dual-aplus-service-verdict` manifest `5ed90500…36a6`（只读）
- 状态：**已停止修改**（`stopped_modifying=true`、`active_commands=0`）；manifest 见 `manifest-r0.json`

## 1. 唯一可观察结果（本包交付）

一份可执行、可复现、带 6 个负对照的修正判定：

1. `out/scenarios.csv` — 43 行 × 两 gate（`G0`/`G25`）+ `chain_anchor_id`/`content_label`/`claim_status`/`content_envelope`
2. `out/content-anchors.csv` — A1（measured）/A2（assumed）/A3（assumed）/A4（measured_but_not_throughput）
3. `out/gate-matrix.csv` — c1s1/c1s2/c2s1/c2s2 × A1/A2/A3 × G0/G25 = 24 行
4. `out/overhead-sensitivity.csv` — 43 × 3 档（1080p 用档位差 `S_ss+(tier−426,385)`，`applies=true`）
5. `out/ddr-budget.csv` — 5,332（主线）与 6,400（回退）双列 + required_eff/gate_eff + DOC-1 §8 单列披露
6. `out/corrections.csv` — C1–C9（原值/原规则/修正值/修正规则/影响/证据/标签）
7. `out/frontier.csv`、`out/summary.json`、`out/legacy-regression.json`
8. `verdict-r1.md` — 按 Q1–Q7；先修正摘要，再 gate 矩阵/内容包络，三段式 headline，推荐与“什么会改变结论”
9. 模型：`model/calc.py`（纯函数）、`model/rules.json`（两 gate/映射/禁止塌缩/6 负对照）、`inputs/legacy/{calc.py,rules.json,frozen-inputs.json}`（P2 逐字节副本）

## 2. 实际执行（argv / rc / 日志）

| # | 命令 | cwd | rc | 日志 |
|---|---|---|---|---|
| 1 | `python model/gen_tables.py` | `T10.ss-verdict-r1/r0` | 0 | `logs/gen_tables.out.txt` |
| 2 | `python model/test_calc.py` | 同上 | 0 | `logs/test_calc.out.txt` |
| 3 | `python model/regress_legacy.py` | 同上 | 0 | `logs/regress_legacy.out.txt` |
| 4 | `python model/render_report.py` | 同上 | 0 | `logs/render_report.out.txt` |
| 5 | `python model/check_outputs.py` | 同上 | 0 | `logs/check_outputs.out.txt` |

解释器：`C:\Program Files\Python311\python.exe`（3.11）。无 vsim/vlog/TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK；无网络/随机。

## 3. 局部检查结果（实际计数）

| 检查 | 结果 |
|---|---|
| `test_calc.py` | **85 项，0 失败**（已知值、边界、6 负对照 + anchor-mix；含 A1/A2/A3 容量与 margin、S=6.25M/5.0M 阈值、tier 平移、DDR 双峰值、UART、max fps、headline、43 行映射） |
| `regress_legacy.py` | P2 逐字节副本哈希匹配；`scenarios.csv` **43 行 0 mismatch、byte-identical**；`overhead-sensitivity.csv` **129 行 0 mismatch**（证明修正来自规则/输入，不是算术重写） |
| `check_outputs.py` | **249 项，0 失败**（CSV↔模型、CSV↔报告关键数字逐行、gate 不塌缩、双核无 feasible、1080p tier 参与、DDR 双列/效率、C1–C9 完整、推荐唯一/极大/内容基一致、legacy PASS） |
| 负对照 | NC1 冷延迟当吞吐、NC2 `below_25→infeasible`、NC3 1333 用 6400、NC4 sim sink 当生产、NC5 2C 当 per-stream、NC6 1080p tier 不适用 → **全部被拒**（另加 A1/A2 锚点混算 `CONTENT_ANCHOR_MIX`） |

## 4. 关键结论（数值）

- Q1：`L_cold=6,766,434`、`S_2=S_23=S_34=4,677,535`、`S_ss=4,677,535`（band 0.00%，非 knife-edge）、`startup_pct=44.6581%`；两帧平均 5,721,984.5（事件）/5,722,994（stats 含 drain）**不是** `S_ss`；b6 6,421,414 是单帧冷启动，不是吞吐。
- Q2：A1 `103.9009 MB/s / 40.0852 fps`、G0 `+33.6174%`、G25 `+6.8939%`；A2 `75.6843 MB/s`、G0 `-2.6694%`、G25 `-22.1355%`；A3 `154.2198 MB/s`、`+98.3279% / +58.6623%`。
  - **1080p30 per-stream headline = `not_proven`**（A1.G0≠A2.G0 内容跨界；不影响“两个 gate 各自分列”）。
  - 行级（A1 measured 内容基）：c1s1=`feasible`、c1s2=`infeasible`（C/2 低于 nominal）、c2s1/c2s2=`conditional`；**所有行 `claim_status=not_proven_all_content`**。
- Q3：1080p tier0 `4,251,150 cycles`（G25 `+17.6152%`）、primary `4,677,535`（`+6.8939%`）、1e6 `5,251,150`（`-4.7828%`）→ 1080p 25% **非三档稳健**；`Δ_req=-322,465`（主档已过），保守档需再降 ≥251,150 cycles 或时钟 ≥196.918 MHz。
- Q4：`DDR_total=809.034 MB/s`、gate `1,011.2925`；1333：`required_eff 15.1732%`、`gate_eff 18.9665%`；1600：`12.6412% / 15.8014%`；DOC-1 §8 的 1.2/2.33/3.4 GB/s 不可由 `data_rate×width/8` 复现，单列不采用。
- Q5：真实 115200 = 11,520 B/s → 40,032 B `3.475 s`（104.25×）、2,594,706 B `225.235 s`（6,757×）；sim sink 18.75 MB/s（快 1,628×）；`export_tail=480,930` 恒定、`sink_limited=false` → 不扣减，`transport=not_proven`。
- Q6：`c2s2=C`（`assumed_from_single_core`）、`paaxi_shared_unproven=true`、资源 231/289、双核 Routed unproven → **无任何 `cores=2` 行 feasible**，双核 headline 最高 `not_proven`。
- Q7：C1–C9 逐条给出（见 `out/corrections.csv` 与 `verdict-r1.md` §1/§8）。
- 推荐：主推荐 `1600x900-30fps-c1s1-187.5MHz`（primary G25 `+36.1774%`、三档最差 `+21.0486%` → primary feasible / conservative conditional）；备选 `1440x810-30fps-c1s1`（三档最差 `+42.9485%`）、`960x540-30fps-c1s2`（三档最差 `+25.0622%`）；1080p30 **单列** “measured-content only / not_proven_all_content”，不作推荐。

## 5. 与规划冻结核对值的差异（逐项解释，未改门槛）

| 项 | 规划值 | 本包值 | 原因 |
|---|---:|---:|---|
| A3 `C_ss` | 154.2202 | **154.2198** | `4.86e8/3,151,346.5` 的精确值；规划为舍入；margin 均 `+98.3279%`（规划 `+98.328%`） |
| 1080p tier0 `C` | 114.3218 | **114.3220** | `4.86e8/4,251,150` 精确值；规划为舍入 |
| 导出超出量 | +80,590（对 400,340 实测字节串行） | 同 **+80,590**；对设计理想 400,320 则为 **+80,610** | 两者皆报：`export_tail=480,930`、设计成本 400,320、实测字节（40,034 B）串行 400,340 |
| 1080p30 行 verdict | 指南要求分列 | c1s1=`feasible` + `claim_status=not_proven_all_content` | 严格按设计指南 §4.1“行 verdict 与 claim_status 分列，不互相替代”；系统 headline 仍为 `not_proven` |
| required_eff 显示 | 15.1732% | 表格内 `+15.1732%`（`fmt_pct` 统一加号） | 数值一致；`check_outputs.py` 校验数值，符号为显示风格 |

## 6. 预算与偏差（如实记录）

- 冻结预算：≤35 calls / ≤60 min。**实际工具调用数约 58 次**（超出冻结调用数）；墙钟未逐命令插桩，但全部为本机短时 Python 运行（单次 < 5 s），无 vsim/TD/板卡耗时。
- 超预算原因：报告生成器/检查器的列名与格式迭代（CSV 打印精度 vs 检查容差、生成模板中 `%` 转义、128 行 check 重写）。未因此扩大范围、未新增授权、未放宽任何门槛、未猜数。
- 若综合测试者认为调用数超限构成流程违规，请按 FAIL/流程问题处理；本包全部产物可复现，不依赖未记录的手工步骤。

## 7. 写范围与只读输入合规

- 只写 `workflow/runs/20261025-233401_fpga-steady-state-reverdict/T10.ss-verdict-r1/**`；**0 删除**、0 批量删除。
- 未改：P1 目录、P2 原件、b6/b11、T08/T10、`fpga/csi2/src/**`、`upstream/**`、`workflow/tasks.json`、`docs/**`、`work/**`、run 根规划文件。
- 冻结前复算：P1 manifest `39f3e3d6…9f9a`、`steady-state.json` `a0945e1f…`、P2 manifest `5ed90500…36a6`、P2 `scenarios.csv` `2d806599…` 等 20 项输入 SHA 全部匹配（见 `input-verified.json`、`manifest-r0.json.read_only_inputs.recheck`）。

## 8. 未测 / not_proven（不得由本包升级）

- 内容：仅平滑梯度（A1）；自然图像/低照/噪声/全帧 comp 未测 → `not_proven_all_content`。
- DDR：行为级 PAXI；sustained/刷新/行切换/仲裁/单 outstanding 未测。
- 双核：无 Routed 构建、无 4 客户仲裁；`c2s2=C` 只是单核假设。
- 传输：sim sink 18.75 MB/s；真实 115200 仅诊断；PCIe 未做 → `transport=not_proven`。
- 时序/资源：单核 ≤187.5 MHz proven；200 MHz 与双核 unproven；本 run 0 次 TD。
- 板级/RK/Flash/下载：0；离线模型 PASS ≠ 生产/板级可行。

## 9. 回退

- 回退 = **不采用本任务目录**；保留全部失败/中间日志（`logs/` 内为最终成功轮的输出，无删除）。
- 不影响 P1/P2 冻结件与生产树；`workflow/tasks.json` 未改，T10 状态仍由原规划处置。
