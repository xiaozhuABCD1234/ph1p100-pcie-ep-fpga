# INT.P4 构建/仿真入口（r2）

## r3 更新（2026-10-27，本轮权威数字；以下 r2 正文保留为历史）

- **候选源（仿真入口，24 个核心 + 6 TB）**：候选 8（`integrated_delivery_top.v`、`integrated_input_processing_top.v`、
  `raw10_sample_vector_to_packed.v`、`frame_good_publish_cancel.v`、`aplus_pcie_egress_adapter.v`、
  `dual_channel_capture_scheduler.v`、`bayer_raw10_demosaic4_p4.v`、`img_algo_parallel_top_p4.v`、
  `algo_rowwin3_p4.v`、`gray8_gaussian3x3_stream_p4.v` —— 其中后 4 个是派生时序变体）+ b20 4 + img 10 = **24**；
  TB 6（5 个候选 TB + 等价 TB）。img 源仍是 10 个（`img/**` 只读，未改）。
- **综合入口（`tools/integrated_delivery/td/01_synth.tcl`）**：25 个 Verilog 源（候选/工具 15 + img 10）+ harness 1 已含在 15 内 + tcl/sdc；
  文件集清单 `INT.P4/td/r3_run1-fileset.sha256`（27 项，SHA256 `FEDA255C…`）。
- **TD 证据目录**：`INT.P4/td/r3_run1/`（独立，不与 r2 混放）；`INT.P4/td/syn_r2_run2/` 仍是 r2 权威。
- **G2（本轮）**：`flow.status` Setup **NUM_FEPS 0 / 17220**、**WNS +72ps / TNS 0ps**，Hold 0 端点；
  IO 42/286、ERAM+CWC 39/300、reg 6004、slice* 10691/71680、DSP 14；`u_front/u_row`、`u_gau/u_row` 均为 `algo_rowwin3_p4`。
- **回归**：dev TB MODE=4/1 默认+EXTRA（27/65/26/65 ok，0 fail）；mode1/mode4 样例哈希 = `79E35F28…/1357408F…/76D88910…`；
  P1/P2/P3 TB 与 Python 全 PASS。**派生变体 token 等价仍有 57–2867 处数据差异（见 result-r3 §3），不作为已通过项。**
- route/bitgen/CWC/download/Flash = 0。命令见 `INT.P4-shortest-steps.md` 的 r3 段。


## 1. 仿真（ModelSim ASE 10.5b；P:/W: 约定）

一键脚本（cwd 任意）：

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools/integrated_delivery/run_integrated_sim.ps1            # 默认 -Mode 4 -Sample 1
powershell ... -Mode 4 -Sample 0 -Extra                                                                        # 多场景表
powershell ... -Mode 1 -Sample 0 -Extra                                                                        # Y8 + 反压
powershell ... -Mode 4 -Sample 0 -Extra -Full                                                                  # 追加派生变体等价 + P1/P2/P3 TB + Python 工具
```

脚本实际行为（r2 已核对）：

| 参数 | 行为 | 日志 |
|---|---|---|
| 默认 | 编译候选 + 集成 TB，跑 `+MODE=4 +SAMPLE=1`，样例写 `tools/integrated_delivery/evidence/` | `INT.P4/regression/integrated_mode4.log` |
| `-Extra` | 追加 T2（监视反压+DDR 写停顿）、T3（abort）、T4（A 禁用+B 优先→使能 A）、T5（错误 ACK→正确 ACK）、T6（提前 EOF 截断帧不得提交） | `integrated_mode4_extra.log`、`integrated_mode1_extra.log` |
| `-Full` | 追加 `tb_img_algo_equiv_p4`（`+SEEDMODE=0/1/2`）×3，再编译并运行 `tb_raw10_packer`、`tb_aplus_pcie_egress_adapter`、`tb_dual_channel_capture_scheduler`，随后运行 `raw10_pack.py`、`verify_input_processing.py`、`dual_channel_schedule.py`、`a1u1_decode.py`、`verify_integrated_sample.py` | `equiv_seedmode{0,1,2}.log`、`p1_tb_raw10_packer.log`、`p2_tb_egress.log`、`p3_tb_scheduler.log`、`py_*.log` |

编译清单（r2，**实际编入**，共 6 + 2 + 4 + 10 + 5 = 27 个源/TB 文件）：

- 集成候选 6：`integrated_delivery_top.v`、`integrated_input_processing_top.v`、
  `raw10_sample_vector_to_packed.v`、`frame_good_publish_cancel.v`、
  `aplus_pcie_egress_adapter.v`、`dual_channel_capture_scheduler.v`
- **r2 仅时序派生变体 2**：`bayer_raw10_demosaic4_p4.v`（含 `int_p4_elastic_beats` 原语）、
  `img_algo_parallel_top_p4.v`
- b20 r0 只读 A+ 核 4：`a1_frame_top.v`、`a1_deflate_core.v`、`a1_ddr_slot_store.v`、`a1_ddr_arb2.v`
- **`fpga/csi2/src/img/*.v` = 10 个**（r1 文档误写 9）：algo_obuf、algo_rowwin3、algo_rowwin_reader、
  bayer_raw10_demosaic4、gray8_gaussian3x3_frame、gray8_gaussian3x3_stream、gray8_he_cdfmin_frame、
  img_algo_parallel_top、img_algo_top_g2、rgb8_gray_stream
- TB 5：`tb_integrated_delivery_top.v`、`tb_img_algo_equiv_p4.v`、`tb_raw10_packer.v`、
  `tb_aplus_pcie_egress_adapter.v`、`tb_dual_channel_capture_scheduler.v`

工作目录：`workflow/runs/20261026-2138_fpga-integrated-delivery/INT.P4/sim/compile`（work 库）。

手工等价（cwd=compile）：

```
vlog -work work <候选6> <派生变体2> <b20 4> <img 10>
vlog -work work <TB 5>
vsim -c -do "run -all; quit -f" tb_integrated_delivery_top +MODE=4 +SAMPLE=1 +SAMPLE_DIR=D:/fpga/ph1p100/tools/integrated_delivery/evidence
vsim -c -do "run -all; quit -f" tb_img_algo_equiv_p4 +SEEDMODE=0
```

## 2. 解码 / 独立校验

```
python tools/integrated_delivery/a1u1_decode.py tools/integrated_delivery/evidence/integrated_sample.a1u1 4096
python tools/integrated_delivery/verify_integrated_sample.py <a1u1> <raw> <json>
python workflow/runs/20261026-2138_fpga-integrated-delivery/test-reports/INT.P4/oracle_sample.py --sample <a1u1> --raw <raw> --json <json>
```

第三条是综合测试者提供的独立判据（不 import 开发代码，用 `struct`/`binascii.crc32`/`zlib` 从像素公式重算
packed RAW10 并与 `.raw` 逐字节比较），r1 复跑结果 `ORACLE PASS`（r2 样例哈希与 r1 相同，内容判据可复用）。

## 3. TD 综合（隔离工程，synth only）

- 工程目录只能是 `workflow/runs/20261026-2138_fpga-integrated-delivery/INT.P4/td/`。
- 入口：`powershell -File tools/integrated_delivery/run_integrated_build.ps1 -Stage 01_synth`（复制
  `01_synth.tcl`+`integrated_core.sdc` 到 run td 目录后调用 TD CLI）；等价手工命令（cwd=INT.P4/td）：
  `D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe 01_synth.tcl`
- **综合顶层是仅用于综合的测试框架**：`tools/integrated_delivery/synth/integrated_delivery_synth_wrap.v`，
  原样实例化 `integrated_delivery_top`，把 2813 个顶层 IO 换成片上捕获激励 / 行为 DDR 从模型 /
  描述符序列 / PCIe+ACK 模型 / 周期反压监视口，并把全部观测总线异或压缩为 32bit 寄存器输出（IO 42）。
  **覆盖边界**：这不是板级壳；不新增引脚/ADC；STA 只覆盖内部寄存器路径；IO 时序未约束（G2 gap）；
  只有一条 `create_clock 5.333ns`，无 false_path/multicycle。r2 起 A/B 捕获为寄存器输出 beat，
  **全部 DUT DDR 从口输入（awready/wready/arready/rvalid/rdata）由行为 DDR 模型驱动**。
- r2 绑定为 G2 证据的是 **run2**（`INT.P4/td/syn_gate_*`、`syn_flow.status`、`td_01_synth_console.log`，
  同内容保存在 `INT.P4/td/syn_r2_run2/`）：
  `#IO=42/286`、`#eram=39/300`、`#CWC=0`、`#reg=5832`、`#slice*=10761/71680`、`#dsp=14`、
  `HWNS=HTNS=0.000ns`、**112 Viol Endpoints / 16770 Total**、`SWNS=-0.637ns`、`STNS=-69.776ns`、
  STA coverage 95.76%、无 `HDL-5314`/`SYN-5013` 未驱动告警、层次表含 `u_arb`/`u_egress`/`u_store`。
  最差路径仍在 DUT 内部：`u_p1/u_algo/u_obuf_gau/count_reg[0]` → `u_p1/u_algo/u_gau/u_row/rb0_reg[0].d`
  （5.906ns，cell 2.304 / net 3.602，fanout 256，7 级）。
  **端点计数从 `flow.status` 的 `NUM_FEPS` 取（112），不再统计打印的 `Slack : -` 行**；r1 真实计数是 330。
- 三次综合（round2 额度 3/3，终身 6/6 用尽，无第 4 次、未自扩额度）：
  run1 **277** 端点 / WNS −1.483 / TNS −255.655（最差路径起点在 harness 捕获产生器）；
  run2 **112** 端点 / WNS −0.637 / TNS −69.776（绑定为 G2 证据）；
  run3 **112** 端点 / WNS −0.637（ERAM 行缓冲实验，TD 未接受 `ram_style`，netlist 与 run2 相同）。
  每次的 flow.status/run.log/gate.qor/报告分别留存在 `INT.P4/td/syn_r2_run{1,2,3}/`；r1 证据在
  `INT.P4/td/r1-evidence/`（不与 r2 拼接）。
- route=0（G2 未通过，按门槛不布线）、bitgen=0、CWC=0、download=0、Flash=0。未写 `D:/TD/**`，
  未复用 b20 工程/计数/下载额度，未伪造 ADC/引脚/时序豁免。

## 4. manifest

```
python tools/integrated_delivery/gen_manifest_intp4.py --round 2
```

产出 `INT.P4-r2-manifest.json`：新文件/派生变体/等价 TB/候选 TB + 7 份文档哈希 + A1 只读四文件哈希 +
**10 个 img 源文件哈希** + 基础文件哈希与 diff 摘要（`source_variant_bases`）+ P1/P2/P3 各自 manifest
声明文件逐项复核（其中 `integrated_input_processing_top.v` 为 r2 显式新版本，记录 r1 旧哈希与新原因）+
TD 产物 + 回归日志 + `legacy_untracked`（2 个遗留文件："登记、未删除"）+ `legacy_dirs`（候选 `work/`
6 文件）+ `endpoint_counts`（r1 330 / r2 112）+ `stopped_modifying=true`、`drift_count=0`。
