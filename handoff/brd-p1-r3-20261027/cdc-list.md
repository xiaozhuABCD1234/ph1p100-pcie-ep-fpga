# T11.BRD.P1 r3 鈥?clock / reset / CDC list (C1鈥揅9, instance names)

This file maps the frozen guide 4.1 CDC list to the actual RTL of this
candidate.  Crossings use only three structures: Gray-pointer async FIFOs
(`capture_async_fifo` / `p2_ddr_bridge`), "stable bundle + single toggle + 2FF"
(`brd_xing_bits`), and single-bit 2FF (`brd_2ff_sync` / the C8/C9 flops).
No runtime clock mux and no unlisted combinational crossing.

| # | direction | structure | RTL instance (board hierarchy) | file |
|---|---|---|---|---|
| C1 | `cam_a_byte_clk` -> `clk_core` | 43-bit async FIFO (Gray + 2FF) | `u_datapath/u_fe_a/u_cam_fifo` | `brd_cam_fe.v` |
| C2 | `cam_b_byte_clk` -> `clk_core` | 43-bit async FIFO (Gray + 2FF) | `u_datapath/u_fe_b/u_cam_fifo` | `brd_cam_fe.v` |
| C3 | `clk_core` <-> `usr_clk` | three Gray FIFOs (WF / AF / RF) | `u_datapath/u_bridge/u_wf`, `u_af`, `u_rf` | `p2_ddr_bridge.v` (read-only) |
| C3b | `usr_clk` -> `clk_core` | single-bit 2FF (`ddr_rdy`) | `u_datapath/u_sync_rdy` | `brd_board_datapath.v` |
| C4 | `clk_core` -> `tl_clk_user` | 358-bit hold + `desc_arm` toggle + 2FF | `u_datapath/u_desc/u_x` | `brd_cdc_mailboxes.v` |
| C5 | `tl_clk_user` -> `clk_core` | 65-bit hold (ACK/CANCEL + seq + session) + toggle + 2FF | `u_datapath/u_ack/u_x` | `brd_cdc_mailboxes.v` || C6 | `tl_clk_user` -> `clk_core` | 108-bit hold (done/status/err/tlp/held/busy/block) + toggle + 2FF | `u_datapath/u_track/u_fwd` | `brd_cdc_mailboxes.v` |
| C6b | `clk_core` -> `tl_clk_user` | 128-bit hold (P4 status snapshot) + toggle + 2FF | `u_datapath/u_track/u_back` | `brd_cdc_mailboxes.v` |
| C7 | `tl_clk_user` -> `clk_core` | 203-bit hold (BAR static config shadow) + toggle + 2FF | `u_datapath/u_cfg/u_x` | `brd_cdc_mailboxes.v` |
| **C8** | `tl_clk_user` -> `clk_core` | `mps_code[2:0]`, quasi-static, one 2FF per bit | `u_datapath/mps_s1[2:0]` -> `mps_s2[2:0]` -> `c_mps_code` | `brd_board_datapath.v` |
| **C9** | `tl_clk_user` -> `clk_core` | `link_up` level, single-bit 2FF | `u_datapath/lnk_s1[1:0]` -> `lnk_s2[1:0]` -> `c_link_up` | `brd_board_datapath.v` |

`u_p4` receives only `c_mps_code` / `c_link_up`.  The raw tl-domain copies stay
in the tl domain (pusher/register face); they are not a crossing.

## Reset

- `pcie_power_on_rst` (R14, active low, PULLUP, the only port on this pin) is
  asynchronous-assert / synchronous-release per domain:
  - `clk_core`: `r_core_rst_cnt` + `core_pll_lock` -> `rst_core_n`
  - `tl_clk_user`: the reference `power_on_rst_dly`
  - `usr_clk`/DDR: `ddr3_mc_0`'s `ddrphy_rst_n`
  - `cam_a/b_byte_clk`: PHY `w_a_rst_out` / `w_b_rst_out`
- R14 is never used as a synchronous reset and no unsynchronised reset is
  shared across domains.

## Constraint side (`constraints/brd_board.sdc`, r1)

- `set_clock_groups -asynchronous` with **one clock per group**:
  `{tl_clk_user}` / `{sys_clk}` / `{clk_core}` / `{cam_a_clk_lane cam_a_byte_clk}` /
  `{cam_b_clk_lane cam_b_byte_clk}` / `{*usr_clk}`.
  r0 grouped `tl_clk_user sys_clk clk_core` together, which timed the raw
  tl->core path (historical worst path `u_p4/u_egress`); that is fixed here.
- Gray buses: 10 `set_path_skew ... 4.000` constraints (2 cam FIFOs x 2
  directions + 3 bridge FIFOs x 2 directions).
- The only two `set_false_path` entries: `pcie_power_on_rst` (R14 async input)
  and `user_int_trigger` (async key, synchronised in RTL).
- No internal `set_false_path` / `set_multicycle_path`.
- `clk_core` is renamed from the same PH1P PLL wrapper `clkc[0]`
  (`REFCLK_DIV=3 / FBCLK_DIV=90 / CLKC0_DIV=10` = 150.000 MHz).

## Known open items
- `cfg_phase` stays 0 (b18 unproven placeholder); P2 must confirm with a real
  frame.
- `cfg_aplus_prep/pred` = 1/1 in the board default (b18 board-proven); the local
  G1 bypass run uses 0/0 to make the raw byte reference exact (both decode).
- C6 `pcie_done` is a one-cycle pulse on the `st_done` counter change; C6
  `pcie_err` is a one-cycle pulse on a NEW error code (r1 fix, so a rejected
  ACK cannot abort a later frame).
- The P4 egress adapter's held identity is fed from the pusher done count
  (= `held_seq` = doorbell value), not from `capture_seq` (r1 alignment).


## r3 note (C5 read side)

The C5 crossing structure is unchanged from r1/r2.  r3 corrects the read-side slice: `in_bus = {cancel, ack_seq, ack_session}`, therefore `o_ack_seq = out_bus[63:32]` and `o_ack_session = out_bus[31:0]`.  Before r3 the halves were swapped, so the egress compared the session against `held_seq` and only the watchdog released the slot (27,282 cycles in SCEN0); r3 releases on the correct ACK in 493 cycles.  This is a data-path slice correction, not a new crossing.
