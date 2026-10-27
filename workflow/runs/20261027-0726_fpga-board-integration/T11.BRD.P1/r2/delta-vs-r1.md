# delta-vs-r1.md — T11.BRD.P1 round 2 (what changed and what did not)

Round 2 is a **test/evidence repair**, not a design change.

| class | r2 status |
|---|---|
| `rtl/**` | **delta 0** — all 16 files byte-identical to r1 (`evidence/r1-r2-sha-diff.md`) |
| `constraints/**` | **delta 0** — `.sdc` + `.adc` byte-identical to r1 |
| `filelist.tcl` | **delta 0** — byte-identical to `handoff/brd-p1-r1-20261027/filelist.tcl` (sha256 `41A61493…A84A3`) |
| DUT / P4 / img / b20 sources | untouched; no RTL edit was made to fit any golden |
| judged criteria | **tightened, not weakened**: `raw == pk_bytes` was demoted to an additional self-consistency check and `raw == expected_raw` (independent model) became the G1 byte criterion |

## 1. Changed files (r2 work root)

| file | change | reason |
|---|---|---|
| `sim/tb_brd_g1_r2.v` | new (from `tb_brd_g1_r1.v`): 10-bit `reg [9:0] cam_val` latch, blocking assignment, then `{4{cam_val}}`; stimulus probe (`tb_probe_r2.txt`, `stim_*` in `sim_meta.txt`, `STIM_PROBE=` marker) | fix `T11.BRD.P1:TB_CAM_STIMULUS_WIDTH` (r1 V1) and make the stimulus observable |
| `sim/run_sim_r2.ps1` | new: compiles r2 RTL + r2 TB, per-scenario dump directory (`sim/scen0` … `sim/prep`, `sim/arb`), per-run `.do` file with `cd` + `vsim` + `run -all`, wall-clock timeout, `SIM_SECONDS` | prevent a diagnostic run from overwriting candidate dumps (r1 lost the scen0 dump and had to restore it) |
| `evidence/gen_expected_raw.py` (+ `.bin`, `.json`, `.log`) | new: independent RAW10 contract model, 3840 B | independent byte criterion (no DUT output read) |
| `evidence/verify_slot_r2.py` (+ `.log`) | new: 150 checks over SCEN0/3/4/prep dumps, cross-run stability and the negative/arbiter logs | r1's verifier compared raw against the DUT's own `pk_bytes.bin` |
| `evidence/golden-r2.md`, `golden-r2.json` | new | re-frozen golden; independent vs candidate-bound values separated |
| `evidence/r1_r2_sha_diff.py`, `r1-r2-sha-diff.md`, `r1-r2-sha-diff.log` | new | S1 delta contract (`rtl/constraints/filelist delta = 0`) |
| `evidence/static_checks_r2.py` (+ log) | new | G0 static regression + r1/r0 freeze integrity + G5 package/binding |
| `evidence/tb-stimulus-fix.md` | new | V1 root cause, fix lines, probe evidence, no-lag proof |
| `evidence/filelist-check.log` | new | `CHECK_FILELIST=PASS`, 78 sources, N2-fixed JSON |
| `evidence/delta-vs-r1.md` | this file | change register |
| `filelist.tcl` | copied byte-identical from the r1 package | r2 must publish the same frozen source list |
| `gen_manifest_r2.py`, `manifest-brd-p1-r2.json` | new | re-freeze with `parent_manifest_sha256 = 304A2FF0…` |
| `README.md`, `result-r2.md`, `lessons-r2.md`, `build-entry.md` | new | r2 documentation |
| `sim/**` dumps + logs | new | candidate evidence lives in per-scenario directories only |

## 2. Files carried from r1 without modification (same input bytes)

These are copies of r1 artefacts whose content is still exactly true for r2
(RTL/constraints are identical, the r0 hash table is unchanged):

| file | note |
|---|---|
| `cdc-list.md` | C1–C9 table for the unchanged datapath (r1 SHA preserved) |
| `evidence/sdc-groups.md` | six-group analysis of the byte-identical SDC |
| `evidence/cdc-static.log` | static CDC grep log for the byte-identical RTL |
| `evidence/adler-rootcause.md` | D7 root-cause analysis (facts unchanged; D7 closed without a delta) |
| `evidence/tb-fix-notes.md` | r1 TB defect table (T1–T10); still the correct history |
| `evidence/historical-evidence-sha256.json` | r0 evidence hash table (historical, read-only) |

Their SHAs are recorded in the r2 manifest; the r1 originals were not modified
(`static_checks_r2.py`: `r1_manifest_files_unchanged`, 218/218).

## 3. Handoff package

`handoff/brd-p1-r2-20261027/` is a new directory. Relative to
`handoff/brd-p1-r1-20261027/`:

- new: `README.md` (r2 change notice, path-resolution note, N2/N3 fixes),
  `known-risks.md` (D7 facts/reopen condition, N1 restated),
  `expected-g1.md` (r2 golden), `prohibitions.md` (r2 additions),
  `build/filelist-sha256.json` (repo-relative paths, N2), `manifest-brd-p1-r2.json`,
  `result-r2.md`;
- **removed**: `build/brd_board.al` (N3 — it carried 81 absolute paths; the
  package now ships only `brd_board.al.tmpl` + `gen_al.py`);
- byte-identical to r1: `filelist.tcl`, `constraints/**`, `rtl/**`,
  `external/**`, `cdc-list.md`, `historical-evidence-sha256.json`,
  `a1u1-header-contract.md` (only the TB filename mention was updated to r2) and
  the `build/0*.tcl` / `build.tcl` entry points apart from the r2 package path.

## 4. Explicit non-changes (review checklist)

- No RTL, constraint or filelist edit; `rtl_delta = constraints_delta =
  filelist_delta = 0`.
- No threshold relaxation, no deleted negative test, no "not applicable" on a
  required layer. `raw == pk_bytes` can no longer turn a run green on its own.
- No candidate dump was overwritten: every scenario writes into its own
  directory, and there is no diagnostic/variant run in r2 at all.
- No local TD/synthesis/route/STA/bitgen/CWC/JTAG/COM/download/Flash; no
  commit/push; no contact with the teammate.
- `G2p = teammate_required`, `G3/G4 = awaiting_hardware`; no local pass/fail is
  claimed for them.
