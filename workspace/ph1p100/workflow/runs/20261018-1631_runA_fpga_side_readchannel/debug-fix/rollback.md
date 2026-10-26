# rollback — T11.runB-debug-rtl P1-fix / P2 candidate (round1 refreeze)

Current state: the P1-fix output is the **P2 frozen candidate, READY-FOR-P3** (G2 PASS; G3 not_run).
The three source paths are committed in `b0282d2a8dfdf11e6e63779510fe380dfffb5e83` (parent `8e1ef05f…`); worktree clean; local only, not pushed.

## Frozen bit and pairing

- New debug bit: `debug-fix/prj/ph1p_pcie_integration_Runs/phy_1/ph1p_pcie_integration.bit`
  sha256=`2385cdedae1d9985687360af77341183517e34cb18be9cad0229291593411873` (5,224,027 B).
- Paired `cw/compiled.bit` has the same sha256; paired `cw/compiled.cwc` sha256=`fa24e25830fefe882edb3b4d9ab18de8fd39598a9822231b8622c9a0c73f22bb`; BID sha256=`71330f1630e250a7c805a68edfffc3a4683a9a4480191c99f95614eacc913ba1`.
- Only SRAM download (`-mode jtag`) is allowed; never Flash/efuse/SPI/svf.
- The old board-proven bit `e81d353b284cb4e99ec86bcd7d511691cda187254f801c4832916f0000692b9a` (paired commit `ab811c8f`) is untouched and remains the fallback. New and old bits are parallel, never mixed.
- Superseded P2-attempt bit `AFFC4396…` is NOT READY evidence only; never download/mix.

## Rollback steps

1. Board: re-download the old bit `e81d353b…` via SRAM `-mode jtag` from an ASCII path (verify SHA first, ~30–40 s). If DDR calibration is abnormal (D37 off), user power-off ≥10 s → power-on → re-download the same old bit. No cable/power/wiring changes.
2. Sources: `git revert b0282d2a8dfdf11e6e63779510fe380dfffb5e83` (or planner checkout of parent `8e1ef05f`). Do not amend/rebase/push.
3. Generated outputs under `debug-fix/prj` / `debug-build/prj_*` may be removed only by the planner/user, one explicit path at a time (root AGENTS: no batch deletion).
4. G3 is not_run: this file documents rollback, it does not claim a board test passed.
