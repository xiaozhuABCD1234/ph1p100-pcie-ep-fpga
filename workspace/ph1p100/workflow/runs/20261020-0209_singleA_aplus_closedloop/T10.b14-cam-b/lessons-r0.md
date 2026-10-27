# T10.b14-cam-b — lessons r0

Reusable root causes / triggers / fixes / verification entry points only.

## 1. "Enable camera B" was the wrong framing

- Trigger: task text said "switch A+ tap to B", and past diagnoses talked about B
  being unused.
- Fact: `u_cfg_b` (`I_cam_mode=1`) and `u_csi_b` (`I_rst_n`/`I_rx_en` released)
  already exist and auto-start; B pins are assigned; the B tap wires already feed
  debug counters. Only the tap **export** and the board-level **selection** were
  missing.
- Rule: before writing an "enable" patch, grep the core for the instance and its
  reset/enable ports and confirm on the actual baseline SHA.
- Entry point: `f9p_camera_display_core.v` L182–239; `board_p2.adc` B pins.

## 2. Compile-time selection must stay a `localparam` + `generate`

- `localparam CAM_SEL=1` plus a generate branch gives a direct BUFG clock
  connection; a mux/register would create a new clock network and CDC risk.
- `CAM_SEL=0` must re-use the exact b13 nets so the rollback is a rebuild, not a
  re-port. Keep the A core instantiated and only re-route the `u_a1` inputs.
- Entry point: `r0/diag/cam-sel-equivalence.md` (line-by-line table).

## 3. The new byte-clock domain needs its own generated clock

- Undriven/unconstrained generated clocks silently degrade route timing.
  Add `create_generated_clock mipi_b_byte_clk` on
  `u_camera/u_csi_b/u_rx_phy/u_hs_clk_div.clkdivout` and add it to the existing
  `mipi_b_clk_hs` asynchronous group; do not touch the other SDC lines.
- Entry point: `r0/td/p2_board.sdc` diff (2 changes only).

## 4. Dead-clock simulation needs an explicit domain initialisation

- With `clk_cam` never toggling, registers that only have a **synchronous**
  `if (!rst_n)` clear stay X. The status packet path survives because
  `cam_diag_mailbox` has an asynchronous slow-side reset and holds 0, but direct
  `o_st_*` outputs stay X and would fail a naive `st_cap == 0` check.
- Fix used: run a few `clk_cam` edges while `rst_n` is still low (hardware powers
  these registers up at 0), then stop the clock. Document it in the TB.
- Entry point: `r0/sim/tb_b14_deadclk.sv`.

## 5. A short-line abort legitimately produces `raw_drop=1` and two SOFs

- The bad frame opens a RAW writer on its first ROI line; the next line rise sees
  `grp_idx != CG`, aborts, and the store drops the partial frame. The good frame
  then gives the only complete SOF+LAST and the only export.
- Pass criteria must be `cap=1/enc=1/exported=1`, `crop_sofs=2`, `crop_lasts=1`,
  `raw_drop=1`, `geom_err=1`, `short=0`, one decoded frame with four CRCs.
  Expecting `raw_drop=0` or `crop_sofs=1` is a checker bug, not an RTL failure.
- Entry point: `r0/sim/check_b14_s5.py`.

## 6. P1 golden harness needs `a1_ddr_model.v` in the file list

- `tb_p1_chain.v` instantiates `a1_ddr_model`; omitting it compiles but fails at
  `vsim` with `vsim-3033` and no capture file (looks like "MISSING" hash).
- Entry point: `r0/sim/run_b14.py` `grp_s2` file list.

## 7. TD rewrites `a1_board.al` on `create_project`

- After a build, the stored `.al` is TD-normalised (`Path="T:/"`, no `<UCode>`,
  regenerated file list). Keep the hand-edited pre-build copy
  (`r0/diag/a1_board.al.pre_build`) for the path-only diff; do not use the live
  `.al` as evidence of the source edit.
- Entry point: `r0/rtl-diff-r0.patch`, `r0/artifact-hashes.txt`.

## 8. Board precondition is data, not a formality

- The B camera was confirmed connected by the user, but the on-board FTDI
  (`VID_0403&PID_6042`, JTAG + COM8) is not enumerated on this PC now → 0
  downloads, 0 COM8, `board=blocked`, no retry. Distinguish this from a FAIL:
  the offline candidate remains valid and hash-frozen.
- Entry point: `r0/board/log/ftdi_preflight.txt`, `r0/board/log/board_blocked.txt`.
