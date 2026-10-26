# cdc-static — T10.a1-adler-smem r0-route（2026-10-22）

**结论：静态单时钟证据成立（供测试者复核）；但时序 G2 仍 FAIL（SWNS −0.541 / 299 端点）。**
不声称 `report_cdc`（TD 2026.2 无此命令，已按原文 `invalid command name "report_cdc"` 留证）。

## 1. 单时钟

`routed_clock_utilization.rpt`（工具 `-file`，routed DB）：

- 仅 1 个全局时钟网：`clk`（`gclk_0`，Global Type `PH1P_PHY_GCLK`，Clock Period **5.333 ns**，Clock Loads **1260**，Total Loads 1260）；
- `PH1P_PHY_IOCLK/LCLK/MLCLK` 使用 0；`PH1P_PHY_SCLK` 4（同一 `clk` 的时钟树/leaf 复用，不是独立时钟源）；
- 时钟源：`clk_dup_1_created_gclkinst.clkout`（PAD 输入 `clk`），无 PLL/MMCM 生成时钟、无门控派生时钟。

`routed_timing_summary.rpt`：Clock Summary 只有 `clk0`，`CC-From = no`、`CC-To = no`（无跨时钟域路径）。

## 2. check_timing（routed DB，`-file`）

`routed_check_timing.rpt` 表头计数：

| 检查 | 计数 | 说明 |
|---|---|---|
| no clock | 0 | 无未约束时钟 |
| clock definition | 0 | — |
| invalid constraint | 0 | — |
| combinational loops | 0 | 无组合环 |
| soft fifo timing exception | 0 | — |
| no input delay / no output delay | 47 / 73（MEDIUM） | 顶层 I/O 的既有约束缺口（历史 SDC 未设 I/O delay），**与本设计 DUT 内部单时钟 CDC 无关**；未在本包修改 SDC |

## 3. 约束与例外

- 约束文件：`a1_small_top.sdc`（`227dd39e…6311`，锁定未改），单时钟 `clk`。
- `report_exceptions` 在 TD 2026.2 不存在（`invalid command name`），未作 signoff；manifest 记录了该尝试。

## 4. 边界

- 以上全部来自**本次 routed DB**（`a1_adler_smem_pr.db`，`16bbf6b9…`）；不是综合前推断。
- 该证据只证明“单时钟 + 无组合环 + 无未约束时钟”，**不**证明时序收敛；本次 Routed setup 仍 −0.541，最终 G2 判定为 FAIL。
