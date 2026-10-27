# 当前代码与交接入口（2026-10-27）

> **后续阶段更新**：板卡已交队友，本地仅仿真与证据整理。当前状态和分工以 [FPGA_SIM_ONLY_HANDOFF_20261027.md](FPGA_SIM_ONLY_HANDOFF_20261027.md) 为准，最新离线成果和候选见 [交接包](../handoff/fpga-sim-only-20261027/README.md)。以下正文保留原先 01:32 同步时点的来源说明，不能作为后续候选已通过的结论。

以后主要从这两个原仓库推进，均使用 `main`：

- [FPGA 主仓库](https://github.com/xiaozhuABCD1234/ph1p100-pcie-ep-fpga)：本仓，当前代码见 [rtl](../rtl/)、[约束](../constraints/)、[IP](../al_ip/)、[工具](../tools/)；工程入口为 [ph1p_pcie_ep_top.al](../ph1p_pcie_ep_top.al)、[create_project.tcl](../create_project.tcl) 和 [build.tcl](../build.tcl)。
- [RK 驱动与应用主仓库](https://github.com/xiaozhuABCD1234/ph1p100-pcie-ep-driver)：队友使用的 RK 代码仓库。

本机分别位于 `D:\fpga\repos\ph1p100-pcie-ep-fpga` 和 `D:\fpga\repos\ph1p100-pcie-ep-driver`。本次同步直接提交原仓 `main`，不创建 fork。

## 从哪里找材料

| 要找的内容 | 入口 |
| --- | --- |
| 原父工作区源码、工具与文档 | [workspace/ph1p100](../workspace/ph1p100/)，保留原相对布局 |
| 项目任务板与历史记录 | [tasks.json](../workspace/ph1p100/workflow/tasks.json)、[records](../workspace/ph1p100/workflow/records/) |
| 当前集成候选与工具 | [integrated_delivery RTL](../workspace/ph1p100/fpga/csi2/src/integrated_delivery/)、[配套工具](../workspace/ph1p100/tools/integrated_delivery/) |
| 集成 run 的计划、状态与报告 | [20261026-2138_fpga-integrated-delivery](../workspace/ph1p100/workflow/runs/20261026-2138_fpga-integrated-delivery/)，先看 [dispatch.json](../workspace/ph1p100/workflow/runs/20261026-2138_fpga-integrated-delivery/dispatch.json) |
| 队友可独立复现的 B 路真帧 | [RK A1U1 交接说明](../handoff/rk-a1u1-b18-20261026/README.md)，含样例、解码器、expected、provenance 和 SHA256SUMS |
| b18 / b20 配套下载材料 | [artifacts](../artifacts/)，每包匹配的 bit/CWC/BID 以其清单为准 |
| 工作流、技能与 OpenCode 配置 | [workflow](../workspace/ph1p100/workflow/)、[技能](../workspace/ph1p100/.agents/skills/)、[OpenCode](../workspace/ph1p100/.opencode/)；仅显式调用时启用 |

## 当前证据边界

b18 保留 B 路真实完整帧与历史解码基线。交接包用于复现真实样例，不证明当前集成候选已通过真实 PCIe、30 fps 或双路同步；物理 Bayer 相位与源像素正确性仍按对应验证结果判定。

b20 工程与仿真已有通过证据，route WNS 为 **+0.012 ns**，余量很薄；当时板卡不在，下载次数为 **0**。核对 [r0/result-r0.md](../workspace/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b20-a-timing/r0/result-r0.md) 及其绑定报告，不用较早的 dispatch 占位摘要覆盖后续实测。

集成 run 已推进至 **INT.P4**。P1 r1、P2 r0、P3 r1 已有独立综合测试报告，具体状态仍以该快照中的 dispatch、manifest 与 [test-reports](../workspace/ph1p100/workflow/runs/20261026-2138_fpga-integrated-delivery/test-reports/) 为准。INT.P4 的集成、构建及未执行项应继续按其实际报告核对；本次仓库同步不代表整机验收通过，也不执行下载。

## 快照与继续开发

原工作区 `D:\fpga\ph1p100` 的活动 run 继续原地推进，路径、角色 ID 与计数不变；本仓 `workspace/ph1p100/` 是同步时点的副本，之后的新进展不会自动进入本仓。历史文档中的绝对 D 盘路径记录来源。新任务以当前 checkout 为根，具体构建入口使用其绑定候选与路径约定。

根 `rtl/` 与快照 `workspace/ph1p100/fpga/` 分别保留当前主仓代码和父工作区候选，不能仅凭同名互相覆盖；变更前核对相应 SHA、manifest 与工程引用。原 manifest 不改写，因排除缓存或生成物而缺少的归档项由同步清单说明。

本次逐文件来源、目标、SHA、体积与时间见 [同步 manifest](sync-20261027-manifest.json)；未入库的 TD 数据库、波形、缓存、重复大向量等见 [排除清单](sync-20261027-exclusions.json)；同步核对结果见 [verification](sync-20261027-verification.json)。bit/CWC/BID 按包保存，本次同步不操作硬件。

下方及其他历史 README 的目录、操作与阶段结论保留追溯，当前入口以上述说明及绑定证据为准。
