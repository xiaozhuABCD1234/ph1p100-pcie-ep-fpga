# dev-plan -- T10.b20-a-timing (targeted abort->smem-address pipeline on the A candidate)

Run `20261020-0209_singleA_aplus_closedloop`. Package `T10.b20-a-timing`, round **r0**.
Planner: general (fpga-planner delegated). 2026-10-26. Batch size 1. Formal packages: 1.
Status: **ready**, `needs_user_input=false` (one operator action at the board step: R14 pulse).
Parent `T10` stays blocked/active; this package does not close it.

## 0. Why this package

b19 `T10.b19-cam-a` proved the A chain end-to-end offline but failed only at routed setup:

| item | b19 value |
|---|---|
| synthesis | `SWNS +0.127 / STNS 0.000`, slice 18,718, ERAM 72 |
| routed | `SWNS -0.098 / STNS -0.518`, **10 violated endpoints**, HWNS +0.020 |
| worst path | `u_a1/a1_abort_reg -> u_a1/u_a1/smem.addrb[10]`, 6 levels (LUT6x2 LUT4x2 LUT3x1 ERAM) |
| other groups | `ddr_user +0.007`, `mipi_a_byte_clk +0.266`, `sys_clk50m +8.994`, `pclkx1 +2.564` |
| bit/CWC/board | none (gate stop, correct) |

The gap is 0.098 ns on one cone: the raw `abort` register fans into the ERAM read-address
next-state logic (5 LUT levels + ERAM address pin). Everything else passes. The user's decision is
**one targeted repair attempt on A**: add a register stage in that cone only, keep frame
semantics/CRC/protocol, discard aborted data, accept +1 cycle abort latency.

Evidence in: `..\T10.b19-cam-a\r0\result-r0.md`, `..\T10.b19-cam-a\r0\td\routed_timing.rpt`
(lines 105-185), `..\T10.b19-cam-a\r0\lessons-r0.md` L8/L9, `..\T10.b19-cam-a\CANDIDATE-MANIFEST-b19-cam-a-r0.json`.

Round accounting: **new task, round0**, new developer and a new independent integrated tester.
b19 is a FAIL evidence base, not an inherited round; its spent route budget does not transfer.
b18 is input evidence only (B camera board frame, bit/CWC reference, must not be reused).

## 1. Verifiable deliverable

One frozen candidate `r0`:

1. `r0/changed-src/` = 11 b19 files, **10 byte-identical to b19**, and `a1_frame_top.v` differs
   only by the abort->smem-address pipeline change (single file, reviewed hunks).
   `r0/td/p2_board.sdc` = `0888b6a7...0f5e` and `r0/td/board_p2.adc` = `1cb30346...7158` byte-identical.
2. `r0/sim/`: T1 A full chain (exact b19 counters incl. `cycles=37,465,298`), T2 16-word native,
   T3 P1 three goldens byte-identical, T4 drop-R + 3-frame retry (abort-recovery path),
   T5 v6 (273/6/67, bit12=0), T6 real top CAM_SEL=0; `vlog Errors:0` everywhere.
3. `r0/td/`: one Routed database with **0 violated endpoints and WNS >= +0.05**, one bitgen,
   one CWC; fail-closed STA in bitgen.
4. `r0/board/`: one SRAM download, R14 reset alignment, one 300 s COM8 capture; A counters and
   export gate pass, or `blocked_A_no_pixels` / `blocked_operator` with evidence.
5. `CANDIDATE-MANIFEST-b20-a-timing-r0.json` (`stopped_modifying=true`), `r0/result-r0.md`,
   `r0/lessons-r0.md`, `r0/diag/abort-path-fix.md`, `r0/diag/a1_frame_top-b20.diff`,
   `r0/check_merge_b20.py`, `r0/board/check_b20_board.py`.

## 2. Package table

| task_id | product | worktree / write scope | depends | functional | engineering | system | G | status |
|---|---|---|---|---|---|---|---|---|
| `T10.b20-a-timing` | b19 A chain + one abort->smem-address pipeline stage; sim, one Routed, 1 bit/CWC, one board run | `...\T10.b20-a-timing\r0\**` only | b19 r0 changed-src/SDC/ADC (read-only), b18 board script basis | C01-C20, T1-T6 | 0 viol / WNS>=+0.05 / per-group / ERAM / bit+CWC identity | preflight, R14 alignment, 300 s, A export gate | G0/G1/G2/G3 | **ready** |

Only allowed writes: this package dir; the tester writes `test-reports/T10.b20-a-timing-r0-integrated.md`.
`workflow/tasks.json`, `docs/**`, `upstream/**`, other task trees are read-only/forbidden.

## 3. The frozen change (the only permitted RTL delta)

**File:** `r0/changed-src/a1_frame_top.v` only. Baseline hash `0064607A...7109` (b19).

**Required structure:** insert **exactly one register stage** in the `abort` -> `smem` read-address
path so that the ERAM read-address cone (`smem.addrb[*]` / `smem_syn_*.addrb[*]`) has **no
combinational path** from the raw `abort` input, `proto_abort`, or `core_abort`. The abort's effect
on the drain/address side may arrive **one cycle later**; the aborted frame's data is discarded.

**Must stay byte/semantically identical** (frozen anchors, checked mechanically by C20):

- module port list; `crc32b`; `assign frame_abort = frame_abort_r;`
- `wire proto_abort` and `wire core_abort = abort || proto_abort || core_flush;`
- `assign in_ready = ...` expression (immediate abort gating), `frame_commit`, `out_*` packing block
- `a1_deflate_core u_core` instance (port map and parameters)
- CRC/length/stat registers and their updates, `st_*` outputs, `dbg` map, `smem` write port
- normal-frame drain cadence: D_GATH/D_EMIT issue rate, sample order, `raddr_of` and the
  prefetch/primed sequence outside abort

**Explicitly allowed:** a new 1-bit (plus, if needed, enable/clear) register and the minimal
re-wiring needed so the address/`bank_busy`/`primed` clear path consumes the registered abort
instead of the raw input; a matching 1-cycle delay of the aborted-frame drain teardown.
**Not allowed:** changing `core_abort` timing, `in_ready`, `frame_abort`, CRC/lengths, block/sample
counts, output packing, protocol fields, `a1_deflate_core.v`, the top, SDC, ADC, seed, frequency,
multicycle/false-path, extra ERAM/DSP, or debug/mailbox semantics. No new test-only logic in
synthesis (`ifdef` is forbidden; the sim DUT must be the synthesized RTL).

**Dev must write** `r0/diag/abort-path-fix.md`: the b19 pre-fix path, the diff with line ranges,
the cone-break argument (which register now launches the address cone), the accepted latency, and
the post-fix routed path quote. And `r0/diag/a1_frame_top-b20.diff` (unified diff vs b19).

## 4. Semantic steps (6, in order)

### S1 Baseline copy + single-file edit + conformance (target 15 min)

1. Create `r0/{changed-src,td,sim,board,diag}`. Copy all 11 files from
   `..\T10.b19-cam-a\r0\changed-src\` (do not edit b19). Copy `td/p2_board.sdc`,
   `td/board_p2.adc`, `td/{01_build.tcl,02_bitgen.tcl,03_cwc.tcl,a1_board.al}`,
   `td/src\**` (332 files incl. `*.v.stale`; keep them, never add them), and adapt only package
   paths. Keep the filelist guard: the three redirects must be the package copies exactly once;
   never add `./src/p2_a1_board_top.v`, `./src/f9p_camera_display_core.v`,
   `./src/src/p2_a1_board_top.v`, `./src/src/f9p_camera_display_core.v`.
2. Apply the S3 change to `r0/changed-src/a1_frame_top.v` only.
3. Adapt `..\T10.b19-cam-a\r0\check_merge_b19.py` -> `r0\check_merge_b20.py`:
   C01-C18 unchanged except hash expectations (10 files = b19 hashes, `p2_a1_board_top.v` =
   `B08438E8...81D0`, `a1_frame_top.v` = new hash, SDC `0888B6A7...0F5E`, ADC `1CB30346...7158`);
   C19 = SDC is exactly b19's file (no new edit); **C20 = frozen-anchor equality**: extract the
   normalized source lines for the anchors listed in S3 from b19's and b20's `a1_frame_top.v`
   and require equality (this is what makes "no protocol/CRC/in_ready change" mechanical).
   Also fail if the b20 file contains `ifdef`, `force`, or an added port.
4. Record `r0/merge-conformance-r0.txt` + the diff. Stop after 2 attempts on a failing check
   (return `blocked` with the check id).

### S2 Simulation (target 35 min)

Copy `..\T10.b19-cam-a\r0\sim\` into `r0/sim/` (originals untouched, TB module names renamed as in
b19 lesson L4) and adapt `run_b19.py` -> `run_b20.py` for package paths. Cases and gates:

| id | case | gate |
|---|---|---|
| T1 | `t1_a_geometry` full 3864x2192 -> ROI -> 1920x1080 | `source_groups=2,117,472`; `line_rises=2,192`; `frame_rises=1`; `frame_falls=1`; `crop_roi_frames=1`; `crop_groups=518,400`; `raw_len=2,592,000`; `read_words=129,600`; `dup_words=0`; `enc=1`; `exported=1`; `exp_bytes=2,594,706`; `cmp_words=648,677`; `cmp_writes=81,085`; **`cycles=37,465,298` exactly**; `ticks_in_frame=1245`; `status_grants=253`; four CRC + strict zlib; no half frame; `timeout/retry/giveup=0` |
| T2 | 16-word native readback (5 cases) | `pass=1 words=16 bad_low3=0 oob=0 mask=0 last_ar=120 wstrb_bad=0`; mask `commit=2 value_kept=1`; addr `bad_low3=2 oob=2`; conc `same_req=1 same_hs=1`; b15neg `pass=1` |
| T3 | P1 `micro8x2 / mid64x8 / full_grad` | compressed bytes byte-identical to b19 goldens `FA513A2B...EDEF` / `EE61E620...9789` / `B992A8AD...DADA9`; four CRC/zlib; `dup=0` |
| T4 | drop-1-R (`T4a`) + 3-frame middle retry (`T4b`) | counts identical to b19: `timeout=retry=1`, `giveup=0`, `exported=1/3`, `exp_bytes=666/1998`, `cmp_drop=1`, `purge_cnt=1`, four CRC+zlib per frame, no deadlock; **`cycles` within +0..+16 of 89,050 / 106,094** (the accepted <=1-cycle abort teardown); `giveup` never taken. T4 is the end-to-end abort-recovery case (raw-R timeout -> `a1_abort` pulse -> frame abort -> retry) |
| T5 | v6, A selected | 4 packets, `273/6/67`, `bad_xor=0`, `f13=00000f01` bit12=**0**, bit20=0, lane sticky `4'hF`; `diag_flags` bits1..5=0; v5 accepted |
| T6 | real top, `CAM_SEL=0` | `sysstat=0x00000F1D`, `u_a1.i_a_pixel=a5a5a5a5a5`, `clk_edges=67`, `i_valid=1`, A selected, B signature absent |

Every case logs `vlog Errors:0`, input hashes and a JSON result. `P: = D:\fpga\ph1p100`,
`W: = r0\sim`. Timeouts: T1 1800 s (b19 took 1309.7 s), others 300 s. Run all cases in one batch;
do not re-run a passing case to "confirm".

**T1 exact `cycles/cmp_words` equality is the cycle-neutrality proof.** T4 is the abort proof.
If T1 cycles differ by even 1, the change added a normal-path bubble: fix or FAIL, do not relax.

### S3 Build (target 30 min, TD sessions 3 total for the task)

One synthesis (<=2 attempts), one route (<=1 attempt), then bitgen (1), CWC (1).

- Session 1: `r0\td\run_build_b20.ps1` (adapted hash guard: 10 unchanged b19 hashes, top
  `B08438E8...81D0`, new `a1_frame_top.v` hash, SDC/ADC b19 hashes, and a guard that the diff
  vs b19 touches only `a1_frame_top.v`). `01_build.tcl` runs synthesis and stops before route if
  the synth gate fails.
- **Synth gate:** `SWNS >= 0`, `STNS >= 0`, 0 violated endpoints, ERAM + CWC <= 300,
  `vlog/elaboration Errors:0`. **Route pre-condition:** synth `SWNS >= +0.127` (must be at least
  b19's synth value; b19 lost 0.225 ns from synth to route, so <= +0.127 cannot reach +0.05).
  Below that: stop with `FAIL(synth_no_gain)`, no route, no bitgen. A second synth (S1 already
  consumed one) is allowed only if the first one fails the gate for a constraint/readability
  reason; no RTL iteration inside the build.
- **Route gate (1 attempt):** 0 violated endpoints, hold >= 0, period check > 0, and
  `WNS >= +0.05` -> PASS candidate; `+0.003 .. < +0.05` with 0 violations -> accepted as
  **thin-margin caveat** candidate (`timing_caveat=thin_margin_+0.0xx`), may proceed to bitgen and
  board but every report must carry the caveat and no "robust timing" claim; `< +0.003` or any
  violation -> `FAIL(route_timing)`, stop, no bitgen.
- **Per-group gate** (b19 comparison): `ddr_user >= +0.003` (b19 +0.007, do not regress),
  `mipi_a_byte_clk >= +0.05`, `sys_clk50m >= +1.0`, `pclkx1 >= +0.5`, `clk_a1 >= +0.05`,
  all other groups 0 violations. Any new violated group = FAIL.
- **Cone-break evidence:** the routed violated-path list must contain 0 paths launched by
  `a1_abort_reg` into `smem.addrb[*]`; quote the new worst `clk_a1` path (begin/end/levels).
  Resource ceiling: slices <= 25,800 (b19 24,989), ERAM <= 103, DSP 0, GCLK 9.
- Keep `routed_qor.rpt`, `routed_timing.rpt`, `routed_timing_status.rpt`,
  `build_console_r0.log`, `syn_gate_timing.rpt`, `syn_gate_area.rpt`. No SDC/seed/frequency/
  effort change; `post_route_opt` stays the frozen b19 setting.

### S4 bitgen + CWC (target 10 min, session 2)

`run_bitgen_cwc_b20.ps1` (adapted from b19): one `02_bitgen.tcl`, one `03_cwc.tcl`, fail-closed
re-check of final `SETUP/HOLD/PERIOD`; record bit/CWC/BID SHA256; `cw/compiled.bit|.cwc`
byte-identical to `td/a1_board.bit|.cwc`; CWC contains `<phy_eram` entries and no incomplete
`<logic_eram/>`. Any failure -> `FAIL(bitgen|cwc)`, no download. Do not reuse b18's bit/CWC.

### S5 Board (target 12 min, session 3 only if hardware/JTAG needs it, 1 download)

`r0/board/run_board_b20.ps1` (b19 copy: `-Secs 300`, b20 paths, `dl_b20_r0.tcl`, marker `B20_DL_OK`):

1. Preflight `VID_0403&PID_6042` and `COM8` with COM8 **closed**. Absent/busy -> `board=blocked`,
   0 downloads, 0 captures, stop.
2. **First** exactly **1** SRAM download of the b20 bit (JTAG, never Flash); require `B20_DL_OK`.
3. Release hwserver/JTAG. **Then** operator pulses `R14` (`sys_rst_n`) once, log
   `reset_pulse=yes`, download and capture timestamps, wait ~2 s, **then** open COM8 for **300 s**
   (worst-case stored frame 2,594,706 B = 225.2 s at 115200 8N1). No pulse possible ->
   `reset_pulse=no`, still capture, a missing frame is `board=blocked_operator` (ambiguous), do not
   claim A dead.
4. Gate (`check_b20_board.py`, b19 gate + negative control on the b18 B capture must still FAIL
   with `camsel_bit12=1`): CAM_SEL bit12=**0**, bit20=0; v6 `273/6/67 bad_xor=0`; A
   `pix_beats>0`, `line_rises>0`, `frame_rises>0` (absolute totals with 1 status packet, deltas
   with >=2); `enc_frames>0`, `exported>0`; >= 1 `FRAME` with four CRCs true and zlib decodable;
   no full-payload bad-CRC frame (tail-cut allowed); `raw_drop/raw_abort` not growing;
   `timeout/retry/giveup` not growing (absolute 0 with 1 packet, deltas 0 with >=2).
5. **A no-pixel stop:** if `pix_beats/line_rises/frame_rises` are all 0, keep the 300 s capture,
   `status_v6.txt/json`, `cam_*`, `phystat`, `sysstat`, lane sticky; set
   `board=blocked_A_no_pixels`; conclusion is A front-end/hardware; **no rebuild, no second
   download, no second capture**.
6. `giveup` grows -> keep v6 `timeout_ar_addr/low3`, `last_issued_ar_addr`, `diag_flags`,
   `inflight_state`; stop. No Flash, no second bitstream.

### S6 Freeze (target 8 min)

`stopped_modifying=true`; manifest over inputs + changed-src + scripts + TD/board artifacts;
`result-r0.md`, `lessons-r0.md`; return per relay contract (task_ids, status, artifact paths,
manifest path, test input paths, blocked/retest). One candidate only; do not mix b19/b18 PASS
evidence with b20.

## 5. Three-dimension checks (one independent integrated tester)

Report `D:\fpga\ph1p100\test-reports\T10.b20-a-timing-r0-integrated.md`, first line one verdict,
`dimension=integrated`, `dimension_results` for functional / engineering / system.

| dimension | checks | G |
|---|---|---|
| functional | single-file diff + C20 anchors, C01-C19, T1-T6 exact gates, P1 byte identity, four CRC+zlib, v6 bit12=0, T4 abort recovery, cycle-neutrality | G0/G1 |
| engineering | 0 violations, WNS>=+0.05 (or documented thin-margin caveat), per-group table, cone-break evidence, ERAM/slices, 1 bitgen + 1 CWC, compiled identity, filelist guard, no SDC relaxation, hash binding | G2 |
| system | preflight record, reset-alignment record, 1 download, 300 s decode, A counters, export gate, no-pixel/operator stop evidence, write scope, no Flash | G3 |

All three apply; none not-applicable. FTDI/COM8 absent or the R14 pulse unavailable makes system
`blocked` (record required), not FAIL and not board-passed. `blocked_A_no_pixels` is not a
candidate defect; do not ask for a rebuild.

## 6. Budget, stop, rollback

- Dev **100 min / 55 calls**. TD **3 sessions** (`<=30 min` each), synth `<=2`, route **1**,
  bitgen 1, CWC 1, download 1, Flash 0. Tester 45 min / 30 calls. Planner 15 min / 30 calls.
- Per problem: <=3 search/read loops; one retry of a failed command only with new evidence;
  2 consecutive no-progress -> `blocked`.
- Timeouts: read/search 60 s, local static/sim 5 min (T1 30 min), build 30 min, bitgen 10 min.
- Stop: conformance after 2 attempts; sim gate failure; synth gate failure or `SWNS < +0.127`;
  route violated or `< +0.003`; bitgen/CWC failure; board giveup growing; A no pixels; budget
  exhausted.
- Rollback: only this package `r0/**`; b19/b18/b17/b13 trees and production files untouched.
  No batch delete (one explicit path at a time, or ask the user).

## 7. Entry points

- plan: this file, `input-index.md`, `fpga-design-guide.md`, `dispatch.json`
- baseline: `..\T10.b19-cam-a\r0\changed-src\`, `..\T10.b19-cam-a\r0\td\{p2_board.sdc,board_p2.adc,*.tcl,a1_board.al,src\}`
- sim: `..\T10.b19-cam-a\r0\sim\` (copy), `..\T10.b19-cam-a\r0\check_merge_b19.py`
- TD: `tools\td\td_env.ps1`, `tools\td\PATH_CONTRACT.md`
- board: `..\T10.b19-cam-a\r0\board\*` (copy + `-Secs 300` + R14 order), `tools\a1\pc_decode.py`
- resume text: `恢复：D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b20-a-timing；本轮目标：<目标>`
