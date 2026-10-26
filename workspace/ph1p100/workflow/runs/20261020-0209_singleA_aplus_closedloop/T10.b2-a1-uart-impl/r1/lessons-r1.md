# T10.b2-a1-uart-impl r1 lessons

## P1 duplicate-driver cleanup
Deleting only the three duplicate assignments was insufficient: the skid block also
carried the per-cycle 0 defaults for `raw_rd_open`/`raw_rd_take`. Removing them left the
signals stuck high (8x2 passed by luck, 64x8 ran 20M cycles with enc=0). The correct
single-owner fix is: delete the skid-block assignments AND add the same defaults to the
feeder/sequencer always block. Full-frame raw_sha256 is unchanged, so the cleanup is
semantically neutral. Always run 8x2 + 64x8 + full (not just the smallest case) after a
reset-ownership change.

## P2 resource/timing facts
- Camera preview (`cam_preview_capture`, 4 x 960x540 banks) = 224 ERAM; remove it for the
  UART-only P2 candidate (HDMI test pattern), otherwise the CWC 30 ERAM cannot fit (326>300).
- The board PLL-derived 187.5 clock adds enough uncertainty that the frozen A1 core is
  -0.060 ns at synthesis (32 endpoints), versus +0.275 ns on the ideal small-top clock.
  A route-only attempt cannot be expected to meet WNS>0; this needs a P1 timing decision,
  not a relaxed constraint.
- TD `phy_1` aborts at `insert_debugger`/`compile_watcher` when ERAM is over; check
  `a1_board_Runs/phy_1/run.log` immediately instead of waiting for `.opt_route.begin.f`.
- PowerShell `Set-Content -Encoding UTF8` on Windows PowerShell adds a BOM; TD tcl then
  fails with `invalid command name`. Write tcl with ASCII/no-BOM.
