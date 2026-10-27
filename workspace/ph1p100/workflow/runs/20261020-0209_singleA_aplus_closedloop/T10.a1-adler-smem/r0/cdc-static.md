# cdc-static — T10.a1-adler-smem r0

**状态：not_executed（不构成 G2 证据）。**

原因：本包在综合闸门停止（global WNS +0.233 < 派发闸门 +0.3），按 dispatch
`Synth WNS < +0.3 -> do not route; close` **未布线**，因此：

- 无 `*_pr.db`，未执行 `import_db` / `update_timing -mode final`；
- 未生成 `routed_timing_summary.rpt`、`check_timing.rpt`、`routed_clock_utilization.rpt`；
- 未做任何“静态单时钟 CDC”复核，也不得声称 `report_cdc`（TD 2026.2 无此命令，bm-addr 包已留证）。

已知事实（仅来自锁定 SDC，未在本包重新取证）：`a1_small_top.sdc`（`227dd39e…6311`）只有单一时钟 `clk`，本包未改 SDC、未改时钟结构。该事实**不能**替代布线后 `check_timing`/`report_clock_utilization` 证据。若后续包布线，需重新生成上述三份报告后再补本文件。
