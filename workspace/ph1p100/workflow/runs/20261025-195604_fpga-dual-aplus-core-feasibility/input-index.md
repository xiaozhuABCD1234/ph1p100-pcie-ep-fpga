# 输入索引：双路 A+ 双核/服务率可行性（离线）

- run：`20261025-195604_fpga-dual-aplus-core-feasibility`
- 角色：fpga-planner（只规划/冻结/拆分，不写生产 RTL，不派生代理）
- 日期：2026-10-25
- 输出目录：`D:/fpga/ph1p100/workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility`
- 用户原话：“现在这个run使用工作流开始开双路 A+ 双核/服务率可行性。”
- 紧邻上下文：用户选择并行池 P1“双路 A+ 双核/服务率可行性（新开 run，先做模型）”。
- 本轮主要目标：回答 PH1P100 上双路 1920×1080@30 RAW10 的 A+ 压缩，在单核/双核下的资源、时序、DDR 带宽、调度服务率是否可行；若不可行，给出单核降帧或降分辨率的量化结论。
- 范围：仅 FPGA 侧离线模型/表格/报告；不接 RK；不做板卡/COM/JTAG/下载/Flash；P1/P2 不跑 TD；P3 仅在 TD 空闲且 b11 不重建时做一次隔离综合，不布线、不 bitgen、不下载。

## 1. 治理与流程输入

| 用途 | 路径 | 使用方式 |
|---|---|---|
| 项目根约束、删除禁令、工作流授权 | `D:/fpga/ph1p100/AGENTS.md` | 只读；批量删除禁令优先 |
| 规划角色合同 | `D:/fpga/ph1p100/.agents/skills/fpga-planner/SKILL.md` | 只读；本文件由其产出要求驱动 |
| 设计指南合同 | `D:/fpga/ph1p100/.agents/skills/fpga-design-guide/SKILL.md` | 只读；冻结本任务工程语义 |
| 有界规则（唯一正文） | `D:/fpga/ph1p100/.agents/skills/fpga-orchestrator/references/work-limits.md` | 只读；1 目标/≤4 包/两级/≤5 步/预算/停止 |
| 主传输合同 | `D:/fpga/ph1p100/.agents/skills/fpga-orchestrator/references/relay-contract.md` | 只读；dispatch 与返回元数据格式 |
| 综合测试报告约定 | `D:/fpga/ph1p100/.agents/skills/fpga-orchestrator/references/report-contract.md` | 只读；PASS/FAIL、三维、G 层 |
| 项目入口与任务映射 | `D:/fpga/ph1p100/.agents/skills/fpga-orchestrator/references/project-context.md` | 只读；T10/F5 归属、155.52/194.4 口径 |
| 宿主调用适配 | `D:/fpga/ph1p100/.agents/skills/fpga-orchestrator/references/runtime-calls.md`、`opencode-calls.md` | 只读；本 run runtime=opencode |
| 开发角色合同 | `D:/fpga/ph1p100/.agents/skills/fpga-dev/SKILL.md` | 只读；P1/P2 由新开发执行 |
| 测试角色合同 | `D:/fpga/ph1p100/.agents/skills/fpga-tester/SKILL.md` | 只读；每任务一个新综合测试者 |

## 2. 需求与当前状态

| 对象 | 路径 | 采用事实/约束 |
|---|---|---|
| 本轮需求与硬约束 | `D:/fpga/ph1p100/workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility/request.md` | 范围、保护路径、TD 串行、b11 优先 |
| 并行工作再评估 | `D:/fpga/ph1p100/docs/并行工作再评估_2026-10-25.md` | §0 本地未接 RK；§2 D/P1；§3 双路不能外推单核、20B/32B、81.067 限制 |
| 项目成果整合与进度复核 | `D:/fpga/ph1p100/docs/项目成果整合与进度复核_2026-10-25.md` | §2 进度；§3 b6 81.067 是核级固定向量，不是整链/双路；§4 离线包边界 |
| 主传输日志 | `D:/fpga/ph1p100/workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility/main-log.md` | 只读；主已登记 run/约束 |

## 3. 单核 A+ 真实资源与吞吐证据（核心输入）

| 对象 | 路径 | 采用事实/用途 |
|---|---|---|
| b6 独立综合报告 | `D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/test-reports/T10.b6-a1-htab-nw-r0-integrated.md` | PASS（带 caveat）；comp 355,261 cycles / 81.067159 MB/s；rand 161,479 / 178.351；Routed WNS +0.119、hold +0.020、0/19,779；ERAM 102、LUT6 18,743、REG 25,135、slice 22,608 |
| b6 候选 manifest | `.../T10.b6-a1-htab-nw/CANDIDATE-MANIFEST-b6-a1-htab-nw-r0.json` | core SHA `6797db053cfc47497540d6345e3a46b7e79cc1d34fa25da5a4c501505fbf35bb`（80,196 B）；manifest SHA `2e9fd356824084813e3415af11757c1b56f774c9b6dd45f3b2a111647ad08880`；comp/rand 输入 SHA |
| b6 规划/设计冻结 | `.../T10.b6-a1-htab-nw/dev-plan.md`、`fpga-design-guide.md` | 只读；精确等价条件、资源/时序门槛、187.5 MHz、禁止降频/放宽 |
| b6 开发结果 | `.../T10.b6-a1-htab-nw/r0/result-r0.md` | 只读；实现差异、P1 三例、Routed 证据入口 |
| b6 Routed 面积（层次） | `.../T10.b6-a1-htab-nw/r0/td/routed_area.rpt` | **关键**：u_core 23 ERAM / 1,399 logic LUT / 1,175 seq；u_bridge 15 ERAM；u_mcu_core 28 ERAM；顶层 102 ERAM |
| b6 Routed 时序/QoR | `.../T10.b6-a1-htab-nw/r0/td/routed_timing.rpt`、`routed_qor.rpt`、`routed_check_timing.rpt`、`routed_clock_utilization.rpt` | 只读；WNS/hold/period/端点/时钟；P1 必须从原报告复算，不抄 manifest |
| b6 综合面积/时序（仅参考） | `.../T10.b6-a1-htab-nw/r0/td/syn_gate_area.rpt`、`syn_gate_timing.rpt` | **不得用于资源拟合**；synth ERAM 72 与 routed 102 不同，只能作检查点 |
| b6 构建控制台 | `.../T10.b6-a1-htab-nw/r0/td/build_console_r0.log` | 只读；用于核对 TD 版本/器件/资源行 |
| b6 边界（探索性） | `.../T10.b6-a1-htab-nw/r0/sim/boundaries/result.json` | 仅参考；非正式验收，不作为本 run 的速率依据 |
| b6 测试者证据目录 | `D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/test-reports/T10.b6-a1-htab-nw-r0-evidence/` | 只读；独立解析器/负对照/命令日志 |

## 4. 整机单链资源与当前板级边界

| 对象 | 路径 | 采用事实/用途 |
|---|---|---|
| b10 r1 结果 | `.../T10.b10-b9-fix/result-r1.md` | Routed WNS +0.103、hold +0.020、0/24,665；slice 24,368、REG 28,004、LUT6 19,695、ERAM 102、DSP 0；`#DRAMHARDCON=85`，合计 187/300；板级 180 包但无像素，**不是吞吐证据** |
| b10 r1 Routed 面积 | `.../T10.b10-b9-fix/r0/td/routed_area.rpt` | 整机层次：u_core 23 ERAM、u_bridge 15、u_mcu_core 28；顶层 102；用于双核边际成本与整机基线 |
| b10 r1 Routed 时序/QoR | `.../T10.b10-b9-fix/r0/td/routed_timing.rpt`、`routed_qor.rpt` | 只读；单核整机 WNS/hold/端点 |
| b10 r1 manifest | `.../T10.b10-b9-fix/CANDIDATE-MANIFEST-b10-b9-fix-r1.json` | 只读；候选/源 SHA 绑定，不作本 run 候选 |
| b11 r0 结果（并行） | `.../T10.b11-aplus-read/r0/result-r0.md` | 只读；WNS +0.015（诊断候选，**不是本 run 基线**）；整帧读回仿真 pass；下载被硬件阻塞 |
| b11 r0 面积/时序/QoR（并行） | `.../T10.b11-aplus-read/r0/td/routed_area.rpt`、`routed_timing.rpt`、`routed_qor.rpt` | 只读；u_core 23 ERAM；顶层 102+85；仅作交叉核对 |

## 5. 双路/槽/调度合同（当前架构假设）

| 对象 | 路径 | 采用事实/用途 |
|---|---|---|
| 20261025-180900 计划 | `D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure/dev-plan.md` | 只读；双路离线两包、23 条账、G0/G1 边界；本 run **不加入**该 run |
| 20261025-180900 设计指南 | `.../fpga-design-guide.md` | **关键合同**：R10F 紧密布局双路 155.520 MB/s；RAW 写+读最低 311.040 MB/s；最坏 stored zlib 2,594,706 B；CMP 8 MiB；A1U1 44 B；core 81.067 不是双路保证 |
| T08 双路本地闭环开发结果 | `.../T08.dual-local-closure/result-r0.md` | 只读；双路 checked CSI/writer/同步/I2C；本地 CRC 读回/释放；W8H2 运行不代表 1080p 吞吐 |
| T08 独立报告 | `.../test-reports/T08.dual-local-closure-r0-integrated.md` | 只读；四槽/8 MiB/29 bit/128 beat/4KiB 边界；读回 8 word/beat；不声称实时 |
| T10 双路调度开发结果 | `.../T10.dual-aplus-scheduler/result-r0.md` | 只读；**blocked before freeze**；真实 A+ 核 + 调度器；TB 100 MHz、one-beat reader；未取得双路 1080p30 吞吐；其“历史 81.067 不满足双路 155.52”是预算陈述，不是本 run 结论 |
| T10 双路调度独立报告 | `.../test-reports/T10.dual-aplus-scheduler-r0-integrated.md` | **不存在**；不得当作 PASS 或复用其判定 |

## 6. 器件、DDR、预算与压缩口径

| 对象 | 路径 | 采用事实/用途 |
|---|---|---|
| 双目整链路方案 | `D:/fpga/ph1p100/docs/双目首版_整链路方案与团队交付.md` | 器件 p11 表：PH1P100 129,024 LUT4、143,360 DFF、300 ERAM20K（6,000 Kbit）、220 DSP、12 PLL；RAW10/RAW12 字节表；2R+2S；25% 余量；RAW12 封存，不得混用 |
| 压缩方案 G2 复核 | `D:/fpga/ph1p100/docs/压缩方案G2复核与优化方向_2026-10-22.md` | P2 comp 355,261/81.067@187.5；150 MHz 仅 64.854；满足 77.76 需 ≥179.851 MHz；P2 comp 本身未达 97.2 MB/s（77.76×1.25）；综合 WNS 不能代表 Routed |
| DDR1333/1600 对比 | `D:/fpga/ph1p100/docs/DDR1333集成与1333vs1600对比_2026-10-17.md` | ×32 理论峰值：1600≈6.4 GB/s、1333≈5.33、800E≈3.2；双路 1080p30 RAW10 155.52（+25%=194.4）；2R+2S 约 622–778（RAW 回退 S≈R，**旧 RAW12 口径**）；三档均“够”是计算值，未实测 |
| DDR 完整帧后端上板 | `D:/fpga/ph1p100/docs/DDR完整帧后端实施与上板验证_2026-10-11.md` | 实际时钟报告 DDR 800 MHz、用户 200 MHz、MCU 50 MHz；配置 DDR3_1600K/tCK1250；**不是实测带宽** |
| 项目入口预算口径 | `D:/fpga/ph1p100/.agents/skills/fpga-orchestrator/references/project-context.md` | 双路 1080p30 packed RAW10=155.520 MB/s，+25%=194.400；8bit/100MHz 原型不能证明双路最坏回退 |
| 旧 1080p p1d1 103.892 MB/s | `.../T10.a1-area-map/p4/result-r0.md` | **不采用**为本 run 核速率；旧 core variant、不同 top，且 Routed 失败；只作历史对照 |

## 7. 工具与环境

| 工具 | 路径/版本 | 本 run 用法 |
|---|---|---|
| Python | 3.11.5（b6 报告） | P1/P2 模型、CSV、独立复算；无第三方网络依赖 |
| TD | `D:/anlogic/TD_Release_2026.2`，`td_commands_prompt.exe`，器件 `PH1P100SBG484 -3` | 仅 P3（blocked）一次隔离综合；P1/P2 为 0 |
| TD 盘符/入口 | `D:/fpga/ph1p100/tools/td/td_env.ps1`、`tools/td/PATH_CONTRACT.md` | 仅 P3；`T:`=run 的 td 目录，`Y:`=项目根；禁止 `X:` |
| ModelSim | `D:/intelFPGA/18.1/modelsim_ase/win32aloem`，10.5b | 本 run P1/P2 不需要；P3 不需要仿真；如后续需要，独占库/日志 |
| 图/表 | 纯文本/CSV/Markdown | 不依赖 GUI、Excel、截图；报告表格由 CSV 生成 |

## 8. 采用版本与冲突裁决

### 8.1 采用

| 项 | 采用值 | 来源 | 说明 |
|---|---|---|---|
| A+ core | `6797db05…35bb`，80,196 B | b6 manifest | b9/b10/b11 同 core；禁止用 r4/r5/area-map 旧 core 速率 |
| 单核核级 comp | 355,261 cycles / 153,600 B / 81.067159 MB/s @187.5 MHz | b6 独立报告 | 固定向量核级；不是整链/双路 |
| 单核核级 rand | 161,479 cycles / 178.351 MB/s | b6 manifest | stored 回退；快于 comp，不作为最坏服务率 |
| 单链 full_grad 锚点 | 6,421,414 cycles / 1920×1080 / 40,076 B export | b6 P1 STAT | **链级锚点**，用于 serial bound；必须核对包含/不包含 UART/DDR 的边界 |
| 时钟 | 187.5 MHz | b6/b10 SDC/报告 | 仅 150/175/200 作敏感性，不改设计 |
| 帧/打包 | 2,073,600 px；2,592,000 B；518,400 groups；5 B/group | 定义 | RAW10 packed，W×H 可被 4 整除；否则末组填充另记 |
| DDR RAW 槽 | 4,147,200 B/frame；129,600×256 bit words；20 B/32 B | 并行评估/20261025-180900 指南 | 写/读各 1.6× 膨胀；不得用 1.0× |
| CMP | 最坏 stored 2,594,706 B/frame；slot 8 MiB；A1U1 44 B；DMA 2,592,768 B | 20261025-180900 指南/T10 | 只算字节/速率，不声称编码/解码 |
| 器件 | 300 ERAM20K、129,024 LUT4、143,360 DFF、220 DSP、12 PLL；slice 71,680 | 双目方案 p11 + TD area | 以 TD 报告行名为准；不把 LUT4 与 LUT6 混称 |
| 裕量门槛 | 25%（容量 ≥1.25×需求） | 双目方案/项目入口/压缩复核 | 0% 仅作“算术实时”对照，不得当 PASS |
| DDR 理论峰值 | ×32 1600 MT/s ≈6.4 GB/s | DDR 文档 | 未扣刷新/仲裁/行切换；不是实测 |
| 单核资源基线 | b6/b10/b11 Routed：顶层 102 ERAM；u_core 23 ERAM、~1.4k logic LUT + 783 ripple、~1.2k seq、32 DRAM LUT；bridge 15；MCU 28；b10/b11 另 DRAMHARDCON 85 | routed_area.rpt | **必须用 routed，不用 synth**；层次列是“核心相关”，不是 LUT6 精确增量 |
| 单核时序基线 | b6 Routed WNS +0.119 / hold +0.020 / 0 违例；b10 r1 +0.103 / +0.020 / 0 | 报告/area | 双核时序**未证明**；不得外推 |
| 板级 | b11 下载被 JTAG 阻塞；b10 有 180 包无像素 | 结果 | 本 run 不做板级；无板级吞吐/恢复结论 |

### 8.2 不采用/不得混用

| 项 | 原因 |
|---|---|
| RAW12 的 622.08/777.60 MB/s 2R+2S | 旧格式/旧回退口径；本 run 是 RAW10 + 20B/32B，必须重算 |
| b6 synth ERAM 72 / LUT6 8,528 | 综合与 Routed 差异大；资源拟合用 Routed |
| b10 r1 板级 180 包 | 无像素、无帧；只能证明状态/UART 活着 |
| b11 WNS +0.015 | 并行诊断候选，不是本 run 基线；不能用于双核时序 |
| T10 scheduler TB 100 MHz 吞吐 | 非生产 187.5 MHz；one-beat reader；未取得双路帧率 |
| 旧 p1d1 103.892 MB/s | 旧 core/top，Routed 失败；不可作 b6 核速率 |
| 把 81.067×2=162.13 >155.52 直接判“双核可行” | 聚合带宽掩盖 per-stream 30 fps 与链级开销；必须 per-stream + full-chain |
| 把顶层 102 ERAM×2=204 直接判“双核装不下/装得下” | 顶层含 MCU 28、bridge 15 等共享/可复用逻辑；必须做层次边际与保守上界两栏 |

## 9. 写范围与保护

### 9.1 本 run 允许写

- `D:/fpga/ph1p100/workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility/` 下本 run 规划/任务/测试目录。
- P1：`.../T10.dual-core-resource-baseline/**`
- P2：`.../T10.dual-aplus-service-verdict/**`
- P3（仅解阻后）：`.../T10.dual-core-synth-probe/**`
- 综合测试：`.../test-reports/<task_id>/**` 与 `<task_id>-r<round>-integrated.md`

### 9.2 保护（只读，不得修改）

- `D:/fpga/ph1p100/fpga/csi2/src/**`
- `D:/fpga/ph1p100/upstream/**`
- `D:/TD/work/csi2/**`
- `D:/fpga_work/**`
- b11：`.../20261020-0209_singleA_aplus_closedloop/T10.b11-aplus-read/**`
- T08：`.../20261025-180900_fpga-dual-offline-closure/T08.dual-local-closure/**`
- T10：`.../20261025-180900_fpga-dual-offline-closure/T10.dual-aplus-scheduler/**`
- `workflow/tasks.json`（本 run 不修改）
- `docs/**`（OneDrive junction，只读）
- 其他 run/worktree、所有 bit/CWC/BID/DB、TD 盘符映射、板卡/COM/JTAG
- 本 run 的 `input-index.md`、`fpga-design-guide.md`、`dev-plan.md`、`dispatch.json`（开发/测试只读）

## 10. 未决/内部假设（不需用户输入）

1. **链级锚点边界**：b6 P1 full_grad 的 6,421,414 cycles 是否包含 UART 导出、DDR 读/写、槽管理等；P1/P2 必须从 TB/STAT 定义核实并写明。若无法分解，报告同时给 serial bound 与 core-only bound，不得把 core-only 当系统结论。
2. **DDR 路径**：当前按“相机写 RAW 槽 → A+ 读 RAW → 写 CMP 槽 → UART/PCIe 读 CMP”=2R+2S；若实际是直接流式/不经 CMP DDR，报告必须给变体并标明。
3. **双核共享**：假设两颗 core 共享一个 256-bit PAXI/DDR 端口、共享 MCU/DDR PHY；第二路相机/writer/bridge 的资源按 T08/T10 合同估算。若实际是两独立端口，另给敏感性；不得假设未授权的硬件。
4. **内容依赖**：只有 comp/rand 两个核级向量和 full_grad 一个全帧；没有自然图像/低照/噪声实拍。报告必须写“最坏内容未证明”，不得把 comp 当所有场景的保证。
5. **双核时序**：没有双核 Routed 构建；P3 仅综合。双核时序结论只能是“未证明/需后续”，不能由单核 +0.119 外推为双核 +0.119。
6. **TD 争用**：P3 只在 b11 不重建、TD 空闲、规划明确放行时做；否则保持 blocked，不影响 P1/P2 结论。

## 11. 快速入口

- 需求：`request.md`
- 计划：`dev-plan.md`
- 设计冻结：`fpga-design-guide.md`
- 派发：`dispatch.json`
- 单核 b6：`workflow/runs/20261020-0209_singleA_aplus_closedloop/test-reports/T10.b6-a1-htab-nw-r0-integrated.md`
- 整机 b10：`.../T10.b10-b9-fix/result-r1.md`
- 双路合同：`workflow/runs/20261025-180900_fpga-dual-offline-closure/fpga-design-guide.md`
- 器件/预算：`docs/双目首版_整链路方案与团队交付.md`
