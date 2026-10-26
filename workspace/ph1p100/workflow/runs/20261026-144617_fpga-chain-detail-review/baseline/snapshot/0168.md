# result — T10.b15-ddr-pace r0

| 项 | 值 |
|---|---|
| task_id | `T10.b15-ddr-pace` |
| run | `20261020-0209_singleA_aplus_closedloop` |
| 父任务 | T10 **保持 blocked**（本包不关闭 T10） |
| 结论 | **sim/build 全过；板级 `H4_UNRESOLVED`**（读通路仍每尝试少回 1 个 R，`enc/exported` 仍为 0） |
| 候选 | `r0/td/a1_board.bit`（1 bitgen + 1 CWC，`SWNS +0.012 ns`，0 违例） |
| 下载 | 1 次 SRAM（`B15_DL_OK`），COM8 150 s，**无第二次** |

## 1. 改动（只 1 个 RTL）

`r0/changed-src/p2_ddr_bridge.v`：`BFF1A358…49731` → `EB9DF41F…954E3`（`r0/rtl-diff-r0.patch`，127 行变更）。
R1 `ar_busy` 仅 `rvalid&&rready&&rlast` 清零；R2 `paxi_arvalid` 追加 `rf_path_empty`
（RF 占用 0 + skid 空，Gray pop 计数 2FF 跨界）；R3 `paxi_rready = 1'b1`；R4
`rf_push = rvalid && rready && ar_busy`；R5 b13 的 8192/2 次重试/70000/65536/purge 语义逐条保留。
其余 10 个 RTL、`p2_board.sdc`、`board_p2.adc` 与 b13 r1 **逐字节相同**（manifest 记录）。

## 2. W1 事实（`r0/diag/paxi-read-facts.md`）

**L_max = 1**：PAXI 端口无 length 字段（`axi_arlen` 在未生成的 AXI 变体里计数为 0）；
板级 b14 r0 `r/ar = 17,200,031/17,213,681 = 0.99921`（L≥2 时 r 必 ≥2·ar）；
`ar−r = ar−rlast = 13,650 =` 尝试数。RF 保持 16 深，**未改 ADDR_BITS**。

## 3. 仿真（`r0/sim/sim-results-b15-*.json`）

| 用例 | 结果 | 关键数字 |
|---|---|---|
| P1 micro8x2 / mid64x8 / full_grad | **PASS** | 三黄金压缩字节逐字节一致 |
| S1 正常整帧（3864×2192→972/556→1920×1080） | **PASS** | `pix_beats 2,117,472`、`line_rises 2,192`、`frame_rises 1`、`crop_groups 518,400`、`raw_len 2,592,000`、`enc=exported=1`、`timeout=retry=giveup=0`、`ar=r=rlast=210,685`、`max_os=1`、`rf_ovf=0`、`rready_low=0`、`max_rf_level=1`、四 CRC+zlib |
| S2 丢 1 R | **PASS** | `exported=1 timeout=1 retry=1 giveup=0`，`stale=0`，`purge_close=1`，`short_burst=0` |
| S3 连续 3 帧（64×8，含 1 次注入丢 R） | **PASS** | `exported=3 timeout=1 retry=1`，`ar=176 r=175` |
| S3 full 三帧（1920×1080） | **PASS** | `exported=3 enc=3`、`timeout=retry=giveup=0`、`raw_drop=cmp_drop=0`、`dup_words=0`、三帧四 CRC+zlib（seed 111/222/333）、三帧均 `raw_len=2,592,000`、`ar=r=rlast=632,055`、`max_os=1`、`rf_ovf=0`、`rready_low=0`、`short_burst=0`、`max_rf_level=1`、`purge_close=0`、255 个 v5 包 |
| S4 full 两帧（1920×1080） | **PASS** | `exported=2 enc=2`、`timeout=retry=giveup=0`、`raw_drop=cmp_drop=0`、`dup_words=0`、两帧四 CRC+zlib、`raw_len=2,592,000`、`ar=r=rlast=421,370`、`max_os=1`、`rf_ovf=0`、`rready_low=0`、`short_burst=0`、`max_rf_level=1`、`purge_close=0`、254 个 v5 包 |
| S5 v5 结构 | **PASS** | `packets=3 bad=0 len=241 ver=5 fields=59`，`B13_V5_RESULT pass=1` |
| S6 b12/b13 回归 | **PASS** | b12 R1 clean/loss、T7 SOF、b12 store T3–T6、b13 store clean/retry/guard/budget |
| S7a 丢 rlast 拍 | **PASS** | `exported=1 timeout=1 retry=1`，`purge_close=1 short_burst=0` |
| S7b 晚到 + 重复 R | **PASS** | `exported=1 timeout=1 retry=1`，`stale_guard=1 stale_r=2`，`ar=13350 r=13351`，重复拍未入队（`dup_words=0`）、四 CRC 通过 |
| S7c arready 压低 100 拍 | **PASS** | `timeout=0 retry=0 exported=1` |
| S7d rvalid 空 64 拍 | **PASS** | `timeout=0 retry=0 exported=1` |
| S8 并发/占用 | **PASS** | 所有用例 `max_os=1`、`ar_busy_hs=0`、`rf_ovf=0`、`rready_low=0`、`ar−rlast ≤ 1` |

## 4. 重建（`r0/td`）

| 项 | 值 |
|---|---|
| 综合（1 次） | `SWNS=0.004`、slice 18,687、ERAM 72 |
| 布线（1 次） | **SWNS=+0.012 ns、STNS=0、HWNS=+0.020、HTNS=0、Period 2.200 ns、0 违例端点** |
| 资源 | slice 24,970/71,680（34.84%）、reg 29,162、**ERAM+CWC 102/300**、DSP 0 |
| bit/CWC | 1 bitgen + 1 CWC（`P2_BITGEN_STA_SETUP=0.012/0.000 HOLD=0.020/0.000 PERIOD=2.200`，`P2_MATCHING_CWC_EXPORTED_NO_DOWNLOAD`）|
| 时序裁决 | `+0.012` 落在 dev-plan §6 的 **+0.003…+0.05** 带 → **`timing_caveat=thin_margin_+0.012`，仅诊断候选、非生产签核**（b13 r1 为 +0.023，属同一量级） |
| SDC/ADC | 与 b13 r1 逐字节相同 |

## 5. 板级（`r0/board`，先下载后开 COM8）

- FTDI `0403:6042` 在位（COM8，`FTDIBUS\VID_0403+PID_6042+AL0B99F427B`）；1 次 SRAM 下载
  `B15_DL_OK`，之后开 COM8 150 s；151 个 v5 包、`bad_xor=0`、`noise=0 B`、`sel=0`、`bit20=0`。
- **结果 `H4_UNRESOLVED`**（详见 `r0/board/H4_UNRESOLVED.md`）：
  `cap_frames +4,500`、`raw_pub +4,500`、`crop_short=0`，但
  `timeout +13,500`（3/帧）、`retry +9,000`（2/帧）、`giveup +4,500`（1/帧）、
  `enc=exported=0`；`ar − r = ar − rlast = 13,740 =` **尝试数**（每尝试恰 1 个 AR 永不被应答）；
  `stale_r = stale_guard = 0`（缺失的拍**从未**出现在 PAXI R 通道）。
- 未做第二次下载/第二次采集；未写 Flash。

## 6. 判定

- **R1–R5 的结构性目标达成且可证**：严格单笔 AR（`max_os=1`、`ar_busy_hs=0`）、
  `rready` 恒 1、每个拥有的拍必入队、RF 不溢出（`max_rf_level=1`），并在
  合规单拍模型下整帧 `ar=r=rlast=210,685`、0 超时、0 丢拍、四 CRC+zlib 通过。
- **板级根因不在 bridge 的 AR 归属/rready/FIFO**：同样 RTL 在板上仍每尝试丢 1 个 AR 的回答，
  且该回答从未到达 R 通道 → 问题在 **DDR MC/PAXI 读响应侧（或某个无法被应答的地址）**。
- 因此本包按 dev-plan §7.4 停在 `H4_UNRESOLVED`，交规划决定后续（不再自行下载/改 RTL）。

## 7. 未完成 / 未测边界（诚实记录）

- `s3_full_three`（满尺寸 3 帧）已在后台**完成并通过**（`sim/cases/b15chain/s3_full_three/result.json`、
  `sim/sim-results-b15-chain-s3_full_three.json`）：`ar=r=rlast=632,055`、0 超时、三帧四 CRC+zlib。
  至此 dev-plan §5 的 S1/S2/S3/S4 满尺寸与丢拍矩阵**全部完成**。
- 未做：Flash、第二次 bit/CWC、第二次下载/第二次采集、A+/导出侧改动、SDC/时钟/几何/v5 任何改动。
- 残留：相机字段 `crop_geom_err`（cam12）非零是 b14 起就存在的 A 路几何计数问题，与本包无关，未触碰。
- 注意：`r0/sim/sim-results-b15-chain-s2_drop1.json` 是**调试期第一次运行（checker 尚未修正
  short_burst 判定）留下的 FAIL 记录，已作废**；S2 的权威结果是
  `sim-results-b15-chain-s2_drop1-s3_small_three-s7a_drop_rlast-s7b_late_dup-s7c_ar_stall-s7d_rv_gap.json`
  与 `sim/cases/b15chain/s2_drop1/result.json`（PASS）。
