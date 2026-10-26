# T10.b15-ddr-pace — dev-plan（规划冻结，2026-10-26）

- run：`20261020-0209_singleA_aplus_closedloop`（项目根 `D:\fpga\ph1p100`）
- 父任务：T10（**保持 blocked**；本包完成也不把 T10 置 done）
- 角色：开发 = fpga-dev（fpga-planner 暂不可用，本包以 general 代行规划；开发仍按 fpga-dev 合同执行）；冻结后另派 **1 个新综合测试者**（functional/engineering/system 是同一人的检查清单）
- 状态：**ready**；`needs_user_input=false`；批大小 1；1 个主要可验收目标、1 个正式工作包（5 个语义步骤）
- 本包主题：**只改 DDR 读并发**——让 bridge 一次只压 1 笔未完成 AR、R 回来再发下一笔，且 `paxi_rready` 在整笔 burst 期间永不掉，消除“每次尝试少回 1 个 R”的确定性丢数据；**不动相机/几何/帧格式/v5/时钟**

## 0. 冻结输入与基线（不得重新解释）

### 0.1 b14 r0 板级事实（v5，`T10.b14-cam-b/r0/board/captures/status_v5.txt`）

| 观测 | 值 | 含义 |
|---|---|---|
| `CAP sel=0` / `sysstat bit20=0` | A 路 | A 相机已恢复，本轮继续用 A |
| `cap_frames` | **4,470** | crop 成帧正常 |
| `pix_beats` / `line_rises` | 正常增长（每帧 2,117,472 beats / 2,192 行量级） | tap→crop 几何正确 |
| `crop_short` / `crop_geom_err` | **0 / 0** | 几何无错 |
| `raw_pub` | **4,470** | 每帧都发布到 DDR 槽 |
| `timeout` / `retry` / `giveup` | **13,410 / 8,940 / 4,470** | 恰好 3 / 2 / 1 **每帧** |
| `enc_frames` / `exported` | **0 / 0** | 一帧都没编出来 |
| `ar` / `r` | **17,213,681 / 17,200,031**（差 13,650） | 每次读尝试都少回 1 个 R（H4 稳定复现） |
| `stale_guard` / `stale_r` / `rd_wait` | 0 / 0 / 0 | 晚到 R 未被现有 stale 路径捕获 |

- 判定：camera→crop→publish 全通，**卡点唯一在 DDR 读响应**；超时/重试兜底按设计在工作（3 次尝试后 giveup），但每次尝试都因“少 1 个 R”而失败，所以 `enc/exported` 恒为 0。
- 本包不是修相机、不是改 crop、不是换路；是**把读通路改成严格串行单笔**，让丢 R 不再发生；超时/重试保留为兜底（发生时应为 0）。

### 0.2 源码基线 = b13 r1 A 路源集（逐字节）

b14 r0 的 `td/src/p2_a1_board_top.v`（`48881D57…E561B`）**等于 b13 r1 版本**（无 `CAM_SEL`），且 b14 r0 板级跑的是这份 A 路构建；`p2_ddr_bridge.v` 自 b13 起**从未改过**（`BFF1A358…49731`）。故本包基线取 **b13 r1 构建源集**，只允许改 `p2_ddr_bridge.v` 一个文件。

| 文件 | b13 r1 SHA256（前 12） | 本包 |
|---|---|---|
| `p2_ddr_bridge.v` | `BFF1A3589BD2` | **唯一允许功能修改** |
| `f9p_camera_display_core.v` | `C9DE0D9C176E830DF35833EFF7E91B811D954FB5480BC13E1FB122EF23305089` | 逐字节不变 |
| `p2_a1_board_top.v` | `48881D574352FD2C61F7587D3687F215BB11EA18D5B5D0B4772820A938DE561B` | 逐字节不变 |
| `camera_a1_uart_top.v` | `ACC1EFF329AA` | 逐字节不变 |
| `a1_ddr_slot_store.v` | `6C619CF90E54` | 逐字节不变 |
| `a1_ddr_arb2.v` | `B84019BDA057` | 逐字节不变 |
| `a1_frame_top.v` | `0064607ACEB2` | 逐字节不变 |
| `a1_deflate_core.v` | `A91C2ED82FBE` | 逐字节不变 |
| `a1_raw_crop.v` | `33A6FEE77FD1` | 逐字节不变 |
| `a1_uart_export.v` | `F8F9E4E354B5` | 逐字节不变 |
| `cam_diag_mailbox.v` | `352AF7C85094` | 逐字节不变 |

- 工作树：**`D:/fpga/ph1p100`**（唯一主源）。构建模板：`T10.b13-ddr-retry/r1/td/**`（Tcl/ADC/SDC/`src/`）；仿真模板：`T10.b13-ddr-retry/r0/sim/**`、`T10.b12-r1-last/r0/sim/**`；只读复制，不改旧包。
- 路径：`P:`=项目根，`W:`=`r0/sim`；TD `T:`=`r0/td`，`Y:`=项目根；`X:` 不映射项目根。
- 禁止批量删除（只能一次 `Remove-Item <单文件>`，需批量先问用户）。

### 0.3 CAM_SEL 与本包裁定（冻结）

- 本轮 **不引入 `CAM_SEL`**：A 路就是 b13 的唯一路径（板级实测 `sel=0 / bit20=0`）。b14 的 `CAM_SEL` generate 变体**不合并**，作为可选后续主题挂起。
- “B 路径代码保留但不选”：`f9p_camera_display_core.v` 内的 `u_cfg_b`（B I2C）与 `u_csi_b`（B MIPI）**原样保留、照常运行**，其 tap/诊断仍只接内部计数器、不进 A+、不进 v5；核文件逐字节不变即满足。
- 理由：b14 r0 的 A 路 bit 是板级跑过的那一份；本包唯一变量必须是 DDR 读并发，合并 B 选择代码会引入与卡点无关的 SDC/时钟域/时序变量。

### 0.4 不可改动（冻结）

- 44 B 帧头/CRC、压缩帧字节、crop 几何/ROI（`CAM_W=3864, CAM_H=2192, ROI_X=972, ROI_Y=556, W=1920, H=1080`）、四槽 DDR 布局、UART_DIV=1628、HB_DIV、引脚、时钟频率（187.5 MHz / 111.375 MHz）、`board_p2.adc`、`a1_small_top.sdc`、`p2_board.sdc`。
- **状态包 v5 保持不变**：241 B / 59 字段 / VER=5 / LEN=241 / XOR 0..239 / 字段名与顺序。**不新增字段、不改语义**；新证据用既有 `ar_cnt / r_cnt / rlast_cnt / stale_r_cnt / stale_guard_cnt / timeout / retry / giveup` 承载（`parse_status_v5.py` 只允许把 `rlast_cnt` 加进 print，不得改解析长度/字段数）。
- 其余 10 个 RTL 文件、vendor/`upstream/**`、旧 run/证据/manifest、`workflow/tasks.json` 不改。
- 不写 Flash、不 PCIe/RK、不做双路/G4；不 false path/multicycle/改 seed/降频/新增 ERAM 实例；不改 DDR IP/PAXI 协议。

## 1. 本轮唯一目标

**问题**：A 路画面链路已通（4,470 帧），但每次 DDR 读尝试都少回 1 个 R，三次尝试全废，`enc/exported=0`。现有 bridge 的“单笔 AR”只是名义上的：`ar_pending` 在**第一个 R 拍**就清零，之后既可能提前放行下一笔 AR，也可能在 `r_expected=0` 时把晚到的 R 拍**吞掉**（`rready=1` 但不入 RF）。

**产物**：一个最小“严格单笔读”候选：
1. `p2_ddr_bridge.v` 读引擎改为：AR 只在 `!ar_busy && AF 有请求 && 读数据通路空 && ddr_rdy && !rd_hold` 时发；`ar_busy` 只在 `r_hs && paxi_rlast` 才清；`paxi_rready` 在整笔 burst 与 purge/guard 窗口内**恒为 1**；
2. b13 的超时/重试（8192 clk_a1 / 最多 2 次）与 purge/guard 逻辑**逐语义保留**；
3. 状态包 v5 不变，板上新增证据用 `ar/r/rlast` 三元组判定 outstanding；
4. 仿真：正常整帧、丢 1 R、连续 3 帧、full 两帧、P1 三黄金、b12/b13 回归、抗逆例、v5 结构；
5. Routed 0 违例（WNS 按 §6），1 bitgen + 1 CWC；
6. 板级先下载后开 COM8 150 s：`timeout/retry/giveup` 归零、`enc/exported` 增量 >0、≥1 帧四 CRC+zlib。

### 1.1 工作包最小表

| task_id | 问题/产物 | 工作树/允许写路径 | 依赖 | functional | engineering | system | 必要 G 层 | 状态 | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|
| `T10.b15-ddr-pace` | bridge 严格单笔读 + rready 常开；A 路整帧导出 | `D:/fpga/ph1p100`；只写 `run/T10.b15-ddr-pace/**` | b13 r1 源集；b14 r0 板级证据 | 正常整帧/丢 1 R/连续 3 帧/full 两帧/P1 三黄金/b12+b13 回归/抗逆例/v5 结构 | Routed 0 违例、WNS 预裁决、ERAM+CWC≤300、1 bitgen+1 CWC、竞态/并发断言 | 先下载后 COM8、150 s、timeout/retry/giveup 归零、enc/exported 增量>0、≥1 帧四 CRC+zlib | G0/G1 仿真；G2 构建；G3 板级；G4 not_run | ready | 派 fpga-dev 执行本计划 |

## 2. 唯一正式包与工作步骤

| # | 语义步骤 | 预算 | 产物/门槛 |
|---|---|---|---|
| W1 | 冻结基线 + 读通路事实采集（只读） | ≤20 min | 复制 b13 r1 11 文件到 `r0/changed-src/`，逐个记 SHA256；从 IP 端口/参数与仿真波形确认：PAXI 每笔 AR 的 burst 拍数 `L_max`、`paxi_rlast` 语义、`paxi_rdata` 位宽、RF 深度；写入 `r0/diag/paxi-read-facts.md`（含证据位置，不猜） |
| W2 | bridge 严格单笔读（只改 `p2_ddr_bridge.v`） | ≤35 min | §3 规则 R1–R5 全部实现；`git diff` 只落在读引擎/`paxi_rready`/读数据写使能及必要计数；超时/重试/purge/guard 语义不变 |
| W3 | 仿真 S1–S8 + P1 + 回归 | ≤40 min | §5 全过；日志/JSON 落 `r0/sim/`；`if_max_os==1` 断言成立 |
| W4 | 重建（综合≤3、布线≤2、1 bitgen + 1 CWC） | TD 内 | Routed 0 违例、hold≥0、period 正、ERAM+CWC≤300；WNS 按 §6；bit/CWC/BID/compiled 自洽冻结 |
| W5 | 板级（先下载后开 COM8） | ≤20 min | FTDI 在位 → 1 次 SRAM 下载成功后才开 COM8 150 s；§7 门槛；失败按 §7.4 分支停 |

### 2.1 写域/允许改的源

- 允许写：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b15-ddr-pace/**`（`changed-src/`、`sim/`、`td/`、`board/`、`diag/`、manifest、日志）。
- 源先复制到 `r0/changed-src/` 再改。**允许功能修改：仅 `p2_ddr_bridge.v`**。
- **允许的机械修改**：`01_build.tcl` / `a1_board.al` 只把 11 个 `changed-src` 路径改指 b15 本地副本（流程/参数/seed 不变）；`parse_status_v5.py` 只加打印 `rlast_cnt`（不改长度/字段数）；板级脚本（`run_board_*.ps1`/`capture_com8.py`/`dl_b15.tcl`）复制改 bit 路径/COM/时长。
- 若 W2 必须改 `capture_async_fifo` 的实例参数（`ADDR_BITS` 4→5）以加深 RF：**允许，但仅限 `p2_ddr_bridge.v` 内的实例化参数**，不得改 FIFO 模块本体；且必须在 `r0/diag/paxi-read-facts.md` 说明 `L_max > 16` 的证据与资源代价。

## 3. RTL 规格（冻结语义，允许等价实现）

只改 `p2_ddr_bridge.v` 的读通路。信号名沿用现有实现（`ar_pending`、`af_*`、`rf_*`、`s_*`、`rd_hold`、`ddr_rdy`）。

**R1 单笔占用标志**
```
ar_busy:  set  于 paxi_arvalid && paxi_arready
          clear 仅在 paxi_rvalid && paxi_rready && paxi_rlast
          （rd_hold/purge 事件仍可强制清除，保持 b13 语义）
```
禁止再用“任一 R 握手”清零（现实现 `ar_pending <= 0` 在首拍即清 → 名义单笔、实际可交错）。

**R2 发 AR 条件（严格串行）**
```
paxi_arvalid = af_rvalid && !ar_busy && rf_path_empty && ddr_rdy && !rd_hold
rf_path_empty = (RF 占用 == 0) && (skid 空, 跨域已同步)
```
- `rf_path_empty` 用写侧占用计数实现（clk_ddr 侧 push 加、clk_a1 侧 pop 以 toggle 跨界 2FF 后减）。`rf_level == 0` 是最保守形式；若 `L_max ≤ RF_DEPTH` 有证据，可用 `rf_level <= RF_DEPTH - L_max` 作为等价实现，但必须在 `paxi-read-facts.md` 写明 `L_max` 与证据。
- `AF`（地址 FIFO）空/非空由 `af_rvalid` 表达；“AF 空才发”实现为：**一笔 AR 从被接受到 `rlast` 之间不得再消耗 AF 条目**（`af_pop` 只在 `paxi_arvalid && paxi_arready`，不得被 purge 以外的路径提前弹）。

**R3 `paxi_rready` 常开**
```
paxi_rready = 1'b1    // 所有时刻
```
- 依据：只要 `ar_busy` 或在 purge/guard 窗口内就永不掉；不在这些窗口时也必须为 1（吞掉孤立 R 并计数）。
- 因此 **RF 不得溢出**：由 R2 的 `rf_path_empty` 前置保证“一笔 burst 一定有空间”，不得用“rready 背压”替代空间保证。
- 若 `L_max > RF_DEPTH` 且无法加深 RF：**停止**（见 §8），不得用 rready 背压。

**R4 读数据写使能**
```
rf_push = paxi_rvalid && paxi_rready && ar_busy_window   // 一笔 burst 期间恒真
```
- 一笔 burst 期间 `paxi_rvalid && rready` 的每一拍都必须 `rf_push`；不允许出现“吞掉不入队”的拍（现实现 `rf_push = paxi_rvalid && r_expected` 在 `ar_pending=0` 时会吞拍）。
- 孤立/晚到 R（`!ar_busy_window`）继续按 b13 语义**只计数、不入队**（`stale_r_cnt`），且 `rready=1` 不得阻塞。

**R5 兜底与既有逻辑逐语义保留**
- `TIMEOUT`（8192 clk_a1）、`retry` 上限 2、`giveup` 释放槽、`A1_GUARD_N=70000`、`BRIDGE_GUARD_N=65536`、`DDR_PURGE_N=4`、`A1_PURGE_N=4`、`rd_abort` toggle 同步、`s_arready` 门控（`!a1_purge_act && !a1_ar_hold_act`）**全部不变**。
- 超时/重试计数语义不变（v5 `#56/#57/#58`）；目标是在板级归零，但仍必须作为兜底存在。

**R6 并发 2 笔（仅兜底）**
- 默认 **MAX_OS=1**。只有 S1/S3/S4 证明 1 笔无法满足帧预算（每帧导出时间使持续吞吐 <77.76 MB/s）**且** 仿真证明 2 笔时 R 归属无歧义（每笔独享 `rlast` 计数、无交错误配）时，才允许 `MAX_OS=2`。
- 一旦采用 2 笔：必须在 `r0/rtl-diff-r0.patch`、manifest、result 明示 `MAX_OS=2` 及理由；同样必须 `if_max_os` 断言覆盖。不得出现 3 笔及以上。

## 4. 观测与证据约定

- v5 结构不变；outstanding 由 `ar_cnt - rlast_cnt`（未完成 AR 数）与 `ar_cnt - r_cnt`（丢拍数）表达。
- 期望（健康）：静止时 `ar_cnt - rlast_cnt ∈ {0,1}`；`ar_cnt - r_cnt ∈ {0, L_max-1}`（burst 在途）；`timeout=retry=giveup=0`；`stale_r=0`、`stale_guard=0`。
- 仿真额外内部计数（**不进 v5**，只进 sim 日志/JSON）：
  - `if_max_os`：`ar_busy` 为真期间观察到的最大并发笔数（必须恒为 1，或批准的 2）；
  - `if_short_burst`：AR 未以 `rlast` 收尾而被 purge/guard 关闭的次数；
  - `last_ar_addr`：最近一笔 AR 地址（用于失败定位；仿真必须打印，板上若不可得则用 §7.4 的 ar/r/rlast 三元组留证）。
- 每次读尝试必须有 `attempt_id`（或等价的帧号+尝试号）在 sim 日志中可对齐 `timeout/retry/giveup`。

## 5. 仿真矩阵（全部必做，逐项留证）

| ID | 用例 | 通过判据 |
|---|---|---|
| **P1** | 三黄金 `micro8x2` / `mid64x8` / `full_grad(1920×1080)` | 压缩字节 SHA256 与 b13 r0 `sim/caps/*.dec` **逐字节一致**；四 CRC、`zlib_ok`、`dup=0`、无半帧、`vlog 0/0` |
| **S1** | 正常整帧（A 几何 3864×2192 → ROI 972/556 → 1920×1080），**不注入丢 R** | `pix_beats=2,117,472`、`line_rises=2,192`、`frame_rises=1`、`crop_roi_frames=1`、`crop_groups=518,400`、`raw_len=2,592,000`、`enc=1`、`exported=1`、四 CRC+严格 zlib、无半帧、`timeout=retry=giveup=0`、`if_max_os==1` |
| **S2** | **丢 1 个 R**（burst 中部） | 第一次尝试 `timeout=1` → `retry=1` → 第二次整帧成功；`giveup=0`；最终帧四 CRC 与 golden 一致；晚到 R 只计 `stale`、不入队、不污染；无重复拍（`dup=0`） |
| **S3** | **连续 3 帧** | 3 帧全部 `exported`、每帧四 CRC+zlib；每帧计数精确；无跨帧残留；`raw_drop=cmp_drop=0` |
| **S4** | **full 两帧**（两帧满尺寸背靠背） | 2 帧 `enc=2/exported=2`，两帧四 CRC+zlib；无 `raw_drop/cmp_drop`、无半帧、不挂死；四槽复用正确 |
| **S5** | v5 结构 | 241 B / 59 字段 / VER=5 / XOR 0..239；单边沿快照；不插帧内；`bad_xor=0`；cam 字段与 A 路计数一致 |
| **S6** | b12 / b13 回归 | 重跑 b12 R1（7 次拒收→LAST→两好帧恢复、槽归还、`raw_abort_cnt`）与 b13 重试/保护窗/晚到 R 用例 → 全部与冻结基线一致 |
| **S7** | 抗逆例（新增必测） | (a) 丢**带 `rlast` 的最后一拍**；(b) 超时后到达**重复/晚到 R**；(c) `arready` 连续压低 100 拍；(d) burst 中部 `rvalid` 空 64 拍。四例均：不丢拍、不挂死、不半帧；该超时的超时、该恢复的恢复 |
| **S8** | 并发/占用断言 | S1/S3/S4 全程 `if_max_os==1`（或批准的 2）；`ar_cnt - rlast_cnt ≤ MAX_OS`；`ar_cnt - r_cnt` 不超过在途上限；`if_short_burst` 只在超时用例出现 |

- 全部用例必须用**真实 b15 `changed-src`** 的 `camera_a1_uart_top`/crop/frame/core/exporter 编译；只有 PAXI 侧模型允许注入丢 R/背压/延迟。
- 若 S2/S7 依赖 b13 已有 PAXI 模型：可扩展模型（注入），**不得改被测 RTL** 以适配用例。
- 仿真必须给出“**未注入丢 R 时 0 丢拍**”的波形/计数证据（这才是本包的根因验证）。

## 6. 重建与时序裁决（预裁决）

- 复制 b13 `r1/td/**` 到 `r0/td/`；只改 `01_build.tcl`/`a1_board.al` 的 11 个路径；其余 Tcl/ADC/SDC/流程/seed 不变。
- 综合 ≤3 次、布线 ≤2 次、**bitgen 1 次、CWC 1 次**；同参数不 sweep。
- 硬门槛：Routed **0 违例端点**、hold ≥0、period 正、ERAM+CWC ≤300。
- **WNS 目标 ≥ +0.05 ns**：
  - Routed `0 违例` 且 WNS ∈ **+0.003 … +0.05**：接受为本轮功能/诊断候选，`timing_caveat=thin_margin_+0.00x`，result/manifest 明示“非生产签核”；
  - **WNS < +0.003 或任何负 slack/违例**：停止，不 bitgen、不下载，交规划。
  - 最差路径若落在本轮新增的读计数/占用逻辑：允许一次“只减观测计数（不改 R1–R5 语义）”的精简；仍不达标即停。**不得放宽 SDC**。
- bit/CWC/BID 与 `cw/compiled.*` 哈希自洽并冻结；1 bitgen + 1 CWC 后不再重建。

## 7. 板级（先下载后开 COM8）

### 7.1 前置

1. **FTDI 预检**（不打开 COM8）：`Get-PnpDevice -PresentOnly` 查 `VID_0403&PID_6042`；记录 `FTDI_PRESENT=0/1` 与原始输出。
2. 不在位 → `board=blocked`、**0 下载、0 COM8、不重试**；`board_blocked_reason=FTDI_0403:6042_absent`。这是合法完成，不是 FAIL。
3. 相机 A 已在位（b14 r0 板级已证），无需用户再次确认；本轮 `needs_user_input=false`。

### 7.2 采集（仅在位）

1. **先下载**：1 次 SRAM（JTAG，同一冻结 bit），确认 `B15_DL_OK`，结束 hwserver/释放 FTDI。
2. **再开 COM8**，150 s，用扩展后的 `parse_status_v5.py`。

### 7.3 门槛（全部满足才算板级通过）

- `status_packets ≥ 120`、`bad_xor=0`、`resync_bytes=0`；`sel=0`、`sysstat bit20=0`。
- `cap_frames` 增量 > 0（相机继续正常）；`crop_short=0`、`crop_geom_err=0`。
- **`timeout` / `retry` / `giveup` 增量全部 = 0**（本包核心目标）。
- **`enc_frames` 增量 > 0 且 `exported` 增量 > 0**。
- **≥1 帧**：44 B 头 + header/stream/xform/raw **四 CRC** 全过 + **zlib 解压成功** + 长度一致；无半帧。
- 静止读数：`ar_cnt - rlast_cnt ≤ 1` 且 `ar_cnt - r_cnt ≤ L_max-1`；`stale_guard=0`。

### 7.4 判定分支（必须写进 result）

- `exported>0` 且四 CRC+zlib → **板级通过**。
- `timeout/retry/giveup` 仍为每帧 3/2/1 且 `exported=0` → **仍每帧丢 R**：立即停止，记录 `ar/r/rlast/stale_guard/stale_r` 差分、失败帧号、尝试号、以及可得的最后一笔 AR 地址证据（仿真 `last_ar_addr` + 板上三元组），判 `H4_UNRESOLVED`；**不第二次下载**。
- `timeout=0` 但 `enc=0` → 读已通、卡在 A+/导出，按 A+ 侧证据交规划（本包不修 A+）。
- `arready` 长期压低 / `ddr_rdy=0` → 记录 DDR 侧就绪条件，交规划。
- 不写 Flash、不 PCIe/RK；下载 ≤1 次；失败不第二次。

## 8. 预算、停止与回退

- 开发：**120 min / 60 calls**；TD **3 会话**、综合 ≤3、布线 ≤2、bitgen 1、CWC 1、下载 **1**、Flash 0；综合测试 45 min / 30 calls。
- 立即停止（不建/不下载）：
  - 需改 `p2_ddr_bridge.v` 以外任何 RTL 文件，或需改 SDC/引脚/时钟/DDR IP/PAXI 协议；
  - `L_max > RF_DEPTH` 且加深 RF 不可行，或必须靠 `rready` 背压才能不溢出；
  - 任一 P1 黄金非逐字节一致，或帧头/CRC/压缩字节变化；
  - v5 破坏 241 B/59 字段/字段顺序/帧内边界；
  - S1/S3/S4 无法通过，或 S8 的 `if_max_os` 断言不成立；
  - 综合 3 次仍负；布线 2 次仍 <+0.003 或任何违例；ERAM+CWC>300；
  - 需要第二个 bitstream；
  - 板级仍每帧丢 R（按 §7.4 留证停止）。
- 回退：源以 b13 r1 为基线；失败只回退 b15 本地副本，不改 upstream/旧 run/manifest；`p2_ddr_bridge.v` 回退即回到 b13 行为（超时+重试兜底）。

## 9. 交付物（缺一不可）

- `r0/changed-src/**`（11 文件：1 改 + 10 逐字节不变）+ `r0/rtl-diff-r0.patch`
- `r0/diag/paxi-read-facts.md`（`L_max`/rlast/位宽/RF 深度的证据）、`r0/diag/read-serialization.md`（R1–R5 逐条对应到代码行 + `if_max_os` 说明）
- `r0/sim/**`（P1、S1–S8、日志/汇总 JSON、`last_ar_addr` 记录）
- `r0/td/**`（综合/布线报告、1 bitgen + 1 CWC、bit/CWC/BID/compiled、params、final STA、SDC diff = 0）
- `r0/board/**`（FTDI 预检；若下载则下载日志 + 150 s 采集 + v5 解析（含 `rlast_cnt`）+ 帧四 CRC/zlib 解码）
- `CANDIDATE-MANIFEST-b15-ddr-pace-r0.json`、`r0/artifact-hashes.txt`
- `result-r0.md`、`lessons-r0.md`
- 若 board blocked：result 明确 `board=blocked`、原因、0 下载，不宣称板级通过。

## 10. 下一次准确启动/恢复文本（开发）

> 恢复 `20261020-0209_singleA_aplus_closedloop` 的 **`T10.b15-ddr-pace` r0**（ready；1 bitgen+1 CWC；SRAM 下载 ≤1）。
> 先读 `T10.b15-ddr-pace/{dev-plan.md,fpga-design-guide.md,handoff.md,dispatch.json}`、
> `T10.b13-ddr-retry/r1/td/src/p2_ddr_bridge.v`（SHA `BFF1A358…49731`）、`T10.b13-ddr-retry/r0/changed-src/**`、
> `T10.b13-ddr-retry/r1/td/**`、`T10.b14-cam-b/r0/board/captures/status_v5.txt`（timeout/retry/giveup = 3/2/1 每帧，ar−r=13,650）。
> 已确认事实：A 相机 4,470 帧正常、几何无误、raw_pub 正常；卡点是 DDR 读每笔 AR 少回 1 个 R。
> 目标：**只改 `p2_ddr_bridge.v`** —— AR 严格单笔（`ar_busy` 到 `rlast` 才清）、`paxi_rready` 恒 1、RF 保证有空间、孤立 R 只计数不入队；
> b13 的 8192 超时/最多 2 次重试与 purge/guard 语义不变；v5 241 B/59 字段不变；其余 10 个 RTL 逐字节不变。
> 仿真：正常整帧、丢 1 R、连续 3 帧、full 两帧、P1 三黄金逐字节、b12/b13 回归、抗逆例、v5 结构、`if_max_os==1`。
> 构建：Routed 0 违例（WNS 按 §6 预裁决）、ERAM+CWC≤300、1 bitgen+1 CWC。
> 板级：FTDI 在位 → 1 次 SRAM 下载成功后再开 COM8 150 s；`timeout/retry/giveup` 归零、`enc/exported` 增量>0、≥1 帧四 CRC+zlib；
> 若仍每帧丢 R → 停止并记录 `ar/r/rlast/stale` 与地址证据，不第二次下载。
> 120 min/60 calls；TD 3 会话/综≤3/布≤2/bitgen 1/CWC 1/下载 1；失败即停，不自扩预算，不批删。
