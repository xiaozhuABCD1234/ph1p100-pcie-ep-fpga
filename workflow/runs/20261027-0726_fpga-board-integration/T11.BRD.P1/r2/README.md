# T11.BRD.P1 — round 2 work root (repo)

This directory is the **only** new source/simulation/evidence work root for
round 2 of `T11.BRD.P1`, inside the authoritative FPGA repository:

`workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/`

Round 1 (`../r1/`) is a frozen, read-only input: manifest
`304A2FF08DA88B6F129577D710A5B077B9FCF0A71F205E72BFB03412616CCC05`, 218 files,
`stopped_modifying=true`. Nothing under `r1/` was modified in round 2
(`evidence/static_checks_r2.py`: `r1_manifest_files_unchanged`).

## Directory contract

| path | content |
|---|---|
| `rtl/` | byte-identical to `r1/rtl/` (16 files) — `a1_core_fix01/` is `alias_of_b20`, not a behavioural variant |
| `constraints/` | byte-identical to `r1/constraints/` (`brd_board.sdc`, `ph1p_pcie_case_ep.adc`) |
| `filelist.tcl` | byte-identical to the r1 package filelist (78 sources) |
| `sim/` | r2 testbench (`tb_brd_g1_r2.v`), runner (`run_sim_r2.ps1`), per-scenario dump dirs, logs |
| `evidence/` | independent model, verifier, golden, delta/SHA tables, static + G5 checks, carried r1 analysis |
| `manifest-brd-p1-r2.json` | frozen round-2 manifest (all hashes) |
| `result-r2.md` | round-2 result (done / not done separated) |
| `delta-vs-r1.md` | change register (what changed, what stayed byte-identical) |
| `lessons-r2.md` | reusable root causes/triggers/fixes |
| teammate package | `handoff/brd-p1-r2-20261027/` (separate directory) |

## SIMULATION MAP (frozen r2 TB)

| scenario | command (from `sim/`) | dump dir |
|---|---|---|
| SCEN0 late ARM, bypass | `powershell -File run_sim_r2.ps1 -Test tb_brd_g1_top -Scen 0` | `sim/scen0` |
| SCEN3 early ARM (doubled) | `… -Scen 3` | `sim/scen3` |
| SCEN4 duplicate ARM | `… -Scen 4` | `sim/scen4` |
| SCEN1 missing EOF | `… -Scen 1` | `sim/scen1` (no dumps by design) |
| SCEN2 wrong ACK | `… -Scen 2` | `sim/scen2` (no dumps by design) |
| PREP=1/PRED=1 | `… -Scen 0 -Prep 1 -Pred 1` | `sim/prep` |
| read arbiter (6 checks) | `… -Test tb_brd_arb` | `sim/arb` |

Verify: `python evidence/gen_expected_raw.py` then `python evidence/verify_slot_r2.py`.
Each dump directory contains a `work` **junction** to `sim/work` (the library
must be resolvable after the runner `cd`s into the dump directory); it is not a
copy and it is not part of the manifest.

## Read-only sources (never modified)

- r1 work root and package (`workflow/.../T11.BRD.P1/r1/**`,
  `handoff/brd-p1-r1-20261027/**`) — frozen r1 candidate.
- `handoff/fpga-sim-only-20261027/inputs/**` — P4 r2, img, mem, b18, b20,
  board-filelist snapshots.
- repo `rtl/`, `al_ip/`, `constraints/`; old workspace `D:/fpga/ph1p100/...`
  (r0 manifests + reference top only).

## Hard boundaries

- Simulation/static/evidence only: **no** TD, synthesis, route, STA, bitgen,
  CWC, JTAG/COM, download or Flash locally.
- No commit/push; no automatic contact with the teammate.
- Repo-relative paths everywhere; no `D:/fpga/ph1p100` absolute path in the
  filelist or the handoff package.
- No r3 files, no b20 bitstream/CWC, no rewrite of old runs/reports/manifests.
- Local PASS means G1 + G0 + G5 only; `G2p = teammate_required`,
  `G3/G4 = awaiting_hardware`.
