# dev-notes — T11.runB-debug-build (dev role)

## round1 (2026-10-18) — documentation-only fix after r0 FAIL

Trigger: integrated tester r0 FAIL (system dimension) — `debug-build/rollback.md` and
`debug-fix/rollback.md` still described the failed attempt ("BLOCKED / G2 FAIL, no CWC /
HEAD=8e1ef05f"), contradicting the frozen state (READY-FOR-P3, G2 PASS, HEAD=b0282d2a).

Actions (no rebuild, no candidate change):
1. Rewrote `debug-build/rollback.md`: frozen candidate `2385cded…` with paired CWC
   `fa24e258…` / BID `71330f16…`; old bit `e81d353b…` parallel fallback; SRAM re-download
   rollback, power-cycle SOP, no Flash; HEAD `b0282d2a`, clean, not pushed; `AFFC4396…`
   marked superseded/NOT READY; G3 explicitly not_run.
2. Rewrote `debug-fix/rollback.md` to the same frozen state (new bit READY-FOR-P3, commit
   `b0282d2a`, revert path) and removed the stale "NOT READY / worktree-only" text.
3. Updated `debug-build/candidate-manifest.json`: `rollback` is now an object with path,
   sha256 and bytes for both rollback documents; added the round1 `run_files` entries;
   re-freeze timestamp/notes updated. No bit/CWC/RTL/SDC/build-entry/commit change.

Verification: rollback docs re-read; all referenced hashes recomputed; candidate and
artifact hashes unchanged from r0; upstream HEAD `b0282d2a…`, worktree clean; old bit
`e81d353b…` unchanged. No TD, no hardware, no network, no push.
