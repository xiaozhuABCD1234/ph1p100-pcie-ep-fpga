# T10.b2-a1-uart-impl r4 -- UART 导出旁路 CDC FIFO + 空闲心跳（结果）

日期：2026-10-24。开发角色单会话。不改协议/帧/CRC/DDR 布局/SDC/A+ core。

## 1. 输入事实（用户已确认，未重复排查）

- P2 r3 bit（`d1ac8726…c142`）SRAM 下载后 **Chip validation success**；
  LED0（clk_a1 心跳）闪、LED1（exported）亮、LED3（cap_frames）亮、LED2 灭。
- 板卡自带 `02_uart_loop.bit` 下载后，COM8 115200 回环 `UARTTEST` 原样返回
  → R17/P16 ↔ FTDI 通道 B ↔ COM8 **物理通路正常**。
- 换回 A+ bit 后 COM8 收 **0 字节**。

旁证（本次核对）：

- r3 `routed_area.rpt`：`O_uart_txd OUTPUT R17 LVCMOS33 drive 8`，与厂商
  `fpga/csi2/prj/camera_ddr_display/board.adc`、`camera_peer/uisrc/04_pin/fep_vid006_imx415.adc`
  的 R17 约束**完全一致** → 引脚/电平/驱动不是可疑项。
- r3 `routed_netlist.v` 中 `O_uart_txd` 确有驱动。→ 问题在导出/发送内部。
- 复现负对照：用本次新写的采集脚本对**当前仍在运行的 r3 bit** 采 COM8 5 s →
  `bytes=0 magic=0 b55=0`（`r4/captures/negctl_before_r4/`）。
  注意：只证明"同一端口+脚本同样收 0 字节"，未目视 LED，不排除板子已被重新配置。

## 2. 假设与变更

假设：`a1_uart_export` 的 `clk` 与 `uart_clk` 在 P2 顶层都接 `clk_a1`（同一网络），
中间的 `capture_async_fifo`（64×8，异步 FIFO）纯属多余，且其读侧/复位在硬件上
是唯一无法从仿真复现的可疑环节。

改动（只 3 个文件）：

| 文件 | 变更 |
|---|---|
| `fpga/csi2/src/a1/a1_uart_export.v` | 删除 `capture_async_fifo` 实例及 `fifo_*` 信号；改为 1 字节 holding 寄存器直连 `a1_uart_tx`；新增 `HB_DIV` 参数（默认 0 = 关闭）与空闲 `0x55` 心跳；`dbg_byte*` 改为 uart 域一次性捕获 |
| `fpga/csi2/src/a1/camera_a1_uart_top.v` | 新增 `HB_DIV` 参数（默认 0）并透传给 `a1_uart_export` |
| `r4/td/src/p2_a1_board_top.v` | 实例化 `.HB_DIV(4194304)`（187.5 MHz → 22.4 ms → 约 44.7 Hz 心跳） |

握手语义（替换原 FIFO 写侧）：

```verilog
assign tx_ready = ~uart_busy;                 // TX 空闲才允许装下一字节
tx_valid_r <= 1'b0;                           // 单周期请求脉冲
// E_HDR / E_PAY 装字节条件： if (!tx_valid_r && tx_ready)
...
a1_uart_tx u_tx (.data(tx_byte_r), .valid(tx_valid_r & ~uart_busy), .busy(uart_busy), ...);
```

- 线上时序不变：`a1_uart_tx` 每字节仍是 10×`UART_DIV`=16,280 个 `clk_a1`，
  115.172 kbaud（115200 8N1 容差内）。未改 `a1_uart_tx` 模块本体。
- 帧格式/字节序/CRC 一字未改；心跳只在
  `estate==E_IDLE && dq_cnt==0 && tx_ready && !tx_valid_r` 时发，
  结构上不可能插入 44 B 帧头或 payload 中间。

哈希（before → after，before 取自 P1 r6 manifest）：

| 文件 | before | after |
|---|---|---|
| a1_uart_export.v | `1d7ea9aa0d11…df91` | `3dad065f2ff5…c15f` |
| camera_a1_uart_top.v | `17793341f717…ac88` | `b10416762bca…e6eb` |
| p2_a1_board_top.v (r4 顶层副本) | r3 版本 | `b782dd0c55fe…b1bc` |

P1 r6 manifest 其余 17 个 artifact 逐项复核 **未漂移**（core `d4b79961…`、frame
`c8b24775…`、store `8bab440d…`、arb `6513ad83…`、crop `ca2f5d16…`、
capture_async_fifo `59dd6dcb…` 等，只有上表两文件按计划变更）。

## 3. 局部检查（P1 字节级回归，sim）

环境：ModelSim Intel FPGA Edition 10.5b，`W:` = `r4/`，`P:` = 工程根，
TB 沿用冻结的 `T10.b1-a1-uart-integ/r0/sim/tb_camera_a1_uart_top.v`（未改），
`UART_DIV=1`（仿真专用快波特），`HB_DIV=0`（默认关闭，保证与 r3 可逐字节比较）。

| case | r3 字节 | r4 字节 | 逐字节一致 | r4 SHA256(.dec) |
|---|---|---|---|---|
| micro8x2 (8×2) | 63 | 63 | 是 | `fa513a2b…edef` |
| mid64x8 (64×8) | 150 | 150 | 是 | `ee61e620…9789` |
| full_grad (1920×1080) | 40,076 | 40,076 | 是 | `b992a8ad…ada9` |

`full_grad` stat：`exported=1 exp_bytes=40032 cap_bytes=40076 raw_pub=1 raw_drop=0
cmp_drop=0 geom=0 err=0 dup_words=0`（= 44 帧头 + 40,032 payload，无重/无丢）。
三例 `cycles` 略增（3748→3809、5024→5172、6,383,945→6,421,414），原因是每字节多
等 TX 一个空闲周期（仿真 uart_clk 比 clk 快），线上字节流不受影响。

汇总：`r4/p1-regression-r4.json`；日志 `r4/logs/vlog_r4.log`、`vsim_*.log`；
抓包 `r4/captures/*.dec|*.stats`。

### 3.1 心跳解码自测

把 micro8x2 + mid64x8 两帧拼上前后/中间 `0x55` 心跳字节（7/3/5 个），交给
`r4/board/resync_decode.py`：跳过 7 个前导 `0x55`，识别 2 帧，
`gap_bytes_between_frames=[7,3]`、`gap_all_beacon_0x55=true`、
`decoded_trailing=0`、四 CRC/RAW10 全部通过、`all_checks_ok=true`
（`r4/decode_selftest/`）。→ 心跳不会破坏 PC 侧解码，但**旧版 `pc_decode.py`
不能直接吃带心跳的原始字节流**（它要求流从 magic 开始），必须用
`resync_decode.py` 前置。

## 4. 综合 / 布线

TD Release_2026.2 (6.2.3.210850)，PH1P100SBG484 speed -3，`T:` = `r4/td`，`Y:` = 工程根。

- **综合**（`syn_1`）：`SWNS +0.256 / STNS 0.000 / 0 违例端点 / 15,041 端点`；
  LUT `#slice* 16,725`、`#reg 16,013`、`#eram 71`（r3 为 72，少的 1 块即被删除的 64×8 FIFO）。
  证据：`r4/syn_attempt1/`（gate.timing/gate.area/flow.status/run.log）。
- **布线第 1 次**（`build_console_r4c.log`）：`SWNS -0.274 / STNS -2.527 /
  HWNS +0.020 / 23 违例端点 / 19,659`。
- **布线第 2 次**（`build_console_r4d.log`，`reset_runs phy_1` 重跑）：与第 1 次
  **完全相同**（-0.274 / -2.527 / 23 / 19,659）→ TD 布局确定，重试无用。
  报告快照：`r4/route_attempt2/`。
- **失败路径归属**：全部是 A+ core 内部
  `u_a1/u_a1/u_core/htab_p3v_syn_23.clkb → …/bm_b_syn_29.addrb[12:…]`
  同一类路径（10 条里 9 条同一 end point 组），**不是 UART/导出路径**；
  与 r2/r3 记录的 187.5 MHz 薄余量区同源（r3 最终仅 +0.012）。
- 布线第 3 次（提高后优化强度 `postrt_opt_loc 40 / extra_round 12`）：
  见 §4.1。

### 4.1 第 3 次布线结果

`01e_route_hi.tcl`（`post_route_opt ultra`，`postrt_opt_loc 40`，`postrt_opt_extra_round 12`，
即把 TD QoR 建议的后优化强度再加两档）：`build_console_r4e.log` →
**仍为 `SWNS -0.274 / STNS -2.527 / HWNS +0.020 / 23 违例端点 / 19,659`**，与前两次逐位相同。

结论：TD 在本工程的布局布线是**确定性**的，换重试次数、加后优化强度、`reset_runs`
都不会改变结果（QoR 报告本身也标注 `post_route_opt ultra(*)`/`extra_round 4(*)`
"already been set"；唯一剩下的是 `QOR-2605 multi-seed`，而 seed 属边界外）。

Routed 细目（`r4/route_attempt2/` 与 `r4/td/routed_*.rpt` 一致）：

| 项 | 值 |
|---|---|
| Setup（slow） | WNS **-0.274 ns** / TNS -2.173 ns / **23** 违例端点 / 19,659 |
| Setup（min/fast corner，报告 Period Check 段） | WNS -0.173 ns / TNS -0.354 ns / 6 违例端点 / 12,689 |
| Hold | WNS **+0.020 ns** / TNS 0 / 0 违例端点 |
| Period Check WNS | +2.200 ns（PLL 输出，正常） |
| 组合环 | 0 |
| 无时钟网络 | 0 |
| LUT6 / reg / ERAM / DSP / IO | 18,592 / 25,094 / **101**/300（设计 71 + CWC 30）/ 0 / 110 |
| #slices | 22,461（31.34%） |
| STA coverage | 96.88%（Routed） |

23 个违例端点全部落在 **A+ core 同一路径组**：
`u_a1/u_a1/u_core/htab_p3v_syn_23.clkb → u_a1/u_a1/u_core/bm_b_syn_29.addrb[12:0]`
（10 条代表路径里 9 条是同一 end point 组的不同 bit），与 UART/导出/心跳路径无关。
根因与 r2/r3 §54/§55 记录的 187.5 MHz 薄余量区同源：这是 A+ core 的 Huffman 表 →
BitMatch 存储器地址路径，不是本次改动引入的。

## 5. bit / CWC

**未生成，且按规则不能生成。**

`02_bitgen.tcl` 是 fail-closed 的：`sw<0 || hw<0 || pw<0 || st!=0 || ht!=0` 任一成立
即 `error "STA rejects bit generation"`。本次 `sw=-0.274`、`st=-2.527`（23 个违例端点），
会被直接拒绝；`03_cwc.tcl` 又依赖 bitgen 产物与 byte-identical 的 compiled.bit，
所以 CWC 也无从生成。

按 `dev-plan §54.2/§55.2` 的既定裁决（"2 次 route 仍负/违例 → 停止并提交 top paths +
根因，选项 (a)(b)(c)，不接薄负 slack"），本次在**第 3 次**布线仍负后停止：
不 bitgen、不 CWC、不下载、不写 Flash。因此本轮**没有** bit/CWC/BID 哈希。

候选对比（供裁决）：

| | r3（已下载过，COM8 0 字节） | r4（本轮） |
|---|---|---|
| 综合 SWNS | -0.193 → 多次后 +0.280 | **+0.256** |
| 布线 SWNS | **+0.012**（0/19,754） | **-0.274**（23/19,659） |
| Hold | +0.020 | +0.020 |
| ERAM | 102（72+30） | 101（71+30） |
| UART 路径 | 经 64×8 异步 FIFO | 直连 1 字节 holding |
| P1 字节流 | 基准 | 与 r3 逐字节相同（仿真） |

即：**UART 修复本身已通过全部可离线验证的检查，但"带 UART 修复的这份 netlist"
在 187.5 MHz 下比 r3 少 0.29 ns 余量**——差异全部落在 A+ core 的同一薄余量路径组，
属于 r3 自己也只靠 +0.012 才勉强通过的同一处。

## 6. 板测（SRAM 单次下载 + COM8 120 s）

**未执行**（无合规 bit 可下载）。

已做且有效的板级/脚本准备：

- 复现负对照：新写的 `r4/board/capture_com8.py` 对**当前板上的 r3 bit** 采 5 s →
  `bytes=0 magic=0 b55=0`（`r4/captures/negctl_before_r4/com8_5s.{bin,dec,stats}`），
  与用户报告的"0 字节"一致，说明端口/波特率/脚本本身没问题。
- 下载脚本 `r4/board/download_sram_r4.tcl`（`-mode jtag` = SRAM，脚本内**没有**
  `program_spi`/Flash 路径），只等一个合规 bit。
- 解码链 `r4/board/resync_decode.py` 已用合成心跳流自测通过（§3.1）。
- 运行手册 `r4/board/README-r4-board.md`（含 hwserver 前置、T: 盘符告警、判定矩阵）。

## 7. 边界与未测

- 未改：A+ core `bf6af390`/`d4b79961`、frame `c8b24775`、SDC `227dd39e`、
  帧格式/CRC/字节序、DDR 布局；未 false path / multicycle / 改时钟 / 改 seed。
- 未写 Flash/eflash；未接 PCIe/RK；未做双路/G4。
- 仿真只能证明"字节流不变"，**不能**证明板上 FIFO 读侧卡死这一硬件现象；
  硬件结论只能来自 §6 的 COM8 抓包。
- `resync_decode.py` 是 r4 新增的 PC 侧前置（因为有心跳）；它不放松任何 CRC 检查，
  但它是**新代码**，P3/P4 复测时应把它本身当作待验对象。
- 心跳是**新增行为**（协议外字节）：若后续要求"串口上只有帧"，需把
  `HB_DIV` 设回 0 重新出 bit。

## 8. 复测清单

- `required_dimensions`: integrated / functional / engineering / system
- `required_checks`:
  1. 复核上表 3 个哈希与 `CANDIDATE-MANIFEST-b2-a1-uart-impl-r4.json`；
     P1 r6 其余 artifact 无漂移。
  2. 重跑 micro8x2 / mid64x8 / full_grad 三例（`HB_DIV=0`），要求与 r3 抓包
     逐字节一致（SHA256 见 §3）。
  3. 工程：综合/布线 SWNS/HWNS/违例端点/资源，与 §4 对照；确认失败端点仍在
     A+ core `htab→bm_b` 组、不在 UART。
  4. bit/CWC/BID 哈希与 compiled.bit 一致性（若已生成）。
  5. 系统：SRAM 单次下载 + COM8 115200 120 s 采集，按
     `r4/board/README-r4-board.md` 的解释矩阵判定。
- `input_status`: changed（`a1_uart_export.v`、`camera_a1_uart_top.v`、r4 顶层副本）

## 9. 交给原规划的裁决选项（本轮不自行选择）

事实：**UART 修复的所有离线证据都通过**（P1 三例逐字节一致、心跳解码自测通过、
综合 +0.256、hold 正、资源不涨），但**带这个修复的 netlist 在 187.5 MHz 下
比 r3 少 0.286 ns 余量**，三次布线完全一致地停在 `-0.274 / 23 端点`，且
23 个端点**全部在 A+ core `htab_p3v → bm_b.addrb`**，与 UART 无关。
`02_bitgen.tcl` fail-closed 会拒绝，所以本轮无法下载、无法回答"板上到底通没通"。

- **(A) 有界 RTL 流水轮（需解除 core 边界）**：只针对
  `u_core/htab_p3v → bm_b.addrb` 加一级地址流水/寄存（不改协议/帧/CRC/DDR 布局），
  再走一次 P1 回归 + 综合/布线。预计 60–90 min（综合 4 min + 布线 17 min/次）。
  这是唯一能同时拿到"合规 bit + UART 硬件答案"的路径。
- **(B) 用户明确授权"诊断性下载"**：用当前 `-0.274` 的 DB 生成 bit 并下载一次 SRAM。
  风险与价值要说清：心跳 `0x55` 与 44 B 帧头**不依赖** A+ core，所以即使
  core 因 setup 违例出错，也足够回答"TX 到底有没有在工作"；
  但 payload/CRC 可能失败，**不能**当作 P2/P3 的功能签核证据。
  （需要用户/规划显式授权绕过 `02_bitgen.tcl` 的 fail-closed 判定。）
- **(C) 改验收口径/时钟**：例如把 `clk_a1` 降到 150 MHz 之类。注意这会同时改变
  UART 波特率（`UART_DIV=1628` → 80 kbaud），必须同步改 `UART_DIV` 与 SDC，
  已超出本轮边界。
- **(D) 回退到 r3 bit 继续 P3**：但 r3 bit 就是"COM8 0 字节"的那一版，无意义。

## 10. 事故记录（不影响上述判定，但必须留痕）

- 17:42 期间 `T:` 曾被别的会话改指到 `T10.a1-eng-freeze/r10/td`，导致我第一次
  `01b_route_only.tcl` 跑错目录（日志写进 r10，见 `lessons-r4.md` 第 6 条）。
- 重新绑定 `T:` 后再启动的那份 `01b` **后台作业没有退出**：它在 17:59:57 设置完
  `.stop.f` 后卡在 `wait_run phy_1 -quiet`，而随后 `01c`/`01e` 又反复
  `reset_runs phy_1`，于是它一直等到 2026-10-25 才被终止（`EXIT=-1`）。
- 影响核查：该作业**从未进入 `import_db`/`report_*` 阶段**，
  所以 `r4/td/routed_*.rpt`、`routed_timing_summary.rpt` 等全部仍是 18:45:33–18:45:43
  （`01e`）的版本，内容仍为 `SWNS -0.274 / 23 违例端点`；`build_console_r4b.log`
  停在 17:59:57。→ 本报告的数值不受影响。
- 另注：本次收尾时 `T:`/`W:` 已被后续任务（`T10.b5-a1-htab-pipe`、`T10.b9-rawstore` 等）
  重新绑定，`r4` 不再持有任何盘符映射，也没有残留 TD 进程；后续如要复现 r4，
  必须先 `tools/td/td_env.ps1 -TdDir <r4>\td -Force`。
