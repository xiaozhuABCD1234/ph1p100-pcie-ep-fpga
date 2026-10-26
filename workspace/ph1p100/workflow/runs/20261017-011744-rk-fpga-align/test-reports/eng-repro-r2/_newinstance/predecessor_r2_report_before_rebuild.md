### 判定：PASS

# T07.rk-align-backend round2 · engineering（时序与工程）复测报告

- task_id：T07.rk-align-backend；dimension：engineering；round：2（复测；本报告绑定 round2 冻结输入）。
- 冻结 manifest：`workflow/runs/20261017-011744-rk-fpga-align/backend/candidate-manifest.json`，SHA256=`CDE55FC8872674F13E0457B8F84C75E1E34AE67C040584D2F38FD56567F0EDEC`（实算一致；schema=2 / round=2）。
- 工作树：项目根，HEAD `ba0fca5f2c397db88059040b2ffe55c76867da31`（未变）；`fpga/csi2/pcie_integration/`、`tools/pcie_integration/`、本 run 目录仍为未跟踪新目录；仓库 28 项 pre-existing dirty（20261016 TD/IpTool run）未被本轮触碰。
- 工具（实查）：TD Release_2026.2 / Build 6.2.3.210850；ModelSim Intel FPGA Edition vlog/vsim 10.5b（2016.10）；Python 3.11.5；Windows PowerShell 5.1.26100.9711（ACP=936，见发现 F1）。
- 声明：未修改任何冻结输入/生产文件；写入仅限 `test-reports/eng-repro-r2/**` 与本报告；未重跑 TD、未操作硬件。

## 0. 结论摘要

| 复测项（派发指定） | 结果 |
|---|---|
| G2 同一最终 run DB 的 STA 绑定 | **通过**：`final_timing.rpt`(06:03:23/Routed/Both/CRPR) SWNS **+0.107 ns** / STNS **0.000**（**0 违例端点**）、HWNS +0.020 / HTNS 0.000；`route_flow.status`(final) +107ps/0；`place_flow.status`(manhattan) +725ps/0；`syn flow.status`(basic) +101ps/0 —— 四处一致、同一 run |
| clk2/clk3（187.5 MHz 字节域） | **通过**：cam_a **+0.107**（C 5.332 / R 5.225 = 191.388 MHz，1829 端点，hold +0.032）；cam_b **+0.130**（C 5.332 / R 5.202 = 192.234 MHz，1742 端点，hold +0.020） |
| 资源 | **通过**：LUT6 **13,713/71,680**（19.13%）、slice reg 15,793/143,360（11.02%）、slice 15,007/71,680（20.94%）、**ERAM 134/300**（44.67%，FIFO20K=0）、DSP 0/220、PCIE 1/1、DDR byte 7/24、PLL 3/12、IO 107/286 |
| bit 与 best_result 同源 | **通过**：`0943CB36…8B0A`（5,224,023 B），两处同 SHA；与同次 `pr.db`/`place.db`/`final_timing.rpt` 同 run（06:01:54–06:03:42）；候选树内仍只有这一个 bit |
| r0 §4（默认入口对冻结输入编译失败） | **已清除**：冻结 RTL 上 `vlog` 0 错；五个 G1 TB 全部 `ALL PASS`（我独立重跑，含 680 拍差分 0 失配、20387 TLP）；证据时间戳（我 06:18–06:19 / 开发 r2 05:54:05–05:54:39）全部晚于 RTL 末次修改 05:50:06；默认入口无任何 `-suppress` |
| r0 §5（manifest 冻结后 commands.log 漂移） | **已清除**：schema2 明确 `volatile_excluded`（commands.log/abs.f/run.do/vsim_stdout.log/td_*.log/*.logw，理由写明 round0 F3 实测）+ `path_base` 明确路径基准；我独立复算 **232/232 全部匹配**（含 size）；冻结后无任何 manifest 条目被写（唯一 06:06:14 的 `backend/g2/README.md` 不是 manifest 条目） |
| 约束/判据未被放宽 | **通过**：SDC/ADC 与 r0 **逐字节相同**（`3f999c44…`/`67831295…`）；无 multicycle/false_path/set_max_delay；187.5 MHz（1.333 ns ÷4 = 5.332 ns）与异步域声明未变 |
| manifest/selfcheck/候选绑定 | **通过**：232 条（prod 153 + scripts 8 + tests 8 + rk 28 + artifacts 35）；生产树 153 = manifest 153（无差集）；sim 8 = test_inputs 8；来源 142 peer_unchanged / 7 modified / 1 local_copy_modified / 1 local_copy_unchanged / 10 new 与声明一致 |
| 薄余量 + END_PACKET 死代码登记 | **充分**（两处均如实登记，见 §7；另发现两处文档/注释不准确，见 §8 F2/F3） |
| CWC / G3–G5 | not_applicable（同 r0：无 CWC 生成物；纯后端候选，板验/DMA 实收/发布留给 system 与后续包） |

**判定说明**：任务与指南对 engineering 的门槛（「独立复核同 manifest 最终 DB/STA/约束/CDC/资源与 bit；G2 必需」）在新 manifest 上全部满足，且 r0 的两项独立发现均已真实清除（其中一项需在宿主上下文上做显式 UTF-8 解码才能完整复跑，见 F1）。F1–F4 为工具/文档层面的缺陷登记，不触及候选身份（RTL/约束/bit/DB 未被建议改动），故不改变本维度判定。

## 1. 本任务范围与必需 G 层（判据未变）

- 依据 `task-T07.rk-align-backend.md` §局部检查、`fpga-design-guide.md` §构建和真实硬件、`dev-plan.md` T07 行（round2 派发）：G0 局部 + G1 必需 + G2 必需；**判据与 round0 完全相同**：同一最终实现 DB setup≥0、hold≥0、TNS=0、实际时钟/引脚/约束覆盖、本次跨域/复位审阅、资源≤器件、唯一 bit 与同次 DB/报告同源；含 CWC 才做 CWC 检查。
- G3/G4/G5 事前不适用（纯后端候选，不声称 DMA 实收/板测/发布）。
- 本轮复测范围（派发）：G2 STA 绑定、入口/重建证据与我 r0 两项发现的清除、约束未放宽、manifest/selfcheck/绑定、薄余量与死代码登记的充分性。

## 2. 冻结输入核对（格式/入口/哈希）

1. **manifest 自检与我的独立复算**：manifest 内 `manifest-selfcheck.json` = `{entries: 232, mismatches: []}`；我按 `path_base` 规则（production/scripts/tests → 项目根；rk_patch/build_artifacts → run 目录）独立复算 **240→232 条**：`TOTAL=232 OK=232 MISSING=0 MISMATCH=0 SIZE_MISMATCH=0`。
2. **格式改进落实**：新增 `path_base`（逐组说明基准）与 `volatile_excluded`（名字+patterns+理由），正是 r0 报告 §2/§5 提出的两项；`notes` 记录 round1/round2 变更摘要。
3. **候选树覆盖**：`fpga/csi2/pcie_integration/` 排除 `sim/`、`peer-ref-2a4b253/`、`README.md` 后 **153 文件 = manifest 153**（无遗漏/无多余）；`sim/` 8 文件 = 全部 test_inputs；`tools/pcie_integration/` 8 文件 = 全部 build_scripts。
4. **来源可核对**：`source-provenance.json` 161 条 = 142 peer_unchanged + 7 modified_by_t07（`ui_cfg_imx415 / cam_ddr_writer / ddr_frame_pusher / ep_bar_win / img_frame_src / pcie_ep_engine / ph1p_pcie_ep_top`）+ 1 local_copy_modified（`csi_rx_packet_integrity.v`，round2）+ 1 local_copy_unchanged（`csi_rx_10bit_unpack_checked.v`）+ 10 new（含 `crc16_upd4.v`、`tb_csi_integrity_diff.v`、`csi_rx_packet_integrity_ref.v`），与 round1/round2 声明的变更集一致。
5. **与 r0 的哈希交叉核对（我 r0 记录值的复算）**：相对 r0，生产侧变化恰为 `cam_ddr_writer.v`（round1 F2 修复）、`ddr_frame_pusher.v` + `ph1p_pcie_ep_top.v`（round1 F1 修复）、`csi_rx_packet_integrity.v`（round2 重构）+ 新增 `crc16_upd4.v`；`mipi_csi2_rx_ph1p_checked.v`、`ep_bar_win.v`、`img_frame_src.v`、`pcie_ep_engine.v`、`csi_rx_10bit_unpack_checked.v`、`.sdc/.adc` 与 r0 **相同**；工具侧 `run_sim.ps1`/`run_td.ps1`/`td/*.tcl` 与 r0 **相同**，仅 `gen_manifest.py` 变化（声明内）。
6. **只读原源未被改动**：`fpga/csi2/src/csi/csi_rx_packet_integrity.v` 现 SHA=`9e46297e4e1bfee5462657112544f509fe2eec83644edf5d07aedc4df990ac08`，与 r0 时其副本哈希相同 ⇒ 原源未被动过；`sim/tb/csi_rx_packet_integrity_ref.v` 与其的差异仅 14 行（文件头注释 + module 名加 `_ref`），确认是「重命名副本」。
7. **复核限制（如实登记）**：round1 的 manifest 已被 round2 覆盖，无法直接 diff r1→r2；对「round2 只动了声明文件」的判断依据是 r2 manifest + provenance + 构建日志 + r0 哈希交叉核对（一致性无矛盾）。

## 3. r0 两项独立发现的复验（都按新 manifest）

### 3.1 r0 §4（编译阻塞 + 证据过期）——已清除
- **冻结 RTL 编译**：`cam_ddr_writer.v` 现只保留一处 `reg p_skip_frm`（r0 的 405/536 双声明已消除）；默认入口（`sim/compile_checked.f`，无 suppress）下 **五个 TB 的 `vlog.log` 均 `Errors: 0, Warnings: 1`**。
- **运行**：五个 TB 全部 `ALL PASS`：
  - `tb_csi_integrity_diff`（新差分 oracle）：`payload beats compared = 680, payload mismatches = 0` + `ALL PASS (payload cycle-exact; abort/counters <=2 cycle lag checked)`；
  - `tb_csi_checked`、`tb_ddr_frame_pusher_rka1`（`20387 TLPs total, 20453 accepted beats`）、`tb_ep_bar_win_rka1`、`tb_ddr_wr_arb` 均 `ALL PASS`。
- **证据时间绑定**：开发 r2 证据（`backend/g1/msim/r2_*`）mtime 05:54:05–05:54:39，全部晚于 RTL 末次修改 05:50:06；我自己的重跑证据 mtime 06:18:40–06:19:12。
- **我如何复跑（重要，见 F1）**：直接用文档命令 `powershell -ExecutionPolicy Bypass -File tools\pcie_integration\run_sim.ps1 …` 在本机 PowerShell 5.1 下会先被 F1 卡住；我改用「把冻结脚本内容按 UTF-8 读出后以 scriptblock 执行（脚本哈希复核=33399210…，`-Root` 显式传入）」完成上述五次运行，**未修改脚本字节**。开发自己的 r2 `commands.log` 显示其会话里默认入口跑完整条链（`cmd /c vsim` + `vsim exit=0`）。

### 3.2 r0 §5（manifest 冻结后 commands.log 漂移）——已清除
- `volatile_excluded` 明确把 `commands.log`、`td_*.log`、`*.logw`、`abs.f`、`run.do`、`vsim_stdout.log` 排除出冻结清单并写明理由（round0 F3 实测）；候选身份由 bit/DB/报告/稳定日志承担。
- 我逐条复算 232/232 全匹配；对 `fpga/csi2/pcie_integration/`、`tools/pcie_integration/`、`backend/candidate/`、`backend/g1/`、`backend/g2/` 全树扫描「mtime > manifest 生成时刻（06:04:56）」的文件：**只有 `backend/g2/README.md`（06:06:14，文档索引文件，不是 manifest 条目）**，即 manifest 覆盖的产物无任何冻结后写入。

## 4. G2 复核（同一最终实现 DB，逐项实读）

| 证据 | 内容 |
|---|---|
| `phy_1/final_timing.rpt`（`ada43e46…`，5,392,168 B，06:03:23） | `Generated Sat Oct 17 06:03:23 2026`；Top `ph1p_pcie_ep_top`；Device `PH1P100SBG484`；Speed 3；**Confidence: Routed**；Check Corner: Both (Slow and Fast)；**CRPR Enabled: Yes**；Constraint File = `…/constraints/ph1p_pcie_case_ep.sdc`；STA coverage 95.40% |
| 全局 Timing Status | **SWNS +0.107 ns / STNS 0.000 ns**；HWNS +0.020 ns / HTNS 0.000 ns；全文 62 条统计行**全部 0 违例端点**（r0 为 159） |
| 分域 SWNS | clk0 `usr_clk` **+0.481**、clk1 `tl_clk_user` **+0.540**、**clk2 `cam_a_byte_clk` +0.107**、**clk3 `cam_b_byte_clk` +0.130**、clk4 mcu_clk +11.713，其余 0.000；无负值 |
| 最差路径（cam_a 组，1829 端点） | `u_csi_a/u_gear_box/r_byte_buffer_reg[55]_syn_2.clk → u_csi_a/u_integrity/O_bad_frames_reg[30]_syn_2.cea`，Budget 5.332 ns，**Data Path 4.982 ns（cell 2.293 ns 46% / net 2.689 ns 54%）**，Logic Level 6（LUT5=3/LUT4=2/LUT3=1），Skew 0.129 ns，Uncertainty 0.050 ns；hold：clk2 **+0.032** / clk3 **+0.020**，均 0 违例 |
| `route_flow.status` / `place_flow.status` / `syn_1/flow.status` | final：Setup WNS **+107ps** TNS 0 FEPS **0**，Hold **+20ps** TNS 0；manhattan：+725ps/0；basic：+101ps/0 |
| `phy_1/run.log`（`bad1f0ad…`） | `Timing Mode: final` → `Setup: WNS 107ps TNS 0ps NUM_FEPS 0`；`Hold: WNS 20ps TNS 0ps NUM_FEPS 0`（同值出现于 1884/1980 两处报告阶段） |
| `phy_1/ph1p_pcie_integration_phy.area` | 见 §0 资源行（逐项实读，与派发数字一致） |
| round2 会话 | `td_20261017_055458.log`（06:03:43）：`PRJ-1406 Run syn_1 finished`、`PRJ-1406 Run phy_1 finished`、`PRJ-1424 … saved as best result`、`T07_ALL_DONE`；`commands.log` 该次 `stage=00_all exit=0`；round2 只有这一次 00_all（派发允许的第 2 次未使用，与「第 1 次达标」一致）。会话内 `USR-8122 Design is unavailable` / `USR-8001 Cannot find top model` 出现在 wrapper 的 `report_area/report_timing` 尝试上，不影响 run 自身产物（最终报告由 `phy_1` 生成） |

**结论**：判据「同一最终 DB：setup ≥ 0、hold ≥ 0、TNS = 0」在新 manifest 下**成立**；负裕量 round0/round1 留痕仍在（对照见 `g2/README.md` §3.1/§3.2），未被覆盖。

## 5. 约束/CDC/接口未被放宽

- `.sdc`/`.adc` 与 r0 逐字节相同（`3f999c44…`/`67831295…`）；`set_multicycle_path`/`set_false_path`/`set_max_delay` 出现次数 **0**；`create_clock cam_a/b_clk_lane 1.333 ns` + `create_generated_clock … -divide_by 4` = 187.5 MHz / 5.332 ns 前提原样；`set_clock_groups -asynchronous` 四组声明原样。
- round2 修改的 `csi_rx_packet_integrity.v`：**模块端口/参数块与只读原源逐字相同**（归一化比对，含 14 项端口）；`mipi_csi2_rx_ph1p_checked.v`（wrapper）与 r0 相同 ⇒ 对外接口/顶层连线未变；TD 综合无端口/连接错误，顶层精化正常。
- `chk.timing`（新）逐项：`no clock(2)`（`pcie_pll_locked`、`tl_clk_user_ce_n`，数据/使能类网）、`local clock 3`（cam_a/cam_b 字节时钟 + sys_clk，IP/PHY 生成、SDC 已覆盖）、`no input delay 73` / `no output delay 87`（MIPI/DDR/PCIe 源同步或串行 CDR 由 PHY/IP sdc 管住，其余慢速 IO）、`invalid/no-path/comb-loop/shadowed = 0`、dangling node 2。分类与 r0 完全一致（约束未动，理应如此），g2/README §5 已逐项解释。
- 异步域因此不做跨域 STA 的设计原样（SDC 注释 + change-report §3 机制表）；新增重构仅在本域组合逻辑内，未引入新的跨域路径（差分 TB 逐拍等价 + 顶层/接口未变为其旁证）。

## 6. 候选绑定与 bit 身份

- 唯一 bit：`phy_1/ph1p_pcie_integration.bit` = `best_result/…bit` = `0943cb36feeb873decc6ea5aae1c2777b3ab4881ebe2954b43bee040ceb38b0a`（5,224,023 B）；候选树内无第二个 bit。
- 同次实现：`place.db` 06:01:54（`510b5187…`）、`pr.db` 06:03:35（`692791c6…`）、`final_timing.rpt` 06:03:23、`bit` 06:03:42、`run.log` 06:03:43 —— 全部落在同一个 round2 `phy_1` run（05:57 启动）内，无跨 run 拼接。
- CWC：候选无 CWC 生成物（对照 source-provenance 可核）⇒ not_applicable（同 r0 理由）。
- 板测层：本包未下载/未写 Flash/未连 RK；G3–G5 不适用；回退仍是「换掉两个新目录 / 继续用 002820 既有 bit」。

## 7. 薄余量与 END_PACKET 死代码登记的充分性评估

1. **薄余量**：实测全局 WNS 就是 cam_a 的 **+0.107 ns**（budget 5.332 的 2.0%），其中 **54% 是 net delay**，且该域跨两片 CSI + 两片 writer。开发在 `g2/README.md` §3.6 与 `change-report.md` §8.5 明确写出「余量薄、不再做 ECO/重综合以保持源↔位流绑定、后续任何改动把该域 setup≥0 当回归门槛」；指南只要求「报告实际 margin、不声称达到旧 0.300 ns 优化目标」——开发未声称 0.300 ns，登记充分。
2. **END_PACKET 死代码**：冻结 `csi_rx_packet_integrity.v` 确有**两处 `END_PACKET:` case 标签**（第 165 行有效块、第 176 行不可达）；`final_timing.rpt` 中出现 `u_csi_a/u_integrity/crc_bad_q_reg_syn_478` 等 39 处 `crc_bad_q` 端点，说明 TD 保留的是**首项（生效）**逻辑；ModelSim 0 错、五个 TB（含差分）全 PASS。开发在 §8.5 如实登记「保留 + 不因此改源/重综合」的理由（Verilog 首项命中、改它要换 bit），**充分**。
3. **附带发现（F3）**：该文件头部注释第 18 行仍写「③ …移到包尾的后一拍（**新状态 END_PEND**）」，而实际实现已改回「既有 END_PACKET 第一拍」（无 END_PEND 状态）。注释描述的是被差分 oracle 否决的早期方案，属陈旧注释；已登记的死代码条目未覆盖这句注释，建议随下次触碰修正（不影响功能/时序）。

## 8. 发现（F1–F4，均为工具/文档层；不改变本维度判定）

**F1（工具/入口健壮性，中等，建议下次触碰时做 tool-only 修复）**：两个冻结 runner 均为 **UTF-8 无 BOM + 仅 LF + 含中文注释**；在本机默认宿主（Windows PowerShell 5.1，ACP=936）下按 ANSI 解码时会吞掉中文注释行内 8（sim）/5（td）个换行，导致**各有一条功能语句被并进注释**：
- `run_sim.ps1`（`33399210…`，144 行→PS 视图 136 行）：raw L123 `$doPath = Join-Path $outDirF "run.do"` 并入 PS 视图 L115 的注释 → `$doPath` 未定义 → `[System.IO.File]::WriteAllLines` 抛 `Empty path name is not legal`，脚本在 vsim 前中止。我在本机复现 3 次（直接 `-File` 两次、`cmd /c "chcp 65001 & powershell -File"` 一次），证据 `test-reports/eng-repro-r2/_diag/{out_probe.txt, psview.txt}`（`vlog exit=0` 但无 `vsim` 行）。
- `run_td.ps1`（`760c5524…`，81 行→PS 视图 76 行）：raw L58 `$tclDst = Join-Path $outDirF ($Stage + ".tcl")` 被并入 PS 视图 L53 的注释（`_diag/psview_td.txt`）→ `$tclDst` 未定义，后续使用会失败/写错位置。本包未执行 TD（遵守不重跑活动工程），该条为**静态解析证据**（Get-Content/AST 行视图 + 逐语句定位），未做端到端复现。
- 对照：开发自己的 r2 证据显示默认入口在其会话里跑完整条链（`cmd /c vsim` + `vsim exit=0`、`td_00_all.log` 有 `PRJ-1406/PRJ-1424/T07_ALL_DONE`），且该脚本字节自 round0 起未变（哈希与 r0 manifest 相同）⇒ 这是**宿主上下文相关的健壮性缺陷**（同一字节在不同调用上下文里解析结果不同），不是本轮回归。
- 建议（不触碰 RTL/bit）：把两个 `.ps1` 另存为 **UTF-8 with BOM 或 CRLF 或纯 ASCII 注释**；修好后重新冻结 manifest（只需重算 build_scripts），**无需重出 bit/G2**；在修复前的文档里写明「请用 UTF-8 解码宿主或在 ASCII 路径/UTF-8 宿主下运行」。我已完成的最坏情况替代路径：用「UTF-8 显式解码后执行冻结脚本内容」跑完五个 TB，结果与开发证据一致。

**F2（文档准确性，次要）**：`g2/README.md` §3.5 对比表与 §5、`change-report.md` §8.4 表把 `TMST-7700 SEVERE（post-route）`记为 **0**（“round2 达标后消失”）；但冻结 `phy_1/run.log` 仍为 **5 SEVERE**（L1796，与 round0 相同的 2 无根时钟网 + 3 local clock 项；place 阶段 2 SEVERE @L1104）。该 5 项本身已在 g2 §5 逐项解释、且与 setup 达标不矛盾（它们不是 setup 违例）；需把「0」更正为「5（与 r0 同类且已逐项解释）」，否则与冻结日志冲突。

**F3（RTL 注释陈旧，次要）**：见 §7.3（`END_PEND` 注释）。

**F4（证据归属，登记即可）**：`backend/g1/crc16_upd4.generated.v`（28 行）不是冻结生产文件（`rtl/checked/crc16_upd4.v`，101 行）的副本，而是**单变体中间产物**；冻结生产文件已可由冻结生成器逐字节复现（我用 `gen_crc16_flat.py --out` 重生成，SHA 均为 `20520d044773247bdd6469c3fd04efcf1ea4c31366abf41f7fde3ea27e98841f`，8905 B；脚本自检 4×20030 例 0 失配）⇒ 无需动作，仅避免误读。

## 9. 我实际执行的命令与证据清单

实际执行（全部只读冻结输入；写入仅 `test-reports/eng-repro-r2/**`）：
1. Python 3.11.5 复算：manifest 232 条哈希+size（`TOTAL=232 OK=232 MISMATCH=0`）、生产树/测试树覆盖差集、provenance 直方图、r0↔r2 哈希交叉核对、冻结后写入扫描、flow.status/run.log/area/报告数字提取、`csi_rx_packet_integrity.v` 与只读原源 diff（14 行头/改名）、端口块归一化比对（相同）、ref 副本核对、`crc16_upd4.v` 重生成比对（IDENTICAL）。
2. ModelSim 10.5b 独立重跑五个 TB（经 `_diag/run_frozen_sim.ps1`：UTF-8 读冻结脚本 → `scriptblock` 执行 → `-Root` 显式传入；脚本哈希打印并复核 `33399210…`）：`vlog exit=0`/`Errors: 0`、`vsim exit=0`、全部 `ALL PASS`。证据：`test-reports/eng-repro-r2/<tb>/{vlog.log, vsim.log, commands.log, run.do}`（run.do 19 B，与开发证据一致；例如差分 TB `vlog.log`=5291eb71…、`vsim.log`=6d9dbdae…；pusher `vlog.log`=372a5007…、`vsim.log`=840bda34…）。
3. F1 复现与定位：直接入口运行（2 次失败 + 1 次 `chcp 65001` 失败）、`_diag/{out_probe.txt, psview.txt, psview_td.txt, parsediag.txt, lineview.txt}`（PS 视图行数 136/76、被吞语句逐条定位）。
4. CRC 生成器：`python tools/pcie_integration/gen_crc16_flat.py --selfcheck-only`（4×20030/0）与 `--out test-reports/eng-repro-r2/_diag/crc16_upd4.regen.v`（与冻结文件逐字节相同）。

**未执行（明确记录）**：未重跑 TD（判据以同一冻结 DB 的既有报告为准，避免覆盖活动工程候选）；未修改/重编码任何冻结脚本（F1 走显式 UTF-8 解码执行内容）；未做任何硬件操作；未触及 CWC（N/A）。

**对特定项的复核限制**：`STA coverage 95.40%` 的精确语义在 TD 文档/交付物中仍无定义（g2 §5 给了开发侧解释「约 4.6% 主要是异步域内部与无 delay 慢速 IO」）；r1 manifest 已被覆盖，r1→r2 逐文件 diff 不可直接核对（以 r0 哈希交叉 + provenance + 构建日志替代）。

## 10. 复测影响与证据复用（供原规划/其他维度）

- `input_status`：changed（本轮已按新 manifest `CDE55FC8…` 复测；我的 r2 证据全部绑定该 manifest）。
- **engineering**：本轮 **PASS**；若规划安排 F1/F2/F3 的 tool/doc-only 修复（预期只改 `tools/pcie_integration/*.ps1` 编码与 `backend/g2/README.md` 等文档，不触碰 RTL/约束/bit），**建议不需要重出 G2**：生产输入/构建产物哈希不变时可复用本报告结论，仅需对改动文件本身做一次增补核对与（如重冻 manifest）重新绑定。
- **functional**：必须绑定新 manifest（本报告 §3 的编译/TB 结论可直接引用；差分 oracle 与五个 TB 的证据已由我独立复现）。
- **system**：复测前按其自身规则更新探针（`change-report.md` §7.2：pusher `rel_tgl2/3` + 参数 `BASE0B/BASE1B`），并绑定新 bit `0943CB36…8B0A`。
- 回退：不改任何现有产物；如需回退仍按「整目录替换 / 选回 002820 bit」。

### 本报告结论

在 round2 冻结输入（schema2/round2，`CDE55FC8…`）上：G2 同一最终实现 DB 达标（setup +0.107 ns / TNS 0 / 0 违例端点、hold +0.020 ns、Routed/双角/CRPR、资源在器件内）、位流与同次 DB/报告同源且唯一、约束与判据未被放宽、manifest/自检/来源与冻结完整性成立、r0 两项独立发现均已清除；薄余量与死代码已如实登记。**engineering 维度：PASS**（F1 工具健壮性、F2/F3 文档准确性作为缺陷登记，交原开发/原规划决定何时做 tool/doc-only 修复）。
