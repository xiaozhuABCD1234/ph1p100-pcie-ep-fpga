# 构建状态

本文件只记录可复核的构建结果；原始 TD 日志不入库，QoR/timing 报告在本地忽略目录
`ph1p_pcie_ep_top_Runs/`。

## 最近一次构建（含传感器增益寄存器，已上板验证）

| 项目 | 值 |
|---|---|
| 入口 | `build.tcl`（打开 `ph1p_pcie_ep_top.al`） |
| TD | Release_2026.2 / 6.2.3.210850 |
| 时间 | 2026-10-30 20:22 |
| 位流 | `ph1p_pcie_ep_top_Runs/best_result/ph1p_pcie_ep_top.bit`，5,224,023 B（未入库） |
| SHA256 | `d2c1be795654a5912fa96d95b543aff91e652dff3bf152a00e5cb8471e6e33e9` |
| Setup | WNS 0.101 ns，TNS 0，0 violated endpoints |
| Hold | WNS 0.020 ns，TNS 0，0 violated endpoints |
| 资源 | 31,217 slices（43.55%）、160 ERAM、38 DSP |
| 流程耗时 | syn 2m18s + phy 8m01s |

上板验证：Chip validation success: PH1P100；重启后 PCIe 重新枚举 Gen2 ×2；
相机 4 lane 锁定；R10F 取帧 CRC 通过；硬件 JPEG 出流；RKNN 推理正常；
**新增的 0x280/0x284 增益寄存器实测生效**（0 dB→19.2 dB→30 dB 亮度单调，
0x00 mean 12.6 → 0x64 mean 37.0，max 26→255）。

## 构建历史

| 时间 | SHA256 | Setup WNS | 说明 |
|---|---|---:|---|
| 2026-10-29 23:34 | `9be1097c…` | 0.026 ns | 清理前基线 |
| 2026-10-30 00:55 | `6e149de1…` | 0.026 ns | 删 6 个未实例化模块后重建，网表等价 |
| 2026-10-30 20:22 | `d2c1be79…` | 0.101 ns | 新增传感器增益寄存器（0x280/0x284） |

## 时序余量

Setup 余量在 26~101 ps 之间，Hold 恒 20 ps，属于擦边通过；clk1（187.5 MHz，
MIPI byte clk）是主要压力点。**改 RTL 或约束后必须重看 `final_timing.rpt`**，
不要把这次结果当稳定余量。

## 已知构建告警

- `PRJ-5611`：4 个 `al_ip/*.xml` 与 `sync_offline/*.v` 的 CompileOrder 重复；
  当前可综合，但增删源文件后顺序可能漂移。`.al` 与 `create_project.tcl` 是两份
  手工同步的源清单，已经漏过一次（closedloop 两个文件），改源文件时两边都要看。
- `HDL-5373`：顶层与 `cam_r10f_writer.v` 多处 “identifier used before declaration”，
  会掩盖真正的隐式网表问题。
- `SYN-5105`：`algo_rowwin3.v` 的行缓存因同步复位无法推断为 ERAM，落到 DRAM；
  功能正确但占用逻辑资源，是可优化项。
