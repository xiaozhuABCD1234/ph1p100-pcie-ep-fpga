# 本轮用户原话与复核上下文

## 当前用户原话

按这个工作流进行复核吧

## 紧邻上下文：用户要复核的对象

上一条回复对 P2 `T10.dual-aplus-service-verdict` 的可行性结论提出三点质疑，用户确认按工作流复核：

1. **单帧延迟 ≠ 稳态吞吐**：P2 把 b6 `full_grad` 单帧 `cycles=6,421,414` 当作 1080p 每帧服务时间，折算 75.684 MB/s / 29.199 fps，判 1080p30 `infeasible`；但 b11 两帧背靠背 `full.stats` 为 `cap=2, cycles=11,445,988`，即 **5,722,994 cycles/帧 → 32.76 fps → 84.92 MB/s**（梯度内容）。b6 最慢 `comp` 核级折算 **5,995,029 cycles/帧 → 31.28 fps → 81.067 MB/s**。三者均高于 30 fps 名义需求中的两个，说明 P2 的 6.421M 很可能是单帧 startup/tail 延迟，不是稳态帧间隔。
2. **25% 设计裕量与名义 1080p30 混在一个 verdict**：设计指南写“25% 项目设计门槛；0% 只作算术对照”。P2 的 R2 在链级 <0% 时判 `infeasible`，导致 1080p30 名义 −2.67% 被判 infeasible；但 25% 门槛下是 −22.1%。需要拆成 **nominal 30fps** 与 **25% design margin** 两个 gate，不能因为 25% 不够就直接降档。
3. **锚点/测试台代表性与数字口径**：b6 `full_grad` 是平滑梯度、TB 头写明 `MODE 0: one 1920x1080 frame`，`clk_uart` 是 sim-only fast baud；P2 的“UART 导出”不是真实 115200 生产路径。另 P2 的 DDR 峰值用 6400 MB/s（DDR1600），当前 DDR1333 约 5333 MB/s；1080p 被固定为 anchor，未参与 0/426,385/1,000,000 overhead 三档敏感性。

## 本轮复核目标

对 P2 的 1080p30/双路可行性结论做**有界、可验收的复核与纠正**，不是重新做整套压缩器。至少要回答：

- 1080p 的真实**稳态**每帧 cycles 是多少？单帧 6,421,414 与 b11 两帧 5,722,994/帧的差异是 startup/tail 还是内容差异？用 4 帧背靠背（或等价多帧）实测，分别记录单帧延迟与稳态帧间隔。
- 把判定拆成两个 gate：**nominal per-stream 30 fps（0%）** 与 **25% design margin（容量 ≥1.25×需求）**；分别给单路、双路、不同内容锚点的结果。
- 1080p 是否应参与 overhead 0/426,385/1,000,000 敏感性；0-overhead/流水线隐藏 tail 是否是可行优化路径。
- 修正 DDR 峰值口径（DDR1333 5333 MB/s vs DDR1600 6400 MB/s），重算 required efficiency/gate；平均带宽是否仍非瓶颈。
- 明确“UART 导出”在链级锚点中的性质：sim-only fast sink 还是真实 115200；吞吐锚点是否应排除 UART、改用 PCIe/高速 sink。
- 双核 nominal 的 per-stream 结论与共享 PAXI/DDR 争用、资源 marginal/conservative、Routed 时序 unproven 的边界；不得用 aggregate 2C 替代 per-stream。
- 复核 P2 模型是否还有其它口径/算术错误；给出修正后的 verdict（可以是 `conditional`/`not_proven`，不要为了通过而放宽门槛）。

## 硬约束

- 只做 FPGA 侧离线复核/仿真；不接 RK，不做 RK 软件/驱动/深度/NPU。
- 本需求另开新 run；不修改 `20261025-195604_fpga-dual-aplus-core-feasibility` 的 P1/P2 冻结候选与报告，不修改 `20261025-180900` 的 T08/T10，不修改 b11 目录/候选/报告。
- 不改 `fpga/csi2/src/**`、`upstream/**`、`D:/TD/work/csi2/**`、`D:/fpga_work/**`、`workflow/tasks.json`。
- 需要 b11/b6 TB/RTL 时，只在新 run 目录复制冻结副本；禁止改原目录。每任务独占 ModelSim `modelsim.ini`/工作库/日志，不共享盘符映射。
- 板卡/COM/JTAG/下载/Flash=0；TD/综合/布线/bitgen/CWC=0。本轮只做离线仿真/模型/报告。
- 不批量删除；不新增外部/队友消息授权；不修改全局配置。
- 若 4 帧全尺寸仿真超出规划冻结预算，停止并如实 blocked/部分结果，不得用 2 帧或单帧冒充 4 帧稳态。

## 关键输入路径

- 上一轮 P2 可行性报告：`workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility/T10.dual-aplus-service-verdict/r0/feasibility-report.md`
- P2 模型与规则：同目录 `model/calc.py`、`model/rules.json`、`model/gen_tables.py`、`model/check_outputs.py`
- P2 输出表：同目录 `out/scenarios.csv`、`out/frontier.csv`、`out/overhead-sensitivity.csv`、`out/ddr-budget.csv`
- P2 冻结 manifest：同目录 `manifest-r0.json`（SHA256 `5ed90500a7e9650ca17e5f269731984fea9f215d7401d555dc5633551c2436a6`）
- P2 独立报告：`workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility/test-reports/T10.dual-aplus-service-verdict-r1-integrated.md`
- P1 资源基线：`workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility/T10.dual-core-resource-baseline/r0/resource-baseline.md`、`dual-core-budget.csv`；manifest `228531e7c16bca1a14898966c150b31bce464d7413f58078ae0bd724e894bdd0`
- b6 单帧链 TB：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b6-a1-htab-nw/r0/sim/boundaries/src/tb_camera_a1_uart_top.v`
- b6 `full_grad` 统计：`.../T10.b6-a1-htab-nw/r0/sim/captures/full_grad.stats`
- b6 comp/rand 报告：`.../test-reports/T10.b6-a1-htab-nw-r0-integrated.md`
- b11 两帧 TB：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b11-aplus-read/r0/sim/tb_b11_full.v`
- b11 两帧统计：`.../T10.b11-aplus-read/r0/sim/caps/full.stats`（`cycles=11445988`，`cap=2`）
- b11 两帧日志：`.../T10.b11-aplus-read/r0/sim/logs/sim_full.log`
- b11 诊断结果：`.../T10.b11-aplus-read/r0/result-r0.md`
- DDR1333/1600 对比：`docs/DDR1333集成与1333vs1600对比_2026-10-17.md`
- 当前状态盘点：`docs/项目成果整合与进度复核_2026-10-25.md`

## 已知仿真时长参考

- b11 `full` 两帧全尺寸：实际 598.5 s（约 10 min）。
- b6 `full_grad` 单帧：实际约 3.5 min（日志显示 3:30）。
- 因此 4 帧全尺寸可能需要约 20–30 min；规划应在派发前冻结足够但有限的仿真预算/超时，不能无界运行。

## 输出目录

`D:/fpga/ph1p100/workflow/runs/20261025-233401_fpga-steady-state-reverdict`

## 期望

由规划角色按项目有界规则理解并拆分本轮复核；先回答“单帧延迟 vs 稳态吞吐”和“双 gate”两个核心问题，再决定是否需要/如何修正 P2 verdict。只做与 b11/T08/T10 不冲突的离线工作。主只原样转发，不解释技术需求。
