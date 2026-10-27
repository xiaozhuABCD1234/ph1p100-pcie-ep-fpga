# Freeze notes — P2 lightweight re-freeze (2026-10-19)

- Candidate: P1-fix3 (issue-02 fix: debug snapshot reset decoupled from PCIe link; 9 words stay on `tl_clk_user`; identity/version/CTRL readable without link; DDR/CSI sources unchanged).
- P2 did **0 builds**; reuses P1-r3 build. G0/G1/G2 pass (G1/G2 inherited and independently checked in r3); G3/G4 not_run.
- Manifest: `debug-build2/candidate-manifest.json`（round3 重冻 SHA256 `e6d63702…a215`，11,105 B）；P1 manifest `fadbf3f0…` (11,795 B), r3 report `5A8BDBF9…`, diff `21D4A910…` (7,016 B; reverse-apply RC=0).
- Old candidates `e81d353b…` (rollback) and `2385cded…` (NOT_MATCHED evidence) remain parallel and untouched.
- Commit: **accepted as worktree-only** for this freeze. Reason: tester r3 PASS is bound to `debug-fix3` manifest with `commit_status=BLOCKED_PENDING`; changing HEAD now would invalidate that binding. Frozen bit/CWC are immutable; `candidate.diff` preserves source reproducibility. Not pushed.
- Optional user commit (no push), if desired after P3:
  ```
  cd upstream\ph1p100-pcie-ep-fpga
  git add rtl/ep_side/img/ep_bar_win.v rtl/ep_side/pcie_ep_engine.v rtl/ep_side/ph1p_pcie_ep_top.v sim/tb/tb_ep_bar_win_debug.v
  git commit -m "debug: decouple dbg snapshot reset from PCIe link (issue-02)"
  git rev-parse HEAD
  git status --short
  ```
  If committed later, record the new SHA separately; no need to re-freeze bit/CWC for P3.
- P2 recheck: one lightweight integrated report `T11.runB-debug-build-r2-integrated.md` (<=15 min/<=20 calls), no rebuild/hardware; checks hashes, bindings, READY wording, old candidates, zero download/Flash, worktree-only declaration.
- P3: new bit SRAM download (TD/BW, one attempt), user GUI two samples >=10 s; CLI readback remains closed. See `hardware-ready.md`.

## Round3 doc-only fix (2026-10-19)

- Trigger: integrated r2 **engineering FAIL** — `debug-fix3/candidate.diff` was corrupt (PowerShell pipeline re-encoding merged `+` lines; `git apply --check --reverse` RC=128 "corrupt patch at …:13").
- Re-exported from the current worktree with `git -C upstream diff --output=<ascii tmp> HEAD -- rtl/ep_side/img/ep_bar_win.v rtl/ep_side/pcie_ep_engine.v rtl/ep_side/ph1p_pcie_ep_top.v sim/tb/tb_ep_bar_win_debug.v`:
  sha256=`21D4A910C5CA74AD4C0526038112B806DAE9B83B67AC74409345B9BCD17FC492`, 7,016 B;
  `git apply --check --reverse` **RC=0**. Raw UTF-8/LF patch, no embedded header; base HEAD `b0282d2a…`.
- Fixed `hardware-ready.md` line 9: CWC map SHA256 = `b6127b21dd72eb9919c6fa57f3ade5cb9be365ccf731dc87036cf78354311b57` (was a path string). File sha256=`78060F3E6454DF2AE7B6432C8FBE7A8E5F9915B1DF6A6D968BC613E58838D275`, 4,025 B.
- Re-frozen `debug-build2/candidate-manifest.json`: sha256=`e6d6370252f3f7a5b6339097108099f2edb17ae54bc38434553d97761a56a215`, 11,105 B; 20/20 bindings + `hardware_ready` recomputed with 0 inconsistencies.
- No bit/CWC/RTL/constraint/commit change; HEAD remains `b0282d2a…`; the 4 source files remain worktree-only; not pushed; no TD/hardware/network.
