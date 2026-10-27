# T10.b7-cam-diag 开发计划（r0-diag）

日期：2026-10-24。本轮唯一正式包；两级（需求 → 工作包）；5 项语义步骤。**状态：ready**。
上游事实：`T10.b5-a1-htab-pipe/r1-diag/result-r1diag.md` —— 60 s 内 8 个计数器全 0，`cap_frames=0`；状态包 61/61、XOR 0 错；UART/clk_a1/复位/DDR 已证明正常。
本包**只加相机前端可观测性**，不修相机、不改图像帧语义。

## 1. 任务表

| task_id | 问题/产物 | 实际工作树/允许写路径 | 依赖 | functional | engineering | system | 必要 G 层 | 状态 | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|
| T10.b7-cam-diag | 无法区分“MIPI 无数据 / I2C 未成功 / crop 未收帧”，因为状态包只有 A1 链下游计数。产物：能回答三问的相机前端计数器 + v2 状态包 + 一次 60 s 板级采集 | 新包 `workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b7-cam-diag/**`；TD 工程 `r0/td/**` 内只改 `src/p2_a1_board_top.v`、`src/f9p_camera_display_core.v`（**只加输出端口与 assign**）、`changed-src/camera_a1_uart_top.v`、`changed-src/a1_uart_export.v`、新增 `changed-src/cam_diag_mailbox.v`、`01_build.tcl` 文件表 | b5 r1-diag v1 包（35 B，61/61）；b6 候选作 A1 基线；P1 三例金标；b6 r0 TD 模板 | P1 三例逐字节；core SHA 保持 `6797db05…35bb`；v2 包 sim 0 bad XOR、字段常量可复现；MIPI 死时包仍照发 | Routed 0 违例、WNS ≥ +0.05、hold ≥ 0、period 0、资源在器件内；新逻辑不进 clk_a1 关键路径 | 图像帧头/CRC/长度/字节序/DDR 布局/UART 数据帧/SDC/引脚不变；线格式只改**空闲状态包**（v1→v2，带 LEN/VER）；1 次 SRAM 下载、0 Flash | G0/G1/G2/G3/G4 | ready | 派 fpga-dev |

不适用项与理由：
- 不需要“修好相机”的验收项：本包验收的是**可观测性与证据自洽**，不是出图。
- 不需要改动 I2C 寄存器表/MIPI 配置/IDELAY tap 策略：任何这类改动会让本轮无法区分“观测缺陷”与“相机缺陷”，属下一个修复包。

## 2. 五项语义实现步骤（每步可独立复核）

1. **搭包与冻结起点**：建 `r0/{changed-src,sim,td,board}`；从 `T10.b6-a1-htab-nw/r0/td` 复制 `src/`、`a1_eng_top.v`、`a1_small_top.sdc`、`p2_board.sdc`、`board_p2.adc`、`01/02/03_*.tcl`（不复制 `a1_board_Runs/`、`cw/`、旧 bit/cwc/bid/大报告）；从 b5 r1-diag 复制 `changed-src/{a1_uart_export.v,camera_a1_uart_top.v}` 作为起点；记录全部 SHA、工具版本、盘符。
2. **相机核只加诊断输出**：在 `r0/td/src/f9p_camera_display_core.v` 增加指南 §3 的 15 个 output，每个**只** `assign` 到已有内部信号（`w_a_cfg_done`、`r_a_err_lat`、`r_a_nack_cnt`、`r_a_lane_sticky`、`w_a_delay_tap/done`、`w_a_rst_out`、`w_a_sync_wait`、`w_a_pkt_tgl/vs_tgl/clk_tgl`、`w_xclr_n`、`w_pll_locked`、`r_rst_n_slow`、`w_a_in_frame`、`w_a_vsync`）。**不加时序逻辑、不改 I2C 表/mode=1/像素路径/预览/HDMI**。
3. **计数 + 跨域邮箱**：新增 `cam_diag_mailbox.v`（通用 toggle 邮箱，参数 W/DIV_BITS）；`camera_a1_uart_top` 内 `u_dbg_cam_mail`（clk_cam → clk_a1，8 字：7 计数 + 1 物理状态字）；`p2_a1_board_top` 内 `u_dbg_sys_mail`（sys_clk50m → clk_a1，2 字：系统状态 + NACK 计数）。clk_a1 侧对 `clk_tgl/pkt_tgl/vs_tgl` 做 2FF + 边沿计数。计数器定义见指南 §4。
4. **状态包 v2 + 解析器**：`a1_uart_export` 输出 97 B（`A5 5A | LEN=0x61 | VER=0x02 | 8×u32 legacy | 15×u32 cam | XOR8`），空闲门控、1 Hz 节拍、legacy 字段顺序不变；新写 `board/parse_status_v2.py`（magic/LEN/VER/XOR 校验、delta 累加含 32 位回绕、level 字段取 OR/min/max、直接输出三问）；`r0/sim/tb_status_pkt_v2.v` 打常量验证。
5. **工程 → 候选 → 采集**：TD `01_build.tcl`（syn+route，冻结策略组同 b6 r0）→ 门槛 → `02_bitgen.tcl`（1 次，fail-closed）→ `03_cwc.tcl`（1 次）→ **1 次 SRAM 下载**（`board/download_sram_camdiag.tcl`，不写 Flash）→ COM8 115200 采 **60 s** → `parse_status_v2.py` → 写 `result-r0diag.md` 的三问结论与判定。

## 3. 三问判定矩阵（必须逐条写进 result-r0diag.md）

解析器输出“first / last / delta / OR”四列后，按此表给结论；每问要求**≥2 个独立计数器互相印证**，不得只凭一个字段。

| 问 | 观测（60 s delta 或 level） | 结论 | 下一步（不在本包执行） |
|---|---|---|---|
| MIPI 有没有数据 | `cam_clk_tgl_inc` delta = 0 | MIPI 字节时钟死（PHY/PLL/传感器 MCLK 侧） | 查 MCLK/PLL/cam_cfg_rst_n、示波器 MIPI clk |
| | clk_tgl > 0 且 `cam_pkt_tgl_inc`=0 且 `cam_pix_beats`=0 | 字节时钟活、**无 CSI 包**（lane 对齐/sync/传感器未出流） | 查 lane_sticky、rst_out、sync_wait、cfg_done |
| | `cam_pix_beats` > 0 且 `crop_groups` = 0 | 有像素但 crop 没接收（tap/line/frame 语义） | 查 frame_rises/falls、in_frame_now、line_rises |
| | beats > 0 且 crop_groups > 0 且 `crop_roi_frames`=0 | crop 收到像素但 ROI 从不完整 | 看 `crop_short`/`crop_geom_err` 比例 |
| I2C 有没有成功 | 任一包 `cfg_done`=1 且 `nack_cnt` 60 s 无增长 且 `xclr_n`=1 | I2C 配置成功、传感器已出复位 | 进入 MIPI 分支 |
| | 全程 `cfg_done`=0 | I2C 未完成（表/时序/地址/供电） | 查 nack_cnt、bus_err_lat、SCL/SDA 波形 |
| | `nack_cnt` 增长 >0 | I2C 有 NACK | 查传感器供电/上拉/地址 |
| | 任一包 `xclr_n`=0 | 传感器被按在复位 | 查 camera_startup / XCLR 引脚 |
| crop 有没有收到帧 | 60 s 内 `crop_roi_frames` delta > 0 | 收到完整 ROI 帧（但仍可能不进 A1，另查 legacy cap/raw_pub） | 回 A1 链 |
| | `crop_short` delta > 0 | 帧在 ROI 完成前结束 | 查 frame_falls 与 last_frame_cycles |
| | `crop_geom_err` delta > 0 | 行内 group 数不符（行长/line 语义） | 查 line_rises 与 CAM_W |
| | 三值全 0 且 groups=0 | crop 输入从未有有效 beat | 回 MIPI 分支 |

## 4. 包级 PASS 门槛（事先冻结，不得事后放宽）

PASS 必要条件，缺一即 FAIL：
1. 60 s 内收到 **≥55 个 v2 包**，`bad_xor=0`，LEN=97、VER=2 全对，无半包/丢字节。
2. 三问各有一个**明确**答案，且每问有 ≥2 个独立计数器一致；答案写入 `result-r0diag.md`（禁止“数据不足，待定”式的含糊结论）。
3. 图像路径未变：P1 三例逐字节（`fa513a2b…`/`ee61e620…`/`b992a8ad…`）；core SHA 仍 `6797db05…35bb`；diff 证明只碰诊断/包/文件表。
4. 工程：Routed **0 违例**、WNS ≥ **+0.05**、TNS 0、hold ≥ 0、period 0、组合环 0、无时钟网 0、资源在器件内。
5. G3：1 bitgen + 1 CWC，`compiled.*` 与父文件逐字节相同；**1 次 SRAM 下载、0 次 Flash**。
6. 明确的 not_run 声明：本包不证明图像正确、不证明 A+ core 硅上正确、不证明需求二/三完成。

**判定语义**：即使结论是“MIPI 完全没数据”，只要三问都可判定、计数自洽、图像路径未变，**本包仍判 PASS**（诊断目的达成）；反之“相机出图了但包不可解析”判 FAIL。

## 5. 预算与停止条件

| 项 | 上限 | 说明 |
|---|---|---|
| 开发 | 90 min / 50 calls | 单会话；含仿真、TD、下载、采集、解析 |
| TD | 3 sessions / 150 min | S1 syn+route，S2 bitgen，S3 CWC/应急 |
| 综合 | ≤2 次 | 第 1 次失败只允许一次局部修正 |
| 布线 | ≤1 次 | 不改 QoR 旋钮/seed/时钟/SDC |
| bitgen | 1 次 | fail-closed |
| CWC | 1 次 | 与 bit 同候选 |
| 下载 | **1 次** | SRAM only；用户本轮明确授权；不写 Flash |
| 综合测试 | 45 min / 30 calls | 不重跑 TD、不第二次下载 |

停止条件（任一）：
- 需要改 I2C 表、`I_cam_mode`、MIPI RX/tap 策略、引脚或 SDC 才能继续 → **停止**，交规划；那属于修复包，不属诊断包。
- TD 许可/磁盘/ModelSim 缺失，或板卡/COM8 不可用 → blocked，附恢复入口，不空转、不换板重试。
- 60 s 内包数 <10 或 XOR 大量错 → 先查 UART/采集，仍不行则 blocked；**不得**用第二次下载“再试一次”。
- 布线有违例或 WNS < +0.05 → 停止，不 bitgen；保留报告交规划。
- 需要 >1 次下载、写 Flash、或改图像帧/CRC/DDR → 停止。

## 6. 交付物

- `r0/changed-src/{camera_a1_uart_top.v,a1_uart_export.v,cam_diag_mailbox.v}` + `r0/rtl-diff-r0diag.patch`
- `r0/td/src/{p2_a1_board_top.v,f9p_camera_display_core.v}`（诊断输出）+ `01/02/03_*.tcl` + 报告 + `a1_board.bit/.cwc/_inst.bid`
- `r0/sim/`：`tb_status_pkt_v2.v` 日志、常量字节、parse 输出；P1 三例 `.dec`/stats/日志
- `r0/board/`：`download_sram_camdiag.log`、`captures/com8_60s.{bin,dec,stats}`、`status_v2_60s.txt`、`parse_status_v2.py`
- `CANDIDATE-MANIFEST-b7-cam-diag-r0diag.json`、`artifact-hashes.txt`、`result-r0diag.md`、`lessons-r0diag.md`

## 7. 回退

- 诊断输出/邮箱在 90 min 内不能稳定（仿真不解码、或 clk_cam 死时包卡住）→ 回退到 b5 r1-diag v1 包，保留 FAIL 证据；**不得**把 v1 全 0 当已诊断。
- TD 失败：保留 b6 bit/CWC 作为 A1 基线历史候选，不得声称 b7 已上板；b7 无 bit 即 G3 not_run。
- 板级采集失败且已用掉唯一 1 次下载：保留 bit/CWC 哈希与失败日志，交规划申请新的板窗；不得自行第二次下载。
- 任何回退只替换本包内文件，不动 b6/b5/upstream/`workflow/tasks.json`。

## 8. 下一动作

主按 `dispatch.json` 派 **fpga-dev**（输入本计划 + `fpga-design-guide.md` + `handoff.md`）。开发完成并在包内冻结 manifest 后，由主新建**一个**独立综合测试者按同一 manifest 验收（不重跑 TD、不第二次下载）；同任务 FAIL 才续原开发/原测试，最多三轮实际修复。
