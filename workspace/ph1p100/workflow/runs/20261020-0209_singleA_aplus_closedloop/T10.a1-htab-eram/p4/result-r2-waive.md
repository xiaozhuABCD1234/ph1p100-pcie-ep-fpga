# T10.a1-htab-eram r2-waive — route-only 尝试在 phy 启动前因 `settings.cfg` 缺 `device_name/package_name` 失败（PRJ-8001）；未 place/route，60 min 会话用尽 → blocked

- task_id `T10.a1-htab-eram` | round **r2** / revision **r2-waive**（一次性例外：仅布线）
- 日期 2026-10-22 | 离线 synthetic；**未综合、未改 RTL**；TD 会话 1/1（60 min 上限）、布线调用 1 次但 **0 次真正 place/route**、bitgen 0、无 .bit/CWC/下载
- 候选：r2 最佳 `0b084317db0608a56865a77fd18e7312add3ddb87c2a465a48f60816d8545396`（工作树未变）
- **唯一判定：blocked。** 唯一一次 route-only 尝试在 `run.exe` 读取 phy `settings.cfg` 时即失败（`device_name`/`package_name` 为空，PRJ-8001），没有进入 opt_place/opt_route，因此没有 routed 报告；按 dispatch 停止，r2 `0b084317` 保持最佳候选，无 r3。

## 1. 尝试内容（无综合、无 RTL 改动）

- 使用 r2 已有的 syn_1 结果（`r2/td/a1_ht_r2_Runs/syn_1/a1_ht_r2_gate.db`，gate.timing 与 `r2/td/syn_gate_timing_s1.rpt` SHA256 相同，SWNS -0.017、1/4640 端点、slice 3068、ERAM 26）。
- 新增 `r2/td/02_route_only.tcl`：`open_project a1_ht_r2.al` → `launch_runs { phy_1 } -jobs 4` → 轮询 `.opt_route.begin.f` → 写 `.stop.f` 让 bitgen 在 step_begin 直接停 → `wait_run` → `import_db *_pr.db` → `report_timing_summary/status/area/timing/qor/clock_utilization` + `report_cdc` + `check_timing`。
- 未调用 `create_project`/`launch_runs syn_1`，未改任何 RTL/SDC/frame。

## 2. 失败事实与根因

| 项 | 实测 | 证据 |
|---|---|---|
| 打开工程 | 成功，analyze 3 个源文件 | `td_stdout_route_only.log` 的 `PROJECT_OPENED` |
| 启动 phy | `phy_1 is launched`，run 目录生成 | `a1_ht_r2_Runs/phy_1/` |
| **run.exe 立即失败** | `PRJ-8001 ERROR: source ./settings.cfg failed: can't read "device_name": no such variable` | `phy_1/run.log`、`run.logw` |
| 生成的 settings.cfg | `set device_name `、`set package_name ` 为空；`start_step opt_place`、`end_step bitgen`、`parent ../syn_1` | `phy_1/settings.cfg` |
| opt_place/opt_route | 未开始；轮询 1800 s 无 `.opt_route.begin.f`，也无 `.opt_place.begin.f` | `td_stdout_route_only.log` 的 `PHY_ROUTE_NOT_STARTED waited=1800s` |
| 会话结束 | `wait_run` 一直等到 shell 60 min 上限，TD 父进程被终止 | 无 `.pr.db`、无 routed 报告 |
| bitgen/.bit | 未调用、未生成 | 目录无 .bit/CWC；`phys_1/run.log` 在 settings 处即失败 |

**根因**：route-only tcl 只 `open_project a1_ht_r2.al`，没有先执行 `import_device ph1_100p.db -package PH1P100SBG484 -speed 3`。`launch_runs` 生成 phy `settings.cfg` 时使用的是会话里的 device/package 变量；正常流程的 `create_project` 会设置它们，单纯 `open_project` 不会。于是 `settings.cfg` 里 `device_name/package_name` 为空，`run.exe` 在 `source ./settings.cfg` 处就报错，物理流程一步都没跑。

## 3. 门槛判定

| 项 | 目标 | 实测 | 结论 |
|---|---|---|---|
| Routed | 完成 | **未开始**（PRJ-8001） | **FAIL（未布通）** |
| Routed WNS/TNS/HWNS/HTNS | ≥0 | 无数据 | 无法判定 |
| 0 违例 | 0 | 无数据 | 无法判定 |
| 资源在器件内 | 是 | 综合 3068/71680、ERAM 26；未到 route | 仅综合证据 |
| report_cdc | 实际执行 | **未执行**（无 routed DB） | **FAIL（证据缺失）** |
| check_timing | 实际执行 | **未执行**（无 routed DB） | **FAIL（证据缺失）** |
| bitgen | not_run | not_run，无 .bit | PASS |

## 4. 预算与停止依据

| 项 | 用/上限 |
|---|---|
| TD 会话 | **1/1**（60 min，被 shell 上限终止） |
| 综合 | 0/0（未调用） |
| 布线 | 调用 1/1，**真正 place/route 0 次** |
| bitgen / .bit / 下载 / Flash | 0 / 0 / 0 / 0 |
| 开发 | 约 75 min 墙钟（含 60 min 会话）/ 约 8 calls |

停止依据：dispatch `Route not Routed -> stop; keep r2 0b084317`、`1 session/60 min or 1 route exhausted -> stop; no r3`、`report_cdc or check_timing not actually executed -> G2 cannot PASS`。未再开新会话、未综合、未改 RTL。

## 5. 结论与最小下一步（交规划）

- **r2 `0b084317` 仍是最佳候选**：功能 33/33 逐位不变、P2 comp 355,261、1080p 4.68–4.87M；综合 WNS -0.017 / 1 端点 / ERAM 26 / slice 3068。**没有 routed 证据**。
- 若未来获得新的明确授权再做 route-only，修正点是：
  1. 在 `open_project`/`launch_runs` 之前执行 `import_device ph1_100p.db -package PH1P100SBG484 -speed 3`（或 `open_project -noanalyze` 前先 import_device），确保生成的 phy `settings.cfg` 含非空 `device_name/package_name`；
  2. 或者不用 launcher：手工建 `phy_1` 运行目录，写完整 `settings.cfg`（`start_step opt_place`、`end_step opt_route`、`device_name ph1_100p.db`、`package_name PH1P100SBG484`、`parent ../syn_1`、`SDCList`），从该目录运行 `DefaultFlow.tcl`；
  3. 启动后 ~60 s 检查 `run.log` 是否已有 `PRJ-8001`/无 `.opt_place.begin.f`，若失败立即停止，避免把 60 min 会话耗在 wait_run 上；
  4. 仍保留 `.stop.f` 在 bitgen 前停止的规则，并单独跑 report_cdc/check_timing。
- 本轮无 r3、无额外综合/布线额度；不得 seed sweep、降频、false path/multicycle 或改 SDC。

## 6. 回退

- 未改 RTL，工作树仍为 `0b084317`；frame/SDC 未改。
- 恢复点：`r2/candidate-0b084317.a1_deflate_core.v`（最佳）、`r1/candidate-3326a1fa…v`、`r0/candidate-b374f6fc…v`、`r0/base-1dca732b…v`。
- 本轮新增的 `r2/td/02_route_only.tcl` 与 `phy_1` 失败日志仅作证据，可保留；如清理，只删明确路径文件，不批量删除。

## 7. 复现

```powershell
# 仅复现 route-only 会话（注意：当前 tcl 已知缺 import_device，复现会得到同一 PRJ-8001）
powershell -NoProfile -ExecutionPolicy Bypass -File tools\td\td_env.ps1 -Force -TdDir "workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-htab-eram\r2\td"
cd T:\; D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe T:/02_route_only.tcl
# 修正版应先 import_device ph1_100p.db -package PH1P100SBG484 -speed 3，再 open_project/launch_runs
```
