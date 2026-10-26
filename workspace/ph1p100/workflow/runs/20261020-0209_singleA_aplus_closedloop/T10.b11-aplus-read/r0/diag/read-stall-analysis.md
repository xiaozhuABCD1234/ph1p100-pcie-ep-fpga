# T10.b11-aplus-read — 读响应丢拍定位报告（W1）

- 日期：2026-10-25；run `20261020-0209_singleA_aplus_closedloop`；包 `T10.b11-aplus-read` r0
- 冻结基线：`T10.b10-b9-fix/r0`（源 8/8、bit `ba5fb801…`、Routed SWNS +0.103、板级 `captures_final/status_v3.json`）
- 本次结论：**A1 侧读通路（slot store → arb2 → p2_ddr_bridge → PAXI）在 RTL 上不能丢 R**；1176 字停点无法归因于该 RTL，
  也没有在仿真中复现。按 dev-plan §5 走 `diagnosis_only`：交付 v4 状态包 + 有界看门狗，不做猜测性功能修复，不申请第二个 bitstream。
- 若需判定板级真因，v4 的 #44–#50 已按“AR 是否发出 → 是否回 R → 是否进 skid → store 是否收到”排好判别链，见第 6 节。

## 1. 静态复核（读通路为什么 1:1）

读通路只有四处会影响“AR 数与 R 数”的配对，逐条核过：

1. `a1_ddr_slot_store` reader：`ddr_arvalid=(R_AR && !rd_armed)`，`R_AR→R_RW` 与 `rd_armed<=1` 同一个
   `ddr_arready && !rd_armed` 条件；`R_RW` 收到 `ddr_rvalid` 才清 `rd_armed`、`rd_idx++` 并进 `R_HOLD`。
   因此**一次 read 会话内 AR 握手数 = 收到 R 数 + 1（最后一个在途）**，绝不可能少发或多收——除非上游 `ddr_rvalid` 不来。
2. `a1_ddr_arb2`：`rd_busy` 的置位条件含 `!rd_busy`，清零条件是 `s_rvalid && s_rready`，而
   `s_rready = rd_busy ? m_rready : 0`。二者互斥，**同拍置位/清零不可能**（H3 结构性排除）；`rd_busy` 也不被写通路影响
   （写授予只影响 `wr_last`）。
3. `p2_ddr_bridge` 读引擎：`ar_pending` 只由 `af_pop=paxi_arvalid&&paxi_arready` 置位、由
   `paxi_rvalid&&paxi_rready` 清零；`paxi_arvalid` 含 `!ar_pending`，所以 **af_pop 与 R 握手不可能同拍**，
   每个 AR 严格配一个 R。`rf_push = paxi_rvalid && ar_pending`，`paxi_rready = ar_pending ? rf_wready : 1`：
   没有在途 AR 时来的 R 被吞掉并计入 `stale_r_cnt`，**不会影响在途 AR 的配对**（H1 的“吞掉真 R”要求 R 与 AR 错位，
   而错位需要 PAXI 给出多余 R 或漏给 R，均不在 A1 RTL 内）。
4. `capture_async_fifo`（AF/RF）：读侧预取 `fetch=!empty&&(!r_valid||r_ready)`，而 `r_ready` 只有在
   `r_valid` 有效时才可能为 1（`af_pop` 含 `af_rvalid`，`rf_pop=s_load` 含 `rf_rvalid`），所以
   `fetch=1 ⇒ mem[rbin]` 一定是已写入的项，**不存在“空 FIFO 幽灵项”**；指针推进与 `r_valid` 一一对应。

结论：H1（bridge 吞 R 导致死等）、H3（arbiter 同拍覆盖）在 RTL 上不成立；H2 只有在 **AR 明明进了 AF FIFO 却再也不被弹出**
时成立（`ar_pending=1` 卡死、或 `ddr_rdy=0`、或 `paxi_arready=0`）。

## 2. W1 仿真：全尺寸真 RTL 读回不丢拍

台架 `r0/sim/tb_b11_read.sv` = 真实 `a1_ddr_slot_store(MODE 0, SLOT_WORDS=129600, EXPECT_BYTES=2592000)`
+ 真实 `a1_ddr_arb2` + 真实 `p2_ddr_bridge`（**clk_a1 187.5 MHz / clk_ddr 200 MHz 真双时钟、真 CDC**）
+ `p2_paxi_model_b11`（单拍 256 bit、AR/R 可背压、可延迟）。写满一个 raw 槽后整槽读回，逐拍与影子比对。

| case | 参数 | 结果 | 关键计数 |
|---|---|---|---|
| one | NWRITE=1 | PASS | words=1 bad=0 |
| multi | NWRITE=2000 | PASS | words=2000 bad=0 |
| bp | NWRITE=2000, AR_GAP=2, R_GAP=12 | PASS | words=2000 bad=0 |
| late | NWRITE=2000, R_GAP=40 | PASS | words=2000 bad=0 |
| stray | NWRITE=2000, 首 AR 前注入 1 个无主 R | PASS | words=2000 bad=0, **stale=1**（被吞、无副作用） |
| dup | NWRITE=9000, 第 4096 拍后重放同一拍 | PASS | words=9000 bad=0, stale=1（多余 R 被吞，不位移） |
| reset | 读中复位再重读 | PASS | 复位后重写重读 words=2000 bad=0 |
| **full** | **NWRITE=129600（整帧）** | **PASS** | **words=129600 bad=0**，ar_hs=r_cnt=rlast=129600+1(在途) |

日志：`r0/sim/logs/sim_read_*.log`；汇总 `r0/sim/sim-results-b11.json`。
`read_full` 是决定性的负结果：**在真 CDC、真 arbiter、真 store、可真背压/延迟的 PAXI 下，129,600 字一字不差读完，没有 1176 停点**。

## 3. 1176 不是地址/边界伪影

RAW_BASE=0、slot0、MODE 0（4×20 B/256 bit 字）⇒ 停点地址 = 第 1176 个 256-bit 字 = 字节 37,632。
按 td 内 DDR3-1600 x32 IP 配置（ROW=14、COL=10、BA=3、256-bit 口）换算：
字地址 bit[9:0]→列、bit[12:10]→bank、bit[13:]>→行 ⇒ 1176 = 行 1 / 列 152。
既不是 2 的幂边界，也不是行/列/bank 的翻转点，也不是四槽布局边界（RAW1=129600..259199、CMP_BASE=262144）。
⇒ 1176 只能是**计数/事件**造成的停点（某个时刻起 AR 不再被 PAXI 收、或收了不回），不是地址译码问题。

## 4. H1–H4 判别表（含本次证据）

| 假设 | 机制 | 本包证据 | 结论 |
|---|---|---|---|
| H1 | bridge 把真 R 当“过期”吞掉（`ar_pending` 提前清） | 静态：`af_pop` 与 R 握手互斥，AR/R 严格 1:1；仿真 stray/dup：多余 R 只进 `stale_r_cnt`，130k 字无位移 | **排除**（作为“永久停”的成因） |
| H2 | 地址进了 AF FIFO 但不再被弹出 | 静态：仅当 `ar_pending` 卡 1 / `ddr_rdy=0` / `paxi_arready=0`。仿真注入 `ddr_rdy` 长低会表现为 af_rvalid=1、ar_pending=0、`ar_block_cnt` 单调涨 | **可能，需板级 #44[0]/[1]/[2]、#45/#46 判定** |
| H3 | arbiter 授予/响应同拍覆盖 | 静态：`!rd_busy` 与 `s_rready` 门控互斥，同拍不可能；仿真全尺寸无丢拍 | **排除** |
| H4 | AR 到了 PAXI，控制器不回 R | 仿真无法构造（模型保证 1:1）；板级若 #45(ar_cnt)==#37(ar_hs) 且 #47(r_cnt)<#45、#44[1]=1、#44[2]=0 即命中 | **板级待判**（命中即属 DDR IP 侧，按计划停止、不做假修复） |

**因此本包不做猜测性功能修复**（dev-plan §5 第二分支）：不改 store reader FSM、不改 arbiter、不改 bridge 协议语义。

## 5. 本包交付的 RTL（只加观测 + 有界看门狗）

- `a1_uart_export.v`：状态包 v4 = `A5 5A E1 04` + 55×u32 + XOR8 = 225 B，`LEN=0xE1`、`VER=4`、`XOR` 覆盖 byte 0..223；
  #1–#43 与 v3 同源同序（逐位不变），#44–#55 同一 clk_a1 沿一起锁存，仍只在 exporter idle 时发。
  新增 `dbg_st[31:0]`（#54 源）与 `sts_ext[383:0]` 输入。
- `camera_a1_uart_top.v`：新增 `i_dbg_bridge[191:0]` 输入；新增 #50 `rd_wait_cycles`、#55 `fwait_cycles` 两个饱和计数器；
  新增 **F_WAIT 有界看门狗**（`WD_LIMIT=2^24` ≈ 89.5 ms @187.5 MHz）：无 `raw_rd_valid` 超时 ⇒ `a1_abort + cmp_abort +
  raw_rd_close + wd_fires++ + 回 F_IDLE`，好帧路径永不触发（P1 三黄金逐字节一致已证）。
- `p2_ddr_bridge.v`：新增 `dbg_a1[191:0]`（#44 br0 + #45–#49 计数）；clk_ddr 计数经
  `cam_diag_mailbox`（W=192，DIV_BITS=8，1.28 µs 稳定保持 + toggle）跨到 clk_a1，**不把 clk_ddr 原信号打进快照**。
  br0 中 clk_ddr 位（ddr_rdy/ar_pending/af_rvalid/rf_wready/wstate/aw_seen/w_seen/wf_rvalid/wf_pop）走邮箱，
  clk_a1 位（af_wready/rf_rvalid/s_rvalid_r/s_rready）直连。
- `a1_deflate_core.v`：仅新增 `output wire [4:0] dbg_state`（读 `state` 寄存器）。
- `a1_frame_top.v`：仅新增 `output wire [31:0] dbg`（dstate/istate/frame_active/banks/cooldown/eidx/first_byte/
  bank_busy/src_ready/din_valid/core 握手/core FSM）。**注意**：dev-plan 的 #52 位图把 `eidx` 放在 [11:10]（2 bit），
  而 `eidx` 实为 3 bit（0..4），故实际位图整体上移一位为 [12:10]eidx、[13]first_byte、[14]bank_busy0…，
  已在 `a1_frame_top.v` 与 parser 注释中写明，`#52`/`#53` 的语义不变。
- `p2_a1_board_top.v`：把 bridge 的 `dbg_a1` 连到 `camera_a1_uart_top.i_dbg_bridge`（纯连线）。
- 未改：crop 几何、四槽布局、44 B 帧头/CRC、UART_DIV/HB_DIV、引脚/SDC/时钟、upstream。

## 6. 板级判别链（下一次 COM8 抓包直接读）

1. `#37 raw_ar_hs`（地址进 AF）vs `#45 ar_cnt`（AR 打到 PAXI）：
   - 相等 ⇒ AR 已到 DDR，转 2；差 1 且 `#44[2] af_rvalid=1`、`#44[1] ar_pending=0`、`#46 ar_block_cnt` 持续增
     ⇒ **H2：AR 卡在 AF**（看 `#44[0] ddr_rdy` 是否为 0；ddr_rdy=0 → DDR PHY ready 掉了）。
2. `#45 ar_cnt` vs `#47 r_cnt`/`#48 rlast_cnt`：差 1 且 `#44[1] ar_pending=1`、`#44[2] af_rvalid=0`
   ⇒ **H4：DDR 收了 AR 不回 R**（DDR IP/时钟/协议侧，按计划停止交规划）。
3. `#49 stale_r_cnt` > 0 ⇒ 出现过无主 R（复位残留或控制器多发），但按 §2 只吞不位移。
4. `#50 rd_wait_cycles` 饱和 ⇒ store 一直 `rd_armed` 等 R（与 v3 的 `raw_rd_state=R_RW` 同证）。
5. 判别脚本：`r0/board/parse_status_v4.py`（MAGIC/LEN/VER/XOR 校验 + #44–#55 位域 + 判别链 + 退出码
   0=平衡 / 3=AR 卡 AF / 4=DDR 不回 R / 5=不确定）。
