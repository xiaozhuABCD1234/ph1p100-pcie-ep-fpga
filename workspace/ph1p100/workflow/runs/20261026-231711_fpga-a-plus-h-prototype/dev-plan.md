# Dev plan — A+H isolated RTL prototype

- run: `20261026-231711_fpga-a-plus-h-prototype`
- project root / actual worktree: `D:/fpga/ph1p100`
- output dir: `D:/fpga/ph1p100/workflow/runs/20261026-231711_fpga-a-plus-h-prototype`
- batch size: **1** (default; the user did not approve a batch). New developer and new integrated tester per task; no reuse across tasks.
- levels: requirement → work package (2 levels). 3 packages, each ≤5 semantic steps.
- **One main goal**: an isolated, offline RTL prototype that implements H first and then A+H, with byte-identical A1U1/zlib output and a measured S_ss for N/L. TD/board are not part of this run.
- **No TD / synthesis / P&R / bitgen / CWC / download / Flash / board / COM / JTAG / RK / network** in any package. A simulation PASS only qualifies a later, separately authorised TD package.

## 1. Task table

| task_id | problem / product | worktree / write scope | depends on | functional | engineering | system | G layers | status | next action |
|---|---|---|---|---|---|---|---|---|---|
| `T10.ah-honly` | H-only: 2 B/cycle replay + 16-bit core→frame_top; baseline control; N/L 1-frame probes; byte-exact; cycles/B; resource estimate | `D:/fpga/ph1p100`; write only `.../T10.ah-honly/**`, `.../test-reports/T10.ah-honly-*/**`, `%TEMP%/opencode/a-plus-h/T10.ah-honly/**` | none | baseline control exact, bench SHA, frame-1 header, deterministic counters, no stall/timeout | manifest 100 %, frozen copies unchanged, isolated libs, no TD, resource estimate | external 32-bit packing/A1U1/geometry/clock/content unchanged | G1; G0 n/a (probe); G2–G4 n/a | **ready** | dispatch developer (`fpga-dev`) |
| `T10.ah-a-plus-h` | A+H: add 2-position literal scan + dual-symbol packer on the frozen H candidate; N/L 4-frame S_ss ≤6.25 M; 4-frame byte-exact; kill/fallback | `D:/fpga/ph1p100`; write only `.../T10.ah-a-plus-h/**`, `.../test-reports/T10.ah-a-plus-h-*/**`, `%TEMP%/opencode/a-plus-h/T10.ah-a-plus-h/**` | **P1 PASS** (H N 1-frame ≤6,500,000 and byte-exact) | N/L S_ss ≤6.25 M; all 4 frame headers equal baseline; deterministic counters | manifest, frozen H candidate, no TD, resource/timing-risk estimate | external protocol/packing unchanged; scope/no overclaim | G0 + G1; G2–G4 n/a | **blocked** | wait for P1 PASS + planner release |
| `T10.ah-verdict` | prototype verdict + handoff: whether S_ss gate met, whether to request TD/timing; never claim G0 closed | `.../T10.ah-verdict/**` only | P1/P2 results | verdict values consistent with reports | evidence binding, manifest/hash traceability | scope/limitations, no closure claim | G1; G0 n/a (no new measurement) | **blocked** | planner closeout after P2 (or after P1 if P2 stays blocked) |

- Parent: `T10` in `workflow/tasks.json` stays active/blocked; this offline prototype does not set it done and does not modify `tasks.json`.
- `T10.ah-*` are local labels under the existing T10 global task, not new global task IDs.

## 2. Package P1 — `T10.ah-honly` (H only)

**Problem**: the frozen b11 core replays the fixed-Huffman candidate at ~2 cycles per stream byte. H widens the replay to 2 B/cycle and the internal core→frame_top transfer to 2 bytes, so the replay phase approaches 1 cycle/B. H alone is modelled at N 6,260,648 / L 5,888,933 and is expected to remain 0.17 % short of G0 on N; its purpose is to prove H correct, byte-exact and measurable before A is attempted.

**Actual worktree / write scope**: `D:/fpga/ph1p100`; edits only in `.../T10.ah-honly/r0/changed-src/**`; frozen copies in `src/`; logs/caps in `sim/`; scratch in `%TEMP%/opencode/a-plus-h/T10.ah-honly/**`. No edit of `src/`, other runs, production, upstream, work, docs, tasks.json or `.agents`.

**Products**:
- `T10.ah-honly/r0/src/` — 12 frozen DUT + `tb_ss_4run_wd.v` + `tb_ss_4run_wd_probe.v`; b6 bench TB + `comp/rand` vectors; all hashes recorded.
- `T10.ah-honly/r0/changed-src/` — modified `a1_deflate_core.v` + `a1_frame_top.v`; the extended TB and the 16-bit bench TB copy; `DIFF-h.md`.
- `T10.ah-honly/r0/sim/` — `modelsim.ini`, `base/work`, `h/work`, `logs/`, `caps/`, `commands.jsonl`; each build has its own library and log.
- `T10.ah-honly/r0/out/` — `baseline-control.json` (S_ss, frame-1 core_interval, 4 headers per content), `h-bench.json`, `h-probe-n.json`, `h-probe-l.json`, `byte-exact.json`, `cycles.json`, `resource-estimate.json`.
- `T10.ah-honly/r0/manifest-r0.json`, `result-r0.md`, `lessons-r0.md`.
- Tester: `test-reports/T10.ah-honly-r0-integrated.md`.

**Semantic steps (5)**:
1. **Freeze/copy + baseline control.** Copy the 12 frozen DUT + the two TBs + the b6 bench/vectors into `src/`; hash them. Add a passive per-frame `A1U1` header capture to the TB copy (no DUT change); run the frozen b11 core 4-frame N and L (`FRAMES=4, CONTENT=2, PACING=0, SINK=1, CAPTURE=0, MAX_CYCLES=60000000`). Require S_ss exactly 7,475,240 (N) / 6,986,952 (L), frame-1 `t_enc(1)−t_pub(1)` exactly 7,476,245 / 6,979,811, and capture the 4 per-frame headers. A mismatch is a control failure → blocked, not a new baseline.
2. **H core.** Parameterize the output (`OUT_BYTES`, default 1 for the frozen bench), add `out_keep`, rework cmem/replay to read 32 bits and emit 2 bytes/cycle with exact last-partial-word handling, and keep the packer write path lossless. No change to match selection, block format, fixed/stored decision, CRC or header.
3. **frame_top adapter.** Accept 1/2-byte transfers with the pending-byte rule; assemble the same 32-bit words, CRC and length; keep external ports and packing. Add the directed odd-length + `scnt=3` + backpressure unit checks.
4. **Byte-exact + probes.** Run the b6 bench (comp/rand) with the frozen 8-bit TB and the adapted 16-bit TB; require the frozen output SHAs and non-increasing cycles. Then run the N and L 1-frame probes (`FRAMES=1, MAX_CYCLES=13300000`, `CORE_STAGE` counters). Require frame-1 header CRC/len equal to the baseline and the deterministic counters (blocks/fixed/stored/literals/matches/cand_aborts/max_match/max_dist) equal; record `stat_stall` as a diagnostic (it is timing/pacing dependent and is not an equivalence gate). Record cycles/B, replay stalls, FIFO occupancy, out_valid duty.
5. **Freeze + report.** Stop modifying; compute `manifest-r0.json` (each artifact's path, bytes, SHA-256; `stopped_modifying=true`; `active_commands=0`; exact tool versions/commands; `previous_manifest` if any); write `byte-exact.json`, `cycles.json`, `resource-estimate.json`, `result-r0.md`, `lessons-r0.md`; state `H_pass`/`H_gap`/`H_fail`, the measured N/L cycles and the 6,500,000 release threshold.

**Runs (frozen, 4 full/probe + ≤4 bench)**:
| # | run | plusargs | cap |
|---|---|---|---|
| B1 | baseline b11 N 4-frame | FRAMES=4, CONTENT=2, PACING=0, SINK=1, CAPTURE=0, MAX=60000000 | 2,700 s |
| B2 | baseline b11 L 4-frame | same, `raw40_l.hex` | 2,700 s |
| H1 | H N 1-frame probe | FRAMES=1, MAX=13300000, probe TB | 900 s |
| H2 | H L 1-frame probe | same, `raw40_l.hex` | 900 s |
| b1–b4 | b6 bench comp/rand, 8-bit and 16-bit TB | `+BP=0 +GAP=0 +TIMEOUT=2000000` | 300 s each |

- Total full/probe ModelSim wall ≤7,200 s (120 min); total bench wall ≤1,200 s (20 min); dev wall ≤180 min; dev calls ≤60.
- If the baseline control fails, stop before H. If the 8-bit bench fails, do not run the 16-bit bench or the frames.
- H probe acceptance (for P1 verdict): frame-1 header/len and the deterministic counters equal baseline; N ≤6,390,000 and L ≤6,010,000 = "H near model"; N ≤6,500,000 = "H sufficient to release P2"; no SS_STALL/SS_STALL_COLD; probe `CORE_STAGE` present.
- **P2 release rule**: H N 1-frame ≤6,500,000 **and** byte-exact **and** no stall/timeout. If H is correct but >6,500,000, P1 may be PASS-with-gap but P2 stays blocked; P3 records kill/回退.

**Three-dimension checks**:
- functional: baseline control exact; b6 bench SHAs; frame-1 header/len/last byte; deterministic counters; probe `CORE_STAGE`; no X; no stall/timeout.
- engineering: manifest 100 % hash; `src/` byte-identical to the frozen P1/b11/b6 inputs; only `changed-src/` differs; isolated ModelSim libs/logs; no TD; resource estimate basis; no writes outside scope.
- system: external 32-bit packing, A1U1 header, geometry, clock, reset, content, sink/pacing unchanged; the 16-bit transfer is internal only; scope and not-proven list.
- G0: **not applicable** (H is not the 4-frame gate; no G0 claim). G1: applicable. G2/G3/G4: not applicable (0 TD/bitgen/board).

**Stop / fallback**:
- baseline control mismatch → `blocked` with the measured EVT/header evidence; do not proceed.
- bench byte mismatch after 2 fix attempts → `FAIL/blocked`; do not run frames.
- probe stall/timeout or missing `CORE_STAGE` → `partial/not_proven`.
- 16-bit adapter cannot be made byte-exact within budget → fall back to 8-bit H (port-limited), report the measured cycles/B and the 6.5 M release check; do not claim the model number.
- dev calls/time exhausted → `blocked/LIMIT_REACHED` with the last actual artifact path; no silent continuation.

## 3. Package P2 — `T10.ah-a-plus-h` (A+H)

**Problem**: H alone is modelled at 6.26 M on N (0.17 % short). A adds a 2-position literal scan (conservative −252,570 cycles) to reach the modelled 6.008 M. The package must measure N/L 4-frame S_ss ≤6.25 M and prove all 4 frames byte-identical. If A cannot preserve the sequential semantics, or the measured gain is insufficient, A is killed; no hard-fitting.

**Depends on**: P1 PASS per §2 release rule. The frozen H candidate (`changed-src` + manifest) is the starting point; the baseline control from P1 is the byte-exact reference.

**Products**:
- `T10.ah-a-plus-h/r0/src/` — frozen H candidate + baseline sources.
- `T10.ah-a-plus-h/r0/changed-src/` — A+H core/frame_top; `DIFF-a.md`.
- `T10.ah-a-plus-h/r0/out/` — `aplus-h-probe-n.json`, `aplus-h-n-4frame.json`, `aplus-h-l-4frame.json`, `byte-exact-4frame.json`, `cycles-b.json`, `resource-estimate.json`, `kill-fallback.json`.
- `manifest-r0.json`, `result-r0.md`, `lessons-r0.md`.
- Tester: `test-reports/T10.ah-a-plus-h-r0-integrated.md`.

**Semantic steps (5)**:
1. **Freeze H + A design.** Copy the frozen H candidate; implement the dual-position lookup/insert with the §7 equivalence guard (same-bucket/same-bank → single-issue fallback); implement the 2-symbol packer into the 32-bit cmem write path; keep all match/literal decisions and counters.
2. **Bench + N probe.** Run the b6 bench (8-bit and 16-bit) byte-exact; run the N 1-frame probe. If the frame-1 header differs or the probe cycles are not below the H probe by at least 100,000 cycles (no usable A gain), stop before the 4-frame runs.
3. **N 4-frame.** Run N 4 frames; require S_ss ≤6,250,000, 4 exp events, all 4 headers equal the P1 baseline control, the deterministic counters equal, no stall/timeout.
4. **L 4-frame.** Same for L; the L S_ss must also be ≤6,250,000.
5. **Freeze + report.** Stop modifying; write `manifest-r0.json` (path/bytes/SHA-256 per artifact, `stopped_modifying=true`, `active_commands=0`, tool versions/commands, `previous_manifest` = the frozen H manifest), the result files and `lessons-r0.md`; report the measured S_ss, cycles/B, A gain, A_killed flag, resource estimate and critical-path risk; give the kill/回退 recommendation.

**Runs (frozen, 3 full/probe + ≤2 bench)**:
| # | run | plusargs | cap |
|---|---|---|---|
| P | A+H N 1-frame probe | FRAMES=1, CONTENT=2, SINK=1, CAPTURE=0, MAX=13300000 | 1,200 s |
| N4 | A+H N 4-frame | FRAMES=4, MAX=60000000 | 2,700 s |
| L4 | A+H L 4-frame | same, `raw40_l.hex` | 2,700 s |
| b1–b2 | bench comp/rand | 16-bit TB | 300 s each |

- Total full/probe ≤7,200 s (120 min); bench ≤600 s; dev ≤180 min / ≤60 calls.
- If the probe fails byte-exact or shows no A gain, skip N4/L4 and report `A_killed`/`FAIL`; this is the intended early-stop.
- Gate: **N S_ss ≤6,250,000 AND L S_ss ≤6,250,000**, 4 frames each, all 4 headers equal the P1 baseline, deterministic counters equal, no stall/timeout. If one side fails, the package verdict is FAIL/partial with both measured values; no averaging, no 2/3-frame substitute.
- S_ss PASS is a **prototype S_ss gate**, not a G0 closure. Report `tail_frac` and `busy` for both contents; do not claim G0 closed.

**Three-dimension checks**:
- functional: probe + 4-frame S_ss; 4 frame headers/len/last byte; deterministic counters; no X; no stall/timeout; A equivalence/fallback frequency.
- engineering: manifest; H candidate unchanged except A edits; isolated libs; no TD; resource estimate; A kill evidence if killed.
- system: external protocol/packing/A1U1/geometry/clock/content/sink unchanged; scope; no G0 claim; no board.
- G0: applicable (S_ss gate only). G1: applicable. G2/G3/G4: not applicable.

**Stop / fallback**:
- A breaks the deterministic counters or frame bytes after 2 fix attempts → kill A; report H-only and `A_killed=true`.
- A gain < 100,000 cycles on the N probe → stop before 4-frame; report the measured gain and kill.
- N or L S_ss > 6,250,000 → FAIL with the numbers; no hard-fitting, no clock change, no threshold relaxation.
- 3 repair rounds max (round0 + 3 real repair rounds per the project rule); after that keep ⚠ not passed and let the planner decide.
- dev budget exhausted → `blocked/LIMIT_REACHED` with the last actual evidence path.

## 4. Package P3 — `T10.ah-verdict` (prototype verdict / handoff, optional, 0 sim)

**Role**: fpga-planner (closeout), not a developer/tester. **0 sim, 0 TD, 0 board.**

**Products**: `T10.ah-verdict/prototype-verdict.json`, `handoff.md`, `final-summary.md`, `user-summary.md` (run root as the project convention).

**Content**:
- H result: measured N/L 1-frame cycles, cycles/B, byte-exact, resource estimate.
- A+H result (if released): measured N/L S_ss, margin, byte-exact, A gain, A_killed flag, resource/timing risk.
- Explicit statements: **S_ss gate met/not met; G0 is not claimed closed; no TD/board/resource measurement; the A+H 45.034 % envelope remains**.
- TD request wording: only after a simulation PASS and a separate user authorization; proposed TD scope (187.5 MHz, WNS/hold, resources) but not executed.
- Kill/回退: if A/H+A fails, the exact rollback path (frozen b11/P1/P4 state; no production change).
- Next launch/recovery text.

**Acceptance**: every number traceable to a P1/P2 report; no "G0 closed"/"A+H done"/"TD PASS" claim; manifest hashes listed; the user summary is short and honest.

## 5. Budgets and execution limits (frozen)

| item | P1 | P2 | P3 |
|---|---|---|---|
| developer calls / wall | ≤60 / ≤180 min | ≤60 / ≤180 min | — |
| tester calls / wall | ≤45 / ≤90 min | ≤45 / ≤90 min | — |
| planner calls / wall | — | — | ≤15 / ≤30 min |
| full/probe vsim runs | exactly 4; ≤7,200 s total; 4-frame ≤2,700 s; probe ≤900 s | exactly 3; ≤7,200 s total; 4-frame ≤2,700 s; probe ≤1,200 s | 0 |
| bench vsim | ≤4 × 300 s, ≤1,200 s total | ≤2 × 300 s, ≤600 s total | 0 |
| TD / board / network | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| tester re-runs | 0 full/probe; bench ≤2 × 300 s | 0 full/probe; bench ≤2 × 300 s | 0 |

- Every command must have an executable timeout/kill; the per-run caps above are the actual safety limits, not the `yield` behavior.
- Planned full/probe runs are 4 (P1) / 3 (P2). A re-run is allowed only when a tool/compile failure invalidated the run, with the failure log/rc as new evidence; a baseline-control mismatch or a byte/exactness mismatch is **not** a re-run reason (it is a control/equivalence failure → blocked/FAIL). The total full/probe wall remains ≤7,200 s; a second re-run needs a planner decision.
- The developer's 60 calls include compile, bench, frames, hashing and reporting. The tester's 45 calls include independent parsing/hash verification; no full-frame re-run.
- A test may be re-run only once after a failure and only with new evidence or corrected parameters; no keyword/ID/directory workarounds.
- If a required tool/device/authorization is missing, return `blocked` immediately; do not burn the budget.

## 6. Order, dependency and dispatch

1. **P1 only is dispatched now.** The main spawns one `fpga-dev` for `T10.ah-honly` with the P1 input paths. P2 remains blocked until P1 returns PASS and the planner updates the dispatch.
2. After the developer stops modifying and freezes `manifest-r0.json`, the main spawns **one** integrated tester (`fpga-tester`) for the same task/manifest. The tester writes one integrated report with functional/engineering/system + G layers.
3. Same-task FAIL → the original developer and original tester repair/retest, round0 + up to 3 real repair rounds. No new IDs for the same task.
4. P1 PASS per §2 release rule → the planner updates `dispatch.json` to release `T10.ah-a-plus-h`. If P1 is PASS-with-gap or FAIL, P2 stays blocked and P3 records the result.
5. After P2 (PASS/FAIL/partial), the planner writes P3 verdict/handoff/final-summary/user-summary. No auto-continuation of remaining themes.

## 7. Acceptance summary

| item | threshold | package |
|---|---|---|
| baseline control S_ss | N exactly 7,475,240; L exactly 6,986,952 | P1 |
| baseline control frame-1 core_interval | N exactly 7,476,245; L exactly 6,979,811 | P1 |
| b6 bench output | comp SHA `2601d57c…a7c05` (50,310 B); rand SHA `54f262f2…496dd` (153,766 B) | P1/P2 |
| H 1-frame cycles | N ≤6,390,000 (near), ≤6,500,000 (P2 release); L ≤6,010,000 (near) | P1 |
| H frame-1 header | N 1,677,912 / 1,168,876,019 / 657,705,490; L 2,156,868 / 1,770,220,292 / 2,924,387,436 | P1 |
| A+H N/L S_ss | ≤6,250,000 each, 4 frames each | P2 |
| A+H frame headers | all 4 equal the P1 baseline control per content | P2 |
| counters | blocks/fixed/stored/literals/matches/cand_aborts/max_match/max_dist equal baseline | P1/P2 |
| resource | estimate vs 300 ERAM / 71,680 LUT6 / 143,360 REG; labelled estimate | P1/P2 |
| G0 | P1 n/a; P2 S_ss gate only; **never** "G0 closed" | P2/P3 |
| TD/board | 0 / 0 | all |

## 8. Explicit non-goals / protected

- No edit of `20261026-2138_fpga-integrated-delivery/**`, `20261026-144617_fpga-chain-detail-review/**`, b18/b19/b20, old P1–P4 frozen dirs, `fpga/csi2/src/**`, `upstream/**`, `D:/TD/work/csi2/**`, `D:/fpga_work/**`, `workflow/tasks.json`, `docs/**`, `work/**`, `.agents/**`.
- No TD/synthesis/P&R/bitgen/CWC/download/Flash/board/COM/JTAG/RK/network; no production change; no external message.
- No batch deletion; one explicit file at a time at most.
- No new clock, geometry, content, packing or protocol; the 16-bit core→frame_top transfer is internal and must not change the external byte stream.
- No "G0 closed", "A+H done", "TD PASS" or "board PASS" wording from any package; only P3 may state the S_ss gate and the open TD/board items.
- Offline sub-package completion does not set parent T10 done; G layers and task state are accounted separately.

## 9. Closeout inputs

- P1/P2 result reports and manifests; tester integrated reports; `out/*.json`; EVT/caps/logs; `DIFF-*.md`; `lessons-r0.md`.
- P3 writes `prototype-verdict.json`, `handoff.md`, `final-summary.md`, `user-summary.md`; the run's recovery entry is the run dir plus the original request. The final summary must list: what was actually measured, the unique candidate/manifest, the S_ss numbers, byte-exact evidence, resource/timing risk (estimate only), TD/board missing items (0), fallback, remaining themes (TD/timing package; A/H kill or continue; production integration), and the exact next launch text.
