# G2 证据（T07.rk-align-backend）

本目录记录 TD 6.2.3 的最终实现/时序/位流证据位置与判据。**证据本体在候选工程里**
（`workflow/runs/20261017-011744-rk-fpga-align/backend/candidate/prj/`），本文件只做索引与结论。

## 1. 工具、入口与版本（实查）

* `D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe`
  → `Release_2026.2` / `Build: 6.2.3.210850`（与 contract 一致）。
* 入口：`tools/pcie_integration/run_td.ps1 -Stage 00_all`（**单会话**：create → syn → phy →
  `save_best_bits`）。`01_create/02_syn/03_phy` 三个分阶段脚本**仅作参考**：实测 TD 的
  `create_project` 才会把 `device_name/package_name` 放进会话变量，另开会话 `open_project`
  再 `launch_runs` 会得到空的 `settings.cfg`，子流程报 `can't read "device_name"`
  （保留的失败证据：`prj/td_20261017_034251.log` 的 `PRJ-8642`、
  `prj/td_20261017_040236.log` 的 `PRJ-8806`、`prj/td_20261017_040348.log` 的 `USR-8122`）。

## 2. 判定用的产物（TD 工程内，SHA 收进 `candidate-manifest.json`）

| 产物 | 位置 | 用途 |
|---|---|---|
| 综合日志/报告 | `.../ph1p_pcie_integration_Runs/syn_1/run.log`、`ph1p_pcie_integration_gate.{db,area,timing,ts}`、`gate.qor` | 资源/综合时序 |
| PHY 日志/报告 | `.../phy_1/run.log`、`ph1p_pcie_integration_phy.{area,ts}`、`place.qor`、`route.qor`、`final_timing.rpt`、`ph1p_pcie_integration_chk.timing`、`..._exception.timing` | 最终 STA（setup/hold/TNS） |
| 最终数据库 | `.../phy_1/ph1p_pcie_integration_pr.db`、`..._place.db`、`..._inst.bid` | 与 bit 同源 |
| 位流 | `.../phy_1/ph1p_pcie_integration.bit`（`save_best_bits` 同时写入 `best_result/`，同 SHA） | 唯一候选 bit |
| 工程/脚本 | `prj/ph1p_pcie_integration.al`、`00_all.tcl` 等 | 复现入口 |

## 3. 实测结果

### 3.1 round0（2026-10-17 04:13–04:33，首轮冻结输入）

SWNS −2.433 ns / STNS −276.644 ns（159 违例端点，全在 cam_a/cam_b 字节域），hold +0.020 ns，
资源 ERAM 134/300、LUT6 19.44%，bit `36A82F37…`。engineering 维度据此判 FAIL（见
`test-reports/T07.rk-align-backend-r0-engineering.md`）。

### 3.2 round1（2026-10-17 05:0x–05:25，修复 F1/F2 后的**当前**候选）

命令：`run_td.ps1 -Stage 00_all`（单会话）。syn 3m52s + phy 15m59s；
`PRJ-1406 Run phy_1 finished` + `PRJ-1424 The implemented result of phy_1 is saved as best result`
+ 控制台 `T07_ALL_DONE`（`prj/td_00_all.log`）。

| 项 | 值 | 判据 |
|---|---|---|
| 最终 STA | `phy_1/final_timing.rpt`（head: Generated Sat Oct 17 05:24:48 2026 / Routed / Both corners / CRPR on） | — |
| **Setup** | **SWNS = −2.507 ns，STNS = −300.004 ns（181 violated endpoints）** | setup ≥ 0 / TNS 0 → **未达** |
| Hold | HWNS = +0.020 ns，HTNS = 0.000 ns | ✓ |
| 按时钟（SWNS） | clk0 `usr_clk` 100 MHz **+0.739**；clk1 `tl_clk_user` 62.5 MHz **+0.919**；**clk2 `cam_a_byte_clk` 187.547 MHz −2.503 / STNS −142.211（85 endpoints）**；**clk3 `cam_b_byte_clk` −2.507 / −157.793（82 endpoints）** | 违例**全部**在两条相机字节域 |
| 最差路径 | `u_csi_a/u_integrity/mux153_syn_1334.clk → u_csi_a/u_integrity/O_crc_errors_reg[0]_syn_2.ic`，数据路径 7.710 ns，**逻辑级 10**，其中 **cell 3.082 ns（39%）/ net 4.628 ns（61%）**；Budget = 5.332 ns | 违例在本包引入的 checked 包层（CRC/keep/计数组合链） |
| 资源 | LUT6 13,940/71,680（19.45%）、slice reg 15,890/143,360（11.08%）、slice 15,169/71,680（21.16%）、**ERAM 134/300（44.67%，FIFO20K=0，无溢出到 DRAM）**、DSP 0/220、PCIE 1/1、DDR 7/24、PLL 3/12、IO 107/286 | ✓ |
| 位流 | `phy_1/ph1p_pcie_integration.bit` 5,224,023 B（与 `best_result/` 同 SHA；与同次 `pr.db`/`place.db`/报告同源） | —— |

**本包结论**：G2 的构建链/hold/资源/候选绑定全部通过，**setup 与 TNS 未达** ⇒
按任务书判据 **G2 不通过**。本轮**不擅自放宽** 187.5 MHz 前提或判据，按修复轮指令记 **blocked**，
把下面的方向交原规划者决策。

### 3.3 时序表述更正（round0 报告 §6.3 指出；round2 更新）

`final_timing.rpt` 的 C-Period/R-Period 含义是 **C = 约束周期（5.332 ns = 187.5 MHz）、R = 实际达成**；slack = C −（数据路径 + 建立/不确定度）。round0/round1 的 R-Period 是 7.835/7.676 ns（约 127.6 MHz，未达约束），round0 文档里“SDC 要求 7.676 ns”的写法**反了**；**round2 R-Period = 5.225/5.202 ns（191.4/192.2 MHz），同一判据下已达标**（见 §3.5）。

### 3.4 为什么这不是"再加一级流水"能修好的（给规划者的技术判断）

* 违例点都在 **187.5 MHz 相机字节域**，而该域**不可反压**（CSI-2 无 flow control）：
  模块必须每拍吃满 4 字节，**插不进流水气泡**；
* 核心是 **CRC-16 的逐拍递推**（`crc <= f(crc, 本拍 4 字节)`）：它把本拍的组合结果喂回同一寄存器的
  输入，**不能靠插寄存器解决**；给错误计数器加一级寄存器也救不了 `crc` 寄存器本身的递推路径；
* 最差路径 **61% 是布线**（net 4.628 ns / cell 3.082 ns）、逻辑级 10：即使把逻辑压浅，
  在 5.332 ns 预算里也很难稳定收敛（该域跨两片 CSI + 两片 writer 扇出）；
* 唯一干净的三种出路（都需要改设计或改前提，**不是本轮"修复"范围**）：
  1. **CRC 代数改造**：2 路交织 CRC（偶/奇拍各一条链，末帧按 GF(2) 多项式合并）或等效的分拍递推
     改造 —— 会改动并需重新验证**本方冻结的 checked 源**（`fpga/csi2/src/csi`）；
  2. **搬到慢域做检查**：字节域只做 keep/透传并写入一个小 ERAM（一行 ≈ 600 字 ≈ 1 块 ERAM20K），
     在 `tl_clk_user`(62.5 MHz) 域做 CRC/WC/行数判定，再从那里喂像素解包 —— 架构改动（新增模块，
     需重做 checked CSI 的验证矩阵）；
  3. **改前提**：与用户/规划确认是否允许调整相机链路速率（I2C 寄存器表）以降低字节时钟
     （4K30 RAW10 的理论需求约 81 MHz 字节时钟，当前 187.5 MHz 有大余量）——这会改变 T11 的
     相机源前提，属规划/用户决策。
* 另一个**不是修法**的选项（仅记录）：`set_multicycle_path`/`set_max_delay` 之类的约束放宽会在
  逐拍递推数据通路上引入功能性风险，本包**不做**。

### 3.5 round2（2026-10-17 05:55–06:04，G2 本域时序重构后的**当前**候选）—— **达标**

命令：`run_td.ps1 -Stage 00_all`（单会话；round2 输入。按派发"最多两次"记账，本轮用**第 1 次**即达标，
未做第 2 次）；syn 05:55:01–05:57:24 + phy 05:57:25–06:03:43；
`PRJ-1406 Run phy_1 finished` + `PRJ-1424 The implemented result of phy_1 is saved as best result`
+ 控制台 `T07_ALL_DONE`（`prj/td_00_all.log`）。

| 项 | 值 | 判据 |
|---|---|---|
| 最终 STA | `phy_1/final_timing.rpt`（head: Generated Sat Oct 17 06:03:23 2026 / **Routed** / Both corners / CRPR on；STA coverage 95.40%） | — |
| **Setup** | **SWNS = +0.107 ns，STNS = 0.000 ns（0 violated endpoints）** | setup ≥ 0 / TNS 0 → **✓** |
| Hold | HWNS = +0.020 ns，HTNS = 0.000 ns | ✓ |
| 按时钟（SWNS） | clk0 `usr_clk` 100 MHz **+0.481**；clk1 `tl_clk_user` 62.5 MHz **+0.540**；**clk2 `cam_a_byte_clk` 187.547 MHz +0.107 / R-Period 5.225 ns（191.4 MHz）**；**clk3 `cam_b_byte_clk` +0.130 / R-Period 5.202 ns（192.2 MHz）**；clk4 50 MHz +11.713；其余 +0.000 | 全部非负 |
| 最差路径 | `u_csi_a/u_gear_box/r_byte_buffer_reg[55]_syn_2.clk → u_csi_a/u_integrity/O_bad_frames_reg[30]_syn_2.cea`，数据路径 4.982 ns，**逻辑级 6**（LUT5=3/LUT4=2/LUT3=1），cell 2.293 ns（46%）/ net 2.689 ns（54%），Budget = 5.332 ns | 余量 **+0.107 ns** |
| 资源 | LUT6 **13,713/71,680（19.13%）**、slice reg 15,793/143,360（11.02%）、slice 15,007/71,680（20.94%）、**ERAM 134/300（44.67%，FIFO20K=0，无溢出到 DRAM）**、DSP 0/220、PCIE 1/1、DDR 7/24、PLL 3/12、IO 107/286 | ✓ |
| 位流 | `phy_1/ph1p_pcie_integration.bit` **5,224,023 B**，SHA256 `0943cb36feeb873decc6ea5aae1c2777b3ab4881ebe2954b43bee040ceb38b0a`（与 `best_result/` 同 SHA）；同次 `pr.db`/`place.db`/报告 | ✓ 同源 |

**与 round1 的对比（同一判据、同一入口，未放宽任何约束）**：

| 指标 | round1（F1/F2 修复后） | round2（本轮重构后） | 变化 |
|---|---|---|---|
| SWNS | −2.507 ns | **+0.107 ns** | **+2.614 ns** |
| STNS | −300.004 ns | **0.000 ns** | 归零 |
| 违例端点 | 181（全部 cam_a/cam_b 字节域） | **0** | — |
| 最差路径 | `u_csi_a/u_integrity/mux153…clk → O_crc_errors_reg[0].ic`（CRC 比较→计数 enable），逻辑级 10 / 61% 布线 / 7.710 ns | `u_csi_a/u_gear_box/r_byte_buffer… → O_bad_frames_reg[30].cea`（数据→计数 enable），逻辑级 6 / 54% 布线 / 4.982 ns | 逻辑级 −4、路径 −2.728 ns |
| `TMST-7700` SEVERE（post-route） | 5（place 阶段 2） | **5**（= chk.timing 的 2 无根时钟网 + 3 local clock，与 round0 同类、逐项解释见 §5；**不是** setup 违例） | — |
| 位流 | `3F2E48E8…B977`（负裕量，仅留痕） | `0943CB36…8B0A`（正裕量） | 新候选 |

> round2 **没有**对 round1 §3.4 的三种出路做任何选择：**没有**改相机链路速率/前提、**没有**把检查搬慢域、
> **没有**放宽 SDC 或加 multicycle/set_max_delay、**没有**改 `fpga/csi2/src/csi` 原源或 wrapper 对外接口/顶层连线；
> 只在本包 `rtl/checked/` 的 checked 包层内部做有界重构（三条手法见 `../change-report.md` §8.1），
> 行为等价由差分 oracle 证明（§8.2）。§3.4 的分析（为什么"加流水/放宽约束"不行）结论仍然成立——
> 本轮的修法是**结构**优化（宽比较→小范围译码、串行线性递推→扁平 XOR 树、比较/计数移出每拍链），不是加流水。

### 3.6 已知节制：round2 余量偏薄（如实列出）

+0.107 ns 是"同一最终 DB 达标"的最小充分证据，但**余量薄**：worst path 54% 是布线、且该域跨两片 CSI + 两片 writer。
本包**不再做**任何 ECO/重综合（避免改动已达标候选的源↔位流绑定）；后续若要加功能或换 TD 版本，
应把"相机字节域 setup ≥ 0"当作回归门槛重跑 G2。判据本身未放宽，其它域（100/62.5 MHz）余量充足。

## 4. 通过/未通过判据清单（engineering 复核用）

| 判据 | 结果 |
|---|---|
| TD 退出码 0 + 完成标记（PRJ-1406/PRJ-1424/T07_ALL_DONE）+ 非空产物 | ✓（round2 单一最终实现） |
| 同一最终实现 DB：setup ≥ 0 且 TNS = 0 | **✓**（SWNS +0.107 ns / STNS 0.000 / 0 违例端点；见 §3.5） |
| hold ≥ 0 | ✓ (+0.020 ns) |
| 资源 ≤ 器件 | ✓（LUT6 19.13% / ERAM 134/300；见 §3.5） |
| 位流与 DB/报告同源（唯一 bit、同次 run、SHA 记录） | ✓（`0943CB36…8B0A`，与 `best_result/` 同 SHA） |
| checked 包层重构的行为等价（对只读原源） | ✓ 差分 oracle `tb_csi_integrity_diff`：680 拍 0 失配、abort/计数 ≤2 拍窗口；见 `../change-report.md` §8.2 |
| 约束/时钟覆盖（`chk.timing` 逐项） | 见 §5 |
| CWC 完整 ERAM/BID 检查 | not_applicable（候选无 CWC 生成物，清单可核） |

## 5. 约束检查（`phy_1/ph1p_pcie_integration_chk.timing`）逐项说明

| 项 | 数量/级别 | 解释与结论 |
|---|---|---|
| no clock | 2（HIGH） | `pcie_pll_locked`、`tl_clk_user_ce_n` 是**数据/使能类网**被误当候选时钟网列出；真实时钟全部来自 PLL/IP 输出（clock summary 里 13 个时钟都有定义）——不构成未约束时钟 |
| local clock | 3 | `cam_a/cam_b_byte_clk`（PHY 内分频器输出，187.5 MHz）与 `sys_clk_dup_1`（50 MHz 参考，peer 原样）：均为 IP/PHY 生成的时钟，已在 SDC 里用 `create_clock/create_generated_clock` 或 IP 自带 sdc 覆盖；其中 `sys_clk_dup_1` 走 local 走线（RTCLK-5079）是 peer 既有实现（T07 未改 PCIe 参考时钟路径） |
| no input delay | 73（MEDIUM） | 板级输入里只有 MIPI/DDR/PCIe 是**源同步或串行 CDR**（由 PHY 原语/IP 自带 sdc 管住），其余是按键/复位/LED 等慢速 IO；peer 原本就不写这些 IO 的 input delay，本包**未改约束**（保持权威源不变） |
| no output delay | 87（MEDIUM） | 同上（LED/UART/DDR 控制等慢速输出） |
| comb. loop / invalid / shadowed / no-path | 0 | 无 |
| `TMST-7700` SEVERE（post-route） | **5**（`phy_1/run.log` L1796；place 阶段 L1104 为 2） | 与 round0 同类：2 无根时钟网 + 3 local clock（即上两行的同一批告警，逐项解释见本表）；**与 setup 违例无关**（round1 亦为 5）。注：本表曾（round2 收口时）误记 0，round3 按实物证据更正，见 `change-report.md` §10.2 |
| `STA coverage` | 95.40%（round1 95.50%） | TD 的时序覆盖率统计：未被覆盖的约 4.6% 主要是异步域内部与无 delay 的慢速 IO（见上两行）；**不是**"95.4% 通过"，本包不据此声称达标 |

## 6. 结论与交接

* **G2 通过（round2）**：同一最终实现 DB 上 setup **SWNS +0.107 ns / STNS 0.000（0 违例端点）**、
  hold +0.020 ns、资源在器件内、位流与同次 DB/报告同源（`0943CB36…8B0A`）。
  达标手段是本包 checked 包层内的**有界结构重构**（`../change-report.md` §8.1），行为等价由差分 oracle 证明
  （§8.2）；**未**放宽 SDC/判据、**未**加 multicycle/max_delay、**未**搬慢域、**未**改 187.5 MHz 或相机速率前提、
  **未**改 `fpga/csi2/src/csi` 原源与 wrapper 对外接口/顶层连线。
* 余量偏薄的如实登记见 §3.6；round0/round1 的失败留痕（183 端点/181 端点、-2.4/-2.5 ns）保留在 §3.1/§3.2 与
  `../test-reports/`，不删除、不覆盖。
* 三维复测必须绑定 round2 manifest（`cde55fc8…edec`，schema2/round2，232 条自检 0 不一致）；
  system 探针按 `../change-report.md` §7.2 接 pusher 的 `rel_tgl2/3`（B 路 release）后再跑。

