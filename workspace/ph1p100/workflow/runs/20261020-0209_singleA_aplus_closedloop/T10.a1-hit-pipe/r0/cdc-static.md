# T10.a1-hit-pipe r0-route — 静态单时钟 CDC 证据（同一 routed netlist：`a1_hp_r0_pr.db`）

> **报告措辞（必须原样保留）**：TD Release_2026.2 **没有 `report_cdc`** 命令；本文件是**同一 routed netlist/clock structure 上的静态单时钟证据**，**不是**工具 `report_cdc` 签核，也**不把 `check_timing` 当 CDC**。
>
> 本文件只证明**时钟结构单域**；本网表 Routed setup **不合格**（SWNS −0.577 / STNS −57.504 / 311 违例端点），G2 仍为 **FAIL**（见 `result.md` §9）。CDC 单域结论不改变该判定。

## 1. 证据来源（全部在 routed DB import 后实际执行）

| 命令 | 结果文件 | SHA256 | 说明 |
|---|---|---|---|
| `report_clock_utilization` | `r0/td/phy_clock_util.rpt` | `f4cd9c89976cdfeb2a45aa7b8b01fde5ddb179501de0cdd15d08f62fe1564000` | 实际执行（`CLOCK_UTIL_EXECUTED`） |
| `check_timing -verbose` | `r0/td/check_timing.rpt` | `cd30e5c8abe10e560a80296289ef13ae7aa6749fb16b59a0e2b78742f930c685` | 实际执行（`CHECK_TIMING_EXECUTED`） |
| `report_timing_summary` | `r0/td/phy_timing_summary.rpt` | `c2eee885d23b7096460e82a99e0343a9f69407a84b2aac052f42f5c09e9a9440` | 实际执行（`TIMING_SUMMARY_EXECUTED`） |
| `report_timing` | `r0/td/phy_timing.rpt` | 同上内容（124318 B） | 只有 1 个 path group |
| `report_cdc -file …` | **无文件** | — | `invalid command name "report_cdc"` → `RPT_CDC_UNAVAILABLE`；**未**生成 cdc.rpt，未伪造 |
| `report_exceptions` | **无文件** | — | `invalid command name "report_exceptions"`（本版本无此命令） |
| `report_clocks` | **无文件** | — | `invalid command name "report_clocks"`（本版本无此命令） |

## 2. 单时钟事实

1. **全局时钟只有 1 个**（`phy_clock_util.rpt` §2 Global Clock Resource Stat.）：
   `gclk_0 / src_0 / PH1P_PHY_GCLK / clk_dup_1_created_gclkinst.clkout / Clock = clk / Period = 5.333 / Waveform = {0.000 2.667} / Net = clk_syn_7`，**Total Loads = 1226**。
2. **时钟源唯一**（§3）：`src_0 = PH1P_PHY_HR_PAD clk_syn_2.di`，Source Clock = `clk`，Non Clock Loads = 0。
3. **负载全部挂同一网络**（§7 FanoutGroup）：`PH1P_PHY_LSLICE(1162)` + `PH1P_PHY_ERAM(52)` + `PH1P_PHY_MSLICE(8)` + `PH1P_PHY_DRAMHARDCON(4)` = 1226，与 Total Loads 相符。
4. **无本地/衍生时钟**：§4 Local Clock Resource Stat. 为空（LCLK Used 0/24、MLCLK 0/24、IOCLK 0/24）；GCLK 1/32（只用了 gclk_0）；SCLK 4/96 是同一时钟的时钟网络脊，不是额外时钟域。
5. **`check_timing` 单域结论**（`check_timing.rpt`）：
   - `2.1 There are 0 leaf clock pins driven by multiple clocks.`
   - `2.2 There are 0 clocks created on internal clock network.`
   - `2.3/2.4/2.5`：0 unexpandable clock sets、0 local clocks、0 generated clocks 未接 master；
   - `1. checking nets with no clock driven` = 0；`6. combinational loops` = 0；
   - `8. no path constraints` = 0、`9. shadowed/ignored timing exception` = 0 → **SDC 无 false path / multicycle / 被忽略异常**；
   - `3. dummy node` = 1 个 dangling node（HIGH，TD 记为 dummy node，非时钟/非路径）；
   - `10/11 no input/output delay` = 47 / 73（MEDIUM；core-only harness 未约束 port delay，属预期，不是 CDC 问题）。
6. **时序报告只有一个 path group**：`Path Group : clk -> clk`（`phy_pr_timing.rpt`），全部 4514 端点的 launch/capture clock 均为 `clk`（每条形如 `triggered by clock clk { rise@0.000000ns fall@2.667000ns period=5.333000 }`）。

## 3. CC-From / CC-To 结论（静态推导，不是工具 CDC 报告）

- 网表只有 1 个时钟 `clk`；`check_timing` 报告 **0** 个 leaf clock pin 被多时钟驱动、**0** 个内部生成时钟、**0** 个 local clock。
- 因此不存在 `clk` 以外的捕获域，**跨域（CC-From / CC-To）路径集合为空**；时序报告也只有一个 `clk -> clk` 组，无其它组。
- 该结论由上述**静态结构 + check_timing 实际输出**推导，**不来自 `report_cdc`**（本版本无此命令），**不得**表述为"CDC 工具签核通过"。

## 4. 复现命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\td\td_env.ps1 -Force `
  -TdDir "workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-hit-pipe\r0\td"
cd T:\; D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe T:/04_route_only.tcl
# 关键片段（已实际执行）：
#   import_db ./a1_hp_r0_Runs/phy_1/a1_hp_r0_pr.db ; update_timing -mode final
#   report_clock_utilization -file phy_clock_util.rpt
#   check_timing -verbose   -file check_timing.rpt
#   report_timing_summary   -file phy_timing_summary.rpt
#   report_cdc              -> invalid command name（记录为证据缺口）
```

## 5. 边界（不要外推）

- 本证据只覆盖**时钟结构单域**。routed **setup** 违例（311 端点，SWNS −0.577）说明该网表当前**不能**作为 G2 候选；
- 若后续修复轮重新布线，必须在新 routed DB 上**重跑**同一组命令并重新冻结哈希，不能沿用本文件的结论。
