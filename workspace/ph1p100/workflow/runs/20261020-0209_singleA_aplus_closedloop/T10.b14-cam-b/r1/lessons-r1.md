# T10.b14-cam-b r1 -- lessons

1. **Verify a "bit compiled the wrong source" claim against the synthesis file
   list, not against board status fields.** `a1_board_Runs/syn_1/a1_board.prj`
   is the authoritative list the synthesizer consumed; it already showed one
   `changed-src` copy. `routed_netlist.v` keeps source path/line comments and
   the `localparam` value, which is a cheap post-build proof of a compile-time
   selection. Add this check to the build script (done in r1) instead of
   relying on a `.al` diff after the fact.

2. **Documented bit positions must be recomputed from the concatenation.**
   `{19'd0, CAM_SEL, lane_sticky, 3'd0, ...}` puts CAM_SEL at bit 12, but the
   r0 comment, manifest and checker all said bit 20. A simulation "proof"
   that hardcodes `camsnap[13]=32'h2232_000E` only tests the testbench, not
   the RTL. Hardware caught it: b13 `0x0F1D` vs b14 `0x1F1D`.
   Rule: for every status field, (a) derive the bit index from widths in a
   comment, (b) assert it on hardware against a known baseline word, (c) make
   the simulator drive the *real* wrapper output, not a constant.

3. **A green simulation can hide a mapping bug.** S3 passed "bit20" because
   the TB drove the field directly. When a bit is the acceptance marker, the
   TB must sample the producer, or the check must be duplicated in a
   build/netlist assertion.

4. **B camera is not the problem.** 4,470 complete 1080p30 frames, exact ROI
   groups and zero geometry errors in both r0 and r1 runs. Stop re-proving the
   CSI/PHY path; spend the next round on the per-frame give-up in the DDR
   store/encode path, which reproduces with camera A (b15).

5. **Board tooling must be self-contained per round.** The r1 parser initially
   failed because `a1_pattern_reference.py` lives in `r0/sim/indep/indep/`;
   the parser now searches the r0 sim tree as a fallback. Better: give each
   round a `sim/indep` link or ship the reference module with the parser.

6. **A full rebuild is cheap (~22 min) and reproducible**: same STA
   (+0.110/+0.020), same CWC bytes (2e624fab...), same board deltas as r0.
   When only the file list changes, expect bit hash drift but identical CWC.

7. **`td_env.ps1` requires `a1_eng_top.v` + `a1_small_top.sdc`** in the round's
   td dir; a fresh r1 copy must include them or the mapping step fails closed
   (it did, first launch).
