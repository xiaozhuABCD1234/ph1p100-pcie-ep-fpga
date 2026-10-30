# PH1P100 PCIe EP FPGA

PH1P100SBG484 / TD `Release_2026.2_NL` 的 PCIe Gen2 ×2 端点。生产主线是
**IMX415 4K30 全像素 → MIPI CSI-2 → R10F → DDR3 → one-shot 推帧**，帧长 10,371,072 B。

## 构建

~~~sh
cd fpga
/opt/anlogic/TD_Release_2026.2_NL/bin/td.sh build.tcl
# 产物：ph1p_pcie_ep_top_Runs/best_result/ph1p_pcie_ep_top.bit
~~~

`build.tcl` 打开已入库的 `.al`；从零重建源列表用 `create_project.tcl`。
最近一次完整构建（1920×1088 JPEG 位流）的时序/资源见 [docs/build-status.md](docs/build-status.md)。

下载 SRAM（不写 Flash）：

~~~sh
/opt/anlogic/TD_Release_2026.2_NL/bin/bw.sh download_sram.tcl
~~~

下载后必须重启 RK3588 才会重新枚举 Gen2 ×2。同一时间只能跑一个 TD 实例。

## 位流变体

| 变体 | 入口 | 说明 |
|---|---|---|
| 生产 4K R10F | `ph1p_pcie_ep_top.al`（top = `ph1p_pcie_ep_top`） | 默认构建；SYNC/CLOSEDLOOP 参数默认关闭 |
| debug 计数 | `rtl/ep_side/debug/ph1p_pcie_ep_top_dbg.v` | 包装顶层，不在 `.al` 中，需手工换 top_module |
| closed-loop 回读 | `rtl/ep_side/debug/ph1p_pcie_ep_top_closedloop.v` | 包装顶层，不在 `.al` 中，需手工换 top_module |
| 历史 1080p/灰度 JPEG | 同一顶层用几何参数 + `c2_en` 选择 | 仓库不跟踪 `.bit`，板上位流需靠构建时间/日志对应 |

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

## 目录与证据

- `rtl/rc_side/`、`rtl/common/PCIE_REG_TABLE.v`：RC 参考/仿真资产，不参与当前 EP 构建。
- `rtl/ep_side/ddr/cam_ddr_writer.v`：旧 8 bit 写者，仅诊断/TB 参照，未实例化。
- `sim/compile_checked.f`：当前仿真源清单；`sim_do/` 是厂商 ModelSim/VCS 模板，路径不可直接复用。
- `docs/debug/`：B 路 SOF 与 4K writer 的调试分析。
- `workflow/`：历史流程记录，不参与构建。

## 几何

顶层 `ph1p_pcie_ep_top.v`：`CAMDDR_W/H=3840/2160`、`X0=Y0=0`（4K 不做 ROI）、
`CAMDDR_X_OFF=12`、`CAMDDR_SKIP_ROWS=16`（物理原点 (12,16)），
`DDR_CAM_BASE0/1=0x0100_0000/0x0200_0000`（B 路 0x0300_0000/0x0400_0000）。
要回 1080p ROI 只改这几行；`cam_r10f_writer` 的参数默认值仍是 1080p 时代的
`SKIP_ROWS=37`，顶层实例会显式覆盖，不要按默认值推断生产几何。

## 边界

- 4K30 单路已上板（29.9 fps、丢组 0）；双路 4K 不可行（单路打包已占 78%），4K+同步未验证。
- 一次 ARM 推一帧；双路时 `ARM_PAIR` 同时授权两片，PCIe 上两帧串行发送、不交错。
- `sof_timestamp/timestamp_hz` 在 4K 采集位流实测有效；JPEG 位流未单独复核。
- 位流是 SRAM 配置，掉电/重下后必须重启主机。
- 最近一次构建是 1920×1088 JPEG 位流（Setup WNS 26 ps / Hold 20 ps）；4K 采集位流是
  SWNS 268 ps / HWNS 20 ps。两者都是擦边余量，改 RTL 或约束后必须重看时序报告。
