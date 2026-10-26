# dev-notes — T11.runB-debug-rtl r3（issue-02 复位域修复；第 3/3 修复轮）

- 裁定依据：dev-plan v1.16 / §3.2.1；用户授权重建调试位流；0 下载、0 Flash、0 硬件。
- 修复（仅调试路径）：9 个 MARK_DEBUG 快照寄存器的**复位源**与 PCIe 链路解耦 —— 新增 `dbg_por_rst`（= ~pcie_power_on_rst | ~pcie_pll_locked，板级 POR 或 PLL 未锁时有效），在 ep_bar_win 的 `g_dbg_mark` 内做异步置位/同步释放；**时钟仍为 clk=tl_clk_user**（与 CWC 探针时钟同一网络：top 的 u_uart core_clk=tl_clk_user，旧/新 cwc 均记录为该网络）。
- 未搬域：9 字全部保留在 tl_clk_user；DDR/CSI 源信号与计数语义未动（无链路时它们保持原值/0，属 Tier-2 归因，不在本轮改判）。身份/版本/CTRL 在无链路时可读；CTRL 读回=0x21（bit0/bit5=1）来自复位默认值。
- 生产等价：`DBG_CTRL_DEFAULT_EN=0` → generate 关闭；新端口/网络无消费者，生产行为不变（8 TB + DBG-off 负例）。
- G1：新 TB（新增 §0 无链路相位：rst 恒 1、dbg_por_rst 释放后 9 字可读、计数可动；负例 DBG-off）+ 既有 8 TB → 9/9 ALL PASS，vlog Errors:0，组 116.3 s。
- G2：单次构建 exit 0 / 692.6 s / Routed；SWNS 0.134 / STNS 0.000 / HWNS 0.020 / HTNS 0.000 ns；0 违例行；SDC 失败告警 0；资源 LUT 23.20% / reg 15.22% / ERAM 50.33%。
- CWC：auto_created_cwc1 9 view / 288 trigger + 288 data；`compiled.cwc`=8d2998b9…、`compiled.bit`=bfafdf97…（与 phy bit 同 SHA）；`--multipiece` accepted（15 片、288/288 数据 + 1 TD 状态尾位）；9 例夹具 9/9。
- 冻结：`debug-fix3/`（bit/CWC/BID/timing/area/日志/diff/rollback/hardware-ready/manifest）；旧 `2385cded…` 与 `e81d353b…` 并列保留、未混拼。
- commit：shell git commit 被权限拒绝（1 次尝试，未绕过）→ `commit_status=BLOCKED_PENDING`，4 个改动文件为 worktree-only。