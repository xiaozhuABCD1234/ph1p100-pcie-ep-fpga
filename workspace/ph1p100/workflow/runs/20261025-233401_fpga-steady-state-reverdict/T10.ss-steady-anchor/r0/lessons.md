# lessons-r0：T10.ss-steady-anchor

- **根因/触发**：2 槽 RAW 存储在“第 2 帧驱动结束→第 1 帧读完关闭”之间存在无空闲槽窗口；若第 3 帧直接背靠背驱动，`e_sof` 时 `wr_begin_ready=0`，整帧被 `raw_begin_deny` 丢弃（raw_drop 增加）。4 帧必须做 slot-free pacing，不能只改 `FRAMES`。
- **可复用修正**：在 TB 的帧间等待目标 RAW 槽 `slot_st==S_FREE`（只读 `dut.raw_slot_st`），并在 `SS_PACE` 记录 read 与 slot 状态；最终 `raw_drop=0` 与 V5 用同一证据。
- **口径**：b11 stats 的 `cycles` 含导出后 2000-cycle drain；事件口径 `t_exp(2)≈11,443,988`。`L_cold+S_2=t_exp(2)` 是自洽拆分；`S_avg2` 不是稳态。
- **测量结论（本轮）**：`L_cold=6766434`、`S_ss=4677535.0`、`startup_pct=44.66%`；`S_23=4677535`/`S_34=4677535`（band 4677535–4677535）。6,421,414 是冷启动单帧，不是每帧稳态；不得用 `L_cold` 或两帧平均替代 `S_ss`。
- **sink 尾巴**：`export_tail` 逐帧=k1=480930, k2=480930, k3=480930, k4=480930；`sink_limited=false`。常数且 <0.5·S_ss 的尾巴在帧间隔中抵消；只有增长/≥0.5·S_ss 才扣减。18.75 MB/s 只是 sim sink，115200 生产 UART 慢 1,628×，不能外推。
- **预算/隔离**：vsim 2 帧 + 4 帧各一次；work/INI/log 独占；只杀自己的子进程；未碰 TD/板卡/COM8。并发负载只影响墙钟，不影响 cycle 数。
- **负对照**：解析器拒绝 S_avg2-as-S_ss、L_cold-as-S_ss、3 帧当 4 帧；复测者应独立重写解析器，不 import 本驱动。

