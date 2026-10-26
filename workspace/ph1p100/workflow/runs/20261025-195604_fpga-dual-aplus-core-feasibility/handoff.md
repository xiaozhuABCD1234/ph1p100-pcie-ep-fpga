# 交接：双路 A+ 双核/服务率可行性（P1/P2 PASS，P3 blocked）

- run：`20261025-195604_fpga-dual-aplus-core-feasibility`
- 项目根：`D:/fpga/ph1p100`
- 日期：2026-10-25
- run 状态：**finished（离线模型层面）**。P1、P2 均 round0 FAIL→round1 **PASS**（各 1 轮实际修复）；P3 `T10.dual-core-synth-probe` **blocked、未派发**。
- 本轮主要目标：PH1P100 上双路 1920×1080@30 RAW10 的 A+ 压缩，单核/双核在资源、时序、DDR、调度服务率上是否可行；若不可行，给出降帧/降分辨率量化结论。**已给出离线结论；不是 RTL/综合/板级/生产完成。**

## 1. 最终结论（P2）

- **双路 1920×1080@30 在 187.5 MHz、冻结 b6 core、共享单 DDR MC 下 `infeasible`。**
- per-stream 链级（full-chain）容量 **75.684265 MB/s**（29.199 fps@1080p，**−2.6694%**）；25% 门槛 **97.20 MB/s**；core-only 81.067159 MB/s（31.276 fps，+4.2530%）只是乐观上界。
- **双核不改变 per-stream 结论**：每核服务一路时 per-stream 仍是单核链级 75.684 MB/s；`2×C_core=162.134 >155.52` 是聚合陷阱，`2×C_chain=151.369 <155.52`，per-stream 仍 75.684 <77.76。双核 feasible 行 0。
- 1080p30 所需时钟：链级 **240.803 MHz**（25%）、192.642 MHz（0%）；200 MHz 只有 +3.8193%，仍 below_25 且 200 MHz 时序 unproven。
- 1080p 链级 25% 最大 fps **23.36**；0% 最大 29.199；单核双路 per-stream 25% 最大 **11.68 fps**。
- 30 fps 链级 25% 最大档：主档 **1600×900**（36.1774%）；三档稳健 **1440×810**（最差 42.9485%）；1728×972 主档 18.3184%、保守档 6.7286%。
- 1080p 全分辨率降帧：**1920×1080@20 c1s1 = 45.9959% feasible**；25/24 fps 分别为 16.7967/21.6632%（below_25）。
- DDR 主路径 2R+2S **809.034 MB/s**，required efficiency **12.6412%**；25% gate 1,011.2925 MB/s（15.8014%）。持续带宽/PAXI 仲裁/单拍效率仍 unproven。
- 场景计数：43 行；feasible 8 / conditional 22 / infeasible 13；**双核 feasible 0；1080p30 feasible 0**。

### 1.1 推荐与备选（P2 规则选出，不是手写）

- **主推荐（带条件）**：`1600×900@30 c1s1`（单核单路）。主档 426,385 overhead 链级 **36.1774% feasible**；保守档 1,000,000 为 **21.0486% → conditional**；所需链/核时钟 172.1100/156.1206 MHz；ERAM 187/300。
- **备选 1（三档稳健）**：`1440×810@30 c1s1`。最差 **42.9485% feasible**；链/核时钟 142.4471/126.4577 MHz；ERAM 187/300。
- **备选 2（全分辨率降帧）**：`1920×1080@20 c1s1`。**45.9959% feasible**；链/核时钟 160.5353/149.8757 MHz；三档相同（1080p 实测锚点）。
- **双路部署注意**：上述是 per-stream 的 **单核单路** 配置；双路要实例化两份，即 2c2s。服务率 per-stream 不变，但双核 conservative ERAM **289/300** + 双核 Routed 时序 **unproven** → **2c2s 最高 `conditional`**。网格内最大可行双路 30 fps 行是 **单核 2×960×540@30**（最差档 25.0622%，feasible），但分辨率牺牲大。**双核不是 1080p30 的解。**
- 不推荐：双核 2×1080p30；单核双路 1080p；1728×972@30（主档 18.3184%、保守档 6.7286%）；第二 DDR 控制器变体（316/374 fail）。

## 2. P1 实际完成（`T10.dual-core-resource-baseline`）

- round0 首次验收 **FAIL**（F1 marginal LUT6/LUT4 少计；F2 manifest 与 freeze 日志不绑定；F3 `u_camera`/第二路 CSI 清单不符）；round1 实际修复后 **PASS**；实际修复 **1 轮**；blocked 空；retest not_required。
- 冻结 manifest：`.../T10.dual-core-resource-baseline/r0/manifest-r0.json`，SHA256 **`228531e7c16bca1a14898966c150b31bce464d7413f58078ae0bd724e894bdd0`**；15 artifacts / 27 inputs / 10 commands；`stopped_modifying=true, active_commands=0`。
- 独立报告：`.../test-reports/T10.dual-core-resource-baseline-r1-integrated.md`；functional/engineering/system pass；G0/G1 pass；G2–G4 `not_applicable`。
- 资源基线（Routed）：单链 102 ERAM 逻辑 + 85 `DRAMHARDCON` = **187/300**；LUT6 19,695/71,680；REG 28,004/143,360；slice 24,368/71,680；DSP 0；PLL 4；`clk_a1` 187.5 MHz 域 WNS **+0.119/+0.103**、hold +0.020、0 违例。
- 双核 `marginal`：146+85=**231/300**（余 69，23.0%，fit pass）；LUT6 **25,709**；LUT4 上界 51,418；REG 34,341；slice 30,733（assumed）；PLL 4。
- 双核 `conservative`：204+85=**289/300**（余 11，3.67%，fit **conditional**）；LUT6 39,390；LUT4 上界 78,780；REG 56,008；slice 48,736；PLL 8。
- **双核 Routed 时序/布局/拥塞/时钟树：unproven**；无任何双核构建，不得由单核 +0.119/+0.103 外推。
- 双 DDR 控制器变体：marginal 316/300、conservative 374/300，均 fail；默认共享单 256-bit PAXI + 单 DDR MC。
- 第二路完整 CSI 未在 routed 中形成使用路径；若需要，补 773 logic/340 ripple/1,474 seq/0 ERAM → LUT6 **26,822**、REG **35,815**、SLICE 约 **32,083**，ERAM/fit 不变。第二路 FIFO ERAM 映射、生产去 CWC 后 ERAM、精确 LUT4 均未证明。

## 3. P2 实际完成（`T10.dual-aplus-service-verdict`）

- round0 首次验收 **FAIL**（F1 frontier margin 与 capacity_basis 不同源；F2 三档 overhead 未落产物、1600×900 保守档仍写成无条件 feasible；F3 推荐缺所需时钟）；round1 实际修复后 **PASS**；实际修复 **1 轮**；blocked=false；retest not_required。
- 冻结 manifest：`.../T10.dual-aplus-service-verdict/r0/manifest-r0.json`，SHA256 **`5ed90500a7e9650ca17e5f269731984fea9f215d7401d555dc5633551c2436a6`**（28,684 B）；23 artifacts / 22 inputs / 18 commands；`stopped_modifying=true, active_commands=0`。
- 独立报告：`.../test-reports/T10.dual-aplus-service-verdict-r1-integrated.md`；functional/engineering/system pass；G0/G1 pass；G2–G4 `not_applicable`。
- 机器可读结果：`.../T10.dual-aplus-service-verdict/r0/out/{scenarios.csv,content-sensitivity.csv,ddr-budget.csv,frontier.csv,overhead-sensitivity.csv}`；报告 `.../r0/feasibility-report.md`；模型 `.../r0/model/{calc.py,rules.json,test_calc.py,gen_tables.py,render_report.py,check_outputs.py}`。
- 43 行网格（39 设计 + 4 单核单路 1080p fps 档）；feasible 8 / conditional 22 / infeasible 13；双核 feasible 0；1080p30 feasible 0；5/5 负对照被拒；`test_calc` 146/146、`check_outputs` 117/117。
- O1–O6 非阻断观察（P2 r1 报告 §7）：
  - **O1** c1s2 的 required-clock 列是容量口径，不是 per-stream；推荐均为 c1s1，不影响 verdict。
  - **O2** `commands.jsonl` 17 条 vs manifest 18 条（`mk_manifest` 不入日志，有意设计）。
  - **O3** 开发实际约 100 calls，超过冻结 45 calls；范围未扩、门槛未改、无 TD/硬件/越界写；作过程记录。
  - **O4** 日志 UTF-16LE；哈希一致。
  - **O5** frontier core-only 行使用 `core_only_upper_bound` 标签（非 R1–R6 系统判定）。
  - **O6** round1 check 首轮失败已记录并修正，最终 117/117；未发现被掩盖失败。

## 4. P3 状态（blocked，未派发）

- `T10.dual-core-synth-probe` **不派发**。
- 条件：
  1. P1、P2 均 PASS → **已满足**（P1 资源 conditional 289/300；P2 PASS r1）。
  2. TD 空闲、b11 无构建/布线/下载活动 → **未确认**；规划不探测、不抢占，b11 优先。
  3. 原规划明确放行 → **未放行**；用户未新增 TD/板卡授权，主不扩权。
- 即使解阻，P3 只做 1 个 TD 会话/1 次隔离综合，**不布线、不 bitgen、不 CWC、不下载、不板卡**；只写本 run 任务目录；只作 `G2-syn` 检查点，不是时序签核/生产候选。
- **P3 不能改变 P2 的 1080p30 per-stream −2.67% 结论**；它只降低双核资源/综合检查点的不确定性，供后续低分辨率双路方案参考。P3 不是 1080p30 的解。

## 5. 未测/风险

- 双核 Routed 时序/布局/拥塞/时钟树：unproven；无构建。
- 200 MHz 时序：unproven；200 MHz 仍 below_25。
- 自然图像/低照/噪声内容：未测；comp 不是严格上界。
- 链级 overhead 426,385 cycles 跨内容恒定是 assumed；仅 full_grad 一例 measured；保守 1,000,000 档使 1600×900 降为 conditional。
- DDR 持续带宽/PAXI 仲裁/单拍效率：unproven；只有 required efficiency。
- 第二路完整 CSI/第二路 FIFO ERAM/去 CWC 后 ERAM/精确 LUT4：未实现或只有上界/assumed。
- 周期级调度/one-outstanding reader：未仿真；T10 scheduler 无 PASS 报告。
- 板级/RK/PCIe/曝光同步/长稳：不在本 run；无实测吞吐/恢复结论。
- P2 PASS 不把父 T10 或双路目标置 done；本 run 不改 `workflow/tasks.json`。

## 6. 证据索引

- P1 manifest：`.../T10.dual-core-resource-baseline/r0/manifest-r0.json`（`228531e7…bdd0`）
- P1 独立报告：`.../test-reports/T10.dual-core-resource-baseline-r1-integrated.md`
- P1 资源基线/表/预算：`.../T10.dual-core-resource-baseline/r0/{resource-baseline.md,resource-table.csv,dual-core-budget.csv}`
- P1 开发/lessons：`.../T10.dual-core-resource-baseline/r0/{result-r0.md,lessons.md}`
- P2 manifest：`.../T10.dual-aplus-service-verdict/r0/manifest-r0.json`（`5ed90500…36a6`）
- P2 独立报告：`.../test-reports/T10.dual-aplus-service-verdict-r1-integrated.md`
- P2 可行性报告：`.../T10.dual-aplus-service-verdict/r0/feasibility-report.md`
- P2 表：`.../T10.dual-aplus-service-verdict/r0/out/{scenarios,content-sensitivity,ddr-budget,frontier,overhead-sensitivity}.csv`
- P2 开发/lessons：`.../T10.dual-aplus-service-verdict/r0/{result-r0.md,lessons.md}`
- P2 测试证据：`.../test-reports/T10.dual-aplus-service-verdict/{independent_check_r1.py,independent_check_r1.out.txt}`；r0 报告/证据保留
- 规划/冻结：`.../request.md`、`.../input-index.md`、`.../fpga-design-guide.md`、`.../dev-plan.md`、`.../dispatch.json`

## 7. 剩余主题（最多 3 条）

1. **核心服务率提升**：双核不改变 per-stream；要在 1080p30 达到 25% 裕量，需链级 cycles/frame ≤5,000,000（−22.14%）或链级时钟 ≥240.803 MHz；可评估 2 pixel/cycle、加宽匹配/打包、流水加深/独立 DDR 读通道；需新 RTL/综合包与用户授权。
2. **DDR/桥实测服务模型**：板级测 256-bit PAXI 持续读写、单拍/突发、仲裁/刷新；验证 2R+2S 的 809.034 MB/s required efficiency；属 b11/后续板级包。
3. **生产双核集成与系统验收**：把双核 A+、双路同步、槽所有权、CMP 导出合并到统一候选，做 Routed/G2、真实曝光/恢复/长稳；另开 run，不在本轮自动续做。

## 8. 恢复入口

```text
使用 fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261025-195604_fpga-dual-aplus-core-feasibility；本轮目标：读取 P1/P2 冻结 manifest 与独立报告，确认双路 1080p30 infeasible 与降帧/降分辨率建议；P3 仍 blocked，需先获得 TD 空闲/b11 不重建/用户或主明确授权。
```

- 原规划会话有效则续原规划 ID；跨宿主/换父会话按本 run 文件恢复并登记新旧真实 sessionID 映射，不重置轮数/预算。
- 本 run 不改 `workflow/tasks.json`；P1/P2 PASS 不把父 T10 或双路目标置 done。
