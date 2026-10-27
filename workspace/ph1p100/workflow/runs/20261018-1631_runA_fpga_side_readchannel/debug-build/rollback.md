# Rollback — T11.runB-debug-build (P2, round1 refreeze)

Current frozen candidate: **READY-FOR-P3** (P2 r0 PASS after round1; G2 PASS inherited from P1-fix r2).

## 1. Frozen identity (do not mix)

| Item | New candidate (this run) | Old fallback |
|---|---|---|
| Bit SHA256 | `2385cdedae1d9985687360af77341183517e34cb18be9cad0229291593411873` (5,224,027 B) | `e81d353b284cb4e99ec86bcd7d511691cda187254f801c4832916f0000692b9a` (5,224,023 B) |
| Paired CWC | `cw/compiled.cwc` = `fa24e25830fefe882edb3b4d9ab18de8fd39598a9822231b8622c9a0c73f22bb` (81,063 B) | none (old bit is the production candidate) |
| Paired BID | `ph1p_pcie_integration_inst.bid` = `71330f1630e250a7c805a68edfffc3a4683a9a4480191c99f95614eacc913ba1` (140,754 B) | old build BID in repo-build |
| Source commit | `b0282d2a8dfdf11e6e63779510fe380dfffb5e83` (parent `8e1ef05f…`) | `ab811c8f820c3ae6601507b54ec45a74c6607855` |
| Role | debug diagnostic candidate — **only SRAM, never Flash** | board-proven fallback |

- The new bit and the old bit are **parallel** and must never be mixed: the new bit only pairs with the CWC/BID above; the old bit only pairs with its own repo-build artifacts and commit `ab811c8f`.
- Superseded attempt bit `AFFC4396…` (`debug-build/prj_frozen/**`) is **NOT READY** evidence only; never download it and never mix it with this candidate.

## 2. Rollback procedure (SRAM only)

1. Stop the debug readback; keep the first-error evidence/UI as-is.
2. Re-download the **old bit** `e81d353b…` with `-mode jtag` from an ASCII path (verify SHA256 before download), ~30–40 s; this restores the known production image.
3. If DDR calibration is abnormal (D37 off / four LEDs), the user performs a physical power-off ≥10 s, power-on, then re-downloads the same old bit. Do not change cables/power/board wiring.
4. SRAM is volatile: a power cycle clears the FPGA image; no persistent change is made by either download.
5. **Never** issue flash/efuse/SPI/svf commands; the debug candidate is SRAM-only.

## 3. Source rollback (only if the planner asks)

- The upstream commit is `b0282d2a8dfdf11e6e63779510fe380dfffb5e83`; worktree is clean; not pushed.
- Source rollback = `git revert b0282d2a` (or checkout parent `8e1ef05f` by the planner). Do not amend/rebase/push as part of P3.
- Removing this run's generated artifacts must follow the root AGENTS single-file deletion rule; the old bit and older evidence stay in place.

## 4. Scope note

- G3 (board readback) is **not_run**; this document describes how to roll back, not a board-test result. P3 remains gated by the hardware-ready.md preconditions and the P2 r0 PASS.
