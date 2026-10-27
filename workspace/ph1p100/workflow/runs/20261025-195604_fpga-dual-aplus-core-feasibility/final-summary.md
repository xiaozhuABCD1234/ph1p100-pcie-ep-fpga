# 最终摘要：双路 A+ 双核/服务率可行性（离线）

- run：`20261025-195604_fpga-dual-aplus-core-feasibility`
- 日期：2026-10-25
- 状态：**finished（离线模型层面）**。P1、P2 均 round0 FAIL→round1 **PASS**（各 1 轮实际修复）；P3 `T10.dual-core-synth-probe` **blocked、未派发**。
- 本轮主要目标：PH1P100 上双路 1920×1080@30 RAW10 的 A+ 压缩，单核/双核在资源、时序、DDR、调度服务率上是否可行；若不可行，给出降帧/降分辨率量化结论。**已给出离线结论；不是 RTL/综合/板级/生产完成。**

## 1. 最终结论

**双路 1920×1080@30 在 187.5 MHz、冻结 b6 core、共享单 DDR MC 下 `infeasible`。双核不改变 per-stream 结论；双核资源最高只能 `conditional`。**

| 关键量 | 值 | 说明 |
|---|---:|---|
| 1080p30 per-stream 需求 / 25% 门槛 | 77.76 / 97.20 MB/s | measured/derived |
| 单核核级 comp | 81.067159 MB/s（31.276 fps，+4.2530%） | 乐观上界，不含 DDR/导出 |
| 单核链级 full_grad | **75.684265 MB/s（29.199 fps，−2.6694%）** | 系统口径；1080p 全帧实测锚点 |
| 2×C_core / 2×C_chain | 162.134 / **151.369 MB/s** | 聚合陷阱；2×chain 已 <155.52 |
| 1080p30 所需时钟（链级） | 240.803 MHz（25%）/ 192.642 MHz（0%） | 200 MHz 仅 +3.8193%，仍 below_25 |
| 1080p 链级 25% / 0% 最大 fps | 23.36 / 29.199 fps | 单核单路 |
| 单核双路 1080p per-stream 25% 最大 | 11.68 fps | C/2 |
| 30 fps 链级 25% 最大档 | 1600×900（36.1774%） | 主档；保守档 21.0486% → conditional |
| 30 fps 三档稳健最大档 | 1440×810（最差 42.9485%） | 全档 feasible |
| 1080p 全分辨率降帧 | 1920×1080@20（45.9959%） | feasible |
| DDR 2R+2S 主路径 | 809.034 MB/s，required eff 12.6412% | 25% gate 1,011.2925 MB/s（15.8014%） |
| 双核资源 marginal / conservative | **231 / 289 / 300**（余 69 / 11） | marginal pass；conservative conditional |
| 双核 Routed 时序 | **unproven** | 无构建，不得外推 |
| 场景计数 | feasible 8 / conditional 22 / infeasible 13（43 行） | 双核 feasible 0；1080p30 feasible 0 |

### 1.1 推荐与备选

- **主推荐（带条件）**：`1600×900@30 c1s1`（单核单路）。主档 426,385 overhead **36.1774% feasible**；保守档 1,000,000 **21.0486% → conditional**；链/核时钟 172.1100/156.1206 MHz；ERAM 187/300。
- **备选 1（三档稳健）**：`1440×810@30 c1s1`。最差 **42.9485% feasible**；链/核时钟 142.4471/126.4577 MHz。
- **备选 2（全分辨率降帧）**：`1920×1080@20 c1s1`。**45.9959% feasible**；链/核时钟 160.5353/149.8757 MHz。
- **双路部署注意**：上述是 per-stream 单核单路；双路实例化两份 = 2c2s。服务率 per-stream 不变，但双核 conservative 289/300 + 双核 Routed 时序 unproven → **2c2s 最高 `conditional`**。网格内最大可行双路 30 fps 行是 **单核 2×960×540@30（最差档 25.0622%）**，分辨率牺牲大。
- 不推荐：双核 2×1080p30；单核双路 1080p；1728×972@30；第二 DDR 控制器变体（316/374 fail）。

## 2. 正式包状态

| 包 | 状态 | 轮数/绑定 | 结论 |
|---|---|---|---|
| `T10.dual-core-resource-baseline`（P1） | **done / PASS（r1）** | 1 轮实际修复；manifest `228531e7…bdd0` | 单链 187/300；双核 marginal 231/300、conservative 289/300；时序 unproven |
| `T10.dual-aplus-service-verdict`（P2） | **done / PASS（r1）** | 1 轮实际修复；manifest `5ed90500…36a6` | 双路 1080p30 infeasible；双核 feasible 0；降帧/降分辨率前沿已给出 |
| `T10.dual-core-synth-probe`（P3） | **blocked / 未派发** | 0 轮 | P2 已 PASS；TD 空闲/b11 优先/规划放行未确认；用户未新增 TD/板卡授权 |

- 3 个正式包（2 completed + 1 blocked），未使用第 4 个名额；两级；每包 5 项语义步骤；`BATCH_SIZE=1`。
- 未修改 `workflow/tasks.json`；未改 b11/T08/T10、`fpga/csi2/src/**`、`upstream/**`、`D:/TD/work/csi2/**`、`D:/fpga_work/**`；无板卡/COM/JTAG/下载/Flash/RK。

## 3. 实际完成/未完成

### 3.1 已完成

- P1：b6 core `6797db05…35bb` 冻结；单核/双核 Routed 资源表、marginal/conservative、第二路 CSI 敏感性、双 DDR 变体、3 负对照、独立 tester PASS。
- P2：43 行场景模型（per-stream/full-chain、core/aggregate、DDR 2R+2S、drop_lb、overhead 三档、frontier）、5/5 负对照、独立 tester PASS；结论和推荐如上。
- 独立报告：P1 `...-r1-integrated.md`、P2 `...-r1-integrated.md`；均 functional/engineering/system pass，G0/G1 pass，G2–G4 `not_applicable`。
- 证据绑定：P1 manifest `228531e7…bdd0`；P2 manifest `5ed90500…36a6`；P2 `feasibility-report.md` SHA `82c2669e…5355`（由 `logs/report.sha256` 绑定）；P2 r1 独立报告 SHA `71cafc6d…c4d4`。

### 3.2 未完成/未证明

- 双核 Routed 时序/布局/拥塞/时钟树：unproven。
- 200 MHz 时序：unproven；200 MHz 仍 below_25。
- 自然图像/低照/噪声内容：未测；comp 不是严格上界。
- 链级 overhead 426,385 cycles 跨内容恒定是 assumed；仅 full_grad 一例 measured；保守 1,000,000 档使 1600×900 降为 conditional。
- DDR 持续带宽/PAXI 仲裁/单拍效率：unproven。
- 第二路完整 CSI/第二路 FIFO ERAM/去 CWC 后 ERAM/精确 LUT4：未实现或只有上界/assumed。
- 周期级调度/one-outstanding reader：未仿真；T10 scheduler 无 PASS 报告。
- 板级/RK/PCIe/曝光同步/长稳：不在本 run；无实测吞吐/恢复结论。
- P3 未做；P3 synth-only 也不能改变 1080p30 per-stream −2.67% 结论。

## 4. 轮数、G 层、预算与观察

- P1：round0 FAIL→round1 PASS；1 轮实际修复；G0/G1 pass；G2–G4 N/A。
- P2：round0 FAIL（F1/F2/F3）→round1 PASS；1 轮实际修复；G0/G1 pass；G2–G4 N/A；O1–O6 非阻断。
- P2 O1–O6 摘要：
  - O1 c1s2 required-clock 列为容量口径（推荐均 c1s1，不影响 verdict）；
  - O2 `commands.jsonl` 17 vs manifest 18（`mk_manifest` 不入日志，有意设计）；
  - O3 开发实际约 100 calls，超过冻结 45（范围未扩、门槛未改、无 TD/硬件/越界写；过程记录）；
  - O4 日志 UTF-16LE；
  - O5 frontier core-only 行使用 `core_only_upper_bound` 标签；
  - O6 round1 check 首轮失败已记录并修正，最终 117/117。
- 预算：P1 在预算内；P2 开发超 45 calls；P3 0；TD/硬件/bitgen/CWC/下载/板卡全 0。

## 5. P3 blocked 条件与恢复

- P3 `T10.dual-core-synth-probe` **未派发**。
- 条件：
  1. P1、P2 PASS → **已满足**。
  2. TD 空闲、b11 无构建/布线/下载 → **未确认**；规划不探测、不抢占，b11 优先。
  3. 原规划明确放行 → **未放行**；用户未新增 TD/板卡授权，主不扩权。
- 若解阻：1 个 TD 会话/1 次隔离综合；不布线、不 bitgen、不 CWC、不下载、不板卡；只写本 run 任务目录；只作 `G2-syn` 检查点，不是时序签核/生产候选。
- P3 只降低双核资源/综合检查点的不确定性，供后续低分辨率双路方案参考；**不是 1080p30 的解**。

## 6. 后续主题（最多 3 条）

1. **核心服务率提升**：双核不改变 per-stream；1080p30 25% 需链级 cycles/frame ≤5,000,000（−22.14%）或链级时钟 ≥240.803 MHz；评估 2 pixel/cycle、加宽匹配/打包、流水加深/独立 DDR 读通道；需新 RTL/综合包与用户授权。
2. **DDR/桥实测服务模型**：板级测 256-bit PAXI 持续读写、单拍/突发、仲裁/刷新；验证 809.034 MB/s required efficiency；属 b11/后续板级包。
3. **生产双核集成与系统验收**：双核 A+ + 双路同步 + 槽所有权 + CMP 导出合并；Routed/G2、真实曝光/恢复/长稳；另开 run，不在本轮自动续做。

## 7. 证据入口

- P1 manifest：`.../T10.dual-core-resource-baseline/r0/manifest-r0.json`（`228531e7…bdd0`）
- P1 报告：`.../test-reports/T10.dual-core-resource-baseline-r1-integrated.md`
- P1 资源：`.../T10.dual-core-resource-baseline/r0/{resource-baseline.md,resource-table.csv,dual-core-budget.csv}`
- P2 manifest：`.../T10.dual-aplus-service-verdict/r0/manifest-r0.json`（`5ed90500…36a6`）
- P2 报告：`.../test-reports/T10.dual-aplus-service-verdict-r1-integrated.md`
- P2 可行性报告/表：`.../T10.dual-aplus-service-verdict/r0/feasibility-report.md`、`out/{scenarios,content-sensitivity,ddr-budget,frontier,overhead-sensitivity}.csv`
- P2 测试证据：`.../test-reports/T10.dual-aplus-service-verdict/{independent_check_r1.py,independent_check_r1.out.txt}`；r0 报告/证据保留
- 本 run 控制/收尾：`request.md`、`input-index.md`、`fpga-design-guide.md`、`dev-plan.md`、`dispatch.json`、`handoff.md`、`final-summary.md`、`user-summary.md`

## 8. 回退与恢复

- 回退：停止采用 P1/P2 `r0` 候选即可；保留全部证据；不改生产/P1/P2/其他 run；不删除。
- 本 run 不改 `workflow/tasks.json`；P1/P2 PASS 不把父 T10 或双路目标置 done。
- 恢复入口：

```text
使用 fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261025-195604_fpga-dual-aplus-core-feasibility；本轮目标：读取 P1/P2 冻结 manifest 与独立报告，确认双路 1080p30 infeasible 与降帧/降分辨率建议；P3 仍 blocked，需先获得 TD 空闲/b11 不重建/用户或主明确授权。
```

- 原规划会话有效则续原规划 ID；跨宿主/换父会话按本 run 文件恢复并登记新旧真实 sessionID 映射，不重置轮数/预算。
