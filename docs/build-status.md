# 构建状态

本文件只记录可复核的构建结果；原始 TD 日志不入库，QoR/timing 报告在本地忽略目录
`ph1p_pcie_ep_top_Runs/`。

## 最近一次构建（四路预处理 + 增益寄存器，已上板）

| 项目 | 值 |
|---|---|
| 入口 | `build.tcl`（打开 `ph1p_pcie_ep_top.al`） |
| TD | Release_2026.2 / 6.2.3.210850 |
| 时间 | 2026-10-30 21:18 |
| 位流 | `ph1p_pcie_ep_top_Runs/best_result/ph1p_pcie_ep_top.bit`，5,224,023 B（未入库） |
| SHA256 | `9c24eb7152c4239827285fc3655c73b642fa75bcf4317c7a5e66dd6088bd4a61` |
| Setup | WNS 0.004 ns，TNS 0，0 violated endpoints |
| Hold | WNS 0.020 ns，TNS 0，0 violated endpoints |
| 资源 | LUT6 29,822（41.6%）、FF 29,441（20.5%）、ERAM 160、DSP 38 |
| 流程耗时 | syn 2m20s + phy 10m19s |

上板验证：Chip validation success: PH1P100；重启后 PCIe 重新枚举 Gen2 ×2；
四路算法（灰度/高斯/HE/Sobel）均出图；`0x280/0x284` 增益寄存器生效
（0 dB→19.2 dB→30 dB 亮度单调）；硬件 JPEG 出流；RKNN 推理正常。

## 构建历史

| 时间 | SHA256 | Setup WNS | LUT6 | 说明 |
|---|---|---:|---:|---|
| 2026-10-29 23:34 | `9be1097c…` | 0.026 ns | 28,025 | 清理前基线 |
| 2026-10-30 00:55 | `6e149de1…` | 0.026 ns | 27,964 | 删 6 个未实例化模块后重建，网表等价 |
| 2026-10-30 20:22 | `d2c1be79…` | 0.101 ns | 27,964 | 新增传感器增益寄存器 0x280/0x284 |
| 2026-10-30 21:18 | `9c24eb71…` | 0.004 ns | 29,822 | 新增 Sobel 边缘检测（第 4 路并行） |

## 时序余量

Setup 余量 0.004~0.101 ns、Hold 恒 0.020 ns，属于擦边通过；clk1（187.5 MHz，
MIPI byte clk）是主要压力点。**改 RTL 或约束后必须重看 `final_timing.rpt`**，
不要把这次结果当稳定余量。Sobel 那版只用了 4 ps，再往上加逻辑前要先扩时序余量
（拆 `algo_rowwin3` 的行窗或给 3x3 加法树再插一级寄存器）。

## 已知构建告警

- `PRJ-5611`：4 个 `al_ip/*.xml` 与 `sync_offline/*.v` 的 CompileOrder 重复；
  当前可综合，但增删源文件后顺序可能漂移。`.al` 与 `create_project.tcl` 是两份
  手工同步的源清单，已经漏过一次（closedloop 两个文件），改源文件时两边都要看。
- `HDL-5373`：顶层与 `cam_r10f_writer.v` 多处 “identifier used before declaration”，
  会掩盖真正的隐式网表问题。
- `SYN-5105`：`algo_rowwin3.v` 的行缓存因同步复位无法推断为 ERAM，落到 DRAM；
  四路算法各有一份行窗，是当前主要的 LUT 开销来源，也是可优化项。
