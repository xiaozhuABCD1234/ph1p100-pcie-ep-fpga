# T10.b20-a-timing -- final summary (dispatch stage)

**This file is a dispatch-stage placeholder, not a closeout.** Nothing has been simulated, built,
downloaded or verified for `T10.b20-a-timing` yet. It records the frozen plan and the exact state the
planner must overwrite at closeout.

## 1. State at freeze

| item | value |
|---|---|
| package | `T10.b20-a-timing`, round r0, batch 1 |
| status | **ready** (dispatched to a new developer) |
| needs_user_input | false (one operator action at the board step: R14 pulse) |
| candidate | none yet -- no manifest, no bit, no CWC, no capture |
| parent `T10` | stays blocked/active; b19 was FAIL (routed -0.098 ns / 10 endpoints) |
| `workflow/tasks.json` | **untouched** at dispatch; update only after the tester verdict |
| planner budget used | 15 min / 30 calls (this freeze) |

## 2. What this package is committed to deliver

1. `r0/changed-src/`: b19 baseline, **only** `a1_frame_top.v` changed, one register stage in the
   `abort -> smem` read-address cone; SDC `0888b6a7...` / ADC `1cb30346...` byte-identical.
2. `r0/sim/`: T1-T6 PASS with the b19 exact counters (`cycles=37,465,298`, `cmp_words=648,677`,
   `cmp_writes=81,085`, four CRC+zlib), P1 three goldens byte-identical, T4 abort-recovery
   (`timeout=retry=1`, `giveup=0`), v6 bit12=0, real top CAM_SEL=0.
3. `r0/td/`: one Routed DB with **0 violations, WNS >= +0.05** (or `+0.003..<+0.05` as a
   thin-margin caveat candidate), one bitgen, one CWC, cone-break evidence.
4. `r0/board/`: one SRAM download, R14 alignment, one 300 s COM8 capture, A export gate; or
   `blocked_A_no_pixels` / `blocked_operator` with evidence.
5. `CANDIDATE-MANIFEST-b20-a-timing-r0.json`, `r0/result-r0.md`, `r0/lessons-r0.md`,
   `r0/diag/abort-path-fix.md`, independent tester report
   `test-reports/T10.b20-a-timing-r0-integrated.md`.

## 3. Verdict matrix (to be filled by the tester + planner, not now)

| outcome | meaning | next |
|---|---|---|
| PASS (all three, WNS >= +0.05, board export) | A chain timing closed, board frame verified | record candidate; consider T10 next step |
| PASS with `timing_caveat=thin_margin_+0.0xx` | bit/CWC/board valid, margin thin | record caveat; no robust-timing claim |
| FAIL(route_timing) | one route spent, still violated or `< +0.003` | keep routed DB; stop; planner decides a different structural target |
| FAIL(synth_no_gain) | synth `< +0.127`, no route spent | stop; the pipeline did not help |
| FAIL(bitgen / cwc) | bit/CWC fail-closed error | no download; return to planner |
| `blocked_A_no_pixels` | A pix/line/frame all 0 with a valid 300 s capture | A front-end/hardware conclusion; no rebuild |
| `blocked_operator` | R14/COM8 window unavailable | keep bit + download record; new window needed |
| `blocked` (preflight/budget) | no downloads/captures taken | resume when the condition is met |

## 4. Explicit exclusions

- Not a b19 repair round; b19 remains FAIL with its evidence intact.
- No SDC/clock/frequency/seed/multicycle/false-path relaxation, no second route, no second
  bitstream, no second download, no Flash, no docs/global-config writes, no batch delete.
- Does not prove: B camera, dual-cam sync, RK/PCIe, DDR IP behaviour, G4 long-run, or any
  `-0.098 -> +0.05` claim until the routed report exists.

## 5. Resume / dispatch text

`恢复：D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b20-a-timing；本轮目标：<目标>`
