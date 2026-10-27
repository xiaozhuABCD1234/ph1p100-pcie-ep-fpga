# INT.P4 结果（r2，round2 修复后开发自检）

判定：**ready_for_test**（同一候选功能回归与交付一致性通过；TD 综合已完成但 187.5MHz setup **未收敛**，
G2 按门槛判 **未通过**；route/bit/CWC/download/Flash 均未做）。本文件不是综合测试结论。
本轮 r2 为实际修复第 2 轮（round0 FAIL → round1 FAIL → round2），TD synth 额度 3/3 全部用尽，不再有第 4 次。

## 1. 本轮修复点（对应 r1 失败报告 E1–E4 / D5a–D5e）

| r1 失败项 | r2 处理 | 证据 / 结果 |
|---|---|---|
| **E1 G2 setup 未收敛**（330 端点、WNS −1.549 / TNS −271.427；最差路径 `u_obuf_gau/count_reg[0]`→`u_front/u_row/rb0_reg[0].d`） | 在 `fpga/csi2/src/integrated_delivery/` 下新增**仅时序**派生变体并插入寄存器 ready 边界；`fpga/csi2/src/img/**`、b20、upstream 一律未改：<br>① `bayer_raw10_demosaic4_p4.v`：模块输出改为 2 拍弹性级（`int_p4_elastic_beats`），`pipe_en` 只依赖本模块 count 寄存器，不再依赖 `m_ready`；② `img_algo_parallel_top_p4.v`：实例化 ①，并在 4 路 `rgb8_gray_stream` 与 3 个输出消费者之间加 2 拍弹性级 B（对灰度流呈现寄存器 ready）；③ `integrated_input_processing_top.v`：算法支路前加 2 拍弹性级（捕获/准入逻辑不再组合直达 P1 行缓冲 accept 路径），r1 的双消费者"恰好一次"握手规则不变 | r2 三次综合：330 → 277 → **112** 端点；WNS −1.549 → −1.483 → **−0.637**；TNS −271.427 → −255.655 → **−69.776**；最差路径已不在 ready 链，落到 `u_obuf_gau/count_reg[0]`→`u_gau/u_row/rb0_reg[0].d`（`algo_rowwin3` 行缓冲读使能/地址：5.906ns，net 3.602，fanout 256）。**未达 0 违例 → G2 FAIL** |
| **E2 综合 harness 未驱动 DDR 从口 / 层次不可见** | `tools/integrated_delivery/synth/integrated_delivery_synth_wrap.v`：补 `ddr_awready/ddr_wready/ddr_arready/ddr_rvalid/ddr_rdata` 行为 DDR 从模型（单 outstanding 读、写立即握手），并在文件头写明覆盖边界；另把 A/B 捕获产生器改为**寄存器输出 beat**（真实捕获源形态） | r2 run2 `run.log` 无 `HDL-5314`、无 `SYN-5013 Undriven`；面积层次表出现 `u_arb`(a1_ddr_arb2, 5 LUT)、`u_egress`(aplus_pcie_egress_adapter, 129 LUT/33 ripple/115 reg)、`u_store`(a1_ddr_slot_store, 355 LUT/724 reg)。覆盖边界写清：仅内部寄存器 STA、IO 未约束、harness 不是板级顶层、不伪造 ADC/引脚、无 false_path/multicycle、单一 5.333ns 时钟 |
| **E3 tcl 用打印行数当端点数（10 vs 330）** | `td/01_synth.tcl` 改为从 `flow.status` 取真实 `NUM_FEPS`（并用 report 头部 `Viol Endpoints` 交叉核对），打印 `INT_SYN_VIOL_ENDPOINTS`/`INT_SYN_VIOL_ENDPOINTS_FLOWSTATUS`/`INT_SYN_TOTAL_ENDPOINTS`；打印路径数改名 `INT_SYN_PRINTED_PATHS` 且注明不是端点计数 | r2 输出 `INT_SYN_VIOL_ENDPOINTS=112 ... FLOWSTATUS=112 ... TOTAL=16770`，`PRINTED_PATHS=10` |
| **E4 / D5d 10 个 img 源未绑定** | manifest 新增 `img_sources`（10 个文件逐一 SHA256+size）、`source_variant_bases`（基础文件哈希+派生 diff） | `INT.P4-r2-manifest.json` |
| **D5a 端点计数错误** | 330（r1）与 112（r2）真实端点写入 manifest `endpoint_counts`、本文件、build-entry、shortest-steps | 同上 |
| **D5b 遗留文件被说成"删除"** | 改为"**已登记、未删除**"（`legacy_untracked` + 说明） | manifest `legacy_untracked` |
| **D5c img 数量 9→10** | build-entry 改为 10 个 img 源（algo_obuf、algo_rowwin3、algo_rowwin_reader、bayer_raw10_demosaic4、gray8_gaussian3x3_frame、gray8_gaussian3x3_stream、gray8_he_cdfmin_frame、img_algo_parallel_top、img_algo_top_g2、rgb8_gray_stream） | build-entry §2 |
| **D5e 候选 `work/` 未登记** | `legacy_dirs` 登记 `fpga/csi2/src/integrated_delivery/work/`（6 文件逐个哈希，旧 ModelSim 库，不删） | manifest `legacy_dirs` |
| 编译文件绑定 | manifest `new_files` 绑定实际编译的派生变体、TB（含新等价 TB）、harness、tcl/sdc、样例；候选 TB 也纳入绑定 | manifest `new_files` |

**派生变体等价证据**（G1 要求）：新 TB `fpga/csi2/src/integrated_delivery/tb_img_algo_equiv_p4.v`
三实例对照——dut0=`img_algo_parallel_top`（基础）、dut1=`img_algo_parallel_top_p4`（派生）、
dut2=基础（不同 ready 序列，对照）。同激励（64×48，两好帧 + 一帧 beat200 abort，768/768/201 拍）：
`y8/gau/he` 三流逐 token 比较（data+sof/eol/eof+abort 标记+帧/HE 状态计数）。
`+SEEDMODE=0/1/2` 三组 ready 形态（75% 随机、另一随机组、常 ready）全部 `CHECK_REF_NEW PASS`
（每流 1720/1703/1720 token 完全一致）。日志 `INT.P4/regression/equiv_seedmode{0,1,2}.log`。

**同时暴露的既有差距（不是本轮引入，如实记录）**：对照 `CONTROL_REF_REF2`（**同一份基础 RTL**、仅输出
ready 序列不同）在 3 组种子下分别出现 98/99/48 处差异，全部在 HE（stream 2）。说明
`fpga/csi2/src/img/gray8_he_cdfmin_frame.v` 的直方图/映射对**停顿形态**敏感（既有性质，本轮
`img/**` 只读，未修）。因此"语义不变"只在**同激励 + 同输出 ready 形态**下被证明；任意背压下的 HE
像素内容在基础 RTL 里本来就不唯一。此项交原规划/后续任务，不在此声称已解决。

## 2. 已接通（同一候选、单 clk、5.333ns）

捕获 A/B（harness/真实 TB 驱动）→ P1 输入处理（packed RAW10 + 三算法/旁路选路；r2 新增算法支路
2 拍弹性级）→ b20 r0 A+ 核 → A+ 槽存储 → DDR 仲裁 → P2 egress adapter → PCIe 描述符面；
P3 调度器提供 A/B 身份、`a_enable` 门控、B 优先/轮转、全字段 release；host ACK → slot_release →
drain → release 闭环。单 `clk`/`rst_n` 域，无 CDC/异步 FIFO、无时钟改动。

## 3. 同会话回归（同一冻结候选，64×48 缩尺）

| 项 | 结果 | 日志 |
|---|---|---|
| 开发 TB `MODE=4` 默认（SAMPLE=1） | `TB_INTEGRATED_DELIVERY_TOP PASS` | `integrated_mode4.log` |
| 开发 TB `MODE=4` `+EXTRA=1`（T1–T6） | PASS，**65 ok / 0 fail**；T1 `m_beats=768 sof=1 eol=48 eof=1` | `integrated_mode4_extra.log` |
| 开发 TB `MODE=1` 默认（SAMPLE=1） | PASS | `integrated_mode1.log` |
| 开发 TB `MODE=1` `+EXTRA=1`（T1–T6） | PASS，**65 ok / 0 fail**；T1 `m_beats=768 sof=1 eol=48 eof=1` | `integrated_mode1_extra.log` |
| 派生变体等价（`+SEEDMODE=0/1/2`） | 三次 `CHECK_REF_NEW PASS` / `TB_IMG_ALGO_EQUIV_P4 PASS`；对照差异 98/99/48（既有 HE 停顿敏感） | `equiv_seedmode{0,1,2}.log` |
| P1/P2/P3 既有 TB | `TB_RAW10_PACK PASS`、`TB_APLUS_PCIE_EGRESS_ADAPTER PASS`、`TB_DUAL_CHANNEL_CAPTURE_SCHEDULER PASS` | `p1_tb_raw10_packer.log`、`p2_tb_egress.log`、`p3_tb_scheduler.log` |
| P1/P2/P3 Python 工具 | `RAW10_PACK PASS`、`INT.P1_VERIFY PASS`、`DUAL_CHANNEL_SCHEDULE PASS`、`A1U1_DECODE OK`、`VERIFY_INTEGRATED_SAMPLE PASS` | `py_*.log` |
| mode1/mode4 样例哈希 = r1 冻结样例 | `.a1u1` `79e35f28…`、`.raw` `1357408f…`、`.json` `76d88910…`（两者逐字节相同） | `Get-FileHash` 记录在 §5 |
| P1 冻结工具证据 | 重跑后 `golden_input_processing.json`=`2c420c86…`、`verify_report.json`=`7e257d07…`，与冻结值逐字节相同 | `py_verify_input_processing.log` |

## 4. TD 综合（G2：已完成，未通过；额度 3/3 用尽）

工程只在 `workflow/runs/<run>/INT.P4/td/`；`D:/TD/**`、b18/b19/b20 目录与计数未动；无 bitgen/CWC/下载/Flash。

| 项 | r2 run2（绑定为 G2 证据） | 门槛 | 判定 |
|---|---|---|---|
| 综合完成 | `INT_SYN_RUN_COMPLETE`，无 SYN-8228 | 必做 | 完成 |
| **setup 端点** | **112 Viol Endpoints / 16770 Total**（flow.status `NUM_FEPS 112`，报告头部一致） | 0 | **未通过** |
| setup WNS/TNS | **−0.637ns / −69.776ns** | ≥0 | **未通过** |
| hold | HWNS/HTNS 0.000 / 0，0 端点 | ≥0 | 通过 |
| IO | 42 / 286 | ≤286 | 通过（仅 harness IO；IO 时序未约束 = gap） |
| ERAM + CWC | 39 + 0 | ≤300 | 通过 |
| 资源 | reg 5832、slice* 10761/71680、lut 13009、dsp 14、pll 0 | 器件内 | 通过 |
| 未驱动 DUT 输入 | 无 `HDL-5314`、无 `SYN-5013 Undriven` | 无 | 通过 |
| 层次可见性 | `u_arb`/`u_egress`/`u_store` 均有独立行 | 可核对 | 通过 |
| STA coverage | 95.76% | 记录 | 有 4.24% 未覆盖；IO 时序未约束 |
| route / bitgen / CWC / download / Flash | 0 / 0 / 0 / 0 / 0 | 0（route 条件） | not_run（G2 未通过） |

- 最差路径（run2，报告原文）：Begin `u_dut/u_p1/u_algo/u_obuf_gau/count_reg[0]` → End
  `u_dut/u_p1/u_algo/u_gau/u_row/rb0_reg[0].d`；`Data Path Delay 5.906ns (cell 2.304 / net 3.602)`，
  7 级逻辑，max fanout 256。链路：`algo_obuf.count` → `gray8_gaussian3x3_stream.pipe_en`(fo199)
  → `algo_rowwin3.evt_en`(fo155) → `ra0`(fo256) → DRAM 读 → relut6/f7mux → `rb0_reg.d`。
  即**行缓冲读使能/地址**在同一个 5.333ns 周期内要穿越 2 个高扇出使能网络 + 320 深分布式 RAM 读
  mux；这段在 `fpga/csi2/src/img/algo_rowwin3.v` 内，本轮只读，无法从集成层消掉。
- 三次综合（`INT.P4/td/syn_r2_run{1,2,3}/` 各存 flow.status/run.log/gate.qor/报告）：
  run1 277 端点 WNS −1.483（最差路径起点在 harness 捕获产生器）；run2 **112 端点 WNS −0.637**
  （harness 捕获改寄存器输出 + P1 输入弹性级后，绑定为 G2 证据）；run3 112 端点 WNS −0.637
  （ERAM 行缓冲实验：TD 未接受 `(* ram_style="bram" *)`，netlist 与 run2 逐项相同）。
  **额度 6/6 终身、round2 3/3 用尽，无第 4 次、未自扩额度。**
- r1 证据已保存在 `INT.P4/td/r1-evidence/`（syn_gate_*、flow.status、run.log、gate.qor、console 日志），
  不与 r2 结果拼接。

## 5. 样例哈希（r2 重跑，mode4/mode1 相同）

```
79E35F28D465D6F3CEC6787416F332D8B717F87FA34FA29EEB74CB2E5EAD04F6  integrated_sample.a1u1
1357408F05E25A42DEBFDA726554FA9F66EE6380A0B1EA514DDC0A942AC1564D  integrated_sample.raw
76D88910EFCE37C2692EA7468D17BB9A7ED887758C8A9607E8596E3CF680C236  integrated_sample.json
```
与 r1 冻结样例完全一致（未改样例内容）。

## 6. 未通过 / 阻塞 / 差距（如实）

- **G2 setup 未收敛**：112 端点、WNS −0.637 / TNS −69.776。剩余违例全部落在 `algo_rowwin3` 行缓冲
  读路径（`u_front`、`u_gau` 各一份）。要真正收敛必须改 `fpga/csi2/src/img/algo_rowwin3.v` 的
  读调度/存储形态（本轮禁改），或降低 P1 时钟（需授权），或调整 STA 约束（不允许）。已用尽
  round2 synth 额度，不再尝试。
  - 已评估但**未采用**的路线：把三块行缓冲改成 ERAM 使读路径止于 ERAM 地址输入。实际综合显示 TD
    不识别 `(* ram_style="bram" *)` 的该形态（读寄存器带异步复位），netlist 未变；实验文件已移出
    候选目录并登记，未编译。
- **既有 HE 停顿敏感性**：见 §1 末，`CONTROL_REF_REF2` 对照（同一 RTL、不同 ready）有 48–99 处差异；
  本轮只读该模块，未修，作为差距交后续。
- **IO 时序未约束**：综合 harness 无封装引脚映射，STA 只覆盖内部路径；板级 IO/ADC 未验证。
- **route / bit / CWC / download / Flash**：not_run（G2 未通过；无板级集成顶层与 ADC，不伪造）。
- **G3/G4**：not_run + awaiting_hardware（无 bit/板窗；流水深度 1 帧、长稳/吞吐后置）。
- **真实 PCIe/RK 传输**：未做，仍待联调；样例仅为 RTL 仿真字节。
- **A 路**：按 `a_enable` 门控，仿真可达，A 路上板/真实相机未验。
- **覆盖差距**：仅 64×48 缩尺（1920×1080 未仿真）；Y8/高斯/HE 内容只做结构+marker+等价对照，
  未做逐像素算法模型核对；高斯 3×3 边界未逐像素核对。
- **背压模型**：每通道无捕获暂存，非授予通道 `s_ready=0`；真实自由运行双相机需补暂存（未实现）。
- **测试框架 vs 板级**：`integrated_delivery_synth_wrap.v` 只是综合手段，不是板级顶层。
- **blocked**：`[]`（无外部设备/权限阻塞；G2 是设计/门槛失败不是 blocked；额度已按规划用尽）。

## 7. 回退入口

- r2 相对 r1 只改/新增这些文件：新增 `bayer_raw10_demosaic4_p4.v`、`img_algo_parallel_top_p4.v`、
  `tb_img_algo_equiv_p4.v`；改 `integrated_input_processing_top.v`（P1 新版本，delta 见 manifest
  `source_version_overrides`）；改 `tools/integrated_delivery/{run_integrated_sim.ps1,td/01_synth.tcl,
  gen_manifest_intp4.py,synth/integrated_delivery_synth_wrap.v}`；文档与 manifest/证据。
- `fpga/csi2/src/img/**`、b20 四文件、upstream、`pcie_integration/**`、`tools/td/**` 未改（哈希见 manifest）。
- 回退到 r1：恢复 `integrated_input_processing_top.v` 到 `8cd7d35b…`、删去两个派生变体与其引用、
  恢复 r1 的 ps1/01_synth.tcl；r1 证据与 manifest 仍完整（`INT.P4/td/r1-evidence/`）。

## 8. 复测清单（交同一综合测试者，round2）

- 必须维度：functional / engineering / system（同一综合测试者，`dimension=integrated`）。
- 必须检查：
  1. manifest `INT.P4-r2-manifest.json` 全量哈希复核（P1/P2/P3 声明、A1 只读 4 文件、**10 个 img 源**、
     派生变体、TB、harness、tcl/sdc、docs、TD 证据），`stopped_modifying=true`、`drift_count=0`；
  2. 独立重跑 S1–S5（重点 S5 反压：不得死锁、不得提交损坏帧）+ 至少一项测试者自有判据；
  3. 开发 TB 默认与 `+EXTRA=1`（MODE=4 与 MODE=1，T1–T6 真实执行）；T6 变异负对照仍有效；
  4. P1/P2/P3 TB 与 Python 工具复跑；A1U1 解码 + 负对照；mode1/mode4 样例哈希 = r1 冻结值；
  5. 派生变体等价证据复核（`equiv_seedmode{0,1,2}.log`，`CHECK_REF_NEW PASS`）；如只复用同哈希日志，
     须绑定新 manifest；
  6. TD：`flow.status` 的 `NUM_FEPS=112`、WNS −0.637ns、TNS −69.776ns、hold 0、IO 42、ERAM+CWC 39、
     资源、无未驱动告警、`u_arb/u_egress/u_store` 层次可见；route/bitgen/CWC/download/Flash=0；
     G2 必须判 **未通过**（不得因端点数下降就放宽）；
  7. D5a–D5e 复核（330→112 真实计数、遗留文件"登记未删除"、img 10、img 绑定、`work/` 登记）；
  8. 无 bit/上板/真实 PCIe/A 路通过声明。
- input_status：**changed**（相对 r1：新增派生变体与等价 TB、改 P1 生产文件、构建脚本、harness、
  tcl、manifest、文档；样例哈希不变）。
- reuse_decision_paths（仅"同哈希 + 绑定新 manifest"可复用）：测试者工具
  `test-reports/INT.P4/r1/verify_manifest_r1.py`、`oracle_sample_r1.py`、`run_p1_tool_isolated_r1.py`、
  `test-reports/INT.P4/tb_intp4_tester.v`；冻结样例与 `tools/integrated_delivery/evidence/*`（哈希一致时）。
  不得复用 r1 的 PASS 日志于 r2 的 RTL；不得把 r1 的 TD 报告当 r2 证据（r2 用 `INT.P4/td/syn_r2_run2/`）。
- report_paths：`workflow/runs/20261026-2138_fpga-integrated-delivery/test-reports/INT.P4-r2-integrated.md`
  （及 `test-reports/INT.P4/**`）。
- manifest_path：`workflow/runs/20261026-2138_fpga-integrated-delivery/INT.P4-r2-manifest.json`。
- blocked：`[]`。
