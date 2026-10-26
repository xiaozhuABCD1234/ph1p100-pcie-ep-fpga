# T10.b10-b9-fix r1 -- result（开发角色，G2-r1 通过；G3-r1 ⚠ 部分）

- run：`20261020-0209_singleA_aplus_closedloop`；包：`T10.b10-b9-fix`（父 T10 **未**置 done）
- 开发角色：general 代行 fpga-dev；日期 2026-10-25
- 结论：**用 r0 已冻结源码重建了 1 个有效候选（8/8 源哈希与 r0 manifest 相等，无任何 RTL/参数/SDC/引脚/端口改动），
  Routed 零违例、SWNS +0.103 ns、bit/CWC/compiled.bit 自洽；完成 1 次 SRAM 下载（累计 1/2）与 1 次 180 s COM8 采集。
  板级拿到 180 个合法 v3 状态包（XOR 全对），但 `raw_pub/enc_frames/exported` 增量全为 0、无帧可解，
  卡点在相机/MIPI 链路（4 条 lane sticky 全置位、PHY 停在 sync_wait、180 s 只有 2 个 VS），不在本次候选逻辑。
  按 r1 规则记 ⚠ partial：保留候选与证据，不做第二次下载。**

## 1. 本轮做了什么（一张表）

| 包 | 门槛 | 结果 | 证据 |
|---|---|---|---|
| W2-r1 重建 | G2-r1 | **PASS** | `r0/td/build_console_b10_r1.log`、`bitgen_console_b10_r1.log`、`cwc_console_b10_r1.log` |
| W3-r1 板级 | G3-r1 | **⚠ partial**：状态包 180 个全合法；三增量 0；无帧 | `r0/board/captures_r1/**`、`r0/board/log-r1/**` |
| W1-r1-opt 定向仿真 | 可选、不计门槛 | **未做**（理由见 §8） | — |

TD 实际使用：**1 个会话、综合 1、布线 1、bitgen 1、CWC 1**（均为 r1 唯一一次，无重跑）。
下载：**1 次 SRAM（累计 1/2）**，Flash 0。

## 2. 源冻结复核（不改 RTL）

8/8 与 `CANDIDATE-MANIFEST-b10-b9-fix-r0.json` 逐项相等（`mk_manifest_b10_r1.py` 内置硬检查，任何漂移即 exit 5）：

| 文件 | SHA256 |
|---|---|
| `changed-src/a1_uart_export.v` | `ff0ce16d6892c5339d806fbfff23a26e373e5d3f3ddf8a6156488f8479f0a7e1` |
| `changed-src/camera_a1_uart_top.v` | `612d42a59cb1c304cd5446991ee3fe001402a1bcfbbf3b800584997d0590b22f` |
| `changed-src/a1_ddr_slot_store.v` | `86d626465dc8d0643a7bb62e952e79ee89215c2e0c02719fc348a04c4363ed84` |
| `changed-src/a1_raw_crop.v` | `33a6fee77fd1aa67a31cacf26dd5530e5e2ea474ee655cbd5f1d98d887c5d72d` |
| `changed-src/cam_diag_mailbox.v` | `352af7c85094ea99b575e99da952af8d33871352140e4c6efddff9e6c2407278` |
| `changed-src/a1_deflate_core.v` | `6797db053cfc47497540d6345e3a46b7e79cc1d34fa25da5a4c501505fbf35bb` |
| `td/src/p2_ddr_bridge.v` | `b9e83481e3d3450b4d2a9d03812cbb1f14189fe80749e0f712aa8585cddfd5f4` |
| `td/src/p2_a1_board_top.v` | `98d6c446bcee4fedb483792e229f4a672bd78e3b36f6bfa91f08f1c9c423441f` |

- `camera_a1_uart_top.v` L156 = `wire [39:0] crop_pix;`（40 bit）确认，且该文件是 r1 综合的实际输入。
- 该文件里的 `// T10.b10 R1:` 注释块是 r0 **已回退**尝试的历史注释；**本候选没有任何 R1 功能修复**，
  为保住哈希绑定**未做注释清理**。
- `a1_uart_export.v` / `p2_ddr_bridge.v` / `p2_a1_board_top.v` 与 r0 完全相同；`changed-src` 六个文件全部未动。

## 3. r0 归档（复制/改名，未删除任何目录）

- 新增 `r0/td/r0-build-evidence/`：`s3/`（s3 根目录报告全量副本）、`s2/`（s2 报告，带 `s2-` 前缀，含 syn/phy run.log）、
  `b9-baseline-reports/`（`candidate_*.rpt`，时间戳 04:50 属 b9，**不是** r0/r1 证据，已在 `INDEX.md` 注明）。
- `a1_board_Runs` → `a1_board_Runs_r0s3`；`a1_board.al` → `a1_board_r0.al`（单目录/单文件改名）。
- 预检确认 `a1_board.bit` / `a1_board.cwc` / `cw/` 在重建前**不存在**，`cw.b9-baseline-copy/` 只读保留。

## 4. G2-r1（工程门槛）：PASS

| 项 | 门槛 | 实测 | 判定 |
|---|---|---|---|
| Routed SWNS | ≥ +0.05 ns | **+0.103 ns** | PASS |
| Routed STNS | 0 | **0.000 ns** | PASS |
| Routed HWNS / HTNS | ≥0 / 0 | **+0.020 ns / 0.000 ns** | PASS |
| 时序违例端点 | 0 | **0 / 24665** | PASS |
| Period check WNS | ≥ 0 | **+2.200 ns** | PASS |
| 综合 SWNS / STNS | ≥0 / 0 | **+0.273 ns / 0.000 ns** | PASS |
| 组合环 / 无时钟引脚 | 0 | `check_timing`：**0 combinational loops、0 无时钟引脚、0 多时钟驱动** | PASS |
| 资源 vs b9 | 差 ≤5%、ERAM 不增 | 见下表，最大差 -0.30%、ERAM 102=102 | PASS |
| bitgen / CWC | 各 1 次 | 1 / 1，`P2_CANDIDATE_BIT_GENERATED_NO_DOWNLOAD`、`P2_MATCHING_CWC_EXPORTED_NO_DOWNLOAD` | PASS |
| bit 与 `cw/compiled.bit` | 字节相同 | **相同**（5,224,022 B，同 SHA256） | PASS |

`P2_SYN_SWNS=0.273 P2_SYN_STNS=0.000 P2_SYN_SLICE=18264 P2_SYN_ERAM=72 P2_SYN_REG=18856`
`P2_ROUTED_SWNS=0.103 P2_ROUTED_STNS=0.000 P2_ROUTED_HWNS=0.020 P2_ROUTED_HTNS=0.000 P2_ROUTED_VIOL_EP=0 P2_ROUTED_TOTAL_EP=24665`
`P2_BITGEN_STA_SETUP=0.103/0.000 HOLD=0.020/0.000 PERIOD=2.200`（period 为正，即无 period 违例）
STA coverage 97.10%，`Constraint File = .../r0/td/p2_board.sdc`。

### 4.1 资源三方对照（同 device PH1P100SBG484-3）

| 版本 | syn slice | syn reg | syn ERAM | routed slice | routed reg | routed lut6 | routed ERAM |
|---|---:|---:|---:|---:|---:|---:|---:|
| **r1（本候选）** | 18,264 | 18,856 | 72 | **24,368** | **28,004** | **19,695** | **102** |
| b9 baseline | 18,281 | 18,859 | 72 | 24,405 | 28,008 | 19,755 | 102 |
| r0 s3（1-bit crop_pix，无效） | 9,793 | 10,558 | 28 | 12,557 | 14,946 | 9,958 | 43 |

- r1 与 b9 的差：slice **-0.15%**、reg -0.01%、lut6 -0.30%、ERAM 持平 → 满足 ≤5%/ERAM 不增。
- 反证价值：r0 的 s2/s3 网表规模只有一半（ERAM 43 vs 102），与“`crop_pix` 被声明成 1 bit、整条像素通道塌缩”一致；
  r1 的资源回到 b9 量级，说明 r1 综合的确实是 40 bit 通道的完整设计。
- `#dsp=0`、`#RAMs=102`、`#DRAMHARDCON=85` 与 b9 完全一致。
- CDC：TD 的 `report_cdc` 在本版本**不存在**（`invalid command name "report_cdc"`，与 r0/b9 相同，记 `cdc_unavailable`）；
  以 `check_timing` 与 `report_clock_utilization` 代偿：0 组合环、0 无约束时钟引脚、0 多时钟驱动，本候选无时钟/复位结构改动。
- `USR-6144 CRITICAL-WARNING ... pclkx5 742.5 vs 742.4 MHz`：b9 构建日志同样出现 1 次，属既有 PLL 量化告警，非新增。
- `routed_netlist.v` 中 `crop_pix` 名称已被 TD 展平（grep 0 命中），故不以网表名做 40 bit 结论；40 bit 由源哈希 + r0 P1 三黄金
  （`full_grad` 真实 1920×1080 逐字节一致）保证。

### 4.2 候选绑定（SHA256）

| 产物 | 长度 | SHA256 |
|---|---:|---|
| `r0/td/a1_board.bit` | 5,224,022 | `ba5fb801ba7b8821655443631451f8dedcd6c2406cd9b44ea7e3ba12a8329e72` |
| `r0/td/a1_board.cwc` | 110,168 | `fc7375b14a25c0707b1142b634046bdb76fcf3f2e338821f5b685267301487d9` |
| `r0/td/a1_board_inst.bid` | 96,813 | `fef4e759bbcadb283dd71ba914532578427b1542f8638e09416978288384fb65` |
| `r0/td/cw/compiled.bit` | 5,224,022 | `ba5fb801...`（**与 a1_board.bit 逐字节相同**） |

`CANDIDATE-MANIFEST-b10-b9-fix-r1.json`（含 `previous_manifest` 的 SHA256）与 `r0/artifact-hashes-r1.txt` 在板测前后各生成一次；
**r0 manifest 全程未改写**。

## 5. G3-r1（板级门槛）：⚠ partial

### 5.1 执行顺序（严格“先下载、后开 COM8”）

| 步骤 | 时间 | 结果 |
|---|---|---|
| COM8 空闲探测（open/close） | 13:41:38 | `COM8_OPEN_OK` / `COM8_CLOSED_OK`，无 hwserver、无捕获进程 |
| SRAM 下载（COM8 关闭） | 13:42:51 → 13:43:30（38.6 s） | `B10_DL_DEVICE=PH1P100`、`PRG-2014 : Chip validation success`、**`B10_DL_OK mode=jtag(sram)`** |
| 释放 FTDI（结束 hwserver） | 13:43:45 | hwserver 进程清零，等待 3 s |
| 开 COM8 采集 180 s | 13:43:57 → 13:46:57 | 31,868 B，`wall_elapsed=180.128` |

- **下载次数：1（累计 1/2），Flash 0**；未做第二次下载。
- 需如实记录：在真正下载前有 **2 次未触及硬件的失败调用**——Tcl 找不到脚本路径（一次相对路径、一次反斜杠绝对路径被 Tcl 当转义）。
  两次日志 `download_sram_r1_badpath_no_device.log` / `download_sram_r1_badpath2_no_device.log` 均无 `hwserver`/`READ_DEVICE`/`PRG-`
  任何设备行，即 **没有打开线缆、没有传输任何比特**；修正为前斜杠绝对路径后一次成功。它们不计入下载次数，但原样留证。

### 5.2 v3 状态解析（`parse_status_v3.py --min-packets 2`，exit 0）

| 项 | 值 |
|---|---|
| 抓包字节 | 31,868（`sha256=d7ea17bb2a55d136feb7e24035a36bb423a14337f62104731c9b5f3ba94d36d8`）|
| 合法包 | **180**（177 B、ver=3、len=177） |
| bad_xor / bad_len_ver | **0 / 0**（XOR 全对） |
| skipped_bytes | 8（首个包前的半包尾巴） |
| verdict | `C`（读从未打开；写侧 begin_ok=0、wr_beats=0） |

首/末与增量（末−首）：

| 字段 | 首 | 末 | 增量 | 门槛 |
|---|---:|---:|---:|---|
| `raw_pub` | 0 | 0 | **0** | >0 ✗ |
| `enc_frames` | 0 | 0 | **0** | >0 ✗ |
| `exported` | 0 | 0 | **0** | >0 ✗ |
| `cap_frames` | 0 | 0 | 0 | — |
| `crop_roi_frames` / `crop_groups` | 0 | 0 | 0 | — |
| `crop_short` | 0 | 2 | 2 | — |
| `crop_geom_err` / `errors` | 0 | 0 | **0 / 0** | 无新错误 |
| `cam_frame_rises` / `falls` | 0 | 2 | 2 | 180 s 只有 2 帧 |
| `cam_pix_beats` / `cam_line_rises` | 0 | 0 | **0 / 0** | 无像素进入 |
| `cam_sysstat`（电平） | 3869 | 3869 | — | `lane_sticky=0xF`（4 条 lane 全置位）、cfg_done/pll_locked/cfg_rst_n=1 |
| `cam_phystat`（电平） | 494 | 494 | — | `sync_wait=1`、`in_frame_now=0`、`vsync_now=0` |
| `cam_last_frame_cycles` | 0 | 16777215 | — | 24 bit 计数器饱和 |

**解码**：`exported` 增量为 0，按规则本可不解码；为留下显式反证仍执行一次
`decode_frame.py` → `frames_ok=0 frames_bad=0`（抓包里 `A1U1` magic 出现 0 次），与 `exported=0` 自洽。
因此**没有** 44 B 头/stream CRC/zlib 的正向证据，G3 的“≥1 帧解码通过”一项**未取得**。

### 5.3 卡点定位（供下一任务，不改本轮结论）

- 数据从未进入 A1 通道：`cam_pix_beats=0`、`cam_line_rises=0`，`raw_begin_ok=0`、`raw_wr_beats=0`、`raw_slot_st=FREE`。
- 相机侧：`cam_sysstat` 的 `lane_sticky=0xF`（MIPI 4 条 lane 都有粘滞错误）、`cam_phystat.sync_wait=1` 且 `in_frame_now=0`；
  180 s 只有 2 个 VS 上升（`cam_last_frame_cycles` 饱和在 0xFFFFFF）→ 不是 1080p 正常帧率（应为 ~30 fps）。
- **与 b9 是同一现象、同一指纹**：用同一解析器重解 b9 的 `captures_b9b/com8_150s.bin`（只读对比，写入
  `r0/board/log-r1/b9_capture_reparse_for_comparison.out`）：150 包、`cam_phystat=494`、`cam_sysstat=3869`、
  `cam_pix_beats=0`、`crop_short` 增 5、verdict C —— 与 r1 完全一致。说明本轮没有把已有链路变坏，
  也没有修好这条链路；**它是 b9 之前就存在的上游条件，不是本候选引入的回归**。
- 由于 `cam_pix_beats=0`，本轮板级证据**不能**独立证明 40 bit 裁剪通道的现场正确性（只能证明“状态/UART/复位/
  计数器/帧边界仲裁在真实板卡上活着且 180 包零 XOR 错”）。40 bit 的正确性仍由源哈希 + r0 P1 三黄金承担，须如实写入残余风险。

## 6. UART/协议侧本轮新增的正面证据

- 180 s 内 **180 个 v3 包、1 Hz 稳定、零 XOR/长度错误**：B9-01（状态包与帧出队互锁）修复后，**在没有业务帧的极端情况下**
  状态机持续出包、`estate/sstate` 均停在 idle（`rd_state=R_IDLE`、`fstate=F_IDLE`），没有出现 r0 反例里的死锁形态。
- `raw_drop/cmp_drop/abort_cnt/raw_begin_deny` 全 0、`errors=0`：无假 abort/丢帧，R1 的 abort 通道未被误触发
  （真正的“丢 LAST”定向用例仍未覆盖，见 §7）。

## 7. 未覆盖 / 残余风险（不改变本轮判定）

1. **R1 丢 LAST → 孤儿 writer**：仍 `not_covered`（r0 尝试两次失败）。本轮下载/采集也没有构造出该场景（没有帧）。
2. **R3**：旧 R 晚于新 AR 到达仍无法区分（无 tag），沿用 r0 结论。
3. **40 bit 裁剪通道的板级独立性**：因 `cam_pix_beats=0`，板测不能替代仿真；不要把本轮 ⚠ 解读为“通道正确性已在板上验证”。
4. `crop_short` 每帧 +1（2 帧 → 2 次）说明裁剪模块收到的是不完整帧；与相机侧无像素一致，属同一根因。
5. 抓包首 8 字节是上一包的尾巴（`skipped_bytes=8`），属串口打开瞬间的相位，不影响 180 个完整包。

## 8. 可选 W1-r1-opt 为什么没做

`W1-r1-opt` 明确“不计门槛、只在证据落盘后时间允许时做”。本轮把剩余预算用于可验收的 G2/G3 取证与绑定；
R1 定向用例在 r0 已两次因自建相机驱动构造失败（`tb_b10_multi` 只出状态包），而当前卡点在相机/MIPI 输入侧，
重跑同一 TB 无新信息、且**不会改变** ⚠ 结论。故按预算纪律跳过，并在此显式记录，而不是伪装成已覆盖。
`r0/sim/` 全部保持只读未改。

补充事实（不属于本包证据）：r1 执行期间仓库根出现一个**并行会话**的仿真工作区
`work/b10-gap-sim-20261025-132023/`（含 `r1-loss/`、`multi-frame/` 等，时间戳 13:21–13:29），不是本开发角色创建、
也未经本包复核。若规划需要 R1/3 连续帧证据，应先确认该工作区的归属与是否可作测试输入，**不要**把它当 r1 交付物。
本包未读写该目录。

## 9. 证据索引

- 工程：`r0/td/build_console_b10_r1.log`、`bitgen_console_b10_r1.log`、`cwc_console_b10_r1.log`、
  `syn_gate_{area,timing}.rpt`、`routed_*.rpt`、`phy_*.rpt`、`params_after.tcl`、`routed_netlist.v`
- 工程归档：`r0/td/r0-build-evidence/{INDEX.md,s2/,s3/,b9-baseline-reports/}`、`a1_board_Runs_r0s3/`、`a1_board_r0.al`
- 候选：`r0/td/{a1_board.bit,a1_board.cwc,a1_board_inst.bid,cw/compiled.bit}`
- 板级：`r0/board/log-r1/{download_sram_r1.log,download_state.json,capture_com8_r1.out,parse_status_v3_r1.out,decode_frame_r1.out,b9_capture_reparse_for_comparison.out,download_sram_r1_badpath*_no_device.log}`
- 采集：`r0/board/captures_r1/{com8_180s.bin,com8_180s.dec,com8_180s.stats,status_v3.json,decoded/decode.txt}`
- 绑定：`CANDIDATE-MANIFEST-b10-b9-fix-r1.json`、`r0/artifact-hashes-r1.txt`、`r0/mk_manifest_b10_r1.py`
