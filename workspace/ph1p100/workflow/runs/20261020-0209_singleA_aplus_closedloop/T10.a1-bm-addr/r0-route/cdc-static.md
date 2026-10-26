# T10.a1-bm-addr r0-route 静态 CDC 证据（单时钟域）

范围：routed DB `T:/a1_bm_addr_Runs/phy_1/a1_bm_addr_pr.db`（`import_db` + `update_timing -mode final` 之后的报告）。
**不声称 `report_cdc`**：TD Release_2026.2 无该命令（本轮实测 `invalid command name "report_cdc"`，`report_clocks`/`report_exceptions` 同样不存在）。

## 1. 时钟定义与时钟树（routed_timing_summary.rpt / routed_clock_utilization.rpt）

- 约束文件 `T:/a1_small_top.sdc`；`Created by Tang Dynasty Release_2026.2`；`Confidence: Routed`；`Check Corner: Both (Slow and Fast)`；`CRPR Enabled: Yes`；`STA coverage: 96.41%`。
- Clock Summary 只有**一个**时钟：

```
clk0: 187.512 MHz  fanout 1304  clk
clk0  Inferred GCLK  5.333 ns (R-Period 5.420 / 184.502 MHz)  SWNS -0.087  STNS -1.109  HWNS +0.023  HTNS 0.000  Skew 0.344  CC-From no  CC-To no
```

- `Path Group: clk -> clk`（`Type: Self`，From Clock = To Clock = `clk`），`CC-From`/`CC-To` 均为 `no` ⇒ 报告中**无跨时钟域路径**。
- 时钟树（`routed_clock_utilization.rpt`，B 节 Clock Buffer Info）：
  - 1 个 `PH1P_PHY_GCLK`（`gclk_0` @ x39y79z0）由 **同一** 源 `PH1P_PHY_HR_PAD.di`（`clk_syn_2.di`，x0y16z0）驱动，`Source Clock Period 5.333 ns`，`Constraint None`；
  - 4 个 `PH1P_PHY_SCLK`（`sclk_1..4`）全部由 `PH1P_PHY_GCLK.clkout` 派生（Driver.Pin 均为 `clk_dup_1_created_gclkinst.clkout`），无第二时钟源、无 `PH1P_PHY_IOCLK`（`#ioclk 0/24`）、无 PLL 生成时钟（`.al` 无 PLL；综合 `pll clock constraints` 检查 0 问题）；
  - `GCLK 1/32`、`SCLK 4/96`，负载 405/380/334/153。
- 结论：**单时钟域**（187.5 MHz `clk`），时钟树为“单 PAD → GCLK → 4×SCLK，同一 GCLK 驱动”，与 r2-waive 的单时钟证据同构。

## 2. `check_timing -verbose`（routed_check_timing.rpt，工具直接 `-file`）

HIGH 项：`no clock` 0、`clock definition` 0（多驱动/内部时钟/不可展开/局部时钟/未连接生成时钟均 0）、`invalid constraint` 0、`pll clock constraints` 0、`combinational loops` 0、`soft fifo timing exception` 0；`dummy node` **1**（悬空节点，HIGH 级提示，非时序路径）。
MEDIUM 项：`no path constraints` 0、`shadowed/ignored timing exception` 0、`no input delay` **47**、`no output delay` **73**（bench top `a1_eng_top` 的边界 I/O 未加 I/O 约束，属外部端口路径，不计入内部单周期时序）、`partial/abnormal delay` 0。

## 3. 结论与边界

- 可声明：**单时钟、单源、无跨域路径**；无组合环；无被忽略的时序 exception；所有内部时序检查落在 `clk -> clk` 单组内（SWNS −0.087 / HWNS +0.023，违约均为 setup，见 result-r0-route.md）。
- 不可声明：`report_cdc` 级 signoff；未覆盖 47/73 条边界 I/O 外部延迟（无 I/O constraint，非本包范围）；STA coverage 96.41%（未覆盖部分为 false-path/异步复位等工具判定，未逐条穷举）。
