# r2-ruling — 20261027-055621_fpga-honly-td-and-ah（2026-10-27 09:30）

覆盖：`T10.ah-honly-synthfix` 关账；TD 租约**新持有者**复核与规则 v2；放行 `T10.ah-honly-td` r1；P3 放行条件；包账。
规划本轮只读复核 + 文件更新；未跑仿真、未跑 TD。

---

## 1. `T10.ah-honly-synthfix` r0：**PASS，关账**

规划独立复算（不依赖测试者叙述）：

| 项 | 值 |
|---|---|
| manifest | `T10.ah-honly-synthfix/r0/manifest-r0.json` SHA-256 **`034777C55D5A7857F18D9860AFBB73F7554940F65213D9228C449BBC5855E510`**；`stopped_modifying=true`、`active_commands=0`；75 artifacts / 31 refs / 15 commands |
| 哈希复算 | **75/75 通过，missing=0、mismatch=0**（以任务根为基准逐项重算） |
| 候选 | core **`d2960cfe0111b7b61aff281e3f16427834dda26107f37867d5c7c89ac346aad8`**（85,221 B）；frame_top **`4afc26e2…e30a`**（29,207 B，与 H-only 逐字节相同） |
| 测试者 | `test-reports/T10.ah-honly-synthfix-r0-integrated.md` 首行 `### 判定：PASS`；93/93 检查；diff 仅白名单两处（净 +4/−3 行、29 B）；自有扫描 0 跨块驱动；4 帧 `S_ss` 精确 6,196,749.5 / 5,834,940，4 个 `.frm/.hdr`（且 `.evt/.stats`）整文件 SHA 与冻结基准相同；bench/adapter/独立 8b comp 304,961 cyc 全复现；0 TD |

**关账**：包 2 关闭为 PASS；候选 core 升为"可综合性已修复的 H-only 候选"，但在 TD r1 出结果前**不得**写成"可作为后续候选"。

---

## 2. TD 租约：持有者已变，规则升级为 v2（holder-agnostic）

### 2.1 规划 09:26:32 实测

| 检查 | 结果 |
|---|---|
| TD 进程（pnmain/td/td_commands_prompt/tdsynth） | **0**；vsim/vsimk **0** |
| `INT.P4/td` 最新写入 | 06:07:52（**198 min** 静默） |
| `INT.P4/r3` 最新写入 | 06:08:17（**198 min**） |
| **新出现** `20261027-0726_fpga-board-integration` | **活跃**（文件更新至 08:57；`T11.BRD.P1` 正在做仿真） |
| 该 run 的 TD 现场 | `T11.BRD.P1/td` 最新 **08:18:30**（**68 min** 静默）：08:15–08:18 已跑过 1 次综合，产出 `brd_board_gate.db` 14.7 MB + `flow.status` |
| 该 run 的 TD 余额 | `td_quota`：sessions 4 / synth 3（已用 1）/ route 2 / bitgen 1 / download 1（P1/P2 专用） |
| `T:` 映射 | **已被该 run 占用**：`T: → ...\20261027-0726_fpga-board-integration\T11.BRD.P1\td`（其 dispatch 明令用 `td_env.ps1 -Force` 重指） |

### 2.2 裁决

- 按 v1 规则（只看 INT.P4）会误判"空闲"；实际存在**第二个、仍在活跃的 TD 竞争者**。故：
  **规则 v2（本轮起生效）**：TD 空闲 = ①0 个 TD 进程 **且** ②**所有已知 TD 使用方**的工程目录最近 20 min 无写入（当前至少：`INT.P4/td`、`INT.P4/r3`、`20261027-0726_fpga-board-integration/T11.BRD.P1/td`）**且** ③无正在进行的 TD 会话迹象。
- **判定：TD 当前空闲，租约授予 `T10.ah-honly-td` r1。** 依据：0 进程；三处目录静默 198/198/68 min，均 >20 min。
- **残余风险（必须写进报告，不得隐瞒）**：board-integration run 仍活跃且保有 synth 2 / route 2 / bitgen 1 余额，可能在本次窗口内启动 TD。本规划无法阻止（不抢、不杀、不改其工程）。应对：
  1. 我们的 TD 命令**串行、不并行**；同一时刻只允许本任务一个 TD 进程。
  2. 若窗口内发现他人 TD 活动：**不 kill、不共享、不抢占**；只允许让**已在运行**的那条命令自然结束，记录重叠事实，**不再启动第二条**。
  3. 若出现单席位冲突（`RUN-8008` / `PRJ-5303` / `PRJ-8806`）：**不重试**，`blocked=TOOL_UNAVAILABLE` + 原始错误，由原规划决定；不得把冲突记成"候选不可综合"。
- **`T:` 不得 remap / 不得 -Force**（属他人）。本任务 tcl 全绝对路径，`T:` 非必需。

---

## 3. 放行 `T10.ah-honly-td` r1（同任务新轮，不新建）

### 3.1 配额清算（延续 r1-ruling §2.3）

| 计法 | 值 | 说明 |
|---|---|---|
| TD 启动（lifetime ≤3） | 已用 1（r0 的 6.49 s elaborate 拒绝），**本 r1 用第 2 次** | 剩 1 次仅作应急 |
| 综合**结果** | r1 获 **1 次** | elaborate 失败不产净表/DB/报告，不计结果 |
| route | **≤2** | 第 2 次须写明参数差异 |
| 209.6 analysis-only | **≤1** | 同一 routed DB 收紧时钟 |
| bitgen/CWC/下载/Flash/板卡/网络 | **0** | — |
| 修复轮 | 0（缺陷属 DUT，已由 synthfix 修；TD 任务自身无可修配置） | — |

**若 r1 综合再次 elaborate 失败**：不自动启动第三次；冻结证据返回，由原规划决定是否动用最后一次启动配额。

### 3.2 允许的改动（仅 source binding / Tcl / README / hash，不改 RTL/几何/时钟/SDC 例外）

| 文件 | 允许改动 |
|---|---|
| `r1/td/01_synth.tcl` | 仅 `add_files` 两行 DUT 路径改为 synthfix 冻结路径（core `d2960cfe…`、frame_top `4afc26e2…`），文件头 DUT 说明/SHA 注释更新；**解析与报告段一行不改** |
| `r1/td/a1_ah_eng_top.v` | 与 r0 版本**逐字节相同**的副本（SHA 重记） |
| `r1/td/a1_ah_small_top.sdc` | 与 r0 版本**逐字节相同**的副本（5.333 ns，无例外） |
| `r1/td/02_route.tcl`、`03_2096_analysis.tcl` | 仅路径/注释随 r1 目录调整，语义不变 |
| `r1/td/README.md`、`r1/BINDING.md` | DUT 绑定、旧→新 SHA（`8acd20b2…` → `d2960cfe…`）、synthfix manifest `034777c5…`、配额与租约 v2 |
| 禁止 | 改 RTL、改几何/时钟/SDC 周期、false_path/multicycle/clock-group、加 IO 约束、改 wrapper 端口、复用 r0 的 run 目录 |

### 3.3 门槛（冻结）

综合：`flow.status` 的 `NUM_FEPS`/WNS/TNS、hold、Period Check WNS、STA coverage；area 的 `#IO/#eram/#fifo20k/#reg/#slice*/#dsp`。
布线：routed DB 上 **WNS ≥ 0、hold ≥ 0、NUM_FEPS = 0**、ERAM+CWC ≤300、slice ≤71,680、IO ≤286；`check_timing`（或 `report_check_timing`）+ `report_cdc`；worst ≥10 条路径归因到 **frame_top 双 CRC32 / core replay / scan** 三类。
布线触发规则：synth WNS ≥ −0.50 ns 才布线；< −0.50 ns 记 `route=not_run` + 原因。
209.6：仅 analysis-only，显式标注非布线结果。
结论：全部满足 → `eligible_for_next_stage`；否则 `not_eligible` + 真实数字，不放宽。

### 3.4 角色与预算

- **恢复原 TD 开发会话 `ses_e85b9e73effe3tYbVh2330erSx`**（同任务新轮，不新建）。
- 完成后**新**综合测试者（≤35 calls / 60 min，不重跑 TD）。
- 开发：≤60 calls / ≤180 min；synth ≤1,800 s；route ≤2,400 s/次；analysis ≤600 s。

---

## 4. P3（`T10.ah-dual-verdict`）放行

条件：**A kill_verified ✅** + **synthfix PASS ✅** + **TD r1 有确定性结果**（测试者判定或明确 blocked）。三者齐备后由原规划写 `dual-verdict.md`（0 sim / 0 TD / 新角色 0）。
必须包含：A 处置与重开条件；TD r1 的 eligible/not_eligible 与真实 WNS/Fmax/资源/关键路径；H-only 候选资格**只由 TD eligible 支撑**；三条限定（N +0.859% 薄裕量、prototype gate ≠ 整机 G0、0 bit/0 板级）；若 not_eligible，给下一包建议（单锥 retime / 结构方案 / 布局参数）。
P3 **不得**把"可综合性已修复"写成"实现可行"。

---

## 5. 包账（仍为 4 包，上限）

| # | task | 状态 | 角色 |
|---|---|---|---|
| 1 | `T10.ah-a-plus-h-r2` | closed（kill_verified / not adopted） | 无 |
| 2 | `T10.ah-honly-synthfix` | **closed（PASS）** | 无 |
| 3 | `T10.ah-honly-td` | r0 FAIL（不可综合）；**r1 ready（本次放行）** | 恢复原 TD 开发 → 新测试者 |
| 4 | `T10.ah-dual-verdict` | blocked（待 TD r1 结果） | 原规划 |

不新增 ID、不扩包。

---

## 6. 风险表

| 风险 | 处理 |
|---|---|
| board-integration run 在我们的 TD 窗口内启动 TD | 单席位冲突时不重试；记录重叠；`blocked=TOOL_UNAVAILABLE`；不把他因记成候选缺陷 |
| r1 综合仍 elaborate 失败（新多驱动） | 不自动第三次；冻结证据；规划决定最后一次启动或转"elaboration 清理"独立包 |
| synth WNS 很负（预期可能接近 0 或为负，历史同族块级仅 ~0.0x ns） | 按 ≥−0.50 才布线；如实记 `not_eligible` 与 Fmax 上界；建议单锥 retime 包，不改时钟求过 |
| 测试者看到跨 run 时间重叠 | 允许其记录为 provenance 观察，但不得因此判数据无效（除非证明同一 DB 被他人改写） |
