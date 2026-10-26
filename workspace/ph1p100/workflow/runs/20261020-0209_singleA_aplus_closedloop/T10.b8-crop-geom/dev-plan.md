# T10.b8-crop-geom 开发计划（r0）

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
