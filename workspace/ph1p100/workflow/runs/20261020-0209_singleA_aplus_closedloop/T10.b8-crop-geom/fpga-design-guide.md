# T10.b8-crop-geom 设计指南（冻结）

## 1. 范围与边界

只改 A 口 RAW crop 的几何参数/行组校验，使中心 1920×1080 ROI 能从真实 IMX415 4K30 RAW10 tap 完整输出。下列内容**冻结**，任何一项需要改动即停止并交规划：

- 图像帧头、magic/version/flags/header_len、字段顺序、字节序、长度、CRC（raw/xform/stream/header）
- DDR 槽布局（RAW_BASE=0、CMP_BASE=131072、SLOT_WORDS、AWB）、arb2、store 协议
- UART 数据帧、`UART_DIV=1628`（115.172 kbaud）、状态包 v2 97 B 格式与字段顺序
- `p2_board.sdc`、`a1_small_top.sdc`、`board_p2.adc`、引脚、时钟、Flash
- I2C 表、`I_cam_mode=1`、MIPI RX/IDELAY tap=46、lane 数、f9p 预览/HDMI

## 2. A-tap 真实语义（已核对 RTL）

| 信号 | 语义 |
|---|---|
| `w_a_pixel[39:0]` | 每 beat 4 个 RAW10 像素：p0=[9:0], p1=[19:10], p2=[29:20], p3=[39:30]（`csi_rx_10bit_unpack` 的 5 B→4 px 输出） |
| `w_a_pixel_valid` | 每 4 像素 1 拍；一行共 CAM_W/4=966 拍 |
| `w_a_in_line` | 每行 CSI-2 long packet 头 1 拍脉冲（不是整行电平） |
| `w_a_in_frame` | FS..FE 电平；上升沿为帧首 |
| `w_a_vsync` | FS 短包 1 拍脉冲 |
| 解包延迟 | `csi_rx_10bit_unpack` 输出 `r_data_out/r_dout_valid` 相对 payload 有 1–2 拍延迟；行尾最后一组在下一条行头之前到达（仿真必须覆盖） |

## 3. 真实几何（本包唯一冻结值）

| 参数 | 值 | 推导/校验 |
|---|---|---|
| `CAM_W` | **3864** | 966 beat/行 × 4 px；实测 65,760 行/30 帧、63,523,629 beat/65,760 行 |
| `CAM_H` | **2192** | 65,760/30；IMX415 全有效阵列 |
| `CG = CAM_W/4` | **966** | 每行必须恰好 966 个有效 beat |
| `ROI_X` | **972** | (3864−1920)/2；972%4=0（243 组），偶数 |
| `ROI_Y` | **556** | (2192−1080)/2；偶数 |
| `W`×`H` | **1920×1080** | 2×2 对齐；W%4=0，H%2=0 |
| `OG = W/4` | 480 | 每 ROI 行组数 |
| `NGRP` | 518,400 | 480×1080；< 2^20，`out_cnt` 20 bit 足够 |
| 有源窗口 | 3840×2160 @ (12,16) | IMX415 有效/有源差；ROI 相对有源 = (960,540)，仍 2×2 对齐。**ROI 以整帧中心定义**，即使有源窗口略偏，输出仍是全帧中心 1920×1080 |

参数合法性在 `initial` 中断言（仅仿真）：`CAM_W%4==0`、`ROI_X%4==0`、`ROI_Y%2==0`、`W%4==0`、`H%2==0`、`ROI_X+W<=CAM_W`、`ROI_Y+H<=CAM_H`、`NGRP<2^20`。

## 4. Crop 行为合同

1. 帧首（`in_frame` 上升）清 `line_idx/grp_idx/out_cnt`，`active=1, done=0`。
2. 每条 `in_line` 上升为一行开始；行内按 `pix_valid` 递增 `grp_idx`（包括 ROI 列之外的 beat）。
3. 对 `line_idx <= ROI_Y+H-1` 的每一行，在下一行开始（或帧尾）校验该行 `grp_idx == 966`；不等则 `out_abort=1`、`st_geom_err+1`、`active=0`，本帧不产生 `out_last`。
4. ROI 行 `[ROI_Y, ROI_Y+H-1]`、列组 `[ROI_X/4, ROI_X/4+OG-1]` 的 beat 按 raster 顺序输出；`out_valid` 每拍 1 组；首组 `out_sof=1`，第 518,400 组 `out_last=1` 并 `st_roi_frames+1`。
5. ROI 完成前 `in_frame` 落下 → `out_abort=1`、`st_short+1`，不产生 `out_last`。
6. `st_groups` 只统计 ROI 内接受的组；完整帧应为 518,400。
7. **不改输出时序/位宽/sof/last 语义**；若仿真证明行尾最后一组可能晚于下一条行头 1 拍，可加 1 拍“行关闭”寄存后再校验，但不得改变输出流或增加端口（现有 4 个计数器足够，v2 包字段不变）。

## 5. 仿真向量合同

### 5.1 全尺寸真实几何（必须）

`tb_crop_geom_real.v`：直接驱动 crop，源 3864×2192，2 帧。

- 每行：`in_line` 1 拍；随后 966 拍 `pix_valid`，每拍 4 个 10-bit 像素；行间空 4 拍。
- 帧 0/1 使用不同确定图案（如 `p0={line[5:0],grp[3:0]}`、`p1=~p0`、`p2=line^grp`、`p3=10'h2A5^(line+grp)`；帧 1 加常量）。
- 期望：每帧 518,400 个 `out_valid`；每 ROI 行 480 组；`out_sof` 每帧 1 次；`out_last` 每帧 1 次；`st_roi_frames=2`；`st_groups=1,036,800`；`st_geom_err=0`；`st_short=0`；`out_abort=0`。
- 逐字节：TB 把输出 40-bit beat 按 5 B 小端写 `caps/roi_real.bin`；独立 Python 参考模型按 `(line=ROI_Y+r, grp=ROI_X/4+c)` 生成 `caps/roi_real.ref.bin`；`fc /b` 或 SHA256 必须相同。另存 `caps/roi_real.stats`（每组行列、首末组、错误计数）。

### 5.2 真实解包流水小向量（必须）

`tb_crop_pipe_real.v`：实例化生产 `csi_rx_packet_handler` + `csi_rx_10bit_unpack`，再接 crop。小尺寸真实比例：`CAM_W=64`（16 beat/行）、`CAM_H=36`、`ROI_X=16`、`ROI_Y=8`、`W=32`、`H=16`。

- 按 CSI-2 字节流构造 FS(0x00)、每行 RAW10 long packet（80 B=20 word）、行尾短包、FE(0x01)；header ECC 用生产 `csi_rx_hdr_ecc` 计算；payload 按 5 B→4 px 逆打包。
- 断言：crop 每行看到 **16** 个 beat（不是 15/17）；8×8 个输出组逐字节等于参考；`geom_err=0`、`short=0`、`roi_frames=1`。
- 该向量证明“每行 1 拍 in_line + 5 B/4 px + 1–2 拍解包延迟”与全尺寸向量一致；不得只用理想直驱向量代替。

### 5.3 负例（必须）

- 某行 965 beat → `geom_err+1`、无 `out_last`、`roi_frames` 不增。
- 某行 967 beat → 同上（严格等宽）。
- ROI 完成前 `in_frame` 落下 → `short+1`、无 `out_last`。

### 5.4 回归（必须）

- P1 三例逐字节等于 b7 金标；stats `err/raw_drop/cmp_drop/geom/dup_words=0`；`a1_deflate_core.v` SHA 仍 `6797db05...35bb`。
- v2 状态包仿真仍 97 B、6 包、`bad_xor=0`、23 字段常量（本次不改 exporter，仍须回归）。

## 6. 工程/候选合同

- TD 工程从 b7 `r0/td` 复制，只改 `01_build.tcl` 的路径表：`a1_raw_crop.v` 指向本包 `r0/changed-src/a1_raw_crop.v`；exporter/camera top/mailbox/core 指向本包副本。
- 综合 ≤2、布线 **1**、bitgen **1**、CWC **1**；策略组、SDC、器件、引脚、时钟频率与 b7 完全一致。
- 门槛：Routed **0 违例**、**WNS ≥ +0.05**、TNS 0、hold ≥ 0、period 0、组合环 0、无时钟网 0、资源在器件内。不满足即停止，不 bitgen。
- bitgen fail-closed 阈值同 b7；`cw/compiled.bit|cwc` 与父文件逐字节相同。

## 7. 板级合同

- `ping_cable.tcl` 必须打印 `PH1P100`；`download_sram_b8.tcl` 只写 SRAM，日志含 `PRG-2014` 与 `DL_OK mode=jtag(sram)`；0 Flash。
- COM8 115200 8N1，**60 s**；下载完成后立即开始（可提前 2 s 开监听），记录 wall 时间；保存 `captures/com8_60s.bin/.stats`。
- 解析：复用 `parse_status_v2.py`；`bad_xor=0`；至少 10 个包（导出忙时状态包会变少；若有完整图像帧，包数可放宽并记录）。
- 目标：`cap_frames>0`、`raw_pub>0`、`enc_frames>0`、`exported>0`；`crop_geom_err` delta=0；`crop_short` delta=0；`crop_groups` delta=518,400×`cap_frames`（mod 2^32）。
- 若 `exported>0`：从同一 `.bin` 扫描 `41 31 55 31`（magic 0x31553141），按 44 B 头解析；校验 `version=1`、`header_len=44`、`width=1920`、`height=1080`、`raw_len=2,592,000`、`header_crc`、`stream_crc`；zlib 解压长度=`xform_len`；若复用既有反变换解码器，再校验 `raw_crc` 并出 PGM/PNG。保存 `frame_*.bin`、`decode.txt`。
- 相机停流（cam 计数不再增长）与 crop 错必须分开记录；停流时不得把 `exported=0` 误判为 crop 仍错。

## 8. 证据/清单

- `geometry-derivation.md`：包 0–12 delta 表、966/2192 计算、ROI 推导。
- `CANDIDATE-MANIFEST-b8-crop-geom-r0.json` + `artifact-hashes.txt`：输入/产物 SHA、唯一 bit/CWC/BID、TD 报告、预算消耗、caveat。
- `result-r0.md`：functional/engineering/system/G0–G4；`lessons-r0.md`：返工与根因。
