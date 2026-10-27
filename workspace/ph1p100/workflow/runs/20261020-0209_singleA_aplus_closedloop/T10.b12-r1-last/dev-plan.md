# T10.b12-r1-last — dev-plan（规划冻结，2026-10-25）

- run：`20261020-0209_singleA_aplus_closedloop`（项目根 `D:\fpga\ph1p100`）
- 父任务：T10（**保持 blocked**；本包完成也不把 T10 置 done）
- 角色：开发 = fpga-dev（general 代行）；本轮结束另派 1 个新综合测试者
- 状态：**ready**；`needs_user_input=false`
- 批大小 1；本轮 1 个主要可验收目标、1 个正式工作包（内含 5 个语义步骤）
- 本轮只修 **R1（丢 LAST/拒收后的孤儿 writer）**；1176 读响应停点仍按 b11 的诊断链处理，不在本包猜修

## 0. 冻结输入与基线（不得重新解释）

### 0.1 代码/构建基线 = b11 r0

`T10.b11-aplus-read/r0` 是唯一源基线（v4 225 B + F_WAIT 有界看门狗 + 观测端口已在其中）：

| 文件 | SHA256 |
|---|---|
| `changed-src/camera_a1_uart_top.v` | `214b21015331e5cf90c0148b7c17a26351ffbade1d012da71e4d001d9b0b8242` |
| `changed-src/a1_ddr_slot_store.v` | `86d626465dc8d0643a7bb62e952e79ee89215c2e0c02719fc348a04c4363ed84` |
| 其余 7 个 changed-src + 2 个 repo_deps | 见 `T10.b11-aplus-read/r0/CANDIDATE-MANIFEST-b11-aplus-read-r0.json`（逐项哈希） |

- b11 Routed：`SWNS=+0.015 / STNS=0 / HWNS=+0.020 / HTNS=0 / VIOL_EP=0 / TOTAL_EP=25627`。
- b11 bit `7ef0e9be93a9326c3d28de3e4b5056af053e6986fe18adfa85670d539b810aa7`、CWC `08ad62f4bb6b8c6a6eca5294578d7972515225be388dfc74705b711715d86a52`。
- b11 **未上板**：FTDI 0403:6042 不在位，下载 0/2，无 COM8；b11 状态 `diagnosis_only`。
- b11 的 WNS 关键路径是 **vendor DDR PHY 校准逻辑**（`u_ddrphy_fast_init → u_ddrphy_dcu → cal_wrlvl`），不是 v4/桥；不要把 +0.015 误解为本轮新增逻辑造成。

### 0.2 R1 有效反例（独立补充验证，已由用户确认）

`D:/fpga/ph1p100/work/b10-gap-sim-20261025-132023`（独立验证目录，**只读输入**，不修改、不覆盖）：

- `README.md`、`r1-loss/result.md`、`r1-loss/attempt1-slowcam/result.json`、`loss/trace.txt`、`check_r1.py`。
- 参数：CAM40×8、ROI(4,2)32×2、每 ROI 16 组/80 B、`FIFO_AW=2`（真实 4 项）、相机 25 MHz、A1≈187.5 MHz、`UART_DIV=4`、`STS_DIV=0`；唯一故障注入是外部 DDR AW/W ready 背压。
- 正常控制先通过：RAW 发布/编码/导出各 1，物理 UART 135 B，四 CRC + 严格 zlib 通过。
- 故障链：cycle 7380 SOF 接受、writer 启动、slot0=WRITE；cycle 7600 LAST 有 valid、FIFO full、ready=0，**LAST 被拒收**；cycle 7814 共拒收 7 组（含 1 个 LAST），crop 无 abort/几何错，释放背压；cycle 9813 FIFO/skid/DDR 已排空，writer 仍活动、nbytes=45（预期 80）、slot0 仍 WRITE、`raw_abort_cnt=0`；随后 seed1000、seed1001 两个完整好帧的 SOF 均被 FIFO 接受，但 RAW 开始被拒（最终 `begin_deny=2`）；cycle 151559 最终 cap=4，发布/编码/导出仍各 1，writer=1，slot0=WRITE，恢复包 0。
- 同一目录的连续三帧小几何用例 **PASS**（ID1/2/3、三种源、3015 B 物理 UART、四 CRC、严格解压、5 个状态包均在帧间）；本包必须保持该回归通过。

### 0.3 现有 RTL 与反例一致的机制（b11 源，行号仅供定位）

1. `camera_a1_uart_top.v` 的 clk_cam 侧（约 318–334 行）在 `fifo_wvalid && !fifo_wready` 时**只** `fifo_ovf_cnt++`，没有生成 loss-abort 请求。文件里的 `// T10.b10 R1:` 注释是**已回退尝试的历史注释**，不是已实现逻辑。
2. A1 侧 `fifo_ready` 组合逻辑（约 394–402 行）在“非 SOF、非 skip_frame、`raw_active=0`”时保持 0，**没有消费 stray beat**；一旦 SOF 被拒而后续数据先到 FIFO 头，abort beat 永远排在后面，形成 head-of-line 死锁（b10 注释声称已消费，代码没有）。
3. `a1_ddr_slot_store.v`（约 203–251 行）abort 与 write 在同一个 always 块中相互独立；`wr_abort` 没有压过同拍 `wr_last`/`wr_ready`，同拍 LAST+abort 可能仍发布坏帧；begin 与 abort 同拍也没有“释放旧槽并接收新 begin”的语义。
4. 因此 LAST 丢失后 store 永远等不到 `wr_last`，`wr_active` 与 slot0=WRITE 永久保持；后续 SOF 因 `raw_active` 被拒，形成孤儿 writer。

## 1. 本轮唯一目标

**问题**：FIFO 拒收/背压导致 LAST 丢失时，RAW writer 不 abort，槽不归还，后续好帧永久被拒。
**产物**：一个最小 R1 修复候选（保持 v4 225 B），在独立反例上恢复，P1 三黄金逐字节不变，Routed 零违例，1 bitgen + 1 CWC；板级在 FTDI 可用时按“先下载后开 COM8”采 150 s，目标 `enc_frames/exported` 增量>0 且帧解码。

## 2. 唯一正式包与工作步骤

| # | 语义步骤 | 预算 | 产物/门槛 |
|---|---|---|---|
| W1 | 复现与根因落盘（**先证明**） | ≤25 min | `r0/diag/r1-root-cause.md`：用 `work/b10-gap-sim-20261025-132023/r1-loss` 的 TB/checker 对 **b11 r0 冻结源**复现 `DUT_FAIL_VALID`（clean PASS、fault LAST 拒收、writer/slot 卡住、两好帧被拒）；记录 7 拒收/LAST/`raw_abort_cnt=0`/`begin_deny=2`；给出与 §0.3 三条机制一一对应的波形/trace 证据 |
| W2 | 最小 R1 修复 | ≤30 min | 只改 `camera_a1_uart_top.v` 与 `a1_ddr_slot_store.v`（见 §3）；不碰 reader/bridge/arbiter/crop/UART 帧格式/v4 字段；坏帧不发布、槽归还、后续好帧恢复 |
| W3 | 强制定向用例 + 回归 | ≤35 min | §4 的 T1–T10 全过；P1 三黄金逐字节同 b10/b11 基线；v4 225 B 仿真；连续三帧小几何仍 PASS；全尺寸两帧真核 129,600 字/enc=2/exported=2；b11 read 九例不回归 |
| W4 | 重建（1 bitgen + 1 CWC） | TD 内 | Routed 0 违例；WNS 按 §6 裁决；hold/period 正；ERAM+CWC ≤300；bit/CWC/BID/compiled 自洽并冻结 |
| W5 | 板级（**条件执行**） | ≤20 min | FTDI 预检：不在位 → `board=blocked`，0 下载、0 COM8；在位 → **先下载后开 COM8**，1 次 SRAM、150 s、v4 ≥120 包、`enc_frames/exported` 增量>0、≥1 帧 44 B 头+四 CRC+zlib；若仍 1176 停点，用 v4 #44–#50 判 H2/H4，**不在本包修** |

### 2.1 写域/工作树

- 工作树：**`D:/fpga/ph1p100`**（唯一主源）。
- 允许写：`workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b12-r1-last/**`（`changed-src/`、`sim/`、`td/`、`board/`、`diag/`、manifest、日志）。
- 允许改的源（先复制到 `r0/changed-src/` 再改，`a1_board.al` 只改 `<File Path>`）：
  - **仅** `camera_a1_uart_top.v`、`a1_ddr_slot_store.v`。
  - 其余 7 个 changed-src 保持 b11 r0 逐字节不变；`a1_uart_export.v`/`p2_ddr_bridge.v`/`p2_a1_board_top.v`/`a1_frame_top.v`/`a1_deflate_core.v`/`a1_raw_crop.v`/`cam_diag_mailbox.v` 不改。
- 禁止：改 reader FSM（R_AR/R_RW/R_HOLD）、`a1_ddr_arb2.v`、`p2_ddr_bridge.v`、DDR 四槽布局、44 B 帧头/CRC、crop 几何、UART_DIV/HB_DIV、引脚/SDC/时钟频率、v4 LEN/VER/字段数/225 B、`upstream/**`、旧 run/证据/manifest、`workflow/tasks.json`、`work/b10-gap-sim-20261025-132023/**`（只读）。
- 禁止 false path / multicycle / 改 seed / 降频 / 新增 ERAM 实例；禁止批量删除（只能一次 `Remove-Item <单文件>`，需批量先问用户）。
- 路径：`P:`=项目根，`W:`=`r0/sim`；TD `T:`=`r0/td`，`Y:`=项目根（`tools/td/td_env.ps1`）；`X:` 不映射项目根。

## 3. RTL 修复规格（冻结语义，允许等价实现）

### 3.1 clk_cam：任何被 FIFO 拒收的 beat 都生成 sticky loss-abort

`camera_a1_uart_top.v`，`always @(posedge clk_cam)`：

```verilog
if (fifo_wvalid && fifo_wready && fifo_wabort)
    abort_hold <= 1'b0;                 // abort beat 已被接收
else if (crop_abort)
    abort_hold <= 1'b1;                 // 既有 crop abort
else if (fifo_wvalid && !fifo_wready)
    abort_hold <= 1'b1;                 // R1: 拒收（SOF/中间/LAST 任一拍）→ 本帧 loss-abort

if (crop_valid && !fifo_wready)         // 只统计真实数据丢失，不把 abort beat 重试算进去
    fifo_ovf_cnt <= fifo_ovf_cnt + 32'd1;
```

要求：
- `abort_hold` 必须 sticky，直到 abort beat 真正被 FIFO 接收；FIFO 满时不能丢。
- 拒收发生在 SOF 上也要置位；这样后续同一帧的数据 beat 会被有序丢弃，不会污染下一帧。
- `fifo_ovf_cnt` 保留；不要删除或改名。

### 3.2 A1 侧：无主的 stray data beat 必须消费，不能卡住 FIFO 头

`camera_a1_uart_top.v`，`always @(*) fifo_ready`：

```verilog
if (fifo_valid) begin
    if (e_sof)           fifo_ready = skid_free;
    else if (skip_frame) fifo_ready = 1'b1;
    else if (e_abort)    fifo_ready = 1'b1;
    else if (raw_active) fifo_ready = skid_free;
    else                 fifo_ready = 1'b1;   // R1: 无主数据 beat 只消费、不写、不发布
end
```

要求：这个 else 只影响“SOF 被拒/丢失后残留的数据 beat”；正常帧的每个 beat 仍走 `raw_active → skid_free` 原路径。P1 三黄金逐字节一致是功能等价的硬证据。

### 3.3 Store：abort 压过同拍写；abort 与 begin 同拍时释放旧槽并接收新帧

`a1_ddr_slot_store.v`：

```verilog
wire abort_now = wr_abort && wr_active;
wire begin_now = wr_begin && wr_begin_ready;

// abort 时旧槽即将释放：只要还有另一个 FREE 槽，允许同拍 begin 新帧
assign wr_begin_ready = rst_n && ddr_ready && free_valid &&
                        (!wr_active || abort_now);
assign accept = wr_active && ddr_ready && wr_valid && !wr_abort;
assign wr_ready = accept && (!flush || ddr_wready);
// ddr_wvalid 继续由 accept && flush 派生，自然被 !wr_abort 门控
```

always 块（写侧）按以下优先级：

1. `abort_now && begin_now`：`slot_st[wr_slot] <= S_FREE`；`slot_st[free_slot] <= S_WRITE`；装载新 `wr_id/slot_seq/pub_tgl`；`wr_slot <= free_slot`；`wr_active <= 1`；`wcnt/pack_r/nbytes/waddr` 清零；`st_dropped++`、`st_abort_cnt++`。
2. `abort_now`（无 begin）：旧槽 `S_FREE`；`wr_active <= 0`；`st_dropped++`、`st_abort_cnt++`。
3. `begin_now`（无 abort）：沿用现有 begin 语义。
4. 写数据块只在 `wr_ready` 时执行；`wr_ready` 已被 `!wr_abort` 门控，因此同拍 LAST+abort 不会发布坏帧。

要求：
- 同拍 `wr_last + wr_abort`：**abort 优先**，槽 FREE，`st_published` 不变，`st_dropped/st_abort_cnt` 各 +1。
- 同拍 `wr_begin + wr_abort` 且另一槽 FREE：旧槽 FREE、新帧正常 begin；不允许把新帧误拒或留下两个 WRITE。
- 只有两个槽都占用时，新 SOF 才允许按 b9 F2 的整帧丢弃路径拒绝；槽释放后下一好帧必须恢复。
- `raw_drop`（`st_dropped`）、`raw_abort_cnt`（`st_abort_cnt`）、`raw_begin_deny`、`raw_deny_nofree`、`raw_deny_ddr` 的字段/语义保持不变；不要用“只加计数器”代替功能修复。

### 3.4 不变式

- 坏帧绝不发布：abort 后该槽不得进入 READY，也不得被 reader 选中。
- 槽不泄漏：任一 abort 后 `wr_active=0`（或同拍被新 begin 接管），被 abort 的槽最终 FREE。
- 好帧字节不变：P1 micro8x2 / mid64x8 / full_grad(1920×1080) 压缩输出逐字节同基线。
- v4 包仍 225 B / 55 字段 / VER=4；不插帧内；单边沿快照。
- 不引入新的 CDC 路径；`abort_hold`/`fifo_ovf_cnt` 留在 clk_cam，store 改动留在 clk_a1。

## 4. 强制定向用例（必须逐项取证）

| ID | 用例 | 通过判据 |
|---|---|---|
| T1 | clean 控制（独立反例 TB） | RAW 发布/编码/导出各 1；135 B 物理 UART；四 CRC + 严格 zlib；`geom=0/rejects=0/aborts=0` |
| T2 | **FIFO 拒收 7 组（含 LAST）→ 释放背压 → 两个好帧恢复** | 故障帧 seed100 不发布；故障槽 FREE；`writer_final=0`；`raw_abort_cnt>=1`；`raw_drop>=1`；解出源序列精确 `[11,1000,1001]`、帧 ID 不同；两好帧 RAW/变换/stream 四 CRC + zlib 全过；checker 退出 0 |
| T3 | 同拍 LAST+abort（store 单元） | `st_published` 不变；槽 FREE；`st_dropped+1`、`st_abort_cnt+1`；随后好帧正常发布/读回 |
| T4 | 同拍 begin+abort（store 单元） | 另一槽 FREE 时旧槽 FREE、新帧 begin 成功且可发布；无两个 WRITE、无孤儿；另一槽不 FREE 时 abort 后下一 begin 成功 |
| T5 | 中写复位 | 写一半复位；释放后 `wr_active=0`、两槽 FREE、计数清零；下一好帧发布/读回；无 X、无 ghost READY |
| T6 | 满槽并发 | slot0=READY/READING + slot1=WRITE 丢 LAST；abort 只释放 slot1；slot0 读回逐字节正确；下一好帧用 slot1；无双 free、reader 不受影响 |
| T7 | SOF 被拒的变体 | FIFO 满导致 SOF 拒收；同一帧数据 + abort beat 有序排空，不 head-of-line 死锁；下一好帧发布 |
| T8 | 既有 abort 回归（b9 `CASE=abort`） | `abort_cnt=1`、slot FREE、坏帧不发布、下一帧发布/读回 |
| T9 | 既有无 free / ddr_rdy 回归（b9 `CASE=nofree`、`CASE=rdy`） | 与 b9 基线一致：拒绝计数正确、释放后恢复、读回逐字节、`dup=0` |
| T10 | 连续三帧小几何（独立补充验证） | ID1/2/3、三种源、3015 B 物理 UART、四 CRC、严格 zlib、5 个状态包均在帧间；`frame_boundary && status_due && dq_cnt>0` 命中 5 次；本修复后仍 PASS |

允许把 T3–T7 放在 `tb_raw_store.v` 的新 `CASE=` 中，T1/T2/T10 复用独立反例 TB；T2 必须用**真实 b12 changed-src** 编译，不能改 checker 的 PASS 条件来迁就 DUT。

## 5. 回归与 v4（全部必做）

| 项 | 判据 |
|---|---|
| P1 三黄金 | `micro8x2`、`mid64x8`、`full_grad` 压缩字节 SHA256 同 b10 r0/b11 r0 冻结基线；四 CRC true；`zlib_ok`；`dup=0`；无半帧；`vlog 0/0` |
| v4 包 | 225 B、55 字段、VER=4、XOR 覆盖 0..223、单边沿快照、不插帧内；`tb_status_v4` `pass=1` |
| 集成两帧 | 真实 `a1_frame_top+a1_deflate_core`，1920×1080，两帧；`read_words=129600`、`enc=2`、`exported=2`；F_WAIT 看门狗不误触发 |
| b11 read 九例 | one/multi/bp/late/stray/dup/full/reset 全部 `pass=1`、`bad=0`；`read_full` 129600/129600；不得因本轮 store 改动回归 |
| 计数 | 正常两帧/三帧路径 `raw_abort_cnt=0`、`raw_drop=0`、`begin_deny` 符合既有背压预期；故障用例才允许非零 |

## 6. 重建与时序裁决（预裁决）

- 复制 b11 `r0/td/{01_build.tcl,02_bitgen.tcl,03_cwc.tcl,a1_board.al,p2_board.sdc,board_p2.adc}` 到 b12 `r0/td/`；`a1_board.al` **只改 `<File Path>`** 指向 b12 `r0/changed-src/**`。
- 综合 ≤3 次、布线 ≤2 次、**bitgen 1 次、CWC 1 次**；同一参数/seed 不 sweep。
- 硬门槛：Routed **0 违例端点**、hold ≥0、period 正、ERAM+CWC ≤300。
- WNS 目标 **≥+0.05 ns**；若只能到 **+0.015 ns**：
  - 先看 `routed_timing_summary.rpt` 的最差 setup 路径。若起点/终点仍在 **vendor DDR PHY**（`u_ddrphy_fast_init`/`u_ddrphy_dcu`/`cal_wrlvl`），且 0 违例，**规划预裁决：接受 +0.015 作为本轮功能/诊断候选**，在 result 中记 caveat（薄余量、非板级签核）；不为了凑 +0.05 去删 v4 观测。
  - 若最差路径落在本轮改动的 `camera_a1_uart_top`/`a1_ddr_slot_store`/v4/桥，先尝试一次**只减观测**的精简（优先 #50 `rd_wait_cycles`、#55 `fwait_cycles` 或邮箱宽度），但 **LEN/VER/字段数/225 B 不变**；精简项必须在报告中逐项列出。精简后仍 <+0.05 → 停止交规划。
  - 若 WNS **<+0.015** 或出现任何负 slack → 停止，不 bitgen、不下载。
- bit/CWC/BID 与 `cw/compiled.bit` 哈希自洽并冻结；1 bitgen + 1 CWC 后不再重建。

## 7. 板级（条件执行，不空转）

1. **FTDI 预检**（不打开 COM8）：用 `Get-PnpDevice -PresentOnly` 查 `VID_0403&PID_6042`，或 TD `READ_DEVICE`；记录 `FTDI_PRESENT=0/1` 与原始输出。
2. **不在位**（当前事实）：`board=blocked`，**0 次下载、0 次 COM8、不重试**；在 `result`/manifest 写明 `board_blocked_reason=FTDI_0403:6042_absent`。
3. **在位**：
   - 先下载（1 次 SRAM，`-mode jtag`；同一冻结 bit），确认 `B12_DL_OK`，结束 hwserver/释放 FTDI；
   - 再开 COM8，150 s，`parse_status_v4.py`；目标：v4 ≥120 个全合法、`enc_frames/exported` 增量 **>0**、≥1 帧 44 B 头 + header/stream/xform/raw 四 CRC + zlib 全过、无半帧；
   - 正常帧路径 `raw_abort_cnt/raw_drop` 不应增长（若增长，说明修复误触发，按 FAIL 处理）；
   - 若仍停在 1176 字：用 v4 #44–#50 判 H2/H4（`#37 vs #45`、`#45 vs #47/#48`、`#44[1]/[2]`、`#46`、`#49`），把判别写进 result；**本包不修 DDR/PAXI**，不把 R1 修复与读停点混为一个结论。
4. 不写 Flash、不 PCIe/RK、不做双路/G4；下载 ≤1 次，失败不第二次。

## 8. 预算、停止与回退

- 开发：**120 min / 60 calls**；TD **3 会话**、综合 ≤3、布线 ≤2、bitgen 1、CWC 1、下载 **1**、Flash 0。
- 立即停止（不建/不下载）：
  - P1 任一黄金非逐字节一致，或核心/frame 出现功能字节变化；
  - 定向 T2 在修复后仍失败，或 T3–T7 任一出现坏帧发布/槽泄漏/两 WRITE；
  - v4 破坏 225 B/55 字段/帧内边界；
  - 综合 3 次仍负；布线 2 次仍 <+0.015 或任何违例；ERAM+CWC>300；
  - 需要第二个 bitstream，或修复需要改 reader/bridge/arbiter/DDR IP；
  - 板级 1 次下载后仍无帧且读停点落在 H4（DDR IP/PAXI）→ 停止交规划。
- 回退：源以 b11 r0 为基线；失败只回退 `a1_board.al` 的本地副本路径，不改 upstream；不改旧 run/manifest。
- 用户已授权连续 SRAM 烧录的历史范围仅限本 run；本包仍只 SRAM，**不写 Flash**。

## 9. 交付物（缺一不可）

- `r0/diag/r1-root-cause.md`（机制 + 反例 trace + 修复前后对照）
- `r0/changed-src/**`（仅两个文件变化）+ `r0/rtl-diff-r0.patch`
- `r0/sim/**`（T1–T10、P1、v4、full、read 九例的脚本/日志/汇总 JSON）
- `r0/td/**`（1 bitgen + 1 CWC、Routed 报告、bit/CWC/BID/compiled.bit、params）
- `r0/board/**`（FTDI 预检；若 blocked 则只有预检日志；若下载则下载日志 + 150 s 采集 + v4 解析/帧解码）
- `CANDIDATE-MANIFEST-b12-r1-last-r0.json`、`r0/artifact-hashes.txt`
- `result-r0.md`、`lessons-r0.md`
- 若 board blocked：result 中明确 `board=blocked`、原因、未下载次数，不宣称板级通过。

## 10. 下一次准确启动/恢复文本（开发）

> 恢复 `20261020-0209_singleA_aplus_closedloop` 的 **`T10.b12-r1-last` r0**（ready；1 bitgen+1 CWC；SRAM 下载 ≤1，FTDI 不在位则 board blocked）。
> 先读 `T10.b12-r1-last/dev-plan.md`、`handoff.md`、`dispatch.json`、`T10.b11-aplus-read/r0/CANDIDATE-MANIFEST-b11-aplus-read-r0.json`、
> `work/b10-gap-sim-20261025-132023/{README.md,r1-loss/result.md,r1-loss/attempt1-slowcam/result.json,r1-loss/check_r1.py}`。
> 结论先行：R1 是有效反例——FIFO 拒收 7 组（含 LAST）后 writer/slot0 卡在 WRITE、`raw_abort_cnt=0`，两个好帧被拒。
> 只改 `camera_a1_uart_top.v`（clk_cam 拒收即 sticky loss-abort；A1 侧消费无主 stray beat）与 `a1_ddr_slot_store.v`（abort 压过同拍写；abort+begin 同拍释放旧槽并接收新帧）；
> 其他 7 个源、v4 225 B、reader/bridge/arbiter/crop/UART 帧格式全冻结。
> 先跑 T1/T2/T10 反例与三帧，再 T3–T7 定向、P1 三黄金、v4、full、read 九例；然后 1 bitgen+1 CWC（Routed 0 违例、WNS 按 §6 裁决、ERAM+CWC≤300）；
> 板级先 FTDI 预检；不在位即 `board=blocked`、0 下载；在位则先下载后开 COM8，150 s，目标 `enc_frames/exported` 增量>0 且 ≥1 帧四 CRC+zlib。
> 120 min/60 calls；TD 3 会话/综≤3/布≤2/bitgen 1/CWC 1/下载 1；失败即停，不自扩预算，不批删。
