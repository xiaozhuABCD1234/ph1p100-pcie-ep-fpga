# T10.a1-eng-freeze — 开发记录（dev-notes）

- task_id: `T10.a1-eng-freeze`｜round r0｜2026-10-20
- 角色：独立开发（原 fpga-dev 技能缺失，按 role-rules + dev-plan 执行）
- 结果：**blocked**（G2 时序 FAIL；候选绑定/资源/吞吐证据成立）
- 预算：工具调用 ≤30；TD 会话 ≤3（实际 2）；生产构建 0；下载 0。

## 1. 写域与新增文件（未改任何既有文件）

新增于 `upstream/ph1p100-pcie-ep-fpga` 以外或 codec 新增目录：

| 路径 | 性质 |
|---|---|
| `workflow/runs/.../T10.a1-eng-freeze/p4/td/00_all.tcl` | TD 构建脚本（新增） |
| `.../p4/td/a1_small_top.sdc` | 单时钟约束（新增） |
| `.../p4/td/a1_eng_top.v` | **build-only** wrapper（新增，非候选 RTL） |
| `.../p4/reports/*.rpt` | 从 TD run 目录复制的综合报告（新增） |
| `.../p4/logs/*.log` | 构建日志（新增） |
| `.../p4/result.md`、`dev-result.md`、`export-contract.md`、`dev-notes.md` | 文档（新增） |
| `.../T10.a1-eng-freeze/CANDIDATE-MANIFEST.json` | 唯一冻结 manifest（新增） |

未修改：`a1_frame_top.v`、`a1_deflate_core.v`、P1/P2/P3 工具与 TB、生产 `.al`/`build.tcl`、`constraints/**`、旧 run、B01 候选。

## 2. 构建会话与失败处理

### 会话 1（11.7 s，失败）
- top 直接设为 `a1_frame_top`。
- `SYN-8228 ERROR: MapIO rule -- The IO number may exceed the device max IOs(286).`
- 原因：`a1_frame_top` 暴露 7×32-bit test-only 状态总线 + 32-bit 输出 + 40-bit 输入，TD 把顶层端口当封装 IO，合计 >286。
- 处理：新增 build-only `a1_eng_top`，把状态总线 XOR 折叠为 `st_dbg[31:0]`，保留全部计数器（不被优化掉），IO 降到 121。未改候选 RTL。
- 证据：`p4/logs/session1_stdout.log`、`session1_syn_run.log`。

### 会话 2（1800 s 上限终止）
- `create_project` + syn_1 + phy_1 + 报告 + `save_best_bits`。
- **syn_1 成功**：44.3 s，生成 `a1_eng_freeze_gate.area` / `.timing` / `.ts`。
- `wait_run phy_1` 在 global placement Phase 4 时达到 30 min 会话上限，被 shell 超时终止；无 Routed、无 bit/CWC。
- `report_area`/`report_timing` 在 `wait_run` 之后执行时报 “Design is unavailable / Cannot find top model”，因为会话未 import netlist；**实际报告取自 run 目录**，未伪造。
- 证据：`p4/logs/session2_stdout.log`、`session2_syn_run.log`、`session2_phy_run.log`。

### 为什么不用第 3 次会话
- 综合 STA 已给出 SWNS **-6.471 ns**、Fmax **84.717 MHz**，目标 187.5 MHz。
- 布线只会增加延迟；再跑 30 min 不可能把 -6.5 ns 变成 ≥0。
- 按 dev-plan §7“WNS<0 → FAIL/blocked，不自动扩轮”，停止并保留证据。

## 3. 关键工程发现

1. `cmem[0:4095]`（16-bit）被推断为**分布式 RAM**，综合关键路径为 `w0_reg → cmem_syn_212.dia_extra[0]`；`htab[0:1023]`（53-bit）亦为分布式。总计 5,240 DRAM LUT、仅 4 ERAM。
2. 资源本身很小（11,026 LUT、1,995 FF、4 ERAM、0 DSP），**不是容量问题，是组合读路径问题**。
3. 状态总线在 wrapper 中 XOR 折叠后仍保留全部计数器；资源数字可代表候选 datapath。
4. 块级 I/O 未约束；G2 的门槛是内部 187.5 MHz 单时钟，不是封装 I/O。

## 4. 候选绑定核对

| 文件 | 实测 SHA256 | 与 P3 r1 manifest |
|---|---|---|
| `a1_frame_top.v` | `3c32803b41378629622ae3a709ab64373b2fb13286bfc7ea789e7e1dbf190961` | MATCH |
| `a1_deflate_core.v` | `6cd35881a864faec3a7fe9f8355d71a66f775bf2c037202959f315d42a799d9f` | MATCH |

P3 r1 manifest：`T10.a1-frame-top/CANDIDATE-MANIFEST.json`（151 files，0 missing，G0/G1 PASS）。
本包 manifest 对上述两文件再次记录 SHA256，并记录 build-only wrapper/sdc/tcl 与全部证据的 SHA256。

## 5. 吞吐口径

- 直接引用 G1 实测 cycles，不重新估算：1080p p1d1 4,677,841 cycles → 1.8047 cycles/B → 103.894 MB/s @187.5 MHz。
- 1080p30 需求 77.76 MB/s = 2.4113 cycles/B；97.2 MB/s = 1.9290 cycles/B。
- 2 帧聚合 9,355,687 cycles / 5,184,000 B，5-cycle 帧间间隔；无长稳。
- 16 行帧 88.9 MB/s（≥77.76、<97.2）；20×5 小帧 ~44 MB/s，不作 1080p 结论。
- 所有数字为仿真换算，非 STA/板上。

## 6. 复现与安全终止

```powershell
subst X: "<run>\T10.a1-eng-freeze\p4\td"
subst Y: "<PROJECT_ROOT>"
cd X:\
D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe X:/00_all.tcl
```

- 所有命令启动前设置 1800 s 上限；TD 会话 1/2 均记录退出码/时长/日志。
- 无下载、无 Flash、无 PCIe/RK、无生产构建。
- 停止后不再修改候选 RTL；manifest 冻结。

## 7. 未做/后置

- Routed G2、bit/CWC、TD CDC 报告、板上 SRAM、真实 RAW/相位、双路 155.52、G3/G4/长稳：not_run/blocked。
- 时序修复（cmem 同步读/ERAM 宏、htab 存储重构）需改 RTL → 必须重跑 P1–P3，另立切片；不在本冻结包内做。
