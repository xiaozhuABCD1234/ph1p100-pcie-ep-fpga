# 本轮用户原话与 A+H 原型边界

## 当前用户原话

尝试做A+H

## 背景：A+H 从哪里来

上一轮 `20261026-143924_fpga-1080p30-g0-production` 已收尾，run 级 headline `G0_not_closed`：

- 自然场景派生 N：S_ss=7,475,240 cycles → 25.08 fps，G0 −16.39%；
- 低照派生 L：S_ss=6,986,952 cycles → 26.84 fps，G0 −10.55%；
- 瓶颈是 core_interval，不是 sink；
- P2 `T10.ss-g0-prod-coregap` 给出 8 行方案矩阵：唯一 187.5 MHz 算术闭合是 **A+H = 6,008,078 cycles（2.3179 c/B，+4.027%）**，但模型包络 **45.034%**，只能判 `conditional`，不是 closure；
- 单独 H（2 B/cycle 回放）= 6,260,648，仍差 **0.17%**；A（双位置 literal 扫描）单独 = 7,223,675；
- A+B+H=5,916,475 也算术闭合，但 B/C matcher 增益未验证，2% 信用是假设；A+H 是最小/首选组合；
- 仅提时钟 209.6/224.3 MHz 不在 b11 时序能力内（187.5 MHz 只剩 +0.015 ns）；双核不提高 per-stream。

A/H 的精确定义以 P2 报告与 `out/coregap-model.json`/`coregap-verdict.json` 为准：

- **A**：2-symbol / 2-position literal 扫描（双位置候选，降低 literal 扫描的每 symbol 周期）；
- **H**：2 B/cycle emit/回放（把输出回放从 1 B/cycle 提升到 2 B/cycle）。

## 本轮目标

做 **A+H 的隔离 RTL 原型**，先 H、后 A+H，验证能否把自然内容 N/L 的 4 帧稳态压到 G0 以内，同时保持 A1U1/zlib 输出逐字节兼容。**本轮只做离线 RTL/仿真，不做 TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK/网络。** TD/时序/资源资格必须在原型仿真 PASS 后由用户单独授权。

建议分两阶段（规划可按有界规则细化）：

1. **H-only 原型**：在冻结 b11 core 副本上只做 2 B/cycle emit/回放；N/L 1 帧探针 + 必要时 4 帧；要求输出 bitstream/CRC 与 baseline 逐字节相同；记录 cycles/B、backpressure、FIFO、资源增量估算。H 预期 6,260,648（仍差 0.17%），用来证明 H 本身正确且接近目标。
2. **A+H 原型**：在 H 基础上加 2-position literal 扫描；N/L 4 帧稳态，目标 S_ss ≤6,250,000；输出 bitstream/CRC 逐字节相同；记录 cycles/B、ERAM/LUT/REG 增量、关键路径风险。若达不到 6.25M，保留失败证据并给 kill/回退结论，不硬凑。

验收门槛（仿真范围内）：

- N/L 4 帧（或至少 1 帧探针 + 4 帧确认）S_ss ≤6,250,000（G0）；
- 同一输入的 A1U1/zlib 输出与 baseline **逐字节相同**（header/CRC/长度/尾字节全等）；
- 不改变几何/时钟/复位/内容/packing/协议；DUT 只在隔离副本中改；
- ERAM/LUT6/REG 增量有估算并对照 300/71,680/143,360；不把估算写成 TD 实测；
- 无 TD/板卡/网络；不修改生产源、b18/b19/b20、integrated delivery run、旧 P1–P4 冻结件、tasks.json。

## 硬约束

- 新 run；只写本 run 目录与 `%TEMP%/opencode/a-plus-h/**`；其余只读。
- **不要碰** `20261026-2138_fpga-integrated-delivery`（集成交付线，可能在使用 b18/b19/b20、TD/板卡）和 `20261026-144617_fpga-chain-detail-review`；本 run 不引用其活动候选、不争用 TD/板卡。
- 不改 `fpga/csi2/src/**`、`upstream/**`、`D:/TD/work/csi2/**`、`D:/fpga_work/**`、`workflow/tasks.json`、`docs/**`、`work/**`、`.agents/**`。
- 需要 b11/b6/P1/P2/P4 的 RTL/TB/内容时，只在本 run 复制冻结副本；DUT 0 修改；每任务独占 ModelSim `modelsim.ini`/工作库/日志。
- 不批量删除；不新增外部/队友消息授权；不改全局配置。
- 4 帧全尺寸单次约 22 min；规划需冻结总 wall/次数/超时；超时/SS_STALL/丢帧按 partial/not_proven，不得用 2/3 帧冒充 4 帧。
- **本轮不授权 TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK**；若原型仿真 PASS，下一包再单独申请 TD/时序/资源授权。

## 关键输入路径

- P2 coregap 报告：`workflow/runs/20261026-143924_fpga-1080p30-g0-production/test-reports/T10.ss-g0-prod-coregap-r1-integrated.md`
- P2 manifest-r1：`.../T10.ss-g0-prod-coregap/r0/manifest-r1.json`（`803d3efb…`，49）
- P2 模型/矩阵：`.../T10.ss-g0-prod-coregap/r0/out/{coregap-model,coregap-verdict,stage-probe}.json`、`model/*`
- P1 自然内容：`.../T10.ss-g0-prod-content/r0/{manifest-r1.json,out/content-verdict-r1.json,content/raw40_{n,l}.hex,src/tb_ss_4run_wd.v}`
- P4 总判定：`.../T10.ss-g0-prod-verdict/r0/{g0-production-verdict.json,manifest-r0.json}`
- 当前 b11 core：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b11-aplus-read/r0/changed-src/a1_deflate_core.v`（`6797db05…35bb`？以实际 manifest 为准）
- b11 frame top / TB：`.../T10.b11-aplus-read/r0/changed-src/a1_frame_top.v`、`.../r0/sim/tb_b11_full.v`
- b6 基线：`.../T10.b6-a1-htab-nw/r0/changed-src/a1_deflate_core.v`、`.../test-reports/T10.b6-a1-htab-nw-r0-integrated.md`
- 集成交付线（只读，不碰）：`workflow/runs/20261026-2138_fpga-integrated-delivery/**`
- 链细节审查（只读，不碰）：`workflow/runs/20261026-144617_fpga-chain-detail-review/**`

## 输出目录

`D:/fpga/ph1p100/workflow/runs/20261026-231711_fpga-a-plus-h-prototype`

## 期望

由规划角色按项目有界规则理解并拆分本轮 A+H 隔离原型；先派一个 H-only 包，H PASS 后再派 A+H；不要一次开多个。主只原样转发，不解释技术需求。
