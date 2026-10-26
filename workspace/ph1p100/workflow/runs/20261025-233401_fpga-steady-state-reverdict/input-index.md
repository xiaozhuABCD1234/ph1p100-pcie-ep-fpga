# 输入索引：P2 可行性稳态锚点复核（`20261025-233401_fpga-steady-state-reverdict`）

- 项目根：`D:/fpga/ph1p100`；输出目录：`workflow/runs/20261025-233401_fpga-steady-state-reverdict`
- 角色：fpga-planner（只写本 run 根目录的规划文件；不开发、不测试、不派生代理）
- 日期：2026-10-25/26；本文件冻结**本轮计划采用的输入版本**，不重写历史报告
- 需求原文与紧邻上下文：`workflow/runs/20261025-233401_fpga-steady-state-reverdict/request.md`（6,320 B，SHA256 `1375364A03BB7DF582E12F1EC0CDF7D84E02BD8D8EAF46D07C01BA3AA24353AF`）
- 用户原话：“按这个工作流进行复核吧”。复核对象是上一轮 P2 `T10.dual-aplus-service-verdict` 的“1080p30/双路 `infeasible`”结论及三点质疑（单帧延迟≠稳态吞吐；0% 与 25% 混判；DDR/UART/overhead/内容锚点口径）。

## 0. 本轮 1 个主要目标与必须回答的问题

**主要可验收目标（1 个）**：对 P2 的 1080p30/双路可行性结论做有界、可复现的**稳态锚点复核与纠正**，产出“单帧延迟 vs 稳态帧间隔”的实测锚点、`nominal 0%`/`25%` 两个 gate 的分离判定，以及修正后的 verdict（允许 `conditional`/`not_proven`）。

必须回答（编号在本计划内稳定引用）：

| # | 问题 | 归属包 |
|---|---|---|
| Q1 | b6 `full_grad` 单帧 `cycles=6,421,414` 是 startup/tail 延迟还是每帧稳态？4 帧（或等价多帧）实测的单帧冷延迟 `L_cold` 与稳态帧间隔 `S_ss` 各是多少？ | P1 |
| Q2 | 把 verdict 拆成 nominal per-stream 30 fps（0%）与 25% design margin（容量 ≥1.25×需求）两个 gate，分别给单路/双路/不同内容锚点结果 | P2 |
| Q3 | 1080p 是否应参与 overhead 0/426,385/1,000,000 三档敏感性？0-overhead/流水线隐藏 tail 是否可行优化路径 | P2 |
| Q4 | DDR 峰值口径：1333（5,332 MB/s）vs 1600（6,400 MB/s）重算 required efficiency 与 gate；平均带宽是否仍非瓶颈 | P2 |
| Q5 | “UART 导出”在链级锚点中的性质：sim-only fast sink 还是真实 115200；吞吐锚点应否排除 UART | P2 |
| Q6 | 双核 nominal 的 per-stream 结论、共享 PAXI/DDR 争用、资源 marginal/conservative、Routed 时序 unproven 边界；不得用 aggregate 2C 代替 per-stream | P2 |
| Q7 | P2 模型是否还有其它口径/算术错误；给出修正后 verdict | P2 |

## 1. 采用版本与冻结输入（SHA256 于 2026-10-25 本规划轮磁盘重算）

| # | 路径（相对项目根，`…/` 省略前缀） | 字节 | SHA256 | 用途/标签 |
|---|---|---:|---|---|
| R1 | `workflow/runs/20261025-233401_fpga-steady-state-reverdict/request.md` | 6,320 | `1375364A…53AF` | 本轮需求；只读 |
| P2-1 | `workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility/T10.dual-aplus-service-verdict/r0/feasibility-report.md` | 28,952 | `82C2669E…36A6` | 被复核报告（r1 PASS 冻结件）；只读 |
| P2-2 | 同目录 `manifest-r0.json` | 28,684 | `5ED90500A7E9650CA17E5F269731984FEA9F215D7401D555DC5633551C2436A6` | P2 唯一冻结 manifest；只读 |
| P2-3 | 同目录 `model/calc.py` | 32,610 | `9EEA41F5…BD2C` | P2 模型；P2 复核包可复制，不修改原件 |
| P2-4 | 同目录 `model/rules.json` | 7,639 | `FDAAE351…2F4D` | P2 判定规则（R1–R6、gate、DDR 6,400、1080p tier `applies=false`） |
| P2-5 | 同目录 `inputs/frozen-inputs.json` | 6,918 | `888D3F33…0F59` | P2 冻结常量/锚点/标签 |
| P2-6 | 同目录 `out/scenarios.csv` | 21,150 | `2D806599…5F50` | 43 行旧判定（回归复现对象） |
| P2-7 | 同目录 `out/overhead-sensitivity.csv` | 24,190 | `E4D6F8D9…67F4` | 129 行三档（1080p 固定锚点） |
| P2-8 | 同目录 `out/ddr-budget.csv` | 1,777 | `2C83C227…4FB9` | 6,400 MB/s 口径 |
| P2-9 | 同目录 `out/content-sensitivity.csv` | 745 | `50B81124…7B69` | comp/rand/full_grad 三锚点 |
| P2-10 | 同目录 `out/frontier.csv` | 4,079 | `CDD7E504…99B4` | 前沿/推荐 |
| P2-11 | `workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility/test-reports/T10.dual-aplus-service-verdict-r1-integrated.md` | 15,245 | `71CAFC6D…C4D4` | P2 独立测试报告；只读 |
| B11-1 | `workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b11-aplus-read/r0/CANDIDATE-MANIFEST-b11-aplus-read-r0.json` | 11,991 | `4425FDCF…961A` | b11 冻结候选（源副本 SHA 的权威来源）；只读 |
| B11-2 | 同 run `T10.b11-aplus-read/r0/sim/caps/full.stats` | 159 | `60B6A9C8…9212` | b11 两帧：`cap=2 … cycles=11445988 exp_bytes=80068 cap_bytes=80156 read=259200` |
| B11-3 | 同 run `T10.b11-aplus-read/r0/sim/tb_b11_full.v` | 8,612 | `E278CEA5…C699` | 两帧集成 TB（新 TB 的派生基线） |
| B11-4 | 同 run `T10.b11-aplus-read/r0/sim/p2_paxi_model_b11.v` | 5,707 | `8B2D937D…8D25` | 行为级 256-bit PAXI（单拍、AR_GAP/R_GAP；非争用模型） |
| B11-5 | 同 run `T10.b11-aplus-read/r0/sim/a1_ddr_model.v` | 2,509 | `BBB41B89…C8B9` | b6 TB 用行为 DDR |
| B11-6 | 同 run `T10.b11-aplus-read/r0/result-r0.md` | 5,781 | `4AEA0871…3CE` | b11 结果与边界（WNS +0.015 等） |
| B6-1 | `workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b6-a1-htab-nw/r0/sim/boundaries/src/tb_camera_a1_uart_top.v` | 11,420 | `D47E7A1D…E994` | b6 单帧链 TB（P1 金标准） |
| B6-2 | 同 run `T10.b6-a1-htab-nw/r0/sim/captures/full_grad.stats` | 158 | `217058D8…1CA2` | b6 单帧：`cap=1 … cycles=6421414 read_words=129600 exp_bytes=40032` |
| DOC-1 | `docs/DDR1333集成与1333vs1600对比_2026-10-17.md` | 34,258 | `3F273EE4…C6AD` | DDR1333/1600 同工具 STA 与频点决策（M1a 维持 1333）；其 §8 的“带宽对照 1.2/2.33/3.4 GB/s”与显式公式不自洽，本轮只作待核口径 |
| DOC-2 | `docs/项目成果整合与进度复核_2026-10-25.md` | 17,833 | `2BEC1A83…3506` | 当前状态盘点；明确 UART 115200 仅取证用（11,520 B/s，2,592,000 B ≈225 s） |
| TSK | `workflow/tasks.json` | 88,112 | `FD820546…5D23` | T10 = `active`/blocked 未完成；**本轮只读，不修改** |

## 2. b11 冻结源副本（P1 的 `src/` 只允许从这些路径复制并逐字节核对）

来自 `B11-1` 的 `changed_src` 组（9 个）：

| 文件 | 字节 | SHA256（b11 manifest） |
|---|---:|---|
| `a1_raw_crop.v` | 7,257 | `33a6fee77fd1aa67a31cacf26dd5530e5e2ea474ee655cbd5f1d98d887c5d72d` |
| `a1_ddr_slot_store.v` | 14,547 | `86d626465dc8d0643a7bb62e952e79ee89215c2e0c02719fc348a04c4363ed84` |
| `a1_uart_export.v` | 27,395 | `69b73de4205cf3387422e9a5097a085dd29831a80335aeeebf00d42b6a819c3e` |
| `camera_a1_uart_top.v` | 41,313 | `214b21015331e5cf90c0148b7c17a26351ffbade1d012da71e4d001d9b0b8242` |
| `cam_diag_mailbox.v` | 3,911 | `352af7c85094ea99b575e99da952af8d33871352140e4c6efddff9e6c2407278` |
| `a1_frame_top.v` | 25,654 | `0064607aceb20ae3ef14133f0aaf5f8b3f489943011a66a1ddc005350dba7109` |
| `a1_deflate_core.v` | 80,501 | `a91c2ed82fbef654c4e065b64ae1cc268ca232feaa26fdd313c58d8740f81b3e` |
| `p2_ddr_bridge.v` | 12,481 | `4a2c7ddf6564de8659e35278c6a6eb5d04603cf0efd9e5899d551f13d884e43a` |
| `p2_a1_board_top.v` | 17,952 | `dafa65ee9f7ca060184de7b31969f95270177fbd10f08c749b115e1057ab348d` |

来自 `B11-1` 的 `repo_deps`（生产树只读依赖，复制不改）（2 个）：

| 文件 | 字节 | SHA256 |
|---|---:|---|
| `fpga/csi2/src/a1/a1_ddr_arb2.v` | 3,739 | `6513ad839dee02e932c49bdfd5afa3d62c382d4a144b8e74d5574273804afdc6` |
| `fpga/csi2/src/mem/capture_async_fifo.v` | 2,044 | `59dd6dcb5b7e7774f7d6518f50f56cafbc8be6b70e8ae1508236bac2b5af531d` |

来自 `B11-1` 的 `sim` 组中本轮需要的 3 个：`tb_b11_full.v`（`E278CEA5…`）、`p2_paxi_model_b11.v`（`8B2D937D…`）、`a1_ddr_model.v`（`BBB41B89…`）。

## 3. 关键数字与“当前解释”（第 4 列是本轮要复核的争议状态）

| 量 | 值 | 来源（label） | 当前解释/争议 |
|---|---:|---|---|
| b6 单帧 full_grad `cycles` | 6,421,414 | B6-2（measured） | P2 当作**每帧服务时间** → 29.199 fps / 75.684 MB/s，判 `infeasible`。**争议：这是冷启动单帧完成时间，不是稳态帧间隔** |
| b6 单帧导出/抓包 | `exp_bytes=40032`、`cap_bytes=40076`、`read_words=129600` | B6-2 | 证明 1080p RAW 槽几何与 44 B 头；不是 payload 尺寸 |
| b11 两帧合计 `cycles` | 11,445,988 | B11-2（measured） | 两帧平均 5,722,994 cycles/帧 → 32.76 fps / 84.92 MB/s（stats 口径含 2,000-cycle drain；事件口径 ≈5,721,994）；**含冷启动**，是稳态容量的（条件）下界，不是 P2 用的 6.421M |
| b11 两帧计数 | `cap=2 enc=2 exported=2 read=259200 raw_drop=0 cmp_drop=0 wd=0 err=0` | B11-2 | 两帧都走完“采集→RAW 槽→DDR 读→core→CMP→导出”；无丢帧 |
| b11 两帧几何/内容 | CAM 3864×2192、ROI 972/556、W/H 1920/1080、LINE_GAP=16、FRAME_GAP=400、`UART_DIV=1`、`clk_uart=clk_a1` | B11-3 | 与 b6 的 CAM 3840×2160、ROI 960/540、LINE_GAP=40、`clk_uart`=1 GHz 不同；几何驱动差 0.86%、内容压缩后差 0.005%，但 **UART sink 慢 325,260 cycles/帧（≈5.1%）**；综合预期 `L_cold` 高 0–5% |
| b11 核心 vs b6 核心 | b11 `a1_deflate_core.v` 80,501 B `a91c2ed8…`；b6 80,196 B `6797db05…35bb` | B11-1 / b6 manifest | **两者功能等价**：unified diff 仅 20 行，新增只读观测口 `dbg_state = state`，无逻辑/协议/输出改动（本规划轮已 diff 核实）；报告必须记录该等价性 |
| b6 comp 核级 | 355,261 cycles / 153,600 B = 2.312897 cycles/B → 81.067159 MB/s | P2-5（measured, 1920×64 strip） | 是“最慢 measured 核级向量”，但**不是全帧锚点**；按面积外推到 1080p 是 assumed |
| b6 rand 核级 | 161,479 cycles / 153,600 B → 178.351365 MB/s | P2-5（measured） | 最快向量；不作最坏 |
| P2 链级 overhead | 426,385 cycles = 6,421,414 − 5,995,029.375 | P2-5（**assumed**） | 定义上等于“冷启动单帧 − comp 外推核级”，**内容混杂、且与待复核的 6.421M 循环依赖**；本轮必须重新表述 |
| 25% gate | per-stream 容量 ≥ 97.20 MB/s（=77.76×1.25） | P2-4 + 设计冻结 | 项目设计门槛；0% 仅算术对照 |
| P2 DDR 峰值 | 6,400 MB/s（×32 @1600） | P2-4 | **与当前 1333 主线不符**；DOC-1 §4.3 M1a 维持 1333；1333 显式峰值 = 1333 MT/s ×32 bit /8 = 5,332 MB/s（用户域 256-bit @166.65 MHz 同为 5,333 MB/s） |
| P2 UART 口径 | 链级锚点含“UART 导出” | P2-1 §2 | TB 是 `UART_DIV=1` 的 **sim-only sink**：`clk_uart=clk_a1` → 18.75 MB/s（10 cycles/B，400,320 cycles/帧），b6 则 1 GHz → 100 MB/s（75,060 a1 cycles/帧）；真实 115200 = 11,520 B/s（DOC-2 亦明确仅取证用），比 b11 sink 慢 1,628×、比 b6 sink 慢 8,688×。稳态下该尾巴是常数、帧间差抵消，主要计入 `L_cold`；若随帧积压才标 `sink_limited` |
| 双核资源 | marginal 231/300（余 69）、conservative 289/300（余 11，3.67%） | P2-1 §4（P1 `228531e7…bdd0`） | 双核 `feasible` 不存在；Routed 时序 unproven；本 run 不重跑 TD |
| 双路 1080p30 DDR 2R+2S | 809.034 MB/s（含 CMP DDR，20 B/32 B 膨胀） | P2-8 | 占 5,332 的 15.17%（P2 用 6,400 时为 12.64%）；平均非瓶颈，持续/仲裁 unproven |

## 4. 已有成果与所有者（本轮只读）

| 对象 | 所有者/状态 | 本轮动作 |
|---|---|---|
| `20261025-195604…/T10.dual-core-resource-baseline/**`（P1 资源基线，manifest `228531e7…bdd0`） | 上一轮已 PASS 冻结 | 只读引用数字；不修改 |
| `20261025-195604…/T10.dual-aplus-service-verdict/**`（P2 模型/表/报告，manifest `5ed90500…36a6`） | 上一轮已 PASS 冻结 | 只读；P2 复核包复制到本 run 后修改自己的副本；**不改原件** |
| `20261020-0209…/T10.b11-aplus-read/**`（两帧 TB/模型/统计/候选） | b11 包所有；板级下载被硬件阻塞 | 只读 + 复制冻结副本；不改原目录/候选/报告 |
| `20261020-0209…/T10.b6-a1-htab-nw/**`（单帧 TB/统计） | b6 包所有 | 只读 + 复制冻结副本；不改 |
| `20261025-180900…/T08/T10` | 另一 run 所有 | 只读；不改、不并入 |
| `workflow/tasks.json` | 主源任务板；T10 `active`（未完成） | **只读；本轮不修改** |
| `20261025-233401…/T10.ss-steady-anchor/**`（本轮 P1，round0 PASS） | 本 run P1 已完成并冻结（manifest `39f3e3d6…9f9a`） | **只读；不得修改**；A1 交 P2 |
| `20261020-0209…/T10.b13-ddr-retry/**`、`T10.b14-cam-b/**` | **另一所有者的在飞工作**（本规划轮观测到 2026-10-25 22:53–23:38 有 TD 构建/布线/bitgen 与 COM8 采集，23:48–23:50 有 b14 收尾文件） | **不是本 run 输入**；不读其结论、不引其数字、不抢占 TD/板卡；本 run 与其并行但离线 |

## 5. 未决事项（由 P1/P2 在任务内核实，不需用户输入）

1. `S_ss`（稳态帧间隔）与 `L_cold`（冷启动单帧完成）的实测值；两帧统计 11,445,988 是否自洽拆分为 `L_cold + S_2 + drain`（事件口径 `t_exp(2) ≈ 11,443,988`）。
2. 4 帧 slot-aware 驱动是否无丢帧（`raw_drop=0/cmp_drop=0`）且相机不是限速方（`t_pub(k+1) < t_exp(k)`）。
3. b6 几何/1 GHz UART 与 b11 几何/187.5 MHz UART 的 `L_cold` 可比性（预期 6.42M–6.75M；差值主要来自 325,260 cycles 的导出串行成本与 ≤1% 几何/内容差；超出须给原因）。
4. `comp` strip 的 2.313 cycles/B 是否是 1080p 全帧的保守上界（**无全帧 comp 锚点**，预期标 `assumed`）。
5. DOC-1 §8 的“1.2/2.33/3.4 GB/s”推导不明：P2 复核包必须用显式公式（data rate×width/8）并单列该文档值，不得静默采用。
6. 共享 256-bit PAXI 双核仲裁/单 outstanding reader 的实际服务率：本 run 无 RTL/板级证据，保持 `unproven`。

## 6. 本轮禁止引用/禁止混用的输入

- **`workflow/runs/20261020-0209…/T10.a1-frame-top/dev-result.md` 的 `f1080p_rand=4,678,532 cycles / 103.88 MB/s`、`multi1080p=9,355,687`**：该包使用 upstream core `6cd35881…`（现 `upstream/…/a1_deflate_core.v`），**不是 b6/b11 冻结 core `6797db05/a91c2ed8`**；属不同 RTL 血统，禁止混入本 run 的链级/核级锚点，只能作为“不同血统、不可比”的反例记录。
- b12/b13 及任何 `board/captures*` 的 COM8 计数：本轮 0 板级，不得当作吞吐/稳态证据。
- 任何把 2 帧平均、单帧冷延迟、core-only 或 aggregate 2C 当作“1080p30 稳态 per-stream 容量”的引用。
- `docs/**` 只作口径参考，不改写；DOC-1 的带宽数字与公式冲突时以显式公式为准并记录差异。

## 7. 环境（本规划轮已核实）

- Python `C:\Program Files\Python311\python.exe`（3.11.x）；无网络依赖。
- ModelSim Intel FPGA Edition 10.5b：`D:\intelFPGA\18.1\modelsim_ase\win32aloem\{vlib,vlog,vsim}.exe`（存在）。
- 共享只读 INI：`D:\fpga\ph1p100\work\parallel-sim-20261024-2204\codec-throughput\modelsim.ini`（存在）；每个任务必须复制到自己的短临时目录并以 `MODELSIM` 指向副本，工作库/日志独占。
- git HEAD：`27c596b01cd961dfa9d0850e4fbf879fe249de90`（2026-10-18）。工作树**既有 dirty**（`.agents/skills/*`、`AGENTS.md`、`docs/TD命令行使用说明.md`、`tools/td/*` 等），非本 run 产生；本 run 不提交、不改这些文件。
- **并发活动（规划轮实测）**：同一 `20261020-0209…` run 目录下有另一所有者正在做 `T10.b13-ddr-retry` 的 TD 构建/布线/bitgen 与 COM8 采集（22:53–23:38），以及 `T10.b14-cam-b` 的规划/收尾（23:48–23:50）。本 run **不使用 TD/板卡**，不与其争用；但机器负载可能拉长 ModelSim 墙钟，P1 的 2700 s/次 与 100 min 总仿真预算已按最坏情形冻结；超出即 partial，不延长、不杀他人进程。
- 本规划轮读取 b11/b6/P2 冻结件后立即记录 SHA（见 §1）；若任务期间这些文件被外部修改，开发/测试只比对 SHA 并报告漂移，不追逐、不覆盖（pacing/输入以本文件冻结值为准）。
- 临时工作目录约定：`%TEMP%\opencode\ss-anchor\`（开发）、`%TEMP%\opencode\ss-anchor-test\`（测试），短路径规避 TB 128 字符路径限制。

## 8. 本规划轮实际读取（用于追溯，不替代复核）

`AGENTS.md`、`.agents/skills/fpga-planner/SKILL.md`、`.agents/skills/fpga-design-guide/SKILL.md`、`.agents/skills/fpga-orchestrator/references/work-limits.md`、`relay-contract.md`、`request.md`、P2 报告与 `calc.py`/`rules.json`/`frozen-inputs.json`/4 张 CSV、P2 独立测试报告、b11 manifest / `tb_b11_full.v` / `p2_paxi_model_b11.v` / `full.stats` / `result-r0.md` / `sim-results-b11.json`、b6 TB 头尾与 `full_grad.stats`、b6 集成测试报告（TB 128 字符限制、核心 SHA）、b11 与 b6 的 `a1_deflate_core.v` diff、DOC-1、DOC-2 关键段、`workflow/tasks.json` T10 条目、b11/b6/P2 关键文件 SHA。

## 9. P1 回填（2026-10-26，round0 PASS；P2/P3 输入）

- 判定：`T10.ss-steady-anchor` r0 **PASS**（functional/engineering/system 全 PASS；G0/G1 pass，G2–G4 `not_applicable`；`blocked=null`、`retest` 空、0 修复轮）。
- 冻结：manifest `39f3e3d6d115afbdcda9753b254f6971a10eb75df88d5718eb9ea5a247199f9a`（41 artifacts；`stopped_modifying=true`、`active_commands=0`）；报告 `test-reports/T10.ss-steady-anchor-r0-integrated.md`；`out/steady-state.json` `a0945e1f60d9…`；`sim/caps/ss4.stats` `29bd31851804…`；`sim/logs/run4.log` `dc215e0b46e4…`。
- 关键实测（A1，measured）：`L_cold=6,766,434`、`S_2=S_23=S_34=4,677,535`、`S_ss=4,677,535`（band 0.00%）、`C_ss=103.9009 MB/s`、`fps=40.0852`、`margin_0=+33.6174%`、`margin_25=+6.8939%`、`f_req_0=140.326 MHz`、`f_req_25=175.408 MHz`、`startup_pct=44.66%`、`export_tail=480,930×4` 恒定、`sink_limited=false`、`C_excl_export=C_ss`；counters `cap=4 enc=4 exported=4 read=518400`、drop/dup/geom/err/wd=0；V1–V6 全 true。
- **争议闭合**：b6 的 6,421,414 是**冷启动单帧**（startup 占 44.66%），不是每帧稳态；两帧平均 5,722,994 也高于稳态 22.3%。P2 的 `75.684 MB/s / 29.199 fps / −2.669%` 是把延迟当吞吐的产物。A1 单内容梯度锚点的算术为 `103.9009 MB/s`、G0 `+33.62%`、G25 `+6.89%`。
- **仍未决**：自然图像/低照/噪声（A2 comp 外推仍 `assumed`）、DDR sustained/PAXI 仲裁、双核 Routed/共享 PAXI、真实 115200/PCIe、TD/板级；A1 的 40.085 fps **不得**外推双路 1080p30。
