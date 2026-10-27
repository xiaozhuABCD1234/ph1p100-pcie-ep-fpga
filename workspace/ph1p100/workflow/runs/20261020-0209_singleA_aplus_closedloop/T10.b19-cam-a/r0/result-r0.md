# T10.b19-cam-a r0 — developer result (final)

Package `T10.b19-cam-a`, run `20261020-0209_singleA_aplus_closedloop`, round r0.
Developer role (general standing in for fpga-dev). 2026-10-26.
**Status: FAIL — routed setup timing does not meet the gate; bitgen/CWC and the
board run were correctly not executed.**

The approved SDC fix (option A) resolved the clock-group failure and the build
completed a full route, but the routed A candidate has 10 violated setup
endpoints, WNS **-0.098 ns** (TNS -0.518), all in the `clk_a1` self domain.
Per the frozen gate (`< +0.003` or any violation -> stop, no bitgen) the route
attempt limit is spent and no bitstream may be produced.

## 1. Candidate and deltas

| item | value |
|---|---|
| RTL top | `b08438e82adcb82726e6632a765e4ac134caea3bb79e0c0a3468274c135981d0` (b18 top + line 97 CAM_SEL=0) |
| other 10 RTL | 10/10 hash-equal to b18 |
| ADC | `1cb30346fa17da6bb0e77802ca72c4b4bb4aecc1445711e19391cf4ee2271580` (b18) |
| SDC before | `3fe1641270eb0cd90a25a3d4724617f7f81103d83f8d364bb954cd41329cf2ed` (b18) |
| SDC after (approved A) | `0888b6a705a039a6cbabebacf323244a36257b5f29fb51bab7d81ef003220f5e` |

Approved SDC diff (`r0/td/p2_board-b19.diff.txt`, `r0/td/sdc-hashes.txt`):

```diff
 set_clock_groups -asynchronous \
     -group {sys_clk50m pclkx1 pclkx5 mclk27 clk_a1} \
     -group {ddr_user} \
-    -group {mipi_a_clk_hs mipi_a_byte_clk} \
-    -group {mipi_b_clk_hs mipi_b_byte_clk}
+    -group {mipi_a_clk_hs mipi_a_byte_clk}
```

Only the group of the two absent B clocks is removed; all other constraints
(`create_clock`, the B `create_generated_clock`, A group, false paths, path
skews, `derive_clocks`) are byte-identical to b18. Static conformance after the
change: **C01-C19 PASS** (`merge-conformance-r0.txt`), C14/C19 now assert the
approved one-group diff.

## 2. Simulation (unchanged by the SDC edit; same candidate)

All PASS, `vlog Errors:0`: T6 real-top `sysstat=0x00000F1D` bit12=0 + A
signature; T2 native 16-word 5/5; T5 v6 273/6/67 field#13 `00000f01` bit12=0;
T3 P1 three goldens byte-identical; T1 A geometry source_groups 2,117,472 /
line_rises 2,192 / frame_rises 1 / crop_sofs=lasts=1 / crop_groups 518,400 /
raw_len 2,592,000 / enc=1 / exported=1 / four CRC+zlib; T4 drop-R timeout=1
retry=1 giveup=0 (1 frame) and 3-frame middle retry 3/3 export.
Evidence: `r0/sim/sim-results-b19-{camsel,native,status,p1,chain}.json`.

## 3. Build

### Attempt 1 (TD session 1, b18 SDC)

`P2_SYN_SWNS=-3.055` — stopped before route. Cause: CAM_SEL=0 trims the B byte
clock, the frozen `set_clock_groups` then references a missing clock and is
dropped, so SDC-declared async CDC paths were timed. Full analysis:
`r0/diag/build-constraint-finding.md`; evidence kept in `r0/td/attempt1/`.

### Attempt 2 (TD session 2, approved SDC, synthesis 2/2 + route 1/1)

```
P2_SYN_SWNS=0.127 P2_SYN_STNS=0.000 P2_SYN_SLICE=18718 P2_SYN_ERAM=72 P2_SYN_REG=20086
P2_ROUTED_SWNS=-0.098 P2_ROUTED_STNS=-0.518 P2_ROUTED_HWNS=0.020 P2_ROUTED_HTNS=0.000
P2_ROUTED_VIOL_EP=10 P2_ROUTED_TOTAL_EP=26649
Period Check WNS: 2.200ns
NO_BIT_FILE
```

- Clock groups now apply: the only violated group is `clk_a1 -> clk_a1`
  (Self, 10 EP); `ddr_user +0.007`, `mipi_a_byte_clk +0.266`,
  `sys_clk50m +8.994`, `pclkx1 +2.564`, all other groups 0 violations.
- Worst path: `u_a1/a1_abort_reg` -> `u_a1/u_a1/smem.addrb[10]`
  (`a1_frame_top` abort -> smem address), 6 logic levels (LUT6×2, LUT4×2,
  LUT3×1, ERAM), data 4.663 ns + skew 0.072 + uncertainty 0.211 vs 5.333 ns.
- Resources: 24,989 slices (34.86%), ERAM 102/300, DSP 0, GCLK 9.
- Final STA still logs the expected `create_generated_clock ... mipi_b_byte_clk`
  failure (the B divider no longer exists); it does not affect the remaining
  groups, which is why the route now has only self-domain paths.
- Gate: WNS < +0.003 and 10 violated endpoints -> **stop, no bitgen, no CWC**
  (route attempts 1/1 exhausted; no seed/frequency/SDC relaxation permitted).

No `a1_board.bit` / `.cwc` / `.bid` exists for b19; `cw/` is empty.

## 4. Board

Not run by rule: no b19 bitstream, b18's B bitstream may not be reused, and the
route gate failed. Preflight/download/R14/COM8 were not executed; 0 downloads.
The A gate `r0/board/check_b19_board.py` was validated on the b18 B capture as a
negative control (`r0/board/gate-selftest-b18/`): `FAIL`, `camsel_bit12=1`.
`run_board_b19.ps1` is ready if a future authorized candidate gets a bitstream.

## 5. Budget / limits

TD sessions 2 (attempt 1 synthesis, attempt 2 synthesis+route); synthesis 2/2;
route 1/1; bitgen 0; CWC 0; downloads 0; Flash 0. No SDC relaxation beyond the
approved B-group removal; no clock/frequency/seed change; no write outside
`T10.b19-cam-a/**`. Elapsed slightly over the 90 min dev target because of the
approved extra synthesis+route round.

## 6. Next decision for the planner

The A-chain logic itself builds and the only miss is -0.098 ns on
`clk_a1` (`a1_frame_top` abort -> smem address, 6 levels). Options are outside
this task's frozen scope (new route attempt/seed, a targeted pipeline fix in
`a1_frame_top`, or accepting a diagnostic build is not allowed by the current
gate). No PASS and no board claim is made.

## 7. Artifacts

- `r0/result-r0.md`, `r0/lessons-r0.md`, `r0/diag/build-constraint-finding.md`
- `r0/merge-conformance-r0.txt`, `r0/check_merge_b19.py`
- `r0/td/p2_board-b19.diff.txt`, `r0/td/sdc-hashes.txt`
- `r0/td/attempt1/{run_build_b19.out,build_console_r0.log,syn_gate_timing.rpt,syn_gate_area.rpt}`
- `r0/td/{run_build_b19.out,build_console_r0.log,syn_gate_timing.rpt,syn_gate_area.rpt}`
- `r0/td/{routed_qor.rpt,routed_timing_status.rpt,routed_timing_summary.rpt,routed_area.rpt,routed_netlist.v}`
- `r0/td/a1_board_Runs/phy_1/a1_board_pr.db`
- `r0/sim/**` (results above), `r0/board/**` (scripts + gate self-test)
- `CANDIDATE-MANIFEST-b19-cam-a-r0.json`

## 8. Rollback

Only `workflow/runs/.../T10.b19-cam-a/**` was written. b18/b17/b13/b14 trees,
`workflow/tasks.json`, `docs/**`, `upstream/**` untouched. No Flash, no board
write, no download. Inert leftovers `r0/td/01_build.tcl.bakcopy`,
`run_build_b18.ps1`, `run_bitgen_cwc_r0.ps1` are not in the build list or
manifest (shell policy rejected deletion).
