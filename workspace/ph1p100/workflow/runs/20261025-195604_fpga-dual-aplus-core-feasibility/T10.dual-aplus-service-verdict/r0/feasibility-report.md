# 双路 A+ 双核/服务率可行性判定（P2：`T10.dual-aplus-service-verdict` r0）

- run：`20261025-195604_fpga-dual-aplus-core-feasibility`；任务：`T10.dual-aplus-service-verdict`
- 角色：fpga-dev（离线模型/表格/报告；**0 次 TD/综合/布线/bitgen/CWC/下载/板卡/ModelSim/RK**）
- 输入冻结：`input-verified.json`（P1 manifest `228531e7…bdd0`、b6 core `6797db05…35bb`、comp/rand/full_grad 锚点、字节账、187.5 MHz、25% 门槛；0 mismatch）
- 机器可读结果：`out/scenarios.csv`（43 行）、`out/content-sensitivity.csv`、`out/ddr-budget.csv`、`out/frontier.csv`、`out/overhead-sensitivity.csv`（129 行）；判定规则 `model/rules.json`；模型 `model/calc.py`
- 单位：MB = 10^6 B；MiB = 2^20 B；时钟 MHz。本报告不声称任何板级/实测吞吐。

## 1. 结论摘要

**双路 1920×1080@30 在 187.5 MHz、冻结 b6 core、共享单 DDR MC 下不可行（`infeasible`）；双核也不能改变 per-stream 结论：每核服务一路时 per-stream 容量仍是单核链级 75.684 MB/s，低于 25% 门槛 97.20 MB/s，也低于 30 fps 需求 77.760 MB/s（-2.67%）。双核资源最高只能判 `conditional`（conservative ERAM 289/300、双核 Routed 时序 unproven）。**

| 关键数字 | 值 | 标签 |
|---|---:|---|
| 单核核级 comp 容量 | 81.067159 MB/s（31.28 fps@1080p） | measured/derived（b6） |
| 单核链级 full_grad 容量 | 75.684265 MB/s（29.199 fps@1080p） | measured（b6 P1 STAT 全帧锚点） |
| 1080p30 per-stream 需求 / 25% 门槛 | 77.76 / 97.20 MB/s | derived |
| 双路总需求（仅 DDR/总量） | 155.52 MB/s | derived（**不用于 per-stream 判定**） |
| 双核 marginal / conservative ERAM | 231 / 289 / 300（余 69 / 11） | derived（P1） |
| 场景判定计数 | feasible 8 / conditional 22 / infeasible 13（共 43 行） | 本模型 |

一句话：**1080p30 的链级裕量是 -2.67%（比 25% 门槛低 22.14 个百分点）；双核只解决“两路并行”的资源/调度，不解决单路链级服务率。**

**三档 overhead 敏感性（设计指南 §4.3/§6.2，`out/overhead-sensitivity.csv`）**：主档 426,385 cycles 下 1600×900@30 链级 36.1774%（feasible）；保守档 1,000,000 cycles 下只有 21.0486%（<25%，按 R4 为 conditional），此时 30 fps 链级 25% 最大档退回 1440×810（42.9485%，三档均 ≥25%）。**因此主推荐带条件，不是无条件 feasible。**

## 2. 范围、冻结输入与标签

- 器件：PH1P100SBG484-3；ERAM20K 300、LUT4 129024、DFF 143360、DSP 220、PLL 12、slice 71680；LUT6 站点（TD 分母）71680，**不与 LUT4 混算**。
- 帧：1920×1080，RAW10 packed 1.25 B/px；`B_raw`=2,592,000 B；RAW 槽 20B/32B → `B_raw_slot`=4,147,200 B（129600 words），膨胀 1.6×；`B_content`=2,592,128；`B_dma`=2,592,768；CMP 最坏 2,594,706+44 = 2,594,750 B；CMP 槽 8 MiB。
- 锚点：comp 355261 cycles / 153600 B = 81.067159 MB/s；rand 161479 / 178.351365 MB/s；full_grad 6421414 cycles / 全帧 29.199 fps。
- **链级锚点边界（本轮核实）**：full_grad 是 1920×1080 全帧（TB 默认 W/H=1920/1080，STAT `read_words=129600` 证明 1080p RAW 槽几何），6421414 cycles 覆盖“相机模型→RAW 槽写→DDR 读→core→UART 导出”的串行链（行为级 DDR，不是 PAXI/DDR MC 时序）。`full_grad.dec` 的 180,425 B 是 TB 逐行十进制字节抓包（40,076 行），**不是 payload 尺寸**。
- **1440×810 档的打包边界**：H=810 不被 4 整除，但 W=1440 使每行 360 组、stride 1,800 B 为整数，total groups 291,600，packed 组连续存放即无 padding；设计指南“W/H 均可被 4 整除”对 810 不成立，模型按实际可分性（W%4==0 且 W*H%4==0）校验，7 档全部通过。
- 标签纪律：`measured`（b6/b10 routed、b6 STAT、P1）、`derived`（公式复算）、`assumed`（overhead 恒定 426385 cycles、slice 比例、共享 PHY、CSI 增量）、`unproven`（双核 Routed、DDR 持续效率、自然图像内容、200 MHz）。
- 工具：Python 3.11.5；无网络/随机；TD=0、ModelSim=0、硬件=0。

## 3. 单核资源/时序基线（Routed）

| source | ERAM 逻辑 | DRAMHARDCON | ERAM 合计 | LUT6/71,680 | REG/143,360 | SLICE/71,680 | DSP/220 | PLL/12 | WNS/hold (ns) | 违例/端点 |
|---|---|---|---|---|---|---|---|---|---|---|
| b10 r1（单链基线） | 102 | 85 | 187 | 19695 (27.48%) | 28004 (19.53%) | 24368 (34.00%) | 0 | 4 | +0.103/+0.020 | 0/24665 |
| b6（core 级） | — | — | — | — | — | — | — | — | +0.119/+0.020 | 0/19779 |

- 单链 102+85=**187/300**（62.33%），LUT6 19695/71,680；单核 Routed WNS +0.119/+0.103 属**薄余量**（hold 仅 +0.020）。
- 时序只在 187.5 MHz 的单核 Routed 上 measured；**双核 Routed 时序 unproven**，不得由 +0.119/+0.103 外推。

## 4. 双核资源表（P1 `228531e7…bdd0`）

| 栏 | ERAM 逻辑 | +DRAMHARDCON | ERAM 合计 | 余量 | LUT6/71,680 | LUT4 上界/129,024 | REG | SLICE | PLL | fit_300 | 时序 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| marginal（期望） | 146 | 85 | 231 | 69 (23.0%) | 25709 | 51418 | 34341 | 30733 | 4 | pass | unproven |
| conservative（上界） | 204 | 85 | 289 | 11 (3.67%) | 39390 | 78780 | 56008 | 48736 | 8 | conditional | unproven |

- **marginal 231/300（余 69，23.0%）pass；conservative 289/300（余 11，3.67%）落 271–300 → 按冻结规则只能 `conditional`。双核最高判定 = `conditional`，本 run 不存在双核 `feasible`。**
- 210 逻辑额度：marginal 146/210（余 64）、conservative 204/210（余 6）；双 DDR 控制器变体 marginal 316/300、conservative 374/300 → **fail**（默认共享 256-bit PAXI/DDR MC，不默认两端口）。
- **第二路完整 CSI 敏感性**：routed 只有 `u_csi_a`，`u_csi_b` 未实现/未计入 marginal；若需要，加 773 logic/340 ripple/1474 seq/0 ERAM → LUT6 **26,822**、REG **35,815**、SLICE 约 **32,083**，ERAM 231/300 与 fit 不变。

## 5. 服务率（core-only vs full-chain；per-stream vs aggregate）

per-stream 需求 `D_s = B_raw×fps`；1080p30 = **77.76 MB/s**，25% 门槛 **97.20 MB/s**。容量按每行 fps/时钟计算；`feasible` 只看 **per-stream full-chain** 裕量。

| cores | streams | per-stream 容量 basis | C_core_comp | C_chain | m_core | m_chain | drop_lb | gate | verdict |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | C | 81.067159 | 75.684265 | 4.2530% | -2.6694% | 2.6694% | fails_30 | infeasible |
| 1 | 2 | C/2（单核分时） | 81.067159 | 75.684265 | -47.8735% | -51.3347% | 51.3347% | fails_30 | infeasible |
| 2 | 1 | C | 81.067159 | 75.684265 | 4.2530% | -2.6694% | 2.6694% | fails_30 | infeasible |
| 2 | 2 | C（每核一路，**不是 2C**） | 81.067159 | 75.684265 | 4.2530% | -2.6694% | 2.6694% | fails_30 | infeasible |

- **aggregate 陷阱**：2×C_core = 162.134 ≥ 155.52，但这是聚合带宽；2×C_chain = 151.369 已 < 155.52，per-stream 更只有 75.684 < 77.76。双路 30 fps 只能看 per-stream。
- **core-only 陷阱**：1080p30 core-only 裕量 4.25%，看着“实时”；同一行链级 -2.67% → `fails_30`。core-only 只是乐观上界（无 DDR 读/槽管理/导出/仲裁）。
- 1080p 帧率梯（每路）：链级 25% 最大 **23.36 fps**，0% 最大 **29.199 fps**；核级 25% 最大 25.02 fps。单核双路的 per-stream 25% 最大只有 **11.68 fps**。
- 30 fps 分辨率前沿：链级 25% 最大 **1600×900**（36.18%），核级 25% 最大 1728×972（28.71%）；1080p30 链级固定差 -2.67%。
- 1080p30 双核时钟梯（每核一路）：150/175/187.5/200 MHz 的链级裕量见 §8/`out/scenarios.csv`；200 MHz 仍只有 3.82% 且 200 MHz 时序 unproven。
- **1 核 2 路 ERAM 口径**：这些行的 ERAM bound 仍用单链 187/300，**未**把第二路 bridge 15 + stream fabric 6 = 21 计入（合计约 208/300，仍 ≤270，verdict 不变）；这是偏保守偏低的口径，已在 `out/scenarios.csv` 的 notes 写明。

overhead 三档敏感性（`out/overhead-sensitivity.csv`；1080p 固定实测锚点，tier 不适用）：

| overhead tier | 30 fps c1s1 最大 25% 档 | 该档 margin | 1600×900 margin | 1440×810 margin | 1728×972 margin |
|---|---|---|---|---|---|
| 0 cycles | 1728×972 | 28.7074% | 50.1244% | 85.3387% | 28.7074% |
| 426385 cycles | 1600×900 | 36.1774% | 36.1774% | 64.5348% | 18.3184% |
| 1000000 cycles | 1440×810 | 42.9485% | 21.0486% | 42.9485% | 6.7286% |

- 主档（426,385）的最大 25% 档是 1600×900；保守档（1,000,000）退回 1440×810。**1600×900 在保守档只有 21.0486% <25%，因此主推荐必须写成“主档 feasible / 保守档 conditional”。**

内容敏感性（`out/content-sensitivity.csv`）：

| case | basis | cycles | capacity MB/s | fps@1080p | margin@30 | gate | label |
|---|---|---|---|---|---|---|---|
| comp_core_1080p | core_only | 355261 | 81.067159 | 31.275910 | 4.2530% | below_25 | measured |
| rand_core_1080p | core_only | 161479 | 178.351365 | 68.808397 | 129.3613% | meets_25 | measured |
| full_grad_chain_1080p | full_chain | 6421414 | 75.684265 | 29.199176 | -2.6694% | fails_30 | measured |

- comp 是最慢的 measured 核级向量；full_grad 是唯一全帧链级锚点。**自然图像/低照/噪声未测**，comp 不是所有内容的严格上界；链级 overhead 跨内容恒定是 `assumed`。

## 6. DDR 2R+2S

公式：`R_w=R_r=D_total×1.6`；`S_w=S_r=B_cmp_total×fps×streams/1e6`（worst stored）；`DDR_total=R_w+R_r+S_w+S_r`；`gate=DDR_total×1.25`；`required_eff=DDR_total/6400`。6,400 MB/s 是 ×32 1600 MT/s 理论峰值，**未扣刷新/行切换/仲裁/命令开销，不是实测**。

| case | streams | fps | raw W | raw R | cmp W | cmp R | total | gate+25% | required eff | 含 CMP DDR | layout |
|---|---|---|---|---|---|---|---|---|---|---|---|
| dual_1080p30_main | 2 | 30 | 248.832000 | 248.832000 | 155.685000 | 155.685000 | 809.034000 | 1011.292500 | 12.6412% | true | 20B_payload_per_32B_word |
| dual_1080p30_no_cmp_ddr | 2 | 30 | 248.832000 | 248.832000 | 0.000000 | 0.000000 | 497.664000 | 622.080000 | 7.7760% | false | 20B_payload_per_32B_word |
| dual_1080p30_tight_1p0x | 2 | 30 | 155.520000 | 155.520000 | 155.685000 | 155.685000 | 622.410000 | 778.012500 | 9.7252% | true | packed_1.0x_tight |
| single_1080p30_main | 1 | 30 | 124.416000 | 124.416000 | 77.842500 | 77.842500 | 404.517000 | 505.646250 | 6.3206% | true | 20B_payload_per_32B_word |
| dual_1600x900_30_main | 2 | 30 | 172.800000 | 172.800000 | 108.138000 | 108.138000 | 561.876000 | 702.345000 | 8.7793% | true | 20B_payload_per_32B_word |
| dual_1080p20_main | 2 | 20 | 165.888000 | 165.888000 | 103.790000 | 103.790000 | 539.356000 | 674.195000 | 8.4274% | true | 20B_payload_per_32B_word |
| dual_960x540_30_main | 2 | 30 | 62.208000 | 62.208000 | 38.964000 | 38.964000 | 202.344000 | 252.930000 | 3.1616% | true | 20B_payload_per_32B_word |

- 主路径（双路 1080p30，20B/32B，含 CMP DDR）总需求 **809.034000 MB/s**，所需效率 **12.6412%**，25% 门槛下也只有 **1011.292500 MB/s（15.8014% 峰值）**。**平均带宽不是主要瓶颈**，但桥的 latency/outstanding/单拍效率仍未证明。
- 变体：不含 CMP DDR 497.664000 MB/s（7.7760%）；20261025-180900 紧密 1.0× 布局 622.410000 MB/s（9.7252%）——**后者不是本 run 采用的主动路径**。排除项（预览/显示、诊断 RAW、元数据、ECC、刷新）另计。

## 7. 调度/缓冲服务率与丢帧下界

- 假设（与 T08/T10 合同一致）：每路 2 RAW 槽/2 CMP 槽、帧级公平、一编码器一次一帧不抢占；无空闲 RAW 槽 → 丢整帧并记 capture_seq 缺口；CMP 满 → 持有 RAW 槽。
- 双核：每核固定服务一路，per-stream = C；单核双路：帧级轮转，长期每路 50%，per-stream = C/2。
- 稳态丢帧下界 `drop_rate_lb = max(0, 1 − C_service/D_s)`，`C_service` 一律取 **per-stream 链级**（本表 `drop_rate_lb_basis` 列）；它是**下界**，实际仲裁/空窗可能更差。
- 1080p30：单核单路丢帧下界 **2.6694%**、单核双路 **51.3347%**、双核双路 **2.6694%**（双核不改变 per-stream）。
- `drop_rate_lb=0` 只表示算术上不积压，**不等于满足 25% 设计裕量**；`gate_25` 单列。本 run 只做帧级下界，不做周期级调度/one-outstanding reader/PAXI 仲裁仿真。

## 8. 判定表（43 行，机械应用 `model/rules.json`）

判定顺序：R1 marginal ERAM>300 → infeasible；R2 per-stream 链级裕量<0 → infeasible；R3 双核时序 unproven → conditional；R4 链级≥25% 且 conservative≤270 且时序已证 → feasible；否则 conditional。`gate_status` 按 per-stream 链级裕量。

| scenario_id | c | s | W×H | fps | clk | C_core | C_chain | m_core% | m_chain% | drop_lb% | gate | verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1920x1080-30fps-c1s1-187.5MHz | 1 | 1 | 1920×1080 | 30 | 187.5 | 81.067159 | 75.684265 | 4.2530 | -2.6694 | 2.6694 | fails_30 | infeasible |
| 1920x1080-30fps-c1s2-187.5MHz | 1 | 2 | 1920×1080 | 30 | 187.5 | 81.067159 | 75.684265 | -47.8735 | -51.3347 | 51.3347 | fails_30 | infeasible |
| 1920x1080-30fps-c2s1-187.5MHz | 2 | 1 | 1920×1080 | 30 | 187.5 | 81.067159 | 75.684265 | 4.2530 | -2.6694 | 2.6694 | fails_30 | infeasible |
| 1920x1080-30fps-c2s2-187.5MHz | 2 | 2 | 1920×1080 | 30 | 187.5 | 81.067159 | 75.684265 | 4.2530 | -2.6694 | 2.6694 | fails_30 | infeasible |
| 1728x972-30fps-c1s1-187.5MHz | 1 | 1 | 1728×972 | 30 | 187.5 | 81.067159 | 74.523525 | 28.7074 | 18.3184 | 0.0000 | below_25 | conditional |
| 1728x972-30fps-c1s2-187.5MHz | 1 | 2 | 1728×972 | 30 | 187.5 | 81.067159 | 74.523525 | -35.6463 | -40.8408 | 40.8408 | fails_30 | infeasible |
| 1728x972-30fps-c2s1-187.5MHz | 2 | 1 | 1728×972 | 30 | 187.5 | 81.067159 | 74.523525 | 28.7074 | 18.3184 | 0.0000 | below_25 | conditional |
| 1728x972-30fps-c2s2-187.5MHz | 2 | 2 | 1728×972 | 30 | 187.5 | 81.067159 | 74.523525 | 28.7074 | 18.3184 | 0.0000 | below_25 | conditional |
| 1600x900-30fps-c1s1-187.5MHz | 1 | 1 | 1600×900 | 30 | 187.5 | 81.067159 | 73.535823 | 50.1244 | 36.1774 | 0.0000 | meets_25 | feasible |
| 1600x900-30fps-c1s2-187.5MHz | 1 | 2 | 1600×900 | 30 | 187.5 | 81.067159 | 73.535823 | -24.9378 | -31.9113 | 31.9113 | fails_30 | infeasible |
| 1600x900-30fps-c2s1-187.5MHz | 2 | 1 | 1600×900 | 30 | 187.5 | 81.067159 | 73.535823 | 50.1244 | 36.1774 | 0.0000 | meets_25 | conditional |
| 1600x900-30fps-c2s2-187.5MHz | 2 | 2 | 1600×900 | 30 | 187.5 | 81.067159 | 73.535823 | 50.1244 | 36.1774 | 0.0000 | meets_25 | conditional |
| 1440x810-30fps-c1s1-187.5MHz | 1 | 1 | 1440×810 | 30 | 187.5 | 81.067159 | 71.967512 | 85.3387 | 64.5348 | 0.0000 | meets_25 | feasible |
| 1440x810-30fps-c1s2-187.5MHz | 1 | 2 | 1440×810 | 30 | 187.5 | 81.067159 | 71.967512 | -7.3306 | -17.7326 | 17.7326 | fails_30 | infeasible |
| 1440x810-30fps-c2s1-187.5MHz | 2 | 1 | 1440×810 | 30 | 187.5 | 81.067159 | 71.967512 | 85.3387 | 64.5348 | 0.0000 | meets_25 | conditional |
| 1440x810-30fps-c2s2-187.5MHz | 2 | 2 | 1440×810 | 30 | 187.5 | 81.067159 | 71.967512 | 85.3387 | 64.5348 | 0.0000 | meets_25 | conditional |
| 1280x720-30fps-c1s1-187.5MHz | 1 | 1 | 1280×720 | 30 | 187.5 | 81.067159 | 69.883859 | 134.5693 | 102.2102 | 0.0000 | meets_25 | feasible |
| 1280x720-30fps-c1s2-187.5MHz | 1 | 2 | 1280×720 | 30 | 187.5 | 81.067159 | 69.883859 | 17.2847 | 1.1051 | 0.0000 | below_25 | conditional |
| 1280x720-30fps-c2s1-187.5MHz | 2 | 1 | 1280×720 | 30 | 187.5 | 81.067159 | 69.883859 | 134.5693 | 102.2102 | 0.0000 | meets_25 | conditional |
| 1280x720-30fps-c2s2-187.5MHz | 2 | 2 | 1280×720 | 30 | 187.5 | 81.067159 | 69.883859 | 134.5693 | 102.2102 | 0.0000 | meets_25 | conditional |
| 1152x648-30fps-c1s1-187.5MHz | 1 | 1 | 1152×648 | 30 | 187.5 | 81.067159 | 67.693376 | 189.5918 | 141.8173 | 0.0000 | meets_25 | feasible |
| 1152x648-30fps-c1s2-187.5MHz | 1 | 2 | 1152×648 | 30 | 187.5 | 81.067159 | 67.693376 | 44.7959 | 20.9087 | 0.0000 | below_25 | conditional |
| 1152x648-30fps-c2s1-187.5MHz | 2 | 1 | 1152×648 | 30 | 187.5 | 81.067159 | 67.693376 | 189.5918 | 141.8173 | 0.0000 | meets_25 | conditional |
| 1152x648-30fps-c2s2-187.5MHz | 2 | 2 | 1152×648 | 30 | 187.5 | 81.067159 | 67.693376 | 189.5918 | 141.8173 | 0.0000 | meets_25 | conditional |
| 960x540-30fps-c1s1-187.5MHz | 1 | 1 | 960×540 | 30 | 187.5 | 81.067159 | 63.112216 | 317.0121 | 224.6513 | 0.0000 | meets_25 | feasible |
| 960x540-30fps-c1s2-187.5MHz | 1 | 2 | 960×540 | 30 | 187.5 | 81.067159 | 63.112216 | 108.5061 | 62.3257 | 0.0000 | meets_25 | feasible |
| 960x540-30fps-c2s1-187.5MHz | 2 | 1 | 960×540 | 30 | 187.5 | 81.067159 | 63.112216 | 317.0121 | 224.6513 | 0.0000 | meets_25 | conditional |
| 960x540-30fps-c2s2-187.5MHz | 2 | 2 | 960×540 | 30 | 187.5 | 81.067159 | 63.112216 | 317.0121 | 224.6513 | 0.0000 | meets_25 | conditional |
| 1920x1080-25fps-c1s2-187.5MHz | 1 | 2 | 1920×1080 | 25 | 187.5 | 81.067159 | 75.684265 | -37.4482 | -41.6016 | 41.6016 | fails_30 | infeasible |
| 1920x1080-25fps-c2s2-187.5MHz | 2 | 2 | 1920×1080 | 25 | 187.5 | 81.067159 | 75.684265 | 25.1036 | 16.7967 | 0.0000 | below_25 | conditional |
| 1920x1080-24fps-c1s2-187.5MHz | 1 | 2 | 1920×1080 | 24 | 187.5 | 81.067159 | 75.684265 | -34.8419 | -39.1684 | 39.1684 | fails_30 | infeasible |
| 1920x1080-24fps-c2s2-187.5MHz | 2 | 2 | 1920×1080 | 24 | 187.5 | 81.067159 | 75.684265 | 30.3163 | 21.6632 | 0.0000 | below_25 | conditional |
| 1920x1080-20fps-c1s2-187.5MHz | 1 | 2 | 1920×1080 | 20 | 187.5 | 81.067159 | 75.684265 | -21.8102 | -27.0021 | 27.0021 | fails_30 | infeasible |
| 1920x1080-20fps-c2s2-187.5MHz | 2 | 2 | 1920×1080 | 20 | 187.5 | 81.067159 | 75.684265 | 56.3796 | 45.9959 | 0.0000 | meets_25 | conditional |
| 1920x1080-15fps-c1s2-187.5MHz | 1 | 2 | 1920×1080 | 15 | 187.5 | 81.067159 | 75.684265 | 4.2530 | -2.6694 | 2.6694 | fails_30 | infeasible |
| 1920x1080-15fps-c2s2-187.5MHz | 2 | 2 | 1920×1080 | 15 | 187.5 | 81.067159 | 75.684265 | 108.5061 | 94.6612 | 0.0000 | meets_25 | conditional |
| 1920x1080-25fps-c1s1-187.5MHz | 1 | 1 | 1920×1080 | 25 | 187.5 | 81.067159 | 75.684265 | 25.1036 | 16.7967 | 0.0000 | below_25 | conditional |
| 1920x1080-24fps-c1s1-187.5MHz | 1 | 1 | 1920×1080 | 24 | 187.5 | 81.067159 | 75.684265 | 30.3163 | 21.6632 | 0.0000 | below_25 | conditional |
| 1920x1080-20fps-c1s1-187.5MHz | 1 | 1 | 1920×1080 | 20 | 187.5 | 81.067159 | 75.684265 | 56.3796 | 45.9959 | 0.0000 | meets_25 | feasible |
| 1920x1080-15fps-c1s1-187.5MHz | 1 | 1 | 1920×1080 | 15 | 187.5 | 81.067159 | 75.684265 | 108.5061 | 94.6612 | 0.0000 | meets_25 | feasible |
| 1920x1080-30fps-c2s2-150MHz | 2 | 2 | 1920×1080 | 30 | 150 | 64.853727 | 60.547412 | -16.5976 | -22.1355 | 22.1355 | fails_30 | infeasible |
| 1920x1080-30fps-c2s2-175MHz | 2 | 2 | 1920×1080 | 30 | 175 | 75.662682 | 70.638648 | -2.6972 | -9.1581 | 9.1581 | fails_30 | infeasible |
| 1920x1080-30fps-c2s2-200MHz | 2 | 2 | 1920×1080 | 30 | 200 | 86.471636 | 80.729883 | 11.2032 | 3.8193 | 0.0000 | below_25 | conditional |

- 计数：feasible **8**、conditional **22**、infeasible **13**；gate：meets_25 20、below_25 10、fails_30 13。双核 feasible 行 **0**；1080p30 feasible 行 **0**。
- 网格说明：设计指南 §6.2 的 39 行 = 7 档几何×4 组合 + 8 个 1080p 双路帧率 + 3 个附加时钟档；本表另加 4 个**单核单路 1080p 帧率档**（25/24/20/15 fps），因为 §6.3 规则 4 要求给出“1080p 下满足 25% 的最大 fps（单核/双核各一）”；合计 43 行，未删任何 §6.2 组合。

## 9. Pareto 前沿与推荐（1 主 + ≤2 备选）

| family | c | s | W×H | fps | clk | basis | margin% | gate | worst tier% | worst gate | verdict | rec | req chain clk | req core clk | notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1080p_fps_chain | 1 | 1 | 1920×1080 | 20 | 187.5 | full_chain_anchor | 45.9959 | meets_25 | 45.9959 | meets_25 | feasible | true | 160.5353 | 149.8757 | max grid fps meeting 25% at 1080p (continuous 23.36 fps); alternate_fps (anchor fixed, tier-invariant) |
| 1080p_fps_chain | 1 | 1 | 1920×1080 | 30 | 187.5 | full_chain_anchor | -2.6694 | fails_30 | -2.6694 | fails_30 | infeasible | false | 240.8030 | 224.8136 | target row: chain cannot hold 30 fps (0% max 29.20 fps); core-only 0% max 31.28 fps |
| 1080p_fps_chain | 2 | 2 | 1920×1080 | 20 | 187.5 | full_chain_anchor | 45.9959 | meets_25 | 45.9959 | meets_25 | conditional | false | 160.5353 | 149.8757 | dual-core row is conditional (no dual-core Routed build); 2C=151.37 MB/s aggregate is not the per-stream capacity |
| 1080p_fps_chain | 2 | 2 | 1920×1080 | 30 | 187.5 | full_chain_anchor | -2.6694 | fails_30 | -2.6694 | fails_30 | infeasible | false | 240.8030 | 224.8136 | 2xC_core aggregate 162.13 >= 155.52 would look OK, but per-stream chain 75.68 < 77.76 and 2xC_chain 151.37 < 155.52 (negative-control trap) |
| 1080p_fps_core_only | 1 | 1 | 1920×1080 | 25 | 187.5 | core_only_comp | 25.1036 | meets_25 | 25.1036 | meets_25 | core_only_upper_bound | false | 200.6692 | 187.3447 | optimistic core-only upper bound: max grid fps meeting 25% (continuous 25.02 fps); not a system basis; core margin is overhead-independent |
| 1080p_fps_core_only | 1 | 1 | 1920×1080 | 30 | 187.5 | core_only_comp | 4.2530 | below_25 | 4.2530 | below_25 | core_only_upper_bound | false | 240.8030 | 224.8136 | core-only margin 4.25% is below the 25% gate and ignores DDR/export |
| 30fps_res_chain | 1 | 1 | 1600×900 | 30 | 187.5 | full_chain_affine | 36.1774 | meets_25 | 21.0486 | below_25 | feasible | true | 172.1100 | 156.1206 | primary recommendation at the main overhead tier 426385; conservative tier 1000000 drops to 21.0486% (below 25%) |
| 30fps_res_chain | 1 | 1 | 1440×810 | 30 | 187.5 | full_chain_affine | 64.5348 | meets_25 | 42.9485 | meets_25 | feasible | true | 142.4471 | 126.4577 | robust alternate: largest 30 fps tier meeting 25% in all three overhead tiers (worst 42.9485%) |
| 30fps_res_chain | 1 | 1 | 1728×972 | 30 | 187.5 | full_chain_affine | 18.3184 | below_25 | 6.7286 | below_25 | conditional | false | 198.0885 | 182.0990 | higher resolution but below 25% at the main tier and worse at the conservative tier (worst 6.7286%); not recommended |
| 30fps_res_chain | 1 | 1 | 1920×1080 | 30 | 187.5 | full_chain_anchor | -2.6694 | fails_30 | -2.6694 | fails_30 | infeasible | false | 240.8030 | 224.8136 | 1080p30 chain is 2.66% short; no resolution-tier rescue at this geometry |
| 30fps_res_core_only | 1 | 1 | 1728×972 | 30 | 187.5 | core_only_comp | 28.7074 | meets_25 | 28.7074 | meets_25 | core_only_upper_bound | false | 198.0885 | 182.0990 | core-only would allow 1728x972 (28.71%), but the same row fails at chain level (18.32%) |
| 30fps_res_core_only | 1 | 1 | 1920×1080 | 30 | 187.5 | core_only_comp | 4.2530 | below_25 | 4.2530 | below_25 | core_only_upper_bound | false | 240.8030 | 224.8136 | core-only 1080p30 margin 4.25% is below 25% |
| 30fps_res_chain_1c2s | 1 | 2 | 960×540 | 30 | 187.5 | full_chain_affine | 62.3257 | meets_25 | 25.0622 | meets_25 | feasible | false | 72.1928 | 56.2034 | max tier where one core time-sharing two streams still meets 25% per stream |
| 30fps_res_chain_1c2s | 1 | 2 | 1152×648 | 30 | 187.5 | full_chain_affine | 20.9087 | below_25 | -1.0516 | fails_30 | conditional | false | 96.9223 | 80.9329 | next tier up; per-stream margin 20.91% is below 25% |
| 1080p_fps_chain | 1 | 2 | 1920×1080 | 15 | 187.5 | full_chain_anchor | -2.6694 | fails_30 | -2.6694 | fails_30 | infeasible | false | 120.4015 | 112.4068 | single core serving two 1080p streams: best grid fps still short; continuous 25% max 11.68 fps per stream |
| 30fps_res_chain | 2 | 2 | 1600×900 | 30 | 187.5 | full_chain_affine | 36.1774 | meets_25 | 21.0486 | below_25 | conditional | false | 172.1100 | 156.1206 | dual-core does not raise per-stream capacity; same 1600x900 row is conditional (no dual-core Routed build, conservative ERAM 289) |

**主推荐（带条件）：1600×900@30（单核单路）** —— 主档 426,385 cycles 链级裕量 **36.1774%**（meets_25）；保守档 1,000,000 cycles 下 **21.0486%**（below_25；该档 verdict = `conditional`）。所需时钟：链 **172.1100 MHz** / 核 **156.1206 MHz**（25% 门槛；均低于已验证的 187.5 MHz，不需要超频）。ERAM **187/300**。**不是无条件 feasible，也不是 1080p。**

**备选 1（三档稳健）：1440×810@30（单核单路）** —— 三档 overhead 下链级裕量最小 **42.9485%**（meets_25），所需时钟 链 **142.4471 MHz** / 核 **126.4577 MHz**；ERAM 187/300 → 三档均 `feasible`。

**备选 2（全分辨率降帧）：1920×1080@20（单核单路）** —— 链级裕量 **45.9959%**（1080p 实测锚点固定，三档相同），所需时钟 链 **160.5353 MHz** / 核 **149.8757 MHz** → `feasible`。

- **不推荐**：双核 2×1080p30（链级 -2.67%，`fails_30`；双核时序 unproven；conservative 289/300）；单核双路 1080p（per-stream 只有 C/2）；1728×972@30（主档 18.3184%、保守档 6.7286%，均低于 25%）。
- 前沿极大性：主档 30 fps 链级 25% 最大档 1600×900（1600x900-30fps-c1s1-187.5MHz）；全档稳健最大档 1440×810；1080p 链级 25% 最大 fps 20（单核）；1c2s 最大 960×540。

## 10. 什么会改变结论（可测阈值）

- **时钟**：链级 1080p30 需 ≥ **192.642 MHz** 才到 0%、≥ **240.803 MHz** 才到 25%；当前 187.5 MHz（+2.74% / +28.43%）。200 MHz 只有 3.82% 且 unproven。
- **链级 cycles/frame**：25% 需 ≤ **5,000,000**（当前 6,421,414，需减少 **22.14%**）；0% 需 ≤ **6,250,000**（当前已 2.74% 超出）。即使 overhead 归零，核级也需 ≤ **1.9288 cycles/B**（comp 现为 2.3129，需快 16.61%）。
- **核级**：25% 需 ≥ **25.02 fps**@1080p（需 ≥ 224.814 MHz 或同比减少 cycles）；当前核级 31.276 fps 只够 0%。
- **分辨率**：30 fps 链级 25% 最大档 1600×900；1728×972 只有 18.3184%（可实时但低于门槛）。
- **overhead 档**：1600×900@30 在保守档（1,000,000 cycles）只有 21.0486%；要让该档也满足 25%，链级 overhead 必须 ≤ 836785 cycles（当前 1,000,000）。1440×810 的对应上限是 1627796 cycles，因此它是三档稳健档。
- **DDR**：主路径需持续 **809.034000 MB/s**（0%）/ **1011.292500 MB/s**（25% 门槛）。若实测持续带宽低于 809 MB/s，或 PAXI 仲裁/单拍效率使有效带宽低于该值，DDR 会取代 core 成为瓶颈。
- **内容**：若自然图像的核级 cycles/B > 2.3129（comp）或全帧链级 > 6,421,414 cycles，结论只会更差；要让 1080p30 25% 成立，链级必须 ≤ 5,000,000 cycles（比 measured 锚点少 22.14%）。
- **双核资源/时序**：即使双核 Routed 时序通过，conservative 仍 289/300 > 270 → 仍 `conditional`；而 per-stream 链级不变，1080p30 仍 `fails_30`。**双核不是 1080p30 的解。**
- **第二 DDR 控制器**：marginal 316/300、conservative 374/300 → 双核直接 `infeasible`，必须保持共享单 DDR MC。

## 11. 风险、未测、G 层与复现

| 风险/未测 | 影响 | 现状 |
|---|---|---|
| 自然图像/低照/噪声未测 | comp 可能不是最坏内容，实时性更差 | `unproven`，不得称“保证” |
| 链级锚点单一内容 | overhead 426385 cycles 跨内容恒定是 assumed | 仅 full_grad 一例 |
| overhead 档依赖 | 主推荐只在 assumed 主档 ≥25%，保守档降为 conditional | `out/overhead-sensitivity.csv` 129 行；§1/§5/§9 已披露 |
| 双核 Routed 时序/布局/拥塞 | 可能改变 WNS | `unproven`；本 run 无 TD |
| DDR 持续带宽/PAXI 仲裁/单拍效率 | 平均够 ≠ 实际够 | `unproven`，只有 required efficiency |
| 第二路完整 CSI 未实现 | marginal 少 773/340/1,474 | 补算 LUT6 26,822/REG 35,815/SLICE 32,083，ERAM 不变 |
| 精确 LUT4、第二路 FIFO ERAM 映射、去 CWC 后真实 ERAM | 资源可能偏移 | 只有上界/assumed |
| 周期级调度/one-outstanding reader | 帧级下界可能偏乐观 | 未仿真；T10 scheduler 无 PASS 报告 |
| RK/PCIe/板级/曝光同步 | 无系统级吞吐/恢复结论 | 全部 not_run |

G 层：**G0 pass**（输入 SHA/字节，0 mismatch）、**G1 pass**（模型/CSV/报告可复现，3 个负对照被拒）、**G2/G3/G4 not_applicable**（无 RTL/综合/布线/bit/板卡）。离线 PASS 不等于双路系统完成。

复现（cwd = 本任务 `r0/`）：

```powershell
python model/gen_tables.py      # 冻结/校验输入 + 生成 out/*.csv；mismatch 必须为 0
python model/test_calc.py       # 已知值/边界/3 个负对照；必须 exit 0
python model/render_report.py   # 由 CSV 生成本报告
python model/check_outputs.py   # CSV↔报告一致性 + 前沿极大性 + 负对照；必须 exit 0
```

