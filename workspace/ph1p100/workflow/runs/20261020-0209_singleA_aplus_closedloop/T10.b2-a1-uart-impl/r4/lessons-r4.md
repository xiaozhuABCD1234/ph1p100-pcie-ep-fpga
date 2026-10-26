# lessons -- T10.b2-a1-uart-impl r4 (UART export: FIFO bypass + idle beacon)

只记可复用的根因/触发/修正/验证入口。

## 1. 同源时钟下不要保留 CDC FIFO（本次根因候选）
- 触发：`a1_uart_export` 的 `clk` 与 `uart_clk` 在 P2 顶层都接 `clk_a1`，中间仍是
  `capture_async_fifo`；板级表现是导出计数在涨（LED1 亮）但 COM 端 0 字节。
- 修正：删除该 FIFO，改 1 字节 holding 寄存器 + 真实 ready/valid
  （`valid = tx_valid_r & ~uart_busy`，只在 `~uart_busy` 时允许装下一字节）。
- 验证入口：P1 三例仿真抓包与 r3 **逐字节相同** → 说明改动对线上字节流透明，
  差异只在“谁来背压”。sim 里 `cap_bytes/exp_bytes` 完全对齐（63/150/40076）。

## 2. 旁路后 `dbg_byte_valid` 必须 one-shot
- 触发：`dbg_byte_valid = tx_valid_r & ~uart_busy` 在 `uart_clk` 比 `clk` 快的仿真里
  会在一个 a1 周期内被采样多次 → `.dec` 重复字节。
- 修正：在 uart 域加 `dbg_hold`，每字节只捕获一次（真实板级 clk==uart_clk 时等价）。
- 入口：`tb_camera_a1_uart_top` 的 `$fwrite(fd,"%0d",dbg_byte)`，看 capture 行数。

## 3. 心跳必须门控在真正空闲
- 只在 `estate==E_IDLE && dq_cnt==0 && tx_ready && !tx_valid_r` 时装 `0x55`，
  所以永远不会插进 44B 帧头或 payload；PC 侧只需在帧间跳过 `0x55`。
- 解码入口：`resync_decode.py`（扫 magic + 校验 header_crc + 断言帧间全 0x55），
  再调冻结的 `tools/a1/pc_decode.py`，不放松任何 CRC。

## 4. TD `wait_run` 报 failed 不等于综合失败
- 触发：`PRJ-5303 WARNING: Run syn_1 failed` / `PRJ-8806 ... exited unexpectedly`，
  但 `a1_board_Runs/syn_1/a1_board_gate.timing` 已完整（SWNS +0.256, 0 viol，
  `flow.status` 正常）。r3 也遇过一次（`build_console_r3d.log`）。
- 处理：以 `syn_1/a1_board_gate.timing` + `flow.status` 为准；不要在 `wait_run`
  失败后重综合（会丢正 slack 结果），用 route-only 脚本续跑。

## 5. `open_project` 后必须 `import_device`
- 触发：只用 `open_project ./a1_board.al` 再 `launch_runs phy_1`，生成的
  `phy_1/settings.cfg` 里 `set device_name ` / `set package_name ` 为空，
  run 立刻失败：`PRJ-8001 ERROR: source ./settings.cfg failed: can't read "device_name"`。
- 修正：`import_device ph1_100p.db -package PH1P100SBG484 -speed 3` 后再
  `reset_runs phy_1` + `launch_runs phy_1`。`create_project` 路径没有这个问题。

## 6. `T:` 会被别的会话改掉
- 触发：r4 构建途中 `T:` 从 `r4/td` 被改成 `T10.a1-eng-freeze/r10/td`（17:42），
  下一次 TD 命令就把日志写进了 r10 目录，`./01b_route_only.tcl` 找不到。
- `.al` 里存的是 `Path="T:/"`，所以 T: 必须是**当前 run 的 td 目录**。
- 入口：任何 TD 命令前 `cmd /c subst | findstr ^T:`，或用
  `tools/td/td_env.ps1 -TdDir <run>\td -Force` 重新绑定；日志落到哪个目录就是
  T: 指错的直接证据。

## 7. TD 的布局布线在本工程是确定性的 —— 重试/加档无效
- 触发：同一综合 DB 连续三次布线（默认参数、`reset_runs phy_1` 重跑、
  `postrt_opt_loc 40` + `postrt_opt_extra_round 12`），结果**逐位相同**：
  `SWNS -0.274 / STNS -2.527 / 23 违例端点 / 19,659`。
  QoR 报告也标注建议参数 `post_route_opt ultra(*)`/`extra_round 4(*)`
  "already been set"，只剩 multi-seed（本工程边界禁止）。
- 结论：**布线负数时不要用重试或加后优化档数来"碰运气"**，直接换 RTL/流水或升级裁决。
  （r3 时期看起来"重试有效"，其实是两次之间改了 RTL——`sys_rst_n` 异步复位修 hold。）

## 8. 187.5 MHz 的薄余量在 A+ core，任何 RTL 改动都可能把它顶翻
- 事实：r3 综合 +0.280 → 布线 +0.012（0/19,754）；r4 只改 UART 导出
  （删 64×8 FIFO、加 1 字节 holding、加心跳计数器），综合 +0.256 → 布线 **-0.274**（23/19,659）。
  失败端点全部是 `u_core/htab_p3v → bm_b.addrb`，与 UART 无关。
- 含义：这份设计在 187.5 MHz 的余量本来就 <0.3 ns，**改动任何模块都会改变 retiming /
  布局结果**。要稳定出合规 bit，必须在 core 那条路径上加一级流水（需解除 core 边界），
  而不是反复重建。
