# 用户摘要：双路 A+ 双核/服务率可行性（离线结论）

- run：`20261025-195604_fpga-dual-aplus-core-feasibility`
- 状态：**P1、P2 均 PASS（各 1 轮实际修复）；本轮离线问题已回答。P3 双核隔离综合仍 blocked、未派发。**
- 边界：只做 FPGA 侧离线模型/表格；无 TD、无综合/布线、无 bitgen/CWC、无下载/板卡、无 RK。

## 一句话结论

**双路 1920×1080@30 在 187.5 MHz、冻结 b6 A+ core、共享单 DDR MC 下不可行（infeasible）。双核不能解决这个问题：它只让两路并行，不提高单路链级服务率；双核资源最高也只能判 conditional，且双核 Routed 时序未证明。**

## 关键数字

- 1080p30 单路需求 77.76 MB/s；25% 设计门槛 97.20 MB/s。
- 单核**链级**实测 75.684 MB/s（29.199 fps）→ **−2.67%**；单核**核级** 81.067 MB/s（31.276 fps，+4.25%）只是乐观上界。
- 双核聚合 `2×核级=162.13 >155.52` 看着够，但 `2×链级=151.37 <155.52`，per-stream 仍 75.68 <77.76；不能拿聚合值判双路。
- 1080p30 若只靠提频：链级需 **240.8 MHz** 才到 25%，0% 也要 192.6 MHz；200 MHz 只有 +3.82%，仍不够且 200 MHz 时序未证明。
- 双核资源：边际方案 **231/300**（余 69，可装）；保守上界 **289/300**（余 11，仅边际）；**双核 Routed 时序 unproven**。
- **单核单路 1080p 在 25% 门槛下最大 23.36 fps**（网格取 20 fps 可行；25/24 fps 不足）；**单核双路 1080p per-stream 最大 11.68 fps**。
- 场景：43 行；feasible 8 / conditional 22 / infeasible 13；**双核 feasible 0；1080p30 feasible 0**。

## 如果不坚持 1080p30，推荐是什么

> 下面是 **per-stream / 单核单路** 的配置；双路要实例化两份，即 2c2s。服务率 per-stream 不变，但双核资源/时序只到 conditional。

- **主推荐（带条件）**：**1600×900@30 单核单路**。主档链级裕量 36.18% 可行；保守 overhead 档降到 21.05% → conditional。所需链/核时钟 172.1/156.1 MHz，ERAM 187/300。
- **备选 1（三档稳健）**：**1440×810@30 单核单路**。最差档 42.95%，三档都满足 25%；所需链/核时钟 142.4/126.5 MHz。
- **备选 2（全分辨率降帧）**：**1920×1080@20 单核单路**。链级裕量 46.00%，可行；所需链/核时钟 160.5/149.9 MHz。
- **双路部署注意**：2× 上述单核单路 = 2c2s，最高只能 **conditional**（双核 conservative 289/300 + 时序未证明）。网格内最大可行双路 30fps 行是 **单核 2×960×540@30**（最差档 25.06%），但分辨率牺牲很大。
- **不推荐**：双核 2×1080p30；单核双路 1080p；1728×972@30；第二 DDR 控制器变体（316/374 超 300）。

## 这次完成了什么

- P1：冻结 b6 core / 单核 Routed 基线；双核资源表（marginal 231/300、conservative 289/300、时序 unproven）；第二路 CSI 补算；3 负对照；独立测试 PASS。
- P2：43 行服务率模型（per-stream/full-chain、DDR 2R+2S、drop 下界、overhead 三档、Pareto/推荐）；5/5 负对照；独立测试 PASS。
- P1 manifest：`228531e7…bdd0`；P2 manifest：`5ed90500…36a6`。

## P3 为什么没做

- P3 `T10.dual-core-synth-probe` 仍 **blocked、未派发**。
- P1/P2 已 PASS，但仍缺：TD 空闲、b11 不重建、规划明确放行；**用户本轮未新增 TD/板卡授权，主不扩权**。
- 即使解阻，P3 只做 1 次隔离综合，不布线、不 bitgen、不下载；只作 `G2-syn` 检查点，不能证明双核 Routed 时序，**也不能改变 1080p30 的 −2.67% 结论**。

## 证据入口

- P1 独立报告：`workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility/test-reports/T10.dual-core-resource-baseline-r1-integrated.md`
- P1 manifest：`.../T10.dual-core-resource-baseline/r0/manifest-r0.json`（`228531e7…bdd0`）
- P2 独立报告：`.../test-reports/T10.dual-aplus-service-verdict-r1-integrated.md`
- P2 可行性报告：`.../T10.dual-aplus-service-verdict/r0/feasibility-report.md`
- P2 manifest：`.../T10.dual-aplus-service-verdict/r0/manifest-r0.json`（`5ed90500…36a6`）
- P2 表：`.../T10.dual-aplus-service-verdict/r0/out/{scenarios,content-sensitivity,ddr-budget,frontier,overhead-sensitivity}.csv`

## 恢复/下一步

```text
使用 fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261025-195604_fpga-dual-aplus-core-feasibility；本轮目标：读取 P1/P2 冻结 manifest 与独立报告，确认双路 1080p30 infeasible 与降帧/降分辨率建议；P3 仍 blocked，需先获得 TD 空闲/b11 不重建/用户或主明确授权。
```

- 若继续 1080p30：优先做“核心服务率提升”（链级 cycles/frame 从 6.421M 降到 ≤5.000M，或链级时钟 ≥240.8 MHz），而不是加第二核。
- 若接受降档：先按主推荐/稳健备选做系统方案；双路部署需再评估双核资源与 Routed 时序。
- 本 run 不改 `workflow/tasks.json`；P1/P2 PASS 不把父 T10 或双路目标置 done。
