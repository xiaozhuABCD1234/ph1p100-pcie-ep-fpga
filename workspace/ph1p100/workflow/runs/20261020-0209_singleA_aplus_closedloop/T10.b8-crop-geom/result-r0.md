# T10.b8-crop-geom r0 — 结果（开发角色）

状态：**blocked**（功能/工程全过，板级 G4 因相机无 payload 未达标；只用掉唯一 1 次 SRAM 下载，不二次下载）。
唯一候选：`r0/td/a1_board.bit` / `.cwc`（SHA 见 manifest）。

## 1. 结论一句话

crop 的几何根因已按实测 3864×2192 / 966 beat/行修正，并在全尺寸双帧逐字节、真实 CSI-2 流水、
965/967/短帧负例、P1 三例与 v2 状态包回归上全部通过；P2 重建 Routed 0 违例 WNS=+0.108 ns，
bit/CWC 已生成且 CWC 与父 bit 逐字节一致；但板级这次相机域**没有 payload**（`cam_pix_beats=0`），
所以 `cap_frames/raw_pub/enc_frames/exported` 仍为 0 —— 这是下载前就已存在的板级停流状态
（同一块板、b7 bit 的下载前 90 s 基线完全同态），不是 crop 仍错，也不能据此把 G4 记 PASS。

## 2. 几何推导（实测，脚本 `r0/board/derive_geometry.py`）

冻结 b7 采集 `com8_150s.bin`，用冻结的 `parse_status_v2.parse()`：

| 量 | 值 | 推导 |
|---|---|---|
| 包数 / bad_xor | 119 / 0 | 97 B v2 |
| Δframes（包 0→12） | 360 | 12 s × 30 fps |
| Δlines | 789,120 | /360 = **2192.000000 行/帧** |
| Δbeats | 762,289,943 | = 966×789,120 + 23（采样瞬时残行 <966） |
| px/beat | 4 | 5 B → 4×10 bit |
| CAM_W | **3864** | 966×4 |
| CAM_H | **2192** | 2192 |
| ROI_X / ROI_Y | **972 / 556** | (3864−1920)/2、(2192−1080)/2；%4=0、%2=0 |
| GX / OG / NGRP | 243 / 480 / 518,400 | 20 bit 足够 |
| Δcrop_geom_err | 360 | **恰好每帧 1 次**：960≠966 后 active=0，本帧不再检查 |

旧默认（3840/2160/960/540）在第一行就失败且整帧清零 → b7 的 `crop_groups/raw_pub/enc/exported=0`
完全由几何引起；不含帧/CRC/DDR/状态包因素。

## 3. 改动（严格最小）

| 文件 | 改动 |
|---|---|
| `r0/changed-src/a1_raw_crop.v` | 4 个默认参数（3864/2192/972/556）+ 参数合同（generate 硬失败 + `` `ifdef SIMULATION `` 值断言）；端口/输出时序/sof/last/4 个计数器语义**未变** |
| `r0/changed-src/camera_a1_uart_top.v` | 仅 `CAM_W/CAM_H/ROI_X/ROI_Y` 默认值 4 行（相对 b7 副本逐个 diff 确认） |
| `r0/td/01_build.tcl` | 仅 5 行路径（crop + exporter + camera top + mailbox + core）指向 b8 包 |

冻结未动：f9p 核、p2 top、a1_frame_top、a1_deflate_core、exporter、store/arb、SDC、ADC、引脚、
I2C/MIPI 表、UART_DIV、状态包 v2 布局、帧头/CRC、DDR 槽。差异见 `r0/rtl-diff-r0.patch`。
帧/CRC/DDR/SDC/引脚/I2C/MIPI/UART 全部未改。

## 4. 功能（G2）— 全过

### 4.1 全尺寸真实几何 `tb_crop_geom_real`（3864×2192，2 帧，966 beat/行，行间 4 拍）

- `beats=1,036,800`（2×518,400）、`sof=2`、`last=2`、`st_roi=2`、`st_groups=1,036,800`、
  `geom=0`、`short=0`、`abort=0`、`per_row=480`、`data_err=0`、`order_err=0`、`row_err=0`；
- 首组 `(line,grp)=(556,243)`、末组 `(1635,722)`；
- 输出 `caps/roi_real.bin` 5,184,000 B 与独立 Python 参考 `caps/roi_real.ref.bin`
  **逐字节相同**，SHA256=`70b10f5f0673346625a5263f2a56621347fa9c18be402a144c0422421f9028b0`。

### 4.2 真实 CSI-2 流水 `tb_crop_pipe_real`（生产候选实际编译的对）

- 用 `csi_rx_packet_integrity` + `csi_rx_10bit_unpack_checked`（`01_build.tcl` 真正编译的两个），
  带 FS / RAW10 long packet（80 B）/ 包 CRC16 / FE，header ECC 用生产 `csi_rx_hdr_ecc`；
- `CAM_W=64` → **每行恰好 16 beat（不是 15/17）**；36 条行包 → 36 个 `O_in_line` 脉冲，
  **脉宽恒 1 拍**（`wide_pulse=0`）；
- 128 个 ROI 组（16 行×8 组 = `OG*H`）逐拍等于 tap 布局参考，`data_err=0`；
- `st_roi=1`、`st_groups=128`、`geom=0`、`short=0`；
- 延迟：`line_in→首 beat=5` 拍、`最后 payload 字→末 beat=3` 拍（1 拍 handler 寄存 + 2 拍 unpack）；
  行尾最后一组早于下一条 `in_line`，crop 无需额外行关闭打拍；
- 包层：`crc_errors=0 header_errors=0 packet_timeouts=0 frame_timeouts=0 bad_frames=0
  good_frames=1 last_wc=80 last_lines=36`。
- 计划文字写的是 vendor `csi_rx_packet_handler`+`csi_rx_10bit_unpack`，但这两个**不在候选里**；
  vendor 对照仿真（`logs/sim_pipe_vendor_unpack.log`）显示 vendor unpack 在 5 B 跨字时字节序错，
  若照字面用它会得到与候选无关的 FAIL。故按“候选实际流水”执行，差异与证据见 finding F1。

### 4.3 负例 `tb_crop_neg`

| 用例 | 结果 |
|---|---|
| 某行 965 beat | `geom_err=1`、`out_last=0`、`roi_frames=0` |
| 某行 967 beat | `geom_err=1`、`out_last=0`、`roi_frames=0` |
| ROI 完成前 `in_frame` 落下 | `short=1`、`out_last=0`、`roi_frames=0`、beats=517,920（=480×1079，无最后一行） |

### 4.4 回归

- P1 三例逐字节等于 b5 金标：`micro8x2` `fa513a2b…cef`、`mid64x8` `ee61e620…789`、
  `full_grad` `b992a8ad…da9`；三例 `err/raw_drop/cmp_drop/geom/dup_words=0`；
- `a1_deflate_core.v` 与 b7 副本 SHA 相同（未改）；
- v2 状态包 `tb_status_pkt_v2`：6 包 × 97 B、`bad_xor=0`（23 字段常量由冻结 TB 断言）。

## 5. 工程（G3）— 全过

综合 1 次 / 布线 1 次 / bitgen 1 次 / CWC 1 次（TD 会话 1）：

| 门槛 | 实测 | 判定 |
|---|---|---|
| Routed 违例端点 | 0 / 22,299 | PASS |
| Setup WNS | **+0.108 ns**（≥ +0.05） | PASS |
| Setup TNS | 0.000 ns | PASS |
| Hold WNS / TNS | +0.020 / 0.000 ns | PASS |
| Period check WNS | +2.200 ns | PASS |
| 组合环 / 无时钟网 | 0（check_timing 见报告） | PASS |
| 资源 | 23,856 slices = 33.28%，102 RAM，85 DRAMHARDCON，0 DSP | 在器件内 |
| 综合 SWNS | +0.174 ns、17,750 slices | 参考 |

`02_bitgen.tcl` 前置 STA 复检 `0.108/0.000 HOLD 0.020/0.000 PERIOD 2.200` → 生成唯一位流；
`03_cwc.tcl` 导出并与父 bit 逐字节相同（`compiled.bit == a1_board.bit`、
`compiled.cwc == a1_board.cwc`，SHA 见 `artifact-hashes.txt`）。

## 6. 系统/板级（G4）— **未达标（blocked）**

- `ping_cable.tcl`：`PH1P100`；
- **1 次 SRAM 下载**（0 Flash）：`PRG-2014 : Chip validation success: PH1P100`、
  `B8D_DL_OK mode=jtag(sram)`，36.5 s；日志 `board/download_sram_b8.log`；
- COM8 115200 8N1：**下载前 2 s 已开捕**，共 90.1 s → 970 B / **10 个 v2 包 / bad_xor=0**；
- 计数（`captures/status_v2_90s.txt`）：
  `cap_frames=0 raw_pub=0 enc_frames=0 exported=0`；
  `cam_pix_beats=0 cam_line_rises=0 cam_frame_rises=1 crop_short=1 crop_geom_err=0 crop_groups=0`；
  最后一个包的 `cam_phystat=0`（OR 0x1EE = tap 46/delay_done/rst_out/sync_wait 曾出现），
  `cam_sysstat=0x0F1D`（OR 含 cfg_done=1、pll_locked=1、lane_sticky=0），`cam_nack_cnt=0`；
- **对照**：下载**前**用同一 COM8 采到的 b7 bit 基线（`captures/com8_90s_predownload_b7bit.bin`，
  90 包/90 s）相机域**完全同态**：`cam_pix_beats=0 cam_line_rises=0 cam_frame_rises=1
  crop_short=1 crop_geom_err=0 phystat=0x1EE sysstat=0x0F1D`，legacy 全 0；
- 因此：本次板级**没有 MIPI payload**，与 b7 记录的“相机停流”一致；`crop_geom_err` 在 90 s 内
  delta=0（满足），但这是**空数据下的满足**，不能当作“crop 已修好”的板级证明；
- `exported=0`，捕获里没有 `A1U1` 帧头 → 未做 zlib/CRC 解码（`decode_frame.py` 已就绪，未触发）。

判定：G4 = **not met / blocked**。需要用户侧给板卡（相机/传感器）重新上电后再做**新一轮** 1 次下载；
本轮不再下载（授权只 1 次，且失败不二次下载）。

## 7. 未测 / 未运行（不得写成 PASS）

- 真实图像内容/像素布局：候选 tap 的 40-bit 布局是 `{p3,p2,p1,p0}`，`a1_frame_top` 注释写的是
  `[7:0]=b0…[39:32]=b4`（finding F2，冻结范围外，未改任何模块）→ 若后续做图像验收，先确认字段序；
- 板级 `raw_pub/enc/exported` 与帧解码：因无 payload 未发生；
- 长时稳定性、Flash、第二次下载：均未做且未授权。

## 8. 预算

开发 ≈ 75 min（上限 120）；TD 1 会话（≤3）、综合 1（≤2）、布线 1（≤1）、bitgen 1、CWC 1、下载 1、Flash 0。
两次“采集但未下载”的空跑源于 TD TCL 路径被反斜杠转义吞掉（见 lessons L5/L6），未触碰下载通道。

## 9. G 层

| G | 结论 |
|---|---|
| G0 输入/几何 | PASS（实测推导 + 冻结 SHA） |
| G1 RTL 改动 | PASS（4 行默认值 + 参数合同 + 5 行路径） |
| G2 仿真 | PASS（全尺寸逐字节 / 真实流水 / 负例 / P1 / v2） |
| G3 工程候选 | PASS（Routed 0 违例、WNS +0.108、bit+CWC 一致） |
| G4 板级 | **NOT MET（blocked）**：无 MIPI payload，四计数为 0；唯一一次下载已用 |
