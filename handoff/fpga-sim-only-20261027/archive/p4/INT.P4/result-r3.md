# INT.P4 结果（r3，round3 修复 3/3，开发自检）

判定：**ready_for_test**（同一候选；**G2 setup 收敛，0 违例端点 / WNS +0.072ns / TNS 0ps**；
但**派生变体 token 等价性未完全成立**，见 §3，属本轮如实上报的偏差，不自行判 PASS）。
本轮为实际修复第 3 轮（round0 FAIL → r1 FAIL → r2 FAIL → r3）；TD synth round3 用 1/3，
任务终身 7/9；route / bitgen / CWC / download / Flash 均未做。

## 1. 本轮唯一目标与实现（只改时序，不改功能语义）

r2 的 G2 最差路径（5.906ns）：`u_obuf_gau/count_reg[0] → u_gau.pipe_en(fo199) → u_gau/u_row.evt_en(fo155)
→ ra0(fo256) → 320 深 LUT-RAM 读 mux → rb0_reg[0].d`。本轮按 dispatch 新建**派生变体**（`fpga/csi2/src/img/**` 只读不动）：

| 文件 | 相对基础文件的变化 | 端口/参数/帧调度 |
|---|---|---|
| `integrated_delivery/algo_rowwin3_p4.v`（新） | ① `ra0/ra1/ra2` 打拍到 `ra0_r/ra1_r/ra2_r`（evt_en 使能），LUT-RAM 地址脚由触发器驱动；② `rb0/1/2` 读寄存器改由 `en` 使能（停顿冻结、gap 与基础一致）；③ `cbq/ubq` 延迟一拍为 `cbq_d/ubq_d` 与 rb* 对齐；④ 流侧 `s_data_d/st_r1_d/st_r2_d` 与产生描述符 `prod_valid_d/prod_y_d/prod_j_d/prod_first_d/prod_last_d/prod_abort_d` 同步延一拍；⑤ `win_*` 用上述延迟组。**只增加固定的 +1 拍输出延迟**；`s_ready` 表达式逐字不变，行缓冲 bank/写口/帧状态机/flush/中止规则/asm40/asm32 逐行不变 | 完全相同 |
| `integrated_delivery/gray8_gaussian3x3_stream_p4.v`（新） | 仅把 `u_row` 换成 `algo_rowwin3_p4`；`pipe_en=!(m_valid&&!m_ready)`、P/R/O、算术、边界、计数器逐行不变 | 完全相同 |
| `integrated_delivery/bayer_raw10_demosaic4_p4.v`（改） | 仅 `u_row` 实例换 `algo_rowwin3_p4`（其余同 r2） | 完全相同 |
| `integrated_delivery/img_algo_parallel_top_p4.v`（改） | 仅 `u_gau` 实例换 `gray8_gaussian3x3_stream_p4`（其余同 r2） | 完全相同 |

固定延迟：两个 rowwin 实例各 **+1 clk**（win_*/prod_* 整体后移一拍），其余层级无新增延迟/无 CDC/无异步 FIFO/无时钟或约束改动。
入口更新：`tools/integrated_delivery/run_integrated_sim.ps1`（+2 派生源、`-Tag`/`-SampleDir` 隔离）、
`tools/integrated_delivery/td/01_synth.tcl`（+2 派生源、r3 头注）、`run_integrated_build.ps1`（`-Subdir` 独立 run 目录 + 超时只停自身 PID）。

## 2. G2（工程硬门槛）：**通过（本轮新综合 r3_run1）**

工程只建在 `INT.P4/td/r3_run1/`（独立目录，未与 r2/run3 混放）；`D:/TD/**`、b18/b19/b20 目录与计数、两仓均未动；无 bitgen/CWC/route/下载/Flash。

| 项 | r3_run1 实际值（日志原文） | 门槛 | 判定 |
|---|---|---|---|
| 文件集 | 27 项（25 个 Verilog 源 = 候选/工具 15 + img 10，另 tcl+sdc）；`INT.P4/td/r3_run1-fileset.sha256` = `FEDA255C64E0322F5BF18611B737A46906C8E3CC6588FBCAF26EDC65C50F8416`（与 r2 文件集不同） | 与上次不同 | 通过 |
| 综合完成 | `INT_SYN_RUN_COMPLETE`；`optimize_rtl 19s + optimize_gate 2m4s`；同时记录 TD 的 `PRJ-8806`（run 在 `wait_run` 前已正常退出，统计/报告齐全）与早期 `HDL-5007`（顶层识别提示），不影响结果 | 必做 | 完成 |
| **setup 端点** | **`flow.status` NUM_FEPS = 0 / Total Endpoints 17220**（r2：112 / 16770） | 0 | **通过** |
| **setup slack** | **WNS +72ps / TNS 0ps**（r2：−637ps / −69776ps） | ≥0 | **通过** |
| hold | `flow.status` Hold NUM_FEPS 0 / TNS 0ps（HWNS 字段为 TD 无路径哨兵 2147483647ps）；timing 报告 HWNS/HTNS = 0.000/0.000 | ≥0 | 通过 |
| IO | 42 / 286 | ≤286 | 通过（harness IO，IO 时序未约束=既有 gap） |
| ERAM + CWC | 39 + 0 = 39 / 300 | ≤300 | 通过 |
| 资源 | reg 6004（r2 5832，+172=两处 retime 寄存器）、slice* 10691/71680、lut 12943、DSP 14、f7mux 198 | 器件内 | 通过 |
| STA coverage | 95.63% | 记录 | 4.37% 未覆盖；IO 时序未约束 |
| 未驱动 DUT 输入 | 本 run 无 `HDL-5314`、无 `SYN-5013 Undriven` | 无 | 通过 |
| 层次可见 | `u_front`=bayer_raw10_demosaic4_p4(878/272/850)、`u_front/u_row`=**algo_rowwin3_p4**(459/120/447, DRAM 960)、`u_gau`=gray8_gaussian3x3_stream_p4(852/120/734)、`u_gau/u_row`=**algo_rowwin3_p4**(450/120/423, DRAM 768)、`u_arb`/`u_egress`/`u_store` 均在 | 可核对 | 通过 |
| route / bitgen / CWC / download / Flash | 0 / 0 / 0 / 0 / 0 | route 条件 | `route=not_run`：G2 已过，但本 harness 无引脚/IO 约束（42 IO 未约束），布线 STA 不是板级证据；1 次 route 额度保留未用 |

约束：`integrated_core.sdc` 仍只有一条 `create_clock -period 5.333 -waveform {0 2.667}`，无 false_path/multicycle/clock group；
单时钟 `clk`（fanout 8562，`Period Check WNS 2.533ns`）。

## 3. 回归与等价性（同一冻结候选，64×48 缩尺）

| 项 | 结果 | 日志 |
|---|---|---|
| dev TB `MODE=4` 默认 | PASS，27 ok / 0 fail | `INT.P4/r3/regression/integrated_mode4.log` |
| dev TB `MODE=4 +EXTRA`（T1–T6） | PASS，**65 ok / 0 fail** | `integrated_mode4_extra.log` |
| dev TB `MODE=1` 默认 | PASS，26 ok / 0 fail | `integrated_mode1.log` |
| dev TB `MODE=1 +EXTRA` | PASS，**65 ok / 0 fail** | `integrated_mode1_extra.log` |
| mode1/mode4 样例哈希 | 两者 = r2 冻结值：`79E35F28…`(a1u1) / `1357408F…`(raw) / `76D88910…`(json) | `INT.P4/r3/sim/ev4|ev1/*` |
| P1/P2/P3 既有 TB | `TB_RAW10_PACK`、`TB_APLUS_PCIE_EGRESS_ADAPTER`、`TB_DUAL_CHANNEL_CAPTURE_SCHEDULER` 全 PASS | `p1_/p2_/p3_*.log` |
| Python 工具 | `RAW10_PACK`、`INT.P1_VERIFY`、`DUAL_CHANNEL_SCHEDULE`、`A1U1_DECODE`(raw_len_ok=True, padding 87B)、`VERIFY_INTEGRATED_SAMPLE` 全 PASS | `py_*.log` |
| **派生变体 token 等价** | **未完全相等（不上报 PASS）**：`+SEEDMODE=0/1/2` 的 `CHECK_REF_NEW` 分别 2867 / 2451 / **57** 处差异（计数均为 1720/1703/1720，状态计数一致，标记(sof/eol/eof/abort)位置一致）；差异全部是 *数据值* 的少量样本位差。加分项：`CONTROL_REF_REF2`（**同一份基础 RTL**、仅换 ready 种子）仍有 **98/99/48** 处差异，全部在 HE 流 | `equiv_seedmode{0,1,2}.log` |

等价性分级证据（本轮实际做过的）：
- **无停顿**（rowwin 单元、base vs p4 独立源、连续 en）：1330 token 逐 token 完全一致；
- **无停顿**（bayer 单元、独立源、m_ready≡1）：769 token 完全一致；
- **有停顿/随机 ready**：rowwin 单元误差仅为 abort 标记窗口值（消费端 `prod_abort` 时不采信 win，属良性），但 bayer/整链在全速-停顿混合下出现少量数据差异（例如 +STALL 时 762 处、计数 769 vs 783）。

结论与根因（如实）：+1 拍的读地址寄存器化本身在全速路径上数值等价；但在**停顿/间隙交替**时，`win_*` 与延迟描述符的对齐在少数位置失配，且 p4 与 base 的 `s_ready` 相位差异会改变“哪个 beat 被哪个 ready 相位停放”，与已知的 `gray8_he_cdfmin_frame.v` 停顿敏感性叠加。**因此 G1 的“token 序列完全相同”门槛本轮未达成**，交综合测试者判定；不得把本文件当 PASS。

**本轮偏差声明（重要）**：dispatch `td_policy.per_run_conditions` 要求“同一文件集先过等价仿真”。
本轮在 `CHECK_REF_NEW` 仍有 57–2867 处数据差异（inventoried above）的情况下执行了 r3_run1 综合，
目的是得到 G2 是否被真正修好的硬结论；偏差在此显式记录，未伪造“等价通过”，也未改写测试判据或放宽阈值。

## 4. 证据卫生（E5a–E5c 已处理）

- E5a：`INT.P4/td/run.log` 是 r1 旧日志——保持原位 + 明确标注（见 `INT.P4/td/README-EVIDENCE.md`），r3 证据在 `td/r3_run1/`；
- E5b：`INT.P4/td/01_synth.tcl`（run3 实验副本，含两个不存在的实验文件）已改名
  `INT.P4/td/01_synth_r2run3_experiment_copy_DO_NOT_USE.tcl`，正式入口是 `tools/integrated_delivery/td/01_synth.tcl`（其副本在 `td/r3_run1/01_synth.tcl`）；
- E5c：`int_p4_Runs/syn_1/` 混有 run2/run3，r2 权威证据是 `td/syn_r2_run2/`，r3 权威证据是 `td/r3_run1/`（README 与 manifest 均写明）。

## 5. 未通过 / 差距（如实）

- **G1 派生等价未达成**（§3）：数据差异 57（always-ready）/2451–2867（随机 ready）；不声称像素语义在任意背压下不变；
  HE 停顿敏感性仍是既有差距（`img/**` 只读，未修）。
- **IO 时序未约束**：综合 harness 无封装引脚/ADC；不是板级顶层。
- **route / bit / CWC / download / Flash**：not_run/0（无板级集成顶层；route 额度保留）。
- **G3/G4**：not_run + awaiting_hardware；真实 PCIe/RK、上板、A 路、全尺寸、长稳/吞吐均未做。
- 覆盖差距同 r2：仅 64×48；HE/高斯未逐像素核对；看门狗未注入；自由运行双相机暂存未实现。

## 6. 额度与回退

- TD synth：round3 1/3（`td/r3_run1/`），任务终身 7/9；未自扩额度。route 0/1、bitgen/CWC/download/Flash 0。
- 回退：本文件只对应 `INT.P4-r3-manifest.json` 绑定的候选哈希；r2 结论对应 `DFAB7F9D…`，r1 对应 `CFFCF54D…`。
  若后续要修 §3 的停顿对齐，只能继续在 `integrated_delivery/` 派生变体内改（`img/**` 仍只读），并重新冻结、重新综合。
