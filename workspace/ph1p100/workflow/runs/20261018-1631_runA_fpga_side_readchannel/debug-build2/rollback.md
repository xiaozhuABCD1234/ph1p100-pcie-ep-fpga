# Rollback — P1-fix3 candidate (T11.runB-debug-build P2 re-freeze)

- New debug bit (NOT downloaded): `debug-fix3/prj/ph1p_pcie_integration_Runs/phy_1/ph1p_pcie_integration.bit`
  SHA256 `bfafdf97ff78d6f6d2646ffc706542a0bbbb7e11869043ba754cf68a270813d0` (5224027 B). Do not mix with older candidates.
- Prior debug bit (NOT_MATCHED, all-zero): `2385cded…1873` at `debug-fix/prj/.../ph1p_pcie_integration.bit`; kept as evidence only.
- Older production bit (rollback source): `e81d353b…2b9a` at upstream build output / prior evidence; kept in place.
- Source: 4 worktree-only files at HEAD `b0282d2a…`; commit_status `BLOCKED_PENDING_ACCEPTED_WORKTREE_ONLY`; candidate.diff in `debug-fix3/candidate.diff`.
  Files: `rtl/ep_side/img/ep_bar_win.v`, `rtl/ep_side/pcie_ep_engine.v`, `rtl/ep_side/ph1p_pcie_ep_top.v`, `sim/tb/tb_ep_bar_win_debug.v`.
- Board rollback: power cycle clears SRAM, or re-download old bit `e81d353b…` via `-mode jtag` (~30–40 s). No Flash.
- Source rollback: `git checkout -- <the 4 files>` (or revert the eventual commit). Do not delete evidence or use batch deletion.
