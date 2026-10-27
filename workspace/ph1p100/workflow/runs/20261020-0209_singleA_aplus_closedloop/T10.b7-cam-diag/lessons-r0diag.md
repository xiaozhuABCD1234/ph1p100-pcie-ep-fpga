# T10.b7-cam-diag r0-diag — lessons（只记可复用的根因/触发/修正/验证入口）

## 1. `p2_board.sdc` 的时钟组把 sys50 和 clk_a1 放在同一组 → 新增 sys→clk_a1 跨域会打爆 hold

- 触发：按指南 §5 加 `cam_diag_mailbox #(.W(64)) u_dbg_sys_mail`，`clk_slow=sys_clk50m`、`clk_fast=clk_a1`。
- 现象：布线 `HWNS=-7.189 ns / HTNS=-291.151 / 42 个 hold 违例端点`，违例起点全部是 `u_dbg_sys_mail/r_hold[*]`，终点 `o_data[*]`。
- 根因：`p2_board.sdc` 的 `set_clock_groups -asynchronous` 把 `sys_clk50m pclkx1 pclkx5 mclk27 clk_a1` 放进**同一个** group，
  而 187.5/50 = 3.75 非整数，TD 按同步关系做 hold 检查，50 MHz 树与 187.5 MHz 树的插入延迟差直接吃掉 hold 预算。
  b6 之前没有真正的 sys50→clk_a1 寄存器路径（`ddr_rdy_sync_a1` 采的是 DDR PHY 输出），所以历史候选 0 违例。
- 修正（SDC 冻结前提下）：sys50 → **dhi_clk**（=`ddr_user`，独立时钟组）→ clk_a1 两级邮箱；两级都满足“数据稳定 ≥37 µs + 单比特翻转 + 2FF”，
  第一级 DIV_BITS=12（82 µs），第二级 DIV_BITS=4（80 ns），clk_a1 侧再留 4 拍稳定窗。
- 验证入口：`build_console_r0diag_route2.log` 的 `P2_ROUTED_HWNS=0.020 / P2_ROUTED_HTNS=0.000 / VIOL_EP=0`；
  `route1_*` 保留违例现场。以后任何“50 MHz 域状态 → 187.5 MHz 域”的需求都不要再直连。

## 2. ModelSim：`integer` 未初始化 → `while (i < N)` 直接为假

- 触发：`integer i;` 后写 `while ((npkt < n) && (i < 200000))`。
- 现象：TB 只跑了 430 个周期就 `$finish`，`bytes=0`，像“设计没发包”。
- 修正：`integer i = 0;`（`for (i = 0; ...)` 不受影响，因为先赋值）。
- 验证入口：`sim/tb_status_pkt_v2.v` 的 `TB_STATUS bytes=582 packets=6`。

## 3. 跨域邮箱必须用异步复位

- 触发：`always @(posedge clk_slow) if (!rst_slow_n)`（同步复位）。
- 现象：慢时钟在复位释放后才启动时，`r_cnt` 永远停在 X，仿真里邮箱永不发布（真实硅上电为 0，仿真会骗人）。
- 修正：双侧改 `always @(posedge clk or negedge rst_n)`；慢时钟停死时输出保持 0/最后值，仿真与硅一致。
- 验证入口：`sim/tb_cam_dead.v` 的 `MB_STOPPED=2222 / MB_FINAL=2222`。

## 4. 指南 §4/§5 的“8 字邮箱”与其自身字段表不一致

- §4 列的 clk_cam 域字段实际是 11 个字（6 计数 + 4 个 crop 计数 + `cam_phystat`）。
- 处理：邮箱按 11×u32 = 352 bit 实现，包内 15×u32 字段顺序严格按 §7 不变；已在 result §1 说明。

## 5. 板级：单次下载后 0 字节，先分清“只丢状态包”还是“整条链没动”

- 触发：唯一 1 次 SRAM 下载成功（PRG-2014）后，COM8 115200 两次 60 s 监听均为 0 字节。
- 判据收益：b6 候选的 `HB_DIV=4194304` 心跳本该每 ~22 ms 出一个 `0x55`（60 s ≈ 2600 B）。
  **0 B 说明不是“v2 包被丢”，而是 FPGA 侧一个字节都没发**（`a1_rst_n` 未释放 / 时钟没跑 / 比特未真正生效 / 板未上电），
  这条推理把问题从“包格式”直接排除掉，下次板窗应优先量 `sys_rst_n`、`lock_a1`、`ddrphy_rdy`、UART TX 空閒电平。
- 纪律：按 dev-plan §5 未做第二次下载；恢复入口 = 新板窗 + 重新授权 1 次下载（bit/CWC 已冻结，可直接复用）。

## 6. 预算

- 实际：开发会话 23:44–00:45 约 61 min 墙钟（含两次完整综合+布线、P1 full_grad 5.2 min、两次 60 s 采集），工具调用约 56 次（超 50）；
  布线 2 次（计划 1 次），综合 2 次（计划 ≤2，未超）。
- 教训：跨时钟组的结构性改动应在**第一次布线前**用 SDC 时钟组逐对核对（本次是布线后才发现），可省一整轮 13 min 重建。
