# lessons -- T10.b18-b17-b r0 (merge b17 native-PAXI/v6 + b14 camera-B)

Only reusable root causes / triggers / fixes / verification entries.

## L1. Verilog-2001 forward reference silently creates a 1-bit implicit net
- Trigger: `p2_a1_board_top.v` connected `u_a1.i_dbg_bridge(dbg_bridge)` and
  `u_bridge` before `wire [511:0] dbg_bridge;` / `wire a1_rd_abort;` were
  declared (inherited from b13/b17; TD accepts it, ModelSim reports
  `vlog-2388 'x' already declared`).
- Root cause: an undeclared identifier in a port connection becomes an implicit
  1-bit wire; the later explicit declaration is a duplicate.  In simulation the
  connection is ambiguous; in TD the elaborator happened to resolve the 512-bit
  declaration, so the b17 bitstream was never proven wrong, only unproven.
- Fix used: move both declarations above the `u_a1` instantiation (no net,
  width, name or connectivity change; `C12` still sees exactly one
  `wire [511:0] dbg_bridge`).
- Verification: `tb_b18_camsel.sv` elaborates the real top with `vlog Errors:0`.
- For future tops: declare every wide debug bus before its first use.

## L2. A top that cannot be simulated can still be verified structurally
- Trigger: `p2_a1_board_top` needs the PLL IP, DDR PHY shell, MCU ROM image and
  MIPI PHY, none of which exist in ModelSim ASE.
- Fix: generate stubs whose port lists are parsed verbatim from the frozen
  sources (`r0/sim/gen_stubs.py`), drive the A and B taps with *different*
  signatures, instantiate the real top with `.*` and observe
  `u_top.u_dbg_sys_mail.i_data[63:32]` and `u_top.u_a1.*`.
- Payoff: `CAM_SEL` bit 12, the B selection and the whole `cam_sysstat` concat
  are proven on the merged RTL instead of being inferred from a diff, and a
  wrong mux is a hard failure (A signature differs from B).  Cost: one script,
  one 40-line TB, <1 s runtime.

## L3. Byte-identical file copies are not enough for a TD rebuild
- Trigger: `b17/r0/td/src/` still contained stale `p2_a1_board_top.v` (b13),
  `f9p_camera_display_core.v` (A-only b17) and `p2_ddr_bridge.v` (pre-PAXI)
  copies next to the frozen ones.
- Fix: the package copy renames those three to `*.v.stale` (they are not part of
  any filelist) **and** `01_build.tcl` now parses `syn_1/a1_board.prj` and
  aborts unless `f9p_camera_display_core.v` and `p2_a1_board_top.v` appear
  exactly once from `T10.b18-b17-b/r0/changed-src` with no `./src/<either>`.
- Verification: `P2_PRJ_GUARD_PASS` in `r0/td/build_console_r0.log`.
- For future merges: `a1_board.al` also carries absolute source paths; rewrite
  them together with the scripts or bitgen opens the *other* task's sources.

## L4. Geometry gates belong to the chain TB, not to the camera core
- The B tap cannot be driven in ASE (D-PHY receiver), so the honest split is:
  geometry/CRC/zlib at the `u_a1` boundary (T1/T3/T4) and tap selection
  statically (C17) plus dynamically on the real top (L2).  Do not claim the
  photo-site B path is simulated.

## L5. CAM_SEL is bit 12, not bit 20
- b14 r1 measured it on the board (`T10.b14-cam-b/r1/CAM_SEL-bit-index-finding.md`);
  the b14 RTL comment said `bit20`.  The merged top comments and
  `r0/board/check_b18_board.py` gate on `(cam13 >> 12) & 1 == 1` and
  additionally require bit 20 == 0.
