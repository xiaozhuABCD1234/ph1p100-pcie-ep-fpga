# INT.P4 TD 证据索引与卫生说明（r3，2026-10-27）

本目录只放 TD 工程与证据。**每个 run 使用独立子目录**，不要在同一目录续跑综合。

| 目录/文件 | 状态 | 说明 |
|---|---|---|
| `r3_run1/` | **r3 权威（本轮 G2 证据）** | 独立工程目录：`01_synth.tcl`（``tools/integrated_delivery/td/01_synth.tcl` 原样副本）、`integrated_core.sdc`、`syn_flow.status`、`syn_gate_timing.rpt`、`syn_gate_area.rpt`、`td_01_synth_console.log`、`td_20261027_060141.log*`、`int_p4_Runs/syn_1/`。Setup `NUM_FEPS 0`、WNS +72ps、TNS 0ps（17220 endpoints）、ERAM+CWC 39/300、IO 42/286、reg 6004。 |
| `r3_run1-fileset.sha256` | r3 文件集清单 | 27 项（25 Verilog 源 + tcl + sdc）逐文件 SHA256；`Get-FileHash` 后该清单 SHA256 = `FEDA255C64E0322F5BF18611B737A46906C8E3CC6588FBCAF26EDC65C50F8416`。 |
| `syn_r2_run2/` | **r2 权威（上轮 G2 证据）** | r2 绑定的 112 端点 / WNS −0.637ns / TNS −69.776ns 证据集，自洽完整。 |
| `syn_r2_run1/`、`syn_r2_run3/` | r2 历史 | run1 为 277 端点版本；run3 为 `ram_style` 实验（netlist 与 run2 相同）。 |
| `int_p4_Runs/syn_1/` | **混合目录（勿单独引用）** | run2 的 `flow.status`/`gate.qor` 与 run3 的 `int_p4_gate.timing/area` 混放；判定一律用 `syn_r2_run2/` 或 `r3_run1/`。 |
| `run.log` | r1 旧日志（E5a） | mtime 03:27:15，是 r1 的运行日志（与 `r1-evidence/run.log` 同哈希 `8023b305…`，含 r1 的 HDL-5314）。与 r3 无关；r3 日志在 `r3_run1/`。 |
| `01_synth_r2run3_experiment_copy_DO_NOT_USE.tcl` | run3 实验副本（E5b） | 原 `01_synth.tcl`（7504B, 04:44:40）含两个已不存在的实验文件路径，**不可用于重跑**。正式入口：`tools/integrated_delivery/td/01_synth.tcl`。 |
| `syn_flow.status`、`syn_gate_*.rpt`、`td_01_synth_console.log`（本目录根） | r2 run2 副本 | 与 `syn_r2_run2/` 同名文件同哈希；r3 不要复用。 |
| `synth_console_r0.log`、`synth_console_r1.log`、`td_20261027_02xxxx/03xxxx/04xxxx.log` | 历史 | r0/r1/r2 会话日志，仅作历史。 |

规则：每轮 synth ≤ 配额、每次 run 独立子目录、综合前同一文件集须先过仿真并用 `r3_run1-fileset.sha256`
方式记录文件集哈希；不同 run 的文件集哈希必须不同（禁止 netlist 重复/仅改 attribute）。
