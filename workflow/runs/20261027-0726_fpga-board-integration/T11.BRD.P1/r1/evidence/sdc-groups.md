# SDC clock groups and CDC closure (r1)

Local static evidence only. No STA/CDC engine was run locally (G2p is
`teammate_required`); the teammate must re-run final STA/CDC on this source set.

## 1. Clock groups in `constraints/brd_board.sdc` (r1)

r0 had `tl_clk_user sys_clk clk_core` in ONE asynchronous group.  That does not
cut the tl->core crossing; it TIMED it, and the worst path was exactly
`u_pcie_top.tl_cfg_max_payload_size -> u_p4/u_egress` (WNS -2.273 ns, 79
endpoints in the r0 historical synth).  r1 puts every domain in its own group:

| group | clocks |
|---|---|
| 1 | `tl_clk_user` (PCIe EP, BAR, pusher) |
| 2 | `sys_clk` (50 MHz, PLL reference) |
| 3 | `clk_core` (150.000 MHz, P4/datapath) |
| 4 | `cam_a_clk_lane cam_a_byte_clk` |
| 5 | `cam_b_clk_lane cam_b_byte_clk` |
| 6 | `*usr_clk` (DDR user clock) |

`set_false_path` remains only on `pcie_power_on_rst` and `user_int_trigger`
(the two allowed asynchronous inputs).  No `set_multicycle_path` and no
internal `set_false_path` exist in the file.

## 2. CDC list delta (C8/C9)

| # | from -> to | structure | instance / registers |
|---|---|---|---|
| C8 | `tl_clk_user` -> `clk_core` | `mps_code[2:0]` quasi-static, one 2FF per bit | `brd_board_datapath` `mps_s1[2:0]` -> `mps_s2[2:0]` -> `c_mps_code` |
| C9 | `tl_clk_user` -> `clk_core` | `link_up` level, 2FF | `brd_board_datapath` `lnk_s1[1:0]` -> `lnk_s2[1:0]` -> `c_link_up` |

`u_p4` now receives only `c_mps_code` / `c_link_up`; the raw tl-domain copies
stay in the tl domain for the pusher / register face (same domain, not a
crossing).  The C1-C7 structures are unchanged from r0; the full table is
`cdc-list.md`.

## 3. Limits of this evidence

- The groups, the false paths and the C8/C9 instances are checked by
  `evidence/static_checks_r1.py` (all PASS) and `evidence/cdc-static.log`.
- This is NOT a CDC/STA sign-off.  The teammate must run the real synthesised
  clock interactions, CDC report and timing on this exact filelist and record
  WNS/TNS/hold/unconstrained IO; r0's -2.273 ns / 79 endpoints are historical
  and belong to the old source set.
