# 本轮用户原话与引用上下文

## 当前用户原话

现在这个run使用工作流开始开双路 A+ 双核/服务率可行性

## 紧邻引用上下文

上一条回复中，用户选择的是建议并行池里的 P1：

> P1：双路 A+ 双核/服务率可行性（新开 run，先做模型）
>
> **为什么独立：** T10 只做“单核 + 分时调度”，没有回答“双核能不能装下、双路 1080p30 到底可不可行”。
>
> **要做的事：**
> - 冻结 b6 core SHA，统计单核真实资源：ERAM/LUT/REG/DSP；
> - 按 PH1P100 的 300 ERAM / 129k LUT / 143k DFF 做双核资源表；
> - 算清双路 1080p30 的账：A+ 输入 155.52 MB/s、RAW 写+读 311.04 MB/s、CMP 写读、预览、DDR 2R+2S；
> - 给结论：双核能否 2×30 fps；若不能，单核降帧到多少、或降分辨率到多少。
>
> **需要：** 纯模型/表格即可先做；如果要综合，只在 b11 不重建时做一次隔离综合，不布线、不 bitgen。
>
> **边界：** 不改 T10 调度器、不改生产 top，只输出架构建议和资源/吞吐表。

用户本轮明确要求：只做 FPGA 侧，并与 OpenCode b11、Codex T08/T10 并行、不互相影响。

## 本轮硬约束

- 只做 FPGA 侧；不接 RK，不做 RK 软件/驱动/深度/NPU。
- 不修改 `fpga/csi2/src/**`、`upstream/**`、`D:/TD/work/csi2/**`、`D:/fpga_work/**`。
- 不修改 OpenCode b11 目录、Codex T08/T10 目录及其候选/测试者：
  - `workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b11-aplus-read/**`
  - `workflow/runs/20261025-180900_fpga-dual-offline-closure/T08.dual-local-closure/**`
  - `workflow/runs/20261025-180900_fpga-dual-offline-closure/T10.dual-aplus-scheduler/**`
- 不把本需求作为第三包加入 `20261025-180900_fpga-dual-offline-closure`；本需求另开新 run。
- 板卡/COM/JTAG/下载/Flash 归 b11；本包不做。
- TD 串行：b11 如需重建优先；本包先做模型/表格，综合只在 TD 空闲时做隔离综合，不布线、不 bitgen、不下载。
- 不修改 `workflow/tasks.json`；不批量删除；新生成物只写本 run 目录或 `D:\fpga` 下独立工作目录。

## 可读输入路径

- 项目根：`D:/fpga/ph1p100`
- 当前状态盘点：`docs/项目成果整合与进度复核_2026-10-25.md`
- 并行工作再评估：`docs/并行工作再评估_2026-10-25.md`
- b6 核级验收报告：`workflow/runs/20261020-0209_singleA_aplus_closedloop/test-reports/T10.b6-a1-htab-nw-r0-integrated.md`
- b6 候选 manifest：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b6-a1-htab-nw/CANDIDATE-MANIFEST-b6-a1-htab-nw-r0.json`
- b10 板级结果：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b10-b9-fix/result-r1.md`
- b11 诊断结果：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b11-aplus-read/r0/result-r0.md`
- T10 双路调度开发结果：`workflow/runs/20261025-180900_fpga-dual-offline-closure/T10.dual-aplus-scheduler/result-r0.md`
- T08 双路本地闭环开发结果：`workflow/runs/20261025-180900_fpga-dual-offline-closure/T08.dual-local-closure/result-r0.md`
- Codex 当前 run 计划：`workflow/runs/20261025-180900_fpga-dual-offline-closure/dev-plan.md`
- 历史整链路方案：`docs/双目首版_整链路方案与团队交付.md`
- 压缩方案复核：`docs/压缩方案G2复核与优化方向_2026-10-22.md`
- b6 独立证据目录：`workflow/runs/20261020-0209_singleA_aplus_closedloop/test-reports/T10.b6-a1-htab-nw-r0-evidence`

## 输出目录

`D:/fpga/ph1p100/workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility`

## 期望

由规划角色按项目有界规则理解并拆分本轮工作；只做与 b11/T08/T10 不冲突的离线可行性工作。主只原样转发，不解释技术需求。
