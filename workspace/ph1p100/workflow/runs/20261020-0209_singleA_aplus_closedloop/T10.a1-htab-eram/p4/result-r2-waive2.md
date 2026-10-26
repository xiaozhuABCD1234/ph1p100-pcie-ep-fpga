# T10.a1-htab-eram r2-waive2 — route-only 成功布通（place 38 s / route 31 s，hold 通过），但 Routed SWNS -0.436 / 138 setup 端点；report_cdc 命令不可用 → blocked（保留 r2 0b084317，无 r3）

- task_id `T10.a1-htab-eram` | round **r2** / revision **r2-waive2**（修正 harness 的 route-only 重试）
- 日期 2026-10-22 | 离线 synthetic；**未综合、未改 RTL**；TD 1/1 会话（远低于 45 min）、route 1/1（完成）、bitgen 0、无 .bit/CWC/下载
- 候选：r2 `0b084317db0608a56865a77fd18e7312add3ddb87c2a465a48f60816d8545396`（工作树未变）
- **唯一判定：blocked。** 物理布线完成且 hold 通过，但 **Routed setup WNS -0.436 ns、138/4514 违例端点**，G2 setup 门槛 FAIL；`report_cdc` 在 TD Release_2026.2 中不存在（`invalid command name`），CDC 证据缺口；按 dispatch 停止，r2 保持最佳功能/综合候选，无 r3。

## 1. Harness 修正（与 r2-waive 的差异）

- 先 `import_device ph1_100p.db -package PH1P100SBG484 -speed 3`，再 `open_project a1_ht_r2.al`、`reset_run phy_1`、`launch_runs phy_1`。
- 12 s 早失败检查：读取 `phy_1/settings.cfg` 的 `device_name/package_name`，检查 `.opt_place.begin.f` 与 `run.log` 的 `PRJ-8001`；不再做 1800 s 轮询。
- 结果：`SETTINGS_CHECK device=ph1_100p.db package=PH1P100SBG484`、`OPT_PLACE_STARTED`；r2-waive 的 PRJ-8001 未再出现。
- 仍在 `opt_route.begin.f` 出现后写 `.stop.f`，让 bitgen 在 `step_begin` 前停止；run.log 结束于 `export_db`，无 bitgen 命令输出、无 .bit。

## 2. Routed 结果（全部门槛）

| 项 | 目标 | 实测 | 结论 |
|---|---|---|---|
| 状态 | Routed | **Routed** | PASS |
| Routed S WNS | ≥0 | **-0.436 ns** | **FAIL** |
| Routed S TNS | ≥0 | **-26.919 ns** | **FAIL** |
| setup 违例端点 | 0 | **138/4514** | **FAIL** |
| Routed H WNS / TNS | ≥0 | **+0.020 / 0.000 ns** | PASS |
| hold 违例端点 | 0 | **0** | PASS |
| 资源 | 在器件内 | slice **2974**/71680、LUT6 2886、reg 1641、ERAM **26**、DRAM LUT 32、gclk 1、sclk 4、DSP 0 | PASS |
| report_cdc | 实际执行 | **未执行**：TD 2026.2 `invalid command name "report_cdc"`，无 cdc.rpt | **FAIL（证据缺口）** |
| check_timing | 实际执行 | **已执行**：`check_timing.rpt` 4865 B | PASS |
| bitgen / .bit | not_run | not_run；无 .bit/CWC/下载 | PASS |

- **最差路径**：`u_dut/u_core/bm_a_syn_41.clkb`（ERAM clk2q）→ … → `u_dut/u_core/state_reg[5]_syn_7.ceb`，5.245 ns（cell 3.228 / net 2.017），4 级（LUT6×2、LUT4、LUT3），slack **-0.436 ns**。
- 与综合对比：r2 s1 SWNS **-0.017**（1/4640 端点）→ 布线 **-0.436**（138/4514）。综合到布线的净延迟差约 0.42 ns，放弃综合 WNS≥0 门槛的 -17 ps 余量不足以覆盖物理布线；这正是该门控存在的原因。
- 布线资源与综合一致（ERAM 26、DRAM LUT 32），没有资源/拥塞问题；纯 setup 时序不收敛。
- `route_flow.status`：place 38 s、route 31 s、fix_hold 2 s、phys_opt 1 s，总 run 1m11s；hold fix 已执行且 hold 通过。

## 3. 判定与停止依据

- dispatch 未豁免的最终门槛：Routed WNS/TNS/HWNS/HTNS≥0、0 违例、资源在器件内、report_cdc/check_timing 实际执行、bitgen not_run。
- 实测：**Routed SWNS -0.436 / STNS -26.919 / 138 端点**（FAIL）；report_cdc 未执行（FAIL/证据缺口）；hold、资源、check_timing、bitgen 通过。
- 停止依据：`Routed WNS<0 -> stop; keep r2`、`report_cdc ... not executed -> G2 cannot PASS`、`1 session/1 route exhausted -> no r3`。未再综合、未改 RTL、未重跑、未调 QoR/seed/频率/SDC。

## 4. 预算

| 项 | 用/上限 |
|---|---|
| TD 会话 | **1/1**（route+reports 约 2–3 min，远低于 45 min） |
| 综合 | 0（未调用） |
| 布线 | **1/1**（Routed 完成） |
| bitgen / .bit / 下载 / Flash | 0 / 0 / 0 / 0 |
| 开发 | 约 20 min / 6 calls |

## 5. 结论与最小下一步（交规划）

- **r2 `0b084317` 仍是最佳功能/综合候选**（P2/P3 33/33 逐位不变、P2 comp 355,261、1080p 4.68–4.87M、综合 -0.017），但**没有 routed PASS**；本次物理结果是 SWNS -0.436 / 138 端点，不能作为 G2 候选。
- 继续收口需要**真正的 RTL/时序改动**（例如把 hit/hent 相关 stage-1 逻辑再寄存一级并重做流水对齐，或重构状态 CE 锥），而不是继续 waive 或调 QoR；同时需要新的用户/规划授权与综合/布线预算。
- **CDC 工具限制**：TD Release_2026.2 没有 `report_cdc` 命令（`invalid command name`），本轮无法产出 cdc.rpt；独立测试若要 G2 PASS，必须接受等价的 CDC 证据方案（例如另一版本的 TD、专用 CDC 工具或对同一网表的静态 CDC 分析），不能在报告中伪造“已执行”。`check_timing.rpt` 已实际执行。
- bitgen 未运行、无 .bit；不下载、不写 Flash。

## 6. 回退 / 复现

- 未改 RTL，工作树仍为 `0b084317`；frame `18d51b1b`、SDC `227dd39e` 未改。
- 回退点：`r2/candidate-0b084317.a1_deflate_core.v`（最佳功能/综合）、`r1/candidate-3326a1fa…v`、`r0/candidate-b374f6fc…v`、`r0/base-1dca732b…v`。
- 复现 route-only：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\td\td_env.ps1 -Force -TdDir "workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-htab-eram\r2\td"
cd T:\; D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe T:/03_route_only_fixed.tcl
```
- 原始 routed 证据：`r2/td/phy_pr_timing.rpt`、`phy_timing_status.rpt`、`phy_area.rpt`、`route_flow.status`、`route_raw.qor`、`check_timing.rpt`；raw phy 目录 `r2/td/a1_ht_r2_Runs/phy_1/`（含 `a1_ht_r2_pr.timing`、`a1_ht_r2_phy.area`、`a1_ht_r2_pr.db`、`run.log`、`.stop.f`）。
