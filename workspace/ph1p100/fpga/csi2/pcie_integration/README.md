# fpga/csi2/pcie_integration — T07.rk-align-backend 交付树

本目录是 **T07.rk-align-backend**（run `20261017-011744-rk-fpga-align`）在 2026-10-17 新建的独立后端交付树，
归属该 run 的唯一开发包；**不是**旧主线、**不是** peer 仓库、**不是** 002820 候选。
旧 PAXI/预览/1080p60 工程与 `D:\TD\work\...` 全部只读未动。

## 目录

| 路径 | 内容 |
|---|---|
| `peer-ref-2a4b253/` | peer FPGA 冻结快照（2a4b253）**原样副本**，仅作逐文件来源比对用（168 文件） |
| `rtl/` | 实际交付的 RTL：peer 文件（部分被本包修改）+ 本包新增/引入的 checked 包层与 wrapper |
| `rtl/checked/` | 本方 checked CSI（`csi_rx_packet_integrity.v`、`csi_rx_10bit_unpack_checked.v`，从 `fpga/csi2/src/csi` 逐字节引入） |
| `constraints/` | peer 的 `.adc/.sdc`（未改） |
| `al_ip/` | 匹配版本的 IP（pcie_ep_core / pcie_pll_ep / ram / ddr3_mc_0）xml + 生成物（未改） |
| `sim/` | G1 测试台 + 编译清单（`compile_checked.f`）+ 厂商 IP 端口桩 |
| `docs/` | 交付树自己的短说明（本文件的补充） |

## 与 peer 的差异（权威清单在 run 的 `backend/change-report.md` 与 `backend/source-provenance.json`）

* 生产 RTL 共 157 项：142 项与 peer 逐字节相同；**7 项被本包修改**（`ddr_frame_pusher.v`、
  `ep_bar_win.v`、`cam_ddr_writer.v`、`img_frame_src.v`、`ph1p_pcie_ep_top.v`、`pcie_ep_engine.v`、
  `ui_cfg_imx415.v`）；6 项新增；2 项是本地 checked 源逐字节复制。
* 修改的原因与语义见 `backend/change-report.md` §1/§2；其中 `ui_cfg_imx415.v` 只改声明顺序
  （TD 能过、ModelSim 不能过的隐式网问题，行为不变）。

## 构建/仿真的唯一入口

`tools/pcie_integration/{run_sim.ps1, run_td.ps1, td/*.tcl, gen_manifest.py}`；
详细用法与产物位置见 run 的 `backend/build-entry.md`。

## 边界

* 本目录不含位流/flash 写入脚本，也不含任何下载动作；`sim_do/` 里的 peer 原始 TB 保留在
  `peer-ref-2a4b253/` 里（**不**复制进 `sim/`，避免把"只写不跑"的台子当已验证据）。
* 正式 RAW10 成帧/R10F/1080p ROI 属 T11 包；本包是**组合后端 + 安全门 + checked CSI 接入**。
