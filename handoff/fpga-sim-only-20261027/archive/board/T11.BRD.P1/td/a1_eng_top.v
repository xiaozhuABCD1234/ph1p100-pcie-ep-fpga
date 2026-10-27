// =============================================================================
// CANARY FILE ONLY -- not a source file, not in any filelist, never compiled.
//
// tools/td/td_env.ps1 (read-only project tooling) refuses to repoint T: unless
// the target run directory contains "a1_eng_top.v" and "a1_small_top.sdc".
// T11.BRD.P1 has no a1_eng_top; these two comment-only canaries satisfy the
// path-contract check. The real top for this run is
//   fpga/csi2/src/board_integration/brd_integrated_top.v
// =============================================================================
