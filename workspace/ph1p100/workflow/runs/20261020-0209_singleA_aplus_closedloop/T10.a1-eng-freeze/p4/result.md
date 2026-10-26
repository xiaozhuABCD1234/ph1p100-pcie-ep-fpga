# T10.a1-eng-freeze — 工程冻结报告（P4）

- task_id: `T10.a1-eng-freeze`｜round **r0**｜run `20261020-0209_singleA_aplus_closedloop`
- 日期：2026-10-20（Asia/Shanghai）｜性质：**离线、synthetic、未上板、未下载**
- 唯一判定：**G2 FAIL（时序未收敛，Routed not_run）→ 本包 blocked**；G0/G1 候选绑定与吞吐证据成立。
- 生产构建 **0**、下载 **0**、Flash **0**、PCIe/RK **0**、bit/CWC **未生成**。

## 1. 结论摘要

| 项 | 结果 | 依据 |
|---|---|---|
| 候选绑定 | **PASS** | `a1_frame_top.v` = `3c32803b…190961`、`a1_deflate_core.v` = `6cd35881…99d9f`，与 P3 r1 manifest 逐字节一致 |
| 综合资源 | **已取得（synthesized）** | LUT 11,026；FF 1,995；ERAM 4/300；DSP 0/220；slice 9,983/71,680 |
| 目标频率时序 | **FAIL** | SWNS **-6.471 ns**、STNS **-1133.864 ns**、Fmax **84.717 MHz**（目标 187.5 MHz） |
| Routed / G2 | **not_run / FAIL** | 第 2 次 TD 会话在 30 min 上限被终止于 global placement；综合时序已明确为负，布线无法挽回 |
| CDC | **结构结论：单时钟，无跨域路径**；TD `report_cdc` **not_run** | 单时钟 `clk0` 187.512 MHz，CC-From/CC-To = no；同步复位 |
| 1080p30 服务率 | **达标（测试范围内）** | 1080p 整帧 103.894 MB/s（≥77.76，97.2 余量 +6.9%）；2 帧聚合同值 |
| 真实样例导出 | **blocked（未执行）** | 见 `p4/export-contract.md`；无板窗/传输/用户在场，不虚构 |

**G2 门槛不成立，故本包不能判 PASS。** 该结论不是“工具缺失”，而是当前 RTL 在 187.5 MHz 下综合 Fmax 仅 84.7 MHz 的真实工程结果。

## 2. 候选与冻结绑定

| 文件 | SHA256 | 与 P3 r1 manifest |
|---|---|---|
| `upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_frame_top.v` | `3c32803b41378629622ae3a709ab64373b2fb13286bfc7ea789e7e1dbf190961` | **MATCH** |
| `upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v` | `6cd35881a864faec3a7fe9f8355d71a66f775bf2c037202959f315d42a799d9f` | **MATCH** |

- 上游 G0/G1 候选：`T10.a1-frame-top\CANDIDATE-MANIFEST.json`（151 files，0 missing，r1 integrated PASS）。
- 参数：`W=1920, H=1080`（`a1_frame_top` 默认参数，wrapper 显式传入）；`prep_en/pred_en` 为运行期输入；单时钟 `clk`。
- 约束：`create_clock -name clk -period 5.333 -waveform {0 2.667} [get_ports clk]`；**无 false path / multicycle**；块级 I/O 未加 I/O delay（内部 SoC 端口，非封装引脚）。
- 构建小顶：`a1_eng_top`（**build-only**，非候选 RTL）。仅把 7×32-bit test-only 状态总线 XOR 折叠为 `st_dbg[31:0]`，避免 TD 把状态端口计为封装 IO（首会话因 286 IO 上限失败）。不增删功能逻辑。
- 工具：Anlogic TD `Release_2026.2`，build `6.2.3.210850`（2026-08-19）；器件 `PH1P100SBG484 -3`。

## 3. TD 构建会话（预算 ≤3，实际 2）

| # | 命令 | 时长 | 结果 | 证据 |
|---:|---|---:|---|---|
| 1 | `td_commands_prompt.exe X:/00_all.tcl`（top=`a1_frame_top`） | 11.7 s | **失败**：`SYN-8228 ERROR: MapIO rule -- IO number may exceed device max IOs(286)` | `p4/logs/session1_stdout.log`、`session1_syn_run.log` |
| 2 | 同上，top=`a1_eng_top` | **1800 s 超时终止** | syn_1 **成功 44.3 s**；phy_1 进入 global placement Phase 4 后被 30 min 会话上限终止；无 Routed | `p4/logs/session2_stdout.log`、`session2_syn_run.log`、`session2_phy_run.log` |

- 第 3 次会话**未使用**：综合已给出 SWNS -6.471 ns / Fmax 84.717 MHz，布线只会更差；继续消耗 30 min 不会改变 G2 判定，按“不得改门槛/不得用理论带宽替代”停止。
- 失败原因不是工具缺失：TD 正常启动、综合完整完成、报告可读。

## 4. 综合资源（Optimize-Gate，`Confidence: Synthesized`）

| 资源 | 用量 | 器件容量 | 占比 |
|---|---:|---:|---:|
| LUT（`#lut`） | **11,026** | — | — |
| Slice | **9,983** | 71,680 | **13.93%** |
| FF / slice reg | **1,995** | 143,360 | **1.39%** |
| ERAM（20k） | **4** | 300 | **1.33%** |
| DSP | **0** | 220 | 0.00% |
| DRAM LUT（分布式 RAM） | **5,240** | — | — |
| IO | 121 | 286 | 42.31% |

层级：`u_core` = 2,888 logic LUT + 408 ripple + 1,447 seq + 4 ERAM + 3,320 DRAM LUT；`a1_frame_top` 其余约 918 logic LUT + 265 ripple + 548 seq + 1,920 DRAM LUT。

**推断问题（关键）**：`a1_deflate_core` 的 `cmem[0:4095]`（16-bit）与 `htab[0:1023]`（53-bit）被推断为**分布式 RAM**（5,240 DRAM LUT），而非 ERAM。资源虽在器件内，但组合读路径是时序失败的直接来源。

## 5. 时序（目标 187.5 MHz / 5.333 ns）

来源：`p4/reports/syn_gate_timing.rpt`（TD Optimize-Gate STA，`Check Corner: Both (Slow and Fast)`，`STA coverage: 97.57%`）。

| 指标 | 值 |
|---|---:|
| SWNS | **-6.471 ns** |
| STNS | **-1133.864 ns** |
| HWNS / HTNS | 0.000 / 0.000 ns |
| Period Check WNS | 2.533 ns |
| Fmax（R-Period） | **84.717 MHz**（11.804 ns） |
| 违例端点 | **568 / 9,685** |
| 时钟 | `clk0`，约束 187.512 MHz，fanout 7,898 |
| 关键路径 | `u_dut/u_core/w0_reg[1].clk` → `u_dut/u_core/cmem_syn_212.dia_extra[0]`，setup，`slow_125c`，budget 5.333 ns |

- 这是**综合后** STA；未布线的 Routed WNS/TNS **not_run**。综合已负 6.5 ns，布线不可能满足 G2。
- 未使用任何 false path 或放宽约束；`report_timing` 的 `Confidence` 为 `Synthesized`，不是 `Routed`。
- 根因方向（仅记录，不在冻结包内改 RTL）：`cmem` 组合读 + 4096 深度 mux；`htab` 53-bit 分布式表。需要将 `cmem` 改为同步读/寄存器输出（或真正的 ERAM 宏），并重新跑 P1–P3 回归后才能重测 G2。

## 6. CDC 检查结论

- **结构结论**：设计只有 **1 个时钟域** `clk`。综合 STA 的 Clock Summary 仅列出 `clk0`（187.512 MHz），`CC-From=no`、`CC-To=no`；RTL 使用同步复位（`always @(posedge clk)` + `if (!rst_n)`），无异步跨域。
- **TD 工具 CDC 报告**：**not_run**。第 2 会话在 `report_cdc` 之前被终止；第 1 会话未进入该步骤。复现入口：在 `00_all.tcl` 的 phy 完成后执行 `report_cdc -file cdc.rpt`（已写入脚本，未执行）。
- 因此本包只声明“按结构/时钟报告无 CDC”，**不**声明“TD CDC 工具 PASS”。

## 7. 持续服务率（1080p30 RAW10 等效）

口径：G1 整帧仿真周期 ÷ 187.5 MHz；分子为**原始 packed RAW10 字节**（2,592,000 B/1080p 帧）。1080p30 需求 = 2,592,000 × 30 = **77.76 MB/s**；余量目标 **97.2 MB/s**。

| 场景 | cycles | cycles/B | MB/s @187.5 | ≥77.76 | ≥97.2 |
|---|---:|---:|---:|---|---|
| 1080p p1d1（prep+pred） | 4,677,841 | 1.8047 | **103.894** | PASS | PASS |
| 1080p p1d0（prep only） | 4,807,468 | 1.8547 | **101.093** | PASS | PASS |
| 1080p p0（bypass） | 4,719,302 | 1.8207 | **102.981** | PASS | PASS |
| 1080p rand（全 stored） | 4,678,532 | 1.8050 | **103.879** | PASS | PASS |
| 1080p ×2 连续帧 | 9,355,687 | 1.8047 | **103.894** | PASS | PASS |
| 1920×16 rand | 80,999 | 2.1093 | 88.890 | PASS | no |
| 1920×16 mixed | 80,984 | 2.1090 | 88.906 | PASS | no |

- 需求周期预算：77.76 MB/s → 2.4113 cycles/B；实测 1.8047 → **1.336× 余量**。
- 97.2 目标：1.9290 cycles/B；实测 1.8047 → **+6.9% 余量**（仅对已测整 1080p 帧）。
- 内容相关性：1080p 四种内容 101.09–103.89 MB/s；全 stored 不慢于压缩路径。16 行小帧因每帧固定开销降到 88.9 MB/s（仍 ≥77.76，但 <97.2）；20×5 小帧约 44 MB/s，不代表 1080p。
- 连续多帧口径：只有 **2 帧背靠背**（间隔 5 cycles），聚合 103.894 MB/s；**没有**长稳/热态/随机反压跨帧数据。97.2 不是跨内容、长稳或板上保证。
- 所有数字是 187.5 MHz **仿真换算**，不是 STA/板上实测；在 G2 时序未收敛前，不能把该服务率当作可上板结论。

## 8. 已知限制

1. **时序不收敛**：综合 Fmax 84.717 MHz < 187.5 MHz；Routed not_run。G2 FAIL。
2. `cmem`/`htab` 推断为分布式 RAM，5,240 DRAM LUT；组合读路径是主因。
3. 无 bit/CWC 产物（未到 bitgen），无 Routed 资源/时序。
4. 无 TD CDC 工具报告；仅结构单时钟结论。
5. 块级 I/O 未约束；状态总线在 build wrapper 中被 XOR 折叠（test-only）。
6. 吞吐仅 1080p 单帧/2 帧与 16 行小帧；无长稳、无真实 RAW、无板上测量。
7. 首会话的 IO 上限失败是 top 端口选择问题，不是 RTL 功能失败；wrapper 已修正。

## 9. 回退方法

- 本包**只新增**：`upstream/.../rtl/ep_side/codec/`（P1–P3 已存在的新增文件）、`workflow/runs/.../T10.a1-eng-freeze/**`。未修改任何既有生产文件。
- 回退 P4：删除 `T10.a1-eng-freeze` 整个目录即可；TD 工程与所有日志都在其中。
- 回退 codec 候选：删除 `rtl/ep_side/codec/`、`sim/tb/codec/`、`tools/codec/` 下本轮新增文件；不影响 B01 生产候选与旧 run。
- 旧版本回退路径：`T10.a1-frame-top\CANDIDATE-MANIFEST.json`（r1，151 files）仍是最后一个 **G0/G1 PASS** 候选；其 hash 与本次绑定一致，可直接复跑 `tools/codec/run_p3.ps1`。
- 生产 B01 bit 未触碰；无下载/Flash，故无板上回退动作。

## 10. T11 / 集成注意

- 变长流：`stream_len` 必须逐帧传递；不能按固定 2,592,000 B 假设缓冲。
- CRC 域：`raw_crc32`、`xform_crc32`、`stream_crc32` 三个域分别命名，不得混用；32 B test-only 头不含 `stream_crc32` 与 W/H，集成时必须外置。
- 不占生产枚举：`A1T1` 头与 `a1_*` 模块均为 test-only，不写入 R10F/DMA，不分配 T03 枚举。
- **在时序修复前不得接入生产路径**：当前 Fmax 84.7 MHz，直接集成会在 187.5 MHz 域失败。

## 11. 复现入口

```powershell
# ASCII 盘符映射（路径含中文）
subst X: "<run>\T10.a1-eng-freeze\p4\td"
subst Y: "<PROJECT_ROOT>"
cd X:\
D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe X:/00_all.tcl
```

- 脚本：`p4/td/00_all.tcl`；约束：`p4/td/a1_small_top.sdc`；wrapper：`p4/td/a1_eng_top.v`。
- 综合报告已复制到 `p4/reports/`；原始 run 目录：`p4/td/a1_eng_freeze_Runs/syn_1/`、`phy_1/`。
- 复测 G2 前必须先修 RTL 并重跑 P1–P3；不得只重跑 TD 改判。

## 12. not_run 清单

- Routed 实现、Routed WNS/TNS、布线后资源、bit/CWC、TD CDC 报告、板上 SRAM、下载/Flash、PCIe/RK、真实 RAW/真实 Bayer 相位、双路 155.52 MB/s、G3/G4/长稳/热态：**not_run / blocked**。
- 生产集成构建：**0**（按预算）。
