# sim_do — 厂商仿真模板（历史）

这里的 `modelsim/sim.do`、`vcs/makefile`、`tb/*.f` 来自安路 PCIe 参考设计，
**不是当前回归入口**。两个 `.f` 引用本仓库不存在的路径：

- `../../prj/case_ep/...`、`../../prj/case_rc/...`（厂商工程目录）
- `/software1/yywang/td_rel/TD_6.1.1_.../sim_release/...`（另一台机器）

这些 `.f` 已在 `.gitignore` 中显式忽略，保留仅作查阅；直接运行会报找不到文件。

## 当前可用的仿真入口

- `../sim/compile_checked.f`：checked MIPI/CSI、codec、DDR、RKA1 的 vlog 源清单。
- `../sim/run_codec_tb.sh`：JPEG codec 的 iverilog 回归。
- `../sim/tb/tb_sync_offline.sv`：同步启动序列（iverilog -g2012）。

## 本目录仍保留的独立 TB

`tb_cam_ddr_writer.v`、`tb_ddr_frame_pusher.v`、`tb_ddr_wr_arb.v`、
`tb_ep_bar_win.v` 是 iverilog 单模块冒烟测试，编译命令写在各自文件头；
它们不依赖上面的厂商 `.f`。
