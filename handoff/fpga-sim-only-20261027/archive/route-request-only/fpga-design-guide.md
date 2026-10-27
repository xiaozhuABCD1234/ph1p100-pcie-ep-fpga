# fpga-design-guide — T10.ah-td-route（TD route 绕行 / 队友执行包）

冻结本任务的 DUT 绑定、工具流程、崩溃契约、绕行阶梯、验收门槛与证据约定。**本文件不改 RTL/SDC/时钟/例外/候选，也不授权本机 TD**。

## 0. 执行边界（2026-10-27 覆盖，最高优先级）

| 侧 | 允许 | 禁止 |
|---|---|---|
| **本机（本 run）** | RTL 仿真/编译、静态核对、源码与证据整理、写本 run 文档与 tcl **脚本**（不执行） | 启动 TD 综合/布局布线/STA/bitgen/CWC/COM/JTAG/下载/Flash；续跑旧 TD/板级任务 |
| **持板队友环境** | 按本指南执行 TD synth/route/STA（含 bitgen 与否由其任务决定，本包仍 **bitgen 0**） | 改 RTL/SDC/时钟/例外/候选；QoR seed 扫描；放宽门槛 |

因此本包在**本机**的唯一可交付物是“可被队友直接执行的绕行包 + 冻结的判定表”；`G2(route/STA) = not_run` 直到队友返回证据。

## 1. DUT 绑定（冻结、只读、逐字节）

| 项 | 值 |
|---|---|
| core | `a1_deflate_core.v` `d2960cfe0111b7b61aff281e3f16427834dda26107f37867d5c7c89ac346aad8` (85,221 B) |
| frame_top | `a1_frame_top.v` `4afc26e246fbae4e32c5ab7e88dffb496048d10966c5ee42b290b3e71f60e30a` (29,207 B) |
| wrapper（build-only，**非候选**） | `a1_ah_eng_top.v` `3e2be8ea…670c7` (3,638 B) |
| SDC | `a1_ah_small_top.sdc` `6d948bba…594bf` (509 B)，`create_clock -name clk -period 5.333 -waveform {0.000 2.667}`，**无 false_path/multicycle/clock group/IO 约束** |
| 器件/顶 | `PH1P100SBG484` speed `-3`；top `a1_ah_eng_top` |
| 绝对路径 | 全部在 `D:/fpga/ph1p100/workflow/runs/20261027-055621_fpga-honly-td-and-ah/…`（见 input-index §2）；**只读**，不得复制改名后冒充 |

任何一行的 SHA 变化 = 结论作废，必须重新绑定。队友机器上执行前**先重算 4 个源文件 SHA** 并写进结果。

## 2. 工具/流程契约

| 项 | 约定 |
|---|---|
| TD | `D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe`，build `6.2.3.210850`（本机唯一版本） |
| 项目/库/日志位置 | 全部在**新 run 目录**（`…/20261027-150010_fpga-honly-td-route/T10.ah-td-route/`），不复用他 run 的 work 库；每 attempt 独立子目录 |
| 参数复现 | run 参数以 `…/T10.ah-honly-td/r1/td/run-syn1/a1_ah_Runs/syn_1/{settings.cfg,a1_ah.prj}` 为准（Default_Synthesis_Strategy / Default_PhysicalDesign_Strategy，无 seed、无 speedup 覆盖） |
| 阻塞语义 | 单席位冲突（`RUN-8008`/`PRJ-5303`/`PRJ-8806`）→ `TOOL_UNAVAILABLE`，不重试、不共享、不 kill 他人进程；**不得**记成 DUT 缺陷 |
| `T:` | 不 remap、不 `-Force`；脚本全绝对路径 |
| 配额（队友侧，冻结） | TD 启动 ≤3、synth ≤1、route ≤2（第 2 次须写明与第 1 次的参数差异，禁 seed 扫描）、analysis-only ≤1、**bitgen 0**、download/Flash/board 0 |
| 超时（冻结） | 单次 synth ≤1800 s、route ≤2400 s、analysis ≤600 s；启动前落实可终止机制 |
| 崩溃复现 | 同一 gate DB 同一 `import_db` 崩溃重复出现即算“复现”；两次 console 只允许 Run Date/minidump 名不同 |

## 3. 崩溃契约（已知事实 + 待验证假设）

**已知**：`import_db <gate.db>` 打印 `Import netlist/timing constraints/IO constraints/Inst constraints` 后，在 **`Import ChipWatcher`** 处 coredump（1.22–1.44 s），发生在 placement 之前；两次（`run-route1`、`run-syn1`）同点崩溃，各留 minidump。

**关键结构事实（本轮新读，dev 必须验证）**：TD 生成的默认 flow 脚本 `…/run-syn1/a1_ah_Runs/syn_1/a1_ah.tcl` 中
- `stepList = {read_design opt_rtl opt_gate opt_place opt_route bitgen}`；
- `prepare` 在 `step == 3`（`opt_place`）执行 `import_db $parent/${prj}_gate.db`；
- `opt_rtl`、`opt_place` 调 `insert_debugger`；`bitgen` 调 `setup_debugger`。

⇒ **假设 H-run**：`open_project + launch_runs phy_1`（run-flow）同样会 `import_db` 同一个 gate DB，**预期复现崩溃**（不是有效绕行，只能作为诊断）。
⇒ **假设 H-single**：**单会话**（elaborate→opt_rtl→opt_gate→place→route）全程**不执行 `import_db`**，可完全避开崩溃代码路径。
⇒ **假设 H-db**：崩溃与该 gate DB 中的 debug/ChipWatcher 段有关（`insert_debugger` 写入）；若导出前不插 debugger 或导入时跳过该段，可绕过。

## 4. 绕行阶梯（冻结顺序；每次尝试必须记录“与上次的参数差异”）

**S1（首选，1 次 TD 启动，消耗 synth 1 + route 1）— 单会话 synth→place→route，零 `import_db`**
按 `a1_ah.tcl` 的可编辑区语义复刻为**一个** tcl：`create_project`（或 `import_device ph1_100p.db -package PH1P100SBG484 -speed 3`，二选一记录）→ `add_files`(3 RTL + SDC) → `top_module a1_ah_eng_top` → `commit_param -step design` → `elaborate` → `read_sdc` → `commit_param -step rtl` → `insert_debugger` → `optimize_rtl` → `commit_param -step gate` → `optimize_gate <area_option> <prj>_gate.area` → `legalize_phy_inst` → `update_timing` → `report_timing_status/-summary` + `flow_status -file flow.status` → `commit_param -step place` → `place` → `update_timing -mode manhattan` → `commit_param -step route` → `route` → `update_timing -mode final` → 全套 routed 报告（见 §5）→ `export_db <prj>_pr.db`。
禁止出现：`import_db`、`setup_debugger`、`bitgen`、`read_adc`、任何 false_path/multicycle/新增 clock。
偏离说明（必须写进结果）：本路径不经 run-flow 的 DB 往返；synth 统计可能与 r1 gate 值（SWNS +0.029/coverage 97.06%/ERAM 27/slice 3,337）不同，**两者都要报**，不得用 r1 synth 数字冒充 S1 synth 数字。

**S2（仅当 S1 未产生 routed DB；1 次启动，0 synth + 1 route）— run-flow 诊断**
复制 r1 项目（`a1_ah.al` + `a1_ah_Runs/syn_1/`）到新目录，`open_project ./a1_ah.al` + `launch_runs { phy_1 } -jobs 4` + `wait_run phy_1 -quiet`，**不手写 import_db**。目的：判定崩溃是发生在 TD 自身 flow 还是我们脚本路径；必须保存 `a1_ah_Runs/phy_1/*` 日志与 minidump。

**S3（诊断，1 次启动；**必须先于**任何版本变更）— 最小复现**
2 文件极小设计（如 8-bit LFSR/计数器 + 同 wrapper 风格顶层，同器件）走同一“综合→导出 gate DB→**新会话** `import_db`”循环：
- 若同样崩 → **版本/工具级缺陷**，与 DUT 无关；此时才可讨论换版本/重装（须用户批准 + 记录安装来源）。
- 若不崩 → 与本 DUT 的 debug/DB 内容相关 → 走 S4。

**S4（最后手段）— 去掉 debug 负载**
① 在 run tcl 可编辑区跳过 `insert_debugger`（gate DB 不含 debug hub）后再导入；② 若 TD 提供 `import_db` 的跳过/删除 debug 选项（须先在离线文档 `doc/SWUG/SWUG105_TCL_Command_User_Guide.pdf`、`doc/release_note.pdf` 中确证，不得凭猜测试参数），按文档使用。
偏离说明：不插 debug hub 属实现形态偏离（**不是** RTL/SDC 改动），结论须标 “routed without default debug hub, 0 CWC/0 bitgen”。

**不做**：seed 扫描、QoR strategy 换挡求过、改时钟/加例外/加 IO 约束、换更简单 DUT 冒充、GUI 手工绕行代替可复现脚本（GUI 仅可作最后诊断，须截图+日志）。

## 5. 验收门槛与必备报告（冻结，不放宽）

| 门槛 | 值 |
|---|---|
| routed setup WNS | ≥ 0 ns（5.333 ns / 187.5 MHz，单时钟） |
| routed hold | WNS ≥ 0，且 `NUM_FEPS`(hold) = 0 |
| `flow.status` | `Setup: … NUM_FEPS = 0` |
| 存储 | ERAM + CWC ≤ 300 |
| 逻辑 | slice ≤ 71,680 |
| IO | ≤ 286 |
| 209.6（可选） | **analysis-only**，显式标 `not_a_routed_209.6MHz_result` |

必备报告（缺一即 FAIL）：
1. `routed_timing_summary.rpt`、`routed_timing_status.rpt`、`routed_timing.rpt`（worst ≥10 条路径，逐条给出 start/end 与归因类别：**frame_top 双 CRC32 / core replay-emit / scan**）；
2. `routed_check_timing.rpt`（`check_timing -verbose`，或 fallback `report_check_timing` 并写明用的哪一个）；
3. `routed_cdc.rpt`（单时钟设计仍要出这份证据；空结果=0 CDC 违例，须带报告不是口头声明）；
4. `routed_qor.rpt`（`report_qor -step route`）、`routed_clock_utilization.rpt`；
5. `routed_area.rpt`（`report_area -io_info`，取 `#IO/#eram/#fifo20k/#reg/#slice*/#dsp`）；
6. `flow.status`（route 步）与 `route_flow.status`（若有）；
7. routed DB `a1_ah_pr.db` 的 SHA-256 + 字节数、所用 gate DB SHA、4 个源文件 SHA、TD build、run dir 绝对路径、完整 console log、0 bit/0 CWC 声明。

判定写法：全部满足 → `eligible_for_next_stage=true`；任一不满足 → `not_eligible` + 真实数字 + 失败类别（时序 vs 工具）；**工具崩溃/未产出 = `not_evaluated`，不得写成时序失败**。

## 6. 证据与结果约定

- 每 attempt 独立目录 `T10.ah-td-route/att-<n>-<S1|S2|S3|S4>/`，内含脚本副本、console、TD 日志、全部报告、`result-att-<n>.md`。
- 结果文档首行唯一判定行；所有数字须给出报告文件名行号或原句，禁止“约/较好”。
- 默认值用哨兵（`-99.0`/`-1`/`n/a`）并打印结构化 `AH_*` 标记，缺报告必须 `exit 1`。
- 冻结后写 `manifest-r<n>.json`（artifacts+sha256+字节），`stopped_modifying=true`；同轮修复须新 manifest，不拼不同输入。
- 复用上轮证据只能“引用绑定”，不得把 r1 的 synth 数字当作 routed 数字。

## 7. 已冻结 / 待确认 / 不适用

| 状态 | 内容 |
|---|---|
| **已冻结** | DUT 4 文件哈希；TD build；器件/顶；单时钟 5.333 ns 无例外；S1→S2→S3→S4 顺序；门槛表；必备报告；配额与超时；本机 0 TD |
| **待确认（用户）** | 本轮是否以“队友执行包”为交付（`question-01.md`）；队友是否具备同版本 TD；若需换版本/重装的批准与来源 |
| **待验证（队友）** | H-run / H-single / H-db 三假设；S1 的 synth 统计是否与 r1 一致；崩溃是否随 DB 走 |
| **不适用** | 本机 G2（route/STA）=`not_run`；G3/G4 位流与板级=不适用（bitgen 0）；RK/PCIe/双路/算法功能=不在本任务范围（功能已由 synthfix manifest 034777c5 冻结，引用不重跑） |

三维边界（本包）：**functional** 只做“脚本语义 vs 默认 flow 的静态映射核对”，不重跑 DUT 功能（理由：无 DUT 执行，功能结论引用上轮冻结证据）；**engineering** 只做静态一致性（路径/哈希/命令白名单/哨兵/超时），build/STA/资源 = `not_run`；**system** 只核 runbook 完整性（独占与 preflight、配额、证据回收清单），无板级动作。

## 8. 交付形态（2026-10-27 用户确认“队友执行包”后追加）

**包名**：`T10.ah-td-route-kit`。**本机只写不跑**；执行方 = 持板队友。

**包内必须齐备的 6 项**（tester 逐项核）：
1. 冻结候选与证据绑定（4 源文件 + gate DB + 两个 manifest 的 SHA/字节，执行时重算回填）；
2. 最小复现步骤 + 已知崩溃（TD `6.2.3.210850`、`import_db → Import ChipWatcher` coredump、两次 minidump、0 `pr.db`、placement 之前）；
3. 绕行方案（**S1 单会话 synth→place→route、全程零 `import_db`**；S2 run-flow 诊断；S3 最小复现；S4 去 debug 负载），含命令/cwd/环境/版本/超时；
4. 门槛表（routed WNS≥0、hold≥0、`NUM_FEPS`=0、ERAM+CWC≤300、slice≤71,680、IO≤286；check_timing/CDC/QoR/clock_utilization/worst≥10 归因；209.6 仅 analysis-only；**0 bitgen/0 板卡**）；
5. 证据模板 + 回传清单（`flow.status`、routed timing/status/timing、area、QoR、check_timing、CDC、clock_utilization、路径归因、routed DB SHA/字节、console、命令日志、manifest）；
6. 边界声明：**本机 0 TD**；队友环境执行；**不改 RTL/SDC/时钟/例外/候选、不 QoR seed 扫描、不 push/不 commit**。

**仓库边界**：`D:/fpga/repos/ph1p100-pcie-ep-fpga` 在本包中**只作入口与落盘建议**（例如未来把 kit/handoff 放 `docs/` 或 `workflow/` 的建议路径），**不写、不 commit、不 push**；落库是另轮授权主题。

**禁止的表述**：本包交付、甚至队友回传前，任何“routed STA 通过 / 时序收敛 / 可实现 / 真实 Fmax / 可上板”的断言。r1 的 `+0.029 ns` 只能写作“gate-level 综合，非布线结果”。
