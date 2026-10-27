# T10.b13-ddr-retry r1 — result（开发自检，非综合测试结论）

- 日期：2026-10-25；run `20261020-0209_singleA_aplus_closedloop`；包 `T10.b13-ddr-retry` r1
- **status = blocked**（工程侧本轮完成：最终 RTL 的新 bit/CWC 已产出并与 RTL 哈希绑定；
  板级仍被相机链路挡住：`pix_beats=0`，A1 读通路未启动，丢 R 重试无法在硬件上验收）
- 父任务 T10 仍 blocked；本包不关闭 T10
- 本轮目标：用 **当前 `r0/changed-src`** 重建 1 次综合/布线/bitgen/CWC，绑定最终 RTL，再 1 次 SRAM 下载 + COM8 150 s

## 1. 重建输入（最终 RTL，未改一行）

- 源集：`r0/changed-src/`（10 文件，其中 b13 改过的 6 个：`a1_ddr_slot_store.v`、`a1_ddr_arb2.v`、
  `p2_ddr_bridge.v`、`camera_a1_uart_top.v`、`p2_a1_board_top.v`、`a1_uart_export.v`；其余 4 个与 b12 逐字节相同）。
- 关键点：`camera_a1_uart_top.v` = `acc1eff329aa295d01b16123581fee48ef49d444efdce3b7fe62214555517405`
  （含 1080p 孤儿字 `orphan_drain` 修复，即 r0 最后一次修改后的版本）。
- `run_build_r1.ps1` 在启动 TD 之前对这个哈希 fail-closed；`r1/td/01_build.tcl` 与重建后的 `a1_board.al`
  都把 6 个改动源（含 `p2_a1_board_top.v`/`p2_ddr_bridge.v`）指向该目录，构建输入无歧义。
- r1 **没有改任何 RTL/脚本/约束**，因此 r0 在 22:14–22:46 产生的仿真证据与本次构建的源集完全同哈希。

## 2. 构建（1 次综合 + 1 次布线）

| 项 | 值 |
|---|---|
| 综合 | SWNS=**+0.205**，STNS=0.000，slice 18,679，ERAM 72，reg 19,923 |
| 布线 | **SWNS=+0.023 / STNS=0.000 / HWNS=+0.020 / HTNS=0.000，0 违例 / 26,339 端点** |
| 资源 | slice 24,843（34.66%），slice reg 29,113，LUT6 19,804，**ERAM 102（≤300）** |
| 裁决 | 0 违例且 +0.023 ≥ +0.003 门槛 → 允许 bitgen；未达 ≥+0.05 目标，`timing_caveat=thin_margin_+0.023`（诊断候选，非生产签核） |
| 计数 | 综合 1、布线 1、TD 会话 2（build 1 + bitgen/CWC 1）、bitgen 1、CWC 1、下载 1、Flash 0 |

日志：`r1/td/build_console_r1.log`、`r1/td/build_driver_r1.log`、`r1/td/bitgen_console_r1.log`、`r1/td/cwc_console_r1.log`。

## 3. 候选与哈希

| 项 | SHA256 |
|---|---|
| bit | `aa7f75698529a56ae6ffe66d59ab1bc619b6f64a22733610b5359524272f6a5e` |
| CWC | `0bef6442601e1b8a27546df82708ef5da68b30665e9a72ab0e15cea7551a9516` |
| BID | `fc8b964dc546d0a1dbc0393afc15e5fbf1b30a4850adf58bf80cb61565713913` |
| `cw/compiled.bit` | `aa7f7569…6a5e` — **与父 bit 逐字节相同** |
| `cw/compiled.cwc` | `0bef6442…9516` — **与父 CWC 逐字节相同** |

- `02_bitgen.tcl` 自带 fail-closed STA：`SETUP=0.023/0.000 HOLD=0.020/0.000 PERIOD=2.200` → 通过后才 bitgen。
- `03_cwc.tcl` 校验 `phy_eram` 映射、无残留 `logic_eram`、且 compiled 与父件一致 → `P2_MATCHING_CWC_EXPORTED_NO_DOWNLOAD`。
- r0 的"过期候选"caveat 由此解除：本轮的 bit/CWC 就是最终 RTL 的产物。全量哈希：`r1/artifact-hashes.txt`。

## 4. 板级（先下载，后开 COM8；各 1 次）

- 预检：`VID_0403&PID_6042` 三节点 OK，`COM8` 在位（COM3/COM4 为蓝牙）。
- **1 次 SRAM 下载成功**：`B13_DL_DEVICE=PH1P100`、`PRG-2014 Chip validation success`、`B13_DL_OK`（26.6 s）；
  随后 `connect_cable -close` + 停 hwserver，**再**开 COM8。
- COM8 150 s：36,150 B、**150 个合法 v5 包（bad_xor=0）**、**A1U1 帧 0**。

| 字段 | 值 |
|---|---|
| cap_frames / raw_pub / enc_frames / exported | 0 / 0 / 0 / 0 |
| timeout / retry / giveup / stale_guard | 0 / 0 / 0 / 0 |
| A1 读通路 ar / r / rlast / stale_r / rd_wait | 0 / 0 / 0 / 0 / 0 |
| br0 / src0 | 41 / 1024（未变） |
| cam clk_tgl / pkt_tgl | 12,601→519,036 / 6,472→257,917（MIPI 有活动） |
| cam vs_tgl / frame_rises / frame_falls | 0→22 / 0→22 / 0→22 |
| **cam pix_beats / line_rises** | **0→0 / 0→0** |
| crop_short / last_frame_cycles | 0→22 / 0→16,777,215 |
| phystat / sysstat | 494 / 3869 |

- 判定：`cap_frames=0` 且 `pix_beats=0`、`line_rises=0` → **相机链路仍无有效视频行**；
  A1 读通路从未启动，`timeout/retry/giveup` 全 0，因此本包目标故障**未被触发**。
  按本轮指令"若相机仍 `pix_beats=0`，停止并留证（不第二次下载）"：**未做第二次下载、未重采、未写 Flash**。
- 与 r0 对比：两个不同 bitstream、同一现象（r0：`pix_beats=0`，`frame_rises 0→1`；r1：`frame_rises 0→22`），
  共同指向相机/MIPI 前端与会话条件，而不是本包的 DDR 重试改动。

## 5. 为什么停在这里

1. 工程侧 r1 的目标已达成：最终 RTL 有唯一、哈希绑定的 bit/CWC，0 违例，`cw/compiled.*` 与父件一致。
2. 板级验收前提（相机出像素）不满足；按契约不得第二次下载、不得为"再试一次"扩预算。
3. 功能证据仍为 r0 同哈希 RTL 的全量仿真（chain/fullchain/store/status/regress-final/main2 + P1 三黄金），
   本轮未重复跑仿真（RTL 未变），由综合测试者决定是否独立复跑。

## 6. 交规划/下一轮

- 需要用户侧先解决相机链路（供电/排线/上电时序/传感器配置），否则板级永远进不到 A1 读通路。
- 相机恢复正常后：申请**新的下载授权**（本质上是 r2 的 1 次 SRAM 下载），直接下载 `r1/td/a1_board.bit`
  （哈希 `aa7f7569…6a5e`，已绑定最终 RTL），COM8 150 s，看 `cap/exported` 增量与 `timeout/retry/giveup/stale_guard`。
- 复测清单见 manifest `retest_required`；`timing_caveat=thin_margin_+0.023` 需由规划决定是否接受为诊断候选。
