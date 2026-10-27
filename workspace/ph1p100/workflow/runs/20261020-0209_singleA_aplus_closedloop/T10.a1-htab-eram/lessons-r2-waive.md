# T10.a1-htab-eram r2-waive lessons

## 1. route-only 的 `launch_runs` 需要先 `import_device`，仅 `open_project` 不够
- 现象：`open_project a1_ht_r2.al` 成功后 `launch_runs phy_1`，生成的 `phy_1/settings.cfg` 里
  `set device_name `、`set package_name ` 为空；`run.exe` 立即报
  `PRJ-8001 ERROR: source ./settings.cfg failed: can't read "device_name": no such variable`。
- 根因：`launch_runs` 的 settings 生成器使用**会话级** device/package 变量。正常流的 `create_project` 会设置它们；route-only 只 `open_project` 不会。
- 修法（按优先级）：
  1. 在 `open_project`/`launch_runs` 前执行 `import_device ph1_100p.db -package PH1P100SBG484 -speed 3`（可配 `open_project -noanalyze`）。
  2. 或者完全绕过 launcher：手工建 phy 运行目录，写完整 `settings.cfg`（`start_step opt_place`、`end_step opt_route`、`device_name ph1_100p.db`、`package_name PH1P100SBG484`、`speed 3`、`parent ../syn_1`、`SDCList {"../../a1_small_top.sdc"}`、`prj_name`），再把 syn 工程的 `.prj` 复制进去，从该目录运行 `DefaultFlow.tcl`；`end_step opt_route` 可直接不跑 bitgen。
- 复用判据：route-only tcl 打印 `PROJECT_OPENED` 后，先检查 phy `settings.cfg` 的 `device_name/package_name` 非空，再 `launch_runs`。

## 2. 坏 run 会吃满整个会话：启动后要尽早检查失败
- 本轮 `run.exe` 在 07:45:01 就因 PRJ-8001 退出（run.log 557 B），但 tcl 仍轮询 `.opt_route.begin.f` **1800 s**，随后 `wait_run` 又等到 shell 60 min 上限，整个 1/1 会话被耗尽，且没有产生任何物理步骤。
- 正确姿势：
  - `launch_runs` 后先等 5~10 s，检查 `phy_1/run.log` 是否含 `PRJ-8001`/`ERROR`，以及 `.opt_place.begin.f` 是否出现；失败立即 `puts` + 退出，不进入长轮询。
  - 轮询上限应远小于会话上限（例如 route 起点 10~15 min），并在 `wait_run` 外包 `catch`；超时先检查 `route_flow.status`/`*.pr.db` 是否存在，而不是无条件等待。
- 本轮 `.stop.f` 的 bitgen 停止逻辑根本没被触发（opt_route 未开始）；因此“bitgen not_run/无 .bit”成立，但这是失败路径的副产品，不是可用的 routed 证据。

## 3. 现成 syn 结果的 route-only 流程要点
- 确认 `syn_1/a1_ht_r2_gate.db` 存在，且 `gate.timing` 与冻结的 `syn_gate_timing_s1.rpt` SHA256 相同（本轮 `40446ba2…`，WNS -0.017、1/4640 端点）。
- phy `settings.cfg` 的 `parent ../syn_1` 必须正确；`SDCList` 用 `../../a1_small_top.sdc`（run 目录相对 td）。
- 布线后单独 `import_db *_pr.db` 再跑 `report_cdc`/`check_timing`；不要依赖 bitgen 流末步。
- 若 `settings.cfg` 的 `end_step` 保持 `bitgen`，就在 `opt_route.begin.f` 出现后写 `.stop.f`，让 bitgen 在 `step_begin` 直接停；本轮因 run 未启动未验证，但这是 flow 里已有的机制（area-map 经验）。

## 4. 失败时的收口
- 未改 RTL/未综合，工作树保持 r2 `0b084317`；本轮新增的 `02_route_only.tcl`、`phy_1` 失败日志、`td_stdout_route_only.log` 保存为证据（含 SHA256）。
- 没有 routed 报告 → G2 不能 PASS；按 dispatch 停止，不自动 r3、不重试、不换 seed/频率/SDC。

## 5. 证据入口
- 结果：`../p4/result-r2-waive.md`；manifest：`../CANDIDATE-MANIFEST-htab-eram-r2-waive.json`
- 失败 run：`r2/td/a1_ht_r2_Runs/phy_1/{settings.cfg,run.log,run.logw}`
- 会话日志：`r2/td/td_stdout_route_only.log`
- tcl：`r2/td/02_route_only.tcl`
- 综合基准：`r2/td/syn_gate_timing_s1.rpt`、`r2/td/syn_gate_area_s1.rpt`
