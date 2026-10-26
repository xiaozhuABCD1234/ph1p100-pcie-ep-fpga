# dev-plan -- T10.b18-b17-b (merged B + native PAXI + v6)

Run `20261020-0209_singleA_aplus_closedloop`. Planner: general (fpga-planner delegated).
Date 2026-10-26. Batch size 1. Formal packages: 1. Two levels: requirement -> work package.
Status: **ready** (r0 acceptance), `needs_user_input=false`, parent `T10` stays blocked.

## 0. Why this package

- b14 r1 proved the B front end is live on the board (4,470 frames, 1080p30, pix/line/crop exact,
  `CAM_SEL=bit12=1`) but had no PAXI fix -> `timeout 13,410 / retry 8,940 / giveup 4,470`,
  `enc 0 / exported 0`.
- b17 r0/r1 proved the native-PAXI repair + v6 offline (16/16 word readback, addresses 0/8/16...,
  `wstrb=0`, two full frames four-CRC+zlib, P1 three goldens, v6 273 B) but was built from the A-only
  b13 top and never reached the board (FTDI absent at its r1 preflight).
- The two defects are camera-independent and already isolated; the merged candidate is the first
  configuration where a live B stream meets a working DDR read path. One candidate, one board run.

Round accounting: b14 r1 closed FAIL (export gate) and b17 r1 closed blocked (FTDI). This is a new
task: round0 starts here, dev/tester are new slots, no rounds are inherited or transferred.

## 1. Verifiable deliverable

One frozen candidate (`r0`) with:
1. `r0/changed-src/` = 11 files per `merge-spec.md`, B tap + v6 + native PAXI coexisting.
2. `r0/sim/` evidence: B geometry chain, 16-word native readback, P1 three goldens, drop-R/retry,
   v6 structure incl. `cam_sysstat` bit12 = 1.
3. `r0/td/` one Routed database, 0 violations, `WNS >= +0.05` target, one bitgen + one CWC.
4. `r0/board/` one 150 s COM8 run if FTDI/COM8 present: timeout/retry/giveup deltas 0,
   enc/exported > 0, >= 1 frame four CRCs + zlib; otherwise `board=blocked` with preflight record.
5. `CANDIDATE-MANIFEST-b18-b17-b-r0.json` (hash of every input/output, `stopped_modifying=true`),
   `r0/result-r0.md`, `r0/lessons-r0.md`, `r0/check_merge_b18.py`, `r0/board/check_b18_board.py`.

## 2. Package table

| task_id | product | worktree / write scope | depends | functional | engineering | system | G | status |
|---|---|---|---|---|---|---|---|---|
| `T10.b18-b17-b` | merged B+v6+native-PAXI candidate, sim + build + one board run | `.../T10.b18-b17-b/r0/**` only | b17 r0 tree, b14 r0/r1 tree (read-only) | C01-C18 merge, T1-T6 sim | Routed/WNS/ERAM, 1 bitgen + 1 CWC, hash-bound | board preflight, v6 decode, export gate | G0/G1/G2/G3 | **ready** |

Only allowed writes: this package dir; the tester writes its report under `test-reports/`.

## 3. Semantic steps (5, in order)

### S1 Merge and static conformance (target 25 min)
Copy per `merge-spec.md` §1; apply the 8 `p2_a1_board_top.v` edits; copy b14 r1 SDC and b17 ADC;
rewrite `01_build.tcl` paths to this package; keep/add the b14 filelist guard (C16).
Write `check_merge_b18.py`, run it, record `r0/merge-conformance-r0.txt` with C01-C18.
No other file may change. Stop after 2 attempts on a failing check (return `blocked` with the check id).

### S2 Simulation (target 45 min)
Extend `../T10.b17-paxi-native/r0/sim/` (copy into `r0/sim/`, do not edit the originals):

| id | case | gate |
|---|---|---|
| T1 | B geometry chain (b14 S1 stimulus shape) | pix_beats 2,117,472; line_rises 2,192; frame_rises 1; frame_falls 1; crop_roi_frames 1; crop_groups 518,400; raw_len 2,592,000; enc=1; exported=1; four CRCs + strict zlib; no half frame |
| T2 | 16-word native readback | 16/16 match; addresses 0,8,...,120; `wstrb=0`; `low3/oob/wstrb` diag bits 0 |
| T3 | P1 three goldens (`micro8x2/mid64x8/full_grad`) | compressed bytes byte-identical to `../T10.b17-paxi-native/r0/sim/sim-results-b17-p1.json`; four CRC/zlib; dup=0 |
| T4 | drop 1 R -> timeout -> retry -> full frame; 3-frame run with middle retry | frame exports with four CRC+zlib; retry budget exhausted does not deadlock; giveup not taken |
| T5 | v6 structure + selected camera | 273 B / VER=6 / 67 fields / XOR; v5 still accepted; field #13 bit12 = 1; `diag_flags` bits1..5 = 0; `last_ar_low3=0`; single packet boundary, no mid-frame insert |
| T6 | CAM_SEL=0 static equivalence (with C17) | A branch line-identical to b13 wiring, 0 diffs |

Every case logs `vlog Errors:0` (no X on outputs), input hashes, and a JSON result under `r0/sim/`.
Simulation entry: `P:` project root, `W:` = `r0/sim`; per-case timeout 5 min, ModelSim ASE.

### S3 Build (target 30 min, TD session budget 3)
One synthesis + one route + one bitgen + one CWC (<=3 synth attempts, <=2 route attempts,
1 bitgen, 1 CWC). Gate:

- Routed `0` violated endpoints, hold >= 0, period check positive, `ERAM + CWC <= 300`;
- `WNS >= +0.05` target, **no caveat**; `+0.003 .. <+0.05` accepted only as diagnostic candidate
  with `timing_caveat` (b13 wording) and cannot claim production sign-off;
  `< +0.003` or any violation -> stop, no bitgen;
- bitgen re-checks final STA fail-closed (`SETUP/HOLD/PERIOD`); bit/CWC/BID hashes recorded;
  `cw/compiled.bit|.cwc` byte-identical to `td/a1_board.bit|.cwc`; CWC has `<phy_eram` entries and
  no incomplete `<logic_eram/>`;
- critical path report + violated-path list saved; if still only the A+ deflate cone, say so.

### S4 Board (target 20 min, 1 download)
`r0/board/run_board_b18.ps1`: FTDI preflight (`VID_0403&PID_6042`, COM8) -> if absent
`board=blocked`, 0 downloads, 0 COM8 -> stop. If present: 1 SRAM download with COM8 closed,
then open COM8 150 s, `parse_status_v6.py`, `check_b18_board.py`.
Gates: CAM_SEL bit12 = 1; 273/6/67 decode, `bad_xor=0`, 150 packets; `timeout/retry/giveup` deltas 0;
`enc_frames > 0`; `exported > 0`; >= 1 frame with four CRCs true and zlib decodable; no half frame;
B counters advancing; `raw_drop/raw_abort` not growing.
If `giveup` still grows: keep v6 `timeout_ar_addr/low3`, `last_issued_ar_addr`, `diag_flags`,
`inflight_state`, and **stop** (no second download, no re-capture, no Flash).

### S5 Freeze and hand off (10 min)
`stopped_modifying=true`; manifest over inputs + changed-src + scripts + TD/board artifacts;
`result-r0.md`, `lessons-r0.md`; return per relay contract (task_ids, status, artifact_paths,
manifest_path, test_input_paths, blocked, retest if repaired).

## 4. Three-dimension checks (one independent integrated tester)

Report `D:\fpga\ph1p100\test-reports\T10.b18-b17-b-r0-integrated.md`, first line one verdict title,
`dimension=integrated`, `dimension_results` covering functional / engineering / system.

| dimension | checks | G |
|---|---|---|
| functional | C01-C18, T1-T6, P1 byte identity, four CRC+zlib, v6 field #13 bit12, no half frame | G0/G1 |
| engineering | 0 violations, WNS/hold/period, ERAM+CWC, 1 bitgen+1 CWC, compiled identity, filelist guard, no SDC relaxation, hash binding | G2 |
| system | board preflight record, 1 download, 150 s decode, deltas, export gate, failed-AR capture, write scope, no Flash | G3 |

Not-applicable justification: none. Every dimension applies (sim + build + board).
If FTDI/COM8 is absent, system is `blocked` (preflight record required), not FAIL, and the task
must not be reported as board-passed.

## 5. Budget, stop, rollback

- Dev: **120 min / 60 calls**. TD: **3 sessions** (<=150 min total), synth <=3, route <=2,
  bitgen 1, CWC 1, download 1, Flash 0. Tester: 45 min / 30 calls. Planner: 15 min / 30 calls.
- Per problem: <=3 search/read loops, one retry of a failed command only with new evidence,
  2 consecutive no-progress -> `blocked`.
- Timeouts: read/search 60 s, local static/sim 5 min, build 30 min.
- Stop: C-check failure after 2 attempts; sim gate failure; 3 synth < target; 2 route still
  violated or < +0.003; bitgen/CWC fail; board giveup still growing; budget exhausted.
- Rollback: delete/ignore `T10.b18-b17-b/r0/**` only; b13/b14/b15/b17 trees and production files
  untouched. No batch delete (one explicit path at a time, or ask the user).

## 6. Entry points

- plan: this file, `merge-spec.md`, `input-index.md`, `fpga-design-guide.md`
- baseline source: `../T10.b17-paxi-native/r0/changed-src/`, `../T10.b14-cam-b/r0/changed-src/`
- SDC/ADC: `../T10.b14-cam-b/r1/td/p2_board.sdc`, `../T10.b17-paxi-native/r1/td/board_p2.adc`
- sim: `../T10.b17-paxi-native/r0/sim/` (copy), `../T10.b14-cam-b/r0/sim/tb_b14_chain.sv` (stimulus)
- TD: `../T10.b17-paxi-native/r0/td/*.tcl` (copy + path rewrite), `tools/td/td_env.ps1`
- board: `../T10.b14-cam-b/r1/board/run_board_r1.ps1`, `../T10.b17-paxi-native/r1/board/parse_status_v6.py`
- resume text: `恢复：D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b18-b17-b；本轮目标：<目标>`
