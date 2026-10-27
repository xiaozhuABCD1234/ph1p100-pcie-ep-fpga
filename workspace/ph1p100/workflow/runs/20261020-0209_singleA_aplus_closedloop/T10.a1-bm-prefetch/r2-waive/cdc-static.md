# T10.a1-bm-prefetch r2-waive — 静态单时钟 CDC 证据（非 report_cdc 签核）

对象：routed DB `a1_bp_r2_pr.db`（SHA256 前缀 `CA76F31CF039D7C0`，4,321,948 B），
候选 core `df6124d4…14a9c`、frame `18d51b1b…1cbe`、SDC `227dd39e…6311`。
本轮所有命令均在**已布线 DB** 上直接执行（`import_db` → `update_timing -mode final` → 各 `report_* -file`）。

## 1. 单时钟证据

| 证据 | 原始件 | 结论 |
|---|---|---|
| 全局时钟表 | `routed_clock_utilization.rpt`（17,819 B，`A7EDF4E8492EE213`） | `PH1P_PHY_GCLK 1/32`、`IOCLK 0/24`、`LCLK 0/24`、`MLCLK 0/24`；唯一全局时钟 `gclk_0 / src_0 / PH1P_PHY_GCLK`，`clk`、`5.333 ns`、`Net clk_syn_7`、Total Loads **1245**；`SCLK 4/96` 为同一时钟的网络脊，不是额外域 |
| 时序组 | `routed_timing_summary.rpt`（142,283 B，`B18C7771236E05D2`） | 唯一 `Path Group: clk -> clk`；`Confidence: Routed`、`Check Corner: Both (Slow and Fast)`、`CRPR Enabled: Yes`；表中 `CC-From`/`CC-To` 无跨域路径记录 |
| 时序检查 | `routed_check_timing.rpt`（4,865 B，`21FA3E56BA3DE6AB`） | `0 leaf clock pins driven by multiple clocks`、`0 clocks created on internal clock network`、`0 unexpandable clock sets`、`0 local clocks`、`0 generated clocks not connected to master`、`0 invalid constraints`、`0 combinational loops`；`1 dangling node`（HIGH，dummy，非路径）；`47 no input delay / 73 no output delay`（MEDIUM） |
| 跨域 FIFO 例外 | `routed_check_timing.rpt` 第 7 项 | `0` 条 soft FIFO timing exception |

## 2. 结论与边界

- 静态单时钟结论**成立**：单一时钟 `clk`（5.333 ns / 187.5 MHz），无跨域、无生成时钟、无多时钟引脚；`clk -> clk` 单组。
- **边界（必须原样保留）**：TD Release_2026.2 **没有 `report_cdc`**（本轮 `report_cdc -file` 记录为 unavailable；无 `cdc.rpt`）；`report_clocks`/`report_exceptions` 同样不存在。本文件是**静态单时钟证据**，不是工具 CDC 签核，`check_timing` 也不能当 CDC 报告使用。
- 覆盖边界：47/73 个 I/O 端口无 input/output delay → 本轮签核只覆盖内部 reg→reg 路径，不含 I/O 边界时序；core-only harness 属预期，不得外推为板级时序通过。
- CDC 不是本轮失败原因：失败原因是 Routed setup 违约（见 `result-r2-waive.md`）。
