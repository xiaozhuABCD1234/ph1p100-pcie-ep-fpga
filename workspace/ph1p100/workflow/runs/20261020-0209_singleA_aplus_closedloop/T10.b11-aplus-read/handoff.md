# T10.b11-aplus-read — handoff（规划 → 开发 / 综合测试）

- 日期：2026-10-25；run：`20261020-0209_singleA_aplus_closedloop`；项目根：`D:/fpga/ph1p100`
- 状态：**ready**；`needs_user_input=false`；批大小 1；父 T10 **保持 blocked**
- 唯一冻结输入：`T10.b10-b9-fix/r0` 候选（源 8/8 哈希见 `artifact-hashes-r1.txt`，bit `ba5fb801…9e72`，Routed SWNS +0.103）
- 本轮唯一目标：消除“第 1177 个 AR 之后丢 1 个 DDR 读响应”的永久等待，使 `enc_frames/exported` 增量 >0，并同时产出 v4 状态包

## 1. 必须按顺序读

1. `T10.b11-aplus-read/dev-plan.md`（冻结计划：诊断链、H1–H4、v4 格式、门槛、预算）
2. `T10.b11-aplus-read/dispatch.json`
3. `T10.b10-b9-fix/r0/board/captures_final/status_v3.json`（最新板级，**不是** `captures_r1` 那次相机死的抓包）
4. `T10.b10-b9-fix/result-r1.md`、`T10.b10-b9-fix/r0/changed-src/*`
5. `T10.b10-b9-fix/r0/sim/{tb_b10_multi.v,p2_paxi_model.v,a1_ddr_model.v,sim-results-b10.json}`
6. `T10.b10-b9-fix/r0/td/{01_build.tcl,02_bitgen.tcl,03_cwc.tcl,a1_board.al,src/}`
7. `T10.b10-b9-fix/r0/board/{parse_status_v3.py,capture_com8.py,download_sram_b10.tcl}`

## 2. 规划已确认的结论（不要重复推翻）

- `a1_busy=1` 是 `frame_active`，不是核内死锁；`a1_in_ready=1` 说明核愿意收数据。
- `a1_in_valid=0` 因为 feeder `fstate=F_WAIT` 等不到 `raw_rd_valid`；`rd_state=R_RW`、`rd_armed=1`、`raw_rd_idx/read_words=1176`。
- AR 握手 1177 次、R 只回 1176 次；b9 与 b10 都是 1176 字 → **确定性丢 1 拍**。
- store 的 `ddr_arready` 只代表地址 FIFO 收下，**不代表 DDR 真的收了 AR**；必须用 v4 的 `af/ar_pending/paxi AR/R/rlast` 计数区分 H1/H2/H3/H4。
- reader FSM 语义自洽，不是首要嫌疑；未证明前不改 R_AR/R_RW/R_HOLD。

## 3. 执行顺序（严格）

1. **W1 诊断（≤50 min）**：真实 `a1_frame_top+a1_deflate_core` 全尺寸两帧 + 两个 slot store + arb2 + `p2_ddr_bridge` + `p2_paxi_model`；
   加压（R 延迟、rready 背压、rlast 语义、读写交错），复现 1176 字停点；写 `r0/diag/read-stall-analysis.md`，落 H1–H4 判别。
2. **W2 修复（≤30 min）**：只改被证明的一点；同时加 feeder 有界看门狗（F_WAIT 无 `raw_rd_valid` 超 N 拍 → 干净 abort + 释放 raw/cmp 槽 + 回 F_IDLE）。
   好帧压缩字节不得变化。
3. **W3 回归（≤30 min）**：P1 三黄金逐字节同基线 + v4 包仿真 + 集成两帧全尺寸。
4. **W4 构建**：`T:`=`r0/td`、`Y:`=项目根；1 bitgen + 1 CWC；Routed 0 违例、WNS≥+0.05、ERAM+CWC≤300。
5. **W5 板级**：**先下载、后开 COM8**（顺序反了作废）；同一 bit ≤2 次；150 s；parse v4；目标增量>0 + 44 B 头/CRC/zlib。

## 4. 硬约束

- 只写 `run/T10.b11-aplus-read/**`；源先复制到 `r0/changed-src/`，`a1_board.al` 只改 `<File Path>`。
- 观测端口允许：core 加 `dbg_state`、frame 加 `dbg`，**只加输出/连线**；新哈希入 manifest，三黄金逐字节一致证明功能等价。
- 不改：crop 几何、四槽 DDR 布局、44 B 帧头/CRC、UART_DIV/HB_DIV、引脚/SDC/时钟；不 false path/multicycle/改 seed/降频/加 ERAM。
- 不写 Flash、不 PCIe/RK、不做双路/G4；不批量删除（只能一次删一个明确路径，需批量先问用户）。
- 预算：150 min / 70 calls；TD 3 会话、综≤3、布≤2、bitgen 1、CWC 1、下载 2（同一 bit）。

## 5. 条件分支

- 50 min 内无法解释 1176 字：**不做猜测性功能修复**；允许 v4 + 看门狗的**诊断构建**，三黄金仍须逐字节一致；报告写 `diagnosis_only`，不宣称目标达成。
- 需要第二个 bitstream：停止交规划。
- 根因落在 DDR IP/PAXI（H4）：停止并交规划，不做假修复。

## 6. 恢复文本

> 恢复 `20261020-0209_singleA_aplus_closedloop` 的 `T10.b11-aplus-read` r0（ready）。
> 读 `T10.b11-aplus-read/{dev-plan.md,dispatch.json}`、`T10.b10-b9-fix/r0/board/captures_final/status_v3.json`、`T10.b10-b9-fix/result-r1.md`。
> 先 W1 真核全尺寸复现 1176 字停点并落 H1–H4，再只改证明的一点 + 有界看门狗；P1 三黄金逐字节；v4 包 225 B；1 bitgen+1 CWC；先下载后 COM8，150 s，目标 `enc_frames/exported` 增量>0。
