# r0 TD build evidence archive (frozen 2026-10-25 13:1x, before the r1 rebuild)

Nothing here was deleted or edited; every file is a byte copy. The r1 build writes
new files into `r0/td/` and a new `a1_board_Runs/`; the r0 project and run tree were
renamed in place:

| r0 name | new name | note |
|---|---|---|
| `a1_board_Runs/` | `a1_board_Runs_r0s3/` | r0 session-3 (last) project runs, source contained the `crop_pix` 1-bit defect |
| `a1_board.al`   | `a1_board_r0.al`  | r0 session-3 project file |

## s3/ -- copies of the r0 session-3 root-level reports (timestamps 2026-10-25 12:27-12:37)

`build_console_b10_s3.log`, `syn_gate_area.rpt`, `syn_gate_timing.rpt`,
`phy_area_run.rpt`, `phy_pr_timing_flow.rpt`, `routed_area.rpt`,
`routed_check_timing.rpt`, `routed_clock_utilization.rpt`, `routed_qor.rpt`,
`routed_timing.rpt`, `routed_timing_status.rpt`, `routed_timing_summary.rpt`,
`routed_netlist.v`, `params_after.tcl`, `place_flow.status`, `route_flow.status`,
`td_20261025_122735.log`.

Reported s3 numbers (from `build_console_b10_s3.log`): `P2_ROUTED_SWNS=0.239`,
`P2_ROUTED_STNS=0.000`, `HWNS=0.020`/`HTNS=0.000`, `VIOL_EP=0/8665`. These are
**not** a delivery candidate: the synthesised source still had `wire crop_pix`
declared 1 bit wide.

## s2/ -- copies of the r0 session-2 reports (timestamps 2026-10-25 11:45-11:57)

The root-level copies of these reports were overwritten by s3, so the s2 numbers are
preserved from the run tree `a1_board_Runs_s2/` with an `s2-` prefix:

`build_console_b10_s2.log`, `s2-syn_gate_area.rpt`, `s2-syn_gate_timing.rpt`,
`s2-syn_flow.status`, `s2-syn_run.log`, `s2-phy_pr_timing.rpt`, `s2-phy_area.rpt`,
`s2-place_flow.status`, `s2-route_flow.status`, `s2-routed_qor.rpt`, `s2-phy_run.log`,
`td_20261025_114642_s2.log`.

## b9-baseline-reports/ -- provenance warning

`candidate_timing.rpt`, `candidate_ignored.rpt`, `candidate_abnormal.rpt`,
`candidate_skew.rpt` still carry the **b9** timestamps (2026-10-25 04:50) because the
r0 package never reached `02_bitgen.tcl`; they were inherited from the b9 copy of the
`td` tree. They are archived only so the pre-r1 state is complete. They are **not**
r0/r1 evidence and must not be cited as such.
