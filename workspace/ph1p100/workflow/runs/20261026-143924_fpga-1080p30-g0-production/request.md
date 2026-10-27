# 本轮用户原话与任务边界

## 当前用户原话

OK还是列好任务去做工作流

## 上一轮已完成的事实（P4，2026-10-26）

run `20261025-233401_fpga-steady-state-reverdict` 已 finished，P1–P4 全部 PASS：

- 用户边界：**G0 名义 per-stream 1080p30（77.76 MB/s / 6.25M cycles@187.5MHz）是硬门槛；G25=25% 仅作参考，不降档。**
- P4 四个全尺寸 4 帧实测：
  - R1 C1 `f1080p_p1d1` 合成全帧 / slot-free：S_ss=4,677,970 → 40.0815 fps / 103.891 MB/s / G0 +33.605%。
  - R2 同 C1 / strict-serial：S_ss=6,449,405 → 29.0724 fps / 75.356 MB/s / G0 −3.092%；R2−R1=1,771,435 cycles。
  - R3 C2 `f1080p_rand` / slot-free：S_ss=5,189,503，算术 36.131 fps / 93.651 MB/s / G0 +20.4%，但 tail=109.85% → **sink_limited=true → G0_not_proven**。
  - R4 comp 代理 / slot-free：S_ss=5,928,286 → 31.628 fps / 81.980 MB/s / G0 +5.427%，复现 P3 R3 Δ=0。
- 最终 headline：**`G0_feasible_for_scope`**，scope = C1 合成全帧或 comp 代理 + slot-free + 93.75 MB/s 冻结仿真 sink + 行为 DDR + 单核 187.5MHz + per-stream。**自然图像/全内容/双路/板级/真实 DDR/RK 均未证。**
- P4 已证明：**slot-free 是 G0 的必要条件**（strict-serial −3.09%）；**sink 是第二约束**（rand raw band 被 93.75 MB/s 限速；生产 sink 需 ≥77.84 G0 / ≥103.79 25ms）。

## 本轮目标

把 1080p30 G0 从“合成/代理 + TB slot-free + 93.75 sim sink”推进到**可负责的生产前提**：

1. **真实/自然/低照/最坏内容 4 帧锚点**：不能只用合成 C1/comp 代理；优先找真实 RAW；若无真实 RAW，只允许“自然图像派生 Bayer / 合成自然纹理”并明确 `proxy_not_natural`，不得称真实传感器 RAW。若没有可信内容源，结论必须是 `G0_not_proven`，不得猜。
2. **生产 slot-free 路径**：审计当前 b10/b11 生产 top 是 frame-serial 还是可 slot-free/overlapped；给出最小改动/证据；不能只拿 TB slot-free 当生产通过。若需要 RTL 改动，先做隔离候选与仿真，不碰生产源。
3. **生产 sink ≥103.79 MB/s**：当前冻结 TB sink 上限 93.75 MB/s；给出可证明 ≥103.79 的离线 sink/PCIe 模型或明确 `G0_not_proven`；raw band tail 约 27.7ms（83%）必须单列。
4. **G0 生产收口**：综合 1–3，给 `G0_feasible_for_scope` / `G0_not_closed` / `G0_not_proven`，scope 写清内容/pacing/sink/DDR/单核；不得降档、不得用 G25 主推降档。

## 建议任务清单（供规划细化；可合并/裁剪但不超过 4 包）

| 草案 | 任务 | 主要产物 | 依赖 |
|---|---|---|---|
| **P1** | 真实/自然/最坏内容 4 帧锚点 | 内容源审计/冻结、4 帧 S_ss、G0、content-map、边界 | P4 基线 |
| **P2** | 生产 slot-free 路径审计与最小候选 | b10/b11 top 审计、slot ownership/pacing 证据、隔离候选/TB、4 帧 | P1 内容可复用 |
| **P3** | 生产 sink ≥103.79 MB/s 路径 | sink 模型/PCIe packer 或 TB 快速 sink、raw band tail、G0 | P1/P2 |
| **P4** | G0 生产收口/判定 | 三包合并、G0 verdict、剩余风险、恢复入口 | P1–P3 |

默认 1 个主要目标、最多 4 个正式包、两级、每包≤5 项语义步骤。先派 P1 一个包，后续按 PASS 再放行；不要预 spawn 多个开发/测试者。

## 硬约束

- 只做 FPGA 侧离线仿真/模型/报告；不接 RK，不做 RK 软件/驱动/深度/NPU。
- 新 run；不改 `20261025-233401` 的 P1–P4 冻结件/报告，不改 `20261025-195604` P1/P2，不改 `20261025-180900` T08/T10，不改 b11/b6 目录，不改 `fpga/csi2/src/**`、`upstream/**`、`D:/TD/work/csi2/**`、`D:/fpga_work/**`、`workflow/tasks.json`、`docs/**`、`work/**`。
- 需要 b10/b11/b6 TB/RTL 时，只在新 run 目录复制冻结副本；DUT 0 修改；每任务独占 ModelSim `modelsim.ini`/工作库/日志；不共享盘符映射。
- TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG=0。本轮不碰硬件；b11 1176 板测归 b11/OpenCode 线。
- 不批量删除；不新增外部/队友消息授权；不修改全局配置。
- 真实自然 RAW 不存在时，只能做“自然图像派生 Bayer/合成自然纹理”，必须标 `proxy_not_natural`；不得声称真实传感器 RAW 或全内容通过。
- 4 帧全尺寸单次约 22 min；规划需冻结总 wall/次数/超时，不能无界运行；超时/SS_STALL/丢帧按 partial/not_proven，不得用 2/3 帧冒充 4 帧。

## 关键输入路径

- P4 报告：`workflow/runs/20261025-233401_fpga-steady-state-reverdict/test-reports/T10.ss-4run-matrix-r0-integrated.md`
- P4 manifest：`.../T10.ss-4run-matrix/r0/manifest-r0.json`（`d353c61a…6dd1`）
- P4 四轮表：`.../T10.ss-4run-matrix/r0/out/{runs-4,four-run-table,g0-verdict,content-map,gap-menu}.csv/json`
- P3 G0 报告：`.../test-reports/T10.ss-g0-closure-r2-integrated.md`
- P3 manifest：`.../T10.ss-g0-closure/r0/manifest-r2.json`
- P3 TB：`.../T10.ss-g0-closure/r0/src/tb_ss_g0.v`（`a565c6f2…`）
- P4 TB：`.../T10.ss-4run-matrix/r0/src/tb_ss_4run.v`
- 当前生产 top / b11：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b11-aplus-read/r0/changed-src/`、`.../r0/td/src/p2_a1_board_top.v`
- b11 两帧 TB/统计：`.../T10.b11-aplus-read/r0/sim/tb_b11_full.v`、`.../caps/full.stats`
- 内容源：`.../T10.a1-adler-smem/r0/p3/cases/f1080p_p1d1/raw.bin`、`.../f1080p_rand/raw.bin`、`work/parallel-sim-20261024-2204/codec-throughput/comp/in.hex`
- 上一轮 P2 报告/模型：`workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility/T10.dual-aplus-service-verdict/r0/{feasibility-report.md,model/*,out/*}`
- DDR 文档：`docs/DDR1333集成与1333vs1600对比_2026-10-17.md`
- 任务板：`workflow/tasks.json`（只读）

## 输出目录

`D:/fpga/ph1p100/workflow/runs/20261026-143924_fpga-1080p30-g0-production`

## 期望

由规划角色按项目有界规则理解并拆分本轮“1080p30 G0 生产前提收口”；先派 P1 一个包，不要一次开多个。主只原样转发，不解释技术需求。
