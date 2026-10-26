# -*- coding: utf-8 -*-
"""Create the frozen T10.b8-crop-geom planning package (no deletes)."""
import json
import pathlib

ROOT = pathlib.Path(r"D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b8-crop-geom")
ROOT.mkdir(parents=True, exist_ok=True)

FILES = {}

FILES["input-index.md"] = r'''# T10.b8-crop-geom 输入索引

日期：2026-10-25。状态：ready。所有路径均为项目内绝对路径；本包只读下列证据，写范围仅本任务目录。

## 1. 直接证据（b7 实测）

- `...\T10.b7-cam-diag\r0\board\captures_retry\com8_150s.bin`（150 s，119 个 v2 包，11,543 B，bad_xor=0）
- `...\T10.b7-cam-diag\r0\board\captures_retry\com8_150s.stats`（bytes=11543，sha256=db186545...）
- `...\T10.b7-cam-diag\r0\board\captures_retry\status_v2.json`（crop_geom_err=1381，crop_groups=0，crop_roi_frames=0）
- `...\T10.b7-cam-diag\r0\board\parse_status_v2.py`（v2 97 B 解析器，本包复用）
- `...\T10.b7-cam-diag\result-r0diag.md`、`lessons-r0diag.md`、`artifact-hashes.txt`、`CANDIDATE-MANIFEST-b7-cam-diag-r0diag.json`

关键派生值（包 0–12，相邻包 delta，30 帧/包）：`65,760/30 = 2,192 行/帧`；`63,523,629/65,760 = 966.0 beat/行`；`966×4 = 3,864 px/行`。包 13 起相机域计数全 0（约 13 s 后停流），属板级风险，不是 crop 根因。

## 2. 生产源与真实语义（只读）

- `D:\fpga\ph1p100\fpga\csi2\src\a1\a1_raw_crop.v`（当前 CAM_W=3840/CG=960，缺陷所在）
- `D:\fpga\ph1p100\fpga\csi2\src\a1\camera_a1_uart_top.v`（crop 默认参数 3840/2160/960/540；raw store EXPECT_BYTES=2,592,000；A+ W/H=1920/1080）
- `D:\fpga\ph1p100\fpga\csi2\src\cam\f9p_camera_display_core.v`（A-tap 例化 `mipi_csi2_rx_ph1p`，`w_a_pixel[39:0]`/`w_a_pixel_valid/w_a_in_line/w_a_in_frame/w_a_vsync`）
- `D:\fpga\ph1p100\fpga\csi2\prj\camera_peer\uisrc\03_ip\mipi_csi_2\csi_rx_packet_handler.v`（`O_in_line` 为每行 1 拍脉冲；`O_in_frame` 为 FS..FE 电平）
- `D:\fpga\ph1p100\fpga\csi2\prj\camera_peer\uisrc\03_ip\mipi_csi_2\csi_rx_10bit_unpack.v`（5 B→4×10 bit，输出寄存 1 拍；RAW10 40 bit/beat）
- `D:\fpga\ph1p100\fpga\csi2\prj\camera_peer\uisrc\03_ip\ui_imx415_cfg\ui_cfg_imx415.v`、`ui_imx415_reg.v`（mode=1，4K30 RAW10；表未列 X/Y_OUT_SIZE，几何以实测为准）
- `D:\fpga\ph1p100\fpga\csi2\src\cam\cam_preview_capture.v`（既有 3840/2160 预览假设，仅参考，不在本包改）

## 3. 工程/仿真基线（只读）

- b7 TD 模板：`...\T10.b7-cam-diag\r0\td\{src,01_build.tcl,02_bitgen.tcl,03_cwc.tcl,a1_eng_top.v,a1_small_top.sdc,p2_board.sdc,board_p2.adc}`
- b7 changed-src：`a1_uart_export.v`（v2 97 B）、`camera_a1_uart_top.v`（诊断计数）、`cam_diag_mailbox.v`、`a1_deflate_core.v`（SHA 6797db05...35bb）
- P1 TB：`...\T10.b1-a1-uart-integ\r0\sim\tb_camera_a1_uart_top.v`（CAM_W/ROI_X 为参数，显式传 3840/2160/960/540）
- P1 金标：`fa513a2b...cef`(249 B)、`ee61e620...789`(625 B)、`b992a8ad...da9`(180,425 B)
- b7 候选：`r0\td\a1_board.bit` SHA 622271bf...922a，CWC 06943a72...6521（仅作历史基线，不复用为 b8 候选）

## 4. 运行规则

- `D:\fpga\ph1p100\AGENTS.md`；`.agents\skills\fpga-planner\SKILL.md`；`workflow\FPGA多智能体工作流_使用说明.md`
- 本 run：`dev-plan.md`、`handoff.md`、`user-summary.md`、`final-summary.md`、`workflow\tasks.json`（规划/主维护，本包不写）
- 盘符：TD 用 T:/Y:，仿真用 P:/W:；打开 TD 前先跑 `tools\td\open_td.ps1` 或 `td_env.ps1`

## 5. 冻结决定

1. 真实源几何 = 3864×2192（966 beat/行，2192 行/帧），不是 3840×2160；crop 必须按 3864/966 校验。
2. 输出 ROI 固定 1920×1080，2×2 对齐；中心 ROI 在整帧坐标 = (972,556)（972/4=243，556 为偶数；相对有源窗口 (12,16) 为 (960,540)）。
3. W/H 保持参数化；协议/帧头/CRC/DDR 布局/SDC/引脚/I2C/MIPI 配置一律不改。
4. 1 次 SRAM 下载 + 60 s 采集；0 Flash；失败不二次下载。
'''

FILES["fpga-design-guide.md"] = r'''# T10.b8-crop-geom 设计指南（冻结）

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
'''

FILES["dev-plan.md"] = r'''# T10.b8-crop-geom 开发计划（r0）

日期：2026-10-25。状态：**ready（已冻结，等待 fpga-dev）**。本轮唯一正式包；两级（需求→工作包）；5 项语义步骤。

## 0. 冻结根因（实测，不再猜）

证据：`T10.b7-cam-diag\r0\board\captures_retry\com8_150s.bin` 的 v2 包 0–12（`bad_xor=0`，1 Hz）。相邻包 delta：

| 量 | 实测 | 推导 |
|---|---|---|
| Δframes | 30 | 1 Hz 包内 30 帧 |
| Δlines | 65,760 | 65,760/30 = **2,192 行/帧** |
| Δbeats | 63,523,629 | 63,523,629/65,760 = **966.0 beat/行** |
| px/beat | 40 bit = 4×10 bit | `csi_rx_10bit_unpack` 5 B→4 px |
| 行宽 | 966×4 | **3,864 px**（IMX415 全有效阵列 3864×2192；有源 3840×2160 居中） |

crop 现状 `CAM_W=3840 → CG=960`：第 0 行实际 966 beat；第 1 行 `new_line` 时 `grp_idx=966≠960` → `active<=0`、`st_geom_err+1`；`active=0` 后本帧不再检查 → **每帧恰好 1 次 geom_err**，`st_groups` 永远 0。与 b7 的 `crop_geom_err=1381`、`crop_roi_frames=0`、`crop_groups=0`、`cap_frames=0` 完全一致。

补充：同一 150 s 采集从包 13 起相机域计数全 0（约 13 s 后停流）。这是板级风险，不是 crop 根因；b8 必须下载后立即开捕，并把“停流”与“crop 仍错”分开记录。

## 1. 任务表

| task_id | 问题/产物 | 工作树/允许写路径 | 依赖 | functional | engineering | system | 必要 G 层 | 状态 | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|
| T10.b8-crop-geom | 真实源是 3864×2192/966 beat/行；crop 写死 3840/960 导致每帧几何失败、全链 0。产物：正确几何的 crop + 全尺寸真实仿真 + P2 候选 + 1 次下载/60 s 证据 | 新包 `workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b8-crop-geom/**`；只改包内 `r0/changed-src/a1_raw_crop.v`、`r0/changed-src/camera_a1_uart_top.v`（仅默认参数）、`r0/td/01_build.tcl`（仅路径表）；TD 其余文件复制不改 | b7 v2 包/计数器、b7 TD 模板、P1 三例金标、b1 P1 TB | 全尺寸 3864×2192 逐字节；真实解包流水小向量；965/967/短帧负例；P1 三例逐字节；core SHA 不变 | Routed 0 违例、WNS ≥ +0.05、hold ≥ 0、period 0、资源在器件内；crop 改动不进 clk_a1 关键路径 | 1 次 SRAM 下载 + 60 s COM8；cap_frames/raw_pub/enc_frames/exported >0；crop_geom_err=0；若有帧 PC 解码/CRC | G0/G1/G2/G3/G4 | ready | 派 fpga-dev |

不适用项与理由：
- 不改 I2C/MIPI/IDELAY/预览：b7 已证明 I2C cfg_done=1、NACK=0、pll_locked=1、MIPI 有 966 beat/行；本轮只修 crop 几何。
- 不改 A+ core/帧格式/CRC/DDR/SDC：不是本包根因；任何改动都会让 P1 金标与 b7 证据失效。

## 2. 五项语义步骤

1. **建包/冻结起点/复算几何**：建 `r0/{changed-src,sim,td,board}`；从 b7 `r0/td` 复制 `src/`、`a1_eng_top.v`、`a1_small_top.sdc`、`p2_board.sdc`、`board_p2.adc`、`01/02/03_*.tcl`（不复制 `a1_board_Runs/`、`cw/`、旧 bit/cwc/bid/大报告）；从 b7 changed-src 复制 `a1_uart_export.v`、`camera_a1_uart_top.v`、`cam_diag_mailbox.v`、`a1_deflate_core.v`；从生产源复制 `a1_raw_crop.v`。写 `geometry-derivation.md`（包 0–12 delta 表、966/2192 计算、ROI 972/556 推导），记录全部 SHA、工具版本、盘符。
2. **修 crop**：`r0/changed-src/a1_raw_crop.v` 只改参数默认值与几何校验（CAM_W=3864、CAM_H=2192、ROI_X=972、ROI_Y=556、W=1920、H=1080；CG=966；加 `initial` 参数断言）；保持端口/输出时序/4 个计数器不变。若仿真证明行尾最后一组晚于下一条行头 1 拍，可加 1 拍行关闭寄存后再校验，但不改输出流、不加端口。`r0/changed-src/camera_a1_uart_top.v` 只改 4 个默认参数，其余与 b7 逐字节一致（除默认值）。
3. **真实几何仿真**：新增 `sim/tb_crop_geom_real.v`（3864×2192、2 帧、966 beat/行、逐字节 + 参考 SHA）、`sim/tb_crop_pipe_real.v`（生产 packet_handler+unpack、小尺寸 64×36、16 beat/行、证明 5 B/4 px 与 1 拍 in_line/2 拍延迟）、`sim/tb_crop_neg.v`（965/967/短帧）。跑 P1 三例与 v2 包回归。
4. **P2 重建**：`01_build.tcl` 路径表指向本包副本（尤其 `a1_raw_crop.v`）；综合 ≤2、布线 1；门槛 Routed 0 违例/WNS≥+0.05/TNS 0/hold≥0/period 0/环 0/无时钟 0/资源在器件内；1 bitgen + 1 CWC，`compiled.*` 逐字节相同。
5. **板级**：`ping_cable.tcl` → `download_sram_b8.tcl`（SRAM only，0 Flash，日志 PRG-2014 + DL_OK）→ COM8 115200 8N1 60 s（下载后立即开捕）→ `parse_status_v2.py` → 目标四计数 >0、`crop_geom_err/crop_short` delta=0、`crop_groups=518,400×cap_frames`；若导出帧，扫描 `41 31 55 31` 44 B 头，校验 header/stream CRC、zlib 解压、raw_crc（若解码器支持）并出 PGM/PNG；写 `result-r0.md`。

## 3. 几何合同（冻结）

| 参数 | 值 | 校验 |
|---|---|---|
| `CAM_W` | 3864 | 966×4；实测 966.0 beat/行 |
| `CAM_H` | 2192 | 65,760/30 |
| `ROI_X` | 972 | (3864−1920)/2；%4=0，偶数 |
| `ROI_Y` | 556 | (2192−1080)/2；偶数 |
| `W`/`H` | 1920/1080 | W%4=0，H%2=0 |
| `CG`/`OG`/`NGRP` | 966/480/518,400 | NGRP<2^20 |
| 有源窗口 | 3840×2160 @ (12,16) | ROI 相对有源=(960,540)；ROI 以整帧中心定义 |

## 4. RTL 允许改动（严格）

- `r0/changed-src/a1_raw_crop.v`：参数默认值、`initial` 断言、必要的 1 拍行关闭校验；**不改**端口、`out_*` 语义、4 个计数器含义。
- `r0/changed-src/camera_a1_uart_top.v`：只改 `CAM_W/CAM_H/ROI_X/ROI_Y` 默认值。
- `r0/td/01_build.tcl`：只改文件表路径到本包副本。
- **禁止**：f9p 核、p2 top、a1_frame_top、a1_deflate_core、exporter、store/arb、SDC、ADC、引脚、I2C/MIPI 表、UART_DIV、状态包 v2 格式。

## 5. 仿真验收（不过不进 TD）

| 项 | 判据 |
|---|---|
| 全尺寸 `tb_crop_geom_real` | 2 帧各 518,400 valid；每 ROI 行 480；sof/last 各 1/帧；`roi_frames=2`；`groups=1,036,800`；`geom=0`；`short=0`；`abort=0`；输出 `.bin` 与独立 Python 参考 SHA256 相同（逐字节） |
| 真实流水 `tb_crop_pipe_real` | 每行 16 beat（不是 15/17）；8×8 组逐字节；`geom=0/short=0/roi_frames=1`；证明 5 B→4 px、1 拍 in_line、1–2 拍解包延迟 |
| 负例 | 965/967 beat → `geom_err+1`、无 `out_last`；短帧 → `short+1`、无 `out_last` |
| P1 三例 | `fa513a2b...cef`/`ee61e620...789`/`b992a8ad...da9` 逐字节；`err/raw_drop/cmp_drop/geom/dup=0` |
| core/v2 回归 | `a1_deflate_core.v` SHA `6797db05...35bb`；v2 包 97 B/6 包/`bad_xor=0`/23 字段常量 |

## 6. 工程/候选门槛

Routed 0 违例；WNS ≥ **+0.05**；TNS 0；hold ≥ 0；period 0；组合环 0；无时钟网 0；资源在器件内。综合 ≤2、布线 1、bitgen 1、CWC 1；`compiled.bit|cwc` 与父文件逐字节相同。任何门槛不过 → 停止，不 bitgen。

## 7. 板级验收（1 次 SRAM 下载，0 Flash）

1. `ping_cable.tcl` 打印 `PH1P100`；`download_sram_b8.tcl` 日志含 `PRG-2014` 与 `DL_OK mode=jtag(sram)`。
2. COM8 115200 8N1 60 s，下载后立即开捕（可提前 2 s）；保存 `.bin/.stats`；记录 wall 时间。
3. `parse_status_v2.py`：`bad_xor=0`；≥10 包（导出忙可放宽，须有完整帧头佐证）；`cap_frames>0`、`raw_pub>0`、`enc_frames>0`、`exported>0`；`crop_geom_err` delta=0；`crop_short` delta=0；`crop_groups` delta=518,400×`cap_frames`。
4. `exported>0` 时：扫描 `41 31 55 31`，校验 44 B 头（version/header_len/width/height/raw_len/header_crc）、`stream_crc`、zlib 解压=`xform_len`；有反变换则 `raw_crc` + PGM/PNG。保存 `frame_*.bin`、`decode.txt`。
5. 若相机停流：记录停流时刻与当时计数；不得把停流误判为 crop 仍错；不得二次下载。

## 8. 预算/停止/回退

| 项 | 上限 |
|---|---|
| 开发 | 120 min / 60 calls |
| TD | 3 sessions；综合 ≤2；布线 1；bitgen 1；CWC 1；下载 1；Flash 0 |
| 综合测试 | 45 min / 30 calls；不重跑 TD、不下载 |

停止条件（任一）：需要改 I2C/MIPI/IDELAY/预览/帧格式/CRC/DDR/SDC/引脚；仿真要求改生产解包器语义；布线违例或 WNS<+0.05；bitgen/CWC 失败；板级无 `cap_frames`；需要第二次下载/Flash/换板；工具/许可/COM8 缺失。失败即停，保留证据交规划；同失败命令仅允许 1 次有新证据的重试，连续 2 次无进展 → blocked。

回退：保留 b7 bit/CWC 作历史候选，不覆盖 b6/b7 包；b8 失败则 G3/G4 not_run，不声称已上板；不动 `workflow/tasks.json`、`D:\TD\work\csi2`、upstream。

## 9. 交付物

- `r0/geometry-derivation.md`、`r0/changed-src/{a1_raw_crop.v,camera_a1_uart_top.v,a1_uart_export.v,cam_diag_mailbox.v,a1_deflate_core.v}` + `r0/rtl-diff-r0.patch`
- `r0/sim/`：`tb_crop_geom_real.v`、`tb_crop_pipe_real.v`、`tb_crop_neg.v`、`caps/roi_real.bin|ref.bin|stats`、日志、P1 三例 `.dec/stats`、v2 包回归
- `r0/td/`：`01/02/03_*.tcl`、报告、`a1_board.bit/.cwc/_inst.bid`、`cw/compiled.*`
- `r0/board/`：`download_sram_b8.tcl/.log`、`captures/com8_60s.bin/.stats`、`status_v2_60s.txt`、`frame_*.bin`、`decode.txt`
- `CANDIDATE-MANIFEST-b8-crop-geom-r0.json`、`artifact-hashes.txt`、`result-r0.md`、`lessons-r0.md`

## 10. 下一动作

主按 `dispatch.json` 派 **fpga-dev**（输入本计划 + `fpga-design-guide.md` + `handoff.md`）。开发停止修改并冻结唯一 manifest 后，由主新建**一个**独立综合测试者按同一 manifest 验收；同任务 FAIL 才续原开发/原测试，最多三轮实际修复。
'''

FILES["handoff.md"] = r'''# T10.b8-crop-geom 交接（r0）

状态：**ready，尚未开工**。只交接冻结输入、操作顺序与判据；设计细节见 `fpga-design-guide.md`，门槛见 `dev-plan.md`。

## 1. 一句话

实测 IMX415 输出 **3864×2192**（966 beat/行、2192 行/帧），crop 却按 3840/960 写死，第一行就 `geom_err` 并把整帧 `active` 清零，所以 b7 的 `crop_groups/raw_pub/enc/exported` 全 0。本包把 crop 几何改成 3864/2192、ROI 972/556、输出 1920×1080，做真实几何逐字节仿真，重建 P2，**唯一 1 次** SRAM 下载 + 60 s COM8，目标四计数 >0。

## 2. 开工前只读检查

1. 读 `T10.b7-cam-diag\result-r0diag.md` §3/§6/§7、`lessons-r0diag.md` §1/§5；读 `r0\board\captures_retry\status_v2.json`。
2. 复核几何：用 `parse_status_v2.py` 解析 `com8_150s.bin`，取包 0–12 delta，确认 `65760/30=2192`、`63523629/65760=966.0`；写进 `r0\geometry-derivation.md`。
3. 确认 b7 TD `01_build.tcl` 第 17 行 `a1_raw_crop.v` 仍指向 `Y:/fpga/csi2/src/a1/`，第 20–22/25 行指向 b7 包；b8 必须全部改到 b8 包。
4. 确认 P1 TB 显式传 `CAM_W=3840/CAM_H=2160/ROI_X=960/ROI_Y=540`，因此默认参数改动不影响 P1 金标。
5. 不写 `workflow/tasks.json`；不动 `D:\TD\work\csi2`；不写 Flash；不做第二次下载；不批量删除。

## 3. 建包与冻结起点

```powershell
$pkg = 'D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b8-crop-geom'
New-Item -ItemType Directory -Force -Path "$pkg\r0\changed-src","$pkg\r0\sim","$pkg\r0\td","$pkg\r0\board" | Out-Null
$b7 = 'D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b7-cam-diag\r0'
Copy-Item -LiteralPath "$b7\td\src" -Destination "$pkg\r0\td\src" -Recurse
foreach ($f in 'a1_eng_top.v','a1_small_top.sdc','p2_board.sdc','board_p2.adc','01_build.tcl','02_bitgen.tcl','03_cwc.tcl') {
  Copy-Item -LiteralPath (Join-Path "$b7\td" $f) -Destination (Join-Path "$pkg\r0\td" $f)
}
foreach ($f in 'a1_uart_export.v','camera_a1_uart_top.v','cam_diag_mailbox.v','a1_deflate_core.v') {
  Copy-Item -LiteralPath (Join-Path "$b7\changed-src" $f) -Destination (Join-Path "$pkg\r0\changed-src" $f)
}
Copy-Item -LiteralPath 'D:\fpga\ph1p100\fpga\csi2\src\a1\a1_raw_crop.v' -Destination "$pkg\r0\changed-src\a1_raw_crop.v"
Copy-Item -LiteralPath "$b7\board\parse_status_v2.py" -Destination "$pkg\r0\board\parse_status_v2.py"
```

`r0\td\01_build.tcl` 只改路径表：第 17 行 crop → `Y:/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b8-crop-geom/r0/changed-src/a1_raw_crop.v`；第 20–22/25 行 → b8 包同名文件。其余 TCL 不动。

记录 `artifact-hashes.txt`：输入/复制文件 SHA256、TD/ModelSim 版本、盘符；注明**未复制** `a1_board_Runs/`、`cw/`、旧 bit/cwc/bid。

## 4. 实现顺序（不要并行改多处）

1. `a1_raw_crop.v`：先只改参数默认值（3864/2192/972/556/1920/1080）和 `initial` 断言；保持端口/时序/计数器。跑全尺寸仿真；若行尾最后一组晚于下一条行头 1 拍，再加 1 拍行关闭校验（只改内部，不改输出）。
2. `camera_a1_uart_top.v`：只改 4 个默认参数；`git diff` 除这 4 行外必须为空（相对 b7 副本）。
3. 仿真：全尺寸 → 真实流水小向量 → 负例 → P1 三例 → v2 回归。全过才进 TD。
4. `01_build.tcl` 路径表；TD 综合/布线/bitgen/CWC。
5. 板级 1 次下载 + 60 s；解析/解码；写 result。

## 5. 仿真判据（不过不进 TD）

| 项 | 判据 |
|---|---|
| 全尺寸 | 2 帧各 518,400 valid；480/ROI 行；sof/last 各 1；`roi_frames=2`；`groups=1,036,800`；`geom=0/short=0/abort=0`；输出与独立参考 SHA256 相同 |
| 真实流水 | 每行 16 beat；8×8 组逐字节；`geom=0/short=0/roi_frames=1` |
| 负例 | 965/967 → `geom_err+1`、无 last；短帧 → `short+1`、无 last |
| P1 | 三例逐字节；`err/raw_drop/cmp_drop/geom/dup=0` |
| core/v2 | core SHA 不变；v2 97 B/6 包/XOR 0/23 字段常量 |

短路径：ModelSim 输出路径 ≤128 字符，工作目录用 `C:\Users\czz\AppData\Local\Temp\opencode\b8`。

## 6. TD / 候选

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'D:\fpga\ph1p100\tools\td\td_env.ps1' -TdDir "$pkg\r0\td"
Push-Location "$pkg\r0\td"
& 'D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe' ./01_build.tcl
Pop-Location
```

- 综合 ≤2、布线 **1**；策略组/SDC/器件/引脚/频率同 b7；不改 seed。
- 门槛：Routed 0 违例、WNS ≥ +0.05、TNS 0、hold ≥ 0、period 0、环 0、无时钟 0、资源在器件内。不过 → 停，不 bitgen。
- 保留每次 syn/route 报告；最差路径写 result。

## 7. bitgen / CWC

```powershell
Push-Location "$pkg\r0\td"
& 'D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe' ./02_bitgen.tcl
& 'D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe' ./03_cwc.tcl
Pop-Location
```

记录 `a1_board.bit`、`a1_board.cwc`、`a1_board_inst.bid` SHA/字节；`cw/compiled.bit|cwc` 与父文件逐字节相同。fail-closed 阈值同 b7。

## 8. 板级（唯一 1 次 SRAM 下载）

1. `ping_cable.tcl` → `PH1P100`。
2. 新建 `board/download_sram_b8.tcl`（从 b7 复制，只改 bit 路径到 b8 `r0\td\a1_board.bit`）；SRAM only，日志必须 `PRG-2014` + `DL_OK mode=jtag(sram)`；0 Flash。
3. 下载完成后立即开 COM8 115200 8N1 60 s（可提前 2 s 开监听）；保存 `captures/com8_60s.bin/.stats`，记录 wall_start/end。
4. `python board/parse_status_v2.py --in captures/com8_60s.bin --out captures/status_v2_60s.txt`；`bad_xor=0`；检查四目标与 `crop_geom_err/crop_short` delta、`crop_groups=518,400×cap_frames`。
5. 若 `exported>0`：写/复用 `board/decode_frame.py`，扫描 `41 31 55 31`，解析 44 B 头，校验 header/stream CRC，zlib 解压；有反变换则 raw_crc + PGM/PNG。
6. 相机停流：记录停流时刻/计数；不得二次下载；不得把停流当 crop 错。

## 9. 冻结/报告

- 停止修改后写 `CANDIDATE-MANIFEST-b8-crop-geom-r0.json`：输入/产物 SHA、唯一 bit/CWC/BID、TD 报告、几何、预算消耗、caveat。
- `result-r0.md` 分 functional/engineering/system/G0–G4；含几何推导、仿真逐字节、P1、TD 门槛、板级四目标、解码/CRC、not_run。
- `lessons-r0.md` 写实际返工/踩坑；不得把未跑项写 PASS。
- 交回主：`task_ids/status=ready_for_test/artifact_paths/manifest_path/test_input_paths/lessons_path/blocked/retest`。
'''

FILES["user-summary.md"] = r'''# T10.b8-crop-geom 用户摘要

**已定位根因（有实测证据）**：IMX415 4K 实际输出 **3864×2192**，每行 **966** 个 40-bit beat（4 像素/beat），每帧 **2192** 行；crop 按 3840×2160 写死每行 960，第一行就几何不匹配，整帧被 `active=0` 丢掉。所以 b7 看到 `crop_geom_err=1381`（每帧 +1）、`crop_groups=0`，后面 raw/压缩/UART 全 0。

**本包冻结的修法**：
- crop 源几何改 **3864×2192**，每行严格校验 **966** beat；中心 ROI 起点 **(972,556)**（972%4=0、556 偶数），输出仍 **1920×1080**，W/H 保持参数化。
- 不改图像帧头/CRC/DDR 布局/UART 协议/SDC/引脚/I2C/MIPI 配置。
- 新增全尺寸真实几何仿真（2 帧逐字节 + 参考 SHA）、生产解包流水小向量（证明 5 B→4 px、1 拍 in_line、1–2 拍解包延迟）、965/967/短帧负例、P1 三例回归。
- P2 复用 b7 工程重建：Routed 0 违例、WNS ≥ +0.05；1 bitgen + 1 CWC。
- **1 次 SRAM 下载 + COM8 60 s**：目标 `cap_frames>0、raw_pub>0、enc_frames>0、exported>0`，`crop_geom_err=0`；有导出帧则 PC 解码/CRC。失败即停，不二次下载、不写 Flash。

**风险（如实）**：
- 115200 波特下整帧导出可能超过 60 s；b7 那次 150 s 采集显示相机约 13 s 后停流。若只完成压缩未传完，`exported=0` 会按未达标记录，但 bit/证据保留给下一次板窗。
- 有源窗口 (12,16) 是 IMX415 有效/有源差的常用值；ROI 以整帧中心定义，即使略偏也仍是中心 1920×1080，且保持 2×2 对齐。

**需要用户输入**：无（本轮 1 次下载窗口已授权）。
'''

FILES["final-summary.md"] = r'''# T10.b8-crop-geom 收尾摘要（规划冻结轮）

日期：2026-10-25。状态：**ready / 未执行**。本文件是规划轮的收尾记录；开发、TD、下载完成后由原规划者按实际结果覆盖更新，**当前不声称任何 PASS**。

## 1. 本轮完成

- 用 b7 的 13 个有效 v2 包（1 Hz）冻结真实几何：**2,192 行/帧**（65,760/30）、**966.0 beat/行**（63,523,629/65,760）、**3,864 px/行**（966×4）。
- 定位 crop 根因：`CAM_W=3840 → CG=960`，第 1 行 `grp_idx=966≠960` → `geom_err+1`、`active=0`，每帧恰好 1 次，`crop_groups` 永远 0。
- 冻结 ROI：源 3864×2192，ROI (972,556)，输出 1920×1080，2×2 对齐；W/H 参数化。
- 冻结验证/工程/板级门槛与预算，写 `dev-plan.md`、`fpga-design-guide.md`、`handoff.md`、`dispatch.json`。
- 未改任何生产源、未跑 TD、未下载、未写 Flash。

## 2. 交付路径

- 计划：`...\T10.b8-crop-geom\dev-plan.md`
- 指南：`...\T10.b8-crop-geom\fpga-design-guide.md`
- 交接：`...\T10.b8-crop-geom\handoff.md`
- 派发：`...\T10.b8-crop-geom\dispatch.json`
- 输入索引：`...\T10.b8-crop-geom\input-index.md`

## 3. 验收摘要（执行时逐项填实际值）

| 层 | 门槛 | 实际 |
|---|---|---|
| G1 功能 | 全尺寸 2 帧逐字节 + 真实流水 8×8 + 965/967/短帧负例 + P1 三例 | 待执行 |
| G2 工程 | Routed 0 违例、WNS ≥ +0.05、hold ≥ 0、period 0、资源在器件内 | 待执行 |
| G3 候选 | 1 bitgen + 1 CWC，compiled 逐字节相同 | 待执行 |
| G4 系统 | 1 次 SRAM 下载 + 60 s：cap_frames/raw_pub/enc_frames/exported >0；geom/short delta=0；PC 解码/CRC | 待执行 |

## 4. 风险与 not_run

- not_run：真实板级、TD、bitgen、下载均未执行；本文件不证明图像正确、不证明 A+ 硅上正确、不证明需求二/三完成。
- 风险：115200 下整帧导出可能 >60 s；b7 采集显示相机约 13 s 后停流；有源窗口偏移假设；严格 966 等宽对丢 beat 零容忍。
- 失败即停：不二次下载、不写 Flash、不换板；保留 b7 bit/CWC 作历史候选。

## 5. 下一次准确启动文本

Codex：
`$fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop；本轮目标：执行 T10.b8-crop-geom（按 dev-plan 派 fpga-dev；1 次 SRAM 下载 + 60 s COM8；失败不二次下载）`

OpenCode：
`/fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop；本轮目标：执行 T10.b8-crop-geom（按 dev-plan 派 fpga-dev；1 次 SRAM 下载 + 60 s COM8；失败不二次下载）`
'''

for name, text in FILES.items():
    with open(ROOT / name, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)

DISPATCH = {
    "run_id": "20261020-0209_singleA_aplus_closedloop",
    "project_root": "D:/fpga/ph1p100",
    "output_dir": "D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b8-crop-geom",
    "task_ids": ["T10.b8-crop-geom"],
    "batch_size": 1,
    "status": "ready",
    "needs_user_input": False,
    "input_paths": [
        "D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b8-crop-geom/dev-plan.md",
        "D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b8-crop-geom/fpga-design-guide.md",
        "D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b8-crop-geom/handoff.md",
        "D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b7-cam-diag/r0/board/captures_retry/status_v2.json",
        "D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b7-cam-diag/r0/board/captures_retry/com8_150s.bin",
        "D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b7-cam-diag/r0/board/parse_status_v2.py",
        "D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b7-cam-diag/result-r0diag.md",
        "D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b7-cam-diag/lessons-r0diag.md",
        "D:/fpga/ph1p100/fpga/csi2/src/a1/a1_raw_crop.v",
        "D:/fpga/ph1p100/fpga/csi2/src/a1/camera_a1_uart_top.v",
        "D:/fpga/ph1p100/fpga/csi2/src/cam/f9p_camera_display_core.v",
        "D:/fpga/ph1p100/fpga/csi2/prj/camera_peer/uisrc/03_ip/mipi_csi_2/csi_rx_packet_handler.v",
        "D:/fpga/ph1p100/fpga/csi2/prj/camera_peer/uisrc/03_ip/mipi_csi_2/csi_rx_10bit_unpack.v",
        "D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b7-cam-diag/r0/td/src",
        "D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b7-cam-diag/r0/td/01_build.tcl",
        "D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b7-cam-diag/r0/td/02_bitgen.tcl",
        "D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b7-cam-diag/r0/td/03_cwc.tcl",
    ],
    "write_scope": [
        "D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b8-crop-geom/**"
    ],
    "protected": [
        "D:/fpga/ph1p100/upstream/**",
        "D:/fpga/ph1p100/fpga/csi2/src/**",
        "D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b7-cam-diag/**",
        "D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b6-a1-htab-nw/**",
        "D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b5-a1-htab-pipe/**",
        "D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b2-a1-uart-impl/**",
        "D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b1-a1-uart-integ/**",
        "D:/fpga/ph1p100/workflow/tasks.json",
        "D:/TD/work/csi2/**",
        "any Flash/program path; shared bit/CWC/BID",
    ],
    "next_action": {
        "operation": "subagent",
        "agent": "fpga-dev",
        "host_fallback": "spawn_agent (Codex); OpenCode uses subagent(agent=..., description=..., prompt=...)",
        "task_id": "T10.b8-crop-geom",
        "prompt_path": "D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b8-crop-geom/dev-plan.md",
        "read_first": [
            "D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b8-crop-geom/fpga-design-guide.md",
            "D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b8-crop-geom/handoff.md",
        ],
        "input_status": "b7 crop-geometry bug frozen from 13 live v2 packets: 966 beats/line, 2192 lines/frame, 3864x2192 source; b7 v2 packet/counters and P1 goldens are the baseline; 1 SRAM download + 60 s COM8 authorized",
        "required_outputs": [
            "r0/geometry-derivation.md + r0/changed-src/{a1_raw_crop.v,camera_a1_uart_top.v} + r0/rtl-diff-r0.patch",
            "r0/sim full 3864x2192 two-frame byte-exact + real unpack pipe small vector + 965/967/short negatives + P1 three goldens + v2 regression",
            "r0/td rebuilt P2 (reuse b7 project) + reports + 1 bit + 1 CWC",
            "r0/board 1 SRAM download log + 60 s COM8 capture + v2 parse with four targets + image header/CRC decode if exported",
            "CANDIDATE-MANIFEST-b8-crop-geom-r0.json + artifact-hashes.txt + result-r0.md + lessons-r0.md",
        ],
    },
    "after_development": {
        "operation": "spawn_single_tester",
        "role": "fpga-tester",
        "task_id": "T10.b8-crop-geom",
        "input": "same frozen manifest and package only; independent of dev; rerun the full-geometry sim, real-pipe sim, negatives and P1; replay the same capture; no TD rerun, no second download, no Flash",
        "budget": {"minutes": 45, "tool_calls": 30},
    },
    "scope_limits": "本轮 1 个主要可验收目标、1 个正式包、两级、5 项语义步骤；只修 crop 几何与行组校验；不改帧/CRC/DDR/SDC/引脚/I2C/MIPI/UART_DIV/状态包 v2；1 次 SRAM 下载、0 Flash；失败不二次下载；不以新 run/改 ID 绕限。",
    "execution_limits": {
        "dev": {"minutes": 120, "tool_calls": 60},
        "td": {"sessions": 3, "synth": 2, "route": 1, "bitgen": 1, "cwc": 1, "download": 1, "flash": 0},
        "tester": {"minutes": 45, "tool_calls": 30, "td_rerun": 0, "download": 0},
        "retry": "同失败命令首次 + 1 次有新证据的重试；连续 2 次无进展 blocked；不自动扩权/扩预算/二次下载。",
    },
    "board_authorization": "1 次 SRAM 下载、COM8 60 s 由用户 2026-10-25 本轮指令明确授权；不含 Flash、不含第二次下载、不含更换板卡。",
    "question_path": None,
    "user_summary_path": "D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b8-crop-geom/user-summary.md",
}

with open(ROOT / "dispatch.json", "w", encoding="utf-8", newline="\n") as fh:
    json.dump(DISPATCH, fh, ensure_ascii=False, indent=2)
    fh.write("\n")

print("wrote", len(FILES) + 1, "files to", ROOT)
for p in sorted(ROOT.iterdir()):
    print(p.name, p.stat().st_size)
