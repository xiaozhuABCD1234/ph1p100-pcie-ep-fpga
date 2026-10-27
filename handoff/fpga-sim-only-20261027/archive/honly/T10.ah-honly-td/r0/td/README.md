# T10.ah-honly-td / r0 / td - isolated TD scaffold (Line B)

Status: **lease GRANTED, execution started** (r0-ruling.md §2, 2026-10-27 07:30).
The exclusive TD lease was re-verified immediately before the first TD call in
`../preflight-r1.json` (07:39:14: 0 TD processes, INT.P4/td + INT.P4/r3 quiet for
91 min, r3 manifest present). Round r0 preparation wrote nothing outside this task
directory and mapped/changed no drive letter. Execution: 1 synth (`syn_1`), then
conditional route (<=2), optional 209.6 analysis-only, 0 bitgen.

## Files

| File | Role |
|---|---|
| `a1_ah_eng_top.v` | build-only wrapper (NOT a candidate RTL file). Instantiates `a1_frame_top #(W=1920,H=1080)` unchanged and folds 8 x 32-bit status buses + `st_busy` + `dbg[31:0]` into one 32-bit XOR `st_dbg`, so TD does not count ~290 test ports as package IO (limit 286). |
| `a1_ah_small_top.sdc` | one clock only: `create_clock -name clk -period 5.333 -waveform {0.000 2.667} [get_ports clk]`. No false_path / multicycle / clock group / IO exception. Block-level IO stays unconstrained = known, recorded gap. |
| `01_synth.tcl` | 187.5 MHz synthesis, `syn_1`; copies `*_gate.timing/.area` + `flow.status`; prints `AH_SYN_*` markers (Setup/Hold WNS/TNS/NUM_FEPS, STA coverage, io/eram/fifo20k/reg/slice/dsp); exits 0 only if all three reports exist. |
| `02_route.tcl` | `phy_1` place & route on the synth gate DB; `update_timing -mode final`; timing summary/status, area, timing, QoR, clock utilization, check_timing, CDC. No bitgen. |
| `03_2096_analysis.tcl` | analysis-only: same routed DB, clock tightened to 4.777 ns. **Not** a 209.6 MHz routed result. |

## Commands (recovery round, cwd = this directory)

```
D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe ./01_synth.tcl
D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe ./02_route.tcl     # only if synth gate DB exists
D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe ./03_2096_analysis.tcl  # optional, analysis-only
```

Expected products: `a1_ah.al`, `a1_ah_Runs/syn_1/a1_ah_gate.{db,timing,area}`,
`syn_flow.status`, `syn_gate_timing.rpt`, `syn_gate_area.rpt`; after routing
`a1_ah_Runs/phy_1/a1_ah_pr.db` and `routed_*.rpt`; analysis `analysis_2096_*.rpt`.
Each run should get its own subdirectory (`syn_run1/`, `route_run1/`) per
fpga-design-guide 搂3.6; do not copy-overwrite older logs.

## Quota (frozen, do not extend from this directory)

- synthesis: **1** (187.5 MHz, 5.333 ns); route: **<=2** (2nd only after a failed
  1st, parameter difference must be written down); analysis: 1 (same DB).
- bitgen / CWC / download / Flash / board / COM / JTAG / RK / network: **0**.
- `T:` may be used only via `tools/td/td_env.ps1 -TdDir <this td dir>` and **never
  with `-Force`**. All tcl paths are absolute, so `T:`/`Y:` are optional.
  Current `T:` points at the finished b20 TD dir = stale; it was only read in r0.

## Lease gate before ANY run (fpga-design-guide 搂3.5)

1. `INT.P4-r3-manifest.json` exists **or** the user explicitly says TD is idle;
2. `Get-Process pnmain,td,td_commands_prompt,run` = 0;
3. no writes under `20261026-2138_fpga-integrated-delivery/INT.P4/td/**` or
   `INT.P4/r3/**` within the last 20 min.

`r0/preflight-r0.json` freezes the r0 observation. It is evidence of one probe,
not a standing lease: re-verify all three points immediately before the recovery
run. Observed at r0: 0 TD processes, INT.P4 latest writes 06:07:52/06:08:17, and
the r3 manifest **was present** at preflight time even though the dispatch recorded
it as absent - the planner must re-decide the lease, this scaffold does not.

## What this scaffold does NOT prove

No DUT function, no timing, no resource fit, no CDC result, no bitstream, no board
behaviour. A build-only wrapper is not the frozen candidate and must not be listed
as one in any manifest. `analysis-only` 209.6 MHz is not a routed 209.6 MHz result.