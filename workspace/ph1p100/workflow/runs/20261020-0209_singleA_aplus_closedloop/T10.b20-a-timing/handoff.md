# T10.b20-a-timing -- handoff

Status at freeze: **ready** (r0), `needs_user_input=false`. Parent `T10` stays blocked/active.
Nothing simulated, built or downloaded in this planning round; the package dir is plan-only.

## 1. What is frozen

- `dev-plan.md` -- one package, 6 steps (baseline+edit+conformance -> sim -> build -> bitgen/CWC ->
  board -> freeze), exact gates, budget, stop/rollback.
- `input-index.md` -- every input path, b19 hashes, P1 goldens, exact T1 counters.
- `fpga-design-guide.md` -- the only RTL delta (abort->smem read-address cone), anchors that must
  not change, timing/resources/per-group gates, path contract.
- `dispatch.json` -- role, scope, gates, hardware order, budgets, tester.

## 2. For the developer (start here)

1. Read `dev-plan.md` S1-S6, `fpga-design-guide.md` S2, and `dispatch.json.gates`.
2. Copy the 11 b19 sources + `td/{*.tcl,a1_board.al,p2_board.sdc,board_p2.adc,src\**}` and
   `sim\**`/`board\**` bases into this package; rewrite **every** path to `T10.b20-a-timing`
   (a leftover `T10.b19-cam-a` path silently builds b19).
3. Change **only** `r0/changed-src/a1_frame_top.v`: one register stage so `smem.addrb[*]` is not
   launched by the raw `abort`/`proto_abort`/`core_abort` cone. Keep `core_abort`, `in_ready`,
   `frame_abort`, CRC/lengths/stat, packing, `u_core` port map identical (C20 anchors).
4. Sim T1-T6. **T1 must reproduce `cycles=37,465,298`, `cmp_words=648,677`, `cmp_writes=81,085`
   exactly** (cycle-neutrality). T4 (drop-R + retry) is the end-to-end abort-recovery case and is
   allowed +0..+16 cycles.
5. TD: session 1 = synth (+ route only if synth `SWNS >= +0.127`), session 2 = bitgen + CWC,
   session 3 reserved for hardware/JTAG only. Route is **one** attempt: 0 violations and
   `WNS >= +0.05`, or `+0.003..<+0.05` as a thin-margin caveat candidate.
6. Board: preflight -> **1** SRAM download -> `B20_DL_OK` -> close JTAG -> operator R14 pulse ->
   COM8 **300 s** -> `check_b20_board.py`.
7. Freeze manifest with `stopped_modifying=true`; return per relay contract.

## 3. Known constraints and traps

- **b19 is FAIL, not a starting round.** Its route budget is spent; do not "resume b19" and do not
  reuse its (nonexistent) bit. b20 is a new task with its own single route.
- **Do not put the pipeline in the normal drain data path.** That changes sample latency/cycle
  count and will fail T1 exact-cycle or P1 byte identity. The register belongs only in the
  abort-side cone (aborted data is discarded, so +1 cycle there is free).
- **`core_abort` stays combinational.** Delaying the core's abort lets it publish an orphan block.
- **`ddr_user` was already +0.007 ns in b19.** New registers must not be placed into that domain's
  thin paths; the per-group gate `ddr_user >= +0.003` is a real failure mode, not a formality.
- **Synth-to-route loss was 0.225 ns in b19.** Route is only worth spending at synth `>= +0.127`;
  the realistic target needs synth `>= +0.25`.
- `01_build.tcl` exits 0 even when route STA is negative (lesson L9). Gate on
  `P2_ROUTED_SWNS / P2_ROUTED_VIOL_EP`.
- TD scripts and `a1_board.al` carry absolute paths, and `td/src` keeps `*.v.stale` copies plus
  `src/src/p2_a1_board_top.v`; keep the filelist guard so duplicate modules are never compiled.
- The SDC still logs `create_generated_clock ... mipi_b_byte_clk` failure (B divider trimmed). It is
  expected; do not "fix" it and do not re-add the B clock group.
- 300 s capture is required (a stored 2,594,706 B frame takes 225.2 s at 115200 8N1). R14 pulse
  must happen **after** the download and **before** COM8. No pulse -> `blocked_operator`, not
  "A is dead".
- The board gate must first reject the b18 B capture (`camsel_bit12=1`) as a negative control.
- FTDI presence is intermittent. Preflight first; absent = `blocked`, 0 downloads, not a defect.
- No batch delete; delete one explicit path at a time or ask the user.

## 4. After the round

- Tester report: `test-reports/T10.b20-a-timing-r0-integrated.md` (new independent tester, three
  dimensions in one report, `dimension=integrated`).
- PASS (all three, board included): planner updates this package's `final-summary.md` /
  `user-summary.md`, records the b20 candidate, and only then considers T10 closure. b19 stays
  FAIL in the record.
- `PASS(route thin-margin)` is a caveat candidate: bit/CWC/board allowed, but no robust-timing or
  production claim.
- `FAIL(route_timing)` after the single route: keep the routed DB/report, no bitgen, return to the
  planner; the next option is a different structural target (out of this package).
- `blocked_A_no_pixels`: the 300 s capture is the deliverable; A front-end/hardware conclusion; no
  rebuild and no second download.
- `blocked_operator`: keep the bit and the download record; resume needs a new authorized window.

## 5. Resume text

`恢复：D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b20-a-timing；本轮目标：<目标>`
