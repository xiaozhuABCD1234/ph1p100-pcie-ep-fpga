# T07.rk-align-backend functional-r0 测试证据索引

测试者：functional 维度（round0），2026-10-17 04:45—04:51（+08:00）。
未修改任何候选/生产文件；本目录只含只读复算与重跑证据。

## msim/ — 冻结流程重跑（run_sim.ps1，未加任何编译开关）

| 目录 | TB | 结果 |
|---|---|---|
| tb_ddr_frame_pusher_rka1/ | tb/tb_ddr_frame_pusher_rka1.v | vlog 失败：vlog-2388（cam_ddr_writer.v:536 重复声明 p_skip_frm），exit=2；run_sim 退出码1，无 vsim.log |
| tb_ep_bar_win_rka1/ | tb/tb_ep_bar_win_rka1.v | 同上（同一编译列表） |
| tb_csi_checked/ | tb/tb_csi_checked.v（+define+MIPI_PHY_SIM_STUB） | 同上 |
| tb_ddr_wr_arb_peer/ | tb/tb_ddr_wr_arb_peer.v | 同上 |

每个目录内：`commands.log`（实际命令/退出码）、`vlog.log`（编译器输出全文）、`abs.f`（展开后的绝对路径源清单）、`work/`（失败前的库文件）。
说明：首轮曾因 `-TbFiles sim/tb/...` 传参差异得到 2 个错误；随后以脚本注释同样的 `tb/...` 形式重跑并覆盖，四个目录的 vlog.log 均为更正后的干净复现（唯一错误即 vlog-2388）。

## msim-suppress/ — 隔离诊断（仅证明唯一阻塞点；**不构成判定依据**）

用 `vlog -suppress 2388`（两处声明逐字相同，语义不变）在隔离目录复跑同一 abs.f，四 TB 全部编译通过并：

- tb_ddr_frame_pusher_rka1：`ALL PASS (20257 TLPs total, 20323 accepted beats)`
- tb_csi_checked：`ALL PASS`
- tb_ep_bar_win_rka1：`ALL PASS`
- tb_ddr_wr_arb_peer：`ALL PASS`

各目录内：`cmd.log`、`vlog.log`、`vsim.log`、`run.do`、`vsim_stdout.log`、`abs.f`。
该流程偏离冻结工具链（run_sim.ps1 无此开关），只用于告诉开发"阻塞集中在何处"，不作为 PASS 证据。

## independent-summary.json

本次全部复算的机器可读汇总：manifest 240 项校验（239 匹配、1 漂移）、四 TB 冻结流程结果、补充诊断结果、证据时间线、静态抽查结论与哈希。
