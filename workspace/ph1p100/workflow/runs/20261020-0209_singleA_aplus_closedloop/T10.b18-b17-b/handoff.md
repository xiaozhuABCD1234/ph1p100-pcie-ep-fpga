# T10.b18-b17-b -- handoff

Status at freeze: **ready** (r0), `needs_user_input=false`. Parent `T10` blocked.
Nothing has been built or downloaded yet for this task; the candidate dir is plan-only.

## 1. What is frozen

- `dev-plan.md` -- one package, 5 steps (merge -> sim -> build -> board -> freeze), gates and budget.
- `merge-spec.md` -- exact file-level recipe (11 sources) and the 8 `p2_a1_board_top.v` edits,
  plus C01-C18 conformance checks. This is the only legal way to build the merged top.
- `fpga-design-guide.md` -- frozen formats/interfaces/clocks/SDC/build/board entry.
- `input-index.md` -- every input path and the b14-vs-b17 same-origin table.
- `dispatch.json` -- role, scope, gates, budget, path contract, stop rule.

## 2. For the developer (start here)

1. Read `dev-plan.md` §3 and `merge-spec.md`.
2. Create `r0/changed-src/`, `r0/td/`, `r0/sim/`, `r0/board/`, `r0/diag/` under this package.
3. Copy the 11 sources per `merge-spec.md` §1 (10 exact copies, 1 merge).
4. Apply edits 1-8 to `p2_a1_board_top.v`; run `check_merge_b18.py` (C01-C18).
5. Sim T1-T6; then TD (copy b17 tcl, rewrite paths, keep the filelist guard); then the single board run.
6. Freeze manifest with `stopped_modifying=true` and return per relay contract.

Hard rules: b17 PAXI/v6/retry logic and b14 B-tap logic must both survive; the only merged file is
the board top; SDC is the b14 r1 file byte-for-byte; no false path/multicycle/seed change;
download only after the FTDI preflight and only once; COM8 opens only after the download.

## 3. Known constraints and traps

- `01_build.tcl` from b17 hardcodes `T10.b17-paxi-native/r0/changed-src` paths. Rewriting them is
  required; forgetting it silently rebuilds the b17 (A-only) design.
- b14 r0/r1 contain stale duplicate sources under `td/src/` and `td/src/src/`. Never add them; the
  filelist guard C16 must abort if either basename appears twice or from `./src`.
- `CAM_SEL` is `bit 12` of `cam_sysstat` (v6 field #13). Any check that reads bit 20 is wrong.
- With `CAM_SEL=1`, `clk_cam` is the B byte clock; the `mipi_b_byte_clk` generated clock is mandatory.
- b17 r1 routed at `+0.002 ns` (thin). If the merged build lands in `+0.003..<+0.05`, it is a
  diagnostic candidate with `timing_caveat`; `<+0.003` or any violation means stop before bitgen.
- The b17 r1 board branch failed on FTDI absence at 16:47, while b14 r1 downloaded successfully at
  17:21. FTDI presence is intermittent: always run the preflight, and treat absence as `blocked`
  (0 downloads), not as a defect of the candidate.
- b14 r1 saw B `lane_sticky=0x1` with complete frames; do not chase it unless a lane-1 failure appears.

## 4. After a successful round

- Tester report: `test-reports/T10.b18-b17-b-r0-integrated.md`.
- On PASS (all three dimensions, board included) the planner updates this package's
  `final-summary.md`/`user-summary.md`, the run-level summary, and only then considers `T10` closure.
- If the board run still shows `giveup > 0`: the v6 `timeout_ar_addr`/`diag_flags` fields are the
  deliverable; stop, hand back to the planner for a DDR-IP-level task. No second bitstream this round.

## 5. Resume text

`恢复：D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b18-b17-b；本轮目标：<目标>`
