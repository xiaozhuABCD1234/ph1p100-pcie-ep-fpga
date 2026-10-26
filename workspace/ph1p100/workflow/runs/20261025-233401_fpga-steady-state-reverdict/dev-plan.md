# 开发与验收计划：P2 可行性复核 + 1080p30 G0 收口 + 四轮矩阵（离线仿真/模型）

- run：`20261025-233401_fpga-steady-state-reverdict`；项目根 `D:/fpga/ph1p100`；输出目录同 run
- 用户原话：首轮“按这个工作流进行复核吧”；**2026-10-26 新边界**：“25%不是硬门槛，然后我希望还是做1080p30，不然和要求是不一样的”。
- 当前主要目标（1 个）：**1080p30 G0 收口**——`G0`（per-stream 77.76 MB/s ↔ `S_ss ≤ 6,250,000 cycles/frame` @187.5 MHz）是**硬门槛**；`G25`（97.20 MB/s）只作设计参考/风险提示，**不得再用“25% 不够”主推降档**；不降档，先量化 G0 差距与可闭合路径（P3/P4）。
- 拆分：**4 个正式包**，两级（需求 → 工作包），每包 ≤5 项语义步骤；`BATCH_SIZE=1`；`workflow/tasks.json` 不修改。
- 状态（2026-10-26）：**P1/P2/P3/P4 全部 PASS，run finished**。P1 `39f3e3d6…`；P2 `fd27c70f…`（`not_proven`）；P3 r2 `3C8377A4…`（`G0_feasible_for_scope`，comp proxy，2 修复轮）；**P4 `T10.ss-4run-matrix` r0 PASS**（manifest `d353c61a…`，68 artifacts）——4 个不同条件全尺寸 4 帧：R1 C1 slot-free 4,677,970（G0 +33.605%）、R2 C1 strict 6,449,405（G0 −3.092%）、R3 C2 rand 5,189,503（sink-limited → `G0_not_proven`）、R4 comp 5,928,286（G0 +5.427%，复现 P3 Δ=0）。最终 headline **`G0_feasible_for_scope` 已收窄**（C1 全帧合成 raw + comp proxy / slot-free / 93.75 MB/s sim sink / 行为 DDR / 单核 187.5 MHz / per-stream）。P1–P4 冻结件不得修改；T10 仍未置 done；G25 仅参考、不降档。

## 1. 计划总表

| task_id | 问题/产物 | 实际工作树/允许写路径 | 依赖 | functional | engineering | system | 必要 G 层 | 状态 | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|
| `T10.ss-steady-anchor`（P1） | Q1：同一冻结 RTL/TB 下的 2 帧控制 + 4 帧实测，给 `L_cold`、`S_2/S_23/S_34/S_ss`、容量/margin/所需时钟与 V1–V6 有效性；回答“6,421,414 是否只是 startup” | `D:/fpga/ph1p100`；仅 `workflow/runs/20261025-233401_fpga-steady-state-reverdict/T10.ss-steady-anchor/**` + 独占临时目录 `%TEMP%\opencode\ss-anchor\` | 无（只读 b11/b6/P2 冻结件） | 2 帧控制逐值复现；4 帧计数/事件/算术；V1–V6；3 个解析负对照 | 副本 SHA=0 mismatch；TB 仅白名单差异；独占 work 库/日志；硬超时；manifest | 测量边界标注（fast sink/行为 DDR/单一内容）；per-stream；不声称 DDR sustained/板级 | G0/G1；G2–G4 N/A | **done（round0 PASS）** | 冻结 manifest `39f3e3d6…9f9a`；A1 交 P2/P3 |
| `T10.ss-verdict-r1`（P2） | Q2–Q7：两 gate 判定矩阵、内容锚点 A1–A4、1080p 参与 overhead 三档、DDR 1333/1600、UART 边界、双核 per-stream/共享 PAXI、P2 口径/算术错误表、修正 verdict | 同上；仅 `workflow/runs/20261025-233401_fpga-steady-state-reverdict/T10.ss-verdict-r1/**` | P1 PASS（已满足）+ P1 冻结件 | 旧 43 行回归 0 mismatch；两 gate 分列；6 负对照；前沿/推荐可复算 | 纯函数/规则/测试；CSV↔报告一致；manifest | 不把 `below_25` 写 `infeasible`；不用 aggregate/core-only/cold latency 替代 per-stream 稳态；A1 单内容不得外推；无 TD/板级声明 | G0/G1；G2–G4 N/A | **done（round0 PASS）** | manifest `fd27c70f…fad0`；headline=`not_proven`；P3 只读引用 |
| `T10.ss-g0-closure`（P3） | G0-only 判定 + tail-overlap 实测 + comp-like 全帧 4 帧 + 2.67% 差距菜单 + G0 结论（不降档） | 同上；仅 `workflow/runs/20261025-233401_fpga-steady-state-reverdict/T10.ss-g0-closure/**` + 独占临时目录 `%TEMP%\opencode\ss-g0\` | P1/P2 PASS 且冻结；只读 P1 TB/driver/steady-state、P2 verdict/model、comp 向量 | R0 控制逐值复现；R1–R3（+可选 R4）计数/事件/算术；G0 表；内容代理自检；负对照 | TB 仅白名单差异；副本 SHA=0 mismatch；独占 work 库/日志；硬超时；manifest | G0 硬门槛、G25 仅参考；不降档；内容代理/快速 sink/行为 DDR/per-stream 边界；无 TD/板级 | G0/G1；G2–G4 N/A | **done（r2 PASS；实际修复 2 轮）** | manifest-r2 `3C8377A4…`（82 artifacts）；`G0_feasible_for_scope`；收尾已写 |
| `T10.ss-4run-matrix`（P4） | 4 个不同条件的全尺寸 4 帧：C1 raw slot-free/fast、C1 strict/fast、C2 rand slot-free/fast、comp slot-free/fast；量化 content/pacing/sink 与 G0 | 仅 `workflow/runs/20261025-233401_fpga-steady-state-reverdict/T10.ss-4run-matrix/**` + `%TEMP%\opencode\ss-4run\` | P1/P2/P3 冻结；P3 TB `A565C6F2…`；C1/C2 raw.bin、comp 向量/hex | R4 复现 P3 R3 ±0.5%；R1/R2 同内容；4 run 计数/自检；四轮表 | TB 仅白名单；SHA 0 mismatch；独占库；2700 s/run；总 ≤120 min；manifest | 合成内容标签；G0 硬/G25 参考；不降档；无板级/TD | G0/G1；G2–G4 N/A | **done（r0 PASS；1 轮）** | manifest-r0 `d353c61a…`（68）；G0 headline 收窄；收尾已写 |

**包数说明**：4 个正式包（均 done），使用第 4 个名额；P1 `39f3e3d6…`、P2 `fd27c70f…`、P3 `3C8377A4…`、P4 `d353c61a…` 均 PASS 并冻结；P4 r0 四轮矩阵完成。P1–P4 冻结件不得修改；P4 不得用 C1/comp 结论外推自然/全内容/双路，也不得用 G25 主推降档。

## 2. 先决算术与 P1 实测确认（Q1 已闭合；P2 已给修正 verdict）

由 b11 冻结两帧统计（`cap=2 enc=2 exported=2 read=259200`，`cycles=11,445,988`，后者含导出后 2,000-cycle drain）：

```text
t_exp(2) = 11,445,988 - 2,000 ≈ 11,443,988
L_cold + S_2 = t_exp(2)
若 L_cold >= S_2（冷启动不快于稳态）  =>  S_2 <= 5,721,994  =>  C >= 84.93 MB/s  =>  G0 已过（+9.2%）
```

该条件不等式已被 P1 的 4 帧实测**确认为真**（`L_cold=6,766,434`、`S_2=S_23=S_34=4,677,535`，band spread 0.00%）：

| 量（P1 r0 measured） | 值 | 含义 |
|---|---:|---|
| `L_cold` | **6,766,434** cycles | 冷启动单帧完成（比 b6 的 6,421,414 高 5.4%；b6 是不同几何/1 GHz UART 的冷延迟，不是吞吐） |
| `S_2` / `S_23` / `S_34` | **4,677,535 / 4,677,535 / 4,677,535** | 三间隔完全一致；`S_ss=4,677,535`，spread 0.00% |
| `S_avg2`（事件口径） | 5,721,984.5 | 两帧平均，**不是** `S_ss`；已证明比稳态高 22.3% |
| `S_ss` / 阈值 | 4,677,535 vs 0% 6,250,000 / 25% 5,000,000 | 同时低于两个阈值 → A1 上 G0 与 G25 都过 |
| `C_ss` / `fps` | **103.9009 MB/s / 40.0852 fps** | `4.86e8/S_ss`、`1.875e8/S_ss` |
| `margin_0` / `margin_25` | **+33.6174% / +6.8939%** | A1（单内容梯度）上的算术；**不是**系统 verdict |
| `f_req_0` / `f_req_25` | 140.326 / **175.408 MHz** | 25% 所需时钟低于已验证的 187.5 MHz |
| `startup` / `startup_pct` | 2,088,899 / **44.66%** | 冷启动占比 >15% → 把 6.421M 当吞吐是实质性口径错误 |
| `export_tail` | 480,930×4，恒定；`sink_limited=false` | 常数尾巴在帧间差抵消；`C_excl_export=C_ss`，不扣减 |
| V1–V6 | 全 true | 计数完整、控制逐值、稳态一致、相机不限速、无早期丢帧、单调 |

**因此**：`6,421,414` 确认为**冷启动单帧延迟**，不是每帧稳态；P2 的 `75.684 MB/s / 29.199 fps / −2.669%` 是把延迟当吞吐的产物。A1 单内容锚点上 1080p30 per-stream 为 `103.9009 MB/s`、G0 `+33.62%`、G25 `+6.89%`。

**但 A1 只是单内容/单几何梯度锚点**：不得外推自然图像、低照/噪声或双路 1080p30；A2（comp 外推 6,421,414 → 75.684 MB/s，G0 −2.669%）与 A3（rand 外推 3,151,346.5 → 154.22 MB/s）构成内容包络，P2 必须按 A1/A2/A3 + 双 gate 判定，内容跨界时 headline = `not_proven`。

## 3. P1：`T10.ss-steady-anchor`（已 round0 PASS）

### 3.1 唯一可观察结果

一份**可复现的测量包**：同一冻结 RTL/TB（b11 几何）下，2 帧控制逐值复现冻结统计，4 帧扩展给出每帧事件时间戳，分离 `L_cold` 与 `S_ss`，并回答 Q1（含 `startup_pct`）；同时给出 `C_ss`、fps、两 gate 的算术 margin 与所需时钟（判定归 P2）。

不回答：双 gate 的最终 verdict、DDR sustained、UART/PCIe 生产路径、双核可行性、板级行为。

### 3.2 允许写范围与输入

- 只写：`.../T10.ss-steady-anchor/**`；临时 work 库/日志/INI 副本只写 `%TEMP%\opencode\ss-anchor\`。
- 只读：`input-index.md` §1/§2 全部输入；b11/b6/P2 目录、`fpga/csi2/src/**`（只复制，不修改）。
- 禁止：改 DUT 源、改 b11/b6/P2 目录/候选/报告/统计、TD/综合/布线/bitgen/CWC/下载/Flash/COM/JTAG/板卡/RK、改 `workflow/tasks.json`、`docs/**`、`work/**`。

### 3.3 五项语义步骤

1. **冻结副本与 G0**：建 `src/`，复制 §1 的 9+2 DUT 源、`p2_paxi_model_b11.v`、`a1_ddr_model.v`、参照 `tb_b11_full.v`；逐文件记 path/bytes/SHA，与 b11 manifest 比对（0 mismatch 才继续）；复制 `modelsim.ini` 到独占临时目录。写 `input-verified.json`。
2. **写派生 TB 与 DIFF**：按设计指南 §3.2 白名单写 `src/tb_ss_anchor.v`（`FRAMES`、`SS_EVT`、slot-free pacing、per-frame watchdog、`MAX_CYCLES=30M`、路径寄存器 `[4095:0]`、统计行追加 `frames/ss_pass`）；写 `src/DIFF.md` 逐条列 diff 与“对 DUT 无影响”论证。
3. **跑 2 帧控制**：`sim/run_ss.py compile` + `control2`（`-gFRAMES=2`，独占 work 库，`vsim` 硬超时 2700 s）。**逐值门槛**：`cycles=11445988`、`cap=2 enc=2 exported=2 read=259200`、`exp_bytes=80068`、`cap_bytes=80156`、`raw_drop=0 cmp_drop=0 wd=0`。任一不符 → 停止，报 `control_mismatch` + 精确 diff；可做 **1 次**有新证据的修正重试，不得跳过控制直接跑 4 帧。
4. **跑 4 帧稳态**：`run4`（`-gFRAMES=4`，硬超时 2700 s）；第 3/4 帧按 §2.5 slot-free pacing；命中 `SS_STALL`/`MAX_CYCLES`/超时则保留已完成帧事件并标 `partial`。解析 `SS_EVT` → `out/events-4frame.csv`，按 §2.2/§2.3 生成 `out/steady-state.json` 与 `out/steady-state.md`（含 Q1 结论、`startup_pct`、band、**逐帧 `export_tail` 与 `sink_limited`**、条件式 `C_excl_export`、V1–V6、失败项、边界声明）。
5. **自检与冻结**：跑解析负对照（`S_avg2` 当 `S_ss`、`L_cold` 当 `S_ss`、3 帧当 4 帧 → 必须拒绝）；写 `result-r0.md`/`lessons.md`；停止修改、确认 `active_commands=0`，冻结 `manifest-r0.json`（覆盖 src/sim/out/logs/工具/命令/输入 SHA）。

### 3.4 交付物

```text
T10.ss-steady-anchor/r0/
  input-verified.json
  src/{9 changed-src, 2 repo_deps, p2_paxi_model_b11.v, a1_ddr_model.v, tb_b11_full.v(ref，可放 src/ref/), tb_ss_anchor.v}
  src/DIFF.md
  sim/run_ss.py, sim/modelsim.ini, sim/logs/*.log, sim/caps/{ss2,ss4}.{stats,dec}
  out/events-4frame.csv, out/steady-state.json, out/steady-state.md
  result-r0.md, lessons.md, manifest-r0.json
```

### 3.5 验收门槛

| 维度 | 检查 | 门槛/证据 |
|---|---|---|
| functional | 2 帧控制 | `cycles=11445988`、`cap_bytes=80156`、`exp_bytes=80068`、`read=259200`、`cap=2/enc=2/exported=2`、`raw_drop=0/cmp_drop=0/wd=0`，**逐值相等** |
| functional | 4 帧完整 | `cap=4 enc=4 exported=4 read=518400`；`raw_drop=cmp_drop=dup=geom=err=wd=0`；`t_exp` 严格递增；事件齐全（V1/V6） |
| functional | 稳态与延迟分离 | `L_cold`、`L_frame`、`S_2`、`S_23`、`S_34`、`S_ss`、`startup`、`startup_pct` 全部给出；`S_ss=(S_23+S_34)/2`；V3 一致（≤2%）或标 `unstable` |
| functional | 容量算术 | `C=4.86e8/S_ss`、`fps=1.875e8/S_ss`、`margin_0`、`margin_25`、`f_req_0=30S`、`f_req_25=37.5S`；逐帧 `export_tail` 与 `sink_limited`；`C_excl_export` 仅在 sink_limited 时给并标乐观界；至少 3 项可手算复核（含 `S=5.0M→97.2 MB/s`、`S=6.25M→77.76 MB/s`） |
| functional | 解析负对照 | 3 个负 fixture 全部被 `run_ss.py` 的解析器拒绝，并给出固定 reason |
| engineering | 副本/白名单 | 14 个复制件 SHA=0 mismatch（13 项编译清单 + 1 参照 TB）；DUT 0 修改；TB diff 只含 §3.2 白名单 1–8；白名单外 0 功能项 |
| engineering | 可复现/独占 | 命令 argv/cwd/exit/耗时/timeout 全记录；work 库/INI/日志独占；2 帧控制确定性；无 TD/硬件；写范围外 0 文件 |
| engineering | manifest | 覆盖 src/sim/out/logs/输入/工具/命令；`stopped_modifying=true, active_commands=0` |
| system | 测量边界 | 明确：sim-only sink（18.75 MB/s = clk_uart/10）、行为 DDR（AR_GAP/R_GAP，非争用）、单一内容、单一几何、per-stream；不声称 DDR sustained/真实 UART/PCIe/板级 |
| system | 结论边界 | 只回答 Q1 与算术；不给双 gate 最终 verdict（归 P2）；`partial/unstable` 时不得给单一 `S_ss` |
| G 层 | G0/G1 | 副本/输入 SHA 0 mismatch；2 帧逐值复现 + 4 帧可复算；G2–G4 `not_applicable`（无综合/布线/bit/板） |

**不适用理由**：P1 是 RTL 行为仿真测量，不是 TD 构建、不是 bit/CWC、不是板测；G2 需要同一候选的综合/布线（本 run 0 次），G3/G4 无 bit/板卡。仿真 PASS 不证明时序、资源或上板行为。

### 3.6 工具、预算、停止

- 工具：ModelSim ASE 10.5b（`D:\intelFPGA\18.1\modelsim_ase\win32aloem`）、Python 3.11；无网络；无 TD/硬件。
- 预算（冻结）：开发 ≤40 calls / ≤120 min；全尺寸 `vsim` ≤3 次（control2 + run4 + 至多 1 次有据重试），单次硬超时 2700 s，总仿真墙钟 ≤100 min；`vlog` 1200 s；Python 120 s；读/搜 60 s。
- 停止/blocked：控制不一致且 1 次修正后仍不一致；4 帧超时/`SS_STALL` 且不足 2 个稳态间隔（含并发 TD/板卡/他人仿真造成的超时；只杀自己进程、不延长）；副本 SHA mismatch；TB 需要白名单外改动；ModelSim 不可用 → 返回 `partial`/`blocked`，给已完成帧、日志、缺失项与恢复入口。**不得**用 2 帧或 3 帧结果冒充 4 帧稳态。
- 回退：只写本任务目录；回退 = 不采用该目录，保留失败日志；不删除、不改 b11/b6/P2/生产。

### 3.7 P1 实际结果（2026-10-26，round0 PASS；P2 唯一输入）

- 判定：functional / engineering / system 全 PASS；G0/G1 pass，G2–G4 `not_applicable`；`blocked=null`、`retest` 空；**0 实际修复轮**。
- 冻结 manifest：`.../T10.ss-steady-anchor/r0/manifest-r0.json`，SHA256 `39f3e3d6d115afbdcda9753b254f6971a10eb75df88d5718eb9ea5a247199f9a`（41 artifacts；`stopped_modifying=true, active_commands=0`；forbidden_actions 全 0）。
- 独立报告：`.../test-reports/T10.ss-steady-anchor-r0-integrated.md`（同一测试者覆盖三维；独立重跑 2 帧控制 16/16 逐值且 stats/evt/dec 逐字节相同；4 帧自写解析器 `json_diffs=[]`）。
- 关键产物 SHA（P2 必须绑定）：`out/steady-state.json` `a0945e1f60d9…`（6,779 B）、`sim/caps/ss4.stats` `29bd31851804…`、`sim/logs/run4.log` `dc215e0b46e4…`、`src/tb_ss_anchor.v` `ddd9e02ca71a…`；输入 b11 manifest `4425fdcf…961a`、P2 manifest `5ed90500…36a6`、`tasks.json` `fd820546…5d23` 均无漂移。
- 实测（均 measured，除注明外）：`L_cold=6,766,434`、`L_frame=6,766,393`、`S_2=S_23=S_34=4,677,535`、`S_ss=4,677,535`（band 0.00%）、`S_avg2=5,721,984.5`、`startup_pct=44.66%`、`C_ss=103.9009 MB/s`、`fps=40.0852`、`margin_0=+33.6174%`、`margin_25=+6.8939%`、`f_req_0=140.326 MHz`、`f_req_25=175.408 MHz`、`export_tail=480,930×4`、`sink_limited=false`、`C_excl_export=C_ss`；counters `cap=4 enc=4 exported=4 read=518400 raw_drop=cmp_drop=dup=geom=err=wd=0 exp_bytes=160136 cap_bytes=160312 cycles=20801058`；V1–V6 全 true。
- 预算实际：2 次全尺寸 vsim（control2 426.1 s + run4 661.3 s = 1087.4 s），vlog 0.6 s；均 ≤ 冻结上限（2700 s/次、100 min 总墙钟）。
- P1 观察项及 P2 处置：O1 manifest `commands[].started` 实际是完成时刻（文档语义，不影响数据）；O2 ModelSim 版本标签措辞（`ALTERA STARTER EDITION 10.5b`）；O3 “13 编译副本”措辞（实为 14 复制/13 编译）；**O4 `L_cold` 比规划上界高 16,434 cycles（0.24%）**，开发/测试已给原因（导出/几何/内容与 b6 不同），P2 用 A4 时须保留该差异说明；O5 `ss_pass` 非侵入加强；O6 开发 selfcheck 的 `validate_claim` 较宽松、测试者已补严格检查；**O7 `export_tail=480,930` 比理想 400,340 高 80,590 cycles 且四帧恒定**，`sink_limited=false`，P2 不得无条件扣减；O8 事件采样可能有 ±1 cycle 偏移、帧间隔精确。
- **使用限制（P2 必须遵守）**：A1 是**单内容（smooth smp 梯度）/单几何（b11 1920×1080）/sim-only 18.75 MB/s sink/行为 DDR/per-stream** 的链级锚点；**不得**把 `40.085 fps`、`+6.89%` 直接外推自然图像/低照/噪声或双路 1080p30。P2 必须用 A1/A2/A3 内容包络 + 双 gate；内容跨界时 headline=`not_proven`。

## 4. P2：`T10.ss-verdict-r1`（round0 PASS）

### 4.1 唯一可观察结果

一份**可执行、可复现、带 6 个负对照**的修正判定：`G0`（nominal 0%）与 `G25`（≥1.25×）分列的 1080p/双路矩阵（c1s1/c1s2/c2s1/c2s2 × A1/A2/A3），内容锚点标签，1080p 三档 overhead，DDR 1333/1600 双列，UART 边界，双核 per-stream/共享 PAXI 边界，P2 口径/算术错误表（C1–C9），以及修正后的 verdict（允许 `conditional`/`not_proven`）。

### 4.2 依赖与允许写范围

- 依赖：P1 综合测试 **PASS（已满足）**，且 `T10.ss-steady-anchor/r0/manifest-r0.json`（SHA256 `39f3e3d6d115afbdcda9753b254f6971a10eb75df88d5718eb9ea5a247199f9a`）与 `out/steady-state.json`（SHA256 `a0945e1f60d9…`）冻结；SHA 必须记录在 P2 的 `input-verified.json` 并在冻结前复算。
- 只读：P1 产物（**不得修改**）、P2 原冻结件（报告/模型/规则/CSV/manifest）、`input-index.md`、`fpga-design-guide.md`、DOC-1/DOC-2。
- 只写：`.../T10.ss-verdict-r1/**`（P2 原目录只读，模型复制后改副本）。
- 禁止：TD/RTL/板卡/RK、改 P1/P2 原件、改 `workflow/tasks.json`、放宽门槛。

### 4.3 五项语义步骤

1. **冻结输入**：`input-verified.json` + `inputs/frozen-inputs.json`；断言 P1 manifest `39f3e3d6…9f9a`、P1 `steady-state.json` `a0945e1f…`、A1=`4,677,535`、`C_ss=103.9009`、`margin_0=+33.6174%`、`margin_25=+6.8939%`、`export_tail=480,930`、`sink_limited=false`、P2 manifest `5ed90500…36a6`、comp/rand 数值、77.76/97.20、5,332/6,400、11,520 B/s、A2/A3 值；每项带 `measured/derived/assumed/unproven` 标签；P1 目录任何文件改动 → 立即 blocked。
2. **实现模型（双模式）**：复制 P2 `calc.py`/`rules.json` 为 `legacy`（原规则，用于回归复现）与 `corrected`（两 gate、A1–A4、1080p tier 平移、5,332、UART 边界、双核 per-stream/PAXI）；纯函数、无硬编码答案；`test_calc.py` 覆盖已知值/边界/6 负对照。
3. **生成表格**：`scenarios.csv`（43 行 × 两 gate + `chain_anchor_id/content_label/claim_status`）、`content-anchors.csv`、`gate-matrix.csv`、`overhead-sensitivity.csv`（43×3，1080p 用档位差）、`ddr-budget.csv`（5333/6400 双列）、`corrections.csv`（C1–C9）。
4. **写 verdict**：`verdict-r1.md` 按 Q1–Q7 组织；先给“对 P2 的修正摘要”（撤回/保留哪些结论、影响的百分点），再给 gate 矩阵与推荐；headline 必须三段式（G0/G25/content），并按设计指南 §4.1 的 claim 级组合规则给 `infeasible`/`not_proven`/`conditional`/`feasible`（内容跨界时必须是 `not_proven`，不得用单一词覆盖）；给 band/knife-edge、`not_proven` 边界与“什么会改变结论”。
5. **检查与冻结**：用 `legacy` 复现旧 `scenarios.csv` 43 行（0 mismatch，≤1e-6）；跑 6 负对照；`check_outputs.py` 校验 CSV↔报告/前沿极大性/推荐唯一性；写 `result-r0.md`/`lessons.md`；冻结 manifest。

### 4.4 交付物

见设计指南 §6.3（`input-verified.json`、`inputs/frozen-inputs.json`、`model/*`、`out/{scenarios,content-anchors,gate-matrix,overhead-sensitivity,ddr-budget,corrections}.csv`、`verdict-r1.md`、`result-r0.md`、`lessons.md`、`manifest-r0.json`）。

### 4.5 验收门槛

| 维度 | 检查 | 门槛/证据 |
|---|---|---|
| functional | 旧判定回归 | `legacy` 重算 43 行与 P2 `scenarios.csv` 逐行一致（计数/verdict/gate，≤1e-6）；证明修正来自规则而非算术错误 |
| functional | 两 gate | 每行同时有 `gate_G0`/`gate_G25`/`margin_chain_pct`；1080p30 的 `G0` 与 `G25` 分列；`below_25` 不得写 `infeasible` |
| functional | headline 组合 | 按指南 §4.1 的 claim 级规则给 1080p30 系统结论；A1/A2 内容跨界时必须 `not_proven`，且 A1/A2 两个 margin 都列出 |
| functional | 内容锚点 | A1（measured）/A2（assumed，且披露与 A4 循环依赖）/A3（assumed）/A4（仅延迟参照）齐全；`claim_status=not_proven_all_content` 存在 |
| functional | 外推限制 | 1080p30 结论必须带内容范围；**不得**把 A1 的 `40.085 fps`/`+6.89%` 写成自然图像或双路可行；A1/A2 跨界必须 `not_proven`；双核不得 `feasible`；`export_tail=480,930` 与 `sink_limited=false` 必须原样使用 |
| functional | 1080p 三档 | `tier=0 → S_ss−426,385`、`426,385 → S_ss`、`1,000,000 → S_ss+573,615`；三档 margin/verdict 均给；不得 `applies=false` |
| functional | DDR | 5,332 与 6,400 两列；`required_eff` 15.173%/12.641%、`gate_eff` 18.966%/15.801%；`DDR_total=809.034`；DOC-1 差异单列 |
| functional | UART | 11,520 B/s；40,032 B → 3.475 s（104.2× 帧周期）、2,594,706 B → 225.235 s（6,757×）；导出成本 400,320 cycles 与逐帧 `export_tail`/`sink_limited` 单列；`transport=not_proven`；不得把 sim sink 当生产 |
| functional | 双核 | `c2s2 = C`（非 2C）；`paaxi_shared_unproven=true`；资源 231/289、时序 unproven；双核 headline 最高 `not_proven`/`conditional`，永不 `feasible` |
| functional | 错误表/推荐 | `corrections.csv` ≥9 条（C1–C9）每条有原值/修正值/影响/证据；主推荐唯一、备选 ≤2、与比较对象同内容基（A1 的 1080p 过 G25 不得单独压过 comp 基的其它档）；1080p30 若仅 G0 过则单列 nominal-only |
| engineering | 模型质量 | 纯函数、无随机/网络；6 负对照全拒；CSV↔报告逐项一致；命令/exit/日志齐全 |
| engineering | 写范围/manifest | 只写本任务目录；P1/P2 原件 0 修改；manifest 覆盖输入/代码/规则/输出/测试/报告；`stopped_modifying=true, active_commands=0` |
| system | 合同一致 | 20 B/32 B、8 MiB、44 B、共享 256-bit PAXI、187.5 MHz；per-stream 非 aggregate；steady-state 非 cold latency、非 core-only |
| system | 声明边界 | 无 RK/PCIe/板级/实测 DDR 声明；内容/双核时序/PAXI 仲裁/DDR sustained 标 `unproven`；离线 PASS ≠ 生产/板级 |
| G 层 | G0/G1 | 输入冻结 + 模型/CSV/报告可复现；G2–G4 `not_applicable` |

### 4.6 冻结核对值（供开发自检/测试者独立手算；不预设 verdict）

| 项 | 值 | 公式/说明 |
|---|---:|---|
| A1 链级 cycles/frame | **4,677,535** | P1 r0 measured（`S_2=S_23=S_34`，band 0.00%） |
| A1 `C_ss` / `fps` | **103.9009 MB/s / 40.0852** | `4.86e8/S`、`1.875e8/S` |
| A1 `margin_0` / `margin_25` | **+33.6174% / +6.8939%** | 仅单内容梯度锚点的算术 |
| A1 `f_req_0` / `f_req_25` | 140.326 / **175.408 MHz** | 25% 所需时钟 < 已验证 187.5 MHz |
| A2（comp 外推） | 6,421,414；75.6843 MB/s；29.1992 fps；−2.6694% / −22.1355% | `2.312897 c/B × 2,592,000 + 426,385`；assumed；与 A4 同值（循环） |
| A3（rand 外推） | 3,151,346.5；154.2202 MB/s；59.4980 fps；+98.328% / +58.662% | `1.051297 c/B` 外推；assumed |
| 1080p tier 0 | 4,251,150（= S−426,385）；114.3218 MB/s；+47.019% / **+17.615%** | 档位差平移；assumed delta |
| 1080p tier 1,000,000 | 5,251,150（= S+573,615）；92.5512 MB/s；+19.022% / **−4.783%** | 25% 在保守档跌破 → 1080p 非三档稳健 |
| c1s2 per-stream（A1/A2/A3） | 51.9504 / 37.8421 / 77.1101 MB/s | `C/2`；margin_0 −33.191 / −51.335 / −0.836% |
| 25% 最大 1080p fps（A1/A2） | 32.068 / 23.359 | `1.875e8/(1.25·S)` |
| 两帧平均（对照） | 84.92 MB/s / 32.76 fps | 含冷启动；**不是** `S_ss`，不得作 gate |
| `export_tail` / 理想串行 | 480,930 / 400,340（+80,590） | 四帧恒定；`sink_limited=false`；`C_excl_export=C_ss` |
| DDR 主路径 / gate | 809.034 / 1,011.2925 MB/s | 双路 1080p30、20 B/32 B、含 CMP |
| required_eff @1333 / @1600 | 15.1732% / 12.6412% | `/5,332` / `/6,400` |
| gate_eff @1333 / @1600 | 18.9665% / 15.8014% | |
| UART 40,032 B | 3.475 s @11,520 B/s；2.135 ms @b11 sink；0.400 ms @b6 sink | 与真实 115200 差 1,628× / 8,688× |

### 4.7 C1–C9 冻结修正表（P2 必须逐条产出 `corrections.csv`）

| id | P2 原口径/原值 | 修正后 | 影响 |
|---|---|---|---|
| C1 冷延迟当吞吐 | 链级 6,421,414 → 75.6843 MB/s / 29.199 fps / −2.669% | A1 `S_ss=4,677,535` → 103.9009 MB/s / 40.0852 fps / +33.617% | −2.669% → +33.617%（G0）；−22.136% → +6.894%（G25） |
| C2 0%/25% 合判 | R2：链级 margin<0 → `infeasible`，25% 并入同一 verdict | 两 gate 分列；`below_25` 不得写 `infeasible` | 1080p30 A1 过双 gate；A2 双失；headline 由内容跨界决定 |
| C3 DDR 峰值 | 6,400 MB/s；required_eff 12.6412% | 1333 主线 5,332 MB/s；15.1732%；保留 6,400 回退列（12.6412%） | gate_eff 18.9665%；平均仍非瓶颈 |
| C4 1080p tier | `applies=false`（1080p 固定锚点，三档同值） | `S_ss+(tier−426,385)`：tier0 +17.615%、primary +6.894%、1e6 −4.783% | 25% 仅在 0/primary 档过，非三档稳健 |
| C5 UART/fast sink | 链级锚点含“UART 导出”，未限定生产路径 | sim sink 18.75 MB/s；115200=11,520 B/s（104.2×/6,757× 帧周期）；`export_tail=480,930` 恒定、`sink_limited=false`；`transport=not_proven` | 不得用 fast-sink 数字暗示 UART 可实时；不得无条件扣 400,320 |
| C6 overhead 循环 | 426,385 = 6,421,414 − 5,995,029.375；A2≡A4 | A2 标 assumed，披露与 A4 同值；overhead 仅作档位差 | 不得把 A2 当独立实测证据 |
| C7 双核 per-stream | 表内 c2s2=C 但结论易被 2C 聚合误读 | `c2s2=C`；`paaxi_shared_unproven=true`；`dual_core_capacity=assumed_from_single_core`；2C 仅用于 DDR/总量 | 双核 headline 最高 `not_proven`/`conditional`，永不 `feasible` |
| C8 内容锚点 | comp strip（153,600 B/1920×64）被当 1080p 核级锚点 | A1（grad，单内容）/A2（comp 外推，保守）/A3（rand 外推，乐观）内容包络；`claim_status=not_proven_all_content` | 自然图像/低照/噪声未测，不得称“保证” |
| C9 前沿/推荐 | 1080p30 `fails_30`；25% 最大 fps 23.36；f_req 240.803 MHz；主推荐 1600×900 | A1：25% 最大 32.068 fps、f_req 175.408 MHz；A2：23.359 fps/240.803 MHz；主推荐仍按内容基一致规则（A1 不得单独压过 comp 基档） | 1080p30 单列为 “measured-content 双 gate 过 / not_proven all content”；1600×900 仍为主推荐候选 |

> 本表是**核对基准**，不是最终结论；开发必须由模型复算，测试者独立手算至少 6 项。任何与表冲突的结果先查公式/单位，不得改门槛迎合。

### 4.8 工具、预算、停止

- 工具：Python 3.11；无 TD/ModelSim/板卡。
- 预算：开发 ≤35 calls / ≤60 min；测试 ≤30 calls / ≤45 min。
- 停止/blocked：P1 manifest/`steady-state.json` 哈希不符或被修改；旧 43 行回归不能 0 mismatch（说明有未披露的算术改动）；需要 TD/板测才能回答；门槛需要放宽 → `blocked`，不猜数、不单选有利锚点。
- 回退：只写本任务目录；失败证据保留；不改 P1/P2/生产；不删除。

### 4.9 P2 实际结果（2026-10-26，round0 PASS；本轮收尾输入）

- 判定：functional/engineering/system 全 PASS；G0/G1 pass，G2–G4 `not_applicable`；`blocked=null`、`retest` 空；**0 实际修复轮**。
- 冻结 manifest：`.../T10.ss-verdict-r1/r0/manifest-r0.json`，SHA256 `fd27c70f304f51ba0b0b022398acd46f1f5f43a32351acfc472dea12e034fad0`（34 artifacts，502,678 B；`stopped_modifying=true`、`active_commands=0`；forbidden_actions 全 0）。
- 独立报告：`.../test-reports/T10.ss-verdict-r1-r0-integrated.md`；测试者独立手算 63 项、legacy 独立 replay（43 行 byte-identical、129 行 0 mismatch）、6 负对照全拒、85/249/86/28 checks 0 失败。
- headline：`not_proven`（A1.G0=pass、A2.G0=fail 内容跨界）；A1 `103.9009 MB/s / +33.6174% / +6.8939%`；A2 `75.6843 / −2.6694% / −22.1355%`；A3 `154.2198 / +98.3279% / +58.6623%`；A4 仅冷延迟参照。
- gate 矩阵 24 行（c1s1/c1s2/c2s1/c2s2 × A1/A2/A3 × G0/G25）；行级 A1 c1s1=`feasible`（claim 仍 `not_proven_all_content`）、c1s2=`infeasible`、c2s1/c2s2=`conditional`；**无 cores=2 feasible**。
- 1080p tier：tier0 `4,251,150`（G25 +17.6152%）、primary `4,677,535`（+6.8939%）、1e6 `5,251,150`（**−4.7828%**）→ 非三档稳健；`Δ_req=−322,465`，保守档需再降 ≥251,150 cycles 或 ≥196.918 MHz。
- DDR：5,332/6,400 双列；required_eff 15.1732%/12.6412%、gate_eff 18.9665%/15.8014%；DOC-1 §8 差异单列不采用。
- UART：11,520 B/s（3.475 s/104.25×；225.235 s/6,757×）；sim sink 18.75 MB/s（1,628×）；`export_tail=480,930` 恒定、`sink_limited=false`、`transport=not_proven`。
- 双核：`c2s2=C`、`assumed_from_single_core`、`paaxi_shared_unproven`；资源 231/289；Routed unproven；2C 聚合 207.8018 仅 DDR/总量。
- 推荐：主 `1600×900@30 c1s1`（primary G25 +36.1774%、三档最差 nominal +21.0486% → primary feasible/conservative conditional；f_req 137.688/172.110 MHz）；备选 `1440×810@30 c1s1`（三档最差 +42.9485%）、`960×540@30 c1s2`（+25.0622%）；1080p30 单列 measured-content only，不作推荐。
- 43 行计数：feasible 12 / conditional 25 / infeasible 6；旧 P2 43 行/129 行 byte-identical 回归通过（修正只来自规则/口径/输入）。
- 非阻断观察：OBS-1（`corrections.csv` C4 叙述字段 +17.6154/−4.7827 vs 权威 +17.6152/−4.7828，舍入笔误）、OBS-2（报告 §9 表列错位）、OBS-3（manifest 日志自指 219 B）、OBS-4（A4 展示列）、OBS-5（frontier 措辞 nominal margin）、OBS-6（A3 继承 rand cpb 6 位小数，3.375 cycles）；均不影响 gate/推荐/headline。若修订 OBS-1/OBS-2，需重冻结 P2 manifest 并复测相关一致性。
- 预算实际：开发约 58 次 calls（冻结 ≤35；planner 信息约 62），测试约 50 次（冻结 ≤30）；未改范围/门槛/产物、0 TD/板卡；测试者记为流程偏差，不作技术 FAIL。
- 收尾：`handoff.md`/`final-summary.md`/`user-summary.md` 已写；P1/P2 冻结件未改；T10 不置 done。

## 5. 公共执行、证据与预算

### 5.1 工作树与隔离

- 实际工作树 `D:/fpga/ph1p100`，不切 worktree；不合并其他聊天成果。
- 每任务独立目录、独立 manifest、独立命令日志；ModelSim work 库/INI/日志独占；不共享盘符映射。
- 工作树既有 dirty（`.agents/skills/*`、`AGENTS.md`、`docs/TD命令行使用说明.md`、`tools/td/*` 等）非本 run 产生；本 run 不提交、不改、不清理。
- b11/b6/P2/T08/T10 目录只读；若任务期间被外部修改，记录快照 SHA，不追逐、不覆盖。
- 不修改 `workflow/tasks.json`；离线包完成不把 T10 置 done。

### 5.2 预算汇总

| 任务 | 开发 | 测试 | 全尺寸 vsim | TD/板卡 |
|---|---|---|---|---|
| P1（done） | ≤40 calls / 120 min | ≤35 calls / 60 min | 开发 ≤3；测试 1（2 帧控制） | 0 |
| P2（done） | ≤35 calls / 60 min | ≤30 calls / 45 min | 0 | 0 |
| P3（done） | r0 ≤45 calls / 120 min；r1 补充 ≤15 calls / 60 min | r0 ≤35 / 60；r1 复测 ≤10 calls / 30 min | 实际 5 次全尺寸（R0–R3 + r3_frozen）；r1 1 次短 v1 | 0 |
| P4（done） | ≤45 calls / 120 min | ≤35 calls / 60 min | 实际 4 次全尺寸（940.4/1,087.5/1,383.6/1,330.0 s）；tester 1 次控制（1,234 s） | 0 |

- P1 实际：2 次 vsim（426.1 + 661.3 = **1087.4 s**），vlog 0.6 s；测试者 1 次控制 410.8 s；均在冻结预算内。
- P2 实际：无 vsim/TD/板卡；**开发约 58 calls（超 35）、测试约 50 calls（超 30）**；未改范围/门槛/产物，测试者记为流程偏差（DEV/TEST-BUDGET-OVERRUN），不作技术 FAIL。
- P3 实际：r0 4 次全尺寸（937.6/1056.1/1111.9/1316.5 s）+ v1 3 次；r1 `r3_frozen` 1326.1 s + 短 v1；全尺寸 **5/5**，vsim 墙钟 **6532.4 s = 108.9 min ≤112**（round1 override）；tester 1 次全尺寸 R0（881.5 s）；**实际修复 2 轮**（r1 metadata、r2 PASS）。
- P4 实际：4 次全尺寸 4,741.5 s = **79.0 min ≤120**；单次最长 1,383.6 s；**0 重试**；tester 1 次 R4 控制 1,234 s；**测试者约 45 calls（超 35）/ 墙钟 55 min（在 60 min 内）**，已披露；本轮无 FAIL。

- 读/搜 60 s；Python 120 s；`vlog` 1200 s；`vsim` 2700 s/次；P1–P3 已用 108.9 min ≤112；P4 另计 ≤120 min（不合并）。
- 同失败命令最多首次 +1 次有新证据/参数纠正的重试；单问题 ≤3 轮搜索/读取；连续 2 次无进展主动停止。
- 禁止 shell 循环绕调用/重试/仿真次数；禁止批量删除；失败日志保留。

### 5.3 返回合同（只给元数据）

- 开发：`task_ids、status、artifact_paths、manifest_path、test_input_paths、lessons_path、blocked、retest`。
- 综合测试：`task_id、dimension=integrated、dimension_results、verdict、report_path、manifest_path、blocked、retest`。
- 详细命令/未测/边界写 `result-r0.md`/`lessons.md`/报告，不粘长源码/长报告。

### 5.4 综合测试

- 每任务一个**新**综合测试者，独立于开发；P1、P2 各一个，不跨任务复用。
- 只写 `test-reports/<task_id>/**` 与 `<task_id>-r<round>-integrated.md`；不改候选/生产/其他 run。
- 报告首行唯一 `### 判定：PASS` 或 `### 判定：FAIL`；三维 + G 层；独立复现/负对照；输入漂移检查；未测项/回退。
- round0 首次验收；同任务真实 FAIL 续原开发/原测试，最多 3 轮实际修复；缺工具/设备/资料/授权直接 blocked，不空转。

### 5.5 PASS/FAIL 边界

- P1 PASS 只证明“在该冻结 RTL/TB/几何/内容、sim-only sink（18.75 MB/s）、行为 DDR 下，`L_cold=6,766,434`、`S_ss=4,677,535` 被正确测量”；`C_ss=103.9009` 是**单内容梯度锚点**的算术，不外推自然图像/双路，不证明 25% 设计裕量、DDR sustained、真实 UART/PCIe、双核、板级。
- P2 PASS 只证明“模型/表格/报告在冻结输入与冻结规则上自洽，且两 gate 未被塌缩、内容包络与 `not_proven` 边界被保留”；不证明 RTL 时序、资源、板级。
- `conditional` 不是 PASS 的子集；`not_proven` 不得被 `G0`/`G25` 覆盖。

## 6. 主要风险与控制

| 风险 | 影响 | 控制 |
|---|---|---|
| 把 6.421M 冷延迟当稳态 | A1 的 `+33.62%/+6.89%` 会被写成 `−2.67%/−22.14%`，verdict 反向 | P1 已实测分离（`startup_pct=44.66%`）；P2 禁止 `COLD_LATENCY_AS_THROUGHPUT` |
| 把 A1 单内容 40.085 fps 外推双路/自然图像 | 越界声称系统可行 | 指南 §4.1 headline 规则 + `claim_status=not_proven_all_content` + 双核最高 `not_proven`；测试者必查 |
| 4 帧 slot 溢出/丢帧 | 4 帧结果无效或只有 2–3 帧 | slot-free pacing + `raw_drop=0` 门槛 + `MAX_CYCLES`/watchdog；失败按 partial |
| 相机/槽等待成为限速方 | `S_ss` 被高估（容量被低估） | V4 `t_pub(k+1)<t_exp(k)` + `capacity_is_lower_bound` 标记 |
| 25% 落在 knife-edge | 单个 interval 差异改变 verdict | P1 实测 band `[4,677,535, 4,677,535]`（0.00%），**已排除**；若后续输入/几何变化导致跨界，仍按指南报两侧 margin、不选有利侧 |
| 内容只覆盖平滑图案 | 自然图像/噪声未证 | A2 保守假设 + `claim_status=not_proven_all_content`；不称“保证” |
| A2 与 A4 数值相同被当独立证据 | 循环论证 | 指南 §4.2 强制披露；P2 报告单列 |
| DDR 用 6,400 或文档 2.33 GB/s | required_eff 偏乐观/不可复现 | 显式公式 5,332；DOC-1 差异单列；负对照 `PEAK_MISMATCH` |
| UART fast sink 被当生产 | 声称不存在的端到端吞吐 | §4.5：115200 比 sim sink 慢 1,628×/8,688×，比帧周期慢 104×/6,757×；导出成本 400,320 cycles 单列；`transport=not_proven` |
| 双核用 aggregate 2C | 双路误判可行 | `c2s2=C`；`paaxi_shared_unproven`；负对照 |
| 4 帧超预算 | 无稳态结论 | 单次 2700 s 硬超时；总墙钟 100 min；超时 partial/blocked |
| 并发 TD/板卡/他人仿真拉长墙钟 | 4 帧被超时杀掉，得 partial | 独占 work 库；只杀自己进程；2700 s 即停并保留已完成帧；不延长/不重试/不抢 TD |

## 7. 后续主题（本轮不做，最多 3 条）

> 本轮已收口（P3 r2 PASS）；最终 5 项剩余主题见 §10.11 与 `final-summary.md` §7。以下为 P2-era 历史主题，保留不删。

1. **全帧最坏内容锚点**：自然图像/低照/噪声或全帧 incompressible 的 1080p 链级稳态锚点；需要真实图集或更长的多帧仿真；当前 A2 只是 strip 外推。
2. **每帧固定开销削减/尾延迟隐藏**：主档 `Δ_req = 4,677,535 − 5,000,000 = −322,465 < 0` → 25% 在主档已过；但 tier `1,000,000` 下 cycles `=5,251,150`、margin `−4.78%`，要三档稳健需再降 **≥251,150 cycles** 固定开销（或把时钟提到 196.9 MHz 以上）。可评估 slot 提前释放、导出与编码解耦、3 槽、帧边界流水化；属 RTL 优化 + 新仿真/综合包。
3. **共享 PAXI 双核仲裁与生产传输**：4 客户 256-bit PAXI 仲裁、单 outstanding reader、双核 Routed 时序、PCIe/高速 sink；属 RTL/TD/板级包，需另开 run 与授权。

原需求路径保留：`workflow/runs/20261025-233401_fpga-steady-state-reverdict/request.md`。

## 8. 收尾与恢复（P1–P4 均 PASS；run finished）

- P1 `39f3e3d6…`、P2 `fd27c70f…`、P3 `3C8377A4…`、P4 `d353c61a…`（68 artifacts）均 PASS；P3 实际修复 2 轮、P4 r0 一轮；最终 **`G0_feasible_for_scope` 已收窄**（C1 全帧合成 raw + comp proxy / slot-free / 93.75 MB/s sim sink / 行为 DDR / 单核 187.5 MHz / per-stream）。
- 收尾文件已按最终结论重写：`handoff.md`/`final-summary.md`/`user-summary.md`；`dispatch.json` 置 finished（completed 4、pending 0）。
- 不修改 `workflow/tasks.json`；离线包完成不把 T10 或双路目标置 done；G25 仅参考、不降档。
- 准确恢复入口（供主/用户）：
  `使用 fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261025-233401_fpga-steady-state-reverdict；本轮目标：读取 P4 manifest-r0 与 r0 integrated 报告，确认 G0_feasible_for_scope 的收窄 scope 与剩余风险；不重跑、不改 P1/P2/P3/P4 冻结件。`
- 下一主题（新 run）：真实自然/最坏内容 4 帧 + 生产 slot-free/sink + 双核共享 PAXI + 板级/真实 DDR/RK；文本见 `handoff.md` §6 与 `final-summary.md` §8。

## 9. 状态汇总

| 包 | 状态 | 原因/下一步 |
|---|---|---|
| `T10.ss-steady-anchor` | **done（round0 PASS）** | manifest `39f3e3d6…9f9a`；A1=`4,677,535`、`C=103.9009 MB/s` |
| `T10.ss-verdict-r1` | **done（round0 PASS）** | manifest `fd27c70f…fad0`；`not_proven` |
| `T10.ss-g0-closure` | **done（r2 PASS；2 修复轮）** | manifest-r2 `3C8377A4…`；comp proxy G0 +5.427% |
| `T10.ss-4run-matrix` | **done（r0 PASS；1 轮）** | manifest-r0 `d353c61a…`；R1 +33.605%、R2 −3.092%、R3 `G0_not_proven`、R4 +5.427% |
| 当前主要目标 | **completed（离线）** | G0 在 C1 全帧合成 raw + comp proxy / slot-free 范围内收口；自然/全内容/双路/板级未证 |

## 10. P3：`T10.ss-g0-closure`（G0 硬门槛收口；2026-10-26 新边界）

### 10.1 新边界（覆盖旧推荐口径）

- 用户原话：**“25%不是硬门槛，然后我希望还是做1080p30，不然和要求是不一样的”**。
- **G0 是硬门槛**：per-stream 1080p30 ≥ **77.76 MB/s** ↔ `S_ss ≤ 6,250,000 cycles/frame` @187.5 MHz（`6.25M × 30 = 187.5 MHz`）。
- **G25 只作设计参考/风险提示**（97.20 MB/s）：可以列参考列，但**不得进入 headline、不得用于主推降档**；旧 P2 的 1600×900 主推荐口径在 P3 不再作为目标。
- 主目标：**1080p30 G0 收口，不降档**；先量化 G0 差距与可闭合路径。允许的 G0 结论词：`G0_feasible_for_scope` / `G0_not_closed` / `G0_not_proven`；不得用 `infeasible` 代替未测，也不得把 A2 单点当全内容证明。
- P1/P2 冻结件不改；P2 的 `not_proven` 是 P2-era 结论（内容跨界），P3 只回答“G0 能否在给定内容/口径下收口”。

### 10.2 唯一可观察结果

一份 **G0-only** 判定包：A1/A2/A3 + 新 comp-like 代理的全帧 4 帧锚点，c1s1/c1s2/c2s1/c2s2，serial vs tail-overlapped 两种口径；G25 只作参考列；tail 交叠是否可行；2.67% 差距的最小改动菜单；G0 verdict（不降档）。

### 10.3 写范围与输入

- 只写：`.../T10.ss-g0-closure/**`；独占临时目录 `%TEMP%\opencode\ss-g0\`（work 库/INI/日志）。
- 只读：P1 `T10.ss-steady-anchor/r0/{src/tb_ss_anchor.v (ddd9e02c…), sim/run_ss.py (d7417ea1…), out/steady-state.json (a0945e1f…), manifest-r0.json}`；P2 `T10.ss-verdict-r1/r0/{verdict-r1.md (62ec3adc…), model/*, out/*, manifest-r0.json}`；`fpga-design-guide.md`/`input-index.md`。
- comp 向量（只读复制）：`D:/fpga/ph1p100/work/parallel-sim-20261024-2204/codec-throughput/comp/in.hex`（614,400 B 文本 = 153,600 B，SHA256 `edbfdeaedb06824ced20ad76b260979e95e1322d6f6e3bab5e7a951a268f9849`）、`in.meta`（330 B，32×4800 B 块）、`in.xform`（153,600 B）。
- 禁止：改 P1/P2/T08/T10/b11/生产源/`workflow/tasks.json`/`docs`；TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK 全 0；不实现 RTL/时钟改动。

### 10.4 五项语义步骤

1. **G0-only 模型/表**：以 G0 为硬门槛重算 A1/A2/A3 × c1s1/c1s2/c2s1/c2s2；serial/overlapped 两口径；G25 只作参考列。冻结差距算术：`A2 6,421,414 − 6,250,000 = 171,414 cycles/帧（2.6694%；对 core 5,995,029 为 2.859%）`；G0 所需时钟 `6,421,414×30 = 192.642 MHz`（G25 的 240.803 MHz 仅参考）；明确“不降档、不用 G25 主推”的规则与负对照。
2. **派生 TB 与驱动**：从 P1 `tb_ss_anchor.v` 派生 `src/tb_ss_g0.v`，只允许：① `PACING`（0=slot-free/P1，1=strict-serial：下一帧等上一帧 `st_exported` 且槽空闲）；② `CONTENT`（0=smp 梯度，1=comp 向量铺展）；③ `SINK`（0=P1 187.5 MHz，1=fast 2 GHz → 200 MB/s，UART_DIV=1 仍 10 cycles/B）；④ `CAPTURE`（comp-like 关闭逐字节 .dec，仅计数）；⑤ `MAX_CYCLES=48,000,000`；⑥ 向量映射（153,600 B / 32×4800 B 块；**4800 B = 2 ROI 行 × 480 组 × 5 B**，故块 b（2 行）→ 向量块 b mod 32；按 ROI 行/组铺展；必要时按 band 做固定 XOR/旋转以破坏跨带精确重复）；⑦ **字节级自检**：从 `tap_pix` 还原 5 B/4 px 与向量逐字节比对，`SS_VEC_MATCH bad=0` 才允许 comp-like run；⑧ 事件/`SS_PACE`/`SS_STATS` 沿用 P1 协议。DUT 源 0 修改；写 `src/DIFF.md`。
3. **有界 run 矩阵**：R0 控制（gradient/P1 sink/slot-free）必须逐值复现 P1 `t_exp(1)=6,766,454`、`t_exp(2)=11,443,989`、`S_ss=4,677,535`、`exp_bytes=160136`、`cap_bytes=160312`；R1 gradient/fast/slot-free；R2 gradient/fast/strict-serial；R3 comp-like/fast/slot-free（G0 关键）；R4（可选）comp-like/fast/strict-serial（仅当 `R2−R1 > 1%` 或 R3 距 6.25M ≤5% 时）。每次 `vsim` 硬超时 2700 s；最长 5 次；总仿真墙钟 ≤90 min；命中超时/`SS_STALL`/丢帧按 partial。
4. **分析与 G0 判定**：逐 run 算 `S_ss`、`export_tail`、`t_exp−t_enc`、overlap gain（`S_serial−S_slotfree`）、`sink_limited`、所需 sink 率（`2,594,750 B / 33.333 ms = 77.84 MB/s`；25 ms 口径 103.79 MB/s）；生成 G0 表、内容代理说明（铺展/打散、跨带匹配风险、无真实图集 → `proxy_not_worst`）、2.67% 差距菜单（tail overlap 0–480,930；core 171,414 cycles；clock 192.642 MHz；组合；风险/资源/时序/验证成本）。
5. **报告/自检/冻结**：`g0-closure.md`、`out/{runs.csv,g0-table.csv,gap-menu.csv,g0-verdict.json,content-proxy.md}`；负对照：G25 驱动降档、cold latency 当 `S_ss`、proxy 当 worst/all-content、serial 结果冒充 overlap、aggregate 2C；写 `result-r0.md`/`lessons.md`；`active_commands=0`、冻结 `manifest-r0.json`。

### 10.5 Run 矩阵（冻结；最多 5 次全尺寸 vsim）

| run | content | pacing | sink | capture | 目的 | 预期/判据 |
|---|---|---|---|---|---|---|
| R0 | smp 梯度 | slot-free（P1） | 187.5 MHz（P1） | 是 | 控制/派生 TB 保真 | 必须逐值复现 P1 事件/统计 |
| R1 | smp 梯度 | slot-free | 2 GHz（200 MB/s） | 是 | sink 影响（tail 是否抵消） | `S_ss≈R0`；tail 常数则差 ≤1% |
| R2 | smp 梯度 | strict-serial | 2 GHz | 是 | tail overlap 影响 | `S_ss≥R1`；差即 overlap gain |
| R3 | comp 代理 | slot-free | 2 GHz | 否 | 内容对 G0 的影响（关键） | `S_ss` vs 6.25M |
| R4（可选） | comp 代理 | strict-serial | 2 GHz | 否 | 内容+overlap 组合 | 仅按 10.4-3 的触发条件 |

- 控制值：`t_rst=20`、`t_exp(1)=6,766,454`、`t_exp(2)=11,443,989`、`L_cold=6,766,434`、`S_ss=4,677,535`、`cap=4 enc=4 exported=4 read=518400`、`exp_bytes=160136`、`cap_bytes=160312`、`raw_drop=cmp_drop=dup=geom=err=wd=0`。
- **口径定义**：`slot-free` 即 **overlapped**——P1 已在上一帧 export 完成前启动下一帧采集（帧 3 `t_sof=6,285,525` 早于帧 1 `t_exp=6,766,454`）；`strict-serial` 是**保守对照**——下一帧必须等上一帧 `st_exported` 且槽空闲才开始。R2−R1 即“强制串行”的代价；0 也如实报（说明 tail 本已隐藏）。
- comp-like 的 `exp_bytes` 预期 ~2.59 MB/帧（stored）或按代理压缩率；若 sink 限速，`sink_limited=true` 并不得用该 `S_ss` 判 G0。

### 10.6 验收门槛

| 维度 | 检查 | 门槛/证据 |
|---|---|---|
| functional | R0 控制 | 逐值复现 10.5 的控制值；任一不符 → 停止/partial，不得继续 |
| functional | R1–R3 完整 | 每 run `cap=4 enc=4 exported=4 read=518400`、无 drop/dup/geom/err/wd；事件单调；`S_ss` 可复算 |
| functional | G0 表 | A1/A2/A3/proxy × c1s1/c1s2/c2s1/c2s2；G0 硬门槛 77.76/6.25M；G25 只作参考列；无 G25 驱动降档 |
| functional | proxy 自检 | `SS_VEC_MATCH bad=0`；铺展/打散方法与跨带匹配风险写明；代理标 `proxy_not_worst`，不得称 worst/all-content |
| functional | 差距菜单 | tail overlap、core 171,414 cycles（2.859%）、clock 192.642 MHz、组合；每项给 gain/风险/资源/时序/验证成本；不实施 |
| functional | G0 结论 | 仅 `G0_feasible_for_scope`/`G0_not_closed`/`G0_not_proven`；写清内容/口径/sink/overlap；不得用 `infeasible` 代替未测 |
| engineering | 副本/白名单 | DUT 0 修改；TB 仅 §10.4-2 白名单；副本 SHA=0 mismatch；`DIFF.md` |
| engineering | 可复现/隔离 | 命令/exit/耗时/timeout 全记录；work 库/INI/日志独占；R0 确定性；写范围外 0 文件 |
| engineering | manifest | 覆盖 src/sim/out/logs/输入/工具/命令；`stopped_modifying=true, active_commands=0` |
| system | 边界 | G0 hard/G25 reference；不降档；单路/双路 per-stream；sim sink/行为 DDR/代理内容；无 DDR sustained/板级/真实 UART/PCIe 声明 |
| G 层 | G0/G1 | P1/P2/comp 向量/副本 SHA 0 mismatch；R0 + 4 帧可复算；G2–G4 `not_applicable` |

### 10.7 预算、停止

- 开发 ≤45 calls / ≤120 min；全尺寸 `vsim` ≤5 次（4 必做 + 1 可选），单次 2700 s，总仿真墙钟 ≤90 min；`vlog` 1200 s；Python 120 s；读/搜 60 s。
- 测试 ≤35 calls / ≤60 min；允许 1 次全尺寸 vsim（R0 控制复现），单次 2700 s。
- 停止：R0 不符且 1 次修正后仍不符；任一 run 超时/`SS_STALL`/丢帧且不足 2 个稳态间隔；`SS_VEC_MATCH bad>0` 且无法在预算内修正（→`G0_not_proven`）；副本 SHA mismatch；需要白名单外改 TB/DUT；需要 TD/板卡；达预算/连续 2 次无进展。**不得**用 2/3 帧冒充 4 帧、不得用 serial 冒充 overlap、不得用 proxy 冒充全内容。

### 10.8 风险

| 风险 | 影响 | 控制 |
|---|---|---|
| 代理内容不等于最坏 | 误判 G0 | 标 `proxy_not_worst`；跨带匹配检查；不称 worst/all-content；真实图集仍 `not_proven` |
| 向量→像素映射错 | 代理无效 | 字节级自检 `SS_VEC_MATCH`；失败即 `G0_not_proven`，不猜 |
| 快速 sink 改动测的正是 tail | 结论混淆 | R0 用 P1 sink；R1/R2 用 fast sink 比较；R3 用 fast sink 并报 `sink_limited`/所需 sink 率 |
| tail overlap 本已发生 | 实验无差异 | R0 事件已显示帧 3 采集早于帧 1 导出；R2 vs R1 给 0 或正值；0 也要如实报，不硬造收益 |
| 192.642 MHz/核心改动未证 | 菜单越界 | 只给菜单与成本；不实施 TD/时钟/ RTL；200 MHz/双核仍 unproven |
| 4 帧 comp-like 超预算 | 无 G0 结论 | 2700 s/run、≤5 次、总墙钟 90 min；超时 partial + `not_proven` |

### 10.9 G0 判定规则（机械）

- 若 R3（comp 代理、slot-free、fast sink）`S_ss ≤ 6,250,000`：`G0_feasible_for_scope`——scope 必须写“代理内容 + 实测 sink ≥ 该 run 所需率且 `sink_limited=false`（经 §10.10-4 修订；不再要求字面 ≥200 MB/s）+ 行为 DDR + per-stream + 单内容类”；若 R2−R1>1%，再以 R4 复核 overlap 口径。
- 若 R3 `> 6,250,000`：`G0_not_closed`——给 `gap = R3 − 6,250,000`（cycles 与 %）与 10.4-4 菜单；不得改成 1600×900 等降档推荐。
- 若代理无法可信构造/映射失败：`G0_not_proven`——用 A2/A3 包络给区间，不得外推全内容。
- G25 列只作参考；双核 c2s2=C + PAXI/时序 unproven 仍适用；任何结论不得写成板级/真实 DDR/RK 已通过。

> **§10.10-4 修订**：sink 条件不再用“≥200 MB/s”字面；以“实测 sink ≥ 该 run 所需率且 `sink_limited=false`”为准。93.75 MB/s 对 comp 代理接受（848,864 B/帧、tail 28.6%）；不可压缩 raw band 仍需 ≥77.84 MB/s（G0）/ ≥103.79 MB/s（25 ms/tail 稳健）。

### 10.10 round0 裁决与 round1 修复合同（2026-10-26）

#### 10.10-1 事实基线（tester r0 integrated FAIL）

- P3 r0 manifest `A4391C0C740C24C1EF7FA9AE2984B2013BBF489E476BF80C88EBDE722C0BDEF8`（68 artifacts；`stopped_modifying=true`、`active_commands=0`）；冻结 TB `src/tb_ss_g0.v` `A565C6F2…`（24,118 B）。
- **R0–R3 timing 实际使用 TB `89948303…`（23,894 B，仅存 `%TEMP%`）**；旧 TB 与冻结 TB 的差异仅是字节级自检分组（4 行 `2'd3`↔`2'd0`）与帧 1 早打印，无 DUT 驱动/端口/几何/时钟/复位改动。
- 数据面（tester 自写解析 + 独立 R0）：R0 `S_ss=4,677,535`（逐值复现 P1；冻结 TB 独立重跑 881.5 s，stats/dec 逐字节相同）；R1 `4,677,531`；R2 `6,365,622.5`；R3 `5,928,286`（band 6 cycles）。R3 `C=81.9799 MB/s`、G0 `+5.4268%`、G25 `−15.6586%`（仅参考）；tail `1,697,820` 恒定；payload `848,864 B/帧`；`sink_limited=false`；实测导出 **93.7449 MB/s**。R2−R1 = `1,688,091.5`（36.089%）。A2 gap `171,414 cycles / 2.6694%`；G0 时钟 `192.642 MHz`。R4 未跑，comp strict-serial `assumed = R3+(R2−R1) = 7,616,377.5`（G0 −17.94%）。
- FAIL 点：engineering（TB provenance/白名单）与 G1（input binding）；system 为“PASS 但 sink scope 需规划确认”；functional PASS。`content-proxy.json` 的 `in.meta` 记录 297 B/normalized SHA，实际 330 B/raw `E98C9A1C3E0FE621C9AA65AAADBCACBEF13C2437A0BBBAFCDE17D2FF471F80FE`（非阻断）。

#### 10.10-2 裁决 D1：接受 R0–R2 的 TB-only 等价；**R3 必须用冻结 TB 重跑**

- 接受 R0–R2 timing 作为 TB-only 等价证据：差异只在只读自检分组/早打印；`CONTENT=0` 时自检整段不执行；tester 已用冻结 TB 独立重跑 R0 并逐字节复现。旧 TB 必须复制到 `src/legacy/tb_ss_g0_89948303.v`、加入 manifest artifacts，并附 diff/无影响论证；规划在此书面接受该 TB-only 等价。
- **R3 是 G0 关键 run，不允许跨 TB 版本拼接**：用冻结 TB `A565C6F2…` 重跑 R3（comp proxy / slot-free / SINK=1 / FRAMES=4 / CAPTURE=0，同一 raw/vec 文件），必须在**同一 run** 打印 `SS_VEC_MATCH bad=0 checked=518400 drv_groups=518400`；`S_ss` 预期 `5,928,286`（接受 ±0.5%），并重核 header CRC（raw/xform/stream/header）。
- R0–R2 **不重跑**（预算 + 等价）；R4 **不跑**（预算；保持 assumed）。

#### 10.10-3 裁决 D2：修订 TB 白名单（不回退）

- 追加允许项（均为 TB-only、只读/打印/文件，不改 DUT 驱动）：① `WD_LIMIT 12,000,000`（R3 `L_cold=9,234,076 > 8M`，8M 会误触发；12M < `MAX_CYCLES=48M`，仅防真挂死）；② `CAPTURE=1` 的 `.dec` 文本 `%02x`（P3-only 格式；P1 `.dec` 在 P3 不做逐字节比较，`cap_bytes` 计数不变）；③ `CAPTURE=0` 的 `+HDR` 前 256 B（header CRC 必需）；④ `SS_META/SS_STATS` 追加字段与 `SS_MODE`（只读记录；b11 前 16 字段顺序/数值不变，R0 已验证）；⑤ 帧 1 早打印 `SS_VEC_MATCH` 与分组修正（仅冻结 TB）。
- 仍**禁止**：任何 DUT 驱动/端口/几何/`LINE_GAP`/`FRAME_GAP`/时钟/复位/内容映射（raw/vec）改动；改 b11 前 16 统计字段；改 `S_ss` 定义或 G0 阈值。
- `DIFF.md` 必须修正：§4 sink 实测为 **2 clk_a1/B ≈ 93.75 MB/s**（不是 187.5）；§5 `%02x` vs P1 `%0d`；§1 WD 12M 理由；F8（`_repair.py`/`scratch_excluded` 与 artifacts 矛盾、`p2_a1_board_top` 文档）；F7（A1 overlapped 取 R1 4,677,531，需注 −4 cycles）；F5（R4 触发已满足但预算未跑）；F6（v1 日志名）。

#### 10.10-4 裁决 D3：接受实测 93.75 MB/s sink（仅限 proxy scope）

- 接受：R3 payload `848,864 B/帧`（25.47 MB/s@33.3ms）、tail `1,697,820`（28.6% < 50%）、`sink_limited=false`；93.75 MB/s 高于冻结 raw-band 的**平均**需求 77.84 MB/s，但 raw band 的 per-frame tail 会是 27.7 ms（83% of 33.3 ms），tail 隐藏未证。**不要求 ≥200 MB/s 重跑**；`§10.9` 的“≥200 MB/s”字面改为功能判据：sink ≥ 该 run 所需率且 `sink_limited=false`，并记录实测率。
- **不得**声称 93.75 MB/s 对不可压缩 raw band 足够：`2,594,750 B/帧 ÷ 93.75 MB/s = 27.7 ms`（83% of 33.3 ms）> 50%，会触发 sink 限速；生产 sink 仍需 ≥ **77.84 MB/s**（G0）/ ≥ **103.79 MB/s**（25 ms/tail 稳健），保持 `not_proven`。

#### 10.10-5 裁决 D4：G0 scope/headline 与 R4

- **临时 headline**：`G0_feasible_for_scope`（R3 5,928,286 ≤ 6.25M，+5.4268%），但**只有在 R3 冻结 TB 重跑 + manifest/元数据重冻结 + tester 复测通过后才正式成立**。若重跑 `S_ss>6.25M` → `G0_not_closed`；若 `bad>0`/无法绑定 → `G0_not_proven`。
- scope 必须写：comp 向量代理（transform-domain ramp 平铺 b mod 32、`848,864 B/帧`、`proxy_not_worst`、单内容）/ slot-free（overlapped）/ 实测 93.75 MB/s sim sink（对 proxy 不限速；raw band 另需 ≥77.84/103.79 MB/s）/ 行为 256-bit PAXI（无 MC/刷新/争用）/ 单核单路 / 187.5 MHz；**不外推**自然图像/全内容/双路/板级/真实 DDR/PCIe/RK。
- G25 只作参考列，不降档。
- R4：`not_run`（触发条件已满足但 90-min 墙钟到顶）；comp strict-serial 只能写 `assumed`（7,616,377.5；G0 −17.94%），**不得**声称 strict-serial 过 G0；headline 只覆盖 slot-free。
- A1 overlapped 取 R1 `4,677,531`（比 P1 4,677,535 低 4 cycles）必须加注；`in.meta` 修为 330 B/`E98C9A1C…`（无需重跑）。

#### 10.10-6 round1 修复合同（同一开发/同一测试者）

- **同一 P3 开发会话**（不新建、不重置修复轮；`repair_round=1/3`）；冻结后由**同一 P3 综合测试者**复测受影响项。
- 允许：① 冻结 TB 重跑 R3（1 次全尺寸，≤2700 s）；② 旧 TB 归档 + manifest 绑定 + diff；③ `content-proxy.json` 的 `in.meta` 修正；④ `DIFF.md`/`g0-closure.md`/`g0-verdict.json`/`g0-table.csv`/`runs.csv`/`gap-menu.csv`/`sink-needs.csv`/`result-r1.md`/`lessons.md` 更新；⑤ 重新冻结 `manifest-r1.json`（不得覆盖 r0 证据；新日志用 `r3_frozen.*` 等独立名）。
- 禁止：重跑 R0–R2/R4；改 DUT/内容映射/几何/时钟/复位；改 `S_ss` 定义/G0 阈值/门槛；用旧 TB 的 R3 timing；把 R4/assumed 写成 measured；写全内容/双路/板级结论；TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK；改 P1/P2/comp 向量/tasks.json/docs。
- 预算：round0 已用 4 次全尺寸 + 86.8 min wall；round1 补充 **≤15 calls / ≤60 min**、**1 次全尺寸 R3 + 至多 1 次短 v1（≤300 s，独立名 `v1_r1.*`）**、补充 sim wall **≤25 min**（累计 ≤112 min，全尺寸计数 **5/5**，不重置）；tester **≤10 calls / ≤30 min**、1 次短 v1（≤300 s，独立名），不做全尺寸重跑。
- 复测清单：R3 `bad=0` 同一 run；`S_ss`/band/计数/header CRC；manifest-r1 绑定冻结 TB + 旧 TB 归档；白名单/DIFF/in.meta/scope wording/R4 assumed/A1 note；P1/P2/comp 哈希未变；0 TD/板卡；写范围。
- 停止/blocked：R3 重跑失败/超时/`bad>0` → `G0_not_proven`；`S_ss>6.25M` → `G0_not_closed` 并给差距；工具/授权缺失 → blocked；预算用尽 → partial + 恢复入口。**不得**用 r0 的跨版本 R3 timing 直接 PASS。

### 10.11 round1/round2 结果与收尾（2026-10-26，finished）

- **r1（metadata FAIL）**：冻结 TB `a565c6f2…` 重跑 R3 → `r3_frozen` 同 run `SS_VEC_MATCH bad=0 checked=518400`、`S_ss=5,928,286`、header CRC 全对；旧 TB 归档 `src/legacy/tb_ss_g0_89948303.v`；`content-proxy.json` in.meta 修正；`manifest-r1.json` 冻结。r1 综合测试 FAIL 于 metadata（manifest/verdict/budget/A1/DIFF 一致性）。
- **r2（PASS）**：`manifest-r2.json` `3C8377A4…`（82 artifacts；`previous_manifest` r1 `D700FE9A…`）；无新全尺寸 vsim（复用 `r3_frozen` + tester `v1_r1`）；51/51 checks PASS；formal **`G0_feasible_for_scope`**。2 条非阻断 OBS：`_repair.py` scratch 注记与 artifacts 矛盾；`g0-closure.md` 顶部/§10 仍为 r0/r1 历史表述。
- **最终**：P3 实际修复 **2 轮**；全尺寸 5/5、vsim 墙钟 108.9 min ≤112；0 TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK；P1/P2/P3 冻结件未改；T10 未置 done。
- **剩余主题**（下一 run，按优先级）：① 自然图像/低照/噪声/最坏内容 4 帧（替换/校准 A2）；② 生产 slot-free 实现 + sink 率（raw band ≥77.84/103.79 MB/s）；③ 双核共享 PAXI/Routed 时序/资源；④ b11 1176 停读/板级；⑤ 真实 DDR sustained/RK。G25 已由用户定为参考，不再作为降档依据。

## 11. P4：`T10.ss-4run-matrix`（四轮不同条件实测矩阵；2026-10-26 用户选择）

### 11.1 目标与边界

- 用户明确选择：**4 个不同条件的全尺寸 4 帧 run（四轮实测矩阵）**，不是同一条件重复 4 次；每轮约 22 min，总约 90 min。仍只做 FPGA 侧离线；TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK=0。
- P4 是**新包**：新开发、新综合测试者；**不复用 P1/P2/P3 会话**；P1/P2/P3 冻结件不改。
- 目标：在同一 4 帧链级口径下，量化 **content / pacing / sink** 三个因素对 G0 的影响，并给出每轮的 G0 结论；G0 仍是硬门槛，G25 仅参考、不降档。
- 边界：本地无真实自然 RAW；所有内容都是**合成/代理**，必须标 `proxy_not_natural` / `proxy_not_worst`（comp）或 `full_frame_raw_synthetic`（raw.bin）；不得称自然图像或全内容。

### 11.2 冻结内容源（只读；SHA 于规划轮复算）

| id | 源 | 字节 | SHA256 | 几何/格式 | 用途 |
|---|---|---:|---|---|---|
| C1 | `T10.a1-adler-smem/r0/p3/cases/f1080p_p1d1/raw.bin` | 2,592,000 | `061b0dfce062d5cd9231e2f0eccee112c189f64487e9b928f99e1531ccf91f8d` | 1920×1080 packed RAW10（5 B/4 px；518,400 组；480 组/行） | R1/R2 全帧 raw（grad，PREP/PRED=1 匹配链） |
| C2 | 同 run `.../cases/f1080p_rand/raw.bin` | 2,592,000 | `8fe204b715d08285b5918d7745e01195c1925b18ef0d19b9fcfb59ff06f0fad5` | 同上 | R3 不可压缩全帧 raw |
| C3 | `work/parallel-sim-20261024-2204/codec-throughput/comp/in.hex` | 614,400（文本） | `edbfdeaedb06824ced20ad76b260979e95e1322d6f6e3bab5e7a951a268f9849` | 153,600 B transform-domain comp 向量（32×4800 B） | comp proxy（R4） |
| C4 | 同 `comp/in.meta` | 330 | `e98c9a1c3e0fe621c9aa65aaadbcacbef13c2437a0bbbafcde17d2ff471f80fe` | 32×4800 B 块 | 元数据 |
| C5 | 同 `comp/in.xform` | 153,600 | `b836b51df0bc98045f3768cf497bb5a76f88fa301e0598c63514284e2fbfba7a` | 153,600 B | 域校验 |
| C6 | P3 `sim/caps/comp_raw.hex` | 6,220,800 | `e3d9094643e3d7d3881ab527abfa0d7e296348895c71eca757cbf911a595eea1` | 518,400×40-bit raw 组 | R4 输入 |
| C7 | P3 `sim/caps/comp_vec.hex` | 368,640 | `a91cd406585d54cb2ed9cc760eb88abfcfc6faf135265684f93a6c20a98595b8` | 32×960 组 | R4 自检 |

- **C1/C2 的 TB 映射**：每 5 B 组 `{b0,b1,b2,b3,b4}`（`b0..b3=p0..p3[9:2]`，`b4` 低 2 位拼接）转 40-bit `tap_pix = {b4,b3,b2,b1,b0}`；由 Python 预处理为 `raw40_<id>.hex`（518,400 行 10-hex），SHA 记录在 `out/content-map.json`。TB 在 ROI 组 `(y-ROI_Y, g-GX)` 输出，非 ROI 填 0；`SS_RAW_MATCH bad=0 checked=518400` 才允许 run。
- **C1 只取 p1d1**：`f1080p_p1d0`/`f1080p_p0` 的 `raw.bin` 与 p1d1 同 SHA（`061b0dfc…`），只是编码器 PREP/PRED 配置不同；链上 PREP/PRED 固定 1/1，选 p1d0/p0 需改 DUT 参数（禁止），故不重复使用。`f1080p_rand` 是不同 raw（`8fe204b7…`），用于 R3。
- **C3–C7 的 R4 映射**：沿用 P3 `inverse_frame(tiled,1920,1080,1,1)` → packed RAW10 → DUT 正向变换；`SS_VEC_MATCH bad=0`；DUT header raw/xform CRC 校验。
- 所有源只读复制到 P4 `content/`；不得改源目录。

### 11.3 四轮矩阵（冻结；4 个不同条件）

| run | content | pacing | sink | capture | 目的/预期 |
|---|---|---|---|---|---|
| **R1** | C1 `f1080p_p1d1`（全帧 raw，grad，可压缩） | slot-free（overlapped） | SINK=1（最大冻结 sink，实测约 93.75 MB/s） | 0（+HDR 256 B） | 全帧 raw 生产路径；预期 G0 过（内容比 comp 代理快）；`full_frame_raw_synthetic` |
| **R2** | C1（同 R1） | strict-serial | SINK=1 | 0（+HDR） | pacing 代价；`R2−R1` 为 overlap penalty；预期 G0 可能跌到 −2% 量级 |
| **R3** | C2 `f1080p_rand`（全帧 raw，不可压缩/stored） | slot-free | SINK=1 | 0（+HDR） | 最坏带宽/sink 压力；记录 tail、`sink_limited`；若 tail>50% 或 rate<所需 → `G0_not_proven`（raw band），并给生产 sink 需求 |
| **R4** | C3–C7 comp proxy（同 P3 R3） | slot-free | SINK=1 | 0 | 对照/重复性：应复现 P3 R3 `S_ss=5,928,286`（±0.5%）；`proxy_not_worst` |

- **对建议矩阵的细化（必须写进报告）**：原建议 R3 为“同内容 + 生产级 sink ≥103.79 MB/s”。**冻结 TB 的 sink 上限是 93.75 MB/s**（`a1_uart_export` 每字节 2 个 `clk_a1` 的 holding-register 交接；请求 2 GHz 也只到 93.75）。P4 的白名单不允许改 DUT/导出握手，因此无法真做 ≥103.79 的 sink。细化：R3 用**不可压缩 rand 全帧 + 最大冻结 sink**做 sink 压力实验，记录 tail/`sink_limited` 与生产 sink 需求（raw band ≥77.84 MB/s G0 / ≥103.79 MB/s 25 ms）；这是对“生产级 sink”意图的**可行**实现。若要求严格“同内容 + ≥103.79”，需新 TB/RTL（超出 P4 白名单）→ 记 `G0_not_proven`，交后续。
- 4 个条件互不重复：C1 slot-free、C1 strict、C2 slot-free、C3–C7 comp slot-free。R1/R2 同内容才可比较；R4 是 P3 对照。

### 11.4 TB/驱动冻结（从 P3 派生）

- 基线：P3 `src/tb_ss_g0.v` `A565C6F2…`（24,118 B）；DUT 12 源与 P1 manifest 逐字节相同。
- 派生 `src/tb_ss_4run.v`，只允许：① `CONTENT` 扩展（0=smp、1=comp、2=C1 raw40、3=C2 raw40）；② `RAWFILE` plusarg（`+RAW40=…`）；③ `PACING`（slot-free / strict-serial）；④ `SINK`（0=P1 18.75 / 1=max 93.75）；⑤ `CAPTURE`（0=+HDR 256 B，1=.dec）；⑥ `MAX_CYCLES=48,000,000`；⑦ `SS_EVT/SS_PACE/SS_STATS` + `SS_RAW_MATCH`（raw 5B 组逐字节）+ `SS_VEC_MATCH`（comp）；⑧ 路径/日志独立名。
- 禁止：改 DUT/端口/几何/时钟/复位/内容映射（raw/vec 只读）；改 `S_ss` 定义/G0 阈值/统计前 16 字段顺序；TD/板卡。
- `src/DIFF.md` 逐条列 diff 与无影响论证；`input-verified.json` 记录 12 DUT + 7 内容源 + P3 TB/DIFF 的 SHA。

### 11.5 运行、分析与输出

1. 预处理 C1/C2 → `content/raw40_p1d1.hex`、`raw40_rand.hex`（记录 SHA/组数/抽查字节）；复制 C3–C7；`input-verified.json` 0 mismatch。
2. 编译 + 4 个全尺寸 4 帧 run（R1–R4）；每次 `vsim` 硬超时 2700 s；**全尺寸 ≤5 次**（4 + 至多 1 次有新证据的重试）；**总 wall ≤120 min**；每 run 记录 `L_cold/S_2/S_23/S_34/S_ss/tail/sink_limited/overlap/exp_bytes/header CRC`。
3. R1/R2 必须同 C1、同 sink；R2−R1 为 pacing 代价；R3 记录 `sink_limited`/tail 与所需 sink；R4 与 P3 R3 比较（±0.5%）；若 R4 不复现 → 停止/blocked，不拼旧 run。
4. 分析：`out/runs-4.csv`、`out/four-run-table.csv`（4 行 + P3 对照）、`out/g0-verdict.json`（每 run G0 + 总体 headline）、`out/content-map.json`（源/几何/packing/映射/自检）、`out/gap-menu.csv`（沿用 P3 菜单 + sink 项）；`four-run-report.md`。
5. 负对照：`RAW_AS_NATURAL`、`RAW_AS_WORST`、`SINK_LIMITED_AS_G0`、`SERIAL_AS_OVERLAP`、`COLD_LATENCY_AS_THROUGHPUT`、`G25_DOWNGRADE`、`AGGREGATE_2C`、`CONTENT_MAP_MISMATCH`；全部拒绝。`result-r0.md`/`lessons.md`/`manifest-r0.json` 冻结。

### 11.6 验收门槛

| 维度 | 检查 | 门槛 |
|---|---|---|
| functional | 4 run 完整 | 每 run `cap=4 enc=4 exported=4 read=518400`、无 drop/dup/geom/err/wd；4 帧事件可复算；R1/R2 同 C1 同 sink |
| functional | 内容自检 | R1/R2/R3 `SS_RAW_MATCH bad=0 checked=518400`；R4 `SS_VEC_MATCH bad=0`；header raw/xform/header CRC 自洽；映射 SHA 一致 |
| functional | R4 对照 | 复现 P3 R3 `S_ss=5,928,286`（±0.5%）；否则停止/blocked |
| functional | 四轮表/G0 | 4 行 + P3 对照；每行 L_cold/S_ss/tail/sink_limited/overlap/G0；G25 仅参考；不降档 |
| functional | R3 sink | 记录实测率/tail/`sink_limited`；若 tail>50% 或 rate<所需 → 该内容 `G0_not_proven`，给生产 sink 需求；不得把 sink-limited 值当 G0 证据 |
| functional | headline | 只能 `G0_feasible_for_scope`（C1 全帧 raw / comp proxy）或 `G0_not_closed`/`G0_not_proven`（C2 raw band）；不得称自然/全内容/worst |
| engineering | DIFF/manifest | DUT 0 修改；TB 仅 §11.4 白名单；副本/内容 SHA 0 mismatch；manifest 覆盖全部；`stopped_modifying=true, active_commands=0` |
| engineering | 隔离/预算 | 独占 work 库/INI/日志；命令/exit/超时记录；全尺寸 ≤5、单次 ≤2700 s、总 wall ≤120 min；写范围外 0 文件 |
| system | 边界 | 合成内容、slot-free/strict-serial、93.75 sim sink、行为 DDR、单核/187.5 MHz/per-stream；无 TD/板卡/真实 DDR/PCIe/RK 声明 |
| G 层 | G0/G1 | 输入/内容 SHA 0 mismatch；4 run 可复算；G2–G4 `not_applicable` |

### 11.7 预算与停止

- 开发 ≤45 calls / ≤120 min；全尺寸 `vsim` ≤5 次（4 + 至多 1 次新证据重试），单次 2700 s，总 wall ≤120 min；`vlog` 1200 s；Python 120 s；读/搜 60 s。
- 测试 ≤35 calls / 60 min；允许重跑 1 次控制（建议 R4 comp proxy，复现 5,928,286），单次 2700 s。
- 停止/blocked：内容映射自检 `bad>0` 且预算内无法修正 → `G0_not_proven`；R4 不复现 P3 R3 → blocked；任一 run 超时/`SS_STALL`/丢帧且不足 2 个稳态间隔 → partial/blocked；预算用尽 → partial；需 TD/板卡 → blocked；不得用 2/3 帧冒充 4 帧、不得用 sink-limited 当 G0、不得用 raw 合成内容称自然/worst。

### 11.8 风险

| 风险 | 影响 | 控制 |
|---|---|---|
| 合成 raw 不是自然/最坏 | 误判全内容 | 标 `full_frame_raw_synthetic` + `proxy_not_natural` + `proxy_not_worst`；只给 scope verdict |
| raw→40bit 映射错 | 内容无效 | Python + TB 双重 `SS_RAW_MATCH`；失败即 `G0_not_proven` |
| 冻结 sink 上限 93.75 | R3 无法做 ≥103.79 | 用 rand + max sink 做压力；记录 `sink_limited`；生产需求 ≥77.84/103.79 另列；不伪造 103.79 |
| R2 strict-serial 含相机串行化 | 把 pacing penalty 当纯 tail | 报告写 R2−R1 是 upper bound；不称纯 tail |
| R4 不复现 P3 R3 | 新 TB 不可信 | ±0.5% 门槛；否则 blocked |
| 4 次全尺寸超 120 min | 无矩阵 | 单次 2700 s、总 wall ≤120；超时 partial |

### 11.9 P4 r0 实际结果与收尾（2026-10-26，PASS）

- 判定：**PASS r0（1 轮）**；manifest-r0 `d353c61adbc99eb14e9c6f2de44e1a45e99a59f292081e4b00311978ea6c6dd1`（68 artifacts）；报告 `test-reports/T10.ss-4run-matrix-r0-integrated.md` `887023ad…`；blocked=false、无 FAIL/复测轮。
- 四轮实测（4 帧全尺寸）：

| run | content/pacing | `S_ss` | `L_cold` | tail | sink_limited | `C` / G0 |
|---|---|---:|---:|---:|---|---|
| R1 | C1 p1d1 / slot-free | **4,677,970** | 6,449,446 | 163,506 (3.50%) | false | 103.891 / **+33.605%** |
| R2 | C1 p1d1 / strict | **6,449,405** | 6,449,446 | 163,506 (2.54%) | false | 75.356 / **−3.092%** |
| R3 | C2 rand / slot-free | 5,189,503 | 11,476,032 | 5,700,448 (**109.85%**) | **true** | 93.651¹ / +20.435%¹ → `G0_not_proven` |
| R4 | comp proxy / slot-free | **5,928,286** | 9,234,076 | 1,697,820 (28.64%) | false | 81.980 / **+5.427%** |

¹ sink 服务率等价，不是 G0 余量。
- **R2−R1 = 1,771,435 cycles（37.87%）**：slot-free 是 G0 的必要条件；R2 只作 strict-serial 保守视图（含相机串行化）。
- **R3**：`S_ss` 与 2,594,706 B × 2 clk/B 的导出时间（5,189,412 cycles）几乎相等；tail 109.85% → `sink_limited=true` → `G0_not_proven`；实测导出 93.748 MB/s；生产 sink ≥77.84（G0）/103.79（25 ms）单列，93.75 不得写成 ≥103.79。
- **R4** 复现 P3 R3：Δ=0 cycles、`exp_bytes=3,395,456`、`cycles=27,020,950`、`SS_VEC_MATCH bad=0`、header CRC 全对；tester 独立重跑 1,234 s 亦 Δ=0。
- 内容自检：R1/R2/R3 `SS_RAW_MATCH bad=0 checked=518400`；DUT `raw_crc` = `zlib.crc32(raw.bin)`（C1 1,020,842,313；C2 237,020,219）；R4 raw/xform CRC 与 P3 冻结值相等；8 负对照全拒。
- 预算：4 次全尺寸 4,741.5 s = **79.0 min ≤120**；单次最长 1,383.6 s；0 重试；tester 1 次控制 1,234 s；全尺寸 4/5；0 TD/板卡。
- 最终 headline：**`G0_feasible_for_scope` 收窄**（C1 全帧合成 raw + comp proxy / slot-free / 93.75 MB/s sim sink / 行为 DDR / 单核 187.5 MHz / per-stream）；C2 raw band `G0_not_proven`；R2 `G0_not_closed`；自然/全内容/最坏/双路/板级不外推。
- 已披露偏差：① 预检 `chk_raw.log` 以 2M-cycle 超时 `pass=0`（设计内，非全尺寸）；② `%TEMP%\opencode\dbg_comp.py` 653 B 只读脚本在写范围外（删除被环境拒绝）；③ tester 未独立重实现 C1/C2 `xform_crc`（`raw_crc` 已独立复算）；④ `four-run-report.md`/`g0-verdict` 将 raw band 写成 2,594,750（正确 2,594,706，差 44 B header，不影响门槛）。
