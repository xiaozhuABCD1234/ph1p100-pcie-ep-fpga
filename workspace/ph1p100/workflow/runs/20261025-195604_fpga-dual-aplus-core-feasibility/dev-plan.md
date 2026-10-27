# 开发与验收计划：双路 A+ 双核/服务率可行性（离线）

- run：`20261025-195604_fpga-dual-aplus-core-feasibility`
- 项目根：`D:/fpga/ph1p100`
- 输出目录：`D:/fpga/ph1p100/workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility`
- 用户原话：“现在这个run使用工作流开始开双路 A+ 双核/服务率可行性。”
- 本轮主要目标（1 个）：给出 PH1P100 上双路 1920×1080@30 RAW10 A+ 压缩的单核/双核资源、时序、DDR 带宽、调度服务率判定；若不可行，给出单核降帧/降分辨率的量化结论。
- 拆分：3 个正式包（2 completed + 1 blocked 条件包），两级（需求 → 工作包），每包 5 项语义步骤；默认 `BATCH_SIZE=1`；本 run 不修改 `workflow/tasks.json`。
- 并行：与 OpenCode b11、Codex T08/T10 并行但只读；不抢 tester、不改其目录/候选/报告；TD 冲突时 b11 优先。
- 当前状态（2026-10-25）：P1、P2 均 round0 FAIL→round1 PASS（各 1 轮实际修复）；本轮离线主要目标已完成。P3 仍 blocked（TD 空闲/b11 优先/规划放行未确认；用户未新增 TD/板卡授权）。

## 1. 计划总表

| task_id | 问题/产物 | 实际工作树/允许写路径 | 依赖 | functional | engineering | system | 必要 G 层 | 状态 | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|
| `T10.dual-core-resource-baseline` | 冻结 b6 单核 SHA；从 b6/b10/b11 Routed 报告建立单核资源/时序权威基线 + 双核 marginal/conservative 资源表 | `D:/fpga/ph1p100`；仅本 run `T10.dual-core-resource-baseline/**` | 无；只读 b6/b10/b11 | 报告数字逐项复算；层次和=顶层；双核两栏算术 | routed/synth 分离；SHA/命令/CSV 可复现；无 TD | 器件/时钟/共享/复制清单；双核时序 unproven | G0/G1；G2–G4 N/A | **done（round1 PASS；1 轮实际修复）** | 已冻结 manifest `228531e7…bdd0`；作为 P2 资源输入 |
| `T10.dual-aplus-service-verdict` | 可执行预算模型 + 43 行场景判定 + DDR 2R+2S + Pareto 前沿 + 主推荐/备选 | 同上；仅 `T10.dual-aplus-service-verdict/**` | P1 PASS + 冻结 manifest `228531e7…bdd0` | 3 锚点复现；全网格分类；前沿极大；负对照 | 纯函数/规则文件/测试；CSV↔报告一致；无 TD | per-stream 非 aggregate；full-chain 非 core-only；T08/T10 合同一致 | G0/G1；G2–G4 N/A | **done（round1 PASS；1 轮实际修复）** | 已冻结 manifest `5ed90500…36a6`；结论已交收尾 |
| `T10.dual-core-synth-probe` | 双核隔离综合（仅 synth）确认资源/综合检查点；不布线/bitgen/CWC/下载 | 同上；仅 `T10.dual-core-synth-probe/**` | P1/P2 PASS + TD 空闲 + b11 不重建 + 规划放行 | 两核例化；综合完成/0 error；面积/时序采集 | 1 session/1 synth；源副本 SHA；不 place/route | G2-syn only；不是时序签核/生产候选 | G0/G1 + G2-syn；G3/G4 not_run | blocked（P2 已 PASS；TD/b11/go 未确认） | 不派发；条件满足后再由原规划另行派发 |

**包数说明**：P1、P2 已 PASS（各 round1），P3 是 blocked 条件包，均计入 3 个正式包；未使用第 4 个名额。本轮不派 P3；P3 必须等 TD 空闲、b11 不重建、原规划明确放行且用户不扩权的前提下另行派发。

## 2. P1：`T10.dual-core-resource-baseline`

### 2.1 目标与可观察结果

唯一可观察结果：一份**可复算、可追溯、区分 routed/synth、区分共享/复制**的单核资源/时序基线，以及双核资源的 `marginal` 与 `conservative` 两栏表；明确回答“双核在 300 ERAM/129,024 LUT4/143,360 DFF/220 DSP/12 PLL 上是否装得下、余量多少、哪些还未证明”。

不回答：双路 30 fps 是否可行（P2）；双核 Routed 时序（P3/后续）；板级/生产资格。

### 2.2 允许写范围与输入

- 只写：`.../T10.dual-core-resource-baseline/**`（r0 子目录）。
- 只读：`input-index.md` §3/§4 所列 b6/b10/b11 报告、manifest、routed_area/timing、b6 设计冻结、器件/预算文档。
- 禁止：TD、综合、布线、bitgen、CWC、下载、板卡、COM、RK、修改 `fpga/csi2/src/**`、`upstream/**`、`D:/TD/work/csi2/**`、`D:/fpga_work/**`、b11/T08/T10 目录、`workflow/tasks.json`。

### 2.3 五项语义步骤

1. **冻结输入**：建立 `input-verified.json`，逐项记录 path/bytes/SHA256；硬断言 b6 core `6797db05…35bb`（80,196 B）与 b6 manifest `2e9fd356…8880`；记录 TD/Python 版本、报告读取时间；0 mismatch 才继续。
2. **提取单核基线**：从 b6/b10/b11 的 `routed_area.rpt`/`routed_timing.rpt`/`routed_qor.rpt` 提取顶层 ERAM/DRAMHARDCON/DRAM_LUT/LUT6/REG/slice/DSP/PLL、WNS/hold/period/viol/total_ep；从层次区提取 `u_core`/`u_bridge`/`u_mcu_core`/`u_camera`/`u_export`/`u_arb`/`u_crop` 行；synth 行单列，不混入拟合。
3. **建立双核资源表**：`dual-core-budget.csv` 两栏：`marginal`（第二核按 `u_core` 层次列：23 ERAM、~1.4k logic LUT + 783 ripple、~1.2k seq、32 DRAM LUT；第二路 bridge 15 ERAM；camera/writer/fabric 估算，FIFO/缓冲若映射 ERAM 另加并标注；共享 MCU/DDR PHY 不复制）与 `conservative`（整机单链基线 + 完整第二链 102 ERAM 等价 + 85 DRAMHARDCON 只算一次）；若实际需要第二 DDR 端口/控制器，另加 85 并单列变体；对 300/210/129,024/143,360/220/12 逐项比较；所有 `assumed` 注明。
4. **写基线报告**：`resource-baseline.md` + `resource-table.csv`；明确单核权威值、双核两栏、`ERAM_total` 是否含 `DRAMHARDCON`、哪些模块共享/复制、单核 Routed 薄余量、双核时序 `unproven`；给出 `fit_300`/`fit_210_logic` 与缺口。
5. **局部检查与冻结**：写 `check_tables.py` + 3 个负对照 fixture（synth 混入、漏 DRAMHARDCON、用 102×2 代替 marginal/conservative）；运行并保存 argv/cwd/exit/日志；写 `result-r0.md`/`lessons.md`；停止修改，冻结 `manifest-r0.json`（`stopped_modifying=true, active_commands=0`）。

### 2.4 交付物

```text
T10.dual-core-resource-baseline/r0/
  input-verified.json
  resource-table.csv
  dual-core-budget.csv
  resource-baseline.md
  check_tables.py
  tests/negative/*.json          # 3 个负对照 fixture + 期望拒绝原因
  commands.jsonl
  result-r0.md
  lessons.md
  manifest-r0.json
```

### 2.5 验收门槛

| 维度 | 适用检查 | 门槛/证据 |
|---|---|---|
| functional | 报告数字复算 | `resource-table.csv` 每行 ERAM/DRAMHARDCON/DRAM_LUT/LUT6/REG/slice/DSP/PLL/WNS/hold/viol/total_ep 与源报告一致；顶层与层次和一致（允许报告自身舍入）；3 个负对照全部被 `check_tables.py` 拒绝 |
| functional | 双核算术 | `marginal`/`conservative` 两栏齐全；`ERAM_total`、headroom、210 额度、LUT/REG/slice/DSP/PLL 逐项可手算复核；LUT6（分母 71,680）与 LUT4（129,024）不混算；不得只给单点 |
| engineering | routed/synth 分离 | 拟合只用 routed；synth 行 `stage=synth`；无 synth+routed 相加；b6 synth 72 与 routed 102 的差异有解释 |
| engineering | 可复现 | 命令/exit/日志/CSV 确定性；所有输入 SHA；无 TD/硬件；写范围外 0 文件 |
| engineering | 唯一 manifest | 覆盖所有产物/输入/工具/命令；`stopped_modifying=true, active_commands=0` |
| system | 器件/时钟/共享 | PH1P100SBG484-3；187.5 MHz；第二路 camera/writer/bridge 的复制/共享清单；b11 只读；无板级/生产声明 |
| system | 时序措辞 | 单核 b6 +0.119（薄余量）；双核 `unproven`；不得由单核外推双核 WNS |
| G 层 | G0/G1 | 输入冻结 + 表格可复算；G2/G3/G4 `not_applicable`（未综合/未实现/未上板），理由见设计指南 §8.2 |

**不适用理由**：P1 是只读报告解析 + 表格，不产生 RTL/bit/板测；G2 需要同一候选的综合/Routed，本包无候选；G3/G4 无 bit/板卡。不得用无关 TD/板测充数。

### 2.6 工具、预算、停止

- 工具：Python 3.11.5；只读 `routed_area.rpt`/`routed_timing.rpt`/`routed_qor.rpt`/manifest；无 TD、无 ModelSim。
- 预算：开发 ≤30 calls / 45 min；测试 ≤30 calls / 45 min；读/搜 60 s；Python 120 s；同失败命令最多首次+1 次有新证据重试；单问题 ≤3 轮。
- 停止/blocked：输入缺失、SHA 漂移、`DRAMHARDCON` 归属无法从报告/构建日志判定、层次和无法闭合、需要 TD 才能回答 → `blocked`；problem 用 `INPUT_CONFLICT`/`SCOPE_CLARIFICATION`/`TOOL_UNAVAILABLE`，不猜数。
- 回退：只写本任务目录；回退=停止采用该目录，不删除、不改生产；保留失败证据。

### 2.7 P1 实际结果（2026-10-25，round1 PASS）

- 判定：`T10.dual-core-resource-baseline` round0 FAIL（F1 marginal LUT6/LUT4 少计；F2 manifest 与 freeze 日志不绑定；F3 `u_camera`/第二路 CSI 清单不符）→ round1 修复后 **PASS**；实际修复 1 轮；blocked 空；retest not_required。
- 冻结 manifest：`.../T10.dual-core-resource-baseline/r0/manifest-r0.json`，SHA256 `228531e7c16bca1a14898966c150b31bce464d7413f58078ae0bd724e894bdd0`；15 artifacts / 27 inputs / 10 commands；`stopped_modifying=true, active_commands=0`；TD/综合/布线/bitgen/CWC/下载/板卡/ModelSim 全 0。
- 独立报告：`.../test-reports/T10.dual-core-resource-baseline-r1-integrated.md`；functional/engineering/system pass，G0/G1 pass，G2–G4 `not_applicable`。
- 关键值（Routed）：单链 102 ERAM 逻辑 + 85 `DRAMHARDCON` = 187/300；双核 `marginal` 146+85=**231/300**（余 69，23.0%，`fit_300` pass、210 逻辑额度 pass）；`conservative` 204+85=**289/300**（余 11，3.67%，`fit_300` **conditional**、210 额度 pass）。
- 资源细节：`marginal` LUT6 **25,709/71,680**（TD 恒等式；logic-only 下界 23,488 单列不作拟合）、LUT4 上界 51,418/129,024、REG 34,341/143,360、SLICE 30,733（assumed 比例）、DSP 0、PLL 4；`conservative` LUT6 39,390、LUT4 上界 78,780、REG 56,008、SLICE 48,736、PLL 8。双 DDR 控制器变体 316/374 → fail。
- 时序：b6/b10 `clk_a1` 187.5 MHz 域 WNS +0.119/+0.103、hold +0.020、0 违例；b11 全局 +0.015 是 `ddr_user` 200 MHz 域，`clk_a1` 域 +0.059（仅交叉核对）。**双核 Routed 时序 unproven**，不得外推。
- 系统边界：routed 的 `u_camera` 只有 `u_csi_a`，`u_csi_b` 未形成使用路径；第二路完整 CSI 未计入 marginal，若需要加 773 logic/340 ripple/1,474 seq/0 ERAM → LUT6 26,822、REG 35,815、SLICE 约 32,083，ERAM/fit 不变。第二路 FIFO 的 ERAM 映射未证明；生产去 CWC 后的真实 ERAM 未重跑；精确 LUT4 只有上界。
- 结论：P1 只解除 P2 前置条件；**资源层面为 conditional**（marginal 可装、conservative 仅边际、时序未证），双路 1080p30 服务率/DDR/丢帧仍待 P2。

## 3. P2：`T10.dual-aplus-service-verdict`

### 3.1 目标与可观察结果

唯一可观察结果：一份**可执行、可复现、带负对照**的服务率/DDR/资源综合判定，明确回答：

- 单核/双核在 1080p30 双路下的 per-stream 服务率与裕量；
- core-only 与 full-chain 的差距；
- DDR 2R+2S 的所需效率与瓶颈；
- 43 行场景中哪些 feasible/conditional/infeasible；
- 若不可行，单核降帧/降分辨率/双核降帧的量化前沿；
- 一个主推荐 + 最多两个备选，以及“什么会改变结论”的可测阈值。

### 3.2 依赖与允许写范围

- 依赖：P1 round1 PASS 且 manifest 冻结（SHA256 `228531e7c16bca1a14898966c150b31bce464d7413f58078ae0bd724e894bdd0`）。
- P1 资源输入（只读）：`T10.dual-core-resource-baseline/r0/{manifest-r0.json,resource-table.csv,dual-core-budget.csv,resource-baseline.md,result-r0.md}` 与 `test-reports/T10.dual-core-resource-baseline-r1-integrated.md`。
- P1 已冻结资源结论：单链 187/300；双核 marginal **231/300**（余 69，23.0%）；conservative **289/300**（余 11，3.67%，**conditional**）；LUT6 25,709、LUT4 上界 51,418、REG 34,341、SLICE 30,733（assumed）；双核时序 unproven；双 DDR 316/374 fail；第二路完整 CSI 未计入，若需要 +LUT6 到 26,822/REG 35,815/SLICE 约 32,083（ERAM 不变）。
- 只写：`.../T10.dual-aplus-service-verdict/**`。
- 只读：P1 产物、`input-index.md`/`fpga-design-guide.md`、b6/b10/b11 报告、T08/T10 合同。
- 禁止：TD、RTL、板卡、RK、修改 P1 产物/其他 run/tasks.json。

### 3.3 五项语义步骤

1. **冻结输入与常量**：`input-verified.json` + `inputs/frozen-inputs.json`；断言 P1 manifest SHA `228531e7…bdd0`、b6 core SHA、comp/rand/full_grad 数值、187.5 MHz、2,592,000/4,147,200/2,594,750/8 MiB/44 B、25% 门槛；每个常量带 `measured/derived/assumed` 标签。
2. **实现模型与规则**：`model/calc.py` 纯函数（帧/组/槽/速率/裕量/时钟/分辨率当量/DDR 2R+2S/资源比较）；`model/rules.json` 冻结 §6 判定与档位；`model/test_calc.py` 覆盖已知值、边界（0/1 帧、单/双路、最小档）、负对照。
3. **生成全网格**：按设计指南 §6.2 生成 43 行 `scenarios.csv`（39 设计行 + 4 个单核单路 1080p fps 档；cores 1/2、streams 1/2、7 个 16:9 档@30、1080p fps 梯、1080p30 双核时钟梯），每行两列 `C_core_comp`/`C_chain` 与 `drop_rate_lb_pct`；另生成 `content-sensitivity.csv`（comp/rand/full_grad）、`ddr-budget.csv`（含/不含 CMP DDR 变体）、`frontier.csv`、`overhead-sensitivity.csv`（三档 129 行）。
4. **判定与写作**：按 `rules.json` 机械分类，生成 `feasibility-report.md`：结论摘要、单核/双核服务率、per-stream vs aggregate、core-only vs chain、DDR、资源、43 行判定表、Pareto 前沿、1 主推荐 + ≤2 备选、什么会改变结论、风险/未测/G 层、复现命令；不得手工覆盖任何行。
5. **检查与冻结**：运行 `test_calc.py` + 3 个负对照（RAW12/1.0×、aggregate 2C≥155.52、synth/routed 混用），核对 CSV↔报告每个数字与 `overhead-sensitivity.csv` 三档回归；写 `result-r0.md`/`lessons.md`；停止修改，冻结 `manifest-r0.json`。

### 3.4 交付物

```text
T10.dual-aplus-service-verdict/r0/
  input-verified.json
  inputs/frozen-inputs.json
  model/calc.py
  model/rules.json
  model/test_calc.py
  out/scenarios.csv
  out/content-sensitivity.csv
  out/ddr-budget.csv
  out/frontier.csv
  out/overhead-sensitivity.csv
  feasibility-report.md
  result-r0.md
  lessons.md
  manifest-r0.json
```

### 3.5 验收门槛

| 维度 | 适用检查 | 门槛/证据 |
|---|---|---|
| functional | 锚点复现 | comp 355,261 cycles/81.067159 MB/s、rand 161,479/178.351、full_grad 6,421,414/29.199 fps 与输入一致（cycles 精确；速率 ≤0.1% 舍入）；模型从常量计算，不硬编码答案 |
| functional | 网格完整 | 43 行（39 设计行 + 4 个单核单路 1080p fps 档），覆盖设计指南 §6.2 全部组合；每行有 cores/streams/W/H/fps/clock/两列容量/两列裕量/drop_rate_lb/verdict/gate_status；无“只给代表行” |
| functional | 判定一致 | `rules.json` 机械应用；`feasible` 必须同时满足 per-stream 25%、conservative ERAM ≤270、timing proven；双核无 Routed 时最高 `conditional`；`fails_30` 不得写 `feasible` |
| functional | 资源输入 | 使用 P1 manifest `228531e7…bdd0`；marginal 231/300、conservative 289/300（conditional）；第二路完整 CSI 敏感性（LUT6 26,822/REG 35,815/SLICE ~32,083，ERAM 不变）单列；不得把 dual-core 写 `feasible` |
| functional | 前沿/推荐 | `frontier.csv` 的 1080p fps 与 30 fps 分辨率前沿是网格内极大；主推荐唯一、确定、可复算；备选 ≤2；不推荐未证明的双核为无条件主推荐 |
| functional | DDR | 2R+2S 公式、1.6×、CMP worst、44 B 头、8 MiB 槽；`required_eff_pct` 与 6.4 GB/s 理论峰值；排除项单列；含/不含 CMP DDR 变体 |
| functional | 调度/丢帧 | 2 槽/帧级公平/丢整帧假设写明；`drop_rate_lb_pct = max(0, 1−C_service/D_s)` 与 `C_service` 口径一致；不得把平均带宽够当无丢帧 |
| functional | overhead 敏感性 | `out/overhead-sensitivity.csv` 129 行（43×3）；1080p 固定实测锚点 `applies=false`；非 1080p 逐档重算 verdict；1600×900 主档 36.1774%、保守档 21.0486% 必须披露 |
| engineering | 模型质量 | 纯函数、无随机、无网络；单元测试覆盖已知值/边界；3 个负对照全部被拒绝；CSV 与报告逐项一致；命令/exit/日志齐全 |
| engineering | 写范围/manifest | 只写本任务目录；manifest 覆盖输入/代码/规则/输出/测试/报告；`stopped_modifying=true, active_commands=0` |
| system | 合同一致 | 20 B/32 B、8 MiB CMP、44 B A1U1、共享 256-bit PAXI、187.5 MHz；双路 per-stream，不是 aggregate；full-chain 优先，core-only 只作乐观上界；不使用 RAW12/622/777 |
| system | 声明边界 | 无 RK/PCIe/板级/实测吞吐声明；内容依赖/双核时序/链级 overhead 均标 `unproven/assumed`；离线 PASS 不等于生产/G2/板级 |
| G 层 | G0/G1 | 输入冻结 + 模型/CSV/报告可复现；G2/G3/G4 `not_applicable`（无 RTL/bit/板） |

**不适用理由**：P2 是模型/表格/报告，无 RTL/时序/板测；G2 需要同一候选综合/Routed，本包没有；G3/G4 无 bit/板卡。不得把模型 PASS 写成双路系统完成。

### 3.6 关键判定阈值（由冻结常量推导，供核对；最终以模型/报告为准）

| 项 | 值 | 说明 |
|---|---:|---|
| 1080p30 per-stream 需求 | 77.760 MB/s | `2,592,000×30/1e6` |
| 双路总需求 | 155.520 MB/s | 仅用于 DDR/总量；不用于 per-stream |
| 25% 门槛 per-stream | 97.200 MB/s | `77.76×1.25` |
| 单核 comp 核级容量 | 81.067 MB/s | b6；per-stream 1080p30 裕量 +4.25% |
| 单核 comp 25% 最大 1080p fps | 25.02 fps | `81.067/(2.592×1.25)` |
| 单核 comp 0% 最大 1080p fps | 31.276 fps | `81.067/2.592` |
| full_grad 链级容量 | ≈75.69 MB/s | `2,592,000×187.5e6/6,421,414/1e6` |
| full_grad 链级 1080p30 裕量 | ≈−2.67% | 链级已低于 30 fps |
| full_grad 链级 25% 最大 1080p fps | ≈23.36 fps | `75.69/(2.592×1.25)` |
| 30 fps 25% 核级最大 16:9 档 | 1728×972（核级） | 1,679,616 px；裕量约 28.7% |
| 30 fps 25% 链级最大 16:9 档 | 1600×900（链级） | 1,440,000 px；1728×972 链级约 20.1%，低于 25% |
| 1080p30 25% 所需 cycles/frame | 5,000,000 | `187.5e6/(30×1.25)` |
| 1080p30 0% 所需 cycles/frame | 6,250,000 | `187.5e6/30` |
| 1080p30 25% 所需时钟（按链级 6.421M） | ≈240.8 MHz | `187.5×6,421,414/5,000,000` |
| 1080p30 0% 所需时钟（按链级 6.421M） | ≈192.6 MHz | `187.5×6,421,414/6,250,000` |
| 双核 1080p 25% 最大 per-stream fps（核级） | 25.02 fps | 双核每核一路，per-stream 仍单核容量 |
| 单核双路 25% 最大 1080p per-stream fps | 12.51 fps | `C/2/(2.592×1.25)` |

> 这些是**核对值**，不是最终报告结论；开发必须用自己的模型复算，测试者必须独立手算至少 5 项。若模型结果与这些值冲突，先查公式/单位，不得改门槛迎合。

### 3.7 工具、预算、停止

- 工具：Python 3.11.5；无 TD/ModelSim/板卡。
- 预算：开发 ≤45 calls / 75 min；测试 ≤40 calls / 60 min；读/搜 60 s；Python 120 s；同失败命令最多首次+1 次有新证据重试；单问题 ≤3 轮；最多 3 轮实际修复。
- 停止/blocked：无法复现锚点、链级边界无法建立且会改变结论、P1 manifest 漂移、需要 TD/板测才能回答 → `blocked` 或 `unproven`；不得用 core-only 单选有利值。
- 回退：只写本任务目录；失败证据保留；不改 P1/生产；不删除。

### 3.8 P2 实际结果（2026-10-25，round1 PASS）

- 判定：`T10.dual-aplus-service-verdict` round0 FAIL（F1 frontier margin 与 basis 不同源；F2 三档 overhead 未落产物、1600×900 保守档仍写成无条件 feasible；F3 推荐缺所需时钟）→ round1 修复后 **PASS**；实际修复 1 轮；blocked=false；retest not_required。
- 冻结 manifest：`.../T10.dual-aplus-service-verdict/r0/manifest-r0.json`，SHA256 `5ed90500a7e9650ca17e5f269731984fea9f215d7401d555dc5633551c2436a6`（28,684 B）；23 artifacts / 22 inputs / 18 commands；`stopped_modifying=true, active_commands=0`；TD/综合/布线/bitgen/CWC/下载/板卡/ModelSim/RK 全 0。
- 独立报告：`.../test-reports/T10.dual-aplus-service-verdict-r1-integrated.md`；functional/engineering/system pass；G0/G1 pass；G2–G4 `not_applicable`。
- 主要结论：
  - **双路 1920×1080@30 = infeasible**。per-stream 链级 75.684265 MB/s（29.199 fps，−2.6694%），核级 81.067159 MB/s（31.276 fps，+4.2530%）；25% 门槛 97.20 MB/s。双核每核一路时 per-stream 仍是单核容量，不会把 75.684 提到 77.76。
  - 聚合陷阱：2×C_core=162.134 >155.52，但 2×C_chain=151.369 <155.52，per-stream 仍 75.684 <77.76；不得用 aggregate 判双路。
  - 1080p30 所需时钟：链级 240.803 MHz（25%）、192.642 MHz（0%）；200 MHz 只有 +3.8193%，仍 below_25 且 200 MHz 时序 unproven。
  - 1080p 链级 25% 最大 fps 23.36；0% 最大 29.199；单核双路 per-stream 25% 最大 11.68 fps。
  - 30 fps 链级 25% 最大档：主档 1600×900（36.1774%）；三档稳健 1440×810（最差 42.9485%）；1728×972 主档 18.3184%、保守档 6.7286%。
  - DDR 主路径 2R+2S 809.034 MB/s，required efficiency 12.6412%；25% gate 1,011.2925 MB/s（15.8014%）。持续带宽/PAXI 仲裁/单拍效率仍 unproven。
  - 场景计数：43 行（39 设计 + 4 单核单路 1080p fps 档）；feasible 8 / conditional 22 / infeasible 13；**双核 feasible 0；1080p30 feasible 0**。
- 推荐（模型规则选出）：
  - 主推荐（带条件）：**1600×900@30 c1s1**，主档 426,385 overhead 36.1774% feasible；保守档 1,000,000 为 21.0486% → conditional；所需链/核时钟 172.1100/156.1206 MHz；ERAM 187/300。
  - 备选 1（三档稳健）：**1440×810@30 c1s1**，最差 42.9485% feasible；链/核时钟 142.4471/126.4577 MHz。
  - 备选 2（全分辨率降帧）：**1920×1080@20 c1s1**，45.9959% feasible；链/核时钟 160.5353/149.8757 MHz。
  - 双路部署注意：2× c1s1 = 2c2s，服务率同 per-stream，但双核 conservative 289/300 + 双核 Routed 时序 unproven → **2c2s 最高 conditional**；网格内最大 feasible 的双路 30 fps 行是 **单核 2×960×540@30（最差档 25.0622%）**，分辨率牺牲大。双核不是 1080p30 的解。
- O1–O6 非阻断观察：O1 c1s2 的 required-clock 列是容量口径（推荐均为 c1s1，不影响 verdict）；O2 `commands.jsonl` 17 条 vs manifest 18 条（`mk_manifest` 不入日志，有意设计）；O3 开发实际约 100 calls，超过冻结 45 calls（范围未扩、门槛未改、无 TD/硬件/越界写，作过程记录）；O4 日志 UTF-16LE；O5 frontier core-only 行使用 `core_only_upper_bound` 标签；O6 round1 check 首轮失败已记录并修正。均由 P2 r1 报告 §7 记录。
- 未测/不声称：自然图像/低照/噪声、DDR 持续带宽/PAXI 仲裁、双核 Routed 时序、200 MHz、第二路完整 CSI、第二路 FIFO ERAM、周期级调度、板级/RK/曝光同步。P2 PASS 不等于双路系统完成。

## 4. P3：`T10.dual-core-synth-probe`（blocked，条件包）

### 4.1 目标

在 TD 空闲且 b11 不重建时，对“双核 + 最小共享桥”的隔离 top 做**一次综合**，确认 P1 的 `marginal` 资源栏是否成立，并给出 synth 检查点；**不布线、不 bitgen、不 CWC、不下载**。

### 4.2 解阻条件（缺一不可）

1. P1、P2 均 PASS，且 P1 的资源结论为 `conditional`（`conservative` 在 271–300、或 >300 但 `marginal` ≤300、或 marginal/conservative 差距会改变结论）；否则 P3 无必要。**当前：P1 PASS（资源 conditional 289/300）、P2 PASS（r1）→ 本条已满足。**
2. b11 当前没有构建/布线/下载活动；TD 空闲窗口 ≥30 min。**当前未确认，规划不探测、不抢占。**
3. 原规划在 dispatch 中明确放行；本包不自行占 TD。**当前未放行；用户未新增 TD/板卡授权，主不扩权。**
4. 只写本 run 的 `T10.dual-core-synth-probe/**`；源只用本 run 冻结副本，不改 `upstream/**`/生产 top/SDC/工程。
5. 接受“G2-syn only，不是时序签核，不是生产候选”。

> 即使 P3 解阻，它只做一次隔离综合，不布线、不 bitgen、不下载；**不能改变 P2 的 1080p30 per-stream 链级 −2.67% 结论**，也不能证明双核 Routed 时序。P3 只用于降低双核资源/综合检查点的不确定性，供后续低分辨率双路方案参考；不是 1080p30 的解。

任一不满足 → 保持 `blocked`，problem 用 `TOOL_UNAVAILABLE`/`PERMISSION_MISSING`/`INPUT_CONFLICT`，不排队空转。

### 4.3 五项语义步骤（仅解阻后）

1. 记录解阻证据（TD 空闲、b11 无构建、规划放行时间/原文）；冻结 b6 core 副本×2、最小双核 top、187.5 MHz SDC、源清单/SHA。
2. 写 `syn_only.tcl`：只读源副本、只综合、只 `report_area`/`report_timing`；不 `place`/`route`/`bitgen`/`cwc`/`download`。
3. 运行 1 个 TD 会话/1 次综合（≤30 min），保存 stdout/报告/exit。
4. 与 P1 `marginal`/`conservative` 对比：ERAM/LUT/REG/slice/DSP/PLL、WNS（synth 检查点）、0 error；若超 300 或 WNS <+0.05，如实记录。
5. 写 `result-r0.md`/`lessons.md`，标 `G2-syn only`，停止，冻结 manifest；不改生产/不 bitgen/不下载。

### 4.4 验收门槛

- 综合完成、0 error、两核例化、源副本 SHA 一致；
- 资源与 P1 栏对比有明确结论（成立/偏乐观/偏悲观/超器件）；
- WNS 只作 synth 检查点，≥+0.05 也不能写“Routed 时序通过”；
- 0 place/route/bitgen/CWC/download；0 生产写入；manifest 完整。

### 4.5 不适用

- G2 完整（需 Routed）、G3/G4、板级、生产候选、bit/CWC；P3 只有 G2-syn。
- 不用 P3 的 synth 结果改 P1/P2 的已冻结结论；P3 是确认/反驳，不改门槛。

## 5. 公共执行、证据与预算

### 5.1 工作树与隔离

- 实际工作树：`D:/fpga/ph1p100`；不切换 git worktree；不合并其他聊天成果。
- 每个任务独立目录、独立 manifest、独立命令日志；不共享 work 库/临时文件。
- b11/T08/T10 目录只读；若其文件在任务期间变化，记录快照 SHA，不追逐、不覆盖。
- 本 run 不改 `workflow/tasks.json`；离线包完成不把父 T10/双路目标置 done。

### 5.2 预算与超时

| 任务 | 开发 | 测试 | TD | 备注 |
|---|---|---|---|---|
| P1 | ≤30 calls / 45 min | ≤30 calls / 45 min | 0 | 默认预算，无长构建 |
| P2 | ≤45 calls / 75 min | ≤40 calls / 60 min | 0 | 较默认放宽：43 行网格 + 129 行敏感性 + 负对照 + 报告；仅执行预算，不扩任务/范围 |
| P3 | ≤20 calls / 40 min | ≤30 calls / 45 min | 1 session / 1 synth ≤30 min | 仅解阻后；不 place/route/bitgen/CWC/download |

- 实际：P1 在预算内；**P2 开发约 100 calls，超过冻结 45 calls**（范围未扩、门槛未改、无 TD/硬件/越界写；P2 r1 报告 O3 记录）。后续同规模模型任务应把 CSV 引号/报告模板/边界预检前置，或事先提高预算。
- 读/搜 60 s；Python 120 s；TD 综合 30 min；所有命令用工具支持的 timeout/安全终止；不支持的长时间命令不启动。
- 同失败命令最多首次+1 次有新证据/参数纠正的重试；单问题 ≤3 轮搜索/读取；连续 2 次无新证据/无实质产物/无有效验证 → 主动停止。
- 禁止 shell 循环绕过调用/重试/仿真次数；禁止批量删除；失败日志保留。

### 5.3 开发返回（只给元数据）

`task_ids、status、artifact_paths、manifest_path、test_input_paths、lessons_path、blocked、retest（修复时）`。详细变更/命令/未测写 `result-r0.md`/`lessons.md`，不粘源码/长报告。

### 5.4 综合测试

- 每任务一个**新**综合测试者，独立于开发；P1/P2 各一个，P3 解阻后一个；不跨任务复用。
- 只写 `test-reports/<task_id>/**` 与 `<task_id>-r<round>-integrated.md`；不改候选/生产/其他 run。
- 报告首行唯一 `### 判定：PASS` 或 `### 判定：FAIL`；三维 + G 层；独立复现/负对照；输入漂移检查；未测项/回退。
- 返回：`task_id、dimension=integrated、dimension_results、verdict、report_path、manifest_path、blocked、retest`。
- round0 首次验收；同任务真实 FAIL 续原开发/原测试，最多 3 轮实际修复；缺工具/设备/资料/授权直接 blocked，不空转。

### 5.5 PASS/FAIL 边界

- P1/P2 的 PASS 只证明“离线资源/模型/报告在冻结输入上自洽”，**不证明** RTL、综合、Routed、板级、双路实时、曝光同步或生产资格。
- P2 的 `conditional` 不是 PASS 的子集；报告必须让读者一眼看到“低于 25% / 双核时序未证明 / 内容未覆盖”。
- P3 的 G2-syn 不是 G2；不得用 synth WNS 替代 Routed，不得写“双核时序通过”。

## 6. 主要风险与控制

| 风险 | 影响 | 控制 |
|---|---|---|
| 把 `81.067×2=162.13>155.52` 当双核可行 | 聚合掩盖 per-stream/链级 | 设计指南 §4.2；P2 负对照；tester 必查 |
| 把顶层 102 ERAM×2 当双核资源 | 高估/低估，结论反转 | P1 层次归属 + marginal/conservative 两栏；禁止单点 |
| 用 synth 资源/时序拟合 | 资源偏小、时序偏乐观 | P1 `stage` 检查 + 负对照；只用 routed |
| 链级 6.421M cycles 边界不清 | 1080p30 结论差 2–7% | P2 三档 overhead 敏感性；core-only/chain 两栏；标 assumed |
| 内容只覆盖 comp/rand/full_grad | 自然图像可能更慢 | 报告写 `unproven`；不得称“保证”；后续实拍另包 |
| 双核时序未证明 | 推荐可能过于乐观 | 双核最高 `conditional`；P3 只 synth；需后续 Routed |
| DDR 只有理论峰值 | 平均够≠桥够 | 给 required efficiency；标 unproven；不写实测 |
| b11/T08/T10 并行变化 | 输入漂移/冲突 | 只读快照 SHA；不改其目录；TD b11 优先 |
| TD 争用 | P3 拖慢 b11 | P3 blocked；P1/P2 不依赖 TD；条件严格 |

## 7. 后续主题（本轮不做，最多 3 条）

1. **核心服务率提升**：P2 已证明双核不改变 per-stream 链级（75.684 MB/s）；要在 1080p30 达到 25% 裕量，需把链级 cycles/frame 从 6,421,414 降到 ≤5,000,000（−22.14%），或链级时钟到 ≥240.803 MHz。可评估 2 pixel/cycle、加宽匹配/打包、流水加深/独立 DDR 读通道；需新 RTL/综合包与用户授权。
2. **DDR/桥实测服务模型**：在板级测 256-bit PAXI 的持续读写、单拍/突发、仲裁/刷新；验证 2R+2S 的 required efficiency；属 b11/后续板级包。
3. **生产双核集成与系统验收**：把双核 A+、双路同步、槽所有权、CMP 导出合并到统一候选，做 Routed/G2、真实曝光/恢复/长稳；另开 run，不在本轮自动续做。

原需求路径保留：`D:/fpga/ph1p100/workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility/request.md`。

## 8. 收尾与恢复

- P1/P2 已 PASS；由**原规划**（本 run 规划会话）读取报告、更新 dispatch/收尾；P3 仅在 TD 空闲、b11 不重建、原规划明确放行且用户不扩权时另行派发；主不选任务。
- 收尾写 `handoff.md`、`final-summary.md`、`user-summary.md`：逐项完成/未完成、唯一 manifest、独立报告、真实数字、G 层、未测/板级缺项、回退、剩余主题、下一次准确启动/恢复文本。
- 本 run 的准确恢复入口（供主/用户）：
  `使用 fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261025-195604_fpga-dual-aplus-core-feasibility；本轮目标：读取 P1/P2 冻结 manifest 与独立报告，确认双路 1080p30 infeasible 与降帧/降分辨率建议；P3 仍 blocked，需先获得 TD 空闲/b11 不重建/用户或主明确授权。`
- 若跨宿主/换父会话：按本 run 计划、manifest、报告恢复，登记新旧真实 sessionID 映射；不重置轮数/预算，不假称 resume。

## 9. 状态汇总

| 包 | 状态 | 原因/下一步 |
|---|---|---|
| `T10.dual-core-resource-baseline` | **done（round1 PASS）** | manifest `228531e7…bdd0`；1 轮实际修复；资源 conditional，双核时序 unproven |
| `T10.dual-aplus-service-verdict` | **done（round1 PASS）** | manifest `5ed90500…36a6`；1 轮实际修复；双路 1080p30 infeasible；主推荐 1600×900@30 c1s1（带条件） |
| `T10.dual-core-synth-probe` | **blocked（未派发）** | P2 已 PASS；TD 空闲/b11 优先/规划放行未确认；用户未新增 TD/板卡授权；不占 TD |
| 本轮主要目标 | **completed（离线模型）** | P1+P2 已给出资源/服务率/降帧/降分辨率结论；P3 可选综合、不改变 1080p30 结论；板级/RK/生产不在本轮 |
