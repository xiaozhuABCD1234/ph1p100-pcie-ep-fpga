# T10.b14-cam-b — dev-plan（规划冻结，2026-10-25）

- run：`20261020-0209_singleA_aplus_closedloop`（项目根 `D:\fpga\ph1p100`）
- 父任务：T10（**保持 blocked**；本包完成也不把 T10 置 done）
- 角色：开发 = fpga-dev（fpga-planner 不可用，本包以 general 代行规划；开发仍按 fpga-dev 合同执行）；冻结后另派 **1 个新综合测试者**（functional/engineering/system 是同一人的检查清单）
- 状态：**ready**；`needs_user_input=true`（仅板级前置：B 相机模块是否物理连接）；批大小 1；1 个主要可验收目标、1 个正式工作包（5 个语义步骤）
- 本包主题：**把 A+ tap 从 A 路切到 B 路**，先回答“B 相机能不能出像素”；不修 A 路、不改 MIPI 配置/寄存器表/tap 策略

## 0. 冻结输入与基线（不得重新解释）

### 0.1 为什么切 B（b13 板级事实）

- b13 r1 板级（`T10.b13-ddr-retry/r1/board/captures/status_v5.txt`，150 包 / 150 s，bad_xor=0）：
  - `cap_frames=0`、`raw_pub=0`、`enc=0`、`exported=0`；
  - **`cam_pix_beats=0`、`cam_line_rises=0`**、`cam_frame_rises=0`、`cam_frame_falls=0、`cam_vs_tgl_inc=0→2`；
  - `cam_clk_tgl_inc`、`cam_pkt_tgl_inc` 明显增长（MIPI 字节时钟与 CSI 包有活动）；
  - `crop_short=0`、`last_frame_cycles=0xFFFFFFFF`、`phystat/sysstat` 非零。
- 判定：A 路“有 MIPI 包/VSYNC、无有效像素”，b7/b9/b10/b13 反复复现；b8 上电曾正常 3,300 帧，说明链路并非完全死路，但当前 A 口无法稳定出图。
- 用户决定：**尝试走 B 相机**。本包只验证 B 的“配置→MIPI→tap→crop→raw→A+→export→帧 CRC/zlib”；若 B 也无像素，本包以 blocked 留证，不再做第二次下载。

### 0.2 相机核现状（已核实，不是推测）

基线核：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b13-ddr-retry/r1/td/src/src/f9p_camera_display_core.v`
SHA256 = `C9DE0D9C176E830DF35833EFF7E91B811D954FB5480BC13E1FB122EF23305089`（b13 r1 构建实际使用版本）

| 问题 | 结论 | 依据（该文件行号） |
|---|---|---|
| B 路 I2C 初始化是否使能 | **已使能**，无需“打开开关” | `u_cfg_b` 实例化于 L228–239：`I_rst_n(r_rst_n_slow)`、`I_cam_mode(2'd1)`（4K）；`ui_cfg_imx415` 复位后 `WAIT_START→PREPARE` 自动启动，无 enable 端口 |
| B MIPI 是否复位释放 | **已释放且 RX 使能** | `u_csi_b` 实例化于 L182–205：`I_rst_n(r_rst_n)`、`I_rx_en(r_rst_n)` |
| B 的 line/frame/vsync 是否可用 | **可用**（内部已有 wire） | L141–145：`w_b_vsync / w_b_in_frame / w_b_in_line / w_b_pixel[39:0] / w_b_pixel_valid`；当前只接调试计数器与 `pulse2toggle` |
| B 的帧/CRC 状态 | 存在但**悬空** | L204：`O_frame_end(), O_frame_good(), O_frame_abort(), O_crc_errors(), O_header_errors(), O_packet_timeouts(), O_frame_timeouts(), O_good_frames(), O_bad_frames(), O_last_wc(), O_last_lines()` 全部未接 |
| B 的 tap | 与 A 共用 `CAM_IDELAY_TAP=46` | L128–129、L190–191；B 眼图未单独扫过（残余风险，见 §6.4） |
| B 的 MCLK/XCLR | 与 A 共用 | L115–116：`assign cam_b_mclk=w_mclk; assign cam_b_xclr_n=w_xclr_n;` |
| B 的引脚 | **已分配**，不是“pinned/disabled” | `T10.b13-ddr-retry/r1/td/board_p2.adc` L39–48（MIPI-B J19/H19、J22/H22、G17/G18、J20/J21、L19/L20）与 L64–67（`cam_b_scl=H13`、`cam_b_sda=G13`、`cam_b_xclr_n=H20`、`cam_b_mclk=G20`） |

- `p2_a1_board_top.v` L56 的注释 “sensor control (A used, B pinned/disabled)” **是过时注释**；本次允许改为“A/B both routed, CAM_SEL selects the A+ tap”，仅注释。
- 结论：**B 路初始化没有被禁用，不需要做“最小使能”改动**；缺的只是“把 B 的 tap/诊断引到核外，并在板级顶选它”。

### 0.3 源码基线 = b13 r1 源集

- b13 r1 构建输入：`T10.b13-ddr-retry/r0/changed-src/`（10 文件）+ `r1/td/src/src/f9p_camera_display_core.v`；候选 bit `aa7f7569…6a5e`、CWC `0bef6442…516`、BID `fc8b964d…3913`；Routed `SWNS=+0.023 / 0 违例`。
- 本包把上述 11 个文件复制到 `T10.b14-cam-b/r0/changed-src/`，逐个记录 SHA256；**只有 2 个文件允许功能修改**（§2.1）。
- 构建/仿真模板：`T10.b13-ddr-retry/r1/td/**`（Tcl/ADC/SDC/`src/`）与 `T10.b13-ddr-retry/r0/sim/**`（P1 三黄金、full、store/read 回归）；只读复制，不改旧包。
- 板级模板：`T10.b13-ddr-retry/r1/board/{run_board_r1.ps1,capture_com8.py,parse_status_v5.py,dl_b13.tcl}`；新包内复制并改 bit 路径/COM/时长。

### 0.4 不可改动（冻结）

- 44 B 帧头/CRC、压缩帧字节、crop 几何/ROI（`CAM_W=3864, CAM_H=2192, ROI_X=972, ROI_Y=556, W=1920, H=1080`）、四槽 DDR 布局、UART_DIV=1628、HB_DIV、引脚、时钟频率（187.5 MHz / 111.375 MHz）。
- `camera_a1_uart_top.v`、`a1_raw_crop.v`、`a1_frame_top.v`、`a1_deflate_core.v`、`a1_ddr_slot_store.v`、`a1_ddr_arb2.v`、`p2_ddr_bridge.v`、`a1_uart_export.v`、`cam_diag_mailbox.v`、vendor/`upstream/**`。
- **状态包仍是 v5：241 B / 59 字段 / VER=5 / LEN=241 / XOR 0..239**；不新增字段、不改字段顺序。
- 不写 Flash、不 PCIe/RK、不做双路/G4；不 false path/multicycle/改 seed/降频/新增 ERAM 实例；不批量删除。
- 不改 `workflow/tasks.json`、旧 run/证据/manifest。

## 1. 本轮唯一目标

**问题**：A 路有 MIPI 包/VSYNC 但无有效像素；B 路前端已使能、引脚已分配，但 B 的 tap 从未进入 A+ 链，无法判断 B 是否可用。

**产物**：一个最小“B tap 选择”候选：
1. 相机核输出 B 的 `o_b_pixel/o_b_pixel_valid/o_b_in_line/o_b_in_frame/o_b_vsync/o_b_byte_clk` 与 B 诊断（纯 assign）；
2. `p2_a1_board_top` 用编译期常量 `CAM_SEL=1` 把 `clk_cam`/pixel/line/frame/vsync/调试信号切到 B，A 核仍存活但不进 A+；`CAM_SEL=0` 时逐线回到 b13 的 A 连接；
3. `p2_board.sdc` 增加 B 字节时钟的 generated clock（新时钟域必须被约束）；
4. 仿真证明 B 几何全链可走通、P1 三黄金逐字节不变、v5 的 `pix/line/frame` 计数记录的是所选相机；
5. Routed 0 违例（WNS 按 §6），1 bitgen + 1 CWC；
6. 板级 1 次 SRAM 下载 + COM8 150 s：先看 B 的 `clk_tgl/pkt_tgl/pix_beats/line_rises/frame_rises/cap_frames`，再看 `enc/exported` 与帧四 CRC+zlib。

### 1.1 工作包最小表

| task_id | 问题/产物 | 工作树/允许写路径 | 依赖 | functional | engineering | system | 必要 G 层 | 状态 | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|
| `T10.b14-cam-b` | B tap 选择 + B 全链验证 | `D:/fpga/ph1p100`；只写 `run/T10.b14-cam-b/**` | b13 r1 源/bit/板级证据 | B 几何全链导出（四 CRC+zlib）；P1 三黄金逐字节；v5 计数/选择位；A 路径 `CAM_SEL=0` 等价 | Routed 0 违例、WNS 预裁决、ERAM+CWC≤300、1 bitgen+1 CWC | 先下载后 COM8、150 s、B 的 clk/pkt/pix/line/frame/cap>0、enc/exported>0、四 CRC+zlib；B 无像素则 blocked 留证 | G0/G1 仿真；G2 构建；G3 板级；G4 not_run | ready | 派 fpga-dev 执行本计划 |

## 2. 唯一正式包与工作步骤

| # | 语义步骤 | 预算 | 产物/门槛 |
|---|---|---|---|
| W1 | 冻结基线 + 核引出 B | ≤25 min | 复制 b13 r1 源集；核只加 B tap/B 诊断 output + 末尾 assign；A 端口/逻辑零改动；`git diff` 只有端口/assign/1 个 B tap localparam |
| W2 | 板级顶选择 B | ≤25 min | `CAM_SEL` 常量 + `generate` 直连（**不得**用 LUT 做时钟 mux）；`CAM_SEL=1` 时 `u_a1.clk_cam`/tap/`i_dbg_*`/`i_dbg_sys` 全来自 B；`CAM_SEL=0` 与 b13 逐线一致；`cam_sysstat[20]=cam_sel` |
| W3 | SDC + 仿真 | ≤40 min | `p2_board.sdc` 加 `mipi_b_byte_clk` generated clock 并加入异步组；S1–S5 全过；P1 三黄金逐字节；v5 结构/选择位正确 |
| W4 | 重建（综合≤3、布线≤2、1 bitgen + 1 CWC） | TD 内 | Routed 0 违例、hold/period 正、ERAM+CWC≤300；WNS 按 §6 裁决；bit/CWC/BID/compiled 自洽冻结 |
| W5 | 板级（先确认 B 已连接；先下载后开 COM8） | ≤20 min | 确认 B 已连接 → 1 次 SRAM 下载成功后才开 COM8 150 s；B 的 clk/pkt/pix/line/frame/cap>0；再要求 enc/exported>0 且 ≥1 帧四 CRC+zlib；B 无像素 → blocked 留证，不第二次下载 |

### 2.1 写域/工作树/允许改的源

- 工作树：**`D:/fpga/ph1p100`**（唯一主源）。
- 允许写：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b14-cam-b/**`（`changed-src/`、`sim/`、`td/`、`board/`、manifest、日志）。
- 源先复制到 `r0/changed-src/` 再改。**允许功能修改（2 个 RTL + 1 个 SDC + 构建路径）**：
  1. `f9p_camera_display_core.v` — 只加 B tap 输出（6）、B 诊断输出（18）与文件末尾纯 `assign`；新增 `CAM_B_IDELAY_TAP=6'd46`（默认同 A 值），`u_csi_b` 用它；B 的 frame/CRC 状态接到新输出；A 的端口/实例/`CAM_IDELAY_TAP` 不变。
  2. `p2_a1_board_top.v` — 新增 `localparam CAM_SEL=1'b1`；`generate` 选择 `clk_cam`、tap、`i_dbg_*`、`cam_sysstat`/`cam_nack_cnt`；`cam_sysstat[20]=cam_sel`；连核的新 B 端口；A 核仍实例化。仅注释修正 “B pinned/disabled”。
  3. `p2_board.sdc` — 只加 1 条 `create_generated_clock mipi_b_byte_clk`（源 `mipi_b_clk_hs_p`，`-divide_by 4`，pin `u_camera/u_csi_b/u_rx_phy/u_hs_clk_div.clkdivout`）并把 `mipi_b_byte_clk` 加入既有 `-group {mipi_b_clk_hs}`。**这是给新时钟域补约束，不是放宽约束**；不得改其他 SDC 行。
  4. `01_build.tcl` / `a1_board.al` — 只把 `f9p_camera_display_core.v` 的文件路径改指 `r0/changed-src/` 副本；其余路径改指 b14 本地副本；流程/参数/seed 不变。
- **逐字节不变**：`camera_a1_uart_top.v`、`a1_raw_crop.v`、`a1_frame_top.v`、`a1_deflate_core.v`、`a1_ddr_slot_store.v`、`a1_ddr_arb2.v`、`p2_ddr_bridge.v`、`a1_uart_export.v`、`cam_diag_mailbox.v`、camera 前端其余/vendor、`board_p2.adc`、`a1_small_top.sdc`、`UART_DIV/HB_DIV`。
- 构建：复制 b13 `r1/td/**` 到 b14 `r0/td/`（不含旧 `a1_board_Runs/`、`cw/`、大报告）；`01_build.tcl` 与 `a1_board.al` 的 11 个 changed-src 路径统一指向 b14 `r0/changed-src/`；Tcl 的流程/参数/seed 不变。
- 路径：`P:`=项目根，`W:`=`r0/sim`；TD `T:`=`r0/td`，`Y:`=项目根；`X:` 不映射项目根。
- 禁止批量删除（只能一次 `Remove-Item <单文件>`，需批量先问用户）。

## 3. RTL 规格（冻结语义，允许等价实现）

### 3.1 相机核新增输出（`f9p_camera_display_core.v`）

全部为 `output wire`，文件末尾只做 `assign`，不新增 reg/always/状态机：

```verilog
// B raw tap (same shape as the A tap)
output wire [39:0] o_b_pixel,
output wire        o_b_pixel_valid,
output wire        o_b_in_line,
output wire        o_b_in_frame,
output wire        o_b_vsync,
output wire        o_b_byte_clk,
// B front-end diagnostics (assigns to existing internal state)
output wire        o_dbg_b_cfg_done,
output wire        o_dbg_b_bus_err_lat,
output wire [31:0] o_dbg_b_nack_cnt,
output wire [3:0]  o_dbg_b_lane_sticky,
output wire [5:0]  o_dbg_b_delay_tap,
output wire        o_dbg_b_delay_done,
output wire        o_dbg_b_rst_out,
output wire        o_dbg_b_sync_wait,
output wire        o_dbg_b_pkt_tgl,
output wire        o_dbg_b_vs_tgl,
output wire        o_dbg_b_clk_tgl,
output wire        o_dbg_b_in_frame,
output wire        o_dbg_b_vsync,
output wire [31:0] o_dbg_b_good_frames,
output wire [31:0] o_dbg_b_bad_frames,
output wire [31:0] o_dbg_b_crc_errors,
output wire [31:0] o_dbg_b_header_errors,
output wire [15:0] o_dbg_b_last_wc,
output wire [15:0] o_dbg_b_last_lines
```

```verilog
assign o_b_pixel       = w_b_pixel;
assign o_b_pixel_valid = w_b_pixel_valid;
assign o_b_in_line     = w_b_in_line;
assign o_b_in_frame    = w_b_in_frame;
assign o_b_vsync       = w_b_vsync;
assign o_b_byte_clk    = w_b_byte_clk;
assign o_dbg_b_cfg_done    = w_b_cfg_done;
assign o_dbg_b_bus_err_lat = r_b_err_lat;
assign o_dbg_b_nack_cnt    = r_b_nack_cnt;
assign o_dbg_b_lane_sticky = r_b_lane_sticky;
assign o_dbg_b_delay_tap   = w_b_delay_tap;
assign o_dbg_b_delay_done  = w_b_delay_done;
assign o_dbg_b_rst_out     = w_b_rst_out;
assign o_dbg_b_sync_wait   = w_b_sync_wait;
assign o_dbg_b_pkt_tgl     = w_b_pkt_tgl;
assign o_dbg_b_vs_tgl      = w_b_vs_tgl;
assign o_dbg_b_clk_tgl     = w_b_clk_tgl;
assign o_dbg_b_in_frame    = w_b_in_frame;
assign o_dbg_b_vsync       = w_b_vsync;
assign o_dbg_b_good_frames = B_GOOD;      // u_csi_b.O_good_frames
assign o_dbg_b_bad_frames  = B_BAD;       // u_csi_b.O_bad_frames
assign o_dbg_b_crc_errors  = B_CRC;       // u_csi_b.O_crc_errors
assign o_dbg_b_header_errors = B_HDR;     // u_csi_b.O_header_errors
assign o_dbg_b_last_wc     = B_WC;        // u_csi_b.O_last_wc
assign o_dbg_b_last_lines  = B_LINES;     // u_csi_b.O_last_lines
```

- `B_GOOD`…`B_LINES` 是 `u_csi_b` 对应输出新接的内部 wire（L204 由空连接改为 wire）；其余 B 输出保持空连接。
- `CAM_B_IDELAY_TAP = 6'd46`；`u_csi_b.I_manual_delay(CAM_B_IDELAY_TAP)`，`USE_MANUAL_TAP` 不变。A 的 `CAM_IDELAY_TAP=46` 不变。
- A 的端口顺序/语义、L156–180 的 `u_csi_a`、HDMI/TPG、I2C A、`dbg_uart` 全部不变。

### 3.2 板级选择（`p2_a1_board_top.v`）

```verilog
localparam CAM_SEL = 1'b1;   // 0 = A (b13 behaviour), 1 = B (this package)
```

- 用 `generate if (CAM_SEL) ... else ...` **常量选择**，不得用运行时寄存器或 LUT mux 切时钟：
  - `cam_byte_clk = CAM_SEL ? b_byte_clk : a_byte_clk;`
  - `sel_pixel/valid/in_line/in_frame/vsync` 同理；
  - `sel_tap/delay_done/rst_out/sync_wait/pkt_tgl/vs_tgl/clk_tgl` 同理；
  - `sel_cfg_done/bus_err_lat/lane_sticky/nack_cnt` 同理。
- `camera_a1_uart_top` 的实例化只把 `.clk_cam/.i_a_*/.i_dbg_*/.i_dbg_sys` 改为 `cam_*`/`sel_*`；参数、其余端口、内部 RTL **零改动**。
- `cam_sysstat` 打包（bit20 为选择标记，低 20 位与 b13 完全一致）：
  ```verilog
  wire [31:0] cam_sysstat = {19'd0, CAM_SEL, sel_lane_sticky, 3'd0,
                             cam_cfg_rst_n, cam_pll_locked, cam_xclr_n,
                             sel_bus_err_lat, sel_cfg_done};
  ```
  `cam_xclr_n/cam_pll_locked/cam_cfg_rst_n` 是 A/B 共用，保持原名；`u_dbg_sys_mail` 的输入改为 `{cam_sysstat, sel_nack_cnt}`。
- 核的新 B 端口全部连接；`o_b_*` 中不进入 A+ 的信号允许悬空（`o_dbg_b_*` 未进包者悬空即可），但 **B tap 6 根必须接到选择网络**。
- 顶层保持 `CAM_SEL=1` 交付；不提供运行时切换、不做双路 A+、不在本包改 A 路。

### 3.3 状态包 v5 映射（不扩包）

| 字段 | b13 含义 | b14 语义 |
|---|---|---|
| #0 `cam_clk_tgl_inc` | A 字节时钟活动 | **所选相机**字节时钟活动（B 时为 B） |
| #1 `cam_pkt_tgl_inc` | A CSI 包 | 所选相机 CSI 包 |
| #2 `cam_vs_tgl_inc` | A VSYNC | 所选相机 VSYNC |
| #3 `cam_pix_beats` | A pixel beats | **B 时即 B 的 pix beats**（用户要求） |
| #4 `cam_line_rises` | A line | **B 时即 B 的 line** |
| #5 `cam_frame_rises` | A frame rise | **B 时即 B 的 frame** |
| #6 `cam_frame_falls` | A frame fall | 所选相机 |
| #7 `cam_last_frame_cycles` | A 帧长 | 所选相机 |
| #8 `crop_roi_frames` | ROI 帧 | 所选相机（= `cap_frames`） |
| #9–#11 | crop groups/short/geom | 不变 |
| #12 `cam_phystat` | A tap/delay/rst/sync/in_frame/vsync | 所选相机；位定义不变 |
| #13 `cam_sysstat` | A cfg/bus/lane/pll/xclr | 所选相机；**bit20=`cam_sel`**（0=A，1=B），bit19:0 不变 |
| #14 `cam_nack_cnt` | A NACK | 所选相机 NACK |

- 包长/字段数/VER/XOR/单边沿快照/不插帧内全部不变；`parse_status_v5.py` 只需增加打印 `field13 bit20`，不得改解析长度。
- 结果必须写明：**v5 的 cam 字段是“所选相机”而非“A 专属”**；A 的计数在 `CAM_SEL=1` 时不可见（A 核仍在跑，但不在包内）。这是本包的观测边界，不是缺陷。

### 3.4 时钟/CDC 规则（冻结）

- `clk_cam` 在 `CAM_SEL=1` 时就是 **B 的 `w_b_byte_clk`**（111.375 MHz，源自 B 时钟 lane/4），与 A 的字节时钟**不是同一时钟**；不得用 A 时钟采 B 的 pixel/line/frame。
- `CAM_SEL` 是编译期常量，**没有运行时切换**，因此没有时钟切换毛刺/切换顺序问题；`generate` 保证综合后是直连而非 LUT。
- 所有跨域仍是既有结构：B byte clock → clk_a1 的 `cam_diag_mailbox`（toggle + 2FF + 稳定窗）；sys50 → dhi_clk → clk_a1 的两级邮箱；B byte clock 与 clk_a1 在 SDC 中异步。
- 若 B 字节时钟不存在（模块未接/时钟 lane 死），`clk_cam` 停振：clk_cam 域计数保持、邮箱保持最后值、clk_a1 状态包继续发；这是**可观测的合法失败态**，不得因此拉全局复位或改用 A 时钟采样。

## 4. 强制定向仿真（逐项取证）

| ID | 用例 | 通过判据 |
|---|---|---|
| S1 | **B 几何合成 tap 全链**：`camera_a1_uart_top` 直接喂 B 形状的 3864×2192 RAW10（4 px/beat，行 966 beats，2192 行），ROI 972/556 → 1920×1080 | `pix_beats=2,117,472`、`line_rises=2,192`、`frame_rises=1`、`frame_falls=1`、`crop_roi_frames=1`、`crop_groups=518,400`、`raw_len=2,592,000`、`enc=1`、`exported=1`；44 B 头 + 四 CRC + 严格 zlib；无半帧 |
| S2 | **P1 三黄金（A 路径）**：`micro8x2`、`mid64x8`、`full_grad(1920×1080)` | 压缩字节 SHA256 与 b13 r0 `sim/caps/*.dec` 基线逐字节一致；四 CRC、zlib、`dup=0`、无半帧、`vlog 0/0` |
| S3 | **v5 结构与选择标记** | 241 B / 59 字段 / VER=5 / XOR 0..239；`#3/#4/#5/#6/#8` 等于 S1 的 B 计数；`i_dbg_sys` 常量置 bit20=1 时 `#13` bit20=1，其余位不变；包不插帧内 |
| S4 | **B 时钟停振/无像素**：`clk_cam` 停止或 pixel_valid 恒 0，clk_a1/状态包照常 | 状态包继续发、`bad_xor=0`；cam 字段保持 0（或最后值）；A1 不启动、不挂死、不产生半帧；无 X 传播到帧路径 |
| S5 | **B tap 短行/几何错**：行 beats 不足或超出 ROI | `crop_short`/`crop_geom_err` 增长、该帧不发布/不导出；后续好帧恢复；计数不重复计 |

- S1 必须用**真实 b14 `changed-src`** 的 `camera_a1_uart_top`/crop/frame/core/exporter 编译；合成 tap 只替换相机核，不替换被测链。
- S2 必须用与 b13 相同的 P1 TB/金标；若 TB 实例化核（不是 `camera_a1_uart_top` 直喂），允许只改端口连接（新 B 端口悬空/常量），**不得改金标或 checker**。
- S3/S4/S5 的日志、JSON 汇总与解析器输出必须落 `r0/sim/`。
- 额外静态检查（不占 TD 预算）：`01_build.tcl`/`a1_board.al` 的 core 路径必须指向 `r0/changed-src/f9p_camera_display_core.v`；`CAM_SEL=0` 时 `generate` 的 A 分支与 b13 连接逐线对照表落 `r0/diag/cam-sel-equivalence.md`。

## 5. 回归与状态包（全部必做）

| 项 | 判据 |
|---|---|
| P1 三黄金 | 与 b13 基线逐字节一致；四 CRC、`zlib_ok`、`dup=0`、无半帧、`vlog 0/0` |
| v5 | 241 B/59/VER=5/XOR；单边沿快照；不插帧内；解析器 `bad_xor=0`；`#13 bit20` 正确 |
| B 全链 | S1 的计数/长度/四 CRC/zlib 精确匹配；`pix_beats` 必须是 2,117,472（1 帧） |
| B 失败态 | S4/S5 不挂死、不半帧、不误发布；计数自洽 |
| A 等价 | `CAM_SEL=0` 的 A 分支连接与 b13 一致（静态对照），P1 三黄金通过 |

## 6. 重建与时序裁决（预裁决）

- 复制 b13 `r1/td/**` 到 b14 `r0/td/`；只改 `01_build.tcl`/`a1_board.al` 的路径与 `p2_board.sdc` 的 2 处 B 时钟约束。
- 综合 ≤3 次、布线 ≤2 次、**bitgen 1 次、CWC 1 次**；同参数/seed 不 sweep；不改流程/时序策略。
- 硬门槛：Routed **0 违例端点**、hold ≥0、period 正、ERAM+CWC ≤300。
- **WNS 目标 ≥ +0.05 ns**；预裁决（与 b13 口径一致）：
  - 若 Routed `0 违例` 且 WNS 落在 **+0.003 … +0.05**：**接受为本轮功能/诊断候选**，`timing_caveat=thin_margin_+0.00x`，在 result/manifest 明示“非生产/非板级签核”；**不**为凑 +0.05 删 B 观测。
  - 若 **WNS < +0.003** 或任何负 slack/违例：**停止**，不 bitgen、不下载，交规划。
  - 若最差路径落在**本轮新增的 B 时钟域**：允许一次“只减 B 调试观测（不改 B tap/选择/SDC 语义）”的精简；仍不达标即停。若违例全部落在既有 B `clk_activity/pulse2toggle/dbg_uart`（b13 前未约束的域），也按同一规则处理，**不得放宽 SDC**。
- bit/CWC/BID 与 `cw/compiled.bit` 哈希自洽并冻结；1 bitgen + 1 CWC 后不再重建。

### 6.4 已登记残余风险（不阻塞本包）

1. B 与 A 共用 `CAM_IDELAY_TAP=46`，B 眼图未单独扫；若 B 有包无像素，tap 是首要嫌疑，另立 tap 扫描包。
2. 板级注释记载 MIPI 差分经底板 FEP1B C 排、子卡 A 排侧串 100R 会衰减；A/B 都可能受此影响，属硬件条件，记录不修。
3. B 模块是否物理连接未知；未确认时板级 blocked（§7.0）。
4. B 时钟停振时 clk_cam 域复位无法被采样（与 A 现状同构）；硬件上电值为 0，仿真需显式初始化，不作为新缺陷。

## 7. 板级（先确认 B 已连接；先下载后开 COM8）

### 7.0 用户前置确认（本包唯一 needs_user_input）

开发在 W5 之前必须拿到用户对下面问题的明确回答，并把原话/时间记入 `r0/board/connection-confirmation.md`：

> 第二颗 IMX415 模块是否已物理插在 **B 口**（MIPI-B：J19/H19、J22/H22、G17/G18、J20/J21、L19/L20；B I2C/控制：H13/G13/G20/H20）？
> 请回答：**已连接 / 未连接 / 不确定**。

- `已连接` → 继续 FTDI 预检与下载。
- `未连接` 或 `不确定` → **不下载、不开 COM8**；`board=blocked`、`board_blocked_reason=B_CAM_CONNECTION_UNCONFIRMED`；离线改动 + 构建 + 仿真仍算完成，交规划。
- 不得以“先下载试试”替代确认。

### 7.1 板级步骤（仅在确认已连接后）

1. **FTDI 预检**（不打开 COM8）：`Get-PnpDevice -PresentOnly` 查 `VID_0403&PID_6042`；记录 `FTDI_PRESENT=0/1` 与原始输出。
2. 不在位 → `board=blocked`、**0 下载、0 COM8、不重试**；写 `board_blocked_reason=FTDI_0403:6042_absent`。这是合法完成，不是 FAIL。
3. 在位：
   - **先下载**（1 次 SRAM，JTAG；同一冻结 bit），确认 `B14_DL_OK`，结束 hwserver/释放 FTDI；
   - **再开 COM8**，150 s，用扩展后的 `parse_status_v5.py`；目标：v5 ≥120 个全合法包、`bad_xor=0`；
   - **B 前端门槛**：`#0 clk_tgl` 增量 >0、`#1 pkt_tgl` 增量 >0、`#3 pix_beats` 增量 >0、`#4 line_rises` 增量 >0、`#5 frame_rises` 增量 >0、`#8 cap_frames` 增量 >0；
   - **A+ 门槛**：`enc_frames/exported` 增量 >0；≥1 帧 44 B 头 + header/stream/xform/raw 四 CRC + zlib 全过；无半帧；
   - 记录 `#12 phystat`（tap/delay_done/rst_out/sync_wait）、`#13 sysstat`（cfg_done/bus_err/lane_sticky/**bit20=1**）、`#14 nack_cnt`。
4. 判定分支（必须写进 result）：
   - `#0=0` → B 字节时钟死：查 B 模块/排线/连接器/供电；记录 A/B 硬件条件。
   - `#0>0, #1=0` → 有字节时钟、无 CSI 包：查 B lane 对齐/`rst_out/sync_wait`/I2C cfg。
   - `#1>0, #3=0` → **有包无像素**：记录 tap/lane_sticky/nack/`frame_rises`；判为 B 前端 PHY/IDELAY/数据格式问题，本包停止，不猜改寄存器。
   - `#3>0, #8=0` → 有像素、crop 未成帧：查 `#10 short/#11 geom` 与 line/frame 语义。
   - `#8>0, exported=0` → crop 成帧但 A+/DDR/导出未通：按 b13 证据口径交规划（本包不修 DDR）。
   - `exported>0` 且四 CRC+zlib → **板级通过**。
5. 不写 Flash、不 PCIe/RK、不做双路/G4；下载 ≤1 次；失败不第二次。

## 8. 预算、停止与回退

- 开发：**120 min / 60 calls**；TD **3 会话**、综合 ≤3、布线 ≤2、bitgen 1、CWC 1、下载 **1**、Flash 0。
- 立即停止（不建/不下载）：
  - 核的 B 输出不是纯 assign，或 A 端口/逻辑被改动；
  - `CAM_SEL` 需要运行时切换/时钟 LUT mux，或必须改 `camera_a1_uart_top` 功能；
  - S1 B 全链不能导出，或 S2 任一 P1 黄金非逐字节一致；
  - v5 破坏 241 B/59 字段/帧内边界；
  - 综合 3 次仍负；布线 2 次仍 <+0.003 或任何违例；ERAM+CWC>300；
  - 需要第二个 bitstream，或修复需要改 crop 几何/ROI/帧格式/DDR IP/PAXI/降频/false path；
  - B 未确认连接 → 板级 blocked，不下载；
  - B 也无像素 → 停止并留证（说明 A/B 硬件条件），不第二次下载。
- 回退：源以 b13 r1 为基线；失败只回退 b14 本地副本，不改 upstream/旧 run/manifest；`CAM_SEL=0` 即回到 b13 A 路径。
- 用户已授权本 run 的 1 次 SRAM 下载（仅在本包 §7.0 确认后使用）；仍**不写 Flash**。

## 9. 交付物（缺一不可）

- `r0/changed-src/**`（11 文件：2 改 + 9 逐字节不变）+ `r0/rtl-diff-r0.patch`
- `r0/sim/**`（S1–S5、P1 三黄金、v5、日志/汇总 JSON）
- `r0/diag/cam-sel-equivalence.md`（`CAM_SEL=0` 与 b13 连接逐线对照）
- `r0/td/**`（综合/布线报告、1 bitgen + 1 CWC、bit/CWC/BID/compiled、params、final STA、SDC diff）
- `r0/board/**`（连接确认、FTDI 预检；若下载则下载日志 + 150 s 采集 + v5 解析 + 帧解码；扩展后的 `parse_status_v5.py`）
- `CANDIDATE-MANIFEST-b14-cam-b-r0.json`、`r0/artifact-hashes.txt`
- `result-r0.md`、`lessons-r0.md`
- 若 board blocked：result 明确 `board=blocked`、原因、0 下载，不宣称板级通过。

## 10. 下一次准确启动/恢复文本（开发）

> 恢复 `20261020-0209_singleA_aplus_closedloop` 的 **`T10.b14-cam-b` r0**（ready；1 bitgen+1 CWC；SRAM 下载 ≤1；B 模块连接未确认时板级 blocked）。
> 先读 `T10.b14-cam-b/{dev-plan.md,fpga-design-guide.md,handoff.md,dispatch.json}`、
> `T10.b13-ddr-retry/r1/td/src/src/f9p_camera_display_core.v`（SHA `C9DE0D9C…05089`）、
> `T10.b13-ddr-retry/r0/changed-src/**`、`T10.b13-ddr-retry/r1/td/**`、`T10.b13-ddr-retry/r1/board/captures/status_v5.txt`。
> 已确认事实：B I2C `u_cfg_b` 已使能（`r_rst_n_slow`, mode=1）、B MIPI `u_csi_b` 已复位释放且 `I_rx_en=1`、
> B 的 `w_b_pixel/valid/in_line/in_frame/vsync/byte_clk` 均存在、B 引脚已在 `board_p2.adc` 分配；不需要“使能 B”。
> 目标：核只加 B tap/B 诊断 assign；`p2_a1_board_top` 用 `localparam CAM_SEL=1` + `generate` 把 `clk_cam`/tap 切到 B，
> `cam_sysstat[20]=cam_sel`；`p2_board.sdc` 加 `mipi_b_byte_clk` generated clock 与异步组；v5 保持 241 B/59 字段，
> `#3/#4/#5` 记录所选相机（B）的 pix/line/frame；P1 三黄金逐字节不变；Routed 0 违例（WNS 按 §6 预裁决）；
> 板级先确认 B 已连接，再 1 次 SRAM 下载、COM8 150 s，先看 B 的 clk/pkt/pix/line/frame/cap，再看 enc/exported 与四 CRC+zlib；
> 若 B 也无像素 → 停止留证，不第二次下载。
> 120 min/60 calls；TD 3 会话/综≤3/布≤2/bitgen 1/CWC 1/下载 1；失败即停，不自扩预算，不批删。
