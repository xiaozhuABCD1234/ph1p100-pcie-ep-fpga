# T11.BRD.P1 — round 2 result (local scope)

## 0. Inherited facts (frozen; not rewritten)

- r1 integrated verdict: **FAIL**, single blocking problem
  `T11.BRD.P1:TB_CAM_STIMULUS_WIDTH` (functional); engineering pass (local);
  system not_run. r1 manifest `304A2FF0…` (218 files) is unchanged.
- Round 2 is the **2nd actual fix round** (1 of 3 remaining before this round).
- **Local boundary (2026-10-27 AGENTS)**: RTL simulation, software/byte checks,
  static interface/constraint checks and evidence only. **No TD synthesis,
  route, STA, bitgen, CWC, JTAG/COM, download or Flash** was run (0 times).
  `G2p = teammate_required` (`not_run`), `G3/G4 = awaiting_hardware`.

## 1. What changed in round 2 (RTL delta = 0)

| item | change |
|---|---|
| `sim/tb_brd_g1_r2.v` | camera stimulus now latches a 10-bit `cam_val` (blocking) and then `{4{cam_val}}`; added a stimulus probe (`tb_probe_r2.txt`, `stim_*` in `sim_meta.txt`, `STIM_PROBE=` marker) |
| `sim/run_sim_r2.ps1` | compiles the r2 RTL/TB; every scenario writes into its **own** dump directory (`sim/scen0`…`scen4`, `sim/prep`, `sim/arb`); per-run `.do` with `cd` + `vsim` + `run -all` |
| `evidence/gen_expected_raw.py` | **independent** 3840 B RAW10 model, contract only (no DUT output read) |
| `evidence/verify_slot_r2.py` | 150 checks; `raw == expected_raw` is the byte criterion, `raw == pk_bytes` demoted to additional |
| `evidence/golden-r2.md` / `.json` | re-frozen golden, independent vs candidate-bound values separated |
| `evidence/static_checks_r2.py`, `verify_manifest_r2.py`, `g5_refs_r2.py`, `r1_r2_sha_diff.py` | G0/G5/delta/freeze checks |
| `handoff/brd-p1-r2-20261027/**` | new teammate package (N2/N3 fixed, new golden, D7 facts + reopen condition) |
| `rtl/**`, `constraints/**`, `filelist.tcl` | **byte-identical to r1** (`rtl_delta=0`, `constraints_delta=0`, `filelist_delta=0`) |

No DUT/P4/img/b20 source was edited. No threshold was relaxed and no negative
test was removed.

## 2. G1 — actual local results (ModelSim ASE 10.5b, 64×48 ROI)

| scenario | run log | result |
|---|---|---|
| SCEN0 late ARM, bypass | `sim/run_scen0_r2.log` | **PASS**: exported=1, 32 MWr × 128 B = 4096 B, doorbell=1 (payload=held_seq=1), slot `0x1_0000` starts `78 9c`, legacy base 0 unused, 0 TLP mismatch, 0 X, correct ACK → release+1 |
| SCEN3 early ARM (doubled) | `sim/run_scen3_r2.log` | **PASS**: one export, identical slot stream |
| SCEN4 duplicate ARM while armed/held | `sim/run_scen4_r2.log` | **PASS**: `arm_ignored ≥ 1`, one export, identical slot stream |
| SCEN1 missing EOF (last ROI row absent) | `sim/run_scen1_r2.log` | **PASS negative**: committed=0 published=0 exported=0, 0 TLP, 0 doorbell, aborted + released |
| SCEN2 wrong ACK → correct ACK | `sim/run_scen2_r2.log` | **PASS negative**: held stays and no release on `held_seq^1`; correct `held_seq` → release+1 |
| `prep` PREP=1/PRED=1 | `sim/run_prep_r2.log` | **PASS**: 32 MWr/4096 B, standard zlib decodes 3840 B, header/transport OK |
| `tb_brd_arb` (6 checks) | `sim/run_arb_r2.log` | **PASS 6/6**: no mid-burst handover, bridge single beat, late/orphan beat counted once and not rerouted, `o_switch_err=0` |

**Independent byte criterion (the r1 FAIL):** `zlib.decompress(slot)` equals
`expected_raw.bin` **byte-for-byte in 3/3 bypass scenarios** (SCEN0/3/4).
`verify_slot_r2.py`: `CHECKS=150 FAILS=0 VERIFY_R2=PASS`.

| independent quantity | value |
|---|---|
| expected raw (contract model) | 3840 B, SHA256 `FBA49D330DB9196A9BD9B8F29419A5603CEF600FE7D08F73708674F4C3C5111E` |
| Adler-32 (last 4 B, big-endian) | `392578F9` |
| CRC-32 (header `xform_crc`/`raw_crc`, DUT status) | `7269454A` |
| decompressed length = `xform_len` | 3840 |
| `frame_bytes` / MWr | 4096 / 32 × 128 B |
| doorbell | 1, payload = `held_seq` |
| first packed bytes / first group | `82 82 82 82 00` / `v = 520` |
| stimulus probe | `lane_bad=0`, `chain_bad=0`, `first_v=520`, `pk_first=0082828282` (`STIM_PROBE=PASS` ×4) |

Candidate-bound (repeatability only, **not** a contract): bypass
`stream_len=2470`, `hcrc=5436BF73`, `stream_crc=9909B919`, identical in
SCEN0/3/4; PREP=1/PRED=1 `stream_len=538`, `hcrc=981E85CF`, `xform_crc=7883ABAF`.

**PREP=1/PRED=1 substitute criteria** (the transform domain is not the packed
raw domain, so it cannot be byte-compared with `expected_raw`; documented in
`evidence/golden-r2.md` §4 and `expected-g1.md` §3): standard zlib decodes the
slot; decompressed length = `xform_len` = 3840; tail = Adler-32 of the decoded
bytes (`5F1669E1`); header `raw_crc = 7269454A` (**the raw domain is still the
contract raw** — an independent check); `xform_crc (7883ABAF) ≠ raw_crc`;
header CRC/payload/transport/doorbell/0 X as above. No check is skipped.

## 3. Golden re-freeze (source and parameters)

- Source: `evidence/gen_expected_raw.py` → `expected_raw.bin` (contract only),
  `zlib.adler32` / `zlib.crc32` over that file, plus the frozen D6 header
  contract. Compressor recorded: **CPython 3.11.5 `zlib`**; reference encoder
  `zlib.compress(raw)` default level (`-1` == 6, header `78 9c`).
- **The compressed byte length is deliberately not a judged criterion.** Proof
  from r1: CPython zlib needs 1391 B for the r1 raw while the DUT emitted
  3137 B, both with Adler `c49f41ae` — the DUT's `a1_deflate_core` is a different
  RFC1950 encoder. Requiring equality would judge the encoder's match policy,
  not the D7/C1–C6 contract. `stream_len`/`hcrc` are recorded as
  candidate-bound repeatability values.
- r1 values (3137 / 3966 / `1263f0ea`) and the r1 tester's lagged fix variant
  (2510) are cross-references only.

## 4. G0 / G5 — static (local)

- `evidence/static-checks.log`: **STATIC_CHECKS_R2=PASS** — 43 top ports identical
  to `ph1p_pcie_ep_top`; R14 once and on `pcie_power_on_rst`; six SDC groups with
  one clock each and `clk_core` alone; only the two allowed false paths; no
  multicycle; C8/C9 2FF; F2 offsets; `rtl/constraints/filelist delta = 0`;
  r1 manifest 218/218 files unchanged; r0 manifest files unchanged; no
  `.bit`/`.cwc`; no r3 SHA anywhere; `a1_core_fix01` == b20 originals.
- `evidence/filelist-check.log`: **CHECK_FILELIST=PASS** — 78 sources, 0 missing,
  0 duplicate modules, 0 r3 paths, 0 guard failures; the SHA JSON is now
  repository-relative (**N2 fixed**).
- `evidence/g5-refs.log`: every file named by the r2 documents exists and is
  bound by the frozen manifest (**0 unbound**).
- Handoff package `handoff/brd-p1-r2-20261027/**`: filelist/constraints/top
  level/build entry/risks/expected/prohibitions, manifest + result copies;
  `build/brd_board.al` is **not** shipped (**N3 fixed** — `gen_al.py` must be run
  first); N1 (second `derive_clocks` in `brd_board.sdc`) is unchanged and
  restated for the teammate STA.
- `evidence/verify-manifest.log`: `VERIFY_MANIFEST_R2=PASS` — all manifest hashes
  recomputed after freezing.

## 5. G2p / bit / board (not local)

`not_run` / `teammate_required` / `awaiting_hardware`. r2's RTL/constraints/
filelist are byte-identical to r1, so a teammate r1 build with the same input
hash may be reused; otherwise re-run synth/route/STA/CDC on this filelist. r0's
`-2.273 ns / 79 endpoints` and the r3 `+0.072 ns` are not this candidate's
numbers. No bit/CWC exists locally.

## 6. D7 / Adler

Closed **without a delta**: the current candidate slot stream is a legal RFC1950
member and D7 is closed by independent evidence (standard `zlib.decompress`,
decompressed length = `xform_len`, raw = independent model, tail = independent
Adler-32, host-owned 44 B header, and the r1 evidence that zeroing the tail is
detected by standard zlib). `a1_core_fix01` remains byte-identical to the b20
originals (`alias_of_b20=true`, `behavioral_variant=false`,
`filelist_included=false`); no 4-byte delta was manufactured. This is **not** a
claim that an "Adler defect" was fixed. Reopen condition: a board/RK host that
observes an invalid tail or decode failure → separate task that first reproduces
the r0 condition.

## 7. Honest status and process deviations

- Local evidence supports G1 (including the independent byte criterion 3/3),
  G0 static and G5 binding. **The integrated tester judges**; this is not a board
  result: no real PCIe/RK, no real DDR, no A path, no 1080p30, no long-run, no
  routed bitstream.
- Simulation budget: top-level G1 scenario runs **6/10** (scen0, scen3, scen4,
  scen1, scen2, prep), `tb_brd_arb` **1/6**. Two additional vsim invocations
  failed at startup and advanced **no** simulation time (they are harness
  iterations, not scenario runs): (1) `cd` while a design was loaded,
  (2) `work` library not found after `cd` — fixed by a `work` junction per dump
  directory. Both logs are kept in `sim/` and are excluded from the PASS
  evidence.
- The r2 TB was frozen before the six scenario runs; no run was repeated after
  the golden was frozen, and no diagnostic/variant run exists in r2 (each
  scenario has its own dump directory, so nothing could be overwritten).
- G1 runs were ~2-8 s of simulator wall time each (limit 20 min/run).
- No production RTL/constraint/build script, old run, old report or old manifest
  was modified; no commit/push; the teammate was not contacted.

## 8. Evidence paths (repo-relative)

```text
workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/
  manifest-brd-p1-r2.json           result-r2.md            delta-vs-r1.md
  README.md  build-entry.md  lessons-r2.md  cdc-list.md  filelist.tcl
  sim/tb_brd_g1_r2.v  sim/run_sim_r2.ps1  sim/compile_r2.log
  sim/run_scen{0,1,2,3,4}_r2.log  sim/run_prep_r2.log  sim/run_arb_r2.log
  sim/scen0|scen3|scen4|prep/{slot_dump.bin,slotbase0_dump.bin,pk_bytes.bin,
                                a1u1_frame.bin,sim_meta.txt,tb_probe_r2.txt}
  evidence/gen_expected_raw.py/.log/.bin/.json
  evidence/verify_slot_r2.py/.log       evidence/golden-r2.md/.json
  evidence/static_checks_r2.py/.log     evidence/verify_manifest_r2.py/.log
  evidence/g5_refs_r2.py/.log           evidence/filelist-check.log
  evidence/r1_r2_sha_diff.py/.log       evidence/r1-r2-sha-diff.md
  evidence/tb-stimulus-fix.md           evidence/delta-vs-r1.md is at the root
  evidence/{sdc-groups.md,cdc-static.log,adler-rootcause.md,tb-fix-notes.md,
            historical-evidence-sha256.json}   (carried from r1, same bytes)
handoff/brd-p1-r2-20261027/**        (teammate package)
```
