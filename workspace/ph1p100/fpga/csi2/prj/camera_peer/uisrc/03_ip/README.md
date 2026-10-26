# uisrc/03_ip — 第三方 / 厂商来源代码说明

本目录下的文件**不是本工程原创**，来源与许可状态如下，修改前请先看这里。
本工程自己的 RTL 全部放在 `uisrc/01_rtl/`。

| 子目录 | 内容 | 来源 | 备注 |
|---|---|---|---|
| `mipi_phy_ph1p/` | 软 MIPI D-PHY 前端（自写） | **本工程原创** | 依据 TD 自带 `ip/depot/MIPI_DPHY_1.0/MIPI_DPHY/RTL/rx_phy_soft_iserdes_dyn_rtem.v` 的 PH1P 分支写的：IBUF_DIFF + HR_ISERDES(DDRX4) + 动态 IDELAY |
| `mipi_csi_2/` | CSI-2 包层、字节对齐、IDELAY 眼图扫描 | 米联客 AFC03_IMX415_PCIE_X1 例程（`uisrc/03_ip/mipi_csi_2/`） | `mipi_csi2_rx_ph1p.v` 是本工程为适配软 PHY 重写的顶层；其余为原样复用 |
| `ui_imx415_cfg/` | IMX415 寄存器表 + I2C 主机 | 同上（`uisrc/03_ip/ui_imx415_cfg/`） | 201 条寄存器表，支持 1080p/4K/720p 三档 |
| `ui_pll/` | PLL IP（137.5MHz 像素 + 687.5MHz 串行） | TD IP Catalog 生成 + 米联客 `25_rgb2hdmi_out` 例程的参数 | `.params_ui_pll.txt` 记录全部参数，可用 `set_property <值> <名> <对象>` 改 |
| `vtc/`, `tpg/` | 视频时序发生器 / 测试图发生器 | 米联客 `11_1_基础篇/25_rgb2hdmi_out` | 器件同为 PH1P100SBG484，可直接复用 |
| `alip/ui_HDMI_TX/` | HDMI TX IP（DEVICE="PH1P"） | 同上 | 含一段加密 RTL（`hdmi_tx_controller_wrapper.enc.v`），TD 直接综合，不可读 |

## 使用注意

- **管脚约束不能照抄例程**：例程器件可能不同、板卡更不同。本工程的约束全部来自
  `03_管脚定义表/*.xlsx` + 底板原理图 + 子卡原理图，并已上板实测（见根目录 README）。
- **TD 不会把大 reg 数组推断成 ERAM**：`csi_rx_*` 里的 FIFO 是小尺寸（LUT 推断没问题），
  但要做几百 KB 的帧缓存必须显式例化 `PH1P_LOGIC_ERAM`（工程内 `frame_buf_eram.v` 是模板）。
- 这些文件保持原样，改动请在自己的模块里做包装，避免以后无法和例程对比。
