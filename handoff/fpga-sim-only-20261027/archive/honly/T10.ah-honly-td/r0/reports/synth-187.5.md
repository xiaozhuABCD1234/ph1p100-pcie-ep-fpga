# synth-187.5 - T10.ah-honly-td, synthesis run 1 of 1

**Verdict: FAILED at elaboration. No gate database, no timing, no area.**
This is not a lease/license/IO problem. The frozen H-only candidate
`a1_deflate_core.v` is rejected by TD with a multiple-driver error, so the
`a1_deflate_core` instance becomes a black box and `syn_1` exits non-zero.

## Run record

| Item | Value |
|---|---|
| Tool | TD Release_2026.2, Build number **6.2.3.210850**, `bin/run.exe` (started via `td_commands_prompt.exe`) |
| Command | `D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe ./01_synth.tcl` |
| cwd | `.../T10.ah-honly-td/r0/td/run-syn1` |
| Script | `run-syn1/01_synth.tcl` SHA `43b8b8e1…9ab29bf` (= canonical `r0/td/01_synth.tcl`) |
| Seed / preset | none (`enable_seed=off`, default) |
| Hard timeout | 1,800 s; **actual 6.49 s** wall; not timed out |
| Run start in TD log | 2026-10-27 07:40:23 |
| `wait_run syn_1 -quiet` | `PRJ-5303 WARNING: Run syn_1 failed.` + `PRJ-8806 ERROR: Run syn_1 has exited unexpectedly.` (3.04 s) |
| Script outcome | reached `AH_SYN_REPORT_MISSING timing=0 area=0 flow=0` -> the `exit 1` branch |
| Process exit code | not exposed by `Start-Process` (empty); the exit-1 branch is evidenced by the marker above, not by an assumed rc |
| Gate DB / reports | `a1_ah_gate.db` **absent**, `a1_ah_gate.timing` **absent**, `a1_ah_gate.area` **absent**, `flow.status` **absent** |

Successful steps before the failure: `create_project` (2.14 s), 4 x `add_files`,
`top_module a1_ah_eng_top`, `launch_runs syn_1`, device import
`ph1_100p.db -package PH1P100SBG484 -speed 3` (2.02 s), **3 source files analysed**,
elaboration of `a1_ah_eng_top` -> `a1_frame_top` -> `a1_deflate_core(OUT_BYTES=2)`
with RAM extraction of `smem`, `wq_mem`, `opq_mem`, `fifo_mem`, `bm_a`, `bm_b`,
`htab_tag`, `htab_p3v`, `htab_pos`, `htab_b`, `htab_b3`, `cmem`.

## Fatal error (verbatim)

```
HDL-8007 ERROR: net 'cmem_lo[15]' is constantly driven from multiple places in
.../T10.ah-honly/r0/changed-src/a1_deflate_core.v(673)
HDL-5007 WARNING: found another driver here in
.../T10.ah-honly/r0/changed-src/a1_deflate_core.v(964)
HDL-1007 : module 'a1_deflate_core' remains a black box due to errors in its contents
.../a1_deflate_core.v(30)
```

## Root cause (read-only inspection of the frozen file)

`reg [15:0] cmem_lo;` (L277) is assigned from **two different `always @(posedge clk)`
blocks**:

| Block | Line | Assignment | Reset |
|---|---|---|---|
| dedicated cmem write-port block | L673-687 | L679 `cmem_lo <= cmem_wdata_c;` | **no reset** (by design, see L280-285) |
| main sequential block | L964-... | L1042 `cmem_lo <= 16'd0;` inside `if (!rst_n)` | asynchronous-style reset branch |

Verilog allows only one procedural driver per `reg`; TD therefore reports a
constant/multiple driver. The block comment at L280-285 states that cmem writes were
deliberately merged into one reset-free always block so TD would infer ERAM instead of
65536 registers - but `cmem_lo`, `cmem_lo_pend`, `cmem_lo_addr` were left behind in the
reset branch, so the intended single-driver structure did not fully land.

Not the blocker, but adjacent copy-edit drift in the same reset branch: L1035-1039
assign `opq_bit_off`, `opq_wptr`, `opq_rptr`, `opq_count` twice in a row (harmless
duplicate assignments, no synthesis impact).

## Consequences

- No WNS/TNS/hold, no `NUM_FEPS`, no `Period Check WNS`, no STA coverage, no
  `#slice/#reg/#eram/#fifo20k/#dsp/#IO`: **these numbers do not exist and are not
  replaced by estimates**.
- Route and 209.6 analysis are `not_run` (both require a gate/routed DB).
- `eligible_for_next_stage = false` on this DUT revision, with the reason being
  **synthesizability**, not timing.

## Artefacts

`run-syn1/`: `synth_console.log` (`045cdc01…`), `td_20261027_074021.log`,
`a1_ah.al`, `a1_ah_Runs/syn_1/{run.log,run.logw,a1_ah.tcl,a1_ah.prj,settings.cfg,run.bat,.read_design.begin.f,.read_design.error.f}`.
No `*_gate.db/.timing/.area`, no `flow.status` anywhere in the run directory.