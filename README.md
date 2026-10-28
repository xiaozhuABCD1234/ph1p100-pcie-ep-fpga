# PH1P100 PCIe EP FPGA

PH1P100SBG484 / TD `Release_2026.2_NL` 的 PCIe Gen2 ×2 端点。生产主线是
**IMX415 4K30 全像素 → MIPI CSI-2 → R10F → DDR3 → one-shot 推帧**，帧长 10,371,072 B。

## 构建

~~~sh
cd fpga
/opt/anlogic/TD_Release_2026.2_NL/bin/td.sh build.tcl
# 产物：ph1p_pcie_ep_top_Runs/best_result/ph1p_pcie_ep_top.bit
~~~

下载 SRAM（不写 Flash）：

~~~sh
/opt/anlogic/TD_Release_2026.2_NL/bin/bw.sh download_sram.tcl
~~~

下载后必须重启 RK3588 才会重新枚举 Gen2 ×2。同一时间只能跑一个 TD 实例。

## 源码入口

| 路径 | 作用 |
|---|---|
| `rtl/ep_side/ph1p_pcie_ep_top.v` | 生产顶层：几何参数、CSI、writer、DDR、pusher、同步门控 |
| `rtl/ep_side/img/ep_bar_win.v` | BAR0 寄存器面（含 RKA1 与 0x1E0 同步） |
| `rtl/ep_side/ddr/cam_r10f_writer.v` | RAW10 → R10F，A/B 各一片 |
| `rtl/ep_side/ddr/ddr_frame_pusher.v` | DDR3 → 主机 MWr，one-shot/HELD/ACK |
| `rtl/ep_side/ddr/ddr_rd_arb2.v`、`utx_arb2.v` | 两片 pusher 的 DDR 读仲裁与 TL 帧级仲裁 |
| `rtl/ep_side/cam/sync_offline/` | A 主/B 从启动序列、SOF 配对、失锁清理 |
| `rtl/ep_side/cam/sync_i2c_config.v`、`sync_frame_gate.v` | 同步 I2C 与帧边界门控 |
| `constraints/ph1p_pcie_case_ep.adc/.sdc` | 引脚与时序 |
| `docs/protocol/rka1-r10f-v1/` | RKA1/R10F 冻结合同与合成向量（driver 仓有同一镜像） |

## 几何

顶层 `ph1p_pcie_ep_top.v` 里一行一个量：`CAMDDR_W/H=3840/2160`、`X0=Y0=0`（不做 ROI）、
`SKIP_ROWS=37`、`DDR_CAM_BASE0/1=0x0100_0000/0x0200_0000`（B 路 0x0300_0000/0x0400_0000）。
要回 1080p ROI 只改这五行。

## 边界

- 4K 全帧通路未上板验证；`SKIP_ROWS=37` 是 1080p 时代的标定值，4K 未复测。
- 一次 ARM 推一帧；双路时 `ARM_PAIR` 同时授权两片，PCIe 上两帧串行发送、不交错。
- R10F 的 `sof_timestamp/timestamp_hz` 仍为 0；同步证据看 BAR `0x1E4/0x1E8`。
- 位流是 SRAM 配置，掉电/重下后必须重启主机。
- `workspace/`、`handoff/`、`workflow/` 是历史证据，不是当前入口。