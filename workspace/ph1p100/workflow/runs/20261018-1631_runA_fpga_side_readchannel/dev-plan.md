# dev-plan.md — 20261018-1631_runA_fpga_side_readchannel（v1.1）

原规划者编写（2026-10-18）。batch=1；1 主要可验收目标；4 正式包；两级（需求→工作包）；每任务新开发 + 一个独立综合测试者。依据：`request.md`（用户拍板）、上一 run `next-round-proposal.md`（P0—P3）、`handoff.md`、`board-selfcheck/channel-notes.md`、KIT `registers-plan.md`；冻结接口见本 run `fpga-design-guide.md`。

**v1.1 更新（2026-10-18）**：`T11.runB-debug-spec` round0 integrated **PASS**（报告 `test-reports/T11.runB-debug-spec-r0-integrated.md`；manifest `b806b2a4…b173`；上游 HEAD=`c89ab758…`、零写入）→ 按计划派发 `T11.runB-debug-rtl`（P1，本次派发）。P1 实现以 `debug-spec/` 冻结件为准：`probe-map.md`（字库 0x140..0x160 九字/288 bit、单实例 tl_clk_user、降级路径与顺延规则）、`enable-state.md`（CTRL 最小 debug-only 开启草案）、`cwc-flow.md`（CWC 判定条件）、`readback-criteria.md`/`board-runbook.md`（供 P2/P3）。

**v1.2 更新（2026-10-18）**：`T11.runB-debug-rtl` 返回 **blocked（仅交付收尾缺项）**——实现/局部检查/8 TB 回归/新 TB/冻结已按计划完成；7 个候选文件已 staged 于上游 index（`rtl/ep_side/debug/ph1p_pcie_ep_top_dbg.v`、`rtl/ep_side/img/ep_bar_win.v`、`rtl/ep_side/pcie_ep_engine.v`、`rtl/ep_side/ph1p_pcie_ep_top.v`、`sim/tb/tb_ep_bar_win_debug.v`、`sim/compile_checked.f`、`tools/pcie_integration/td/00_all_debug.tcl`；HEAD 仍 `c89ab758…`，`git diff --cached --stat`=7 files/619+/6-），仅 `git commit` 被会话级 shell 权限拒绝（manifest `commit_sha=null`、`commit_status=BLOCKED`；problem=`T11.runB-debug-rtl:PERMISSION_MISSING:git-commit`）；过程调用 ≈59（>30 已如实登记）。**处置（参照上一 run `T11.runA-readback-checker` 先例）**：原规划批准**一次有界补收**（同 task_id、新开发会话；仅暂存候选复核 + `git commit`（不推送）+ SHA 回填 manifest + 补收记录；≤15 min/≤20 calls）；**再遇权限拒绝即停止、blocked 接受**并交原规划备条件。本包**不标 PASS**；补收 ready_for_test 后才新建综合测试者。

**v1.3 更新（2026-10-18）**：有界补收**再次被工具权限层拒绝**（同一 problem_id=`T11.runB-debug-rtl:PERMISSION_MISSING:git-commit`、`new_information=false`；补收复核全通过：HEAD=`c89ab758…`、7 文件/619+/6- staged 与 manifest 逐条 SHA 相等、无未暂存/未跟踪改动；唯一一次 `git commit` 未执行、未产生 commit、index 完整）。**处置**：本包记为 **blocked-pending-external（git commit 权限）**——属交付收尾外部阻塞，**未消耗修复轮**（round0 未开始，非 FAIL）；同 new_information=false 问题**不再派补收**。**解锁条件（二选一）**：①用户（现场）在 upstream 检出手动执行一次 commit（精确命令/验证方法见本 run `user-request-commit.md`）并把输出回传；②环境放行 shell `git commit` 权限后由原规划派同 task_id 有界续收。**恢复入口**：用户回话后交原规划——commit 已完成→复核并回填 manifest→ready_for_test→综合测试者；已放行权限→派同 task_id 续收（仅 commit+回填）。P2（`T11.runB-debug-build`）明确 **blocked-by-order（父 commit 缺失）**。

**v1.4 更新（2026-10-18）**：用户按选项 A 手动完成 commit（截图原样存 `user-input-04.md`；短 SHA `8e1ef05`）；原规划只读核对通过——**HEAD=`8e1ef05f12831e94311c6cc593090198b0e258fc`**、parent=`c89ab758…`、subject 一致、7 files/619+/6-、工作树 clean、未推送。原规划已回填 `debug-rtl/candidate-manifest.json`（commit_sha/commit_status=COMMITTED；其余字段与冻结件未动，回填本身记于 manifest notes 与 dev-notes §8）→ 本包置 **ready_for_test**，交本 run 原综合测试者出 r0 integrated 报告（sessionID=`ses_eb1c0a458ffeT2bv7TnR2Cd1SQ`，由主续接）。用户告知后续开放 shell git 权限（登记在案，用于后续包；不改变不推送口径）。P2 仍 blocked-by-order（待本包 r0 收束）。

**v1.5 更新（2026-10-18）**：`T11.runB-debug-rtl` **PASS（r1，integrated）**——r0 唯一 FAIL=原规划回填后 `run_files[dev-notes]` 哈希过期（规划侧记录漂移，非 RTL 问题），原开发刷新后 r1 复测：新 manifest `305aec10…`/18,954 B、39/39 一致、候选 7 文件与 27 条日志哈希=r0（未变）、HEAD=`8e1ef05f…`、worktree clean；G0/G1=pass；实际修复轮=1。原规划独立复核：manifest 自哈希、dev-notes 哈希（`a35086fa…`）、HEAD/clean 均一致。→ 派发 P2 `T11.runB-debug-build`（本次派发）：TD 单会话 ≤30 min×≤2、`00_all_debug` 构建、`setup_debugger`+CWC 映射校验、G2（SWNS/STNS/HWNS≥0、0 违例、资源、bit/DB/报告同源绑定）、新 bit 与 `e81d353b…` 并列；**不下载上板**。git 权限：P2 不需要上游新 commit（RTL/构建入口冻结于 `8e1ef05f`）；如确需 commit 且被拒→不阻塞位流/manifest 冻结，按先例交原规划/用户。测试者：新任务按规则新建综合测试者出 r0 报告。

**v1.6 更新（2026-10-18，P2 blocked 范围裁定）**：`T11.runB-debug-build` 返回 blocked（problem=`T11.runB-debug-build:SCOPE_CLARIFICATION:debug-wrapper-sdc-cwc`，new_information=true）：构建 exit=0/637 s/Routed，但 **G2 FAIL**（SWNS −4.293 / STNS −488.545 / HWNS −3.456 ns；882 setup + 400 hold failing endpoints；相机域 clk2 −1.925 / clk3 −1.757 ns）——根因=P1 debug wrapper 新增 `u_top` 层级，使生产 SDC 的 `u_pcie_pll_ep/…`、`u_csi_a/…` 等对象失配（rename/generated clock/clock groups 静默失败，run.log L170–189）；且 RTL 无 mark_debug/CWC IP → `insert_debugger` KIT-2501、`setup_debugger` 未产出 `cw/compiled.cwc|bit`。产物 bit `AFFC4396…`=**NOT READY 不可上板**（保留为证据，不删除、不下载）。**裁定：走 ②+③**——② 保留 wrapper（P1 RTL 与已验证的参数覆盖不变），新增**debug 专用 SDC 变体**（生产 SDC 一字不动；仅对层级对象加 `u_top/` 前缀、语义逐条等价），并加 **fail-closed 解析校验**（对象全命中/时钟表与基线一致/组数一致/无新增未约束端点，任一失败即停，不得靠静默通过）；③ CWC 走 **TD 真实流程**（先 ≤10 次只读证据判定 `mark_debug`+`insert_debugger` 或 ChipWatcher IP 哪条受支持，再接入 dbg_bank 9 字/288 bit，`setup_debugger` 产物 + `check_chipwatcher_readback.py` 0 失败）。不选 ①（去掉层级）：需未经验证的合成 define/顶层参数覆盖机制且会改动生产顶层，静默失败风险更高。**包结构不变（4 包）**：本修补作为 `T11.runB-debug-rtl` 的**续修（P1-fix，同 task_id）**派发，含 1 次验证构建（≤30 min；失败且有新证据可第 2 次）；`T11.runB-debug-build`（P2）维持 blocked-by-order，待 P1-fix 收束后恢复——**优先复用 P1-fix 的验证构建产物，不默认重建**（两包合计构建 ≤2 次）。G2 门槛不因修补放宽。

**v1.7 更新（2026-10-18，CWC 校验裁定）**：P1-fix 返回 blocked（problem=`T11.runB-debug-rtl:CWC_VALIDATOR:BID_WIDTH_MISMATCH`，new_information=true）：**G2 已 PASS**（SWNS 0.139 / STNS 0.000 / HWNS 0.020 / HTNS 0.000 ns、0 违例、Routed；资源 LUT 23.27%/reg 15.19%/ERAM 50.33%）；debug SDC 解析 PASS（生产 SDC 未动、3/51 行仅加 `u_top/`、时钟表一致、4 组）；G1 9/9 ALL PASS；CWC 已由 TD 真实流程生成（`auto_created_cwc1`，9 视图、288 trigger + 288 data nets，`compiled.cwc`=`fa24e258…`；bit `2385cded…` 未下载/未写 Flash）。唯一 FAIL=`check_chipwatcher_readback.py` 的 `BID width mismatch`——TD 2026.2 把 288 bit 逻辑存为 288×1024 并拆 **15 片 phy_eram**，校验器按“单段/全宽等式”假设（历史文档已声明该限制）不匹配。**裁定：② 书面等效校验（扩展工具）；不放行 ① 拆实例重建**——① 需第 3 次构建（合计已用 2 次、预算冻结）、破坏 9 字同实例同时性、且不增加证据价值；③ 仅 P3 GUI 读不足（映射未证会把“空白/错值”误判）。**冻结等效判据**：15 片逻辑宽度之和=288、逐片宽度≤BID `logic_width`、无重叠/无缺口、address/data 偏移连续、深度 1024、working mode（address_step=1、num_section=1、bytes/section、ECC、super_wide）逐片与 BID 一致；输出 288-bit 全覆盖映射表（机器可读）；**默认严格模式保持拒绝多片**（防回归历史缺口），新模式下真实 CWC+BID 0 失败；负例 ≥4（重叠/缺口/错 RID/错深度或工作模式）必须拒收；单段正例两模式均通过。工具改动限 `tools/td/check_chipwatcher_readback.py` + 测试夹具；**不重建、不改 CWC/bit**。**P3 门**：本修复 PASS + P2 轻量冻结（复用 P1-fix 构建，不重建）+ 用户在场；P3 首样本身份字命中 `FICP/RKA1/1.0` 作为映射最终实测旁证，不符即停。构建记账：P2 1 次 + P1-fix 1 次 = **2 次（用尽）**，本修复 **0 构建**。

**v1.8 更新（2026-10-18，P2 轻量冻结）**：`T11.runB-debug-rtl` **PASS r2**（manifest `ae6d061a…`；工具 commit `27c596b0`，root 仓未推送）。原规划完成 P2 轻量冻结（**不重建**，复用 P1-fix 验证构建）：① upstream 3 路径已本地 commit **`b0282d2a8dfdf11e6e63779510fe380dfffb5e83`**（`rtl/ep_side/img/ep_bar_win.v`、`constraints/ph1p_pcie_case_ep_dbg.sdc`（新）、`tools/pcie_integration/td/00_all_debug.tcl`；3 files/102+/1-；未推送；worktree clean）；② 更新 `debug-build/candidate-manifest.json` → `FROZEN_READY_FOR_P3`（bit `2385cded…` 5,224,027 B、compiled.bit 同 SHA、compiled.cwc `fa24e258…`、BID `71330f16…`、final_timing `1f83737f…`、area `9e1d7127…`、run.log `fd049037…`；G2 SWNS 0.139/STNS 0.000/HWNS 0.020/HTNS 0.000、0 违例、Routed、LUT 23.27%/reg 15.19%/ERAM 50.33%；G1 9/9；生产 SDC 未动+debug 变体 3 行前缀；CWC multipiece 288/288、strict 仍拒；失败尝试 `AFFC4396…` 保留为证据）；③ `debug-build/hardware-ready.md` 更新为 **READY-FOR-P3（附前提）**。**P2 判定**：以“冻结完成 + 复用 P1-fix r2 证据”闭合工程内容；按规则仍出 P2 自己的 **r0 integrated 报告**（轻量、≤15 min/≤20 calls，独立核对绑定/哈希/READY 前提/新旧并列），本次交本 run 综合测试者。**G 层分账**：P2 G0=pass（冻结/哈希）、G1=pass（继承 P1-fix 9/9，输入未变）、G2=pass（继承 P1-fix 构建+独立哈希核对；本包 0 构建）、G3=not_run（P3）、G4=not_run。**P3 顺序**：P2 r0 PASS → 派 P3（batch=1，不并行）；P3 参数冻结：bit `2385CDED…1873`（先复核 SHA→ASCII 暂存）、CWC GUI `auto_created_cwc1` 9 信号 word0..8、≥2 样本≥10 s、仅 SRAM/不写 Flash、DDR D37 异常=用户断电 10 s 重上同 bit、≤45 min/≤30 calls、单命令 ≤60 s。

**v1.9 更新（2026-10-18，P2 PASS r1 → P3 派发）**：`T11.runB-debug-build` **PASS r1**（integrated；manifest `36af4723…`/10,206 B；报告 `test-reports/T11.runB-debug-build-r1-integrated.md`；r0 唯一缺陷=回退文档过期已修复；候选与证据哈希未变：bit `2385cded…`、CWC `fa24e258…`、commit `b0282d2a…` 未推送、worktree clean；G0/G1/G2=pass（G1/G2 继承），G3/G4 not_run）。非阻塞观察：`debug-build/rollback.md` 措辞“P2 r0 PASS after round1”有歧义（实为 round1 PASS），下次触碰修正，不影响判定。→ 派发 P3 `T11.runB-board-readback`（本次派发；用户在场；batch=1）：SRAM 下载新 debug bit（先复核 SHA→ASCII 暂存）→ CWC 读回 9 字（身份/基线/CSI，≥2 样本≥10 s）→ 相机采集统计 → 真实硬件证据冻结；不得混拼 `AFFC4396…`/旧 bit；G3 按 Tier 判定、G4 仅短窗；测试者只核证据（不重跑硬件）。

**v1.10 更新（2026-10-18，P3 blocked → awaiting_user_gui）**：`T11.runB-board-readback` 返回 **blocked**（reason_code=`TOOL_UNAVAILABLE`；new_information=true）——bit `2385CDED…1873` / CWC `FA24E258…22BB` SHA 复核（含 ASCII 暂存）一致；`read_device_id`=PH1P100；仅 SRAM 下载 **PASS**（PRG-2014、100%、rc=0、28.85 s）；命令审计零 flash/efuse/SPI/svf；未混拼、未改线/电源/相机。CWC 读回仅 TD GUI（TD bin 无脚本入口；300 个 tcl 抽样零命中），9 字 **0 样本**；Tier-1/Tier-2 `not_evaluated`、G3 `not_run`。**处置：blocked 非 FAIL，round0 未开始、实际修复轮 0/3，未派综合测试者；本包置 `awaiting_user_gui`。** 用户清单 `board-readback/user-gui-checklist.md`（主已原样转发）。**恢复条件**：用户回传两组 9 字（十六进制原文+时间戳，间隔 ≥10 s）或界面异常原文。**恢复路径**：同 task_id 续原开发（`ses_eb09dc456ffeXF5AloX2zjXoNp`，≤15 min/≤20 calls）填 `readback-record.md`、按 §3.5 判 Tier-1/Tier-2/G3、保持或回退 SRAM；随后本 run 综合测试者（`ses_eb1c0a458ffeT2bv7TnR2Cd1SQ`）只核证据、不重跑硬件。遗留：hwserver PID 30988 仍运行（停止被宿主权限拒绝，未绕过；用户按需结束）。**判定链/分流冻结见 §3.5；判据未改，G3/G4 不因等待提前记。** 用户等待说明：按清单约 5–10 分钟；回报后约 10–15 分钟完成填表判定+独立核对，不再动板子。

**v1.11 更新（2026-10-18，user-input-05 → 复核出 TD Tcl 官方读回接口 → 有界自动尝试）**：用户追问 `user-input-05.md`（原话“你不能尝试操作chipwatcher吗”）。原规划只读复核：原 P3 结论“无 CLI”**不完整**——只查了 `bin` 可执行与 `scripts` 抽样，未查 TD **内置 Tcl 命令表**。用 `td_commands_prompt.exe` 执行 `info commands` 与 help 表，确认 TD 2026.2 注册：`get_hw_cws`、`get_cw_probes`、`run_hw_cw -trigger_now -cable`、`wait_on_hw_cw -timeout -cable`、`write_hw_cw_data -csv_file`、`check_cw_trigger`；另有 `export_chipwatcher`/`report_cwc_status`。这是**官方非 GUI 路径**（不是 GUI 自动化），值得一次有界尝试。**裁定：派发同 task_id 有界自动尝试**，续原 P3 开发（`ses_eb09dc456ffeXF5AloX2zjXoNp`）；≤20 min/≤20 calls（A 枚举 ≤5 min/≤5 calls；B 真实读回 ≤15 min/≤15 calls）；只读、仅 SRAM、零 Flash、不改线/电源/相机；默认不重下，仅 `get_hw_cws` 明确无 CWC 且证据支持时同 bit SRAM 重下 1 次；**禁止 GUI 自动化**；失败即停回 GUI 清单，不判 FAIL、不耗修复轮。**包结构不变（4 包）**。若成功→按 §3.5 判 Tier-1/Tier-2 并冻结 CSV/stdout→综合测试者；若失败→保留 stdout/CSV/界面原文，`awaiting_user_gui` 兜底。G3 仍未判定。

**v1.12 更新（2026-10-18，CWC Tcl round1 blocked → 批准最终 round2）**：round1 返回 blocked（TOOL_UNAVAILABLE + LIMIT_REACHED 20/20）：已证实 `config_chipwatcher <compiled.cwc>`→KIT-1004 `auto_created_cwc1`（9 view/288+288）、`get_hw_cws *` OK、`export_chipwatcher` 成功且与 `cwc-multipiece-map` 一致、`list_cable/connect_cable/report_cwc_status` 无报错；卡点 `run_hw_cw/wait_on_hw_cw/check_cw_trigger/write_hw_cw_data` 对实例名各写法均 `KIT-8000 No watcher instance matched`，`get_cw_probes *` 返回 9 个空 `{}`；本轮未下载、零 Flash、无 GUI 自动化、未改线；manifest 未更新。**关键线索**：`report_cwc_status` 的 **Bit File 列为空**→疑 CWC 与配对 bit 未关联（原尝试的 ASCII 暂存 cwc 与 bit 不同名/不同目录；GUI 要求 .bit/.cwc 同目录同源，或需 TD 下载后才注册硬件 watcher）。**裁定：批准一次有界 round2（最终 CLI 轮，不新增包、不扩授权）**——A 先冻结 round1 `cwc-cli` 证据与 manifest；B 零硬件配对修复（原始 `debug-fix\...\phy_1\cw\compiled.cwc`（同目录有 compiled.bit）或 ASCII 同名对 `compiled.cwc`+`compiled.bit`，可试 `config_chipwatcher -dir`）；C 仅 B 仍 KIT-8000 时，TD `download` 同 SHA bit `2385CDED…1873`（仅 SRAM，≤1 次，先确认 SRAM-only 模式）→ 重配 CWC → 重试；D 成功即两样本（≥10 s）CSV+stdout 冻结并按 §3.5 判定。**失败条件**：B/C 后 `run_hw_cw` 仍 `KIT-8000` → 全部停止（不再变体、不再 CLI 轮），冻结证据回 GUI 兜底；不判 FAIL、不耗修复轮。预算：**≤15 min/≤20 calls**（A≤5、B≤4、C≤6、D≤5）；单命令 ≤60 s；download ≤5 min；零 Flash、不改线/电源/相机、禁止 GUI 自动化。

**v1.13 更新（2026-10-18，round2 blocked → CLI 关闭 → awaiting_user_gui）**：round2 返回 blocked：`config_chipwatcher`+ASCII 同名对后 `run_hw_cw` 仍 KIT-8000；TD `download`（-mode jtag / PROGRAM_SRAM）rc=1：**PRG-9505 USB device open error + PRG-9525 Chip validation failed**；结束遗留 hwserver(PID 30988) 后仍 PRG-9505 → **TD CLI 无法建立 USB/JTAG 会话**。安全：round2 零写板、零 Flash、未改线/电源/相机、无 GUI 自动化；板仍上电，SRAM=debug bit `2385cded…`。**处置：P3=awaiting_user_gui；CLI round1/round2 均记为已尝试/关闭，非 FAIL、修复轮 0/3、G3 仍 not_run。** 恢复链：用户先恢复 USB 枚举（拔插 USB，确认无 hwserver/占用）→ GUI 按 `user-gui-checklist.md` 采两样本 → 回传 → 同 task_id 续原 P3 开发（补写读数表、补齐 candidate-manifest v3 的 `sha256=null`、按 §3.5 判 Tier-1/2/G3）→ 综合测试者核对（不重跑硬件）。**条件式 CLI-3（不自动派发）**：仅当用户报告 GUI 不可用/不便且 USB 枚举已恢复有工具证据时，由原规划激活；≤10 min/≤10 calls；先补 manifest；若板上位流因断电已丢，允许同 SHA bit SRAM 重下 1 次（先确认 SRAM-only）；`config_chipwatcher`→`run_hw_cw`；成功即两样本判定，仍 KIT-8000/任何 USB 错误永久停回 GUI；零 Flash、不改线/电源/相机、禁止 GUI 自动化、不吃修复轮、不再有后续 CLI 轮。包结构不变（4 包）。

**v1.14 更新（2026-10-18，user-input-06 → 批准 ASCII 路径有界重试）**：用户判断问题为**非英文路径**，要求把所需文件放到 **D 盘 TD 原位置附近**，由我方继续自动尝试，**不需用户操作**；明确授权 `D:\anlogic` 相关目录外部写入。`issue-01-nonascii-path.md` 由主机械登记（状态=**待核实**，非已确认根因）。**裁定：批准一次有界 ASCII 重试（用户明确要求的新尝试；不新增包、不改“零 Flash/不推送/不碰线电源/禁止 GUI 自动化”边界）。** 工作目录 `D:\anlogic\runa_p3\ascii_<YYYYMMDD_HHMMSS>\`（新建、不覆盖；不写入 `TD_Release_2026.2` 安装目录）。只复制 paired `compiled.cwc`（FA24E258…22BB）与 `compiled.bit`（2385CDED…1873，5,224,027 B）+ Tcl/CSV；保留原证据。顺序：SHA 复核 → `list_cable`/`connect_cable` → `read_device_id`=PH1P100 → ASCII cwd 下 `config_chipwatcher ./compiled.cwc` → `get_hw_cws *` → `get_cw_probes` → `run_hw_cw -trigger_now -cable 0` → `wait_on_hw_cw -timeout 20` → `write_hw_cw_data -csv_file`；成功两样本（≥10 s）并按 §3.5 判定冻结；仍 PRG-9505/KIT-8000 即停回 GUI。预算 **≤15 min/≤20 calls**（staging≤4、USB≤3、readback≤6、second+freeze≤5）。**本轮不重下 bit**（板上仍载 debug bit）；若位流已丢/ID 异常→停报告。**issue-01 处置=尝试核实，结果出来再定性（确认/排除/仍待定）。** 技术备注：PRG-9505 是 USB 会话错误、非路径错误，且 config/get_hw_cws 在非英文路径下曾成功——ASCII 路径是用户要求下的排除性验证，不预设根因。

**v1.15 更新（2026-10-18，ASCII 轮 blocked → issue-01 排除 → 批准最终同会话 download 尝试）**：ASCII 轮返回 blocked：ASCII cwd（`D:\anlogic\runa_p3\ascii_20261018_232333\`，SHA 与源一致）下，无 hwserver 仍 PRG-9505；启动 TD 自带 hwserver + `connect_cable -host_name 127.0.0.1:5555 -open` 后 `read_device_id`=PH1P100、`report_cwc_status`=`compile chipwatcher successfully!`（**USB 会话可建立**），但 `run_hw_cw`（多实例名/探针总线名、有无 -cable）**全部 KIT-8000**。**issue-01 结论：已排除（非英文路径非根因）**；路径、配对、USB 均非 CLI 卡点；剩余疑点=“hw watcher 句柄疑由 GUI Watch 生成”。安全：未重下 bit、零写板/零 Flash、无 GUI 自动化、未改 TD 安装；hwserver(PID 73028) 已停、5555 已释放；`ascii-attempt-record.md`、`phaseASCII1..4` stdout、ASCII 目录 td 日志已冻结；manifest v5 的 15 项 sha256=null 待补。**裁定：批准一次最终有界尝试（≤10 min/≤12 calls；不新增包、不扩安全边界）**——同一 TD CLI 会话内先 `download` 同 SHA bit（**SRAM，≤1 次，≤5 min**）再 `run_hw_cw`，测试“watcher 句柄需同会话 download/注册”假设（此前 round2 download 从未在可用 USB 会话内成功执行）。成功即两样本（≥10 s）并按 §3.5 判定冻结；失败（download rc≠0 / PRG-9505 / PRG-9525，或 download 成功但 `run_hw_cw` 仍 KIT-8000）＝**绝对停止：CLI 永久关闭，GUI 唯一路径**。零 Flash、不改线/电源/相机、禁止 GUI 自动化；结束时停 hwserver 释放 5555。

**v1.16 更新（2026-10-18，GUI 全零 → issue-02 复位域 → 裁定路径①，P1-r3 续修）**：用户 GUI 实读 9 字全零（**NOT MATCHED**；`Triggered:1`，9 信号/实例/位流 SHA 均正确，操作无误）。开发离线诊断确认根因：9 个 `MARK_DEBUG` 快照寄存器在 `tl_clk_user` 域，异步复位 `tl_rst_user` 仅当 `pl_link_up && LTSSM==L0` 才释放（`ph1p_pcie_rst_sync` L52–74）；无 PCIe 主机 → 复位恒有效 → 连常量字（FICP/RKA1/1.0）也为 0（`ep_bar_win.v` L464–499；`pcie_ep_engine.v` L397–399）。CLI final 尝试：`download` 同 SHA bit **成功**（SRAM、PRG-2014、rc=0、25.9 s）但 `run_hw_cw` 仍 KIT-8000 → **CLI 读回永久关闭**。**裁定：选①**（RTL 修复+重建+重读）——②不可行（现有 CWC 仅 9 字且全在死域，无“无链路可读子集”）；③改 G3 为需 PCIe 主机，与既定范围（PCIe 不验证、严格 FPGA 侧）冲突。①并入原 P1（`T11.runB-debug-rtl`，同 task_id，不新增第 5 包；**第 3/3 个实际修复轮，最后一轮**）：只动调试路径（`DBG_*` 门控的快照/复位/时钟绑定；必要时 debug-only SDC 变体/debug wrapper），不碰 PCIe 硬核、生产 SDC 语义、`00_all` 默认行为；产出新候选到 `debug-fix3/`（不覆盖 `debug-fix/`），旧 `2385cded…` 并列保留。预算：dev **≤75 min/≤35 calls**；TD 构建 **≤30 min×≤2**（第 2 次需新证据）；G2 阈值不放宽；新 TB（无链路复位场景：常量非零、计数可动）+ 既有 8 TB 全 PASS；CWC 重生成 + `--multipiece` 0 失败。**P3=NOT_MATCHED/awaiting-fix**；新候选冻结后 P2 轻量重冻（不重建），再派 P3 上板 GUI 两样本（≥10 s）。`issue-02-reset-domain.md` 已登记。

**v1.17 更新（2026-10-19，P1-r3 PASS → P2 重冻 → P3 重读准备）**：`T11.runB-debug-rtl` **PASS round3**（integrated；报告 `T11.runB-debug-rtl-r3-integrated.md`）：新 TB §0 无链路相位 + 8/8 回归 PASS；diff 4 文件（复位源解耦、9 字未搬域、DDR/CSI 未动）；G2 SWNS 0.134/0 Viol、资源正常；CWC `8d2998b9…` multipiece 0 失败；manifest `fadbf3f0…`；新 bit `bfafdf97…`（未下载）；commit BLOCKED_PENDING（HEAD `b0282d2a`，4 路径 worktree-only）。**P2 轻量重冻完成（0 构建）**：新建 `debug-build2/`（`candidate-manifest.json`、`hardware-ready.md`、`rollback.md`、`freeze-notes.md`），状态 **FROZEN_READY_FOR_P3**；绑定 bit `bfafdf97…`/CWC `8d2998b9…`/BID `02c5cfdf…`/timing `5a5c0e8d…`/area `35b25c1e…`/P1 manifest `fadbf3f0…`/r3 report `5A8BDBF9…`/diff `4535A87D…`；G0/G1/G2=pass（继承），G3/G4=not_run；旧 bit `e81d353b…`（回退）与 `2385cded…`（NOT_MATCHED 证据）并列未动。**P2 r2 轻量复验**（≤15 min/≤20 calls）交原综合测试者；PASS 后 **P3 重派**：新 bit SRAM 下载（TD 会话或 BW `-mode jtag`，≤1、零 Flash）→ 用户只点 Instant Trigger 两次（≥10 s）→ 期望 word0=`50434946`/word1=`31414B52`/word2=`00010000`/word8=`00000021`；word3-7 如实记录（可能 0/静止，Tier-2 归因）；CLI 读回永久关闭。**commit 接受 worktree-only 冻结态**（理由：r3 PASS 绑定 manifest `commit_status=BLOCKED_PENDING`，此时改 HEAD 会漂移并需重测；冻结 bit/CWC 不可变、diff 可复现）；可选用户提交命令见 `freeze-notes.md`，不推送、不阻塞 P3。

**v1.18 更新（2026-10-19，P2 PASS r3 → P3 重读派发）**：`T11.runB-debug-build` **PASS round3**（integrated；`T11.runB-debug-build-r3-integrated.md`）：functional/engineering/system 全 PASS；G0/G1/G2=pass（继承 P1-r3），G3/G4=not_run；manifest `e6d63702…`/11,105 B（22/22 绑定 0 不一致；diff `21D4A910…`/7,016 B reverse-apply RC=0）；bit `bfafdf97…`/CWC `8d2998b9…`/HEAD `b0282d2a` 未变；4 路径 worktree-only 接受。非阻塞：`cwc_summary.map_sha256` 仍为路径字符串，权威 `candidate.cwc_map.sha256=b6127b21…` 已核（下次编辑修）。**P3 重读已派发**（同 task `T11.runB-board-readback`，续原 P3 开发 `ses_eb09dc456ffeXF5AloX2zjXoNp`；≤20 min/≤20 calls）：ASCII 暂存新 paired bit/CWC → TD hwserver+connect_cable → `read_device_id`=PH1P100 → **仅 SRAM 下载新 bit（≤1 次、零 Flash）** → 新建 `user-gui-checklist-p1fix3.md` → 返回 `awaiting_user_gui`（不干等）。用户只点 Instant Trigger 两次（间隔 ≥10 s）；期望 word0=`50434946`/word1=`31414B52`/word2=`00010000`/word8=`00000021`；word3-7 如实（可 0/静止，Tier-2 归因）。**Tier-1 命中即 G3 部分通过**（FPGA 侧读通道）；仍不符→停止并诊断，不再让用户盲试。测试者核证据 ≤15 min/≤20 calls；零 Flash、不改线/电源/相机、禁 GUI 自动化。

**v1.19 更新（2026-10-19，P3 r1 PASS → run finished）**：`T11.runB-board-readback` **PASS round1**（integrated；`T11.runB-board-readback-r1-integrated.md`）：functional/engineering/system 全 PASS；**G3=partial（按冻结判据，不升 pass）**、G4=not_run；manifest v11 `BC27553A…`/23,415 B（83 条 0 不一致、0 null）；两样本 `1:30:48→1:31:7x`（≥19 s）：word0/1/2=`50434946/31414B52/00010000`、word3 +300、word5=`00279000`、word6 good 190→234、word8=`00000021`。**run 终态=finished**：4 包全部 PASS；首次通过 1/4；P1 3/3、P2 2 轮、P3 1 轮；⚠未通过 0。CLI 读回 4 次实际尝试（round1/round2/ASCII/同会话 download）均无样本、永久关闭；GUI 为唯一读回路径；issue-01 已排除、issue-02 已修复。父 T11 不置 done。终版文件：`final-summary.md`、`user-summary.md`、`handoff.md`、`dispatch.json`（finished）。

## 1. 本轮目标与边界

- **主要可验收目标（1 个）**：**FPGA 侧读通道成立 + 读到身份/写者基线/CSI 计数**（相机已接：延伸采集统计读数）。全程**无 PCIe、仅 SRAM、不写 Flash、不推送**。
- **路径（P0—P3，依赖顺序，不并行）**：方案冻结（离线）→ 调试核 RTL+回归（离线）→ 新 debug 位流构建/G2/候选冻结（离线）→ 上板 SRAM 替换 + CWC 读回 + 证据/回退（硬件，用户在场）。
- **安全边界（全程）**：`download -mode jtag` 仅 SRAM；绝不写 Flash/efuse/SPI；物理断电/接线/相机=用户操作；不改电源/线缆；单次下载 ≤5 min、上板窗口 ≤35 min；无目视判据。
- **非目标**：PCIe/主机读、UART 复活、JTAG 盲试、集成 P1 checker 到生产顶层（后续主题）、Run B、长稳 G4、100 帧/10 min 短稳（B2 余项，后续轮）。
- **旧候选规则**：新 debug 位流新候选，与 `e81d353b…2b9a`（配对 `ab811c8f…855`）**并列不混拼**；旧候选=来源/回退；回退=重下旧 bit（≈30–40 s）。
- **完成口径**：本轮 done=读通道成立且身份/基线/CSI 读到并留证；“父 T11 done”不因本轮达成（寄存器级板验系列、真实几何/相位、端到端、压缩仍缺）。

## 2. 工作包总表

| 顺序 | task_id | 问题/产物 | 工作树/允许写路径 | 依赖 | functional 验收 | engineering 验收 | system 验收 | 必要 G 层 | 状态 | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | T11.runB-debug-spec | 调试读回方案冻结：CWC 流程核实 + 探针/字表 + 判据 + 使能默认 + runbook | 只写 run `debug-spec/**`；**上游仓零写入**；不触硬件 | 无 | 字表/判据与 registers-plan/expected_rules 逐条一致；流程结论有原文出处；runbook 可执行性自查 | 路径/命令/哈希可复核；不引用未证实语义；ASCII/相对路径规则落实 | 只读边界（零上游写入、零硬件调用）；回退=丢弃目录即可 | G0（文档级）；G1 不适用；G2/G3 not_run | **PASS（r0，integrated）** | 无（manifest `b806b2a4…b173`；报告见 v1.1 注） |
| 2 | T11.runB-debug-rtl | 调试核插入 + 字库镜像 RTL + TB + 8 TB 回归；新 debug 构建入口；**r3：复位域修复（无链路可读）** | 上游调试路径（`rtl/ep_side/debug/**`、`ep_bar_win.v` DBG 门控块、debug wrapper、debug SDC 变体、`sim/tb/**`、构建入口）+ 本地 commit；新输出 `debug-fix3/**` | 1（探针/字表冻结）+ P3 全零诊断 | 新 TB（无链路复位：常量非零、计数可动）ALL PASS + 既有 8 TB 全 PASS；DBG 关行为不变 | 编译 0 error；diff 仅允许清单；`00_all`/生产 SDC 语义未改；G2 不放宽；CWC `--multipiece` 0 失败 | protected 逐字节；新旧 bit 并列不混拼；不触硬件 | G0/G1/G2（构建） | **PASS（r3，integrated）**；manifest `fadbf3f0…`；bit `bfafdf97…`（未下载）；commit worktree-only | P2 重冻已完成；无（P1 第 3/3 轮收束） |
| 3 | T11.runB-debug-build | TD 单会话构建（≤30 min×≤2）→ 新 debug 位流 + `compiled.cwc` + G2/资源 + 候选冻结 + 上板手册 | 只写 run `debug-build/**` + 构建输出指到 run 内；上游仅 debug 入口文件（已在包 2） | 2 | 构建会同判据齐备（PRJ-1406/1424/exit=0）；CWC 映射校验 0 失败；位流/字表可追 | Routed、全域 SWNS≥0（记数值）、无新违例、资源在器件内；manifest/哈希齐 | 未下载/未写 Flash；产物并列不覆盖；回退=删本包产物 | G0/G1/G2 | **PASS（r3，integrated）**（`debug-build2/`；manifest `e6d63702…`；bit `bfafdf97…`/CWC `8d2998b9…`；0 构建；worktree-only 接受） | 已派 P3；旧候选 `2385cded…` 仅证据、`e81d353b…` 回退 |
| 4 | T11.runB-board-readback | 上板：SRAM 重下 debug bit + CWC 读回（身份/基线/CSI，≥2 样本）+ 采集统计 + 恢复记录 | 只写 run `board-readback/**`；**上游零写入**；板上仅 SRAM | 3 + 用户在场（相机已接） | Tier-1 身份 3 字全中 + 至少一组计数可复读；Tier-2 基线/计数按§4 判据（见下） | 命令/退出码/时间/bit SHA/BID/CWC 链闭环；无 flash 命令；CWC 非原子告示 | SRAM-only；恢复/回退记录；DDR 校准 SOP 执行留痕 | G3（partial→pass 按 tier）；G4 not_run | **PASS（r1，integrated）**；**G3=partial**、G4=not_run；manifest v11 `BC27553A…`；bit `bfafdf97…` SRAM 已上板 | run finished；无（父 T11 不置 done；后续主题见 final-summary §6） |

## 3. 详细工作包

### 3.1 T11.runB-debug-spec（P0，离线，PASS r0）

**主要可观察结果**：`debug-spec/` 方案包——把“怎么读、读什么、什么算对、怎么操作”冻结成可执行文档，含 CWC 工具链在 TD 2026.2 上的可行性核实结论。

- **工作树/允许写范围**：只写 run `debug-spec/**`；`upstream/**`、`docs/`、`tools/td/**`、`workflow/tasks.json`、既有 run/证据 **只读**。
- **protected**：上游仓全仓（含 `ab811c8f`/`48be9f20`/`c89ab758`）、bit `e81d353b…` 及其配对证据、全部既有证据/run、`D:\TD\work\csi2`（只读引用）。
- **语义步骤（≤5）**：
  1. **CWC 工具链可行性核实（只读）**：TD 2026.2 安装内查 `setup_debugger` 流程（`scripts/DefaultFlow.tcl` 对照）、`cw/compiled.cwc|compiled.bit` 生成条件、官方例程 `D:/TD/03_F9P_CA05_PH1P50_PH1P100/V2026/…/04_use_ChipWatcher/`；**不启动 TD、不连硬件、不调 bw**；结论+原文路径写 `debug-spec/cwc-flow.md`（含“若 2026.2 不支持则回退 TD 6.2.2/6.2.3”的判定条件）。
  2. **探针/字表冻结**：按 guide §1/§2 产出 `debug-spec/probe-map.md`——A 组每字↔探针层级名（或字库字序）；实例数/位宽落点；B 组加装条件；对 `ep_bar_win.v`/顶层只读复核名字来源。
  3. **使能默认核对**：按 guide §3 写 `debug-spec/enable-state.md`——CTRL 复位默认、采集是否自动活、是否需要 debug-only 默认开启（最小改动清单草案）。
  4. **判据/记录冻结**：`debug-spec/readback-criteria.md`——与 `registers-plan.md` R01—R17/`expected_rules.json` 逐条绑定（含 §1 阈值），并给读数记录模板（复用 `run_record.schema.json` 字段）。
  5. **上板 runbook 草案**：`debug-spec/board-runbook.md`——下载/读回步骤、操作者标记、ASCII 路径与 hwserver 参数、≥2 样本/≥10 s、失败保留界面、DDR 校准断电 10 s SOP、回退步骤。
- **综合测试三维对象**：functional=字表/判据与 KIT 规则逐条一致（抽验 ≥8 条 + 全 A 组）+ runbook 步骤可执行性独立复核；engineering=路径/命令/哈希/引用可复核、无未证实语义；system=零上游写入/零硬件调用审计、回退=丢弃 `debug-spec/`。
- **必要 G 层**：G0（输入/口径冻结）；G1/G2/G3 not_run（不适用理由：纯文档包，不涉 RTL/构建/硬件）。
- **工具与安全超时**：读/搜 60 s；只读本地文件与安装文档；**禁止**调用 bw/TD/硬件。
- **停止条件/回退**：文档缺失或结论矛盾 → blocked 交原规划；回退=丢弃目录。
- **预算（冻结）**：开发 ≤30 min / ≤30 次工具调用；综合测试 ≤15 min / ≤30 次。

### 3.2 T11.runB-debug-rtl（P1，离线，PASS r3）

**主要可观察结果**：可构建的 debug 设计增量（CWC 插入 + 字库镜像如采用）与 TB/回归证明，形成本地 commit + manifest。

- **允许写范围**：上游新目录 `rtl/ep_side/debug/**`、`sim/tb/tb_*debug*.v`；新 debug 构建入口（`tools/pcie_integration/` 下新增文件）；`sim/compile_checked.f` 允许追加行（记录）；顶层例化点**最小**改动（仅插入，不删改既有逻辑；逐条入 diff）；本地 commit（不推送）；run `debug-rtl/**`。
- **protected**：`build.tcl`/`run_td.ps1` 既有默认行为、既有 RTL/约束/协议镜像、既有 TB、KIT/checker 文件、全部证据、bit `e81d353b…`。
- **语义步骤（≤5）**：1) 按 `probe-map.md` 实现探针/字库（同域、只读、无副作用）；2) debug 构建入口（不动 `00_all`）；3) 新 TB（镜像=寄存器值、边界帧、无副作用检查）+ 负例 ≥2；4) 新 TB + 既有 8 TB 回归（run_sim.ps1，`MIPI_PHY_SIM_STUB`，vlog Errors:0 + ALL PASS）；5) commit/manifest/dev-result/lessons。
- **三维对象**：functional=独立重跑新 TB+抽验回归；engineering=编译/端口规范/diff 允许清单/manifest；system=protected 比对、回退、零硬件。
- **G 层**：G0/G1；G2 not_applicable（本包不构建）；G3 not_run。
- **工具与安全超时**：ModelSim 入口；单 TB ≤5 min、整组 ≤15 min；不用 TD、不触硬件。
- **预算（冻结）**：开发 ≤45 min / ≤30 次；综合测试 ≤20 min / ≤30 次。

#### 3.2.1 r3 复位域修复（2026-10-18；用户授权重建；第 3/3 修复轮；**PASS r3**）

- **结果**：**PASS round3**（integrated；`T11.runB-debug-rtl-r3-integrated.md`；manifest `fadbf3f0…`；新 bit `bfafdf97…`；G2 SWNS 0.134/0 Viol；CWC `8d2998b9…` multipiece 0 失败；新 TB §0 无链路 + 8/8 回归 PASS；diff 4 文件）。
- **触发**：P3 GUI 实读 9 字全零（NOT MATCHED）；根因 issue-02：探针快照在 `tl_clk_user` 域，`tl_rst_user` 仅 `pl_link_up && LTSSM==L0` 释放；无主机→常复位→常量也 0。
- **目标**：无 PCIe 链路时 9 字均可读（FICP/RKA1/1.0/CTRL 非零；DDR/CSI 计数可动）；CWC 探针时钟与快照时钟显式一致（H2）。
- **允许写范围**：`rtl/ep_side/img/ep_bar_win.v` 的 `DBG_*` 门控快照块、`rtl/ep_side/ph1p_pcie_ep_top.v`/`pcie_ep_engine.v` 的 debug 接线、`rtl/ep_side/debug/**`、debug-only SDC 变体 `constraints/ph1p_pcie_case_ep_dbg.sdc`、`sim/tb/tb_*debug*.v`、`sim/compile_checked.f` 追加行、`tools/pcie_integration/td/00_all_debug.tcl`；新输出 `debug-fix3/**`（不覆盖 `debug-fix/`）；本地 commit（不推送）。
- **protected**：PCIe 硬核/IP、生产 SDC `ph1p_pcie_case_ep.sdc` 语义、`00_all` 默认行为、DBG 关闭时的生产 RTL 行为、旧 bit `2385cded…`/`e81d353b…`、既有证据。
- **语义步骤（≤5）**：1) 修调试快照复位/域与 CWC 时钟绑定 + 新 TB（无链路复位场景：常量非零、计数可动；负例 DBG-off 等价）；2) 新 TB + 既有 8 TB 回归 ALL PASS（vlog Errors:0）；3) TD 构建 ≤2 次（≤30 min/次；第 2 次需新证据）+ G2（阈值不放宽）+ `setup_debugger` 重出 CWC + `check_chipwatcher_readback.py --multipiece` 0 失败；4) `debug-fix3/` 冻结（bit/CWC/BID/timing/area/diff/rollback，新旧并列）；5) dev-result/lessons + commit。
- **三维对象**：functional=新 TB+8TB 全 PASS、无链路常量非零/计数可动；engineering=diff 允许清单/G2 数值/CWC 0 失败/manifest 0 不一致；system=生产行为不变、零下载、旧候选保留。
- **G 层**：G0/G1/G2；G3 not_run（上板另行）。
- **预算（冻结）**：开发 ≤75 min / ≤35 次；综合测试 ≤30 min / ≤30 次；TD 单会话 ≤30 min、最多 2 次。
- **停止/回退**：2 次构建仍失败、时序不收敛、CWC 校验失败或需扩范围 → blocked 交原规划；不放宽门槛；旧候选/旧 bit 原位保留。

### 3.3 T11.runB-debug-build（P2，离线，PASS r3）

**主要可观察结果**：新 debug 候选位流 + 配对 `compiled.cwc` + G2 报告 + 冻结 manifest（与旧候选并列）。

- **当前重冻（2026-10-19，P1-r3 候选；PASS r3）**：`debug-build2/**` 为冻结件（不覆盖 `debug-build/`）——`candidate-manifest.json`（`e6d63702…`/11,105 B）、`hardware-ready.md`、`rollback.md`、`freeze-notes.md`；状态 `FROZEN_READY_FOR_P3`；0 构建（复用 P1-r3）。绑定 bit `bfafdf97…`、CWC `8d2998b9…`、BID `02c5cfdf…`、timing `5a5c0e8d…`、area `35b25c1e…`、P1 manifest `fadbf3f0…`、r3 report `5A8BDBF9…`、diff `21D4A910…`/7,016 B（reverse-apply RC=0）。G0/G1/G2=pass（继承；P2 0 构建），G3/G4=not_run。旧 bit `e81d353b…`/`2385cded…` 并列未动。P2 r3 integrated PASS（报告 `T11.runB-debug-build-r3-integrated.md`；22/22 绑定 0 不一致）；非阻塞：`cwc_summary.map_sha256` 仍路径字符串，权威字段已核。不重建、不下载、不触硬件。
- **允许写范围**：run `debug-build/**`（构建输出、日志、manifest、hardware-ready.md；本轮重冻写 `debug-build2/**`）；上游仅限包 2 已提交文件；**不改** `00_all` 入口。
- **语义步骤（≤5）**：1) 单会话构建（wrapper ≤30 min；**最多 2 次**，第 2 次须有新证据/参数纠正并记录理由）；2) 会同判据核验（PRJ-1406/1424/T07_ALL_DONE、exit=0、final_timing.rpt Routed）；3) `setup_debugger` 生成 `cw/compiled.cwc|compiled.bit` + `check_chipwatcher_readback.py` 校验 0 失败；4) STA/资源报告（全域 SWNS≥0、hold≥0、资源在器件内；对上一轮 +0.115/+0.150 基线给对比表）；5) 候选冻结（manifest SHA、candidate diff、rollback.md、hardware-ready.md 上板手册+readback-criteria 绑定）。
- **三维对象**：functional=会同判据+位流/字表/CWC 三者可追（哈希链）；engineering=STA/资源/构建时限/CWC 映射/路径规则/manifest 0 不一致；system=产物并列不覆盖、未下载未写 Flash、回退=删本包产物+重下旧 bit。
- **G 层**：G2；G0 继承；G1 继承包 2；G3 not_run。
- **工具与安全超时**：TD 2026.2；单会话 ≤30 min；**禁止**下载/bw/flash。
- **预算（冻结）**：开发 ≤60 min / ≤30 次（理由：用户冻结“TD 单会话 ≤30 min、最多 2 次”，含等待与报告时间）；综合测试 ≤25 min / ≤30 次；本轮 P2-r2 轻量复验 ≤15 min / ≤20 次（只核冻结/哈希/绑定，不重建、不触硬件）。

### 3.4 T11.runB-board-readback（P3，硬件，PASS r1；G3=partial）

**主要可观察结果**：板上读回记录——身份 3 字 + 写者基线 + CSI 计数（≥2 样本）+ 相机采集统计（相机已接）+ 恢复/回退记录。

- **允许写范围**：run `board-readback/**`（记录、日志原文、截图可选、manifest）；**上游零写入**；板上仅 SRAM。
- **前置**：包 3 的 hardware-ready.md；用户在场；相机单 A 已接；hwserver/bw 同 B1 参数；bit 暂存 ASCII 路径（`%TEMP%` 或 ASCII 副本）并先复核 SHA。
- **语义步骤（≤5）**：1) 下载 debug bit（`-mode jtag`，记录 rc/时长/PRG-2014；旧 bit 文件原位保留）；2) CWC 打开 `compiled.cwc`→Watch→Instant Trigger，读 A 组字**原值**（≥2 样本、间隔 ≥10 s；记录实例名/CWC SHA）；3) 相机采集统计：同一读法记录 0x120/0x124（+B 组按条件）随时间的值；4) 写记录（操作者/时间/bit SHA/BID/命令与退出码/读数原文/非原子告示）；5) 恢复/回退：正常=保持 SRAM 调试位流（掉电即失，回退=重下 `e81d353b…`）；DDR 校准异常（D37 灭）→**用户断电 10 s→上电→重下同 bit**；异常无法恢复→回退旧 bit 并记录。
- **functional 验收**：Tier-1（硬）=0x040=0x50434946、0x118=0x31414B52、0x11C=0x00010000 三字全中 + ≥1 组计数可复读（两样本一致或可解释）；Tier-2（基线/采集）=0x0A0 单调且 ≥1、0x0A4 非零且 128 B 对齐、0x0AC=2,592,768、CSI 解码原始值 + good 增长（相机活）。若 Tier-1 过而 Tier-2 为 0/静止：记录原值并按“使能默认/采集状态”归因，交原规划判定（不得改判据求 PASS；不得以目视替代读数）。
- **engineering 验收**：命令/退出码/时间/bit SHA/BID/CWC 哈希链闭环；记录 schema 兼容；非原子/跨域告示在案。
- **system 验收**：命令审计零 flash/efuse/SPI/svf；未改线/电源/相机；DDR 校准 SOP 留痕；回退路径可执行并记录。
- **G 层**：G3（Tier 划分见上，报告必须分 tier 写）；G4 not_run（不适用理由：本轮不测长稳）。
- **工具与安全超时**：bw/hwserver（B1 参数）；单次下载 ≤5 min；上板窗口 ≤35 min（读回 15—30 min 符合用户冻结）；命中 flash 命令或未知提示 → 立即停。
- **预算（冻结）**：开发（含现场协同执行记录）≤45 min / ≤40 次（理由：用户冻结 15—30 min 读回窗口 + 下载 ≤5 min + GUI 协调；环境已由 B1 摸清）；综合测试 ≤25 min / ≤30 次。
- **本轮 P3 重读预算（2026-10-19）**：dev 下载+清单 **≤20 min/≤20 calls**；综合测试者核证据 **≤15 min/≤20 calls**；下载 ≤1 次、单命令 ≤60 s（下载 ≤5 min）；零 Flash、不改线/电源/相机、禁 GUI 自动化。
- **终态（2026-10-19）**：旧候选全零已由 P1-r3（issue-02 复位域修复）解决；新 bit `bfafdf97…` SRAM 上板后用户 GUI 两样本命中：word0/1/2/8 正确、word3 +300、word6 good 190→234（bad/hdr/crc=0）。**P3 PASS r1（integrated）**；**G3=partial**（Tier-2 word6 稳定性未判达成，不升 pass）、G4=not_run；manifest v11 `BC27553A…`（83 条 0 不一致、0 null）。CLI 读回永久关闭；run finished；父 T11 不置 done。

### 3.5 P3 用户读数回收：判定链与分流（冻结，2026-10-18）

**当前口径（2026-10-18 更新）**：**CLI 读回永久关闭**（final 尝试：download 成功仍 KIT-8000）；唯一读回路径=**用户 GUI 两样本**。以下 **A0 为历史记录，不再执行**；先按 §3.2.1 完成 P1-r3 修复/重建、P2 重冻，再按本节的用户 GUI 流程重读新候选。**不重下旧 bit、不换 CWC、不改接线/电源/相机、不碰 Flash。**

**A0. 自动 CLI 路径（首选；2026-10-18 新增）**
- 命令（TD 2026.2 内置 Tcl，`td_commands_prompt.exe` 注册表确认）：`get_hw_cws -nocase -verbose` → `get_cw_probes auto_created_cwc1 -nocase -verbose` → `run_hw_cw <objects> -trigger_now -cable 0` → `wait_on_hw_cw <objects> -timeout 20 -cable 0` → `write_hw_cw_data <objects> -csv_file <run>/board-readback/cwc-cli/sampleN.csv`；`check_cw_trigger` 可作辅助。
- 两样本间隔 ≥10 s；CSV/stdout/时间戳/实例名/bit+CWC SHA 原文冻结；开发不代填、不换算。
- 边界：只读、仅 SRAM、零 Flash、不改线/电源/相机；不重下 bit（仅 `get_hw_cws` 明确无 CWC 且证据支持时同 bit SRAM 重下 1 次）；若命令要求工程上下文，只读打开/复制到 run 内 scratch，不得改动冻结工程；**禁止 GUI 自动化**；≤20 min/≤20 calls（A 枚举 ≤5 min/≤5 calls；B 读回 ≤15 min/≤15 calls）。
- **round1 结果（blocked，20/20 用尽）**：`config_chipwatcher` → KIT-1004 `auto_created_cwc1`；`get_hw_cws *` OK；`export_chipwatcher` 成功且 XML 与 `cwc-multipiece-map` 一致；但 `run_hw_cw/wait_on_hw_cw/check_cw_trigger/write_hw_cw_data` 均 `KIT-8000 No watcher instance matched`，`get_cw_probes *` 返回 9 个空 `{}`；`report_cwc_status` 的 **Bit File 列为空**（关键线索）。证据 `board-readback/cwc-cli/`。
- **round2 结果（blocked；CLI 关闭）**：配对修复后 `run_hw_cw` 仍 KIT-8000；TD `download`（-mode jtag / PROGRAM_SRAM）rc=1：**PRG-9505 USB device open error + PRG-9525 Chip validation failed**；结束遗留 hwserver(PID 30988) 后仍 PRG-9505 → TD CLI 无法建立 USB/JTAG 会话。零写板/零 Flash/未改线/无 GUI 自动化；板仍上电，SRAM=debug bit。manifest v3 的 round2 新文件 sha256=null 待补。
- **条件式 CLI-3（不自动派发）**：仅当用户报告 GUI 不可用/不便且 USB 枚举恢复有工具证据（`list_cable`/`read_device_id` OK 或 BW `read_device_id`=PH1P100）时，由原规划激活；≤10 min/≤10 calls；先补 manifest；若板载位流因断电已丢，允许同 SHA bit SRAM 重下 1 次（先确认 SRAM-only）；`config_chipwatcher`→`run_hw_cw`；成功两样本判定，仍 KIT-8000/任何 USB 错误永久停回 GUI；零 Flash、不改线/电源/相机、禁止 GUI 自动化、不吃修复轮、不再有后续 CLI 轮。
- **ASCII 路径重试（2026-10-18，user-input-06；issue-01 尝试核实）**：工作目录 `D:\anlogic\runa_p3\ascii_<YYYYMMDD_HHMMSS>\`（新建、不覆盖；TD 安装目录零写入）；只复制 paired `compiled.cwc`/`compiled.bit` + Tcl/CSV；SHA 双向复核。顺序：`list_cable`/`connect_cable` → `read_device_id`=PH1P100 → ASCII cwd 下 `config_chipwatcher ./compiled.cwc` → `get_hw_cws *` → `get_cw_probes` → `run_hw_cw -trigger_now -cable 0` → `wait_on_hw_cw -timeout 20` → `write_hw_cw_data -csv_file`；成功两样本（≥10 s）按 §3.5 判定冻结；仍 PRG-9505/KIT-8000 即停回 GUI。**本轮不重下 bit**；若位流已丢/ID 异常→停报告。预算 ≤15 min/≤20 calls（staging≤4、USB≤3、readback≤6、second+freeze≤5）。issue-01 结果出来再定性；PRG-9505 为 USB 会话错误、非路径错误（不预设根因）。
- **ASCII 轮结果 + issue-01 结论（2026-10-18）**：ASCII cwd `D:\anlogic\runa_p3\ascii_20261018_232333\`（SHA 与源一致）下仍 KIT-8000；启动 TD 自带 hwserver + `connect_cable -host_name 127.0.0.1:5555 -open` 后 `read_device_id`=PH1P100、`report_cwc_status`=compile chipwatcher successfully!（USB 会话可用），但 `run_hw_cw` 全写法仍 KIT-8000。**issue-01=已排除（非英文路径非根因）**；路径/配对/USB 均非卡点；剩余疑点=hw watcher 句柄疑由 GUI Watch 生成。安全：未重下 bit、零写板/零 Flash、无 GUI 自动化、未改 TD 安装；hwserver(PID 73028) 已停、5555 已释放；证据 `ascii-attempt-record.md`/`phaseASCII1..4`；manifest v5 的 15 项 sha256=null 待补。
- **最终同会话 download 尝试（2026-10-18，批准；≤10 min/≤12 calls）**：单一 `td_commands_prompt.exe` 会话：TD 自带 hwserver(5555)+`connect_cable`→`read_device_id`=PH1P100→`download -bit <ASCII>\compiled.bit -mode jtag -cable 0`（同 SHA、仅 SRAM、≤1 次、≤5 min；rc≠0/PRG-9505/PRG-9525 即停不换模式）→`config_chipwatcher ./compiled.cwc`→`get_hw_cws *`→`run_hw_cw auto_created_cwc1 -trigger_now -cable 0`→`wait_on_hw_cw -timeout 20`→`write_hw_cw_data -csv_file`；成功两样本 ≥10 s 按 §3.5 判定冻结。**失败（download 失败或成功后仍 KIT-8000）=绝对停止：CLI 永久关闭，GUI 唯一路径**；零 Flash、不改线/电源/相机、禁止 GUI 自动化；结束停 hwserver 释放 5555。
- 失败即停（命令不存在、列表空、探针名不符、trigger 连续 2 次失败、无 CSV、code mismatch、线缆占用、任何 Flash 提示），保留原文回 GUI 清单，**不判 FAIL、不耗修复轮**；成功后按 B—D 判据判定，再交综合测试者。

**A. 录入与格式门（不判硬件）**
1. 逐字录入 `readback-record.md`：实例 `auto_created_cwc1`、CWC SHA `FA24E258…22BB`、bit SHA `2385CDED…1873`、操作者=现场用户、两个时间戳（+08:00）；开发不得代填/推测/换算。
2. 格式完整（每样本 9 字、8 位十六进制、时间戳、间隔 ≥10 s）且无界面异常 → 进入 B。
3. 缺字/间隔 <10 s/明显笔误 → **仅一次有界重采**：请用户再点两次 Instant Trigger（间隔 ≥10 s），不重下、不改配置；仍不合格 → blocked（`RETURN_FORMAT`/`INPUT_CONFLICT`），非 FAIL。

**B. 身份门（硬停）**
- word0（0x040）=`0x50434946`（FICP）、word1（0x118）=`0x31414B52`（RKA1）、word2（0x11C）=`0x00010000`（1.0），两样本均须命中。
- 任一不符 → **立即停**：不再采样、不解释其它字、不反复 Trigger；保留界面原文/截图；**回退旧 bit `E81D353B…2B9A` 或用户断电 10 s 清 SRAM**；本次尝试记 Tier-1 FAIL；按 `INPUT_CONFLICT` 交原规划（疑 CWC/bit/实例不匹配），不重建、不换 CWC、不改判据。

**C. Tier-1 复读门**
- 至少一组计数两样本一致或可解释（优先 word3 seq 非减且 ≥1；或 word6 good 增长）；身份字固定值本身不单独充当“计数复读”。
- 计数全 0/静止 → 记录原值，按 Tier-2 归因；不据此改身份判定，也不放行 PASS。

**D. Tier-2 逐项（两样本）**

| 项 | 判据 | 不符处置 |
|---|---|---|
| word3/0x0A0 seq | 单调不减且 ≥1 | 记录后停；归因采集使能/写者 |
| word4/0x0A4 base | 非零；低 7 位=0（128 B 对齐） | 记录后停；离线核查映射/偏移 |
| word5/0x0AC len | **=`0x00279000`**（2,592,768） | 记录后停；离线核查映射/偏移；不重下 |
| word6/0x120 | 原文 + `good[31:24]/bad[23:16]/hdr_err[15:8]/crc_err[7:0]`；good 两样本增长 | 不增长→如实记录、Tier-2 未达；归因相机流/采集；不目视替代 |
| word7/0x124 | 原文 + `last_lines[31:16]/last_wc[15:0]` | 仅记录，无硬阈值 |
| word8/0x044 CTRL | bit0=1、bit5=1、bit4=0、bit6=0、bit7=0、bit8=0、[31:9]=0（mask `0xFFFFFE10`） | 使能位不符→记录后停；**bit6/bit7=1→安全停，请用户立即断电 10 s 清 SRAM**，不继续读回 |

- 跨域说明：word6/word7 经两级同步，跨域瞬间差一拍属可解释差异，原文记录，不合并成“原子快照”。
- 具体值错（word4/word5/word8）不等于可重试：**不反复 Instant Trigger、不重下同 bit、不重建**；交原规划做离线映射/使能核查后再定是否形成修复包。
- 零/静止（word3/word4/word6）按 `enable-state.md` 归因；Tier-1 过而 Tier-2 未达时，G3 记 `partial`（分 tier 写），不得改判据求 PASS。

**E. 证据与判定**
1. 开发填 `readback-record.md`（两样本原值、解码、Tier 结论、时间/操作者/实例/CWC SHA、异常原文）；更新 manifest 工件哈希与 `dev-result.md`。
2. 保持 SRAM（默认）或按分流回退旧 bit；记录 hwserver 是否结束；不改线/电源/相机。
3. 综合测试者（本 run 原 tester）仅核证据链、独立复算解码/判据/审计，不重跑硬件；报告 `test-reports/T11.runB-board-readback-r0-integrated.md`。
4. 判定记账：全过→Tier-1/Tier-2 PASS、G3 pass（分 tier）；身份不符→Tier-1 FAIL、停；具体值错→G3 not pass、交原规划；零/静止→G3 partial、归因；工具/界面异常→blocked。实际修复轮从 round0 后的真实 FAIL 起算，blocked 不计轮。

**F. 失败即停清单（汇总）**
- 身份三字任一不符 / code mismatch / 设备不识别 / 实例缺失 / word8 bit6 或 bit7=1 / 出现 Flash/efuse/SPI 提示 / D37 灭且断电重上后仍异常 / 端口占用且用户无法结束 hwserver / 需要改线或改电源或改相机。
- 停后动作：保留界面原文/截图、记录已执行命令与时间、保持或回退旧 bit、交原规划；不盲试未知命令、不重综合、不重烧、不推送。

**G. 复位域修复后的 P3 重读流程（当前；issue-02 修复后）**
1. 前置：P1-r3 PASS + P2 轻量重冻（新 bit/CWC/BID/rollback/hardware-ready）；更新 `user-gui-checklist.md` 的 bit/CWC 路径/SHA、实例名与 9 信号名（如映射变化）。
2. SRAM 下载新 bit：SHA 复核 → ASCII 暂存（`D:\anlogic\runa_p3\...` 或 `%TEMP%`）→ `download -mode jtag`（BW）或 TD 会话 download；≤1 次，记录 rc/PRG-2014/时长；零 Flash；旧 bit `2385cded…`/`e81d353b…` 原位保留。
3. 用户 GUI：打开同源新 `compiled.cwc` → Watch → 实例 `auto_created_cwc1` → Add Signals 9 个 → Instant Trigger **两次、间隔 ≥10 s**；Hex 原文+时间戳+界面原文回报。**用户只点这两次，不改设置/线/电源/相机。**
4. 判定：身份 word0=`50434946`/word1=`31414B52`/word2=`00010000`；word8=`00000021`；word3-7 如实记录（可 0/静止，Tier-2 归因）；Tier-1 命中即 G3 部分通过；若仍全零/不符 → 停（不再让用户重试/不重下同 bit），回到诊断，**不得记 PASS**。
5. 证据冻结：`readback-record.md` 两样本原文、bit/CWC SHA、实例/信号、命令/rc/时间、Tier-1/2、G3 分 tier；综合测试者只核证据、不重跑硬件。

## 4. 综合测试者安排（独立于开发）

- **每任务新开发 + 一个新综合测试者**；同任务修复才续原 ID；每任务每轮一份 `test-reports/<task_id>-r<round>-integrated.md`（首行唯一判定标题；dimension=integrated，覆盖 functional/engineering/system + G 层）。
- 离线包：独立重跑 TB/回归（含测试者自建负例）、抽验判据来源、哈希/diff/BOM、命令审计；不要求硬件。
- 上板包（P3）：DUT 已由人与工具实测，测试者**独立复核证据链**（操作者/时间/身份/命令/读数/回退）、独立复算解码与判据、审计无 flash/未改线；**不重跑硬件**；不得把未绑定证据的读数记 PASS。
- 预算（冻结）：P0 ≤15 min、P1 ≤20 min、P2 ≤25 min、P3 ≤25 min；均 ≤30 次工具调用。

## 5. 统一阈值（冻结）

| 门槛 | 值 |
|---|---|
| 身份 | 0x040=`0x50434946`；0x118=`0x31414B52`；0x11C=`0x00010000`（任一不符=Tier-1 FAIL） |
| 写者基线 | 0x0A0 单调不减且 ≥1（采集活）；0x0A4 非零/128 B 对齐；0x0AC=`2,592,768`；0x0A8 位图按 R09 |
| CSI/采集 | 0x120/0x124 原始值 + 解码；≥2 样本、间隔 ≥10 s；good 增长（相机活，单 A） |
| 构建 | 会同判据齐 + exit=0 + Routed + 全域 SWNS≥0/hold≥0 + 资源在器件内 + 无新违例；单会话 ≤30 min×≤2 |
| CWC | `setup_debugger` 产物齐 + `check_chipwatcher_readback.py` 0 失败 + CWC/bit 配对记录 |
| 回归 | 既有 8 TB + 新 TB 全 `*** ALL PASS ***`（vlog Errors:0；`MIPI_PHY_SIM_STUB`） |
| 板安全 | `-mode jtag` 仅 SRAM；flash/efuse/SPI/svf 命令零命中；未改线/电源/相机 |
| protected/diff | 除允许清单与记录在案追加行外逐字节相等 |
| manifest | 0 不一致；所有新文件/日志可复算 SHA256 |

## 6. 预算、停止与回退

- **执行预算（用户冻结 + 默认）**：TD 单会话 ≤30 min、最多 2 次；读/搜 60 s；单 TB ≤5 min；整组回归 ≤15 min；板上读回 15—30 min（窗口 ≤35 min）；开发/测试预算见各包；角色自停规则=默认 30 次工具调用/规划 15 min/开发与测试 45 min（本 run 包 2/3/4 冻结的 60/45/45 min 为有理由覆盖）。
- **停止**：缺工具/资料/授权/设备 → blocked（不空转）；连续 2 循环无新进展 → NO_PROGRESS；预算耗尽 → LIMIT_REACHED；外部错误不自动重试、不扩权；三轮实际修复后仍 FAIL → 保留 ⚠ 交原规划。
- **回退**：包 1=丢弃目录；包 2=`git revert`/丢弃新增文件；包 3=删本包产物（旧候选不受影响）；包 4=重下旧 bit `e81d353b…`（SRAM 易失，无需 Flash）。全程遵守根 AGENTS 单文件删除禁令。
- **顺序裁剪**：时间不足从尾部裁（P3→P2→P1），被裁/阻塞包如实登记、不降门槛赶工、不自动续做。

## 7. 后续主题（≤3，不自动续做）

1. P1 checker（`ddr_frame_readback_checker.v`）集成到生产顶层 + 状态寄存器 + 重跑 G1/G2 + 新候选（板内读回自证）。
2. B2 余项：采集使能确认、100 帧/10 min 短稳、发布确认、条件读回；真实几何/相位回填后重跑 G1/G2。
3. Run B 三算法接入与板级验证；RK 环境修复后的端到端 G4（另轮）。

## 8. 本轮 done 口径与用户配合

- **本轮 done**=P0—P3 依序收束且 P3 达到 Tier-1（Tier-2 按实况归因）；“父 T11 done”不因本轮达成。
- **用户配合最小集（终态）**：本轮已结束，**无需任何操作**；板子保持现状即可（SRAM 内为 `bfafdf97…` 调试位流，掉电即消失）。如需恢复旧位流：断电 10 s 上电（清除 SRAM）或告诉我们重下 `e81d353b…`（SRAM，约 30–40 s，不写 Flash）。
