# T10.b19-cam-a -- handoff

Status at freeze: **ready** (r0), `needs_user_input=false`. Parent `T10` stays active.
Nothing built, simulated or downloaded in this planning round; the package dir is plan-only.

## 1. What is frozen

- `dev-plan.md` -- one package, 5 steps (baseline one-line edit -> sim -> build -> board -> freeze),
  exact gates, budget, stop/rollback.
- `input-index.md` -- every input path and the b18/b13 same-origin facts.
- `fpga-design-guide.md` -- CAM_SEL delta, formats, clock/reset, sim/build/board conventions.
- `dispatch.json` -- role, scope, gates, hardware order, budgets, path contract, tester.

## 2. For the developer (start here)

1. Read `dev-plan.md` S1-S5 and `dispatch.json.gates`.
2. Create `r0/changed-src`, `r0/td`, `r0/sim`, `r0/board`, `r0/diag` under this package.
3. Copy the 11 b18 sources; change **only** `p2_a1_board_top.v` line 97:
   `localparam CAM_SEL = 1'b0;`. Verify the other 10 hashes + SDC/ADC are unchanged.
4. Adapt `check_merge_b18.py` -> `check_merge_b19.py`; C17 must stay `pairs=17 diffs=0`; C18'
   expects `sysstat=0x00000F1D`, A signature, bit12=0.
5. Sim T1-T6; then TD (2 sessions, 1 synth, 1 route, 1 bitgen, 1 CWC); then one board run.
6. Freeze manifest with `stopped_modifying=true` and return per relay contract.

## 3. Known constraints and traps

- **Only one RTL character may change.** If any other changed-src hash differs, the package is not
  the b18-proven chain and the run is invalid. Do not "fix" A by editing the tap/core/config.
- b18 `result-r0.md` says board blocked -- that is the earlier run. The actual B success is
  `r0/board/captures_full/` (`FRAME id=1 ... stream_len=2,594,706`, four CRCs+zlib, exported=1).
  Use the capture, not the stale verdict.
- A was last measured on b13 with `pix_beats=0`. That bit had no PAXI fix/retry, so it is not a
  conclusion. If b19 A still shows 0 pix/line/frame, stop with `blocked_A_no_pixels`; do **not**
  rebuild or download a second bit.
- 300 s capture is required: a stored 2,594,706 B frame takes 225.2 s at 115200 8N1. 150 s can
  cut it. Reset alignment is one operator pulse on R14 (`sys_rst_n`) after the single download;
  record `reset_pulse` and timestamps. No reset -> missing frame is ambiguous (`blocked`).
- `CAM_SEL` is v6 field #13 bit **12** (not bit 20). With A it must read 0; bit20 must stay 0.
- TD scripts and `a1_board.al` carry absolute paths. Rewrite them to this package or bitgen opens
  b18's sources. Keep the filelist guard (`p2_a1_board_top.v`/`f9p_camera_display_core.v` exactly
  once from this package, never `./src`). Do not reuse the b18 bit/CWC.
- Timing: b18 merged WNS +0.066; b13 A-only +0.023. Target >= +0.05; +0.003..<+0.05 is a
  diagnostic candidate with `timing_caveat` (b13 wording), no production sign-off;
  < +0.003 or any violation -> stop before bitgen.
- FTDI presence is intermittent. Preflight first; absent = `blocked`, 0 downloads, not a defect.

## 4. After a successful round

- Tester report: `test-reports/T10.b19-cam-a-r0-integrated.md` (new independent tester, three
  dimensions in one report).
- On PASS (all three, board included) the planner updates this package's
  `final-summary.md`/`user-summary.md` and the run-level records; only then consider `T10` closure.
- On `blocked_A_no_pixels`, the capture is the deliverable; the planner records the A hardware
  conclusion. No new bitstream this round.
- On `giveup > 0`, keep the v6 failed-AR fields and stop; hand back for a DDR-IP-level task.

## 5. Resume text

`恢复：D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b19-cam-a；本轮目标：<目标>`
