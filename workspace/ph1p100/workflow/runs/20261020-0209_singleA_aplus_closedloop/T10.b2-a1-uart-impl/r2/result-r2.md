# T10.b2-a1-uart-impl r2 -- result (BLOCKED at board-level 187.5 boundary)

## 1. Resource fix (DONE)
- Removed `cam_preview_capture` from the P2 camera copy; HDMI now shows the built-in TPG.
  The camera byte clock/raw tap/A1 path is unchanged.
- ERAM: design **72** (was 296), CWC 30 -> **102** (<=300, target <=280 met).
- LUT 16,753; reg 16,059; IO 110/286; no DSP pressure.

## 2. Timing fix that worked
- Added a one-deep skid register at the P2 DDR bridge read-data output (board-integration
  boundary), isolating the ERAM clk2q read data from the frozen slot store's wide
  read-data/duplicate comparator.
- `clk_a1 -> clk_a1`: **SWNS +0.116 ns, 0/14,968 violating endpoints** (was -0.060,
  32 endpoints). The store/bridge read path is no longer critical.
- Other groups: ddr_user +0.423; mipi_a_byte +0.728; mcu +12.255; sys_clk50m +10.283;
  pclkx1 +3.101; mclk27 +36.490.

## 3. Remaining failure (frozen A+ core/frame reset distribution)
- Path group `sys_clk50m -> clk_a1`: **SWNS -0.193 ns, STNS -63.883, 331/331 endpoints**.
- Worst path: begin `a1_rst_sync_reg[2].q`; through `u_a1/rst_n` (fanout 3360, net 0.754 ns)
  and `a1_deflate_core`/`a1_frame_top` FIFO/read-address logic; end
  `u_a1/u_a1/u_a1/smem.addrb[12]`. Data path 4.890 ns (net 3.323), required 5.266.
- Root cause vs small top: the small top used a primary `clk`/`rst_n` port (5.333, reset
  untimed) and synthesized +0.275. The board PLL gives required 5.266 (setup 0.067,
  uncertainty 0.000 — not jitter), and the synchronized reset is a real launch flop into
  the core's reset/memory-address mux, which TD times as a data path. This path is inside
  the frozen A+ core/frame; it cannot be pipelined from the P2 wrapper.
- Even if the reset path were excluded, the clk_a1 data path is only +0.116 at synth
  (small-top +0.275; the small-top route lost ~0.23 ns), so a route-only pass is unlikely
  to reach WNS>0 / +0.2. The A1 core needs more margin.

## 4. Board-level boundary options
A. Authorize a bounded A+ core/frame reset/pipeline fix (new P1 hash; re-run 8x2/64x8/full
   regression; keep retiming/phys_opt). This is the only path to a robust +0.2.
B. Authorize a documented **real-asynchronous reset-distribution false path** and accept
   the thin clk_a1 +0.116 synth margin; route risk, target +0.2 not met.
C. User/planner device/clock/acceptance decision; do not silently relax 187.5 MHz; stop P2.

## 5. Artifacts / boundaries
- P1 r5 hash unchanged `17793341...baac88`; P1 core/frame/SDC untouched.
- No route, no bitgen, no CWC, no download. Synth 1/2 this round (second synth would not
  change the core-internal path); route 0/2; bitgen 0/1; CWC 0/1.
- Evidence: `td/a1_board_Runs/syn_1/a1_board_gate.timing` (top paths), `...area`,
  `td/build_console_r2.log`.
