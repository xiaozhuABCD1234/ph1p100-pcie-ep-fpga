# T10.b7-cam-diag r0-diag — 相机前端可观测性 + v2 状态包（开发结果）

日期：2026-10-24 23:44 – 2026-10-25 05:5x。开发角色：单会话（fpga-dev 不可用，general 代行）。
结论先行：**RTL / 包格式 / P1 回归 / 工程全过；唯一 1 次 SRAM 下载成功，但板级 60 s 收不到任何字节 → 三问在硬件上无法判定，系统层 blocked（未做第二次下载）。**

## 1. 交付内容（只加可观测性）

| 文件 | 改动 |
|---|---|
| `r0/changed-src/cam_diag_mailbox.v` | 新增：参数化“稳定保持 + 翻转同步”邮箱（W/DIV_BITS，慢侧整体锁存 + 单比特翻转，快侧 3FF + 1 拍稳定窗后取样，双侧异步复位） |
| `r0/changed-src/camera_a1_uart_top.v` | clk_cam 域 6 个计数 + `cam_phystat` + crop 4 计数 → 11×u32 邮箱；clk_a1 域三路独立 2FF 翻转计数；15×u32 打包成 480 bit 给 exporter。新增 8 个输入（`i_dbg_tap/delay_done/rst_out/sync_wait/pkt_tgl/vs_tgl/clk_tgl/i_dbg_sys`） |
| `r0/changed-src/a1_uart_export.v` | 空闲状态包 v1(35 B) → **v2(97 B)**：`A5 5A | LEN=0x61 | VER=0x02 | 8×u32 legacy 同序 | 15×u32 cam | XOR8` |
| `r0/td/src/f9p_camera_display_core.v` | 只加 16 个 `o_dbg_*` output + 文件末尾 16 条 `assign`（+38 行，无新时序逻辑） |
| `r0/td/src/p2_a1_board_top.v` | 连 16 路诊断；`cam_sysstat` 打包；sys 状态经 **sys50 → dhi_clk → clk_a1 两级邮箱**；接 `u_a1.i_dbg_sys` |
| `r0/td/01_build.tcl` | 3 处路径重定向到包内副本（exporter / camera top / core）+ 文件表加 `cam_diag_mailbox.v`；策略组、SDC、器件、引脚不变 |

未改：`a1_raw_crop`、store/arb2/fifo、`a1_frame_top`、`a1_deflate_core`（SHA 仍 `6797db05…35bb`）、图像帧头/CRC/长度/字节序、DDR 布局、UART 数据帧、`UART_DIV=1628`、`p2_board.sdc`、`a1_small_top.sdc`、`board_p2.adc`、引脚、Flash。

`r0/rtl-diff-r0diag.patch`：相机核 +38/-0；p2 top +51/-0；camera top +137/-1；exporter +41/-28；tcl +7/-6 —— 只有端口、assign、计数器、包格式与文件表。

## 2. 局部仿真（全部实测通过）

| 项 | 结果 | 证据 |
|---|---|---|
| v2 包格式 | 6 包 × 97 B，`bad_xor=0`、`bad_len_ver=0`、8+15 个字段逐个等于常量（legacy `0x1111…0x8888`，cam `0xA1A1A1A1+k`） | `sim/status_v2_bytes.txt`、`sim/status_v2_parse.txt` |
| 相机无活动分支 | clk_cam 正常但无 CSI 活动：状态包照发 9 个（873 B = 9×97），cam 字段全 0，legacy 全 0，A1 链不阻塞 | `sim/vsim_deadcam.log` |
| 邮箱保持 | 慢时钟停住后快侧保持最后值 `0x2222`，输入改成 `0x3333` 不再更新（`MB_STOPPED=2222`、`MB_FINAL=2222`） | 同上 |
| P1 三例 | micro8x2 `fa513a2b…cef`(249 B)、mid64x8 `ee61e620…789`(625 B)、full_grad `b992a8ad…da9`(180,425 B)，**三例与 r4/b5 金标逐字节相同**，`err=0/raw_drop=0/cmp_drop=0/geom=0/dup=0` | `sim/p1-regression-b7.json`、`sim/caps/*.dec|.stats` |
| core 未漂移 | `a1_deflate_core.v` = `6797db053cfc47497540d6345e3a46b7e79cc1d34fa25da5a4c501505fbf35bb` | `artifact-hashes.txt` |

## 3. 工程（2 次综合 / 2 次布线；第 1 次因 hold 违例主动废弃）

### 第 1 次布线（废弃，证据保留 `route1_*`）

`P2_ROUTED_SWNS=0.101 STNS=0.000 HWNS=-7.189 HTNS=-291.151 VIOL_EP=0` + **42 个 hold 违例端点**。
根因（已定位到路径）：`u_dbg_sys_mail/r_hold[..] → o_data[..]`，即 **sys_clk50m → clk_a1 的 64 bit 直接跨域**。
`p2_board.sdc` 把 `sys_clk50m` 与 `clk_a1` 放在**同一个** `set_clock_groups -asynchronous` 组里
（两者频率比 187.5/50 = 3.75，非整数），因此该跨域被当同步路径做 hold 检查，时钟树插入延迟差直接把 hold slack 打到 -7.19 ns。
SDC 本轮冻结，故在 RTL 侧改为 **sys50 → dhi_clk（`ddr_user`，独立时钟组）→ clk_a1** 两级邮箱，两级都是“稳定保持 + 翻转同步”，
不采样多比特异步总线，且不依赖 clk_cam（MIPI 死时 I2C 状态仍可送出）。

### 第 2 次（最终候选）

| 项 | 值 |
|---|---|
| 综合 syn_2 | SWNS **+0.280** / STNS 0.000；slice 17,799 / reg 18,039 / ERAM 72 |
| 布线 phy_2 | SWNS **+0.099** / STNS **0.000** / **0 违例端点**（22,453 EP）；hold **+0.020** / HTNS 0.000；Period Check WNS **+2.200**；组合环 0、无时钟网 0 |
| 资源（布线） | slices 23,961（33.43%）、RAM 102、DSP 0、DRAMHARDCON 85 |
| 最差路径 | `u_a1/u_a1/smem_syn_41.addrb[11]`（A1 core SRAM 地址，既有路径）；timing 报告中 **0 次**出现 `u_dbg_*mail` |
| 门槛 | Routed 0 违例 ✔、WNS +0.099 ≥ +0.05 ✔（< +0.2，caveat 同 b5）、TNS 0 ✔、hold ≥ 0 ✔、period ✔、环/无时钟 0 ✔、资源在器件内 ✔ |

**预算超支（如实记录）**：承诺 1 次布线，实际 2 次；第 2 次是“同失败命令 +1 次有新证据的重试”（证据 = 第 1 次 hold 报告精确定位到 sys 邮箱路径），
综合 2/2、布线 2/1、bitgen 1/1、CWC 1/1、下载 1/1（0 Flash）。

## 4. bit / CWC（各 1 次，fail-closed 放行）

`02_bitgen.tcl`：`P2_BITGEN_STA_SETUP=0.099/0.000 HOLD=0.020/0.000 PERIOD=2.200`，`candidate_abnormal.rpt` 0 端点 → 出 bit。

| 产物 | SHA256 | 字节 |
|---|---|---|
| `r0/td/a1_board.bit` | `622271bf337933bb0ec3c4b0c00f29e20b52a3afc758d4e53f21fd03d15e922a` | 5,224,022 |
| `r0/td/a1_board.cwc` | `06943a72cc09cffb78081cdc27e2ad118da702e4198884fe54d63ef9533c6521` | 110,168 |
| `r0/td/a1_board_inst.bid` | `92c2374ac872c777c0faa744cea8513dc9e181e36e67eb5f1c22c852ba88052f` | 96,813 |
| `r0/td/cw/compiled.bit` | 与 `a1_board.bit` 逐字节相同 | 5,224,022 |
| `r0/td/cw/compiled.cwc` | 与 `a1_board.cwc` 逐字节相同 | 110,168 |

## 5. 板级（**唯一 1 次 SRAM 下载已用；0 次 Flash**）

- `ping_cable.tcl` → `R1D_PING_DEVICE=PH1P100`。
- `download_sram_camdiag.tcl`：`B7D_DL_DEVICE=PH1P100`、`PRG-2014 : Chip validation success: PH1P100`、
  `B7D_DL_OK mode=jtag(sram)`；日志中同样有 b5 见过的无害行 `Error @ mpsse.cpp:90 : usb_open() failed`（hwserver 首次探测通道）。
- 采集（COM8 115200 8N1，两次独立 60 s 监听，均无任何字节）：
  - 第 1 次 `bytes=0`（`captures/com8_60s.stats`，wall 60.117 s）
  - 第 2 次 `bytes=0`（同一文件被覆盖写；两次 sha256 均为空串 `e3b0c442…b855`）
  - COM8 确认为板上 FTDI：`USB Serial Port (COM8)`，`FTDIBUS\VID_0403+PID_6042+AL0B99F427B`，Status=OK。
- 依 dev-plan §5：包数 <10 先查 UART/采集，仍不行 → **blocked**，**未做第二次下载、未换板、未写 Flash**。
- 附带事实：如果 FPGA 里跑的是 b6 候选，它每 ~22 ms 会发 `0x55` 心跳（60 s ≈ 2600 B），实际 0 B，说明**当前板级状态下一个字节都没出来**，
  不是“只丢了状态包”。

## 6. 三问判定

| 问 | 硬件答案 | 依据 |
|---|---|---|
| MIPI 有没有数据？ | **无法判定（板级无数据）** | 60 s 内 0 个 v2 包、0 字节；没有 `cam_clk_tgl_inc` / `cam_pkt_tgl_inc` / `cam_pix_beats` 可读 |
| I2C 有没有成功？ | **无法判定（板级无数据）** | 同上；`cfg_done` / `nack_cnt` / `xclr_n` 未取到 |
| crop 有没有收到帧？ | **无法判定（板级无数据）** | 同上；`crop_roi_frames` / `groups` / `short` / `geom_err` 未取到 |

**不得**把仿真的全 0 当作“MIPI 无数据”的证据：无活动 TB 里计数按构造就是 0，对板子没有任何结论力。

## 7. 判定（G 层）

| 层 | 结果 | 说明 |
|---|---|---|
| G0 计划/边界 | pass | 只动允许文件；SDC/引脚/帧格式/DDR 未动 |
| G1 功能（仿真） | pass | v2 包 6/6、字段全对、XOR 0 错；P1 三例逐字节；无活动分支包照发 |
| G2 工程 | pass（caveat WNS +0.099 < +0.2） | 0 违例、hold +0.020、period +2.200、资源在器件内；布线 2 次（超预算，见 §3） |
| G3 候选 | pass（bitgen+CWC 各 1 次，compiled 逐字节相同） | 1 次 SRAM 下载成功（PRG-2014），0 Flash |
| G4 系统/证据 | **blocked** | 下载后 2×60 s 无任何 UART 字节 → 三问无硬件答案；按规则未二次下载 |

## 8. not_run / caveat

- 本包不证明图像正确、不证明 A+ core 硅上正确、不证明需求二/三完成。
- 未在硅上验证 v2 包（板级无输出）；v2 只在 RTL 仿真层面被证明。
- 板级 0 字节的根因未定位（可能：板未上电/`sys_rst_n` 被按住/`ddrphy_rdy` 未起/比特未真正生效）；本轮无第二次下载授权，交规划申请新板窗。
- WNS +0.099 低于首选 +0.2（caveat，与 b5 r1-diag 的 +0.173 同类）。

## 9. 复测清单（给综合测试者）

- `required_dimensions`: integrated / functional / engineering / system
- `required_checks`:
  1. 哈希：`artifact-hashes.txt` / `CANDIDATE-MANIFEST-b7-cam-diag-r0diag.json`；core 仍 `6797db05…35bb`。
  2. 重跑 `sim/tb_status_pkt_v2.v` → 582 B / 6 包 / `bad_xor=0` / 23 字段等于常量（用 `board/parse_status_v2.py`）。
  3. 重跑 `sim/tb_cam_dead.v` → 9 包、cam 全 0、`MB_STOPPED=MB_FINAL=2222`。
  4. 重跑 P1 三例（`sim/run_p1.py`）→ 三例逐字节等于 `sim/caps/*.dec` 与 b5 金标。
  5. 工程：`build_console_r0diag_route2.log` 的 `P2_ROUTED_*`（0.099/0.000/0.020/0.000/0 违例）；`route1_*` 为 hold 违例的废弃证据。
  6. 系统：**1/1 下载已用**；重放判定只需 `parse_status_v2.py --in board/captures/com8_60s.bin`（应得 0 包）。**不得再下载**。
- `input_status`: changed（包内 5 个 RTL/TCL 文件 + 新增 mailbox/仿真/板级脚本），其余同 b6 冻结集。
