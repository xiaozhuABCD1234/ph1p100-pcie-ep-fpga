# rollback — T11.runB-debug-rtl r3 (issue-02 fix)

- New bit (P1-fix3, NOT downloaded): debug-fix3/prj/ph1p_pcie_integration_Runs/phy_1/ph1p_pcie_integration.bit
  sha256=bfafdf97ff78d6f6d2646ffc706542a0bbbb7e11869043ba754cf68a270813d0 (5,224,027 B). Do NOT mix with older candidates.
- Previous debug candidates kept untouched in parallel: 2385cded...1873 (debug-fix, board-tested all-zero -> NOT_MATCHED) and e81d353b...2b9a (old production bit, rollback source).
- Upstream candidate is worktree-only (4 modified files) because shell git commit was denied in this round (permission.rejected); planner/user commits or opens permission.
  Files: rtl/ep_side/img/ep_bar_win.v, rtl/ep_side/pcie_ep_engine.v, rtl/ep_side/ph1p_pcie_ep_top.v, sim/tb/tb_ep_bar_win_debug.v.
- Rollback = git checkout -- <those 4 files> (or revert the eventual commit); build outputs under debug-fix3/prj may be removed as a directory after planner review (single-path deletes only).
- Production path untouched: DBG_CTRL_DEFAULT_EN=0 disables the generate block; new ports/nets are unused in production.