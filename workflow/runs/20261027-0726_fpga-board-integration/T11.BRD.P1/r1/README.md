# T11.BRD.P1 — round1 工作根（repo）

本目录是 `T11.BRD.P1` round1 的**唯一新源码/仿真/证据工作根**，位于权威 FPGA 仓：

`D:\fpga\repos\ph1p100-pcie-ep-fpga\workflow\runs\20261027-0726_fpga-board-integration\T11.BRD.P1\r1\`

## 目录约定

| 子目录/文件 | 内容 |
|---|---|
| `rtl/` | 从只读快照复制的 r0 板级源码 + r1 改动的板级模块；如修 Adler，放 `rtl/a1_core_fix01/`（新候选，不改 b20 原件） |
| `sim/` | G1 TB、编译/运行脚本、仿真日志 |
| `constraints/` | `brd_board.sdc`、`ph1p_pcie_case_ep.adc` 及必要的合并结果 |
| `evidence/` | 静态检查、CDC/SDC 表、Adler 根因、负例日志、解码脚本输出 |
| `manifest-brd-p1-r1.json` | 冻结 manifest（全量 SHA256） |
| `result-r1.md` | 开发结果（本地做/未做分开） |
| `lessons-r1.md` | 可选：新根因/触发/修正 |
| 队友包（另目录） | `D:\fpga\repos\ph1p100-pcie-ep-fpga\handoff\brd-p1-r1-20261027\` |

## 只读来源（禁止直接修改）

- r0 板级源码：`handoff/fpga-sim-only-20261027/inputs/board/fpga/csi2/src/board_integration/`
- r0 板级工具：`handoff/fpga-sim-only-20261027/inputs/board/tools/board_integration/`
- P4 r2 闭包：`handoff/fpga-sim-only-20261027/inputs/board/fpga/csi2/src/integrated_delivery/` + `inputs/p4/…/r2-timing-experiment/`
- img 算法：`handoff/fpga-sim-only-20261027/inputs/p4/fpga/csi2/src/img/`
- b20 A+ core：`handoff/fpga-sim-only-20261027/inputs/p4/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b20-a-timing/r0/changed-src/`
- EP 基座：repo 根 `rtl/`、`al_ip/`、`constraints/`（若与 r0 快照 SHA 不同，优先用 `inputs/board-filelist/` 的 r0 快照并记录）
- 旧工作区：`D:\fpga\ph1p100\fpga\csi2\src\board_integration\`、`D:\fpga\ph1p100\tools\board_integration\` 仅只读对照
- r0 结果/报告/manifest：`D:\fpga\ph1p100\workflow\runs\20261027-0726_fpga-board-integration\T11.BRD.P1\`（冻结）

## 硬边界

- 只用 RTL 仿真/静态检查/证据；**不启动** TD、综合、布线、STA、bitgen、CWC、JTAG、COM、下载、Flash。
- 不 commit / 不 push；不自动联系队友。
- filelist/交接包用 repo 相对路径；不写旧 `D:/fpga/ph1p100` 绝对路径、不写 `T:`/`Y:`。
- 禁止 r3 两文件、b20 位流/CWC、改旧 run/旧报告/旧 manifest、改 `integrated_delivery/**`、`img/**`、`mem/**`、`pcie_integration/**`。
- 本地 PASS 仅指 G1+G0+G5；G2p/bit/board 一律 `teammate_required`/`awaiting_hardware`/`not_run`。

## 关键更正

- `SLOT_WORDS=81920` words × 32B = **2,621,440 B = 2.5 MiB/槽**；r0 文档“640 KiB”是算术错误，r1 用正确值。
- `SLOT_BASE_WORD=2048` → 字节基址 `0x1_0000`；store/排空/描述符/pusher 必须同基址（board 侧对 P4 `ddr_awaddr`/`ddr_araddr` 加 word 偏移，不改 P4 源）。
- 44B A1U1 头归主机/离线工具构造；槽内只存 zlib 精确字节。
