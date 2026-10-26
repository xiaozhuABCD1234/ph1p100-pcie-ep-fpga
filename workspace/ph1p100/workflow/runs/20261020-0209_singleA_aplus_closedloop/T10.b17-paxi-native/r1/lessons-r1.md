# T10.b17-paxi-native r1 -- lessons

Date: 2026-10-26.  Scope: accept thin-margin diagnostic, 1 bitgen + 1 CWC from
the frozen r0 routed DB, one board attempt.  Result: `r1/result-r1.md`.

## 1. What made r1 cheap and safe

- The r0 routed DB (`a1_board_pr.db`, SHA256 `6033715A...9632`) is sufficient
  for bitgen and CWC: `open_project ./a1_board.al` + `import_db` reproduced the
  final STA (`SWNS 0.002 / STNS 0`, `0 Viol Endpoints / 26,705`) without any
  synthesis, place or route.  A separate `r1/td` with a copy of the DB, `src/`,
  the `.al` and the two Tcl scripts is enough; the 118 MB `a1_board_Runs` tree
  does not need to be copied, only `phy_1/{a1_board_pr.db,a1_board.prj,settings.cfg}`.
- Keeping r1 in its own directory preserved the frozen r0 candidate verbatim.
  This is the reusable pattern for "same route, new export" rounds.

## 2. Triggers and gotchas

- `open_project` **rewrites `a1_board.al`**: `Path="T:/"` -> `Path="T:/."`, adds
  `<UCode>00000011</UCode>`, normalizes `./src/...` -> `src/...`.  The 59-file
  source list and all 11 source hashes stay identical.  Record the input `.al`
  hash (r0: `038AFD52...365C`) before the run; do not treat the post-run `.al`
  hash as the design-input hash.  R1 stores both: inherited r0 hash and the
  post-run file hash.
- The dev-plan +0.003 ns floor is a **project policy gate**, not a TD check:
  `02_bitgen.tcl` only rejects negative setup/hold/period slack.  Therefore a
  planner waiver is required to cross the floor, and the result must carry
  `timing_caveat` plus "not production sign-off".  The waiver must be recorded
  in the result/manifest, never silently folded into "PASS".
- `03_cwc.tcl` is a strong anti-stale check: it refuses an existing
  `a1_board.cwc`/`cw/compiled.*`, requires `<phy_eram>` and rejects an
  incomplete `<logic_eram .../>`, and byte-compares `cw/compiled.bit` with the
  parent bit.  Both comparisons returned true in r1.  If `compiled.bit`
  differed, the export must not be used.
- CWC/BID sizes matching b15 (110,168 / 96,813 B) is **not** evidence of reuse;
  the SHA256 values differ.  Always compare hashes, and contrast against the
  previous candidate (r1 vs b15 hashes recorded in result §3).

## 3. Board branch

- FTDI/COM8 must be checked before any COM8 open.  `Get-PnpDevice -PresentOnly`
  plus `[System.IO.Ports.SerialPort]::GetPortNames()` is a quick, no-side-effect
  preflight; on this host only COM3/COM4 exist, so COM8 is absent and the branch
  is `board=blocked` with 0 downloads.
- Do not create a placeholder capture or "decode" an absent capture.  Without a
  download there is no r1 v6 data; the offline v6 evidence is inherited from r0
  and bound by the r0 manifest hash.
- The board script already gates download first and capture second; keeping that
  order is essential because hwserver/JTAG and the COM8 UART share the FTDI
  device.  On an absent device the script exits before starting hwserver.

## 4. What would change the next decision

- A board window is the only missing input: with FTDI present, run the existing
  script once (1 SRAM download, then 150 s COM8) and parse v6; do not alter the
  bit or scripts.
- +0.002 ns is acceptable only as a diagnostic.  Any production claim needs a
  new build that clears the +0.003 floor (or an explicit, separately recorded
  sign-off decision); do not "fix" it by relaxing SDC, changing seed or dropping
  v6 fields.
- If the board branch later shows per-frame timeout/retry/giveup 3/2/1 with
  `exported=0`, stop after one download and use the r0 v6 failure-AR evidence;
  the next investigation is the DDR MC/IP read-response side, not another
  bitstream.
