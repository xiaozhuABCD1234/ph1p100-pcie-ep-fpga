# T10.a1-htab-eram r2-waive2 lessons

## 1. route-only harness 的正确姿势（已在本轮验证）
- 必须先 `import_device ph1_100p.db -package PH1P100SBG484 -speed 3`，再 `open_project a1_ht_r2.al`、`reset_run phy_1`、`launch_runs phy_1`。本轮生成的 `phy_1/settings.cfg` 为：
  `set device_name ph1_100p.db`、`set package_name PH1P100SBG484`、`set start_step opt_place`、`set end_step bitgen`、`set parent ../syn_1`；r2-waive 的 PRJ-8001 未再出现。
- 12 s 早失败检查足够：settings.cfg 的 device/package 非空 + `.opt_place.begin.f` 出现；若 `run.log` 含 PRJ-8001 立即退出。不要再做 1800 s 轮询。
- `.stop.f` 在 `opt_route.begin.f` 出现后写入，flow 在 bitgen 的 `step_begin` 前停止；run.log 结束于 `export_db`，无 bitgen 输出、无 .bit。该机制在本轮得到验证。
- 本轮 place 38 s、route 31 s、fix_hold 2 s、phys_opt 1 s；本设计已经很小（slice ~3k），布线本身很快，时间都花在时序收敛而不是布局布线。

## 2. 综合 -0.017 → 布线 -0.436：waive 的余量没有覆盖物理延迟
- 综合 SWNS -0.017（1/4640 端点）→ 布线 SWNS **-0.436**（138/4514 端点），净延迟差约 0.42 ns。
- 最差路径仍是 `bm_a ERAM clk2q → state_reg[5].ceb`（5.245 ns，4 级），不是 DRAM 长线、也不是资源/拥塞；是纯组合时序深度。
- 结论：综合 WNS 的 +0.5 门槛（后来降到 0）不是形式主义；-17 ps 的综合结果在布线后变成 -436 ps。**route-only waiver 是合理的有限实验，但不能替代真实的 RTL 时序修复**。
- 后续若继续，应该做真正的结构改动（例如把 hit/hent 相关 stage-1 或 state CE 锥再寄存一级并重做流水对齐），而不是继续 waive、调 QoR、seed 或降频。

## 3. TD Release_2026.2 没有 `report_cdc`
- `report_cdc -file cdc.rpt` 返回 `invalid command name "report_cdc"`；本版本 TD 没有该命令，无法在 route 后产出 cdc.rpt。
- `check_timing -verbose -file check_timing.rpt` 正常执行（4865 B），`route_flow.status`、`route.qor`、`*_pr.timing`、`*_phy.area` 均完整。
- 对独立测试的含义：G2 的 CDC 门槛不能靠“TD 流末步”或伪造报告满足；需要等价方案（另一版本 TD、专用 CDC 工具、或对同一网表的静态 CDC 分析），并在报告中明确证据来源。本轮如实记录为证据缺口。

## 4. 结果与边界
- Routed：SWNS -0.436 / STNS -26.919 / 138 setup 端点；HWNS +0.020 / HTNS 0.000 / 0 hold 端点；slice 2974/71680、ERAM 26、DRAM LUT 32、reg 1641；资源在器件内。
- bitgen not_run、无 .bit/CWC/下载；未改 RTL/未综合；候选仍为 r2 `0b084317`。
- 按 dispatch：Routed WNS<0 + report_cdc 未执行 → G2 不能 PASS；停止，保留 r2 最佳，无 r3、无自动扩轮。

## 5. 证据入口
- 结果：`../p4/result-r2-waive2.md`；manifest：`../CANDIDATE-MANIFEST-htab-eram-r2-waive2.json`
- tcl：`r2/td/03_route_only_fixed.tcl`；stdout：`r2/td/td_stdout_route_only_w2.log`
- routed：`r2/td/phy_pr_timing.rpt`、`phy_timing_status.rpt`、`phy_area.rpt`、`route_flow.status`、`route_raw.qor`、`check_timing.rpt`
- raw phy：`r2/td/a1_ht_r2_Runs/phy_1/{a1_ht_r2_pr.timing,a1_ht_r2_phy.area,a1_ht_r2_pr.db,run.log,settings.cfg,.stop.f}`
- 无 cdc.rpt（TD 2026.2 无 report_cdc）
