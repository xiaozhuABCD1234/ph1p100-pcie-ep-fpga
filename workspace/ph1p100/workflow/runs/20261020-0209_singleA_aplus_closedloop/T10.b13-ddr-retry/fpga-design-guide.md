# T10.b13-ddr-retry — fpga-design-guide（任务级冻结，2026-10-25）

本指南冻结 `T10.b13-ddr-retry` 的数据格式、接口、参数、时序/缓冲、工作目录、构建入口与既有约束。与 dev-plan 冲突时以 dev-plan 的验收/预裁决为准；与项目既有 44 B 帧格式/UART 协议冲突时以既有协议为准，本任务**不新增第二套帧协议**。

## 1. 任务边界

- 只解决 **A1 读通路在 DDR 丢 R 时的超时/重试恢复**；不改 DDR IP、PAXI 协议、DDR 四槽布局、crop、帧头/CRC、压缩算法。
- 只 `RETRY_EN=1` 的 **raw 读**（`u_raw_store`）启用；`u_cmp_store` 用 `RETRY_EN=0`，行为与 b12 逐字节一致。
- b12 r1 已证明：DDR 接受 AR 后可不返回 R（H4）；停点不固定（1176→882）。重试是恢复手段，根因调查另立 B 主题。

## 2. 冻结常量（生产默认值）

| 名称 | 值 | 域 | 含义 |
|---|---|---|---|
| `TIMEOUT_N` | 8192 | clk_a1 | AR 已被 DDR 接受后，等 R 的最大连续拍数（≈43.7 µs @187.5 MHz） |
| `GUARD_N` | 32768 | clk_a1 | 超时后禁止新 AR 的保护窗口（≈174.8 µs） |
| `MAX_RETRY` | 2 | — | 同一帧最多重试 2 次（共 3 次尝试） |
| `BRIDGE_GUARD_N` | 65536 | clk_ddr | bridge 侧禁 AR/吞晚到 R 窗口（≈327 µs @200 MHz，≥ store GUARD_N 实时长度） |
| `A1_PURGE_N` | 4 | clk_a1 | bridge A1 侧清 skid/排空 RF 的拍数 |
| `DDR_PURGE_N` | 4 | clk_ddr | bridge DDR 侧清 `ar_pending`/排空 AF 的拍数 |

- 单元 TB 可缩短 `TIMEOUT_N/GUARD_N` 控仿真时长，但 T2/T12 至少各有一组**生产默认值**用例。
- 常量集中在 store/bridge 的 `localparam`/参数与注释中；不得散落魔数。

## 3. 读通路结构与改动点

```
raw store reader ──AR──> a1_ddr_arb2 (m0) ──> p2_ddr_bridge AF ──> PAXI AR ──> DDR
        ^   <──R──────────────────────────────── RF <── PAXI R <──────────┘
        │
   rd_timeout (1 clk_a1) ──> top: a1_abort/cmp_abort, F_IDLE
                         ├─> arbiter m0_rd_abort: clear rd_busy (owner=raw only)
                         └─> bridge rd_abort: purge ar_pending/AF/RF/skid, guard
```

### 3.1 `a1_ddr_slot_store.v`（仅 raw）

新增端口：
```verilog
output wire        rd_timeout,       // 1 clk_a1 pulse
output wire        rd_retry_ready,   // level, guard done && budget left
output reg  [31:0] st_timeout_cnt,
output reg  [31:0] st_retry_cnt,
output reg  [31:0] st_retry_giveup,
```
新增参数：`RETRY_EN, TIMEOUT_N, GUARD_N, MAX_RETRY`（默认见 §2；cmp 实例显式 `RETRY_EN(0)`）。

读 FSM（3 bit）：
| 状态 | 行为 |
|---|---|
| `R_IDLE` | `rd_open_ready = ready_valid`；接受 open → `slot: READY→READING`、`rd_expect^=1`、`rd_words=words_of(oldest_slot)`、`rd_idx=0`、`R_AR` |
| `R_AR` | `arvalid=1`，等 `arready` → `rd_armed=1`、`R_RW`；**不设超时** |
| `R_RW` | `rready=1`；`rd_armed` 后无 `rvalid` 计 `rd_wait`；`rd_wait==TIMEOUT_N-1` → 超时拍 |
| `R_ABORT` | 可选合并进超时拍；清 `rd_valid/rd_armed`，保持槽 READING |
| `R_GUARD` | `arvalid=0`、`rready=0`；`guard_cnt--`；到 0 且预算未耗尽 → `rd_retry_ready=1`，等 top `rd_open`；预算耗尽 → 槽 FREE、`giveup++`、`R_IDLE` |
| `R_HOLD` | 原语义：等 `rd_take`；`rd_idx>=rd_words` 等 `rd_close`；close → 槽 FREE、`R_IDLE` |

重试 `rd_open`（`R_GUARD` 接受）：
- `rd_sel` 保持；**不**第二次翻转 `rd_expect`；`rd_words = words_of(rd_sel)`（按 `slot_len[rd_sel]`，不是 `oldest_slot`）；`rd_idx=0`、`rd_prev_v=0`、`rd_armed=0`、`R_AR`；
- `st_retry_cnt++`、`retry_used++`；槽仍 `S_READING`。

超时拍必须原子完成：`rd_timeout=1` + 清 `rd_valid` + `rd_idx=0` + 进入 `R_GUARD` + `timeout_cnt++`；不得同拍发布/关闭槽。

### 3.2 `a1_ddr_arb2.v`

```verilog
input wire m0_rd_abort;
// always @(posedge clk): if (m0_rd_abort && rd_busy && !rd_owner) rd_busy <= 1'b0;
```
- 只清 m0（raw）主人；`rd_owner=1`（cmp）时忽略。
- 写仲裁、`rd_last`、`s_rready` 逻辑不变。
- 仿真断言：`m0_rd_abort` 有效时 `rd_busy && !rd_owner`。

### 3.3 `p2_ddr_bridge.v`

```verilog
input  wire        rd_abort;      // clk_a1, 1-cycle
output wire [255:0] dbg_a1;       // 192→256, old [191:0] unchanged
```
- **全局 `rst_n` 不得因 purge 拉低**；只做本地清指针/丢弃。
- A1 侧：`rd_abort` → `purge_cnt++`、清 `s_rvalid_r`、4 拍内 `s_load=0` 且 `rf_pop = rf_rvalid`（排空 RF）→ 之后正常。
- CDC：`rd_abort` → toggle → 2FF（clk_ddr）→ 单拍 `purge_evt`。禁止把 clk_a1 单拍直接当 clk_ddr 条件。
- DDR 侧 `purge_evt`：
  1. `ar_pending<=0`（最高优先级）；
  2. `DDR_PURGE_N` 拍：`paxi_arvalid=0`、`af_pop=af_rvalid`（丢弃未发地址）、`paxi_rready=1`；
  3. `BRIDGE_GUARD_N` 拍：继续 `paxi_arvalid=0`、`paxi_rready=1`、`ar_pending=0`；
  4. 任意 `paxi_rvalid && !ar_pending` → `stale_r_cnt++`（#49）且 `stale_guard_cnt++`（#59）；**永不 push RF**。
- 正常 `R`：`ar_pending=1` 时 `rf_push=paxi_rvalid`；`ar_pending` 在 `af_pop_normal` 置位、在 `r_hs` 清零（原语义）。
- AF `r_ready = af_pop_normal || af_pop_purge`；`af_pop_purge` 不置 `ar_pending`。
- `dbg_a1 = {purge_cnt[31:0], stale_guard_cnt[31:0], <原 192 bit>}`（总 256）。
- mailbox 实例 `W(256), DIV_BITS(8)`。
- **已知残余风险**：PAXI 单 outstanding 且 R 无 tag；若某个 R 比 `BRIDGE_GUARD_N`（327 µs）还晚，理论上可能与之后的新 AR 混叠。327 µs 相对正常读延迟有 >100× 余量；混叠会破坏帧数据并被四 CRC/严格 zlib 检出（不会静默导出好帧），但必须在 result 中登记为残余风险，不得宣称“绝对不可能”。

### 3.4 `camera_a1_uart_top.v` / `p2_a1_board_top.v`

- `camera_a1_uart_top` 新增 `output wire o_rd_abort`，直接等于 raw store `rd_timeout`；同拍接 `u_arb.m0_rd_abort`。
- 序列 always 最高优先级 `raw_rd_timeout` 分支：`a1_abort<=1; cmp_abort<=1; a1_in_valid<=0; a1_in_sof<=0; grp_sent<=0; fstate<=F_IDLE;` **不** `raw_rd_close_r`。
- `p2_a1_board_top`：`wire [255:0] dbg_bridge;`；`u_bridge .rd_abort(o_rd_abort)`；camera top `.i_dbg_bridge(dbg_bridge)`；其余端口/约束不变。
- `sts_ext_bus` 512 bit = `{stale_guard_cnt, giveup, retry, timeout, <原 384>}`。
- 不改 feeder 分组顺序、crop、UART 帧、写路径、看门狗 `WD_LIMIT`。

### 3.5 状态包 v5（唯一新增数据格式）

| 字节 | 值 |
|---|---|
| 0 | `0xA5` |
| 1 | `0x5A` |
| 2 | `0xF1`（LEN=241） |
| 3 | `0x05`（VER=5） |
| 4..239 | 59 × u32 LE |
| 240 | XOR8 of bytes 0..239 |

字段：
- `#1..#8` legacy 8 words（原顺序）
- `#9..#23` camera 15 words（原顺序）
- `#24..#43` raw-store 20 words（原顺序）
- `#44..#55` read-path/A+ 12 words（原顺序，含 `#44 br0`、`#45 ar_cnt`、`#46 ar_block_cnt`、`#47 r_cnt`、`#48 rlast_cnt`、`#49 stale_r_cnt`、`#50 rd_wait_cycles`）
- `#56 rd_timeout_cnt`
- `#57 rd_retry_cnt`
- `#58 rd_retry_giveup`
- `#59 rd_stale_guard_cnt`

约束：整包单边沿快照；只在 `estate==E_IDLE && sstate==S_IDLE && tx_ready && !tx_valid_r` 的帧边界发送；不插帧内；241 B 全合法、XOR 正确。
- 帧（44 B 头 + 压缩流 + CRC）**字节不变**；v5 不改变帧边界仲裁逻辑。
- `parse_status_v5.py` 放在 `r0/board/`，打印 59 字段与前 55 字段的 v4 兼容解码。

## 4. 时序/缓冲/CDC 约束

- 新增跨域只有 `rd_abort`（clk_a1→clk_ddr，toggle+2FF）和 bridge 观测（clk_ddr→clk_a1，既有 stable-hold mailbox）。不得新增未约束 CDC。
- 所有超时/guard 计数器各自在本域；`rd_timeout` 是 clk_a1 单拍。
- 不新增异步 FIFO 实例；不改 AF/RF/WF 深度；不改 mailbox DIV。
- 不在 purge 时复位全局 FIFO；AF/RF 只按条目丢弃。
- 不改 SDC/ADC/引脚/时钟频率；不 false path/multicycle；不加 ERAM 实例。

## 5. 工作目录与构建入口

- 工作树：`D:/fpga/ph1p100`；包目录 `workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b13-ddr-retry/`。
- 源副本：`r0/changed-src/`（先复制 b12 r0 的 9 个 + `a1_ddr_arb2.v`，再改 6 个）。
- 构建：`r0/td/` 复制 b12 `r0/td/{01_build.tcl,02_bitgen.tcl,03_cwc.tcl,a1_board.al,p2_board.sdc,board_p2.adc}` 与 `r0/td/src/**`；`a1_board.al` 仅改 `<File Path>`；`a1_ddr_arb2.v` 指向 b13 副本。
- TD 环境：`powershell -NoProfile -File tools/td/td_env.ps1 -TdDir <abs r0/td> -Force`；`T:`=r0/td、`Y:`=项目根、`P:`=项目根、`W:`=r0/sim；`X:` 不映射。
- 命令入口：`01_build.tcl`（综合+布线）、`02_bitgen.tcl`（bitgen+BID+final STA）、`03_cwc.tcl`（CWC 且 `compiled.*` 与父文件逐字节一致）。
- 预算：综合≤3、布线≤2、bitgen 1、CWC 1；不 sweep、不重跑 bitgen。

## 6. 仿真入口与 DDR 模型

- 复用 `T10.b12-r1-last/r0/sim/a1_ddr_model.v` / `p2_paxi_model.v` / `tb_*`；新增（或参数化）确定性故障注入：
  - `drop_r_word=k`：第 k 个 R 被丢弃且永不返回；
  - `late_r_delay=D`：第 k 个 R 延迟 D 拍返回（用于 T3）；
  - 模型日志必须打印 `DROP_R word=<k> cycle=<n>` / `LATE_R word=<k> delay=<D>`。
- 检查器只读 DUT 输出与 UART/v5 包；不得改 checker 的 PASS 条件；T2/T3/T5/T6 用真实 b13 changed-src 编译。
- v5 包结构 TB 由 `tb_status_v4.v` 演进为 `tb_status_v5.v`（241 B/59 字段），并保留对旧 55 字段布局的兼容打印。

## 7. 板级入口（冻结顺序）

1. FTDI 预检（不打开 COM8）：`VID_0403&PID_6042`；记录原始输出。
2. 在位：**先下载**（1 次 SRAM）→ `B13_DL_OK` → 释放 FTDI。
3. 再开 COM8 150 s → `parse_status_v5.py` → 241 B/59 字段/bad_xor=0。
4. 目标：`enc_frames/exported` 增量>0；≥1 帧 44 B 头+四 CRC+zlib；无半帧。
5. 记录 `timeout/retry/giveup/stale`；若每帧同一 `rd_idx` 失败且 exported=0 → 停止转 B（DDR IP 调查），不二次下载/第二个 bitstream。
6. 不写 Flash；不 PCIe/RK；不双路/G4。

## 8. 不可变项（复核清单）

- [ ] 44 B 帧头/CRC、压缩字节、crop 几何/ROI 未变
- [ ] UART_DIV/HB_DIV、引脚、SDC、ADC、时钟频率未变
- [ ] `a1_frame_top.v`/`a1_deflate_core.v`/`a1_raw_crop.v`/`cam_diag_mailbox.v` 逐字节未变
- [ ] DDR 四槽布局、DDR IP/PAXI 协议未变
- [ ] 未新增 false path/multicycle/ERAM/降频/改 seed
- [ ] 全局 `rst_n` 未在 purge 时拉低；WF 写 FIFO 不受影响
- [ ] `u_cmp_store` 的 `RETRY_EN=0`，行为与 b12 一致
- [ ] 状态包 v5 只追加 4 字段，`#1..#55` 顺序/表达式不变
