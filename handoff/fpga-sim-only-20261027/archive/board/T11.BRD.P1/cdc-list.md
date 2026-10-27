# T11.BRD.P1 — 时钟 / 复位 / CDC 清单（C1–C7 落地与实例名）

本文件把 `fpga-design-guide.md` §4.1 的冻结 CDC 清单逐项对应到本包实际 RTL 实例。
所有跨域结构只有三类：Gray 指针异步 FIFO（`capture_async_fifo` / `p2_ddr_bridge` 内部）、
"整组保持 + 单比特 toggle + 2FF"（`brd_xing_bits`）、单比特电平 2FF（`brd_2ff_sync`）。
没有运行时时钟 mux，没有未列出的跨域组合路径。

| # | 方向 | 结构 | RTL 实例（板级顶层层次） | 文件 |
|---|---|---|---|---|
| C1 | `cam_a_byte_clk` → `clk_core` | 43bit 异步 FIFO（格雷 + 2FF） | `u_datapath/u_fe_a/u_cam_fifo` | `brd_cam_fe.v` |
| C2 | `cam_b_byte_clk` → `clk_core` | 43bit 异步 FIFO（格雷 + 2FF） | `u_datapath/u_fe_b/u_cam_fifo` | `brd_cam_fe.v` |
| C3 | `clk_core` ↔ `usr_clk` | 三只 Gray 指针 FIFO（WF / AF / RF） | `u_datapath/u_bridge/u_wf`、`u_af`、`u_rf` | `p2_ddr_bridge.v`（b18 只读） |
| C3b | `usr_clk` → `clk_core` | 单比特电平 2FF（`ddr_rdy`） | `u_datapath/u_sync_rdy` | `brd_board_datapath.v` |
| C4 | `clk_core` → `tl_clk_user` | 358bit 保持 + `desc_arm` toggle + 2FF | `u_datapath/u_desc/u_x` | `brd_cdc_mailboxes.v` |
| C5 | `tl_clk_user` → `clk_core` | 65bit 保持（ACK/CANCEL + seq + session）+ toggle + 2FF | `u_datapath/u_ack/u_x` | `brd_cdc_mailboxes.v` |
| C6 | `tl_clk_user` → `clk_core` | 108bit 保持（done/status/err/tlp/held/busy/block）+ toggle + 2FF | `u_datapath/u_track/u_fwd` | `brd_cdc_mailboxes.v` |
| C6b | `clk_core` → `tl_clk_user` | 128bit 保持（P4 状态快照）+ toggle + 2FF | `u_datapath/u_track/u_back` | `brd_cdc_mailboxes.v` |
| C7 | `tl_clk_user` → `clk_core` | 203bit 保持（BAR 静态配置整组影子）+ toggle + 2FF | `u_datapath/u_cfg/u_x` | `brd_cdc_mailboxes.v` |

## 复位

- `pcie_power_on_rst`（R14 按键，低有效，PULLUP，只出现这一个端口）——
  各域都是"异步置位、同步释放"：
  - `clk_core`：`brd_integrated_top` 内 `r_core_rst_cnt` + `core_pll_lock` → `rst_core_n`
  - `tl_clk_user`：沿用参考工程的 `power_on_rst_dly`（取反后作 `tl_rst_n`）
  - `usr_clk`/DDR：沿用 `ddr3_mc_0` 的 `ddrphy_rst_n`
  - `cam_a/b_byte_clk`：沿用 PHY 的 `w_a_rst_out` / `w_b_rst_out`
- 没有把 R14 直接当同步复位使用，也没有跨域共用未同步复位。

## 约束侧对应（`td/brd_board.sdc`）

- `set_clock_groups -asynchronous`：`{tl_clk_user sys_clk clk_core}` / `{cam_a_clk_lane cam_a_byte_clk}` /
  `{cam_b_clk_lane cam_b_byte_clk}` / `{*usr_clk}`
- 格雷总线：`set_path_skew ... 4.000` 共 10 条（2 个 cam FIFO × 2 方向 + 3 个 bridge FIFO × 2 方向）
- 允许的两条 `set_false_path`：`pcie_power_on_rst`（R14 异步输入）、`user_int_trigger`（异步按键）
- 内部数据路径**没有**任何 `set_false_path` / `set_multicycle_path`
- `clk_core` 由 `rename_clock` 从同一个 PH1P PLL wrapper 的 `clkc[0]` 命名（与 b18 的 `clk_a1` 同一写法），
  频率由 `brd_a1_core_pll` 的 `REFCLK_DIV=3 / FBCLK_DIV=90 / CLKC0_DIV=10` 决定 = 150.000 MHz

## 已知未完成 / 需后续确认

- `cfg_phase`（Bayer 相位）默认 0，来自 b18 `SRC_BAYER_PHASE` 的"未板证"占位，需 P2 用真实帧确认。
- `cfg_aplus_prep/pred` 取 b18 板级已验证值 1/1。
- C6 的 `pcie_done` 由 `st_done` 计数器变化沿产生，属于"状态快照"语义，最长延迟一个 mailbox 往返。
