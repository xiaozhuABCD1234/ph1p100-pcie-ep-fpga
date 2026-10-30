# 构建状态

本文件只记录可复核的构建结果；原始 TD 日志不入库，QoR/timing 报告在本地忽略目录
`ph1p_pcie_ep_top_Runs/`。

## 最近一次构建（清理后重建，已上板）

| 项目 | 值 |
|---|---|
| 入口 | `build.tcl`（打开 `ph1p_pcie_ep_top.al`） |
| TD | Release_2026.2 / 6.2.3.210850 |
| 时间 | 2026-10-30 00:55 |
| 位流 | `ph1p_pcie_ep_top_Runs/best_result/ph1p_pcie_ep_top.bit`，5,224,023 B（未入库） |
| SHA256 | `6e149de166e05085de6539c2fd8dcdcfe613c4896ce8c5bb77c8cd4e57f5bdde` |
| Setup | WNS 0.026 ns，TNS 0，0 violated endpoints |
| Hold | WNS 0.020 ns，TNS 0，0 violated endpoints |
| 资源 | 31,217 slices（43.55%）、160 ERAM（53.33%）、38 DSP（17.27%） |
| 流程耗时 | syn 2m37s + phy 9m11s |

这次构建是**删掉 6 个未实例化模块后的首次全流程构建**，时序与清理前一致
（SWNS/HWNS 都是 26 ps / 20 ps），随后已下载到板上验证：Chip validation success:
PH1P100，PCIe 重新枚举为 Gen2 ×2，相机锁 4 lane，取帧 CRC 通过。

对比：清理前 2026-10-29 23:34 的位流 SHA256 为
`9be1097c288fc184dfc8ff58770635cb8e8a2e428919033550b2cc7c1dd3e6d9`（同尺寸），
说明删除死代码不改变功能网表。

## 时序余量

Setup WNS 只有 26 ps、Hold 20 ps，属于擦边通过；clk1（187.5 MHz，MIPI byte clk）
是主要压力点。**改 RTL 或约束后必须重看 `final_timing.rpt`**，不要把这次结果当稳定余量。

## 已知构建告警

- `PRJ-5611`：4 个 `al_ip/*.xml` 与 `sync_offline/*.v` 的 CompileOrder 重复；
  当前可综合，但增删源文件后顺序可能漂移。
- `HDL-5373`：顶层与 `cam_r10f_writer.v` 多处 “identifier used before declaration”，
  会掩盖真正的隐式网表问题。
- `SYN-5105`：`algo_rowwin3.v` 的行缓存因同步复位无法推断为 ERAM，落到 DRAM；
  功能正确但占用逻辑资源，是可优化项。
