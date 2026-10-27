# T10.b13-ddr-retry — 用户摘要（规划冻结，2026-10-25）

- **板级事实**：b12 r1 实跑 4,470 帧都正常，但读通路在 `raw_rd_idx=882/129,600` 停住：
  store AR=883、PAXI AR=883、PAXI R=882、stale=0、`ar_pending=1`、`ddr_rdy=1`、`rd_wait` 饱和；
  `slot0=READING`、`slot1=READY`。判定 **H4：DDR 接受 AR 后不回 R**，不是 A1 读 RTL 丢响应。
  停点此前 1176、本次 882，不固定 → 更像 DDR 刷新/读写仲裁的偶发丢响应。
- **本轮选择 A（你已定）**：**DDR 读超时 + 重试**。新包 `T10.b13-ddr-retry`（父 T10 仍 blocked）。
- **冻结语义**：
  1. AR 被接受后连续 **8192 clk_a1** 等不到 R → 超时；abort 当前帧读，**槽保持 READING**（不发布、不覆盖 READY 槽）；
  2. 清读 FSM + bridge 读路径：清 `ar_pending`、排空 AF、丢弃 RF/skid；**保护窗口 32768 clk_a1 内不发新 AR**；
     晚到 R 在 `ar_pending=0` 时被吞掉并计 stale，不会进入 RF，也不会被当成新事务；
  3. 之后**重试同一帧**（从第 0 字重读），最多 **2 次**；仍失败则释放槽、计数 `giveup`，不导出半帧；
  4. 超时重试期间 A+ 核和压缩槽被 abort，只有 `a1_commit` 才推描述符，因此**不会发布/导出半帧**；
  5. 状态包升级 **v5：241 B / 59 字段**，新增 `#56 timeout / #57 retry / #58 giveup / #59 stale`；#1–#55 原顺序不变。
- **改动范围**：只改 `a1_ddr_slot_store.v`（超时/重试 FSM）、`a1_ddr_arb2.v`（raw 读 abort 清 `rd_busy`）、
  `p2_ddr_bridge.v`（purge/guard/晚到 R）、`camera_a1_uart_top.v`（超时序列 + v5 总线）、
  `p2_a1_board_top.v`（连线/观测宽度）、`a1_uart_export.v`（v5 包）；其余源/帧格式/SDC/时钟/DDR IP 全冻结。
- **仿真验收**：DDR 模型丢 1 个 R → 超时 → 重试 → 整帧导出（四 CRC+zlib）；晚到 R 不污染；连续 3 帧仅中间帧重试；
  重试预算耗尽不死锁、下一好帧恢复；帧中部超时；P1 三黄金逐字节；b12 R1 用例全回归；b11 read 九例；full 两帧；
  full 丢 1 R；v5 结构 241 B。
- **构建**：综合≤3、布线≤2、1 bitgen + 1 CWC；Routed **0 违例**；WNS 目标 **≥+0.05**；若 0 违例且只有 **+0.003…+0.05**，
  按 b12 口径接受为**诊断候选**并记 `timing_caveat`；**<+0.003 或任何违例即停**。
- **板级**：先 FTDI 预检；在位 → **先下载 1 次 SRAM**，成功后再开 COM8 150 s；v5 ≥120 包，`enc_frames/exported` 增量>0，
  ≥1 帧 44 B 头 + 四 CRC + zlib，无半帧；记录 timeout/retry/giveup/stale。
  若仍**每帧在同一 `rd_idx` 失败且 exported=0** → **停止，转 B（DDR IP 调查）**，不做第二次下载/第二个 bitstream。
- **预算**：开发 120 min/60 calls；TD 3 会话、综合≤3、布线≤2、bitgen 1、CWC 1、下载 1、Flash 0。
- **不需要额外用户输入**；板级若 FTDI 不在位，`board=blocked` 是本包合法完成，不宣称硬件通过。
- **入口**：`T10.b13-ddr-retry/{dev-plan.md,fpga-design-guide.md,dispatch.json,handoff.md}`；
  证据 `T10.b12-r1-last/r1/board/captures2/status_v4.txt`；基线 `T10.b12-r1-last/r0/**`。
