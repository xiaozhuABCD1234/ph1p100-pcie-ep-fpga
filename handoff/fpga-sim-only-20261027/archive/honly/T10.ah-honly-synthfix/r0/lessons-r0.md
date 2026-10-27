# lessons-r0 — T10.ah-honly-synthfix

Reusable only (root cause / trigger / fix / verification entry). No narrative.

## 1. ModelSim hides the multi-driver that TD rejects

- **Trigger**: a `reg` driven from two `always @(posedge clk)` blocks (here the cmem
  write-port block and the main sequential reset branch). ModelSim resolves it as
  last-write-wins, so `vlog` reports `Errors: 0, Warnings: 0`; TD elaboration stops with
  `HDL-8007 ... constantly driven from multiple places` + `HDL-5007 another driver here`
  and turns the module into a black box (no gate DB).
- **Lesson**: for any candidate that will be synthesised, run a **static multi-driver
  scan** before spending a TD start; a clean `vlog` says nothing about elaborability.
- **Verification entry**: `%TEMP%/opencode/ah-synthfix/scan_multidriver.py <files>` ->
  `total_findings` / `cross_block_total` must be 0; artefacts `r0/scan/{pre,post}-scan.json`.

## 2. Merging a reset into a RAM write block: reset the registers, never the array

- **Trigger**: the three write-combine registers (`cmem_lo`, `cmem_lo_pend`,
  `cmem_lo_addr`) had their reset in a different block than their functional writes.
- **Fix that preserves RAM inference**: add `if (!rst_n) begin <regs> <= 0; end else if
  (<functional cond>)` **inside** the existing write-port block and delete the duplicate
  reset lines elsewhere; never assign the memory array in the reset branch (TD keeps
  emitting `HDL-1007 extracting RAM for identifier 'cmem'`).
- **Semantics**: both blocks were `always @(posedge clk)`, so this is a **synchronous**
  reset move — same edge, same values, no polarity/async change. The only theoretical
  side effect (a reset edge that coincides with an active write condition no longer
  performs the array write) is unobservable because reset discards all encoder state and
  every RAM word is rewritten before replay reads it.

## 3. Zero-change proof recipe that actually catches regressions here

- Static scan (0 findings) + 4 compiles (0/0) is not enough; the discriminating evidence is
  **exact** equality of: b6 payload SHA **of the decoded payload**, byte counts, cycle
  counts, `zlib.decompress` against the source vectors, adapter 12/12, 4-frame
  `.frm`/`.hdr` whole-file SHA, `S_ss` half-cycle-exact, and the full `.stats` key set.
- Any one of these moving means a real behaviour change; none may be relaxed.

## 4. Two tool traps hit while re-running the frozen flow

- `modelsim.ini` lives at `D:/intelFPGA/18.1/modelsim_ase/modelsim.ini`, **not** in
  `win32aloem/`; copy it into each fresh build dir before `vlib`.
- The b6 bench `*.stats` file is **whitespace key/value** (`out_bytes 50310`), while the
  4-frame `*.stats` is **`k=v`**; one parser for both silently yields -1/False. Two
  parsers, and assert the parsed values against the frozen numbers.
- The frozen bench "sha256" is the SHA of the **decoded payload**, not of the `out.hex`
  text file; hashing the hex file yields a false mismatch (4 wasted minutes, no re-run of
  the long sims).

## 5. Cost data for future planning

- vsim wall: N4 1,680 s, L4 1,655 s, benches 4.7–6.8 s, adapter 2.1 s; builds < 0.5 s each.
  The whole package fits in ~56 min of simulator wall time, so a `0 TD` synthesizability
  fix with full byte-exact regression is cheap compared with a wasted TD start (which
  costs a start-quota slot plus the trip back to planning).
- Copying the 5 TBs and 2 DUT files into the task directory (instead of editing the frozen
  candidate in place) made the "source immutability" check a one-line SHA comparison and
  let the diff be produced with `git diff --no-index` without touching a repository.
