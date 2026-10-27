# T10.b13-ddr-retry — dev-plan（规划冻结，2026-10-25）

- run：`20261020-0209_singleA_aplus_closedloop`（项目根 `D:\fpga\ph1p100`）
- 父任务：T10（**保持 blocked**；本包完成也不把 T10 置 done）
- 角色：开发 = fpga-dev（general 代行）；冻结后另派 **1 个新综合测试者**（functional/engineering/system 是同一人的检查清单）
- 状态：**ready**；`needs_user_input=false`；批大小 1；本轮 1 个主要可验收目标、1 个正式工作包（5 个语义步骤）
- 用户已选 **A：DDR 读超时 + 重试**。本包只做 A1 读通路的超时自救；**不修 DDR IP/PAXI 协议**，不猜改 DDR 控制器配置
- 基线：b12 r0 源码 + b12 r1 候选 bit（板级已实测）。**1176/882 停点由 H4 解释：DDR 接受 AR 但不返回 R**；停点不固定，符合刷新/读写仲裁偶发丢响应

## 0. 冻结输入与基线（不得重新解释）

### 0.1 b12 r1 板级实测（用户已裁决）

- 证据：`T10.b12-r1-last/r1/board/captures2/status_v4.txt`；原始包 `captures2/com8_150s.bin`（150 包，33,750 B，bad_xor=0）
- 停点：`raw_rd_state=rd_state=R_RW rd_armed=1`、`raw_rd_idx=882`、`raw_rd_words=129,600`、`rd_wait_cycles=0xFFFFFFFF`（饱和）
- 读通路：store AR=883、PAXI AR=883、PAXI R=882、rlast=882、stale=0、`ar_pending=1`、`af_rvalid=0`、`rf_rvalid=0`、`s_rvalid=0`、`ddr_rdy=1`
- 槽：`slot0=READING`、`slot1=READY`，两槽各 2,592,000 B；`raw_pub=2`、`enc=0`、`exported=0`
- camera/crop 正常：cap_frames 增量 4,470、crop_roi_frames 增量 4,470、`crop_short=0`、`crop_geom_err=0`
- 结论 **H4**：DDR 接受第 883 个 AR 后永不返回 R；A1 读通路 1:1 平衡（883/883/882，stale=0）
- 停点不固定（此前 1176，本次 882）→ 不是固定地址/固定 FIFO 深度问题，优先按 **DDR 刷新/读写仲裁偶发丢响应**处理；重试是恢复手段，DDR IP 根因另立 B 主题
- b12 r1 候选：bit `9180DB8C13751CA34179E6CF3DE73DB178F259546565AFDD1CFFDAB3702F8CD3`、CWC `FFB88419D3A0A18A686EF0DCFD161DD0E4B719319AFC4D6B103FBF46EB47C9A0`、BID `96D8A5DFF7C938BE571480B9F8A80EA893CC31B5CCE19402807A9BB3299E4A32`；Routed `SWNS=+0.003 / HWNS=+0.020 / 0 违例 / 25,697 端点 / ERAM 72`，`timing_caveat=thin_margin_+0.003`（诊断候选）；r1 板级 1 次 SRAM 下载

### 0.2 源码基线 = b12 r0 changed-src（9 文件，SHA256）

| 文件 | SHA256 |
|---|---|
| `a1_ddr_slot_store.v` | `c48f3eb0b1ab747d05b4a848f60a58dd24c9f7dbf9df0ef85147984e6c8d1887` |
| `a1_uart_export.v` | `69b73de4205cf3387422e9a5097a085dd29831a80335aeeebf00d42b6a819c3e` |
| `camera_a1_uart_top.v` | `ac6d5223576120565a2150e8ba058c87e39c2b4e704899724213efa1662db6b9` |
| `p2_ddr_bridge.v` | `4a2c7ddf6564de8659e35278c6a6eb5d04603cf0efd9e5899d551f13d884e43a` |
| `p2_a1_board_top.v` | `dafa65ee9f7ca060184de7b31969f95270177fbd10f08c749b115e1057ab348d` |
| `a1_frame_top.v` | `0064607aceb20ae3ef14133f0aaf5f8b3f489943011a66a1ddc005350dba7109` |
| `a1_deflate_core.v` | `a91c2ed82fbef654c4e065b64ae1cc268ca232feaa26fdd313c58d8740f81b3e` |
| `a1_raw_crop.v` | `33a6fee77fd1aa67a31cacf26dd5530e5e2ea474ee655cbd5f1d98d887c5d72d` |
| `cam_diag_mailbox.v` | `352af7c85094ea99b575e99da952af8d33871352140e4c6efddff9e6c2407278` |

- 另加 b12 构建用的仓库文件 `a1_ddr_arb2.v`：`6513AD839DEE02E932C49BDFD5AFA3D62C382D4A144B8E74D5574273804AFDC6`（本包首次纳入 changed-src）
- 构建脚本基线：`T10.b12-r1-last/r0/td/{01_build.tcl,02_bitgen.tcl,03_cwc.tcl,a1_board.al,p2_board.sdc,board_p2.adc}`（哈希见 b12 r0 manifest）；`a1_board.al` 只允许改 `<File Path>`
- 仿真基线：`T10.b12-r1-last/r0/sim/**`（P1 三黄金 `caps/*.dec|stats`、R1 clean/loss、multi control/triple、t7、store T3–T7、b11 read 九例）；`T10.b11-aplus-read/r0/sim/**`（read 九例与 v4 TB）

### 0.3 不可改动（冻结）

- 44 B 帧头/CRC、压缩帧字节、crop 几何/ROI、UART_DIV/HB_DIV、引脚/SDC/时钟频率、DDR 四槽布局
- `a1_frame_top.v`、`a1_deflate_core.v`、`a1_raw_crop.v`、`cam_diag_mailbox.v`、camera capture/MIPI/vendor、`upstream/**`
- 不写 Flash、不 PCIe/RK、不做双路/G4；不批量删除；禁止 false path/multicycle/改 seed/降频/新增 ERAM 实例
- 不改 `workflow/tasks.json`、旧 run/证据/manifest；`work/b10-gap-sim-20261025-132023/**` 只读

## 1. 本轮唯一目标

**问题**：DDR 偶发接受 AR 后不返回 R，A1 读 FSM 永久停在 `R_RW`，`raw_rd_idx` 卡死，帧不导出；b12 r1 实测 882/129,600 字。
**产物**：一个最小超时/重试候选：单次 R 丢失后 8192 clk_a1 超时 → 清读通路 → 保护窗口 → 重读**同一帧** → 帧完整导出；不发布半帧、不覆盖已发布槽、不把晚到 R 当新事务；状态包 v5 增加 timeout/retry/giveup/stale 字段；Routed 零违例；1 bitgen + 1 CWC；板级先下载后开 COM8、150 s，目标 `enc_frames/exported` 增量>0 且 ≥1 帧四 CRC+zlib。

### 1.1 工作包最小表

| task_id | 问题/产物 | 工作树/允许写路径 | 依赖 | functional | engineering | system | 必要 G 层 | 状态 | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|
| `T10.b13-ddr-retry` | DDR 丢 R 的超时/重试恢复 + v5 观测 | `D:/fpga/ph1p100`；只写 `run/T10.b13-ddr-retry/**` | b12 r0 源、b12 r1 板级证据 | 丢 1 R→超时→重试→整帧导出；晚到 R 不污染；多帧；b12 R1 回归；P1 三黄金；full 两帧 | Routed 0 违例、WNS 预裁决、ERAM+CWC≤300、1 bitgen+1 CWC | 先下载后 COM8、150 s、v5 包、`enc_frames/exported` 增量>0、≥1 帧四 CRC+zlib | G0/G1 仿真；G2 构建；G3 板级；G4 not_run | ready | 派 fpga-dev 执行本计划 |

## 2. 唯一正式包与工作步骤

| # | 语义步骤 | 预算 | 产物/门槛 |
|---|---|---|---|
| W1 | 先复现 + 冻结超时语义 | ≤20 min | 在 **b12 r0 冻结源**上用扩展 DDR 模型注入“丢 1 个 R”，复现停在 `R_RW`/无导出；落 `r0/diag/ddr-drop-repro.md`（丢 R 的 word/cycle、超时前 `rd_wait` 增长、无 `rd_close`）；冻结 §3 常量与状态机 |
| W2 | 最小 RTL 修改 | ≤35 min | 只改 §2.1 允许的 6 个源；实现 store 超时/重试、arbiter 读 abort、bridge purge/guard、top 重试序列、v5 包；其余源逐字节不变 |
| W3 | 仿真与回归 | ≤30 min | §4 的 T1–T12 全过；P1 三黄金逐字节；b12 R1 用例全回归；full 两帧 129,600/enc=2/exported=2；v5 241 B 结构；无半帧、无槽泄漏 |
| W4 | 重建（综合≤3、布线≤2、1 bitgen + 1 CWC） | TD 内 | Routed 0 违例、hold/period 正、ERAM+CWC≤300；WNS 按 §6 裁决；bit/CWC/BID/compiled 自洽冻结 |
| W5 | 板级（先下载后开 COM8） | ≤15 min | FTDI 预检；在位 → **1 次 SRAM 下载，确认成功后**再开 COM8 150 s；v5 ≥120 包、`enc_frames/exported` 增量>0、≥1 帧 44 B 头+四 CRC+zlib；若每帧同一 `rd_idx` 超时且 exported=0 → 停止转 B |

### 2.1 写域/工作树/允许改的源

- 工作树：**`D:/fpga/ph1p100`**（唯一主源）。
- 允许写：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b13-ddr-retry/**`（`changed-src/`、`sim/`、`td/`、`board/`、`diag/`、manifest、日志）。
- 源先复制到 `r0/changed-src/` 再改。**允许功能修改（6 个）**：
  1. `a1_ddr_slot_store.v` — 读 FSM 超时/重试（仅 `RETRY_EN=1` 的 raw 实例；写侧/发布/abort 语义不变）
  2. `a1_ddr_arb2.v` — 新增 `m0_rd_abort`，只清 raw 主人的 `rd_busy`（公平性/写通路不变）
  3. `p2_ddr_bridge.v` — 新增 `rd_abort`：清 `ar_pending`、排空 AF、丢弃 RF/skid、guard 内禁 AR、晚到 R 吞掉并计数；观测总线扩到 256 bit
  4. `camera_a1_uart_top.v` — 把 `rd_timeout` 接到 bridge/arb；超时中止 A+ 核与压缩槽并回 `F_IDLE`；v5 `sts_ext` 扩到 512 bit；新增 `o_rd_abort` 端口
  5. `p2_a1_board_top.v` — 连接 `o_rd_abort` 到 bridge，`dbg_bridge` 宽度 192→256
  6. `a1_uart_export.v` — v5 状态包 241 B / 59 字段（仅追加，不改帧头/CRC）
- **逐字节不变**：`a1_frame_top.v`、`a1_deflate_core.v`、`a1_raw_crop.v`、`cam_diag_mailbox.v`、camera 前端/`f9p_*`/vendor、SDC/ADC/引脚/时钟/UART_DIV/HB_DIV。
- 构建：复制 b12 `r0/td/{01_build.tcl,02_bitgen.tcl,03_cwc.tcl,a1_board.al,p2_board.sdc,board_p2.adc}` 与 `r0/td/src/**` 到 b13 `r0/td/`；`a1_board.al` 只改 `<File Path>` 指向 b13 副本，并把 `a1_ddr_arb2.v` 从 `Y:/fpga/csi2/src/a1/a1_ddr_arb2.v` 改指 `changed-src/a1_ddr_arb2.v`；**不改** Tcl 的流程/参数/seed。
- 路径：`P:`=项目根，`W:`=`r0/sim`；TD `T:`=`r0/td`，`Y:`=项目根；`X:` 不映射项目根。
- 禁止批量删除（只能一次 `Remove-Item <单文件>`，需批量先问用户）。

## 3. RTL 规格（冻结语义，允许等价实现）

### 3.1 Store 读超时/重试（`a1_ddr_slot_store.v`，仅 raw 实例）

新增参数（默认值即生产值）：
```verilog
parameter integer RETRY_EN   = 0,      // raw 实例=1；cmp 实例=0（保持旧行为）
parameter integer TIMEOUT_N  = 8192,   // clk_a1；AR 已被接受后等 R 的上限
parameter integer GUARD_N    = 32768,  // clk_a1；超时后禁止新 AR 的保护窗口
parameter integer MAX_RETRY  = 2       // 同一帧最多重试 2 次（共 3 次尝试）
```

- `rd_state` 由 2 bit 扩到 3 bit：`R_IDLE=0, R_AR=1, R_RW=2, R_HOLD=3, R_ABORT=4, R_GUARD=5`。
- 超时只统计 **AR 已被接受之后**（`rd_armed=1`，处于 `R_RW`）连续 `TIMEOUT_N` 个 clk_a1 没有 `ddr_rvalid`；进入 `R_RW`/收到 R 时清零 `rd_wait`。`R_AR` 等不到 `arready` 不属本包（由 top 的 F_WAIT 看门狗兜底）。
- 超时拍（`RETRY_EN && rd_state==R_RW && rd_armed && rd_wait==TIMEOUT_N-1`）：
  1. 拉高 `rd_timeout` **1 个 clk_a1**（同时送 top/bridge/arbiter）；
  2. `rd_valid<=0`、`rd_armed<=0`、`rd_wait<=0`、`st_timeout_cnt++`；
  3. `rd_idx<=0`，**槽保持 `S_READING`**（不 FREE、不 READY、不发布）；
  4. `rd_state<=R_GUARD`，`guard_cnt<=GUARD_N`；`ddr_rready` 在 `R_GUARD` 恒 0。
- `R_GUARD`：
  - `guard_cnt` 递减；期间 `ddr_arvalid=0`，绝不发新 AR；
  - `guard_cnt==0 && retry_used<MAX_RETRY` → `rd_retry_ready=1`（level），等待 top 的 `rd_open`；
  - 接受重试 `rd_open`：`rd_sel` 不变、`rd_expect` **不再翻转**、`rd_words<=words_of(rd_sel)`（按 `slot_len[rd_sel]` 重算）、`rd_idx<=0`、`rd_prev_v<=0`、`rd_armed<=0`、`st_retry_cnt++`、`retry_used++`、`rd_state<=R_AR`；槽仍 `S_READING`；
  - `guard_cnt==0 && retry_used==MAX_RETRY` → 放弃：`slot_st[rd_sel]<=S_FREE`、`st_retry_giveup++`、`rd_state<=R_IDLE`、`rd_retry_ready=0`；不发布、不导出。
- `rd_open_ready` 扩展为：`rst_n && ddr_ready && ((R_IDLE && ready_valid) || (R_GUARD && guard_done && retry_used<MAX_RETRY))`。
- 正常 `rd_close`（成功或 top 放弃）仍释放槽并回 `R_IDLE`；`st_rd_close_cnt` 语义不变。
- 新计数输出：`st_timeout_cnt`、`st_retry_cnt`、`st_retry_giveup`；`st_rd_state[4:0]` 的既有位段（`rd_valid/rd_sel/rd_armed/rd_state[1:0]`）**逐位不变**，`rd_state[2]` 放到空位 `st_rd_state[27]`；v5 #29 仍打包低 5 位，新增状态位由 #29 的 bit27 观测。
- `RETRY_EN=0`（cmp 实例）时 `rd_state` 永不进入 `R_ABORT/R_GUARD`，行为与 b12 逐字节一致；新增端口未连接即可。

### 3.2 Arbiter（`a1_ddr_arb2.v`）

- 新增 `input wire m0_rd_abort`。`m0_rd_abort && rd_busy && !rd_owner` → 下一拍 `rd_busy<=0`（只清 raw 主人；**不得**清 cmp 的 `rd_owner=1` 事务）。
- 写仲裁、round-robin、`rd_last` 语义不变；`s_rready` 仍只在 `rd_busy` 时跟随主人。
- 该 abort 只在 store 已确认超时（raw 主人）时发出；仿真必须断言 `rd_busy && rd_owner==0`。

### 3.3 Bridge（`p2_ddr_bridge.v`）

- 新增 `input wire rd_abort`（clk_a1 单拍）。**只用本地 purge，不得拉低全局 `rst_n`**（否则 WF 写 FIFO 会丢已收写请求）。
- clk_a1 侧：收到 `rd_abort` → 清 `s_rvalid_r`，进入 4 拍 `a1_purge`；期间 `s_load=0`、`s_rvalid=0`，并对 `rf_rvalid` 持续 `rf_pop=1` 排空 RF；计数 `purge_cnt++`。
- clk_a1→clk_ddr：`rd_abort` 经 toggle+2FF 同步（与既有 mailbox 同风格），**不得**把单拍脉冲直接当 clk_ddr 电平。
- clk_ddr 侧收到 purge 事件：
  1. `ar_pending<=0`（优先级高于 `af_pop`/`r_hs`）；
  2. 进入 `P_PURGE`：`paxi_arvalid` 强制 0；`af_rvalid` 时 `af_pop=1` 排空 AF（丢弃未发地址）；`paxi_rready=1` 吞掉任何晚到 R；
  3. 之后 `BRIDGE_GUARD_N=65536` clk_ddr（约 327 µs @200 MHz）内继续禁 AR、`ar_pending=0`、`rready=1`；该窗口 **≥ store 的 GUARD_N（32768 clk_a1 ≈ 175 µs）**，保证 store 重试前 bridge 不会发出任何新 AR；
  4. 窗口内 `paxi_rvalid` 且 `!ar_pending` → `stale_r_cnt++`（既有 #49）且 `stale_guard_cnt++`（新 #59）；晚到 R 永不进入 RF。
- `af_pop` 拆成 `af_pop_normal = paxi_arvalid && paxi_arready`（置 `ar_pending`）与 `af_pop_purge = purge_active && af_rvalid`（不置 `ar_pending`）；FIFO `r_ready` 取二者或。
- 观测：`dbg_a1` 192→256 bit；新增 `[255:224]=purge_cnt`、`[223:192]=stale_guard_cnt`；旧 `[191:0]` 位序/含义不变。mailbox `W(192)`→`W(256)`，DIV_BITS 保持 8。
- 正常路径（无 `rd_abort`）行为、吞吐和时序不变；`rd_abort` 保持 0 时新增逻辑等价旁路。

### 3.4 Top 序列（`camera_a1_uart_top.v`）

- 新增端口 `output wire o_rd_abort`；把 raw store 的 `rd_timeout` 直接赋给它（同 clk_a1 单拍），并接 `u_arb.m0_rd_abort`。
- 新增 `wire raw_rd_timeout, raw_rd_retry_ready;` 与 store 新端口相连。
- 序列 always 块增加**最高优先级**分支（在 `case (fstate)` 之前）：
  ```verilog
  if (raw_rd_timeout) begin
      a1_abort       <= 1'b1;   // 干掉 A+ 核当前半帧
      cmp_abort      <= 1'b1;   // 释放压缩槽，不产生描述符
      a1_in_valid    <= 1'b0;
      a1_in_sof      <= 1'b0;
      grp_sent       <= 32'd0;
      fstate         <= F_IDLE; // 不回 raw_rd_close，槽保持 READING 等重试
  end
  ```
  该分支不得清 `raw_expect_ok` 以外的既有计数，不得 `raw_rd_close_r<=1`；`a1_commit` 不会发生，因此 `desc_push` 不会推半帧。
- `F_IDLE` 仍用 `a1_can_start = !a1_busy && !a1_out_valid && raw_rd_open_ready && cmp_begin_ready`；重试时 `raw_rd_open_ready=1`（来自 `R_GUARD`），`rd_open` 语义与首次打开一致，`cmp_id` 正常 +1（导出帧 ID 是重试尝试的 ID，raw 槽 ID 不变）。
- F_WAIT 的 `WD_LIMIT=2^24` 有界看门狗保留为兜底；正常超时路径先于它触发（8192 << 2^24）。
- `sts_ext_bus` 由 384→512 bit：`{stale_guard_cnt, retry_giveup, retry_cnt, timeout_cnt, <原 384 bit 顺序不变>}`；`i_dbg_bridge` 192→256 bit，旧映射不变。
- 不改 feeder 的 feed 顺序、crop、UART 帧、写路径。

### 3.5 状态包 v5（`a1_uart_export.v`）

- `STS_LEN=8'd241`、`STS_VER=8'd5`、`STS_LAST=8'd240`（XOR 覆盖字节 0..239）；`4 + 59*4 + 1 = 241`。
- 字段 #1–#55 **顺序与表达式完全不变**（v3/v4 的旧位序保留）；只追加：
  - `#56 rd_timeout_cnt`（store 超时次数）
  - `#57 rd_retry_cnt`（实际重启的重试次数）
  - `#58 rd_retry_giveup`（重试预算耗尽、释放槽并未导出的帧数）
  - `#59 rd_stale_guard_cnt`（purge/guard 内被吞掉的晚到 R 数）
- `sts_ext` 端口 384→512 bit；`allsnap` 扩到 59×32；单边沿快照、不插帧内的既有约束不变。
- 帧 44 B 头/CRC/压缩字节不动；v5 只影响状态包。开发需提供 `r0/board/parse_status_v5.py`（241 B / 59 字段，兼容打印旧 55 字段），并在 sim 中验证 `bad_xor=0`、包不出现在帧内。

### 3.6 不变式（仿真必须逐条断言）

1. **不发布半帧**：超时/重试/放弃路径 `st_published` 不变；只有 `wr_last` 且 `EXPECT_BYTES` 匹配才 READY。
2. **不覆盖已发布槽**：超时槽保持 `READING`；`READY` 槽不被写；重试只读原槽。
3. **晚到 R 不污染**：`ar_pending=0` 时任何 R 只被吞掉并计数，不进 RF、不置 `s_rvalid`；store 在 `R_GUARD` 不看 `rvalid`。
4. **不把晚到 R 当新事务**：purge 后到新 AR 前 `ar_pending` 必须为 0；bridge guard（65536 clk_ddr ≈327 µs）≥ store guard（32768 clk_a1 ≈175 µs），保证 store 重试前 bridge 不发新 AR。**残余风险**：PAXI 单 outstanding、R 无 tag，比 327 µs 更晚的 R 理论上可能与后续新 AR 混叠；由余量与四 CRC/严格 zlib 最终检出，result 必须登记，不得宣称绝对排除。
5. **不泄漏槽**：超时后槽仍 READING（重试）或最终 FREE（giveup/close）；任一时刻至多一个 READING、至多一个 WRITE。
6. **计数自洽**：`retry_cnt <= timeout_cnt`；`giveup <= timeout_cnt`；`stale_guard_cnt` 只在 purge/guard 内增长；正常帧全 0。
7. **v5 结构**：241 B / 59 字段 / VER=5 / XOR 正确 / 单边沿 / 不插帧内。

## 4. 强制定向仿真（逐项取证）

| ID | 用例 | 通过判据 |
|---|---|---|
| T1 | clean 小几何控制 | 无超时/重试/放弃/stale；RAW 发布/编码/导出各 1；44 B 头 + 四 CRC + 严格 zlib；v5 结构正确 |
| T2 | **DDR 模型丢 1 个 R（帧中部）→ 超时 → 重试成功** | `timeout_cnt=1`、`retry_cnt=1`、`giveup=0`；导出帧 raw/stream 字节 **逐字节等于 T1 黄金**；四 CRC + zlib；无半帧；`rd_idx` 在超时后回到 0 |
| T3 | **晚到 R**（丢的 R 在 `TIMEOUT_N` 后、`GUARD_N` 内到达） | 与 T2 同样导出成功；`stale_guard_cnt>=1`；晚到 R **不出现在**重试数据流（raw 字节仍等于黄金）；`ar_pending` 在重试 AR 前为 0 |
| T4 | 连续 3 帧，仅第 2 帧丢 1 个 R | 3 帧全部导出、ID 不同、四 CRC+zlib 全过；计数恰为 `1/1/0`；第 1/3 帧 stale=0 |
| T5 | **重试预算耗尽**：第 1 帧每次 AR 都丢 R | `timeout_cnt=3`、`retry_cnt=2`、`giveup=1`；该帧不导出、不发布、槽 FREE；下一好帧正常导出；无死锁 |
| T6 | 帧中部超时（先收到 k 个字再丢） | A+ 核被 `a1_abort` 清干净；重试后整帧与黄金逐字节一致；无重复/缺字；`fstate` 回到 `F_IDLE` 再重开 |
| T7 | 超时后 `rd_open` 前保持静默（保护窗口） | `rd_open_ready=0` 直到 `guard_cnt=0`；窗口内 `ddr_arvalid=0`；窗口内无 `ar_pending` 置位 |
| T8 | b12 R1 回归（clean/loss，7 拒收含 LAST） | 与 b12 r0 相同判据全过：故障帧不发布、槽 FREE、`raw_abort_cnt>=1`、`raw_drop>=1`、两好帧恢复、源序列 `[11,1000,1001]` |
| T9 | b12 store T3–T7 / t7 / multi control+triple | 与 b12 r0 基线全过（同拍 LAST+abort、begin+abort、中写复位、满槽并发、SOF 拒收、三帧小几何） |
| T10 | b11 read 九例（one/multi/bp/late/stray/dup/full/reset） | 全部 `pass=1`、`bad=0`；`read_full=129600/129600`；其中故意长时间不返回 R 的用例：改为**先验证超时/重试行为**，不得放宽 checker |
| T11 | P1 三黄金 | `micro8x2`、`mid64x8`、`full_grad(1920×1080)` 压缩字节 SHA256 与 b12 r0 `sim/caps/*.dec` 基线一致；四 CRC、zlib、`dup=0`、无半帧、`vlog 0/0` |
| T12 | full 两帧 + full 丢 1 R | 真核 1920×1080 两帧：`read_words=129600`、`enc=2`、`exported=2`、无超时；另做 1 帧丢 1 R：超时/重试后仍导出且四 CRC+zlib 全过 |
| T13 | v5 包结构 | 241 B/59 字段/VER=5/LEN=241/XOR 覆盖 0..239；单边沿快照；不插帧内；连续包解析 0 bad_xor |

- DDR 模型必须能**确定性**注入：`drop_r_word=k`（丢第 k 个 R，永不返回）、`late_r_delay=D`（延迟 D 拍返回）；日志打印注入点/拍数，checker 以 DUT 输出为准，不得改 PASS 条件迁就 DUT。
- T2/T3/T5/T6 必须用**真实 b13 changed-src** 编译；单元 TB 参数可缩短 `TIMEOUT_N/GUARD_N` 以控仿真时长，但必须另有一组**生产默认参数**的用例（至少 T2、T12）。

## 5. 回归与 packet v5（全部必做）

| 项 | 判据 |
|---|---|
| P1 三黄金 | 压缩字节 SHA256 同 b12 r0 `sim/caps/*.dec`；四 CRC、`zlib_ok`、`dup=0`、无半帧、`vlog 0/0` |
| v5 包 | 241 B、59 字段、VER=5、XOR 0..239、单边沿快照、不插帧内；`parse_status_v5.py` 可解析且 `bad_xor=0` |
| full 两帧 | 真实 `a1_frame_top+a1_deflate_core`，1920×1080；`read_words=129600`、`enc=2`、`exported=2`；F_WAIT 看门狗不误触发 |
| b12 R1 | clean/loss 两用例 + store T3–T7 + t7 + multi 全部复跑；故障帧不发布、槽归还、两好帧恢复；正常路径 `raw_abort_cnt=0` |
| b11 read | 九例全过；`read_full` 129600/129600；超时用例按新语义判定且不放宽 |
| 计数 | 正常帧 `timeout/retry/giveup/stale` 全 0；故障帧只允许目标计数增长，`raw_pub` 不重复计 |

## 6. 重建与时序裁决（预裁决）

- 复制 b12 `r0/td` 脚本/ADC/SDC/`src/**` 到 b13 `r0/td/`；`a1_board.al` 只改 `<File Path>`（含 `a1_ddr_arb2.v` 指向 b13 副本）。
- 综合 ≤3 次、布线 ≤2 次、**bitgen 1 次、CWC 1 次**；同参数/seed 不 sweep；不改流程/约束。
- 硬门槛：Routed **0 违例端点**、hold ≥0、period 正、ERAM+CWC ≤300。
- **WNS 目标 ≥ +0.05 ns**。预裁决（与 b12 口径一致）：
  - 若 Routed `0 违例` 且 WNS 落在 **+0.003 … +0.05**：**接受为本轮功能/诊断候选**，`timing_caveat=thin_margin_+0.00x`，在 result/manifest 明示“非生产/非板级签核”；**不**为凑 +0.05 删 v5 观测。
  - 若 **WNS < +0.003** 或任何负 slack/违例：**停止**，不 bitgen、不下载，交规划。
  - 若最差路径落在本轮新增逻辑：先只做一次“只减观测”精简（不得改 LEN/VER/字段数/241 B），仍不达标即停。
- bit/CWC/BID 与 `cw/compiled.bit` 哈希自洽并冻结；1 bitgen + 1 CWC 后不再重建。

## 7. 板级（先下载后开 COM8）

1. **FTDI 预检**（不打开 COM8）：`Get-PnpDevice -PresentOnly` 查 `VID_0403&PID_6042`；记录 `FTDI_PRESENT=0/1` 与原始输出。
2. 不在位 → `board=blocked`、**0 下载、0 COM8、不重试**；写 `board_blocked_reason=FTDI_0403:6042_absent`。这是本包的合法完成，不是 FAIL。
3. 在位：
   - **先下载**（1 次 SRAM，JTAG；同一冻结 bit），确认 `B13_DL_OK`，结束 hwserver/释放 FTDI；
   - **再开 COM8**，150 s，用 `parse_status_v5.py`；目标：v5 ≥120 个全合法包、`bad_xor=0`；
   - `enc_frames/exported` 增量 **>0**；≥1 帧 44 B 头 + header/stream/xform/raw 四 CRC + zlib 全过；无半帧；
   - 记录 `timeout_cnt/retry_cnt/giveup/stale_guard_cnt`：若 timeout>0 且 retry>0 且 exported>0 → 超时重试恢复在硬件上成立；若全 0 且导出成功 → 本轮未遇到丢 R，仍算板级通过（不宣称重试被触发）；
   - 若 `exported` 增量=0 且 ≥3 帧在**相同 `rd_idx`** 超时、`retry_cnt` 增长但 `giveup` 也增长 → **停止，转 B（DDR IP 调查）**，不在本包第二次下载/第二个 bitstream；
   - 若 `exported=0` 且 timeout 计数不增长 → 不是本包目标故障，保留 v5 #44–#59 证据交规划，不猜修。
4. 不写 Flash、不 PCIe/RK、不做双路/G4；下载 ≤1 次；失败不第二次。

## 8. 预算、停止与回退

- 开发：**120 min / 60 calls**；TD **3 会话**、综合 ≤3、布线 ≤2、bitgen 1、CWC 1、下载 **1**、Flash 0。
- 立即停止（不建/不下载）：
  - T2/T3 重试后仍不能导出，或 T4/T5/T6 出现半帧/槽泄漏/两个 WRITE/晚到 R 被当新数据；
  - P1 任一黄金非逐字节一致，或帧头/CRC/压缩字节变化；
  - v5 破坏 241 B/59 字段/帧内边界；
  - 综合 3 次仍负；布线 2 次仍 <+0.003 或任何违例；ERAM+CWC>300；
  - 需要第二个 bitstream，或修复需要改 DDR IP/PAXI 协议、downclock、false path；
  - 板级 1 次下载后 exported=0 且每帧同一 `rd_idx` 丢 R → 停止转 B。
- 回退：源以 b12 r0 为基线；失败只回退 `a1_board.al` 的本地路径副本，不改 upstream；不改旧 run/manifest。
- 用户已授权本 run 的 1 次 SRAM 下载；仍**不写 Flash**。

## 9. 交付物（缺一不可）

- `r0/diag/ddr-drop-repro.md`（丢 R 注入、超时前状态、修复前后对照、`rd_idx`/`rd_wait` 证据）
- `r0/changed-src/**`（6 个文件变化 + 其余 4 个逐字节不变）+ `r0/rtl-diff-r0.patch`
- `r0/sim/**`（T1–T13、P1、v5、full、b12 R1、b11 read 的脚本/日志/汇总 JSON）
- `r0/td/**`（综合/布线报告、1 bitgen + 1 CWC、bit/CWC/BID/compiled.bit、params、final STA）
- `r0/board/**`（FTDI 预检；若下载则下载日志 + 150 s 采集 + v5 解析 + 帧解码；`parse_status_v5.py`）
- `CANDIDATE-MANIFEST-b13-ddr-retry-r0.json`、`r0/artifact-hashes.txt`
- `result-r0.md`、`lessons-r0.md`
- 若 board blocked：result 明确 `board=blocked`、原因、0 下载，不宣称板级通过。

## 10. 下一次准确启动/恢复文本（开发）

> 恢复 `20261020-0209_singleA_aplus_closedloop` 的 **`T10.b13-ddr-retry` r0**（ready；1 bitgen+1 CWC；SRAM 下载 ≤1；先下载后开 COM8）。
> 先读 `T10.b13-ddr-retry/{dev-plan.md,fpga-design-guide.md,handoff.md,dispatch.json}`、
> `T10.b12-r1-last/r1/board/captures2/status_v4.txt`、`T10.b12-r1-last/r0/{changed-src/,sim/,td/}`、
> `T10.b11-aplus-read/r0/sim/`（read 九例/v4 TB）。
> 已确认事实：b12 r1 板级 4,470 帧正常，store AR=883、PAXI AR=883、R=882、stale=0、`ar_pending=1`、`rd_wait` 饱和，
> `slot0=READING`、`slot1=READY`，`raw_rd_idx=882` → H4：DDR 接受 AR 后不回 R；停点不固定（1176→882）。
> 目标：读等待 >8192 clk_a1 → abort 当前帧读、复位读 FSM/bridge 读路径（清 ar_pending、排空 AF/RF）、
> 保护窗口 32768 clk_a1 内不发新 AR、晚到 R 当 stale 丢弃 → 重试同一帧（最多 2 次）→ 完整导出；
> 不发布半帧、不覆盖已发布槽、不把晚到 R 当新事务；v5 增加 timeout/retry/giveup/stale 四字段（241 B/59 字段）。
> 只改 `a1_ddr_slot_store.v`、`a1_ddr_arb2.v`、`p2_ddr_bridge.v`、`camera_a1_uart_top.v`、
> `p2_a1_board_top.v`、`a1_uart_export.v`；其余源/SDC/ADC/引脚/时钟/帧格式全冻结。
> 先跑 T2/T3（丢 R→超时→重试→导出；晚到 R 不污染），再 T4–T13、P1 三黄金、b12 R1、b11 read、full 两帧；
> 然后综合/布线/1 bitgen+1 CWC（Routed 0 违例，WNS 按 §6 预裁决）；板级先下载 1 次 SRAM，再开 COM8 150 s，
> 目标 `enc_frames/exported` 增量>0 且 ≥1 帧四 CRC+zlib；若每帧同一位置失败 → 停，转 B（DDR IP 调查）。
> 120 min/60 calls；TD 3 会话/综≤3/布≤2/bitgen 1/CWC 1/下载 1；失败即停，不自扩预算，不批删。
