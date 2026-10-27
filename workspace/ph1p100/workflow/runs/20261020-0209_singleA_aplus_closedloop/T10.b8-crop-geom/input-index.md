# T10.b8-crop-geom 输入索引

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
