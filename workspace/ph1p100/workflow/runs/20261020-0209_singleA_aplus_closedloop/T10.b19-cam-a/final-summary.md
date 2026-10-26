# T10.b19-cam-a -- final summary (planning round, 2026-10-26)

## Verdict

**Planning complete; candidate not yet produced.** Package frozen as `ready`, round0 acceptance
pending. `needs_user_input=false`. Parent `T10` remains active.

## What this round did

Took the b18-proven chain (native PAXI x8 / mask=0 / retry / R1 / v6 / B tap) and froze the
cheapest decisive A-camera trial: the same 11 sources with exactly one localparam changed,
`CAM_SEL 1'b1 -> 1'b0`. A was last measured on b13 with `pix_beats=0`, but that bit had no PAXI
fix and no retry, so the camera question was never isolated. b19 isolates it without touching the
read/export logic.

Deliverables written (this dir): `input-index.md`, `fpga-design-guide.md`, `dev-plan.md`,
`dispatch.json`, `handoff.md`, `user-summary.md`, this file.

## Frozen decisions

| item | decision |
|---|---|
| baseline | b18 r0 `changed-src` (11 files), byte-identical except the top localparam |
| RTL delta | `p2_a1_board_top.v` line 97 `localparam CAM_SEL = 1'b0;` only |
| kept | PAXI native x8 / `wstrb=0` / retry / R1 / v6 273 B / B tap+core (instantiated, unselected) |
| SDC/ADC | b18 byte-identical (both A and B byte clocks constrained); no seed/frequency change |
| sim gate | A geometry `2,117,472 / 2,192 / 1 / raw_len 2,592,000 / enc=1 / exported=1 / four CRC+zlib`; 16/16 native; P1 three goldens byte-identical; drop-R retry; v6 bit12=0, lane `4'hF`; real-top A select |
| build gate | 0 violations, hold >= 0, period positive, ERAM+CWC <= 300; WNS >= +0.05 target, +0.003..<+0.05 diagnostic with caveat, <+0.003 or violation -> stop; 1 bitgen + 1 CWC |
| board gate | preflight -> 1 SRAM download -> reset alignment -> COM8 **300 s**; bit12=0; v6 273/6/67 `bad_xor=0`; A pix/line/frame > 0; enc>0; exported>0; >=1 frame four CRC+zlib; no half frame |
| A no-pixel | `board=blocked_A_no_pixels`; keep capture/status/cam_*; A hardware conclusion; no rebuild/redownload |
| reset alignment | one operator pulse on R14 `sys_rst_n` after download; record; no pulse -> missing frame ambiguous, board blocked |
| budget | dev 90 min / 50 calls; TD 2 sessions; synth <=2; route <=1; bitgen 1; CWC 1; download 1; Flash 0; tester 45 min / 30 calls |

## Not done / not claimed

No RTL was written, no simulation, no build, no download in this round -- the plan freezes the
inputs, the one-line recipe and the gates. No timing, resource, board or throughput number is
claimed for b19. `T10` is not closed.

## Next exact action

Spawn one new developer on `T10.b19-cam-a` r0 with `dispatch.json` and `dev-plan.md` S1-S5.
