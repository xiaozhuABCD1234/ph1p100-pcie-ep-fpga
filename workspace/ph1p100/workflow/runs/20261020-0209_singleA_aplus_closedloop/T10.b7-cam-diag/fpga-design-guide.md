# T10.b7-cam-diag 设计指南（r0-diag，冻结）

本文件冻结本包的数据格式、接口、时钟/CDC、集成点、构建入口与不可改边界。开发按此实现；发现冲突先交规划，不自行改协议。

## 1. 现状（已核实，不是推测）

板级候选 `p2_a1_board_top.v` 的链路：

```
IMX415-A (MIPI-A, 4K RAW10) -> f9p_camera_display_core
   -> o_a_pixel[39:0] / o_a_pixel_valid / o_a_in_line / o_a_in_frame / o_a_vsync /
      o_a_byte_clk  (raw tap, observation only)
   -> camera_a1_uart_top: a1_raw_crop (ROI 1920x1080) -> CDC FIFO(clk_cam->clk_a1)
   -> raw store -> A+ core -> cmp store -> UART 115200 export
```

已核实的关键事实：
1. `camera_a1_uart_top` 只有 `o_st_cap_frames` 一个相机侧计数被导出；`a1_raw_crop` 的 `st_groups/st_geom_err/st_short` 与 `out_abort` 在内部存在但**没进状态包**。
2. `f9p_camera_display_core` **内部已有一整套相机诊断状态**，但只接到它自己的 `dbg_uart`（`O_uart_txd` 在板级顶层**悬空**）：`w_a_cfg_done`、`r_a_err_lat`、`r_a_nack_cnt[31:0]`、`r_a_lane_sticky[3:0]`、`w_a_delay_tap[5:0]`、`w_a_delay_done`、`w_a_rst_out`、`w_a_sync_wait`、`w_a_pkt_tgl`、`w_a_vs_tgl`、`w_a_clk_tgl`、`w_xclr_n`、`w_pll_locked`、`r_rst_n_slow`、`w_a_in_frame`、`w_a_vsync`。
   → **不需要新写相机计数器**；本包只是把已有状态“引出来 + 跨到 clk_a1 + 放进状态包”。
3. `clk_cam` 就是 `o_a_byte_clk`（111.375 MHz，MIPI PHY 输出）。若它死了，`a1_raw_crop` 永远不计数——这与 `cap_frames=0` 完全一致，也是本包必须区分的首要分支。
4. 时钟域：`sys_clk50m`（50 MHz，I2C/相机启动/粘滞状态）、`clk_cam`=`a_byte_clk`（111.375 MHz，CSI 包/pixel/line/frame）、`clk_a1`（187.5 MHz，A1 链/状态包）、`clk_uart`=`clk_a1`。**禁止**把 clk_cam 的多比特计数直接异步采样到 clk_a1。

## 2. 目标（本包只做可观测性）

让 60 s 状态包能明确回答：
- Q1 MIPI 有没有数据（字节时钟活否 / CSI 包有没有 / pixel 有没有）；
- Q2 I2C 有没有成功（cfg_done / NACK / 传感器是否在复位）；
- Q3 crop 有没有收到帧（完整 ROI / 短帧 / 行长错 / 完全没有）。

不改图像帧、不改 I2C 表、不改 MIPI 配置、不改 ROI 参数、不改 A1 压缩链。

## 3. 相机核新增诊断输出（只加 assign）

在 `r0/td/src/f9p_camera_display_core.v` 增加以下 output，并在文件末尾用 `assign` 连到**已有的**内部信号。不得新增 reg/always/状态机，不得改任何已有逻辑或端口顺序语义。

| 新 output | 源内部信号 | 源域 | 说明 |
|---|---|---|---|
| `o_dbg_a_cfg_done` | `w_a_cfg_done` | sys50 | I2C 配置完成（电平，配完保持 1） |
| `o_dbg_a_bus_err_lat` | `r_a_err_lat` | sys50 | I2C NACK 粘滞 |
| `o_dbg_a_nack_cnt[31:0]` | `r_a_nack_cnt` | sys50 | NACK 累计 |
| `o_dbg_a_lane_sticky[3:0]` | `r_a_lane_sticky` | sys50 | 曾对齐过的 lane |
| `o_dbg_a_delay_tap[5:0]` | `w_a_delay_tap` | clk_cam | IDELAY tap |
| `o_dbg_a_delay_done` | `w_a_delay_done` | clk_cam | tap 扫描完成 |
| `o_dbg_a_rst_out` | `w_a_rst_out` | clk_cam | CSI RX 复位输出 |
| `o_dbg_a_sync_wait` | `w_a_sync_wait` | clk_cam | 等 sync |
| `o_dbg_a_pkt_tgl` | `w_a_pkt_tgl` | clk_cam | 包完成翻转（已有） |
| `o_dbg_a_vs_tgl` | `w_a_vs_tgl` | clk_cam | vsync 翻转（已有） |
| `o_dbg_a_clk_tgl` | `w_a_clk_tgl` | clk_cam | 字节时钟活动翻转（已有，DIV_BITS=15） |
| `o_dbg_a_in_frame` | `w_a_in_frame` | clk_cam | 当前在帧内（电平） |
| `o_dbg_a_vsync` | `w_a_vsync` | clk_cam | 当前 vsync（电平） |
| `o_dbg_xclr_n` | `w_xclr_n` | sys50 | 传感器 XCLR（1=出复位） |
| `o_dbg_pll_locked` / `o_dbg_cfg_rst_n` | `w_pll_locked` / `r_rst_n_slow` | sys50 | 相机 PLL / 配置域复位释放 |

## 4. 计数与打包定义（clk_cam 域，7+1 字）

在 `camera_a1_uart_top` 内新增（全部 `posedge clk_cam`，复位 `rst_n`）：

| # | 信号 | 定义 | 位宽/回绕 |
|---|---|---|---|
| 0 | `cam_pix_beats` | `i_a_pixel_valid` 为 1 的拍数（每拍 4 个 RAW10 像素） | 32 bit，约 38.6 s @111.375 MHz 满速；解析器按 1 Hz delta 处理回绕 |
| 1 | `cam_line_rises` | `i_a_in_line` 上升沿 | 32 bit |
| 2 | `cam_frame_rises` | `i_a_in_frame` 上升沿 | 32 bit |
| 3 | `cam_frame_falls` | `i_a_in_frame` 下降沿（区分“卡高”） | 32 bit |
| 4 | `cam_vsync_rises` | `i_a_vsync` 上升沿 | 32 bit |
| 5 | `cam_last_frame_cycles` | 最近一次 `in_frame` 上升→下降之间的 clk_cam 拍数（下降沿锁存） | 32 bit（4K30 约 3.7 M，不溢出） |
| 6 | `crop_roi_frames` | `crop_frames`（`a1_raw_crop.st_roi_frames`） | 32 bit |
| 7 | `crop_groups` | `a1_raw_crop.st_groups` | 32 bit |
| 8 | `crop_short` | `a1_raw_crop.st_short` | 32 bit |
| 9 | `crop_geom_err` | `a1_raw_crop.st_geom_err` | 32 bit |
| 10 | `cam_phystat` | 打包（见下） | 32 bit 电平 |

`cam_phystat` 位图（clk_cam 域直接打包，均为单比特/慢变）：

```
[5:0]   delay_tap
[6]     delay_done
[7]     rst_out
[8]     sync_wait
[9]     in_frame_now        (i_a_in_frame)
[10]    vsync_now           (i_a_vsync)
[31:11] 0
```

`crop_*` 与 `cam_phystat` 同域，无需再同步。

## 5. 跨域邮箱合同（`cam_diag_mailbox.v`，新增）

单模块、参数化，两个实例：

```
cam_diag_mailbox #(.W(256), .DIV_BITS(12)) u_dbg_cam_mail  // clk_slow=clk_cam, clk_fast=clk_a1
cam_diag_mailbox #(.W(64),  .DIV_BITS(12)) u_dbg_sys_mail  // clk_slow=sys_clk50m, clk_fast=clk_a1
```

合同（必须逐条实现）：
1. **慢侧**：`r_cnt` 计数到 `2**DIV_BITS-1` 时，把 `i_data[W-1:0]` 锁进 `r_hold`，并把 `r_tgl` 取反。`DIV_BITS=12` @50 MHz ≈ 82 µs，@111.375 MHz ≈ 37 µs。数据在翻转后保持 ≥37 µs 不变。
2. **快侧**：`r_tgl_s <= {r_tgl_s[1:0], r_tgl}`（至少 2FF，3 级更稳）；`r_tgl_s[1] ^ r_tgl_s[2]` 为“新数据”脉冲；在该脉冲后**再打 2 拍**才 `r_snap <= i_data_s`（同步器 + 亚稳窗口）。因为数据稳定 ≥37 µs，而 2 拍 = 10.7 ns，余量 >3000×。
3. **快侧复位**：`rst_fast_n` 有效时 `r_snap<=0`、`r_tgl_s<=0`；慢侧复位只清自己的计数/翻转，不等对方。
4. **慢侧时钟死掉时**：`r_tgl` 不再翻转，`r_snap` 保持最后一次值（上电后为 0）。**禁止**在快侧用“邮箱超时”阻塞状态包或 A1 链；包必须照发。
5. `i_data` 的全部位在慢侧同一拍锁存（`r_hold <= i_data`），保证快侧快照自洽。
6. 不引入新时钟、不用异步 FIFO、不用多比特格雷码；只用“稳定保持 + 翻转同步”。

`cam_phystat`/`cam_pix_beats` 等 8 字 = 256 bit 走 `u_dbg_cam_mail`。
`{cam_sysstat[31:0], cam_nack_cnt[31:0]}` = 64 bit 走 `u_dbg_sys_mail`。

`cam_sysstat` 位图（sys50 域打包，在 `p2_a1_board_top` 内完成）：

```
[0]     cfg_done
[1]     bus_err_lat
[2]     xclr_n
[3]     pll_locked
[4]     cfg_rst_n
[7:5]   0
[11:8]  lane_sticky
[31:12] 0
```

## 6. clk_a1 侧翻转计数（不放进邮箱）

`clk_a1` 对三路慢翻转做 2FF + 边沿检测并累加（32 bit）：

| 字段 | 源 | 频率量级 | 说明 |
|---|---|---|---|
| `cam_clk_tgl_inc` | `o_dbg_a_clk_tgl` | 111.375 MHz / 2^16 ≈ 1.7 kHz | >0 即字节时钟活 |
| `cam_pkt_tgl_inc` | `o_dbg_a_pkt_tgl` | 每 CSI 包一次（µs~ms 级） | CSI 包计数 |
| `cam_vs_tgl_inc` | `o_dbg_a_vs_tgl` | 帧率级（~30 Hz） | 帧同步计数 |

三路翻转周期都 ≫ 2 个 clk_a1 周期，边沿检测安全；每路单独 2FF，禁止把三路当一个总线同步。

## 7. 状态包 v2（唯一允许的线格式变化：空闲状态包）

仍然只在完全空闲时发（`estate==E_IDLE && dq_cnt==0 && !desc_push && !tx_valid_r && tx_ready`），节拍 `STS_DIV=187,500,000`（1 s），`HB_DIV>0 && STS_DIV==0` 的旧心跳规则保持不变。

```
偏移  长度  内容
0     1     0xA5
1     1     0x5A
2     1     LEN = 0x61 (97)
3     1     VER = 0x02
4     32    8 × u32 legacy（顺序不变）:
           cap_frames, raw_pub, enc_frames, exported,
           raw_drop, cmp_drop, errors, read_words
36    60    15 × u32 cam:
           0  cam_clk_tgl_inc
           1  cam_pkt_tgl_inc
           2  cam_vs_tgl_inc
           3  cam_pix_beats
           4  cam_line_rises
           5  cam_frame_rises
           6  cam_frame_falls
           7  cam_last_frame_cycles
           8  crop_roi_frames
           9  crop_groups
           10 crop_short
           11 crop_geom_err
           12 cam_phystat
           13 cam_sysstat
           14 cam_nack_cnt
96    1     XOR8 over bytes[0..95]
```

- 全部小端；计数器在包开始时一次性锁存。
- legacy 8 字段与 b5 r1-diag **同序同义**，便于对照。
- 解析器：`board/parse_status_v2.py`，必须校验 magic/LEN/VER/XOR，按 1 Hz 做回绕感知累加（当前值 < 上次值则 +2^32），level 字段（`cam_phystat`/`cam_sysstat`/`cam_nack_cnt`）输出 OR 与首末值。
- 旧 `parse_status.py` 只认 35 B v1，**不要改它**；v2 用新脚本。

## 8. 集成点与文件清单

| 文件 | 改动 | 约束 |
|---|---|---|
| `r0/changed-src/cam_diag_mailbox.v` | 新增 | 见 §5 |
| `r0/changed-src/camera_a1_uart_top.v` | 新增 clk_cam 计数、`u_dbg_cam_mail`、`cam_phystat`；新增 1 个输入 `i_dbg_sys[63:0]`（clk_a1 域快照）；把 15 个 cam 字段拼成 480 bit 内部总线给 exporter | 不改 crop/CDC/raw store/A+ 链/端口语义 |
| `r0/changed-src/a1_uart_export.v` | v1 包 → v2 包（§7） | 不改图像数据发送、不改 CRC/帧头 |
| `r0/td/src/f9p_camera_display_core.v` | 只加 §3 的 output + 末尾 assign | 不改 I2C/MIPI/预览/HDMI/状态机 |
| `r0/td/src/p2_a1_board_top.v` | 连 §3 输出；`u_dbg_sys_mail`；`cam_sysstat` 打包；`i_dbg_sys` 接 `u_a1` | 不改 DDR/PLL/复位/引脚/HDMI |
| `r0/td/01_build.tcl` | 文件表加 `cam_diag_mailbox.v`；3 处路径重定向到包内副本 | 策略组/约束/器件不变 |
| `r0/td/02_bitgen.tcl`、`03_cwc.tcl` | 原样复制 b6 | 不改 |

**禁止改**：`ui_cfg_imx415.v`、`ui_i2c.v`、`ui_imx415_reg.v`、`csi_rx_*`、`mipi_csi2_rx_ph1p`、`camera_startup.v`、`raw10_display60_clocks.v`、`uitpg`/`ui_HDMI_TX`、`a1_*.v`（core/frame/crop/raw store）、DDR bridge/shell、`*.sdc`、`*.adc`、引脚、`a1_small_top.sdc`。

## 9. 仿真自证（下线前必须全过）

1. **包格式**：`r0/sim/tb_status_pkt_v2.v` 只例化 `a1_uart_export`，`UART_DIV=1`、`STS_DIV=2048`；把 23 个字段置固定常量（legacy 0x11111111…，cam 0xA1A1A1A1…）；断言：包长 97、magic/LEN/VER 对、`bad_xor=0`、23 字段逐一等于常量、包间不插帧。
2. **MIPI 死分支**：把 `u_dbg_cam_mail` 的慢时钟保持 0（或 `i_dbg_sys` 恒 0），`STS_DIV` 缩小；断言状态包仍按节拍发出、`cam_clk_tgl_inc=0`、其余 cam 字段为 0，A1 链不阻塞。
3. **P1 三例**：`tb_camera_a1_uart_top.v`，`+MODE=0`、`-gUART_DIV=1`，三例 `.dec` 必须逐字节等于 `fa513a2b…`/`ee61e620…`/`b992a8ad…`，stats `err=0/raw_drop=0/cmp_drop=0/geom=0`；用**短工作目录**（TB 的 `+OUT/+STAT` 只有 128 字符）。
4. **core 未漂移**：`a1_deflate_core.v` SHA 必须仍是 `6797db05…35bb`（b6 冻结）；若不等，停止并交规划。

## 10. 工程/板上顺序

1. `01_build.tcl`：syn → route，冻结策略组同 b6 r0（`post_route_opt ultra`、`postrt_opt_loc 20`、`postrt_opt_extra_round 4`）；综合 ≤2、布线 ≤1。
2. 门槛：Routed 0 违例、WNS ≥ +0.05、TNS 0、hold ≥ 0、period 0、组合环 0、无时钟网 0、资源在器件内；记录最差路径（确认不在 `u_dbg_*` 邮箱组合锥上）。
3. `02_bitgen.tcl` fail-closed（任一为负/TNS>0 拒绝）；`03_cwc.tcl`；记录 bit/cwc/bid SHA，`compiled.*` 与父文件逐字节比对。
4. 下载：`board/download_sram_camdiag.tcl`，先 `ping_cable.tcl` 确认 `PH1P100`，SRAM only，**不写 Flash**；日志必须含 `PRG-2014` 与显式 `DL_OK mode=jtag(sram)`。
5. 采集：COM8 115200 8N1，60 s（≥58 s 有效），保存 `.bin`；`parse_status_v2.py` 输出包数/bad_xor/23 字段首末/三问结论。
6. `result-r0diag.md` 写：三问答案、支持字段、反例字段、G0–G4、命令与 exit、caveat。

## 11. 已知风险与处理

| 风险 | 处理 |
|---|---|
| `clk_cam` 死 → `u_dbg_cam_mail` 不翻转 | 设计允许；`cam_clk_tgl_inc=0` 就是答案；包照发，不阻塞 |
| `w_a_delay_tap` 在扫描中变化 | 只在 `delay_done=1` 后采信；解析器报 `delay_done=0` 时把 tap 标为“未稳定” |
| 32 位计数回绕 | 1 Hz 采样 + 回绕感知累加；`cam_pix_beats` 满速约 38.6 s 回绕一次，60 s 最多 2 次，可检测 |
| 新增 480 bit 总线影响布线 | 全部是慢变电平/计数，要求 WNS ≥ +0.05；若最差路径落到邮箱，先加 1 级寄存器再重跑（仍只 1 次布线预算内需先仿真验证） |
| 下载后无包 | 先查 USB/COM8/波特率；不得第二次下载；blocked 交规划 |
| 相机核改动被质疑 | diff 必须证明“只有 output + assign + 文件表”；测试者按此核验 |

## 12. 工具与环境（沿用，不改）

- ModelSim Intel FPGA Edition 10.5b：`D:\intelFPGA8.1\modelsim_ase\win32aloem`
- TD：`D:nlogic\TD_Release_2026.2`，`td_commands_prompt.exe`；器件 `PH1P100SBG484 -3`
- 盘符：TD `T:`、项目 `Y:`；仿真 `P:`/`W:`；先跑 `tools/td/td_env.ps1`
- UART：COM8 115200 8N1（冻结 `UART_DIV=1628` → 115.172 kbaud）
- 不打开/不改 `D:\TD\work\csi2`
