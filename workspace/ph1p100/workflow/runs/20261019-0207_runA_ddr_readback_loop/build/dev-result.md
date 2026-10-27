# dev-result — T11.runC-build（0207 runC P2，round0）

- 角色：fpga-dev（opencode subagent，0207 runC P2）；执行窗口 2026-10-19 14:58:24–15:12:43（+08:00）。
- 任务：单会话 `00_all_debug` 构建 → 会同判据 → CWC 重生成（含新字探针）+ 校验 → G2 → 候选冻结。**本包零 RTL 改动**（P1 已冻结）。
- 工作树：`upstream\ph1p100-pcie-ep-fpga-wt0207`（branch `opencode/runC-0207`，HEAD `b0282d2a…`，worktree-only `6 M + 2 ??` 未变）；共享树 `upstream\ph1p100-pcie-ep-fpga` 只读、零写入。

## 1. 构建（单会话，用 1/2 次预算）

- 入口：`tools\pcie_integration\run_td.ps1 -Stage 00_all_debug -OutDir <run>\build\prj`；TD 2026.2（`TD_BIN=D:\anlogic\TD_Release_2026.2\bin`，安装目录只读）。
- wall=**858.7 s**（start `2026-10-19T14:58:24.9879432+08:00`，end `2026-10-19T15:12:43.7275425+08:00`）；`build\prj\commands.log`：`stage=00_all_debug exit=0`。
- 会同判据（`build\prj\td_00_all_debug.log`）：`PRJ-1406`（syn_1 + phy_1）、`PRJ-1424`、`T07_ALL_DONE`、`T11_DBG_ALL_DONE` 齐；`final_timing.rpt` Confidence=**Routed**。
- TD 窗口互斥：启动前进程检查（`build\preflight-processes.txt`）——无活跃构建会话（无 `run_td`/`td_commands`/`bw_commands`）；`td.exe` PID 45416 与 `hwserver.exe` PID 49924 为夜间 GUI/线缆实例，保持不动、未触碰；构建不依赖线缆；无需等待。

## 2. G2（阈值不放宽；与 r3 基线 debug-fix3 对比）

| 项 | r3 基线 | 本次 | 门槛 | 判定 |
|---|---|---|---|---|
| SWNS / STNS | 0.134 / 0.000 ns | **0.104 / 0.000 ns** | ≥0 | PASS |
| HWNS / HTNS | 0.020 / 0.000 ns | **0.020 / 0.000 ns** | ≥0 | PASS |
| 违例 | 0 | **0**（setup+hold NUM_FEPS=0，0 Viol Endpoints） | 0 | PASS |
| Confidence | Routed | **Routed** | Routed | PASS |
| LUT6 | 16627/71680 (23.20%) | 18722/71680 (26.12%) | 器件内 | PASS |
| slice reg | 21814/143360 (15.22%) | 26555/143360 (18.52%) | 器件内 | PASS |
| ERAM | 151/300 (50.33%) | 162/300 (54.00%) | 器件内 | PASS |
| IO / DSP / PCIE | 107/286, 0/220, 1/1 | 107/286, 0/220, 1/1 | 器件内 | PASS |

- 时钟表（final_timing.rpt）：usr_clk 100.000 / tl_clk_user 62.500 / cam_a_byte_clk 187.547 / cam_b_byte_clk 187.547 / sys_clk 50.000 —— 同基线 5 时钟。
- `ph1p_pcie_integration_chk.timing` 检查表前 24 行与 r3 基线**逐行 IDENTICAL**。
- 资源增量（+2095 LUT6 / +4741 reg / +11 ERAM）与 checker+int 新增逻辑量级一致；时序仍全 ≥0。

## 3. CWC（重生成，含新字探针）

- 实例 `auto_created_cwc1`：**16 view node / 512 trigger / 512 data**（9 既有字 word0..8 + 7 新字 word9..15，`CWC_BUS_NUM=16 × 32bit`；run.log KIT-1004）；`ram_logic_width=513`（512 数据 + 1 状态尾位）、`physical_pieces=26`、`data_coverage=512/512`；探针时钟同基线（tl_clk_user 网络）。
- `compiled.cwc` 143,444 B，SHA256 `8DDA54D4EFA8E6BE728A6EBB34686F25DE90A36B039EDA6F831DFB9C346C664F`；`cw/compiled.bit` 与 `phy_1/ph1p_pcie_integration.bit` 逐字节相同（`5B67A8F5…`，5,224,027 B）=同源配对。
- 校验：`python tools\td\check_chipwatcher_readback.py <cwc> <bid> --multipiece --map-out` → **rc=0，accepted=true，0 失败**（`build\cwc-check.txt`、`build\cwc-multipiece-map.json`）；strict 默认 → rc=1，`accepted=false`（`auto_created_cwc1: BID width mismatch`）→ **默认拒多片行为未改**（`build\cwc-strict-check.txt`）。

## 4. 允许清单 / protected 审计

- 允许清单：P2 **无 RTL/TB/入口改动**；构建输入=worktree 中 P1 冻结的 9 个文件，SHA256 与 P1 manifest r1 逐项全等、git blob 全等（见 candidate-manifest.json `candidate_files`）；写入仅限 run `build/**`。
- protected：旧候选 bit `BFAFDF97…813D0`、CWC `8D2998B9…1026`（debug-fix3）复算未变；共享树零写入；TD 安装目录只读；`workflow\tasks.json` 未写；`e81d353b…`/`2385cded…`/`AFFC4396…` 未触碰。
- 边界：不下载、不触硬件、零 Flash/efuse/SPI/svf、不推送、无 GUI 自动化；G3/G4 not_run。

## 5. 非阻塞观察（供 tester/P4）

1. run.log `PHY-3001` 行 68→69（+1；placer/hold-fix 过程行：如 huge nets 2→3、HPWL 数值变化）；`PHY-1030` 11=11；均为过程报告行、非违例（最终 NUM_FEPS=0）。
2. 会话内 `report_area`/`report_timing` 被跳过（USR-8122/USR-8001）——与基线同现象（CLI 会话未 import netlist）；报告本体在 run 目录（`final_timing.rpt`/`ph1p_pcie_integration_phy.area`）。
3. wall 858.7 s 高于 r3 692.6 s（新增 checker/int 逻辑；仍远低于单会话 30 min 上限）。
4. 沿用 P1 报告 §4 约定：`candidate.diff` 含 2 个追加分隔 CR 字节；1 处 trailing-whitespace 警告（cosmetic）；新文件行尾不对称——跨 checkout 比对用 `git hash-object`（blob）；控制台中文乱码=输出捕获现象。

## 6. lessons（可复用入口）

- L1：构建前进程检查并落盘 `preflight-processes.txt`（活跃会话判定+留证）；既有 GUI/hwserver 实例不触碰。
- L2：CWC 由 `00_all_debug` 单会话自动生成（RTL MARK_DEBUG → insert_debugger → setup_debugger），无需额外 tcl；`cw/` 目录出现即产物齐。
- L3：新字自动进探针集：view nodes=字数、bits=字数×32（本次 16×32=512）。
- L4：校验器用法 `check_chipwatcher_readback.py <cwc> <bid> --multipiece --map-out <map>`；strict 拒绝多片可作“默认行为未改”负证。
- L5：`run_td.ps1` 需显式设置 `$env:TD_BIN`；中文路径由脚本内临时 subst 处理。

## 7. 回退与复测影响（给 tester）

- 回退：丢弃 run `build/**` 产物（默认不删；如删除按根 AGENTS 单文件路径执行或交用户）；旧候选原位；SRAM 重下 ≈30–40 s。
- 复测影响清单：必复测=manifest 全项 SHA256 复算（含 13 项）、multipiece 0 失败、strict 拒多片、bit/CWC/BID 配对、G2 数值复核、工作树 6M+2?? 未变；输入变化=**无**（相对 P1 冻结 RTL）；证据复用=**无**（本包全部证据为本轮生成）。
- 关键证据路径：`build\candidate-manifest.json`、`build\cwc-check.txt`、`build\cwc-multipiece-map.json`、`build\cwc-strict-check.txt`、`build\preflight-processes.txt`、`build\prj\commands.log`、`build\prj\td_00_all_debug.log`、`build\prj\ph1p_pcie_integration_Runs\phy_1\{ph1p_pcie_integration.bit, ph1p_pcie_integration_inst.bid, final_timing.rpt, ph1p_pcie_integration_phy.area, run.log, route_flow.status, ph1p_pcie_integration_chk.timing, cw\compiled.cwc, cw\compiled.bit, cw\auto_created_cwc1\auto_created_cwc1_watcherInst.sv}`。
