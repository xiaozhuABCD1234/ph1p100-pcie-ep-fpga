# result-r0 — T10.ah-honly (H-only 2 B/cycle emit prototype, round0)

- run: `20261026-231711_fpga-a-plus-h-prototype`
- task: `T10.ah-honly` (P1, offline RTL/simulation only)
- round: 0 (first freeze)
- frozen candidate: `T10.ah-honly/r0/changed-src/{a1_deflate_core.v,a1_frame_top.v}`
  with the TB copies in the same directory; the 12 DUT in `src/` are frozen
  P1/b11 copies and are not edited.
- manifest: `T10.ah-honly/r0/manifest-r0.json` (all artifacts, SHA-256)
- **No TD/synthesis/P&R/bitgen/CWC/download/Flash/board/COM/JTAG/RK/network was
  used. All resource/timing values are estimates.**

## 1. Verdict summary

| item | result |
|---|---|
| baseline control N | **PASS exact**: S_ss 7,475,240; frame-1 core_interval 7,476,245; 4 headers; cap=enc=exported=4, read=518,400, err/wd=0 |
| baseline control L | **PASS exact**: S_ss 6,986,952; frame-1 core_interval 6,979,811; 4 headers; same counters |
| b6 core bench (8-bit and 16-bit TB) | **PASS byte-exact**: comp 50,310 B `2601d57c…a7c05`, cycles 304,961 (≤355,261); rand 153,766 B `54f262f2…496dd`, cycles 161,479 (= baseline, ≤161,479) |
| H N 1-frame probe | **PASS**: core_interval **6,197,186** (2.39089 cycles/B), frame-1 len/crc/header_crc exact, counters exact, no SS_STALL, CORE_STAGE present, export completed |
| H L 1-frame probe | **not_run** (4-run full/probe budget; see §6); L near-model **not proven** |
| byte-exact verdict | **PARTIAL** (N fully byte-exact; L probe not run) |
| P2 release check (N-based) | **PASS**: N 6,197,186 ≤ 6,500,000, byte-exact N, no stall/timeout |
| H near-model (N ≤6,390,000) | **PASS**: 6,197,186 (model 6,260,648, i.e. 63,462 cycles better) |
| H near-model (L ≤6,010,000) | **not proven** (probe not run) |
| G0 | **not applicable / not claimed** (P1 is a probe; no 4-frame H run) |

## 2. Frozen inputs and baseline control

The baseline control re-ran the frozen b11 core + the 12 frozen DUT with a
testbench-only passive per-frame A1U1 monitor (`+FRM=`). It detects the
`41 31 55 31` magic, records the 44 header bytes, parses
`stream_len/raw_crc/xform_crc/stream_crc/header_crc`, counts the declared
payload and records the last payload byte. No DUT, clock, reset, pacing or sink
change.

- N: exp t = 12,440,157 / 19,914,239 / 27,389,479 / 34,864,719 →
  S_ss = (34,864,719 − 19,914,239)/2 = **7,475,240**; frame-1
  core_interval = 9,084,241 − 1,607,996 = **7,476,245**.
  Frame 1 header: len 1,677,912, stream_crc 1,168,876,019,
  header_crc 657,705,490, raw_crc 3,665,401,424, xform_crc 2,597,442,251,
  last `0x1b`. Frames 2–4: len 1,677,336 each, stream_crc 1,924,014,695,
  header_crc 2,085,554,086 / 2,375,352,844 / 889,196,697, last `0x1b`.
- L: exp t = 12,901,635 / 19,887,447 / 26,874,402 / 33,861,351 →
  S_ss = **6,986,952**; frame-1 core_interval = 8,587,807 − 1,607,996 =
  **6,979,811**. Frame 1: len 2,156,868, stream_crc 1,770,220,292,
  header_crc 2,924,387,436, raw_crc 707,927,594, xform_crc 2,647,552,023,
  last `0x66`. Frames 2–4: len 2,156,300 each, stream_crc 1,078,294,197,
  header_crc 3,110,933,611 / 1,219,957,185 / 4,028,760,916, last `0x66`.
- Both controls: cap=4 enc=4 exported=4, read=518,400, raw_drop=cmp_drop=geom=
  err=wd=0. `ss_pass=0` is the known `dup=0` clause (N dup=3,896 / L dup=568),
  not a performance gate (P4 clarification).

Control verdicts: `out/baseline-control.json` → PASS/PASS. A mismatch would have
been a control failure, not a new baseline; none occurred.

## 3. H core bench (b6 vectors, 153,600 B each)

`out/h-bench.json`: four runs, `+BP=0 +GAP=0 +TIMEOUT=2000000`.

| run | bytes | SHA-256 | cycles | limit | pass |
|---|---:|---|---:|---:|---|
| 8-bit comp | 50,310 | `2601d57cd98d1fe69b2e46fe8423779a5d44bd14c00e1fe2d5faab6ff15a7c05` | 304,961 | 355,261 | yes |
| 16-bit comp | 50,310 | `2601d57cd98d1fe69b2e46fe8423779a5d44bd14c00e1fe2d5faab6ff15a7c05` | 304,961 | 355,261 | yes |
| 8-bit rand | 153,766 | `54f262f2a600a3e2f12129f2937a390737d1ec8018d8f0236979e604760496dd` | 161,479 | 161,479 | yes |
| 16-bit rand | 153,766 | `54f262f2a600a3e2f12129f2937a390737d1ec8018d8f0236979e604760496dd` | 161,479 | 161,479 | yes |

The 8-bit TB is the frozen `tb_a1_deflate_core.v` (OUT_BYTES default 1,
`out_keep` unconnected, missing-connection warning accepted); the 16-bit TB is
the adapted copy (OUT_BYTES=2, both bytes of a `keep=1` transfer written in
stream order). The stored-only rand vector is unchanged at exactly the frozen
161,479 cycles.

## 4. H N 1-frame probe

`out/h-probe-n.json`; `FRAMES=1 CONTENT=2 PACING=0 SINK=1 CAPTURE=0
MAX_CYCLES=13300000`, repaired probe `sim/logs/h-n-probe2.log`.

- CORE_STAGE present at t=7,805,190: blocks 540, fixed 457, stored 83,
  literals 505,140, matches 397,627, cand_aborts 83, max_match 92,
  max_dist 2048 — **all equal to the P2 baseline**.
- t_pub(1)=1,607,996, t_enc(1)=7,805,182 →
  **core_interval = 6,197,186** cycles = **2.39089 cycles/B**
  (baseline 7,476,245; Δ = **−1,279,059**; model 6,260,648 → **63,462 better
  than the model**). N ≤6,390,000 near-model **PASS**; N ≤6,500,000 P2 release
  **PASS**.
- Frame-1 A1U1 header (independent UART tap): len **1,677,912**,
  stream_crc **1,168,876,019**, header_crc **657,705,490**, raw_crc
  3,665,401,424, xform_crc 2,597,442,251, last payload byte **0x1b** — exactly
  the frozen P1 values and the local control.
- Export: exp t=11,161,098 (= t_enc + 2×1,677,912 + 92), exported=1,
  read=129,600, no SS_STALL/SS_STALL_COLD. `CORE_STAGE` present. The
  `B11_FULL_TIMEOUT` at 13,300,001 is the accepted 1-frame harness artifact
  (the TB still executes the inherited two-frame read wait); it occurs **after**
  the export (exported=1 in the timeout line), exactly as in the P2 reference
  probe. The probe `.stats` file is empty for the same reason; cap/enc/exported
  are evidenced by the EVT, CORE_STAGE and the `exported=1 read=129600`
  timeout line.
- Backpressure/diagnostic taps: replay_cycles 959,765; replay_stall 0 (this tap
  counts only S_REPLAY_R waiting for `out_space`; the real backpressure shows in
  the opq/FIFO path); fifo_max 15 (16-entry output FIFO, 2-byte entries);
  out_valid_cycles 1,373,509; core_ready_low 578,089; core_stall 335,034
  (core out_valid && !out_ready); svalid_wait 0; xfer2 639,437.
- `stat_stall` = 1,509,741 vs baseline 2,784,218: diagnostic only (input
  pacing), not an equivalence gate.

## 5. H L 1-frame probe — not run

**Status: not_run / not_proven.** The frozen full/probe budget is four runs.
The four run slots were consumed by: B1 N 4-frame, B2 L 4-frame, H1 N probe
(functional failure: frame_top pending-byte double count, `stream_len`
1,837,973, export hang) and H1b repaired N probe. No fifth full/probe
simulation was authorised. The L 4-frame baseline control is exact
(S_ss 6,986,952 / frame-1 core_interval 6,979,811), but the H L near-model
target (≤6,010,000) is **not proven**. The L probe is the first item to run in
a follow-up / tester authorisation if the planner wants the L half of the
near-model statement.

## 6. Byte-exact verdict and negative controls

`out/byte-exact.json` → **PARTIAL**: N bench + N frame-1 header/last byte +
deterministic counters are byte-exact; L is not_run.

Demonstrated negative controls (details in `out/negative-controls.json`):

- NC4: the first H bench attempt pushed replay bytes in the state that issued
  the 32-bit cmem read, before the synchronous read data landed. It produced
  two `X` bytes at stream offsets 2–3 and SHA `80dcdd95…`; the frozen-SHA check
  rejected it. Fix: a dedicated `S_REPLAY_E2` push after the wait state.
- NC7: the first H N probe exposed a frame_top pending-byte double count (a
  2-byte transfer at `scnt=3` counted/CRCed the held high byte twice:
  `stream_len` 1,837,973, export never completed). Fix: count/CRC the held byte
  only when it is written at `scnt=0`; the repaired probe matches the baseline.
- NC1–NC3, NC5, NC6: frozen bench SHAs, 8-bit vs 16-bit equality, stored-path
  cycle equality, independent header tap, baseline-control exactness.

## 7. Resource / timing (estimate only, not TD)

`out/resource-estimate.json`: 0 ERAM (2048×32 keeps the same 65,536 bits as
4096×16), +350..950 LUT6 and +240..620 REG combined. The frame_top CRC now
chains two CRC32 byte steps in one 187.5 MHz cycle; this is flagged **high**
timing risk for a later STA package (b11 routed WNS at 187.5 MHz was only
+0.015 ns). No synthesis, no STA, no resource measurement was run.

## 8. Scope / limitations

- H only; no A (2-position literal scan) implementation in this package.
- No 4-frame H run, no S_ss for H, no G0 claim. P2 owns the 4-frame ≤6.25 M gate.
- External 32-bit packing, A1U1 header layout, UART byte order, geometry,
  clock, reset, content and sink are unchanged; the 16-bit transfer is internal
  to core→frame_top only.
- L H probe not run (budget); the L near-model claim is not proven.
- Detailed machine diffs: `DIFF-h.md`, `out/DIFF-h.raw`,
  `out/DIFF-frame-top.raw`. Reusable root causes: `lessons-r0.md`.

## 9. Freeze / next action

Stopped modifying; `manifest-r0.json` lists every artifact with bytes and
SHA-256, `stopped_modifying=true`, `active_commands=0`. The frozen candidate is
the repaired core/frame_top pair above. Next: independent integrated tester
(round0); a follow-up L probe needs a planner/tester authorisation because the
developer full/probe budget is exhausted.
