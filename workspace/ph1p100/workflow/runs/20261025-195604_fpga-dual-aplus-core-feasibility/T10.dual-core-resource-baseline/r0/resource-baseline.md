# 单核资源/时序基线 + 双核资源预算（P1：`T10.dual-core-resource-baseline`）

- run：`20261025-195604_fpga-dual-aplus-core-feasibility`；任务：`T10.dual-core-resource-baseline` r0
- 角色：fpga-dev（离线，只读报告解析；不跑 TD/综合/布线/bitgen/CWC/下载/板卡/RK）
- 日期：2026-10-25
- 输入冻结：`input-verified.json`（27 个输入，硬断言 11 项，`mismatch_count=0`）
- 机器可读表：`resource-table.csv`（64 行：3 routed 顶层 + 3 synth 顶层 + 58 层次行）、`dual-core-budget.csv`（marginal / conservative + 2 个双 DDR 变体）
- 独立复算：`check_tables.py`（自己重新解析报告与 CSV，5 组检查 + 3 个负对照，`logs/check_tables.out.txt`，exit 0）

## 1. 结论摘要

**单核（b10 r1，整机单链、Routed）实测 102 ERAM 逻辑 + 85 DRAMHARDCON = 187/300（62.33%）；双核 marginal 栏 146 + 85 = 231/300（余量 69，23.0%）可装入且满足 210 逻辑额度（146/210）；conservative 栏 204 + 85 = 289/300（余量 11，3.67%）落在 271–300 的“仅边际成立”区，按本 run 冻结规则只能判 `conditional`。marginal 的 TD LUT6 当量为 25,709/71,680（35.9%），LUT4 上界 51,418/129,024（39.9%），均远低于器件。**

| 关键数字 | 值 | 标签 |
|---|---:|---|
| 单链 Routed ERAM（逻辑 + 硬核） | 102 + 85 = **187/300** | measured + derived |
| 双核 `marginal` ERAM | **231/300**，余量 69（23.0%） | derived（基线与层次增量 measured） |
| 双核 `conservative` ERAM | **289/300**，余量 11（3.67%） | derived/upper bound |
| 单链 Routed WNS / hold | **+0.103 / +0.020 ns**，0/24,665 | measured |
| 双核时序 | **unproven**（无任何双核 Routed 构建） | unproven |
| 资源结论 | **conditional**：marginal 成立；conservative 仅边际成立，需 P3/后续综合确认 | derived |

- 若需要**第二颗 DDR 控制器/端口**（不共享现有 256-bit PAXI/DDR MC）：marginal 316/300、conservative 374/300，均 `fail`；默认架构是共享单 DDR MC，故单列为变体，不作主结论。
- 本报告**不回答**双路 1080p30 服务率（P2），**不声称**双核 Routed/G2/板级通过；不把单核 +0.103/+0.119 外推为双核时序。

## 2. 冻结输入与工具

- b6 core：`r0/changed-src/a1_deflate_core.v`，80,196 B，SHA256 `6797db053cfc47497540d6345e3a46b7e79cc1d34fa25da5a4c501505fbf35bb`（硬断言通过）
- b6 manifest：SHA256 `2e9fd356824084813e3415af11757c1b56f774c9b6dd45f3b2a111647ad08880`（硬断言通过；manifest 内 `single_rtl_change` 节点与 core 一致；b6 独立报告同时携带该 manifest 哈希与 core 短哈希）
- 报告头（b6/b10/b11 三份 `routed_timing.rpt` 一致）：`Tang Dynasty Release_2026.2`、`TD V6.2.3.210850`、`PH1P100SBG484`、`Speed 3`、`Confidence Routed`、`Constraint File p2_board.sdc`、`Check Corner Both (Slow and Fast)`。
- 工具：Python 3.11.5；**0 次 TD/综合/布线/bitgen/CWC/下载/板卡**。全部输入 path/bytes/SHA256 见 `input-verified.json`，27/27 在检查时重新哈希无漂移。

**顶层识别（实测澄清）**：三份 `routed_area.rpt` 的报告头均为 `Report Model: p2_a1_board_top`。b6 不是“只有 core 的小顶层”，而是同一 board top 的较小功能集（LUT6 18,743、REG 25,135，对比 b10 19,695/28,004），其 102 ERAM 与 b10/b11 相同。因此用 102 作单链基线与本 run 设计指南 §2.3/§3.2 的采用值一致；不改变任何冻结数字。

## 3. 单核权威基线（只用 Routed）

| source | stage | ERAM 逻辑 | DRAMHARDCON | ERAM 合计 | LUT6 /71,680 | REG /143,360 | SLICE /71,680 | DSP /220 | PLL /12 | WNS (ns) | hold (ns) | 违例/端点 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| b6 | routed | 102 | 85 | 187 | 18,743 (26.15%) | 25,135 (17.53%) | 22,608 (31.54%) | 0 | 4 | +0.119 | +0.020 | 0/19,779 |
| b10 r1 | routed | 102 | 85 | 187 | 19,695 (27.48%) | 28,004 (19.53%) | 24,368 (34.00%) | 0 | 4 | +0.103 | +0.020 | 0/24,665 |
| b11 r0 | routed | 102 | 85 | 187 | 19,882 (27.74%) | 28,686 (20.01%) | 24,844 (34.66%) | 0 | 4 | +0.015 | +0.020 | 0/25,627 |
| b6 | **synth** | 72 | 报告无此行 | 72 | 8,528 | 16,030 | 16,767 | 0 | 4 | 未采用 | 未采用 | — |
| b10 r1 | **synth** | 72 | 报告无此行 | 72 | 9,576 | 18,856 | 18,264 | 0 | 4 | 未采用 | 未采用 | — |
| b11 r0 | **synth** | 72 | 报告无此行 | 72 | 10,231 | 19,523 | 18,660 | 0 | 4 | 未采用 | 未采用 | — |

- **P1 采用 b10 r1 作单链基线**（同一 top、完整整机功能、Routed 0 违例）；b6 作 A+ core 核级权威证据（core SHA 冻结）；b11 只作并行交叉核对（其全局 WNS +0.015 < +0.05 门槛，**不是本 run 基线**）。
- **b11 域拆分**：b11 表中 `WNS_ns=+0.015` 是**全局 WNS**，来自 `ddr_user` 200 MHz 域；b11 的 `clk_a1` 187.5 MHz 域 WNS 为 **+0.059 ns**（`clk0` 行）。引用 +0.015 时必须注明是全局/跨域值，不能当成 A+ 187.5 MHz 域结果。
- **routed/synth 分离**：synth 行 `stage=synth`，不参与任何拟合、不与 routed 相加。synth ERAM 72 与 routed 102 的差异已定量解释：routed 在布线阶段自动插入 2 个 CWC 调试 RAM（`auto_created_cwc1`/`cwc2` 各 15 ERAM，层次行 `U_cwc_ram`），`72 + 2×15 = 102`；三个源完全一致。synth 报告没有 `#DRAMHARDCON` 行，表中留空而不是猜 0/85。
- 187 = 102 + 85 的口径证据：area 报告 `#eram 102 out of 300`、`#eram20k 102`，QoR `#RAMs 102` 与 `#DRAMHARDCON 85` 分列，构建控制台同时打印两行；b10 `result-r1.md` §4.1 明确写“ERAM 102 / DRAMHARDCON 85（合计 187 ≤ 300）”。故 85 未被计入 102，合计 187/300。**不存在 DRAMHARDCON 归属矛盾**。

### 3.1 层次归属（Routed，TD 原始列名）

| source | instance | module | logic lut | ripple | seq | eram | dram lut | pll |
|---|---|---|---:|---:|---:|---:|---:|---:|
| b10 | top | p2_a1_board_top | 15,109 | 3,618 | 28,004 | 102 | 680 | 4 |
| b10 | u_a1 | camera_a1_uart_top | 3,904 | 2,601 | 7,659 | 29 | 144 | 0 |
| b10 | u_a1/a1_frame_top | a1_frame_top | 1,829 | 967 | 1,724 | 27 | 32 | 0 |
| b10 | u_core | a1_deflate_core | **1,453** | **783** | **1,167** | **23** | **32** | 0 |
| b10 | u_bridge | p2_ddr_bridge | 227 | 0 | 399 | **15** | 0 | 0 |
| b10 | u_usr_mcu_wrapper/u_mcu_core | usr_mcu_core | 976 | 179 | 635 | **28** | 32 | 0 |
| b10 | u_camera | f9p_camera_display_core | 1,484 | 505 | 2,232 | 0 | 0 | 1 |
| b10 | u_ddrmc_test_top | p2_ddrmc_shell | 5,981 | 136 | 7,974 | 0 | 496 | 2 |
| b10 | auto_created_cwc1 / cwc2 | auto_created_cwc* | 784 / 805 | 53 / 57 | 2,021 / 2,163 | **15 / 15** | 0 | 0 |

- 层次闭合：三源的 ERAM/DRAM_LUT/PLL/DSP 深度 1 之和与顶层**精确相等**（如 b6：29+15+28+15+15=102）；logic/ripple/seq 有顶层直接粘合残留（b6 91/43/60，b10 95/43/91，均 <2%），按“报告自身顶层未实例化逻辑”处理，不猜数。
- `u_core` 三源均为 23 ERAM / 32 DRAM LUT（logic 1,358–1,453，ripple 772–783，seq 1,167–1,177）。层次列是**归属**，不是“第二核精确增量”，表中保留原列名。
- CWC 30 ERAM 是调试插桩，不是生产功能；但 P1 的拟合口径坚持“只用 routed”，因此 102 照用，并在 conservative 上界里说明它被复制了两次。

## 4. 双核资源表（两栏，器件 300/129,024/143,360/220/12）

基座：b10 r1 Routed = 102 ERAM 逻辑 + 85 DRAMHARDCON；LUT6 19,695；REG 28,004；SLICE 24,368；DSP 0；PLL 4。

| 项 | marginal | conservative | 器件/额度 | marginal 余量 | conservative 余量 |
|---|---:|---:|---:|---:|---:|
| ERAM 逻辑 | **146** | **204** | 300（总）/ 210（逻辑额度） | 总 154；额度 64 | 总 96；额度 6 |
| DRAMHARDCON（只算一次） | 85 | 85 | — | — | — |
| **ERAM 合计** | **231** | **289** | 300 | **69（23.0%）** | **11（3.67%）** |
| LUT6（TD，分母 71,680） | 25,709（35.87%） | 39,390（54.95%） | 71,680 | 45,971 | 32,290 |
| LUT6 logic-only 下界（仅 logic，不含 ripple/DRAM_LUT；**不作拟合值**） | 23,488 | 39,390 | 71,680 | 48,192 | 32,290 |
| LUT4 上界（2×LUT6，分母 129,024） | 51,418（39.85%） | 78,780（61.06%） | 129,024 | 77,606 | 50,244 |
| REG / DFF | 34,341 | 56,008 | 143,360 | 109,019 | 87,352 |
| SLICE | 30,733（assumed 比例外推） | 48,736 | 71,680 | 40,947 | 22,944 |
| DSP | 0 | 0 | 220 | 220 | 220 |
| PLL | 4（共享 187.5 MHz 域） | 8 | 12 | 8 | 4 |
| `fit_300` | **pass**（≤270） | **conditional**（271–300） | — | — | — |
| `fit_210_logic` | **pass**（146≤210） | **pass**（204≤210，仅 6 余量） | — | — | — |
| `timing_status` | **unproven** | **unproven** | — | — | — |

### 4.1 两栏怎么算出来的

**marginal**（期望值）= b10 单链 + 第二链最小增量：

| 增量 | ERAM | logic lut | ripple | seq | dram lut | 标签 |
|---|---:|---:|---:|---:|---:|---|
| 第二 A+ core（`u_core`） | 23 | 1,453 | 783 | 1,167 | 32 | measured（层次归属） |
| 第二 bridge（`u_bridge`） | 15 | 227 | 0 | 399 | 0 | measured（层次归属） |
| 第二路 stream fabric：frame 级 4 + `u_cam_fifo` 2 + arb/crop/raw_store/cmp_store/export | 6 | 2,113 | 1,294 | 4,771 | 144 | 4 ERAM 为派生（27−23），其余 measured 层次；无 ERAM 的 FIFO 若未来映射 ERAM 需另加 |
| **合计增量** | **44** | **3,793** | **2,077** | **6,337** | **144** | derived |
| **marginal 合计** | **146** | 25,709* | — | **34,341** | 824 | derived |

\* `LUT6_total` 用 TD 恒等式 `#lut6 = with-luts(logic) + with-adder(ripple) + dram lut + shifter lut`：`19,695 + 3,793 + 2,077 + 144 = 25,709`。b6/b10/b11 三源顶层均精确满足该恒等式（18,743/19,695/19,882），因此 ripple 与 DRAM_LUT 必须计入 LUT6 当量；只算 logic 的 23,488 仅作下界，不是拟合值。`SLICE` 用工作量比例外推（assumed）：`24,368 × (1 + 12,207/46,731) = 30,733`。PLL 4 假设第二核共享现有 `clk_a1` 187.5 MHz 域；若需独立 PLL，PLL=5（仍 ≤12）。

**conservative**（上界）= 完整第二链复制：`2×102 = 204` ERAM 逻辑、`2×LUT6 = 39,390`、`2×REG = 56,008`、`2×SLICE = 48,736`、`2×PLL = 8`；**85 DRAMHARDCON 只算一次**（共享单 DDR MC/PHY）。该上界同时复制了 2×15 CWC 调试 RAM，因此不是生产估算，只是“保证装得下”的上界。

**双 DDR 变体**（若第二路必须独立 DDR 端口/控制器）：`marginal 146+170=316`、`conservative 204+170=374`，均 >300，`fail`。默认架构仍是共享 256-bit PAXI + 单 DDR MC，故主表不采用。

### 4.2 共享 / 复制清单

| 模块 | 处理 | 依据 | 标签 |
|---|---|---|---|
| `u_ddrmc_test_top`（DDR MC + PHY + 85 DRAMHARDCON） | **共享，不复制** | 单链整机已含；第二核共享 256-bit PAXI | assumed（设计指南 §1/§3.2） |
| `u_camera`（HDMI + PLL + **仅 u_csi_a**） | **部分共享**：A 路 CSI 共享；**第二路 CSI RX 未实现/未计入** | routed 层次只有 `u_csi_a`（`mipi_csi2_rx_ph1p`），**没有 `u_csi_b` 行**；`u_csi_b` 在 `f9p_camera_display_core.v` 中例化但数据输出未形成使用路径，无 routed 资源。若第二路需要完整 CSI，marginal 需加 773 logic/340 ripple/1,474 seq/0 ERAM → LUT6 26,822、REG 35,815（仍可装入） | measured（routed）+ assumed（第二路需求） |
| `u_usr_mcu_wrapper` / `u_mcu_core`（28 ERAM） | **共享，不复制** | 单 MCU 管两路 | assumed |
| `debug_hub_top` | 共享 | 0 ERAM | measured |
| CWC（2×15 ERAM） | 调试插桩；conservative 被动复制 | routed 自动插入；生产可移除但本包不重跑 | measured（存在）/ assumed（可移除） |
| `u_core`（23 ERAM） | **复制**（第二核） | `u_core` 层次行 | measured |
| `u_bridge`（15 ERAM） | **复制**（第二路） | `u_bridge` 层次行 | measured |
| 第二路 A1 PLL | **假设共享**；若独立 +1 PLL | `u_a1_pll` 层次 | assumed |
| 第二路 frame glue/cam FIFO/arb/crop/stores/export | **复制**，ERAM 6、logic 2,113、ripple 1,294、seq 4,771 | 层次行；frame 级 4 ERAM 为 27−23 的差 | measured + derived |
| 第二路 FIFO 若额外映射 ERAM | **未计入**；需 P3/实现确认 | 层次显示 0 ERAM，但 TD 可能在实现阶段映射 | assumed / unproven |

### 4.3 第二路 CSI 的真实状态（F3）

- routed 证据：b6/b10/b11 三份 `routed_area.rpt` 的 `u_camera` 下都只有 **一个** `u_csi_a`（`mipi_csi2_rx_ph1p`），**没有 `u_csi_b` 层次行**；`u_camera` 行 1,484 logic/505 ripple/2,232 seq/0 ERAM/1 PLL 的闭合对应“单 CSI + HDMI + cfg_a/b + 其它”。
- 源码事实：`f9p_camera_display_core.v` 例化了 `u_csi_b`，但其数据输出未形成实际使用路径，因此 routed 不包含它的资源。**源码例化 ≠ routed 资源**，资源清单以 routed 为准。
- 对 marginal 的影响：第二路 CSI 的 ERAM 为 0，故 **ERAM 146/231 不变**；但逻辑/寄存器至少少 773 logic、340 ripple、1,474 seq。本报告把这一项明确标为“**未实现/未计入 marginal**”，不写“已含 2 路、共享”。
- 若第二路必须使用完整 CSI，marginal 修正为：logic 4,566、ripple 2,417、seq 7,811、DRAM_LUT 144 → **LUT6 26,822**（19,695+7,127）、**LUT4 上界 53,644**、**REG 35,815**、SLICE 约 32,083、ERAM/headroom/fit 不变（231/300 pass、146/210 pass）。保守栏 2× 完整链已覆盖第二路 u_camera，不受影响。

## 5. 时序

- 单核 Routed：b6 `+0.119/+0.020 ns`、0/19,779；b10 r1 `+0.103/+0.020 ns`、0/24,665；周期检查 WNS `+2.200 ns`；`clk_a1` 约束 187.500 MHz（报告 Clock Summary）。**均为薄余量**（hold 只有 20 ps）。
- b11 全局 `+0.015/+0.020`、0/25,627，低于 +0.05 门槛，仅作并行交叉核对；其中 `+0.015` 是全局/`ddr_user` 200 MHz 域值，`clk_a1` 187.5 MHz 域为 `+0.059`。
- **双核时序 `unproven`**：没有任何双核 Routed 构建/布局/时钟树/拥塞数据。第二核是核内路径复制，理论上不改变单核关键路径，但共享桥、布局与时钟树可能改变结果；不得把 +0.103/+0.119 外推为双核 WNS。P3 即使做，也只允许“G2-syn 检查点”，不得写成时序签核（b6 synth +0.280 → routed +0.119 已证明 synth 偏乐观）。

## 6. 判定与缺口

- `fit_300`：marginal **pass**（231 ≤270，余量 23.0%）；conservative **conditional**（289 落在 271–300，余量 3.67%，按冻结规则只能“仅边际成立，需 P3/后续综合确认”）。
- `fit_210_logic`：marginal **pass**（146/210，余 64）；conservative **pass 但很紧**（204/210，余 6，仅 2.86%）。超过 210 但总 ERAM ≤300 时必须写“超出项目初步额度”，本表未超。
- LUT/REG/SLICE/DSP/PLL 在 marginal 与 conservative 均未超器件；**LUT4 只有上界**：TD 不报告 LUT4 数量，表中用 `2×LUT6` 作保守上界（marginal 51,418/129,024=39.85%，conservative 78,780/129,024=61.06%），真实 LUT4 利用率必须由后续实现测量，不得把 19,695 与 129,024 混算。
- 结论：**双核在“边际 + 共享 DDR/MCU”口径下资源可装入且有约 23% ERAM 余量；在“完整第二链复制”上界下只剩 3.67%，只能判 conditional。** 是否真正可落地取决于：第二路 FIFO 的实际 ERAM 映射、CWC 是否保留、第二路 CSI 是否补实现（+773/340/1,474，仍可装入）、布局/拥塞/时序（均 unproven）。

## 7. 标签纪律

| 标签 | 本报告中的对象 |
|---|---|
| measured | 三源 `routed_area.rpt`/`routed_qor.rpt`/`routed_timing.rpt` 的顶层与层次列；core/manifest SHA；187.5 MHz；0/19,779、0/24,665、0/25,627；CWC 2×15 |
| derived | `ERAM_total=102+85=187`；marginal 增量 44/146/231；conservative 204/289；headroom 与百分比；slice 比例外推；LUT4 上界；`fit_300`/`fit_210` 判定 |
| assumed | 第二核共享 `clk_a1`（PLL 4）；第二路 stream fabric 的 4 ERAM frame 级归属；共享 MCU/DDR PHY；第二路 FIFO 无额外 ERAM；slice 工作量比例；**第二路完整 CSI（u_csi_b）未实现/未计入 marginal，需时 +773 logic/340 ripple/1,474 seq** |
| unproven | 双核 Routed 时序/拥塞/时钟树；生产（去 CWC）后的真实 ERAM；精确 LUT4 数量；第二链在器件上的实际可布性 |

## 8. 边界（本包未做/不做）

- 不做双路 1080p30 服务率/DDR 带宽/丢帧判定（P2）；不引用 b6 81.067 MB/s 作双路结论。
- 不做 TD 综合/布线/bitgen/CWC/下载/板卡/RK；不改生产 RTL/约束/IP、b11/T08/T10 目录、`workflow/tasks.json`。
- 不声称 G2/G3/G4；本包只有 G0（输入 SHA/字节）与 G1（表格可复算、层次闭合、负对照）。
- 不删除任何文件；所有新文件只写本任务 `r0/`。

## 9. 复现

```powershell
cd D:/fpga/ph1p100/workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility/T10.dual-core-resource-baseline/r0
python gen_baseline.py        # 重新冻结 SHA 并生成 CSV/负对照；mismatch_count 必须为 0
python check_tables.py        # 独立复算 + 3 负对照；必须 5/5 PASS 且 exit 0
```

日志：`logs/gen_baseline.out.txt`、`logs/check_tables.out.txt`；命令/exit 见 `commands.jsonl`。
