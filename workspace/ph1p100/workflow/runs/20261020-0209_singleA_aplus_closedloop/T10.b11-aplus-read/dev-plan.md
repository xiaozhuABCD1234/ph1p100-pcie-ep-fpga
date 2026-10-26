# T10.b11-aplus-read — dev-plan（规划冻结，2026-10-25）

- run：`20261020-0209_singleA_aplus_closedloop`（项目根 `D:\fpga\ph1p100`）
- 父任务：T10（**保持 blocked**；本包完成也不把 T10 置 done）
- 角色：开发 = fpga-dev（general 代行）；本轮结束另派 1 个新综合测试者
- 状态：**ready**；`needs_user_input=false`（连续烧录已由用户重新授权）
- 批大小 1；本轮 1 个主要可验收目标、1 个正式工作包（内含 5 个语义步骤）

## 0. 冻结的板级事实（b10 r1 / v3，不得重新解释）

证据：`T10.b10-b9-fix/r0/board/captures_final/status_v3.json`（**这是最新一次板级**），
以及同一候选的 `r0/changed-src/{a1_ddr_slot_store.v,camera_a1_uart_top.v,a1_deflate_core.v}`。

| 项 | 值 | 含义 |
|---|---|---|
| cap_frames / crop_roi_frames | 3570 / 3570，crop_short=0、crop_geom_err=0 | 相机与 crop 正常，前端不再是瓶颈 |
| raw slot | slot0=READING、slot1=READY，两槽各 2,592,000 B | raw DDR 双槽写入已修复 |
| raw_deny_nofree | +3570 | 两槽占满后的正确背压 |
| raw_rd_open_ok / raw_rd_close | 1 / 0 | 读到一半，帧未关闭 |
| raw_rd_idx / read_words | 1176 / 1176（**全程不动**） | 只读到第 1176 个 20 B 字 |
| raw_ar_valid / raw_ar_hs / raw_rv_cnt | 1177 / 1177 / 1176 | **发出 1177 个 AR，只回来 1176 个 R：恰好丢 1 拍** |
| rd_state / rd_armed / rd_valid | R_RW / 1 / 0 | 有一个 AR 已“握手”，正在等 R |
| a1_busy / a1_in_valid / a1_in_ready | 1 / 0 / 1 | 帧已开（frame_active=1），核饿着 |
| fstate | F_WAIT | feeder 在等 `raw_rd_valid` |
| cmp_begin_ready / cmp_begin | 0 / 0 | `cmp_begin` 只在 F_IDLE 打过一拍；`wr_begin_ready=!wr_active&&free_valid`，压缩帧在写时本来就不再收第二个 begin |

## 1. 规划裁决：卡点不在 A+ 核，而在“DDR 读响应丢 1 拍”

1. `a1_frame_top.st_busy = frame_active`（upstream 行 189），`in_ready=(istate==I_IDLE)&&!abort&&(frame_active?(!in_sof&&!bank_busy[wr_bank]):...)`（行 193–195）。
   板级 `a1_busy=1` 且 `a1_in_ready=1`，说明帧已开、`istate=I_IDLE`、`bank_busy=0`，核**愿意收**。
2. `camera_a1_uart_top` 的 feeder 只在 `raw_rd_valid` 时从 F_WAIT 进 F_FEED（行 324–333）；
   `a1_in_valid=0` 只是因为它没数据可喂。**“核心 busy 不收输入、不吐输出”是读饥饿的症状，不是核内死锁**。
3. 因此唯一断链是：`rd_state=R_RW` + `rd_armed=1`，第 1177 个 AR 之后 `ddr_rvalid` 永不再来。
   reader FSM（R_IDLE→R_AR→R_RW→R_HOLD）与 `ddr_arvalid=(R_AR)&&!rd_armed`、`ddr_rready=(R_RW)` 本身自洽，**不改 reader 状态机语义**。
4. 关键：store 的 `ddr_arready` 来自 `a1_ddr_arb2`→`p2_ddr_bridge` 的 **地址 FIFO 写侧**（`af_wready`），
   不等于 PAXI/DDR 真的收了 AR。所以“1177 个 AR 握手”只证明地址进了 FIFO，**不证明第 1177 个 AR 发到过 DDR**。
5. b9 与 b10 两次板级都在 **1176 字** 处停（b9 `captures_b9b/status_v3.json` 同样是 1176/1176/1177），
   是**确定性**停点，不是随机延迟；指向地址/协议边界或响应计数错误，必须在仿真里按同一停点复现。

### 1.1 交给开发的候选根因（按优先级排查，禁止跳步猜）

- **H1（桥读响应计数）**：`p2_ddr_bridge` 的 `ar_pending` 只用 `paxi_rvalid && paxi_rready` 清零（行 204–208），
  但 `paxi_rlast` **完全未用**、`rf_push = paxi_rvalid && r_expected`。
  若控制器对一次 AR 给出多余/非 last 的 R，或上一笔残留在 `ar_pending` 已清后又来一拍，
  该拍会被 `paxi_rready=1` 吞掉（`r_expected=0`），随后真正的 R 又被当“过期”丢弃 → A1 侧永久等待。
  判别：`paxi R 计数 vs rlast 计数 vs stale 计数`（v4 #47/#48/#49）。
- **H2（地址 FIFO 进出不平）**：`af` 写侧 `af_wready` 收下地址，读侧 `af_pop=paxi_arvalid&&paxi_arready`。
  若 `af_rvalid` 卡住或 push/pop 竞争，地址留在 FIFO 里永不发；store 已进 R_RW，等不到 R。
  判别：`af 写计数 vs af_pop 计数 vs paxi AR 计数`、`ar_issue_block`（v4 #45/#46）。
- **H3（arbiter 授予/响应同拍覆盖）**：`a1_ddr_arb2` 中 `rd_busy` 的置位（`s_arvalid&&s_arready`）与清零
  （`s_rvalid&&s_rready`）在同一 always 块，若同拍发生清零优先；且 `m0_rvalid` 被 `rd_busy` 门控，
  一拍就可能被丢。判别：`rd_busy/rd_owner` 计数、`set 与 clear 同拍` 断言（v4 #44 + sim 断言）。
- **H4（DDR/PAXI 侧）**：AR 确实发到 PAXI 但控制器不回 R。若证据落在这里，**停止并交规划**
  （属板级 DDR IP/时钟/协议配置，不在 A1 RTL 写域内），不得用假修复掩盖。
- 特别要求：把 `raw_rd_idx=1176` 对应的地址（`RAW_BASE_WORD+1176`）与 PAXI 地址/银行/行边界一起算清，
  解释“为什么正好是 1176”，否则不算定位。

## 2. 工作包 T10.b11-aplus-read（唯一正式包）

**问题**：b10 r1 候选在板上读到第 1176 字后永久等待一个丢失的 DDR 读响应，A+ 核被饿死，
`enc_frames/exported` 恒为 0。**产物**：一个能解释并消除该停点的候选 + v4 状态包 + 板级 ≥1 帧解码。

| # | 语义步骤 | 预算 | 产物/门槛 |
|---|---|---|---|
| W1 | 全尺寸真核复现与定位（**先诊断**） | ≤50 min | `r0/diag/**`；真实 `a1_frame_top+a1_deflate_core` 跑 1920×1080 两帧 raw→reader→core→cmp→export，DDR 侧用 `p2_paxi_model` 并按“AR 1 拍、R 可延迟/可背压/rlast 语义”加压；必须复现“129,600 字里只到 1176 字”或给出模型不能复现的证据；落 H1–H4 判别表 |
| W2 | 一处最小修复 + 有界看门狗 | ≤30 min | 只在 W1 证明的那一点改；另加 feeder/reader **有界超时**（F_WAIT 或 R_RW 超 N 拍 → 干净 abort：`a1_abort`/`raw_rd_close`/`cmp_abort`/计数，回 F_IDLE），保证任何未来丢拍不再永久挂死；好帧压缩字节必须不变 |
| W3 | P1 三黄金 + v4 包仿真 | ≤30 min | micro8x2 / mid64x8 / full_grad(1920×1080) 压缩输出**逐字节同 b10 r0 基线**；四 CRC、zlib、dup=0、无半帧；v4 包 XOR/长度/单边沿快照/不插帧内；`vlog 0/0` |
| W4 | 重建（1 bitgen + 1 CWC） | TD 内 | Routed **0 违例**、WNS **≥ +0.05**（目标 ≥+0.2）、hold≥0、ERAM+CWC ≤300；bit/CWC/BID/compiled 自洽并冻结 |
| W5 | 板级（**先下载、后开 COM8**） | ≤25 min | 1 次构建的 bit，**≤2 次下载（同一 bit）**；COM8 150 s；v4 包 ≥120 个全合法；`enc_frames/exported` 增量 **>0**；≥1 完整帧 44 B 头+header_crc+stream/xform/raw CRC+zlib；无半帧 |

### 2.1 写域/工作树

- 工作树：**`D:/fpga/ph1p100`**（唯一主源）。
- 允许写：`run/T10.b11-aplus-read/**`（`changed-src/`、`sim/`、`td/`、`board/`、`diag/`、`caps/`、日志、manifest）。
- 允许改的源（复制到 `r0/changed-src/` 后再改，`a1_board.al` 只改 `<File Path>`）：
  - 必改：`camera_a1_uart_top.v`（feeder 看门狗、v4 打包源）、`a1_uart_export.v`（v4 包，LEN/VER/HDR_LAST 与 XOR）、
    `a1_ddr_slot_store.v`（只在 W1 证明 reader 有责时改；否则保持）、`p2_ddr_bridge.v`（H1/H2 落点时）、
    `a1_ddr_arb2.v`（仅 H3 落点时）。
  - **可观测性允许**：`a1_deflate_core.v` 增加 `output wire [4:0] dbg_state`；`a1_frame_top.v` 增加 `output wire [31:0] dbg`
    转发 `{istate,dstate,frame_active,wr_bank,rd_bank,cooldown,core_in_ready,eidx,core 状态,src_ready,din_valid}`。
    **只加输出/连线，不改任何功能逻辑**；两者新哈希必须入 manifest，并由 P1 三黄金逐字节一致证明功能等价。
  - 禁止：改 `a1_raw_crop.v` 几何语义、crop 参数、DDR 四槽布局、UART 帧格式（44 B 头/CRC）、UART_DIV/HB_DIV、
    引脚/SDC/时钟频率、`upstream/**`、旧 run/证据/manifest、`workflow/tasks.json`、嵌套副本 `workflow/workflow/**`。
  - 禁止 false path / multicycle / 改 seed / 降频 / 新增 ERAM 实例；禁止批量删除（只用 `Remove-Item <单文件>`，需删前先问）。
- 仿真路径：`P:` = 项目根，`W:` = `r0/sim`；TD 路径：`T:` = `r0/td`，`Y:` = 项目根（`tools/td/td_env.ps1`）；`X:` 不映射项目根。

## 3. 状态包 v4（冻结格式，整包单边沿快照）

线上格式（小端）：`A5 5A E1 04` + **55 × u32** + `XOR8(bytes 0..223)` = **225 B**；`LEN=0xE1`、`VER=0x04`、`HDR_LAST=55`、`sidx 0..224`。
#1–#43 与 v3 **逐位不变**（v3 parser 仍可用前 177 B 自检）；#44–#55 为新增，全部在**同一个 clk_a1 沿**与 v3 一起锁存。

| # | 名称 | 位图/含义 |
|---|---|---|
| 44 | `br0` | [0]`ddr_rdy` [1]`ar_pending` [2]`af_rvalid` [3]`af_wready` [4]`rf_rvalid` [5]`rf_wready` [6]`s_rvalid_r` [7]`s_rready` [8]`wstate` [9]`aw_seen` [10]`w_seen` [11]`wf_rvalid` [12]`wf_pop` |
| 45 | `ar_cnt` | PAXI `arvalid&&arready` 计数 |
| 46 | `ar_block_cnt` | `af_rvalid && !paxi_arvalid` 的拍数（AR 在等/被挡） |
| 47 | `r_cnt` | PAXI `rvalid&&rready` 计数 |
| 48 | `rlast_cnt` | PAXI `rvalid&&rready&&rlast` 计数（判 H1：是否 `r_cnt==rlast_cnt`） |
| 49 | `stale_r_cnt` | `paxi_rvalid && !ar_pending` 的拍数（被吞掉的 R） |
| 50 | `rd_wait_cycles` | `rd_armed && !ddr_rvalid` 连续拍数（饱和，R 到达清零） |
| 51 | `core0` | [4:0]core `S_*` state [5]`core_in_ready` [6]`core_in_valid` [7]`core_out_valid` [8]`core_out_ready` [9]`core_busy` [10]`core_done` |
| 52 | `frame0` | [1:0]`dstate` [4:2]`istate` [5]`frame_active` [6]`wr_bank` [7]`rd_bank` [8]`cooldown` [9]`core_in_ready` [11:10]`eidx` [12]`first_byte` |
| 53 | `src0` | [0]`src_ready`（bank 源可读） [1]`din_valid`（核输入字节有效） [2]`bank_busy0` [3]`bank_busy1` [31:4]0（按实际网名映射并在 parser 注释） |
| 54 | `exp0` | [1:0]`estate` [3:2]`pstate` [5:4]`dq_cnt` [6]`wbuf_valid` [7]`cmp_open_ready` [8]`cmp_rd_valid` [9]`cmp_rd_take` [10]`status_due` [11]`sstate` [12]`cmp_open` |
| 55 | `fwait_cycles` | feeder 在 F_WAIT 且无 `raw_rd_valid` 的连续拍数（饱和） |

硬约束：
- 包仍然**只在 exporter idle（`estate==E_IDLE`、队列空、无帧打开）**时发；不得插入帧头/payload 内；1 Hz 分频不变。
- 新增源必须是 clk_a1 寄存器/线（跨域量先 2FF 或用既有同步值），**不得把 clk_ddr 原信号直接打进快照**（p2_ddr_bridge 的计数在 clk_ddr 侧，需 2FF 同步或做成 clk_a1 侧观测寄存器）。
- 新 parser `r0/board/parse_status_v4.py`：校验 MAGIC/LEN/VER/XOR，打印 #44–#55 全部位域、delta/level、判决链
  （`AR 是否发出 → 是否回 R → R 是否进 skid → 是否被 store 收 → feeder 是否喂`）。v3 parser 不改。

## 4. 门槛（必须逐项取证）

| 阶段 | 门槛 |
|---|---|
| 定位 | `r0/diag/read-stall-analysis.md` 给出 H1–H4 判别（含计数/波形/`$display` 片段），能解释 1176 字停点；不能解释则不得声称定位 |
| P1 sim | 三黄金逐字节同基线；四 CRC true；`zlib_ok`；`dup_words=0`；`geom=0 err=0 raw_drop=0 cmp_drop=0`；无 X/半帧；`vlog 0/0` |
| 集成 sim | 1920×1080 全尺寸、**真实 A+ core**（非 mock）、两帧；读完整 129,600 字、`enc_frames=2`、`exported=2`；无看门狗误触发 |
| v4 sim | 225 B、XOR 全对、单边沿快照、不插帧内；`r_cnt==rlast_cnt` 与 `stale_r_cnt` 有确定结论 |
| 综合 | 0 违例端点、SWNS≥0；≤3 次 |
| 布线 | 0 违例、WNS≥+0.05（<+0.2 记 caveat）；≤2 次；两次逐位相同即停 |
| bit/CWC | 1 bitgen + 1 CWC；bit/CWC/BID/compiled 哈希冻结 |
| 板级 | 先下载后开 COM8；同一 bit ≤2 次下载；150 s；v4 包 ≥120 全合法；`enc_frames`/`exported` **增量>0**；≥1 帧 44 B 头 + header_crc/stream/xform/raw CRC + zlib 全过；无半帧 |

## 5. 预算、停止与回退

- 开发：**150 min / 70 calls**；TD **3 会话**、综合 **≤3**、布线 **≤2**、**bitgen 1**、**CWC 1**、下载 **2（只能同一冻结 bit）**、Flash 0。
- 条件分支：
  - W1 在 50 min 内定位 → W2 修复 → W3 回归 → W4 构建 → W5 板级；这是主路径。
  - W1 超时仍无法解释 1176 字 → **不做猜测性功能修复**；允许把 v4 + 有界看门狗作为**纯诊断构建**，仍执行 W3（三黄金必须逐字节不变）、W4、W5，
    报告记 `diagnosis_only`、不宣称目标达成；**不再申请第二个 bitgen**。
  - 任何需要第二个 bitstream 的功能修复 → 停止交规划，不自行扩预算。
- 立即停止（不建/不下载）：P1 任一例非逐字节一致；核心/frame 出现功能字节变化；ERAM+CWC>300；
  综合 3 次仍负；布线 2 次仍 <+0.05；v4 破坏帧内/帧间边界；两次下载用尽仍 0 帧；H4 落点（DDR IP 侧）。
- 回退：源与 bit 均以 b10 r1 冻结件为基线（8 个源哈希见 `T10.b10-b9-fix/r0/artifact-hashes-r1.txt`）；
  新候选失败只回退 `a1_board.al` 的本地副本路径，不改 upstream。
- 下载授权：用户已重新授权连续烧录；本包只允许 SRAM（`-mode jtag`），**不写 Flash**、不 PCIe/RK、不做双路/G4。

## 6. 下一次准确启动/恢复文本（开发）

> 恢复 `20261020-0209_singleA_aplus_closedloop` 的 **`T10.b11-aplus-read` r0**（ready；1 bitgen+1 CWC；同一 bit ≤2 次 SRAM 下载）。
> 先读 `T10.b11-aplus-read/dev-plan.md`、`handoff.md`、`dispatch.json`、`T10.b10-b9-fix/r0/board/captures_final/status_v3.json`、
> `T10.b10-b9-fix/r0/{result-r1.md,changed-src/,sim/,td/}`。
> 结论先行：卡点不是 A+ 核，而是第 1177 个 AR 之后丢 1 个 DDR 读响应（1176/1176/1177，b9/b10 同为 1176 字）。
> 先做 W1：真实 core 全尺寸两帧复现 + v4 字段 + H1–H4 判别（≤50 min）；定位后只改那一点，并加有界看门狗；
> 再做 P1 三黄金逐字节 + v4 包仿真；然后 1 bitgen+1 CWC（Routed 0 违例、WNS≥+0.05、ERAM+CWC≤300）；
> 板级**先下载后开 COM8**，150 s，目标 `enc_frames/exported` 增量>0 且 ≥1 帧四 CRC+zlib 通过。
> 150 min/70 calls；TD 3 会话/综≤3/布≤2/bitgen 1/CWC 1/下载 2；失败即停，不自扩预算，不批删。
