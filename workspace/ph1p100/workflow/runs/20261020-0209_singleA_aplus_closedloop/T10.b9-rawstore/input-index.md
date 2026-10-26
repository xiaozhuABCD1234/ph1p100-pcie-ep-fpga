# T10.b9-rawstore 输入索引

- run: `20261020-0209_singleA_aplus_closedloop`
- task: `T10.b9-rawstore`（本任务新 ID，接续 T10.b8-crop-geom，不新造 run）
- 规划时间：2026-10-25
- batch_size：1（1 开发，1 综合测试者覆盖全部包）

## 1. 用户本轮原话要点（冻结依据）

1. 冻结 `T10.b9-rawstore`：核对 crop 输出格式（W=1920/H=1080、4 px/beat、10-bit 打包）与 raw 路径（capture_async_fifo / a1_ddr_slot_store / a1_ddr_arb2）：每行 beat 数 480、store 256-bit 字数/帧长 W*H*5/4=2,592,000 B 是否整除；帧完成条件（sof/last/行计数/字节计数）；ddr_rdy、写通道、slot 发布/丢弃。
2. 状态包 v3 增加 raw store 计数（wr_beats/wr_words、wr_ptr、state、ddr_rdy、slot_pub/drop、frame_done/abort），必要时加 A+ 读侧计数。
3. 有明确 bug 本轮直接修，否则先诊断下一轮修。
4. 重建 P2；Routed 零违例、WNS≥+0.05；1 bitgen + 1 CWC；**1 次 SRAM 下载**，先开 COM8 再下载，采 90 s。
5. 门槛：状态包能回答"raw 写入卡在哪一拍/为什么没发布"；若修复后 raw_pub>0、enc_frames>0、exported>0，则按 44 B 头 + CRC + zlib 解码。
6. 预算：开发 120 min/60 calls；TD 3 会话、综合 ≤2、布线 ≤1、bitgen 1、CWC 1、下载 1；失败即停，不二次下载。
7. 更新 dev-plan/handoff/user-summary/final-summary，写 dispatch。

## 2. 板级证据（b8 状态包 v2，已解析）

- 主解析：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b8-crop-geom/r0/board/captures_pwr/status_v2.json`
- 原始流：`.../captures_pwr/com8_150s.bin`（10,767 B，111 包，97 B/包，bad_xor=0）
- 复现脚本：`.../r0/board/parse_status_v2.py`、`.../r0/board/capture_com8.py`

| 字段 | first | last | delta | 判读 |
|---|---|---|---|---|
| cap_frames / crop_roi_frames | 20 | 3320 | 3300 | 裁切整帧 3300 次（out_last 计数） |
| crop_groups | 10,368,000 | 1,721,088,000 | 1,710,720,000 | = 3300 × 518,400，**整帧组数一毫不差** |
| crop_short / crop_geom_err | 0 | 0 | 0 | 无 abort、无几何错 |
| **raw_pub** | **2** | **2** | **0** | **OR=0x2：早期发布过 2 帧后永久冻结** |
| raw_drop / cmp_drop / errors | 0 | 0 | 0 | 之后既不发布也不丢弃、不报错 |
| enc_frames / exported / read_words | 0 | 0 | 0 | A+ 读侧一个 256-bit 字都没拿到 |

`cam_pix_beats`、`cam_line_rises=7,233,600`、`cam_frame_rises=3300`、I2C `cfg_done=1/NACK=0` 证明 MIPI 与整帧时序正常，问题完全在 crop 之后的 raw 落盘段。

## 3. 源码（实际生效路径）

| 文件 | 路径 | 说明 |
|---|---|---|
| crop | `fpga/csi2/src/a1/a1_raw_crop.v` | b8 已改为 3864×2192/ROI(972,556)/1920×1080，本任务不改几何 |
| A1 顶 | `fpga/csi2/src/a1/camera_a1_uart_top.v` | crop→CDC FIFO→raw slot store→A+→cmp store→导出→状态 |
| raw store | `fpga/csi2/src/a1/a1_ddr_slot_store.v` | 2 slot，MODE0=4 组/256-bit 字，EXPECT_BYTES 校验后才 publish |
| P1 仲裁 | `fpga/csi2/src/a1/a1_ddr_arb2.v` | **P2 板级不使用**（被 p2_ddr_bridge 取代），本任务不改 |
| CDC FIFO | `fpga/csi2/src/mem/capture_async_fifo.v` | 512 深，写满即静默丢（`w_ready` 在 A1 顶未接） |
| P2 顶 | `T10.b8-crop-geom/r0/td/src/p2_a1_board_top.v` | b7 起的状态导出段 |
| P2 DDR 桥 | `T10.b8-crop-geom/r0/td/src/p2_ddr_bridge.v` | 单拍 256-bit PAXI，AW/W/AF/RF 三 FIFO |
| 状态打包 | `T10.b8-crop-geom/r0/td/src/camera/uisrc/01_rtl/dbg_uart.v` | 97 B = 5 B 头 + 23×32b，v3 在此扩展 |
| 状态信箱 | `T10.b8-crop-geom/r0/changed-src/cam_diag_mailbox.v` | 64-bit 慢速信箱（v3 建议按 64b 双字扩容实例数） |
| b8 构建脚本 | `T10.b8-crop-geom/r0/td/01_build.tcl` | 已用 `Y:/` + changed-src 覆盖法，b9 沿用并改指向 |
| b8 候选清单 | `T10.b8-crop-geom/CANDIDATE-MANIFEST-b8-crop-geom-r0.json` | b9 基线哈希来源 |

## 4. b8 产物（本任务基线，只读）

- `T10.b8-crop-geom/r0/changed-src/{a1_raw_crop.v, camera_a1_uart_top.v, a1_uart_export.v, a1_deflate_core.v, cam_diag_mailbox.v}` —— b9 改动的基线版本。
- `T10.b8-crop-geom/r0/sim/{a1_ddr_model.v, tb_p1_chain.v, run_sims.py, sim-results-b8.json}` —— P1 三黄金样例与 DDR 行为模型可直接复用。
- `T10.b8-crop-geom/r0/td/src/**` —— b9 的 P2 源码基线（p2_a1_board_top.v / p2_ddr_bridge.v / dbg_uart.v 等）。
- `T10.b8-crop-geom/r0/board/{capture_com8.py, parse_status_v2.py, download_sram_b8.tcl}` —— 采流/解析/下载脚本基线。

## 5. 采用版本与未决事项

- 采用：b8 的 crop 几何与 P2 工程结构；v2 包 23 字段顺序作为 v3 前 23 字段（版本字节升 3）。
- 未决（由本任务 v3 计数回答，不再靠猜）：
  - D1 raw 读打开了吗？（`a1_can_start` 四项与 `rd_open` 计数）
  - D2 打开了但 DDR 没回数据？(`ar` 拍数/握手数 vs `rvalid` 拍数)
  - D3 还是写侧根本没开始？(`wr_begin_ok/deny`、`wr_beats`)
- 已知不属于本任务：crop 几何、MIPI/I2C 配置、图像帧头/CRC 格式、UART 分频、SDC/引脚、Flash。
