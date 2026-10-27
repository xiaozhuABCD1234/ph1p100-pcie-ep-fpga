# T10.b9-rawstore 设计指南（冻结）

本文件冻结本任务的数据格式、接口、帧完成条件、诊断口径与状态包 v3 布局。dev 实现与 tester 验收都以本文件为准；与本文件冲突的旧描述（b7/b8 计划中"raw_drop=0 表示没丢帧"等）不生效。

---

## 1. 数据格式（冻结，不允许改）

| 项 | 值 | 依据/校验 |
|---|---|---|
| 每 beat | 4 px，40-bit RAW10 打包（`{b4,b3,b2,b1,b0}`，每像素 10-bit → 5 B/组） | `a1_raw_crop` 端口 `[39:0]`；`csi_rx_10bit_unpack` |
| crop 输出 | 1920×1080 → 每行组数 `OG = W/4 = 480`，每帧组数 `NGRP = 480×1080 = 518,400` | b8 实测 `crop_groups` 每帧 +518,400 |
| store 打包（MODE 0） | 4 组/256-bit 字，`FLUSH_CNT=3`，`add_bytes=5`/拍 | `a1_ddr_slot_store.v` L105/117/118 |
| 每帧字数 | 518,400 / **4 = 129,600 字**（整除 ✔） | `RAW_WORDS = (GROUPS+3)/4 = 129,600` |
| 每帧字节 | 1920×1080×10/8 = **2,592,000 B**；2,592,000/20 = **129,600 字**（整除 ✔） | `EXP_RAW_BYTES`，publish 前逐字节校验 |
| slot 容量 | `AWB=18` → 262,144 字 > 129,600 ✔；slot1 基址 = 129,600 字 = 4,147,200 B；`CMP_BASE=131,072` 字 = 4,194,304 B，间隔 47,104 B，不重叠 ✔ | `01_build.tcl` 参数 |
| 读回字数 | `words_of = (len+19)/20 = 129,600` | store L133 |

**结论：整除关系、帧长、slot 容量三者自洽，帧长/打包不匹配这一假设被排除。** 板级 `crop_groups` 恰好 = 3300×518,400 也反证 crop 侧完整。

## 2. 帧完成条件（冻结）

1. `out_sof` 与 ROI 第 1 组同拍（`out_cnt==0`）；`out_last` 与第 518,400 组同拍；`done` 置 1 后到 `frame_rise` 前不再收数。
2. store 侧：`wr_last` 触发末字 flush；`nbytes+5 == EXPECT_BYTES(2,592,000)` 才 `slot_st=S_READY, st_published+1`；否则 `slot_st=S_FREE, st_dropped+1`（**绝不发布半帧**）。
3. 行计数校验：`line_idx <= ROI_Y+H-1` 的行必须恰有 `CG=966` 个组，否则 `out_abort` + `st_geom_err+1`。

## 3. 静态核对结论：4 个明确缺陷（本轮修复）

行号基于 b8 生效版本。

- **F1（明确 bug，必修）abort 过不了 CDC。**
  `a1_raw_crop.v` L135/L144 只把 `out_abort` 拉高一拍，**同拍 `out_valid=0`**；而 `camera_a1_uart_top.v` L115 只在 `crop_valid` 时写 FIFO（`w_data={abort,last,sof,pix}`）。→ `e_abort` 永远不会出现 → store 收不到 `wr_abort`，`wr_active` 保持 1，此后再无 `wr_begin`，**整链永久卡死且不打任何计数**。
  修法：abort 必须随一个有效 beat 跨域（例如在 abort 拍的 `out_pix` 放一个哑组并使 `out_valid=1`，或把 abort 并入下一拍 beat 的标志位），A1 侧见到 abort-beat 即 `wr_abort`、清 `raw_active`、`raw_drop+1`，并新增 `raw_abort_cnt` 计数。要求：一个 abort 只消耗一个 FIFO 项、不写 DDR。

- **F2（明确 bug，必修）无空 slot 时整链静默冻结 + FIFO 静默丢数。**
  `camera_a1_uart_top.v` L148-156：`e_sof` 且 `!raw_begin_ready` 时 `fifo_ready` 恒 0 → CDC FIFO（512 深）写满，而写侧 `w_ready` 未接（`capture_async_fifo` 满时 `push=0`）→ **整帧 beat 被静默丢弃**，且 `raw_drop` 仍为 0。板级 `raw_drop=0` 因此不能证明"没丢帧"。
  修法：`e_sof` 且 `!raw_begin_ready` 时**整帧丢弃**：`fifo_ready=1`、置 `skip_frame`、直到下一个 `e_sof` 前全部吃掉落盘（`raw_drop+1`、`raw_begin_deny+1` 及原因位），不得让 FIFO 溢出到半帧。FIFO 满事件另加 `fifo_ovf_cnt`（cam 域计数，跨域后进 v3）。

- **F3（明确 bug，必修）P2 DDR 桥读引擎可丢 AR / 可重发 AR。**
  `p2_ddr_bridge.v` L178-186：`af_pop = af_rvalid && paxi_arready && ddr_rdy`，**没有被 `paxi_arvalid`/`!ar_pending` 限定**；而 `paxi_arvalid = af_rvalid && !ar_pending` 又**没有 `ddr_rdy` 限定**。后果二选一：
  - `ar_pending=1` 期间弹出的地址被丢弃，store 那一拍 AR 永不返回 → `R_RW` 永久等待（`read_words` 停在该字）；
  - `ddr_rdy=0` 时同一 AR 反复握手 → RF 里多出重复数据 → 后续读整体错位并最终卡死。
  修法：`paxi_arvalid = af_rvalid && !ar_pending && ddr_rdy`；`af_pop = paxi_arvalid && paxi_arready`（**握手即弹出，无握手不弹出**）；`ar_pending` 只由「已发出 AR」置位、由 `paxi_rvalid && paxi_rready` 清除。写通道同理复核 `wf_push` 与 `s_awready` 只在握手成立时置位。

- **F4（明确 bug，必修）raw store 的 `ddr_ready` 被硬接 1。**
  `camera_a1_uart_top.v` L206 `.ddr_ready(1'b1)`。store 契约要求 DDR 就绪才收 `wr_begin`/写数据；P1 由 arb2 保证，P2 完全没接。修法：给 `camera_a1_uart_top` 增加 `i_ddr_rdy` 端口，P2 顶接 bridge 的 `ddr_rdy`（或 `wf_wready && af_wready`），P1 TB 接 1'b1 保持黄金样例不变。

## 4. 板级数据给出的方向（不是猜测）

`raw_pub` 的 OR 掩码恒为 `0x00000002`：**只在采集早期（首包之前）发布过 2 帧，此后 88 s 内一动不动，且 0 drop / 0 error / read_words=0**。两帧能发布 ⇒ 写通道确实工作过（每次发布都要 129,600 次写握手、2,592,000 B 精确匹配），⇒ **卡点在发布之后：要么读没打开，要么读打开但 DDR 不回数据**。两个 slot 被占满后 `free_valid=0`，后续每帧都在 `e_sof` 被拒 → 只剩 crop 计数在涨，与实测完全吻合。

判定口径（v3 必须能唯一定位，四选一并给计数）：

| 结论 | 判据 |
|---|---|
| A 读已打开但 DDR 不回数 | `raw_rd_open_ok>0` 且 `raw_ar_valid>0`、`raw_ar_ready` 可能 >0，但 `raw_rv_cnt=0`；`rd_state` 停在 R_RW |
| B 读连 AR 都发不出 | `raw_rd_open_ok>0`，`raw_ar_valid>0`，`raw_ar_ready=0`（`rd_state` 停在 R_AR） |
| C 读根本没打开 | `raw_rd_open_ok=0`，`rd_state` 停在 R_IDLE；看 `raw_rd_state` 的 `a1_busy/a1_out_valid/raw_rd_open_ready/cmp_begin_ready/fstate` 哪一位卡住 |
| D 写侧没起来 | `raw_begin_ok=0`、`raw_wr_beats=0`、`raw_pub` 不涨 |

## 5. 状态包 v3（冻结布局）

- 帧格式沿用 v2：`5 B 头 + 32-bit 字段序列`；头内 **版本字节 = 3**，长度字节 = **177**（5+43×4），XOR 校验覆盖同 v2 规则。
- 前 23 字段**完全沿用 v2 顺序与语义**（cap_frames … cam_nack_cnt），v2 解析脚本只需改版本/长度即可继续读前 23 项。
- 新增 20 字段（序号 24..43，全 32-bit，小端）：

| # | 名称 | 含义 |
|---|---|---|
| 24 | raw_begin_ok | `wr_begin` 被接受次数 |
| 25 | raw_begin_deny | `e_sof` 被拒次数（整帧丢弃，F2 后） |
| 26 | raw_wr_beats | store 接受的组数（每拍 +5 B） |
| 27 | raw_wr_words | 已 flush 的 256-bit 字数（`ddr_wvalid` 计数） |
| 28 | raw_wr_ptr | 当前 `waddr`（0..129,599 电平） |
| 29 | raw_wr_state | `[31]=wr_active [30]=wr_slot [29:27]=wcnt [26:0]=nbytes` 打包 |
| 30 | raw_rd_state | `[1:0]=rd_state [2]=rd_armed [3]=rd_sel [4]=rd_valid [5]=raw_rd_open [6]=raw_rd_open_ready [7]=raw_drop [8]=skid_valid [9]=fifo_valid [10]=fifo_ready [11]=raw_active [12]=a1_busy [13]=a1_out_valid [14]=cmp_begin_ready [16:15]=fstate [17]=a1_in_valid [18]=a1_in_ready [19]=a1_out_last [20]=cmp_begin [21]=cmp_abort`，其余 0 |
| 31 | raw_slot_st | `[1:0]=slot0 [3:2]=slot1`（0 FREE/1 WRITE/2 READY/3 READING），`[4]=seq0 [5]=seq1` |
| 32 | raw_slot_len0 | `slot_len[0]`（电平，正常应为 2,592,000） |
| 33 | raw_slot_len1 | `slot_len[1]` |
| 34 | raw_rd_idx | 读 FSM 当前 `rd_idx` |
| 35 | raw_rd_words | 本帧应读字数（正常 129,600） |
| 36 | raw_ar_valid | `s_arvalid=1` 的拍数（累计） |
| 37 | raw_ar_hs | AR 握手次数（`s_arvalid && s_arready`） |
| 38 | raw_rv_cnt | `s_rvalid=1` 的拍数（累计） |
| 39 | raw_rd_open_ok | `rd_open` 被接受次数 |
| 40 | raw_rd_close | `rd_close` 次数 |
| 41 | raw_abort_cnt | 收下并清掉的 abort 帧数（F1 后） |
| 42 | raw_deny_nofree | begin 被拒中「无空 slot」的次数 |
| 43 | raw_deny_ddr | begin 被拒中「DDR 未就绪」的次数 |

硬要求（否则数据不可信）：

1. **整包同一拍快照**：在 `clk_a1` 域用一个 `snap_en` 脉冲把 43 字段（含 v2 老字段中的 A1 侧量）整体锁进影子寄存器，保持稳定直到本包发完（≥2 个包周期）。禁止逐位直接跨域采计数器（多位 CDC 会撕裂）。
2. 快照机制建议：每字段一个 `cam_diag_mailbox`（64b）实例按双字扩容（43/2 → 22 个），与 b7 同构、不改协议、不改 UART 分频；若选 32b 索引邮箱须自证单包一致性。
3. `st_*` 计数位宽：`raw_wr_words`、`raw_rv_cnt` 等在 90 s 内可超 2^32？字数 129,600×3300 ≈ 4.3e8 < 2^32 ✔（`raw_ar_valid` 拍数同量级，安全）。
4. v2 的 23 个字段语义不得改；`errors` 仍为 `raw_st_err+cmp_st_err+exp_err`。

## 6. 工作目录、构建与复现入口

- 唯一可写：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b9-rawstore/**`
- 源码基线：拷 b8 的 `r0/changed-src/*.v` + `r0/td/src/**` 到本任务 `r0/`，**改 `r0/changed-src/` 与 `r0/td/src/` 内的副本，不动 `fpga/csi2/src/**`**。
- `r0/td/01_build.tcl`：从 b8 复制，把 `add_files Y:/workflow/.../T10.b8-.../r0/changed-src/X.v` 全部改指 `T10.b9-rawstore`，并把 `a1_ddr_slot_store.v` 改为本任务副本；`p2_ddr_bridge.v`/`dbg_uart.v` 用 `./src/` 本任务副本。
- 盘符：TD 用 `T:`（本 run `td` 目录）、`Y:`（项目根）；仿真用 `P:`/`W:`；开 TD 前先 `tools/td/open_td.ps1`。禁用 `X:`。
- 板级：`r0/board/` 复用 b8 的 `capture_com8.py`、`download_sram_b8.tcl`（改名 b9）、新增 `parse_status_v3.py`。

## 7. 不改清单

帧头/CRC/zlib 打包格式（44 B 头）、DDR 布局与地址、SDC/引脚/时钟频率、UART 分频、I2C/MIPI 配置、I2C 时序、显示/预览通路、crop 几何参数（3864×2192/ROI 972,556/1920×1080）、`a1_deflate_core` 压缩核心行为。任何一条需要改即停止并交回规划。
