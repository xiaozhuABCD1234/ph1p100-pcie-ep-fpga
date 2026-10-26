# handoff — `20261026-143924_fpga-1080p30-g0-production`（finished）

- 状态：**finished**；四包均 PASS；run 级 headline **`G0_not_closed`**（不是 G0 通过）
- **本文件为收尾版**，优先于 P4 候选目录内的 `handoff.md`/`final-summary.md`/`user-summary.md` 草案（草案状态仍写 ready_for_test，已由 P4 PASS 取代；其中“A+H 唯一”已按 OBS-2 修正为“最小/首选”）。
- 收尾文件：本文件、`final-summary.md`、`user-summary.md`；规划：`dev-plan.md`、`fpga-design-guide.md`、`input-index.md`、`r1b-ruling.md`、`round1-ruling.md`、`p2-obs-ruling.md`、`p4-release-ruling.md`、`dispatch.json`
- 0 TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK/网络；未改 `workflow/tasks.json`、P1–P4 候选/报告、生产源、旧 run

## 1. 冻结候选与报告（唯一绑定）

| 包 | 验收 | manifest SHA-256 | artifacts | 报告 |
|---|---|---|---:|---|
| P1 `T10.ss-g0-prod-content` | PASS r1b | `e306ed42ed47dbcec6127bf2faee88925a9a88ae8a5ef07ecbda8dda91fe1fd9` | 70 | `test-reports/T10.ss-g0-prod-content-r1b-integrated.md`（+ r1 报告 §8 负对照） |
| P2 `T10.ss-g0-prod-coregap` | PASS r1 | `803d3efb0104376004eb46c2b633d9b19577ba746190edadea802f81e3b92a66` | 49 | `test-reports/T10.ss-g0-prod-coregap-r1-integrated.md`（r0 报告保留） |
| P3 `T10.ss-g0-prod-sink` | PASS r0 | `de8a5cffb8044828d2c4eb0ae72d1959c5267a06744a4002bf60a413995aa139` | 5 | `test-reports/T10.ss-g0-prod-sink-r0-integrated.md` |
| P4 `T10.ss-g0-prod-verdict` | PASS r0 | `8460fb8da43a2e21a9b39074bf99815d445a82852874100df1a97aad3a5a7a28` | 9 | `test-reports/T10.ss-g0-prod-verdict-r0-integrated.md` |

- 上游合计 **124 artifacts，0 mismatch**（P1 70 + P2 49 + P3 5）；P4 自身 9/9 稳定。
- P2 必须绑 **r1**：r1 原地覆盖了 7 个 r0 文档（OBS-8），r0 不再可复现；P4 已只引 r1。
- P1 的 4 条负对照在 **r1 报告 §8**（不是 r1b §8）；P1 `manifest-r1` 的 `A3_complete=false` 是 r1b 前冻结字段，已由 r1b PASS 取代。

## 2. 结果摘要

- P1：N `S_ss=7,475,240`（−16.3906%）、L `6,986,952`（−10.5475%）；core-bound（N 7,475,238 vs export 3,354,672；L 6,986,951 vs 4,312,600）；`L_cold` 12,440,137 / 12,901,615 单列。
- P2：`closable_at_187_5=conditional`；A+H 6,008,078 / 2.3179 c/B / +4.027%（最小/首选算术组合，非唯一；A+B+H 5,916,475 也算术闭合但 matcher 未验证）；包络 45.034%；单 H 6,260,648（−0.17%）；224.3 MHz 仅 0.006%；双核 per-stream 不变。
- P3：93.75 对实测 comp 够用（最紧 L@25 ms 86.25，占 92.0%）；raw band 25 ms 需 103.788，93.75 短 10.7075%，生产 sink 未实现/未证。
- P4：headline `G0_not_closed`；六条强制陈述、scope tuple、能说/不能说、风险、用户决策、恢复入口齐全。

## 3. `sink_limited` 澄清（关键口径）

`tail_frac≥50%` 只是诊断；只有 `busy=export_time/S_ss≥0.95` 才判 `G0_not_proven`。
N `busy=44.8771%`、L `busy=61.7236%` → 两类 `G0_not_closed`；P4 四轮 R3 `busy=99.998%` 仍 sink-limited，历史判定不变。P1/P3 原 `G0_not_proven` headline 在 run 级修正，数值/证据不变、原报告不改写。

## 4. 过程偏差（保留、不追改判）

| 项 | 事实 | 处理 |
|---|---|---|
| P1 r0→r1 | 12M 看门狗误当首帧门槛；两段式 cold 20M/steady 12M 修 harness | 已修，0 改 DUT |
| P1 r1→r1b | `dup=0` 与自然内容不兼容；裁决 A：`dup` 只记录 | 0 重跑转 PASS，不占修复轮 |
| P2 r0 | dev 49 calls > 40；3 探针（2 证据 + 1 harness 重试）34.93 min | OBS-5 登记，无仿真增量 |
| P2 r1 | 0 sim 文档重冻；原地覆盖 7 个 r0 文件（OBS-8） | r1 为唯一绑定；r0 不可复现 |
| P3 | tester 49 calls > 20（0 sim） | 自披露，无门槛放宽 |
| P4 | dev 31 calls > 25；tester 调用亦超 25；`build_verdict.py:139` 重复条件（OBS-3） | 自披露，无证据增量；工具卫生待下次修 |
| P1 负对照指针 | P4 evidence-binding 写 r1b §8，实际在 r1 §8（OBS-1） | 以 r1 报告 §8 为准 |
| P1 manifest 字段 | `A3_complete=false` 为 r1b 前冻结值（OBS-5） | 以 r1b PASS 为准 |

## 5. 下一次启动（准确文本；不得说 G0 已闭）

**A+H core 原型（推荐先做）**：
```text
$fpga-orchestrator 执行：在 D:/fpga/ph1p100 新建 run，任务 T10.F5-core-aplus-h-prototype：
基于 run 20261026-143924_fpga-1080p30-g0-production 的 P2-r1 A+H（2-position scan + 2 B/cycle replay）
做隔离 RTL 原型；验收：1 帧 stage probe <=2.411 cycles/B，TD 综合+布线 WNS>=0、ERAM<=300，
然后 4 帧 G0@187.5MHz；允许 TD，不允许板卡/Flash；不改生产源。
```

**真实 RAW 复核**：
```text
$fpga-orchestrator 执行：在 D:/fpga/ph1p100 新建 run，任务 T10.F1-real-raw-content：
以真实 IMX415 RAW（或用户提供的传感器 RAW）复核 P1 的 N/L 4 帧 core_interval 与 G0；
无真实 RAW 时只允许标注 proxy_not_natural，不得冒充。
```

**本 run 恢复（仅收尾/文档）**：
```text
$fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production；本轮目标：<目标>
```
（OpenCode 前缀 `/fpga-orchestrator`。）

## 6. 回退

- 本 run 为纯新增离线 run，未改生产 RTL/内容源/tasks.json；删除/忽略四个 `T10.ss-g0-prod-*` 目录即回到 P4 冻结态。P1/P2/P3/P4 候选与报告不互相覆盖（P2 r1 例外，见 OBS-8）。
- 无 bit/Flash/板级产物；无需 RTL/硬件回退。
