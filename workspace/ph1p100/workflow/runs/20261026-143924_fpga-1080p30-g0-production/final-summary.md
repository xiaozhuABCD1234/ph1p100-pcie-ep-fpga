# final-summary — `20261026-143924_fpga-1080p30-g0-production`（已收尾）

- 主题：1080p30 G0 生产前提收口；run 状态：**finished**（P1 r1b / P2 r1 / P3 r0 / P4 r0 均 PASS）
- **本文件为收尾版**，优先于 P4 候选内的 `final-summary.md` 草案（草案状态为 ready_for_test，已由 P4 PASS 取代；“A+H 唯一”已按 OBS-2 修正为“最小/首选”）。
- **run 级 headline：`G0_not_closed`**（不是 G0 通过；P4 PASS 只表示合并/判定/证据绑定正确）
- 依据：P4 综合报告 `test-reports/T10.ss-g0-prod-verdict-r0-integrated.md`；P4 manifest `8460fb8d…`（9 artifacts）；上游 124 artifacts（P1 70 + P2 49 + P3 5）0 mismatch
- 工具/动作：P1 4 次全尺寸 vsim（86.1 min）、P2 3 次 1 帧探针（34.93 min）、P3/P4 0 sim；**全程 0 TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK/网络**

## 1. 四包结果

| 包 | 结论 | 关键数字 | manifest |
|---|---|---|---|
| P1 `T10.ss-g0-prod-content` | PASS r1b（gate correction，0 重跑） | N `S_ss=7,475,240`（25.083 fps / 65.015 MB/s / **−16.3906%**）；L `6,986,952`（26.836 fps / 69.558 MB/s / **−10.5475%**）；两类 `core_interval` 主导（N 7,475,238 vs export 3,354,672；L 6,986,951 vs 4,312,600）；`dup` 只记录 | `e306ed42…`（70） |
| P2 `T10.ss-g0-prod-coregap` | PASS r1（文档重绑；`conditional`） | A+H 6,008,078 / 2.3179 c/B / **+4.027%** 仅算术；包络 **45.034%**；单 H 6,260,648（−0.17%）；224.3 MHz 仅 0.006% 余量；双核 per-stream 不变 7,476,245 | `803d3efb…`（49） |
| P3 `T10.ss-g0-prod-sink` | PASS r0（0 sim） | comp 需求 50.32/64.69 MB/s @33.33 ms、67.09/86.25 @25 ms，均 <93.75（最紧 L 占 92.0%）；raw band 93.75→5,189,412 cycles/83.03%，103.79→4,687,500/75.0%，25 ms 缺口 **10.7075%**；生产 sink 未证 | `de8a5cff…`（5） |
| P4 `T10.ss-g0-prod-verdict` | **PASS r0（0 sim）** | 合并 124 artifacts、六条强制陈述、scope tuple、用户决策、恢复入口；headline `G0_not_closed` | `8460fb8d…`（9） |

## 2. 六条强制陈述

1. **当前 core + 187.5 MHz 不能闭合自然内容**：N 7,475,240（−16.3906%）、L 6,986,952（−10.5475%），两类 core-bound；L_cold 12,440,137 / 12,901,615 单列、不进 `S_ss`。
2. **A+H 只是算术候选**：6,008,078 / 2.3179 c/B / +4.027%，包络 45.034% → `conditional`；**不是 G0 closure、未实现**。注：A+B+H（5,916,475，+5.64%）与 A_full+H（3,970,580，乐观上界）也是算术闭合，但 B/C matcher 未验证、2% credit 是 assumed；A+H 是**最小/首选**组合，不是唯一。
3. **仅提时钟不可行**：b11 Routed WNS +0.015 ns @187.5 → 关键路径约 5.318 ns ≈188.0 MHz；209.6/224.3 MHz 需重流水，224.3 仅 0.006% 算术余量。
4. **双核不提高 per-stream**：单路仍 7,476,245 cycles（75.684 MB/s）；ERAM 231–289/300、双核时序 unproven。
5. **sink**：93.75 MB/s 对实测 comp 路径够用（最紧 L@25 ms 86.25，占 92.0%）；raw band ≥103.79 MB/s 未实现/未证，只对 RAW fallback（stored）有意义；生产 115200 UART 约 11.52 kB/s。
6. **用户决策**：坚持 1080p30、不降档；需决定 ① core 结构改版（A+H 原型 + TD/时序/资源 + 板级 + 4 帧复测）；② 换核/换算法；③ 接受 `G0_not_closed` 边界。降档需用户明确授权，本轮不主推。

## 3. `sink_limited` 口径澄清（run 级）

- `tail_frac ≥ 50%` 只是**诊断旗标**；只有**sink 忙碌率** `busy = export_time / S_ss ≥ 0.95` 才阻断为 `G0_not_proven`。
- P1：N `tail_frac=44.8783%`、`busy=44.8771%`；L `tail_frac=61.7249%`、`busy=61.7236%`；均 <0.95 → 两类均为 `G0_not_closed`。
- 向后兼容：P4 四轮矩阵 R3 `busy=99.998%` 仍 `sink_limited`/`G0_not_proven`；R1/R2/R4 `busy≤28.64%` 不受影响。
- P1/P3 报告的 `G0_not_proven` headline 在 run 级被修正；**数值/证据不变、原报告不改写**；P2 headline 已是 `G0_not_closed`。

## 4. scope tuple（不可外推）

`content` = P1 自然场景/低照图像派生 Bayer（`natural_scene_image`/`low_light_natural_scene` + `proxy_not_natural_raw`/`not_sensor_raw`/`proxy_not_worst`/`display_referred`，**非传感器 RAW**）；`pacing` = TB `wait_slot_free`（非生产自由跑）；`sink` = 93.75 MB/s TB 代理（非生产 sink）；`DDR` = 行为级 256-bit PAXI；`core/clock` = 单核 187.5 MHz；`stream` = 单路。

## 5. 能说 / 不能说

- **能说**：在上述 scope 内，自然/低照内容的 4 帧实测 G0 未闭合且 gap 可量化；core 是主约束、sink 不是；A+H 是有条件候选；当前 187.5 MHz 不可闭合；P3 的 93.75 对 comp 够用。
- **不能说**：G0 已闭合/feasible；A+H 已实现；真实传感器 RAW/光学/噪声；最坏/全内容；生产 sink ≥103.79；真实 DDR/PCIe/UART sustained；板级/bit/Flash；双路；RK/NPU；用 G25 降档；用 P4 合成 C1 的 `G0_feasible_for_scope` 覆盖自然内容。

## 6. 过程与偏差（如实保留）

- P1：r0 看门狗 12M 误当首帧门槛 → r1 两段式（cold 20M/steady 12M）修 harness；r1 `dup=0` 门槛与自然内容不兼容 → r1b 裁决 A（`dup` 只记录），0 重跑转 PASS。P1 全尺寸 4/6、vsim 86.1/200 min。
- P2：r0 3 探针（2 证据 + 1 harness 重试）34.93 min；dev 49 calls >40（OBS-5，已披露、无仿真增量）；r1 文档重冻 0 sim，原地覆盖 7 个 r0 文档文件（OBS-8：r0 不可再复现，P4 以 r1 为准）。
- P3：0 sim；dev 17 calls/16 min；tester 49 calls >20（0 sim、无门槛放宽）。
- P4：0 sim；dev 31 calls >25（OBS-4）；tester 调用亦超 25（自披露）；0 证据增量、无 D1–D10 影响。
- P1 负对照 4 条的准确位置是 `test-reports/T10.ss-g0-prod-content-r1-integrated.md` §8（不是 r1b §8）；P4 的 evidence-binding 指针需按此理解（OBS-1）。
- P1 `manifest-r1` 内嵌 `A3_complete=false`/`headline=G0_not_proven` 是 r1b 裁决前的冻结字段；r1b PASS 报告已取代，P4 已说明（OBS-5）。
- P4 `build_verdict.py:139` 有重复条件（OBS-3，工具卫生，不影响 JSON 值）。

## 7. 未证 / 剩余风险

传感器 RAW/噪声/光学；最坏/全内容；生产 pacing/sink（UART ≈11.52 kB/s）；真实 DDR/PAXI sustained；PCIe/UART sustained；板级/bit/Flash/COM/JTAG；双路；RK/NPU；A+H 实现后的时序/资源（0 TD）；A+B+H 的 matcher 增益（未验证）；P2 r0 文档不可复现（OBS-8）。

## 8. 下一步（准确文本；不得说 G0 已闭）

**若要继续 1080p30（推荐先做 core 原型）**：
```text
$fpga-orchestrator 执行：在 D:/fpga/ph1p100 新建 run，任务 T10.F5-core-aplus-h-prototype：
基于 run 20261026-143924_fpga-1080p30-g0-production 的 P2-r1 A+H（2-position scan + 2 B/cycle replay）
做隔离 RTL 原型；验收：1 帧 stage probe <=2.411 cycles/B，TD 综合+布线 WNS>=0、ERAM<=300，
然后 4 帧 G0@187.5MHz；允许 TD，不允许板卡/Flash；不改生产源。
```
（OpenCode 前缀 `/fpga-orchestrator`；Codex 前缀 `$fpga-orchestrator`。）

**若先用真实内容复核**：
```text
$fpga-orchestrator 执行：在 D:/fpga/ph1p100 新建 run，任务 T10.F1-real-raw-content：
以真实 IMX415 RAW（或用户提供的传感器 RAW）复核 P1 的 N/L 4 帧 core_interval 与 G0；
无真实 RAW 时只允许标注 proxy_not_natural，不得冒充。
```

**本 run 恢复入口**（仅收尾/文档）：
```text
$fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production；本轮目标：<目标>
```

- 本 run 不再开新包；`workflow/tasks.json` 未改；P1–P4 候选/报告未改。
