# T10.b18-b17-b -- final summary (planning round, 2026-10-26)

## Verdict

**Planning complete; candidate not yet produced.** Package frozen as `ready`, round0 acceptance
pending. `needs_user_input=false`. Parent `T10` remains blocked.

## What this round did

Merged the two proven branches into one task instead of iterating them separately:
b17's native-PAXI repair + v6 status + R1 retry (offline all-PASS, Routed +0.002) as the base, with
b14's camera-B tap and `CAM_SEL=1` overlay (B live on the board, 4,470 frames, but no PAXI fix).

Deliverables written (this dir): `input-index.md`, `fpga-design-guide.md`, `merge-spec.md`,
`dev-plan.md`, `dispatch.json`, `handoff.md`, `user-summary.md`, this file.

## Frozen decisions

| item | decision |
|---|---|
| base | b17 `r0/changed-src` (PAXI native x8, `wstrb=0`, single AR, v6 273 B, R1 retry) |
| overlay | b14 `f9p_camera_display_core.v` (B tap, 25 ports) + `CAM_SEL=1` select mux in the board top |
| merged file | only `p2_a1_board_top.v` (8 edits; conformance C01-C18) |
| v6 selected camera | `cam_sysstat` bit 12 (field #13), must read 1 |
| SDC | b14 r1 `p2_board.sdc` byte-for-byte (`mipi_b_byte_clk`, divide_by 4, B async group) |
| ADC / shared six | b17 (ADC unchanged; six sources byte-identical to b14) |
| sim gate | T1 B geometry (2,117,472 / 2,192 / 1 / 2,592,000 / enc=1 / exported=1 / four CRC+zlib), T2 16/16 native readback, T3 P1 three goldens, T4 drop-R retry, T5 v6 + bit12, T6 CAM_SEL=0 equivalence |
| build gate | Routed 0 violations, hold >= 0, period positive, ERAM+CWC <= 300; WNS >= +0.05 target, +0.003..<+0.05 diagnostic with caveat, < +0.003 or violation -> stop; 1 bitgen + 1 CWC |
| board gate | preflight -> 1 SRAM download -> COM8 150 s; bit12=1, v6 273/6/67, `bad_xor=0`; timeout/retry/giveup deltas 0; enc>0; exported>0; >=1 frame four CRC+zlib; no half frame |
| board failure | keep v6 failed AR address + `diag_flags`/`inflight_state` and stop; no second download |
| budget | dev 120 min / 60 calls; TD 3 sessions; synth <=3; route <=2; bitgen 1; CWC 1; download 1; Flash 0; tester 45 min / 30 calls |

## Not done / not claimed

No RTL was written, no simulation, no build, no download in this round -- the plan only froze the
inputs, the merge recipe and the gates. No timing, resource, board or throughput number is claimed
for b18. `T10` is not closed.

## Next exact action

Spawn one new developer on `T10.b18-b17-b` r0 with
`T10.b18-b17-b\dispatch.json` and `dev-plan.md` §3 S1-S5.
