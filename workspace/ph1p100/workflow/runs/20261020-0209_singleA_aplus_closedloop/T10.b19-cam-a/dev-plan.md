# dev-plan -- T10.b19-cam-a (A camera on the b18-proven chain)

Run `20261020-0209_singleA_aplus_closedloop`. Package `T10.b19-cam-a`, round **r0**.
Planner: general (fpga-planner delegated). 2026-10-26. Batch size 1. Formal packages: 1.
Status: **ready**, `needs_user_input=false`. Parent `T10` stays active.

## 0. Why this package

- b18 proved the whole read/export chain on a **real B frame**: `FRAME id=1 1920x1080
  raw_len=2,592,000 stream_len=2,594,706 four_crcs=1 zlib_ok=1`, `exported=1 enc=2 raw_pub=4`,
  `ar=r=rlast=340,767`, `timeout/retry/giveup=0`, `sysstat=0x1F1D` (bit12=1). Evidence:
  `..\T10.b18-b17-b\r0\board\captures_full\` (bin SHA256 `143AA87D...09E4`).
- A was last tested on b13 (no PAXI fix, no retry): board `pix_beats=0`, 0 A1U1 frames. That does
  not isolate A because the read path was broken. One compile-time bit now decides it:
  `CAM_SEL=0` on the otherwise byte-identical b18 candidate.
- If A is alive, the same PAXI/retry/v6 chain should produce a full A frame. If A still has no
  pixels, the evidence is a camera-front-end/hardware conclusion; stop, do not rebuild.

Round accounting: `T10.b19-cam-a` is a new task; round0 starts here, new dev and new integrated
tester slots. b18 board evidence is an input, not an inherited round. b13 is historical evidence.

## 1. Verifiable deliverable

One frozen candidate `r0`:

1. `r0/changed-src/` = 11 b18 files, **10 byte-identical**, `p2_a1_board_top.v` differs by exactly
   one line (`CAM_SEL 1'b1 -> 1'b0`); `td/p2_board.sdc` and `td/board_p2.adc` byte-identical to b18.
2. `r0/sim/` evidence: A geometry chain, 16-word native readback, P1 three goldens, drop-R/retry,
   v6 (273/6/67, bit12=0), real-top CAM_SEL=0 stub test; `vlog Errors:0` everywhere.
3. `r0/td/` one Routed database, 0 violations, WNS target, one bitgen + one CWC.
4. `r0/board/` one SRAM download then one 300 s COM8 capture with reset alignment; A counters and
   export gate; or `board=blocked` (preflight/operator) / `blocked_A_no_pixels` with evidence.
5. `CANDIDATE-MANIFEST-b19-cam-a-r0.json` (`stopped_modifying=true`), `r0/result-r0.md`,
   `r0/lessons-r0.md`, `r0/check_merge_b19.py`, `r0/board/check_b19_board.py`.

## 2. Package table

| task_id | product | worktree / write scope | depends | functional | engineering | system | G | status |
|---|---|---|---|---|---|---|---|---|
| `T10.b19-cam-a` | A-tap candidate from the b18 chain, sim + build + one board run | `...\T10.b19-cam-a\r0\**` only | b18 r0 (read-only), b13 A evidence, b14 SDC | C01-C18', T1-T6 | Routed/WNS/ERAM, 1 bitgen + 1 CWC, hash-bound | preflight, reset alignment, 300 s, A export gate | G0/G1/G2/G3 | **ready** |

Only allowed writes: this package dir; the tester writes its report under `test-reports/`.
`workflow/tasks.json`, `workflow/workflow/**`, `docs/**`, `upstream/**` and other task trees are
read-only/forbidden.

## 3. Semantic steps (5, in order)

### S1 Baseline copy + single-line edit + conformance (target 10 min)

Copy the 11 sources from `..\T10.b18-b17-b\r0\changed-src\`; copy `td/{01_build.tcl,02_bitgen.tcl,
03_cwc.tcl,run_build_b18.ps1}` and `a1_board.al`; copy the b18 SDC/ADC byte-for-byte. Apply **only**:

```verilog
// r0/changed-src/p2_a1_board_top.v, line 97
localparam CAM_SEL = 1'b0;      // was 1'b1
```

Write `r0/check_merge_b19.py` = b18 checker adapted: C01-C16 unchanged; C17 A-branch equivalence
must remain `pairs=17 diffs=0`; C18 expects **bit12=0**, A tap signature, lane sticky `4'hF`,
`sysstat=0x00000F1D` in the stub test. Assert the one-line diff by file hash (10 hashes equal
b18, top differs only on that line) and SDC/ADC hash equality. Rewrite all TD paths to this
package (including `a1_board.al`); keep the filelist guard; stale `td/src` copies, if any, are
renamed `*.v.stale` and never added. Record `r0/merge-conformance-r0.txt`. Stop after 2 attempts
on a failing check (return `blocked` with the check id).

### S2 Simulation (target 30 min)

Copy `..\T10.b18-b17-b\r0\sim\` into `r0/sim/` (do not edit originals), then `run_b19.py`:

| id | case | gate |
|---|---|---|
| T1 | `t1_a_geometry` (full 3864x2192 -> ROI 972/556 -> 1920x1080, A tap signature) | `source_groups=2,117,472`; `line_rises=2,192`; `frame_rises=1`; `frame_falls=1`; `crop_roi_frames=1`; `crop_groups=518,400`; `raw_len=2,592,000`; `enc=1`; `exported=1`; four CRCs + strict zlib; no half frame; timeout/retry/giveup 0 |
| T2 | 16-word native readback | 16/16 match; addresses 0,8,...,120; `wstrb=0`; low3/oob/wstrb diag bits 0 |
| T3 | P1 `micro8x2/mid64x8/full_grad` | compressed bytes byte-identical to `..\T10.b18-b17-b\r0\sim\sim-results-b18-p1.json`; four CRC/zlib; dup=0 |
| T4 | drop-1-R + 3-frame middle retry | timeout 1 / retry 1 / giveup 0; frames export with four CRC+zlib; no deadlock; giveup not taken |
| T5 | v6 structure, A selected | 273 B / VER=6 / 67 fields / XOR; field #13 bit12=**0**, bit20=0, lane sticky `4'hF`; `diag_flags` bits1..5=0; v5 still accepted |
| T6 | real top, `CAM_SEL=0` | C18': `sysstat=0x00000F1D`, `u_a1.i_a_pixel` = A signature, selected byte clock toggling, B signature must not reach `u_a1`; C17 `diffs=0` |

Every case logs `vlog Errors:0`, input hashes, and a JSON result under `r0/sim/`. Entry
`P: = D:\fpga\ph1p100`, `W: = r0\sim`; per-case timeout 5 min, ModelSim ASE. The chain TB proves
geometry/CRC/zlib at the `u_a1` boundary; the real-top stub proves A selection (the D-PHY path is
hardware-only, same split as b18 L4). A frame bytes are not compared to B; only structural gates.

### S3 Build (target 25 min, TD sessions 2)

One synthesis (<=2 attempts), one route (<=1 attempt), one bitgen, one CWC:

- Routed `0` violated endpoints, hold >= 0, period check positive, `ERAM + CWC <= 300`;
- `WNS >= +0.05` target; `+0.003 .. <+0.05` accepted only as a diagnostic candidate with
  `timing_caveat=thin_margin_+0.0xx` (b13 wording), no production sign-off;
  `< +0.003` or any violation -> stop, no bitgen;
- bitgen re-checks final STA fail-closed (`SETUP/HOLD/PERIOD`); record bit/CWC/BID SHA256;
  `cw/compiled.bit|.cwc` byte-identical to `td/a1_board.bit|.cwc`; CWC has `<phy_eram` entries
  and no incomplete `<logic_eram/>`;
- keep `routed_qor.rpt`, `routed_timing_status.rpt`, violated-path list, `build_console_r0.log`;
  no SDC/seed/frequency change. Reference: b18 WNS +0.066 / ERAM 103; b13 A WNS +0.023. Do not
  reuse the b18 bit or CWC.

### S4 Board (target 15 min, 1 download)

`r0/board/run_board_b19.ps1` (b18 copy, `-Secs 300`, b19 paths, new `dl_b19_r0.tcl`):

1. Preflight `VID_0403&PID_6042` + COM8 with COM8 closed. Absent -> `board=blocked`, 0 downloads,
   0 captures; stop.
2. Exactly **1** SRAM download of the b19 bit; require the `B19_DL_OK` marker; no retry.
3. Release hwserver/JTAG. **Reset alignment**: operator pulses board reset `R14` (`sys_rst_n`)
   once to restart both camera cores and zero the counters; log `reset_pulse=yes`,
   download time and capture-start time; wait ~2 s, then open COM8 for **300 s**. Why 300 s:
   a worst-case stored frame is 2,594,706 B = 225.2 s at 115200 8N1; 150 s can truncate it.
   If no reset pulse is possible, record `reset_pulse=no` and still capture 300 s; a missing
   frame is then **ambiguous** -> `board=blocked`, do not claim A dead.
4. Parse v6 + frames, then `check_b19_board.py`. Gates:
   - CAM_SEL bit12=**0**, bit20=0; v6 `273/6/67`, `bad_xor=0`;
   - A tap counters `pix_beats>0`, `line_rises>0`, `frame_rises>0` (absolute totals when only one
     status packet, deltas when >=2; b18 saw 1 packet in 300 s);
   - `enc_frames>0`, `exported>0`; >= 1 `FRAME` with four CRCs true and zlib decodable; no half
     frame; `raw_drop/raw_abort` not growing;
   - `timeout/retry/giveup` not growing (absolute 0 with one packet, deltas 0 with >=2).
5. **A no-pixel stop**: if `pix_beats/line_rises/frame_rises` are all 0, keep the 300 s capture,
   `status_v6.txt/json`, `cam_*` counters, `phystat`, `sysstat`, lane sticky; set
   `board=blocked_A_no_pixels`; conclusion is A front-end/hardware, not DDR/PAXI; **no rebuild,
   no second download, no second capture**.
6. If `giveup` grows: keep v6 `timeout_ar_addr/low3`, `last_issued_ar_addr`, `diag_flags`,
   `inflight_state`; stop. No Flash, no second bitstream.

### S5 Freeze (10 min)

`stopped_modifying=true`; manifest over inputs + changed-src + scripts + TD/board artifacts;
`result-r0.md`, `lessons-r0.md`; return per relay contract (task_ids, status, artifact_paths,
manifest_path, test_input_paths, blocked/retest). Mark the single candidate; do not mix b18 and
b19 evidence in one PASS.

## 4. Three-dimension checks (one independent integrated tester)

Report `D:\fpga\ph1p100\test-reports\T10.b19-cam-a-r0-integrated.md`, first line one verdict,
`dimension=integrated`, `dimension_results` covering functional / engineering / system.

| dimension | checks | G |
|---|---|---|
| functional | one-line diff/hash equality, C01-C18', T1-T6, P1 byte identity, four CRC+zlib, v6 bit12=0, no half frame | G0/G1 |
| engineering | 0 violations, WNS/hold/period, ERAM+CWC, 1 bitgen + 1 CWC, compiled identity, filelist guard, no SDC relaxation, hash binding | G2 |
| system | preflight record, reset-alignment record, 1 download, 300 s decode, A counters, export gate, no-pixel stop evidence, write scope, no Flash | G3 |

All three apply; none is not-applicable. FTDI/COM8 absent or reset operator unavailable makes
system `blocked` (record required), not FAIL and not board-passed. A no-pixel run is
`blocked_A_no_pixels`, not a candidate defect; do not ask for a rebuild.

## 5. Budget, stop, rollback

- Dev **90 min / 50 calls**. TD **2 sessions** (`<=90 min`), synth `<=2`, route `<=1`, bitgen 1,
  CWC 1, download 1, Flash 0. Tester 45 min / 30 calls. Planner 15 min / 30 calls.
- Per problem: <=3 search/read loops; one retry of a failed command only with new evidence;
  2 consecutive no-progress -> `blocked`.
- Timeouts: read/search 60 s, local static/sim 5 min, build 30 min.
- Stop: conformance after 2 attempts; sim gate failure; 2 synth below target; route violated or
  `< +0.003`; bitgen/CWC failure; board giveup growing; A no pixels; budget exhausted.
- Rollback: only this package `r0/**`; b18/b13/b14/b17 trees and production files untouched.
  No batch delete (one explicit path at a time, or ask the user).

## 6. Entry points

- plan: this file, `input-index.md`, `fpga-design-guide.md`, `dispatch.json`
- source: `..\T10.b18-b17-b\r0\changed-src\` (one-line edit only)
- SDC/ADC: `..\T10.b18-b17-b\r0\td\p2_board.sdc`, `board_p2.adc`
- sim: `..\T10.b18-b17-b\r0\sim\` (copy), checkers `..\T10.b18-b17-b\r0\check_merge_b18.py`
- TD: `..\T10.b18-b17-b\r0\td\*.tcl|*.al|run_build_b18.ps1`, `tools\td\td_env.ps1`
- board: `..\T10.b18-b17-b\r0\board\*` (copy + 300 s + reset alignment), `tools\a1\pc_decode.py`
- resume text: `恢复：D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b19-cam-a；本轮目标：<目标>`
