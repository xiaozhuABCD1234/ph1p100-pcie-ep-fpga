# 开发结果 r0 — `T10.dual-aplus-service-verdict`

- run：`20261025-195604_fpga-dual-aplus-core-feasibility`；任务：`T10.dual-aplus-service-verdict` r0（round1 实际修复后重新冻结）
- 角色：fpga-dev（唯一开发；离线模型/表格/报告，**0 次 TD/综合/布线/bitgen/CWC/下载/板卡/ModelSim/RK**）
- 实际工作树：`D:/fpga/ph1p100`；写范围仅本任务 `r0/**`
- 状态：`ready_for_test`；r0 FAIL → round1 实际修复 1 轮后重新冻结；开发结束、停止修改
- 结论（模型输出，不是综合测试判定）：**双路 1920×1080@30 在 187.5 MHz、b6 冻结 core、共享单 DDR MC 下 `infeasible`；双核最高只能 `conditional`，且双核不能把 1080p30 的 per-stream 链级从 75.684 MB/s 提到 77.76 MB/s。主推荐 1600×900@30 单核单路在主档 feasible（36.1774%），但保守 overhead 档只有 21.0486% → conditional；三档稳健的最大档为 1440×810@30（最差 42.9485%）。**

## 0. round1 修复（针对 r0 综合测试 F1/F2/F3）

| 缺陷 | 修复 | 证据 |
|---|---|---|
| **F1** `frontier.csv` 的 core-only 行 basis 与 margin 不同源（16.7967/18.3184 配 meets_25） | frontier 新增 `margin_chain_pct`/`margin_core_pct`；`margin_pct` 与 `gate_25` 一律按 `capacity_basis` 同源（core_only → 核级 25.1036/28.7074/4.2530；chain → 链级）；报告 §9 由 CSV 渲染 | `out/frontier.csv`；`check_outputs.py` 新增 `frontier_core_only_margin_same_source` 等断言 |
| **F2** 冻结的三档 overhead 敏感性缺失，1600×900@30 在 1,000,000 档仅 21.0486% 仍写成无条件 feasible | 新增 `out/overhead-sensitivity.csv`（43×3=129 行；1080p 固定实测锚点、`applies=false`；逐档重算 verdict）；报告 §1/§5/§9/§10 披露主档 feasible、保守档 conditional；主推荐改为“带条件”，并新增三档稳健备选 1440×810（最差 42.9485%） | 129 行 CSV；§5 三档表；§9 三档 verdict；gen/check 的 1M 回归（21.0486/42.9485/6.7286） |
| **F3** 推荐未给“所需时钟” | `scenarios.csv` 新增 `required_clock_chain_25_mhz`/`required_clock_core_25_mhz`/`required_clock_chain_0_mhz`；`frontier.csv` 同步两列；报告 §9 每个推荐写链/核所需时钟（1600×900：172.1100/156.1206；1440×810：142.4471/126.4577；1080p@20：160.5353/149.8757 MHz） | 上述 CSV 列 + §9 文本 + `check_outputs.py` 时钟一致性断言 |

同步：43 行网格、计数（feasible 8 / conditional 22 / infeasible 13）、双核 feasible 0、1080p30 feasible 0 均未变；3 类负对照 5 个 fixture 仍全部被拒；P1 manifest `228531e7…bdd0` 与 b6 core `6797db05…35bb` 无漂移；写范围仍仅本任务目录。`test_calc` 128→**146** 项、`check_outputs` 85→**117** 项，全部 PASS。

## 1. 输入冻结（0 mismatch）

`model/gen_tables.py` 对 22 个输入逐个记录 path/bytes/SHA256，并执行 **97 项硬断言**；`mismatch_count=0` 后才写 `input-verified.json` 与 CSV。锚点：

| 对象 | 采用值 | 结果 |
|---|---|---|
| P1 manifest | `228531e7c16bca1a14898966c150b31bce464d7413f58078ae0bd724e894bdd0`（23,644 B） | pass |
| b6 core | `6797db053cfc47497540d6345e3a46b7e79cc1d34fa25da5a4c501505fbf35bb`（80,196 B） | pass |
| b6 manifest | `2e9fd356…8880`（24,443 B） | pass |
| comp | 355,261 cycles / 153,600 B / 81.067159 MB/s | pass（速率 ≤1e-6） |
| rand | 161,479 cycles / 178.351365 MB/s | pass（≤1e-5） |
| full_grad | 6,421,414 cycles，1080p 全帧 | pass |
| 字节账 | 2,592,000 / 4,147,200 / 2,594,750 / 8 MiB / 44 B / 2,592,128 / 2,592,768 / 2,594,706 | pass |
| 时钟 / 门槛 | 187.5 MHz / 25% | pass |
| 器件 | 300 ERAM / 129,024 LUT4 / 143,360 DFF / 220 DSP / 12 PLL / 71,680 slice+LUT6 站点 | pass |
| P1 预算 | marginal 231/300、conservative 289/300、LUT6 25,709/39,390、LUT4 51,418、REG 34,341/56,008、SLICE 30,733/48,736、2DDR 316/374 | pass |
| P1 第二路 CSI 敏感性 | 26,822 / 35,815 / 32,083（ERAM 不变） | pass |

`input-verified.json` 同时记录 11 个 snapshot（b11/T08/T10 result、180900 设计指南、本 run request/input-index/design-guide/dev-plan、b5 full_grad.stats、TB、DDR 文档）的实际 SHA；snapshot 漂移只记录、不改变锚点判定。

### 1.1 链级锚点边界（本轮核实，不是照抄）

- b6 `full_grad` 确为 **1920×1080 全帧**：P1 TB 默认 `W=1920/H=1080`（本次对 TB 源做正则断言），STAT `read_words=129600` 与 1080p 20B/32B RAW 槽（4,147,200 B / 32 B）一致。
- 6,421,414 cycles 是“相机模型→RAW 槽写→DDR 读→core→UART 导出”的**串行链**（行为级 DDR，不是 PAXI/DDR MC 时序）；因此 C_chain 作为系统口径，C_core 只作乐观上界。
- `full_grad.dec` 的 180,425 B **不是 payload**：TB 每个捕获字节写一行十进制文本（`$fwrite(fd,"%0d\n",dbg_byte)`），40,076 个捕获字节 = 180,425 B 文件。P1 报告中的 `.dec` 列因此不能用于推断几何。

### 1.2 冻结档位的打包边界

设计指南 §6.2/§6.4 声称 7 个 16:9 档 “W/H 均可被 4 整除”，但 **1440×810 的 H=810 不被 4 整除**。实际要求只是每行整 5B 组：W=1440 → 每行 360 组、stride 1,800 B、总 291,600 组，无 padding。模型按 `W%4==0 && W*H%4==0` 校验，7 档全部通过；该差异已写入 `input-verified.json.boundary_notes` 与报告 §2。未改设计指南（只读）。

## 2. 模型与规则

```text
model/calc.py          纯函数：几何/字节/槽/速率/裕量/所需时钟/面积当量/DDR 2R+2S/判定/三档 overhead/frontier/负对照校验
model/rules.json       冻结阈值、网格、R1–R6 判定、per-stream 规则、DDR 变体、overhead 三档、frontier 同源规则、推荐规则、负对照 fixture
model/test_calc.py     146 项：已知值、边界、4 组合、网格不变量、三档 overhead、所需时钟、frontier 同源、3 个负对照
model/gen_tables.py    冻结/断言输入（97 项）→ out/*.csv（含 overhead-sensitivity）；--journal 追加命令日志
model/render_report.py 只从 CSV + frozen-inputs 生成本报告；写 logs/report.sha256
model/check_outputs.py CSV 再生成逐字节比对、6 行手算、frontier basis 同源、三档回归、前沿极大性、报告 43 行逐格比对、报告哈希、负对照
```

判定机械应用 `rules.json`：R1 marginal>300 → infeasible；R2 per-stream 链级裕量<0 → infeasible；R3 双核时序 unproven → conditional；R4 链级≥25% 且 conservative≤270 且时序已证 → feasible；否则 conditional。`feasible` 从不使用 core-only、aggregate 或 synth 数据。

## 3. 生成物与关键结果

| 文件 | 行数 | 说明 |
|---|---:|---|
| `out/scenarios.csv` | 43 | 7 档几何×{1,2}核×{1,2}路（28）+ 1080p 双路帧率 25/24/20/15×2 核（8）+ 单核单路 1080p 帧率 25/24/20/15（4）+ 双核 1080p30 时钟 150/175/200（3，187.5 已含在几何网格） |
| `out/content-sensitivity.csv` | 3 | comp / rand / full_grad（comp 最慢 measured 核级；full_grad 唯一全帧链级） |
| `out/ddr-budget.csv` | 7 | 主路径、无 CMP DDR、1.0× 紧密变体、单路、1600×900@30、1080p20、960×540@30 |
| `out/frontier.csv` | 16 | 1080p fps 前沿（链级/核级、1c1s/1c2s/2c2s）与 30 fps 分辨率前沿；含 basis 同源 margin、三档最差 margin、所需时钟 |
| `out/overhead-sensitivity.csv` | 129 | 43 场景 × overhead {0, 426385, 1000000}；1080p 用实测锚点（applies=false），其余逐档重算 verdict |

**39→43 行说明**：设计指南 §6.2 的 39 行全部保留；另加 4 个单核单路 1080p 帧率档，因为 §6.3 规则 4 要求“1080p 下满足 25% 的最大 fps（单核/双核各一）”。没有删除任何组合，CSV 仍可枚举。

关键模型输出（全部由 calc.py 计算）：

| 量 | 值 |
|---|---:|
| 1080p30 per-stream 需求 / 25% 门槛 | 77.76 / 97.20 MB/s |
| 单核核级 comp | 81.067159 MB/s（+4.2530% @1080p30） |
| 单核链级 full_grad | 75.684265 MB/s（**−2.6694%** @1080p30；29.199 fps） |
| 链级 25% 最大 fps / 0% 最大 fps | 23.36 / 29.199 fps（1080p，单路） |
| 单核双路 per-stream 25% 最大 fps | 11.68 fps |
| 30 fps 链级 25% 最大档 / 核级 | 1600×900（36.1774%）/ 1728×972（28.7074%） |
| 所需时钟（链级 1080p30） | 192.642 MHz（0%）、240.803 MHz（25%） |
| DDR 主路径 2R+2S | 809.034 MB/s，required eff 12.6412%，gate 1,011.2925 MB/s（15.8014%） |
| 2×C_core / 2×C_chain | 162.134（≥155.52，聚合陷阱）/ 151.369（<155.52） |
| 场景计数 | feasible 8 / conditional 22 / infeasible 13；双核 feasible 0；1080p30 feasible 0 |
| overhead 三档的 30 fps c1s1 最大 25% 档 | 0 → 1728×972；426385 → 1600×900；1,000,000 → 1440×810 |
| 1600×900@30 三档链级裕量 | 50.1244% / 36.1774% / **21.0486%（<25%）** |
| 1440×810@30 三档最差 | **42.9485%（meets_25，三档稳健）** |
| 推荐所需时钟（链/核，25%） | 1600×900: 172.1100/156.1206；1440×810: 142.4471/126.4577；1080p@20: 160.5353/149.8757 MHz |

推荐（由规则选出，不是手写）：**主 1600×900@30 c1s1（主档 feasible 36.1774%，保守档 conditional 21.0486%——带条件）**；备选 1 **1440×810@30 c1s1（三档稳健，最差 42.9485%，feasible）**；备选 2 1080p@20 c1s1（feasible，45.9959%，三档相同）。1728×972@30（主档 18.3184%、保守档 6.7286%）与双核 1080p30 不推荐。

## 4. 本地检查（实际执行）

| # | 命令（cwd = 本 `r0/`） | exit | 结果 |
|---|---|---:|---|
| 1 | `python model/gen_tables.py --journal` | 0 | 97/97 断言 pass，mismatch 0，43/3/7/16/129 行；三档回归通过 |
| 2 | `python model/test_calc.py --journal` | 0 | **146/146 PASS**，含 3 个负对照（RAW12/1.0×、aggregate 2C、synth 混入）与三档/时钟断言 |
| 3 | `python model/render_report.py --journal` | 0 | 239 行报告 + `logs/report.sha256` |
| 4 | `python model/check_outputs.py --journal` | 0 | **117/117 PASS**：CSV 逐字节再生成、6 行手算、frontier basis 同源、三档回归、前沿极大性、报告 43 行逐格一致、报告哈希、P1/b6 漂移、负对照、无 TD 产物 |

负对照实际拒绝码：`PACKING_PROFILE_REJECTED`（RAW12）、`PACKING_MISMATCH`（1.0×）、`AGGREGATE_CAPACITY_FOR_PER_STREAM`（2C 当 per-stream）、`FEASIBLE_CLAIM_BELOW_PER_STREAM_GATE`（链级 −2.67% 仍声称 feasible）、`STAGE_MIX_SYNTH_IN_FIT`（synth 拟合）。

### 4.1 本轮修复历史（保留，不隐藏）

| 尝试 | exit | 根因 | 修正 |
|---|---:|---|---|
| gen #1 | 1 | `check_geometry` 要求 H%4==0，但冻结档 1440×810 的 H=810 不是 4 的倍数 | 改为只要求 W%4==0 且 W*H%4==0（行内组/stride 整数即可），补断言与报告说明 |
| test #1 | 1 | `grid_not_viable()` 仍读数值键 `margin_chain`，而 builder 行用 `margin_chain_pct` | 统一经 `_margin_frac()`，兼容 CSV/builder 两种行 |
| render #1 | 1 | `% ,d` 不是 Python 格式符 | 改 `format(x, ",")` |
| render/check #1 | 1 | CSV 行用裸 `join` 拼接，notes 含逗号导致列错位（报告 DDR/frontier 列出现串列） | `row_to_csv` 按 RFC4180 引号转义；gen/check/render 全部重跑 |
| check #2 | 1 | 只查 `26,822` 等带逗号形式，报告未格式化 | 报告统一 `format(...,",")` |
| round1-F1 | — | frontier 的 core-only 行用链级 margin 配 core_only basis | 新增 `margin_chain_pct`/`margin_core_pct`，`margin_pct`/`gate_25` 按 basis 同源；`check_outputs` 增同源断言 |
| round1-F2 | — | 三档 overhead 未落产物，1600×900 保守档 21.0486% 未披露 | 新增 129 行 `out/overhead-sensitivity.csv`；报告 §1/§5/§9/§10 披露；主推荐带条件 + 1440×810 三档稳健备选 |
| round1-F3 | — | 推荐缺所需时钟 | `scenarios.csv`/`frontier.csv` 增所需时钟列；§9 每个推荐给链/核时钟 |
| round1 check 调试 | 1 | 新增断言把 1,000,000 档最大 25% 档误写为 1600（实为 1440），且 CSV 行的 W 是字符串 | 按复算修正为 1728/1600/1440 并统一 `int()`；重跑 117/117 |

失败命令没有重试超过“首次+1 次有新证据”，失败文本保留在 `logs/*.out.txt`（最新一次）与本表。

## 5. 未测 / 不声称

- 未做 TD/综合/布线/bitgen/CWC/下载/板卡/ModelSim/RK；G2–G4 `not_applicable`。
- 未测：自然图像/低照/噪声内容；DDR 持续带宽/PAXI 仲裁/单拍效率；双核 Routed 时序/布局/拥塞；第二路完整 CSI 的 RTL 实现；第二路 FIFO 的 ERAM 映射；200 MHz 时序。
- 链级 overhead（426,385 cycles）跨内容恒定是 `assumed`，只在 full_grad 内容上 measured；`comp` 不是所有内容的严格上界。三档敏感性显示主推荐 1600×900 在 1,000,000 档只有 21.0486%（conditional），全档稳健档是 1440×810（42.9485%）。
- 1 核 2 路行的 ERAM 仍用单链 187/300（未加第二路 bridge+fabric 21 → 约 208/300）；仍 ≤270，不改变判定，但属保守偏低口径。
- 报告不声称板级吞吐、曝光同步、生产候选或双路系统完成；P2 离线 PASS 不等于双路目标完成。

## 6. 写范围与保护

- 只写 `T10.dual-aplus-service-verdict/r0/**`；未改 P1 产物、`fpga/csi2/src/**`、`upstream/**`、`D:/TD/work/csi2/**`、`D:/fpga_work/**`、b11/T08/T10 目录、`docs/**`、`workflow/tasks.json`、本 run 计划/指南/dispatch。
- 未删除任何文件；未使用批量删除；未映射 TD 盘符。

## 7. 回退

停止采用本 `r0/` 目录即可；证据与失败记录全部保留；不触碰生产/P1/其他 run。冻结入口：`manifest-r0.json`（`stopped_modifying=true, active_commands=0`）。
