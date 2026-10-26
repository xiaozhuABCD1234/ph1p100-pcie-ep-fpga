# final-summary（P4 起草；P4 PASS 后由原规划复核并正式收尾）

- run：`20261026-143924_fpga-1080p30-g0-production`；主题：1080p30 G0 生产前提收口
- 状态：P1 PASS r1b、P2 PASS r1（`conditional`）、P3 PASS r0、**P4 `T10.ss-g0-prod-verdict` ready_for_test（round0，0 sim）**
- **run 级 headline：`G0_not_closed`**

## 1. 四包结果

| 包 | 结果 | 关键证据 |
|---|---|---|
| P1 `T10.ss-g0-prod-content` | PASS r1b | 自然/低照各 4 帧实测：N `S_ss=7,475,240`（−16.3906%）、L 6,986,952（−10.5475%），两类 core-bound；`dup` 为内容统计量、只记录 |
| P2 `T10.ss-g0-prod-coregap` | PASS r1（`conditional`） | 8 行矩阵 + 模型（残差 ≤5%、LOO）；A+H 6,008,078/2.3179 c/B/+4.027% 是唯一 187.5 MHz 算术闭合，包络 45.034%；单 H 6,260,648（−0.17%）；时钟/双核不可行 |
| P3 `T10.ss-g0-prod-sink` | PASS r0 | 93.75 对实测 comp 有余量（最紧 L@25 ms 86.25，占 92.0%）；raw band ≥103.788 未实现/未证、只对 RAW fallback |
| P4 `T10.ss-g0-prod-verdict` | **ready_for_test** | 合并判定 + scope + 六条强制陈述 + 用户决策 + 恢复入口；124 个上游 artifact SHA 复核 0 mismatch |

## 2. run 级结论

1. 当前 **单核 + 187.5 MHz 不能闭合自然内容**；N/L 缺口是实测的 core 缺口，不是 sink。
2. **`sink_limited` 口径修正**：`tail_frac≥50%` 只是诊断旗标；仅 `busy=export_time/S_ss≥0.95` 阻断为 `G0_not_proven`。L `busy=61.72%` → 由 `G0_not_proven` 重分类为 **`G0_not_closed`（−10.5475%）**；N `busy=44.88%` 同类。P1/P3 原报告 headline 为 `G0_not_proven`，run 级修正；**数值/证据不变、原报告不改写**（P2 headline 已是 `G0_not_closed`）。
3. A+H 只是**算术**候选（`conditional`、未实现）；仅提时钟与双核都不解决 per-stream；P3 的 93.75 够 comp、不够 raw band 25 ms。
4. 用户坚持 1080p30、不降档；需决定 core 结构改版 / 换核或算法 / 接受边界；降档需用户明确授权，本轮不主推。

## 3. scope（不可外推）

content = P1 自然/低照图像派生 Bayer（**非传感器 RAW**）；pacing = TB `wait_slot_free`；sink = 93.75 TB 代理；DDR = 行为 256-bit PAXI；core/clock = 单核 187.5 MHz；stream = 单路。

## 4. 未证 / 风险

传感器 RAW/噪声/光学、最坏/全内容、生产 pacing/sink（现有 UART ≈11.52 kB/s）、真实 DDR/PCIe sustained、板级、双路、A+H 实现后的时序/资源（0 TD）——均未测。P2 r1 原地覆盖 r0 文档（OBS-8），只能复现 r1。

## 5. 下一步

1. 新综合测试者对 P4 做 round0（仅 integrated、0 sim、D1–D10），报告 `test-reports/T10.ss-g0-prod-verdict-r0-integrated.md`。
2. PASS 后由原规划复核三份 summary、更新 dispatch/任务板并收尾本 run。
3. 用户决策后另开新 run：core 结构改版（A+H 原型 + TD + 板级 + 4 帧复测）或换核/换算法；本 run 不再开新包。

## 6. 恢复入口

`恢复：D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production；本轮目标：<目标>`（Codex 前缀 `$fpga-orchestrator`，OpenCode 前缀 `/fpga-orchestrator`）。
