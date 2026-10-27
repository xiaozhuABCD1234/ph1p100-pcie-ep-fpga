# T10.b2-a1-uart-impl r1 -- result (BLOCKED at P2 route/CWC resource)

## 1. P1 cleanup + regression (PASS)
Authorized 3-line duplicate-driver cleanup in `camera_a1_uart_top.v`:
the skid always block no longer drives `raw_rd_open`/`raw_rd_close_r`/`raw_rd_take`;
the feeder/sequencer block is the single owner and carries the same 0 defaults.
RTL hash: `17793341f717ddac3476d9c129a96b87a745f553dbdbee59efb1f29966baac88`.

Regression (ModelSim ASE 18.1, vlog 0/0):
- 8x2: 0 mismatch, 4 CRCs true, zlib true, read_words=1, dup=0, raw_len 20, stream_len 19.
- 64x8: 0 mismatch, 4 CRCs true, zlib true, read_words=32, dup=0, raw_len 640, stream_len 106.
- 1920x1080: 0 mismatch, 4 CRCs true, zlib true, read_words=129,600, dup=0, raw_len=2,592,000,
  stream_len=40,032 <= 2,594,706, raw_sha256=2f34e253...d355e830 (same as r3), cycles=6,383,945.
P1 r5 manifest: `T10.b1-a1-uart-integ/CANDIDATE-MANIFEST-b1-a1-uart-integ-r5.json`; boundary unchanged.
r4 hash record corrected (873cb98c7c79 / 8bab440d528a; stale e88de/5196 are documentation-only).

## 2. P2 synth (elaboration PASS, timing/resource FAIL)
- `p2_a1_board_top` elaborates; synth finished in 182 s.
- Resources: LUT 23,342; reg 15,960; **ERAM 296/300**; IO 110/286.
- `clk_a1` 187.5: **SWNS -0.060 ns, 32 violating endpoints**; overall SWNS -0.137 / STNS -12.058.
  Other groups: ddr_user +0.426/0 viol; mipi_a_byte +0.727/0 viol; mcu +11.678/0 viol.
- The camera preview (`cam_preview_capture`, 4 banks 960x540) accounts for 224 ERAM and the
  HDMI 148.5 path; the design ERAM 296 + ChipWatcher 30 = 326 > 300, so `phy_1` aborted in
  `compile_watcher` before place/route:
  `KIT-8472 ERROR: ERAM consumption exceeds limit (300), 296 by design, 30 by chipwatcher`.
- No route, no bitgen, no CWC, no download.

## 3. Why stopped
r1 is the final bounded P2 attempt (dispatch: 90 min/50 calls, TD 2 sessions/120 min, no
automatic r2). Even after removing the preview (224 ERAM), the A1 187.5 domain is already
-0.060 ns at synthesis under the board PLL; the small-top route history (+0.275 synth ->
+0.047 route) shows route will not recover to WNS>0. The P2 gate requires WNS>0, so a route
attempt would not produce a valid candidate. Stop BLOCKED; no bitgen/CWC.

## 4. Minimal next step
1. Planner/user decision: allow removing `cam_preview_capture` from the P2 camera copy
   (HDMI = TPG only) to free 224 ERAM and the HDMI critical path; reduce CWC probes to fit.
2. Resolve the 187.5 timing: either authorize a new P1 timing fix (new hash) or explicitly
   accept a documented 187.5 boundary (the gate currently requires WNS>0; -0.060 synth is
   negative). Do not silently relax the clock.
3. Fresh synth/route/bitgen/CWC round after the decision.

## 5. Budget
Dev ~90 min (exhausted); calls ~24/50; TD this round 1 session (~55 min); synth 1/2;
route 0 completed (phy aborted at debugger); bitgen 0/1; CWC 0/1; download 0.
