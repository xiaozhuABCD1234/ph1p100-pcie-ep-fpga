# input-index — 20261027-150010_fpga-honly-td-route

本轮只做规划理解/拆分/派发；0 TD、0 仿真、0 改动任何候选或其他 run。本文件列准确输入路径、采用版本、哈希与未决项。

## 0. 权威顺序（本轮适用）

| 序 | 来源 | 本轮含义 |
|---|---|---|
| 1 | `D:/fpga/ph1p100/AGENTS.md`（**2026-10-27 更新段**） | **本地不再启动 TD 综合/P&R/STA/bitgen/CWC/COM/JTAG/下载/Flash**；板已交队友；本地只留仿真、静态核对、源码/测试/证据整理与已授权主仓同步。原文：“此边界优先于本文件下方及旧 run 中历史 TD/板卡额度”。 |
| 2 | 本 run `request.md`（用户原话“先做1”） | 要求**本地**绕开 TD 崩溃拿 routed DB + routed STA；含 TD 配额（启动≤3/synth≤1/route≤2/analysis≤1/bitgen 0）。 |
| 3 | 上轮 `20261027-055621_fpga-honly-td-and-ah/{dual-verdict.md,r2-ruling.md}` | 上轮事实、门槛、租约 v2 规则与候选状态。 |

**冲突裁决（本规划）**：`AGENTS.md` 第 1 条优先 → 本轮**不在本地执行** TD route；请求中“本地 routed STA”降级为**队友执行包**（P2，blocked）。配额数字保留为队友侧上限与本 run 记账口径，不因边界变化而放宽任何门槛。请求中“不写 `D:/fpga/repos/...`”与 AGENTS“后续成果以该仓为工作根”不冲突：**本轮写范围仍限本 run**，主仓同步需另轮授权。

## 1. 需求与背景

| 项 | 路径 |
|---|---|
| 用户原话 + 本轮边界 | `workflow/runs/20261027-150010_fpga-honly-td-route/request.md` |
| 上轮合并判定 | `workflow/runs/20261027-055621_fpga-honly-td-and-ah/dual-verdict.md` |
| 上轮 TD 放行/租约/门槛 | `.../20261027-055621_fpga-honly-td-and-ah/r2-ruling.md` §2、§3 |
| 上轮用户摘要（启动文本） | `.../20261027-055621_fpga-honly-td-and-ah/user-summary.md` |

本轮要回答的 5 个问题（request §本轮目标）未变，只是**执行位置**从本地改为持板队友。

## 2. 候选绑定（冻结、只读，本轮与后续 kit 均按此）

| 角色 | 路径（相对 `workflow/runs/`） | SHA-256（本轮实测复核） | 字节 |
|---|---|---|---|
| core（synthfix 版） | `20261027-055621_fpga-honly-td-and-ah/T10.ah-honly-synthfix/r0/changed-src/a1_deflate_core.v` | `d2960cfe0111b7b61aff281e3f16427834dda26107f37867d5c7c89ac346aad8` | 85,221 |
| frame_top | `.../T10.ah-honly-synthfix/r0/changed-src/a1_frame_top.v` | `4afc26e246fbae4e32c5ab7e88dffb496048d10966c5ee42b290b3e71f60e30a` | 29,207 |
| build-only wrapper（**非候选**） | `.../T10.ah-honly-td/r1/td/a1_ah_eng_top.v` | `3e2be8eaf88fc1196d1565de19d6ca41b35e85470f3bbd9271af5067526670c7` | 3,638 |
| SDC（单时钟 5.333 ns，无例外） | `.../T10.ah-honly-td/r1/td/a1_ah_small_top.sdc` | `6d948bba2087d1b86e772ef4a05486b261c2ddb445950739701bdcc0655b94bf` | 509 |
| gate DB（r1 综合产物） | `.../T10.ah-honly-td/r1/td/run-syn1/a1_ah_Runs/syn_1/a1_ah_gate.db` | `169d5937ef274c502b0a6d0d63231cd0170bd674aac48c005c1efb13e3f045cd` | 2,324,352 |
| r1 manifest（83 artifacts） | `.../T10.ah-honly-td/r1/manifest-r1.json` | `8325f230cb8581783b8e1a0ea835e33d00b8337e0dffb6a15e7d95926c8869fa` | 35,875 |
| synthfix manifest | `.../T10.ah-honly-synthfix/r0/manifest-r0.json` | `034777c5`（上轮 r2-ruling 记录，本轮未重算） | — |

绑定规则：任何后续 routed 结论必须同时绑定上表 RTL/SDC/wrapper 哈希 + 实际用于 route 的 DB 哈希；**换 RTL/SDC/时钟/例外/候选 = 作废**。

## 3. 工具与环境（只读事实）

| 项 | 值 | 来源 |
|---|---|---|
| TD 安装 | `D:/anlogic/TD_Release_2026.2`（`D:/anlogic` 下**仅此一个版本**，无第二套可切换） | 本轮目录列举 |
| TD build | `6.2.3.210850`，Built `11:35:58 Aug 19 2026` | `run-syn1/route_console.log` 头 |
| 器件 | `PH1P100SBG484` speed `-3`，top `a1_ah_eng_top` | `01_synth.tcl`、`a1_ah.al` |
| 崩溃点 | `import_db ./a1_ah_Runs/syn_1/a1_ah_gate.db` → `Import ChipWatcher` → coredump，**placement 之前** | `run-syn1/route_console.log` L61-70、`run-route1/route_console.log` 同 |
| minidump | `run-route1/minidump-20261027-093503.dmp`（78,531 B）、`run-syn1/minidump-20261027-093540.dmp`（80,243 B） | 上轮 dual-verdict §2.3 |
| 无 routed 产物 | 0 `*_pr.db`、0 `routed_*.rpt`、0 QoR/check_timing/CDC、0 bit/CWC | 本轮目录列举 + 上轮报告 |
| 默认流程脚本（关键证据） | `run-syn1/a1_ah_Runs/syn_1/a1_ah.tcl`：`stepList {read_design opt_rtl opt_gate opt_place opt_route bitgen}`；`prepare` 在 **step==3（opt_place）** 时执行 `import_db $parent/${prj}_gate.db`；`opt_rtl`/`opt_place` 调 `insert_debugger`，`bitgen` 调 `setup_debugger` | 本轮直读 L45-73、L140-143、L190-192、L263-266 |
| 运行参数来源 | `run-syn1/a1_ah_Runs/syn_1/{settings.cfg,a1_ah.prj}`（复现参数须以此为准） | 目录列举 |

**推论（写进 design-guide，供 dev 验证）**：项目 run-flow 的 `phy_1` 也会在 `prepare(3)` 调 `import_db <parent>/a1_ah_gate.db`，因此“只改用 `open_project + launch_runs phy_1`”**很可能复现同一崩溃**；真正绕过 DB 往返的路径是**单会话 synth→place→route（全程不 import_db）**。

## 4. TD 占用实测（规划时点，仅作 provenance，不构成本轮动作）

| 检查（`2026-10-27T15:05:52+08:00`） | 结果 |
|---|---|
| TD 进程（pnmain/td/td_commands_prompt/tdsynth/td_phy/td_gui） | **0** |
| `INT.P4/td`（`.../20261026-2138_fpga-integrated-delivery/INT.P4/td`） | 最新写 06:07:52 → **≈538 min 静默** |
| `INT.P4/r3` | 06:08:17 → ≈537 min |
| `20261027-0726_fpga-board-integration/T11.BRD.P1/td` | 08:18:30 → ≈407 min |
| `20261026-2138_fpga-integrated-delivery` 整体 | 06:53:54 → ≈492 min |
| `T:` | 存在，**未 remap/未 -Force**（未被本 run 触碰） |

结论：规划时 TD 物理空闲；本轮 blocked 的原因是 **AGENTS 新边界**，不是占用。

## 5. 已有成果（只读，不得改写）

- 上轮 4 包：A（kill_verified）、synthfix（PASS）、honly-td（r1 blocked=TOOL_UNAVAILABLE）、dual-verdict（合并判定）。
- 候选状态：**H-only synthfix 版 = 唯一候选、临时状态、实现资格 not_evaluated**。
- 上轮测试报告：`test-reports/T10.ah-honly-td-r1-integrated.md`（G2=blocked，synth pass/routed blocked/analysis not_run）。

## 6. 已决 / 未决

**已决（2026-10-27，用户明确选择 A）**：
1. 本轮目标降级为**“队友执行包”**（`T10.ah-td-route-kit`；本机 **0 TD**）；本机 TD route 执行记 `not_applicable_local_boundary`，不再作为待办。见 `question-01.md`（已标记确认）与 `dispatch.json`。

**仍未决（不阻塞 P1）**：
2. 若用户后续恢复本机 TD 权限，需**新的一次明确授权**（本轮配额 3/1/2/1/0 不自动结转）。
3. TD 版本切换/重装：`D:/anlogic` 无第二版本；任何重装须先最小复现（S3）+ 用户批准（request 已写此前提）。
4. 主仓 `D:/fpga/repos/ph1p100-pcie-ep-fpga`：本包只作**入口与落盘建议**，不写/不 commit/不 push；落库属另轮主题。

