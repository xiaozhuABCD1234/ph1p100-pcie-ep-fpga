# dev-plan — 20261027-150010_fpga-honly-td-route

规划者：本轮原规划。**本机 0 TD / 0 仿真**（仅静态核对）；用户 2026-10-27 已明确选择 **A：做成队友执行包**，接受 `AGENTS.md` “本地仅仿真、板已交队友、本机不再 TD”的新边界。
两级结构：`需求（同一 H-only 候选的 routed DB + routed STA）` → `3 个正式包`。`BATCH_SIZE=1`，每包独立开发、独立综合测试者，不跨包复用。

## 0. 本轮裁决（已定稿）

| # | 事项 | 结论 |
|---|---|---|
| 1 | 本机 TD route 执行 | **关闭**，记 `not_applicable_local_boundary`（不是工具故障、不是时序失败、不是候选缺陷） |
| 2 | 交付形态 | **T10.ah-td-route-kit**：本机写包 + 静态核对；**执行在持板队友环境** |
| 3 | 门槛 | 一分不放宽：routed WNS≥0、hold≥0、`NUM_FEPS`=0、ERAM+CWC≤300、slice≤71,680、IO≤286 + check_timing/CDC/QoR/clock_utilization/worst≥10 归因 |
| 4 | 位流/板卡 | **0 bitgen / 0 CWC / 0 下载 / 0 Flash / 0 板卡 / 0 网络**（本机与队友侧本包均 0） |
| 5 | 仓库 | `D:/fpga/repos/ph1p100-pcie-ep-fpga` 仅作**入口与落盘建议**，本包 **不写、不 commit、不 push** |
| 6 | 本轮不得出现 | “routed STA 通过 / 时序收敛 / 可实现 / Fmax”等任何无队友证据的断言；r1 的 synth `+0.029 ns` 只在注明“gate-level”时引用 |

## 1. 工作包表

| task_id | 问题/产物 | 实际工作树 / 允许写路径 | 依赖 | functional | engineering | system | 必要 G 层 | 状态 | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|
| **T10.ah-td-route-kit** | 队友可直接执行的 TD route/STA 包：冻结候选与崩溃证据 → 最小复现 → 绕行（S1 单会话零 `import_db`）→ 门槛/判定 → 证据模板与回传清单 → runbook | 仅 `workflow/runs/20261027-150010_fpga-honly-td-route/T10.ah-td-route-kit/**`；其余只读 | 无 | 静态核对：tcl 命令逐条对应 `a1_ah.tcl` 默认 flow 或 TD 文档；**不重跑 DUT 功能**（引用 synthfix `034777c5…`） | 静态一致性：路径/SHA/禁词/哨兵/exit/超时；**build·STA·资源 = not_run** | runbook 完整性：独占 preflight、配额账本、证据回传、边界声明；无板级动作 | **G2 = not_run（no local TD）**；不重跑 G0/G1（引用上轮）；G3/G4 不适用 | **ready（本次放行）** | 新建 1 个开发会话 → 冻结 manifest → 新建 1 个综合测试者 |
| **T10.ah-td-route** | 队友侧执行 S1→S2→S3→S4，取同一 DUT routed DB + routed STA + 全套报告 | **队友环境**（建议镜像 `T10.ah-td-route/att-<n>-<S>/`）；不得写本机候选/其他 run/production | kit | DUT 绑定复核（4 文件 SHA + wrapper/SDC） | routed WNS/hold/NUM_FEPS/资源/IO + 全部报告 | 无板级；工具/环境与证据链路 | G2 = 待队友执行 | **not_applicable_local_boundary**（执行通道=队友） | 队友窗口执行；回传后由本规划核门槛 |
| **T10.ah-td-route-closeout** | 收尾：判定记账、handoff/final-summary/user-summary、下一轮启动文本；**不写 `tasks.json`** | 本 run 根目录 + `test-reports/` | kit（必）/队友结果（有则并入） | 结论只引用绑定证据 | not_run/blocked 分账 | 恢复入口与负责人 | 按实际 | **blocked**（等 kit 验收） | kit PASS 后由本规划写 |

包数 3/4；两级；每包 ≤5 语义步骤；收尾不建新代理。

## 2. P1（T10.ah-td-route-kit）实现步骤（5 项，开发按此做，不得自扩）

**Step 1 — `crash-analysis.md`（冻结事实，不推测成结论）**
- 绑定表：core `d2960cfe0111b7b61aff281e3f16427834dda26107f37867d5c7c89ac346aad8` / 85,221 B；frame_top `4afc26e246fbae4e32c5ab7e88dffb496048d10966c5ee42b290b3e71f60e30a` / 29,207 B；wrapper `3e2be8ea…670c7` / 3,638 B；SDC `6d948bba…594bf` / 509 B；synthfix manifest `034777c5…e510`；TD r1 manifest `8325f230cb8581783b8e1a0ea835e33d00b8337e0dffb6a15e7d95926c8869fa`；gate DB `run-syn1/a1_ah_Runs/syn_1/a1_ah_gate.db`（**执行时按实际重算 SHA 并回填**，规划时实测 `169d5937ef274c502b0a6d0d63231cd0170bd674aac48c005c1efb13e3f045cd` / 2,324,352 B）。
- 崩溃事实：`import_db` 打印 netlist/timing/IO/Inst 后在 **`Import ChipWatcher`** coredump（1.22–1.44 s），**placement 之前**；两次同点（`run-route1`、`run-syn1`），minidump 78,531 B / 80,243 B；0 `*_pr.db`、0 routed 报告、0 bit/CWC。
- 环境事实：TD `D:/anlogic/TD_Release_2026.2` build `6.2.3.210850`（本机唯一版本，无第二套）；器件 `PH1P100SBG484` speed `-3`；top `a1_ah_eng_top`。
- 结构证据：`run-syn1/a1_ah_Runs/syn_1/a1_ah.tcl`（`stepList`、`prepare` 在 `step==3` 调 `import_db $parent/${prj}_gate.db`、`opt_rtl`/`opt_place` 调 `insert_debugger`、`bitgen` 调 `setup_debugger`）。
- 三假设与证伪：**H-run**（run-flow 亦 `import_db` → 预期复现）/ **H-single**（零 `import_db` 可绕开）/ **H-db**（debug/ChipWatcher 段触发）→ 各自对应 S2 / S1 / S4 的判别判据。

**Step 2 — 可执行脚本（不执行）**
- `att-s1/10_s1_single_session_synth_route.tcl`：单会话 `create_project`(或 `import_device`，二选一并记录) → `add_files`(3 RTL + SDC) → `top_module` → `commit_param -step design` → `elaborate` → `read_sdc` → `commit_param -step rtl` → `insert_debugger` → `optimize_rtl` → `commit_param -step gate` → `optimize_gate <area_option> <prj>_gate.area` → `legalize_phy_inst` → `update_timing` → `report_timing_status/-summary` + `flow_status -file flow.status` → `commit_param -step place` → `place` → `update_timing -mode manhattan` → `commit_param -step route` → `route` → `update_timing -mode final` → 全部 routed 报告 → `export_db <prj>_pr.db`；**禁止出现 `import_db` / `setup_debugger` / `bitgen`**；参数取自 `run-syn1/…/settings.cfg` 与 `a1_ah.prj`；附“命令↔默认 flow 行号”映射表。
- `att-s2/20_s2_run_flow_route.tcl`：`open_project ./a1_ah.al` + `launch_runs { phy_1 } -jobs 4` + `wait_run phy_1 -quiet`，**不手写 import_db**（诊断用，预期可能复现崩溃，须保存 `a1_ah_Runs/phy_1/*` 与 minidump）。
- `att-s3/minimal_repro/`：2 文件极小设计（如 8-bit LFSR，同器件同 wrapper 风格）+ `31_s3a_synth.tcl`/`31_s3b_import.tcl`（综合→导出 gate DB→**新会话** `import_db`），用于 H-db/H-version 判别；**S3 必须先于任何版本变更/重装**。
- 全部脚本：绝对路径、cwd 注释、哨兵默认值（`-99.0`/`-1`/`n/a`）、结构化 `AH_*` 标记、缺报告 `exit 1`、无交互、无 `pause`。

**Step 3 — 判定/配额/执行说明**
- `acceptance-checklist.md`：门槛表（同上）+ 必备报告（timing_summary/timing_status/timing、check_timing（fallback `report_check_timing` 并写明用的是哪个）、CDC、QoR、clock_utilization、area -io_info、flow.status、routed DB SHA+字节、4 源文件 SHA、TD build、run dir、console、0 bit/0 CWC）+ 判定写法（`eligible_for_next_stage` / `not_eligible`+真实数字 / `not_evaluated`）与“工具崩溃≠时序失败”规则；209.6 仅 analysis-only 且标 `not_a_routed_209.6MHz_result`。
- `quota-ledger.md`：TD 启动 ≤3、synth ≤1、route ≤2（第 2 次须写参数差异，禁 seed 扫描）、analysis-only ≤1、bitgen 0；单次 synth ≤1800 s、route ≤2400 s、analysis ≤600 s；preflight（0 TD 进程且独占窗口）、单席位冲突（`RUN-8008`/`PRJ-5303`/`PRJ-8806`）= `TOOL_UNAVAILABLE` 不重试。
- `teammate-runbook.md`：逐步命令、cwd、版本核对、每次 attempt 目录、必须回传文件、Windows SHA256 计算方法（`Get-FileHash -Algorithm SHA256` / `certutil -hashfile`）、回传后本规划判定入口。

**Step 4 — 证据模板与回传清单**
- `evidence-templates/result-att-<n>.md`（首行唯一判定行、attempt/参数差异、环境、全部数字带报告出处、偏离声明）、`manifest-att-<n>.json`（artifacts+sha256+bytes+`stopped_modifying`）、`return-bundle.md`（必须回传：脚本副本、console、flow.status、routed 报告全套、pr DB 的 SHA/字节、源文件 SHA、minidump（若崩）、0 bit/0 CWC 声明）。

**Step 5 — 静态自检 + 冻结**
- `hash-bindings.json`：本机重算 4 源文件 + gate DB + 两份 manifest 的 SHA 与字节；脚本路径存在性；禁词扫描（`import_db` 只允许出现在 S2/S3 的说明与 S1 的“禁止”注释、`bitgen`/`setup_debugger` 仅允许出现在禁止声明、`add_false_path`/`set_multicycle_path`/`create_clock` 仅允许在引用 SDC 的说明）；`exit` 语义逐一核对；**全程不启动 TD、不跑仿真**。
- `manifest-r0.json` + `result-r0.md` + `handoff.md`，明确写“本包 G2 = not_run，不构成时序/实现结论”。

## 3. 综合测试者（P1）核验清单

包完整性（用户 6 项内容齐备）、候选/门 DB/manifest SHA 与 `input-index.md` 一致、脚本可执行性（命令↔flow 映射、绝对路径、cwd、超时、哨兵、exit）、**S1 内零 `import_db`**、门槛与 209.6 口径与 `fpga-design-guide.md` §5 完全一致、回传清单可操作、**证据证明本机 0 TD / 0 仿真**（无 TD 日志/进程/新 DB，开发报告声明与文件时间线一致）、边界声明齐备（不 push/不写主仓/不改候选/RTL/SDC/时钟/例外）、无越界写入（manifest 路径全在允许范围）。测试者**不得**声称 routed 时序结论。

## 4. 配额、时间与停止条件（冻结）

| 角色/阶段 | 预算 |
|---|---|
| P1 开发 | ≤45 min / ≤30 calls；**本机 0 TD、0 仿真**；单文件读/搜 ≤60 s |
| P1 综合测试 | ≤45 min / ≤30 calls；不重跑 TD、不改 kit |
| 本 run 总墙钟 | ≤2.5 h（含规划收尾）；超时即 blocked 交原规划 |
| 队友侧（P2） | TD 启动 ≤3、synth ≤1、route ≤2、analysis ≤1、bitgen 0；synth ≤1800 s、route ≤2400 s、analysis ≤600 s |
| 本规划复核 P2 | ≤30 min / ≤30 calls（只读报告与 SHA） |
| 修复轮 | round0 首次验收 + ≤3 轮实际修复；同任务同输入不重复消耗 |

停止条件（任一即停并 blocked，写原因/已做未做/最后证据路径/最小下一步）：需改 RTL/SDC/时钟/例外/候选才能过；需本机启动 TD；工具/时间预算耗尽；连续 2 次无新证据；需写主仓或 push。
回退：P1 未达 → `blocked=NO_PROGRESS`，不派 P2；P2 全失败 → 候选止步 gate-level（`implementation not evaluated (tool defect)`），回退上轮 `dual-verdict.md` 的限定，不重开 A/H 方案。

## 5. 保护范围（只读）

`RTL/SDC/时钟/周期/例外/候选`、`20261027-055621_fpga-honly-td-and-ah/**`、b18–b20、integrated delivery、board-integration、旧 P1–P4、生产源 `fpga/**`、`workflow/tasks.json`、`docs/**`、`workflow/**`（任务板/records）、`.agents/**`、`D:/fpga/repos/**`、`D:/TD/work/csi2`、`D:/anlogic/**`（除只读文档）。禁 batch delete、commit/push、bitgen/下载/Flash/板卡/网络/外部消息。

## 6. 后续主题（本轮不做，≤3）

1. 队友回传后的实现资格判定与 G2 记账（本 run 收尾）。
2. TD 版本获取/重装：仅当 S3 证明版本级缺陷且用户批准（含来源与回滚）。
3. H-only 候选迁移权威主仓的 diff 评审与落库（另轮授权；本包仅给落盘建议）。
