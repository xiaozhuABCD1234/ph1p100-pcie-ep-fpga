# T10.ah-honly-td / r1 / td - TD execution scaffold

**Round r1** (same task, not a new task). DUT switched to the synthfix revision
(core `d2960cfe…aad8`, 85,221 B; frame_top `4afc26e2…e30a`, unchanged). See
`../BINDING.md` for the full old→new table and hash evidence.

Execution status is recorded in `../result-r1.md` / `../manifest-r1.json`; this file
only documents the entry points. The wrapper and SDC are byte-identical copies of the
r0 versions (wrapper SHA `3e2be8ea…670c7`, SDC SHA `6d948bba…594bf`); no RTL, clock or
exception was changed.

## Files

| File | Role |
|---|---|
| `a1_ah_eng_top.v` | build-only wrapper (NOT a candidate). `a1_frame_top #(W=1920,H=1080)` unchanged; 8 x 32-bit status + `st_busy` + `dbg[31:0]` folded into one 32-bit XOR `st_dbg` to stay inside the 286-IO device. |
| `a1_ah_small_top.sdc` | single clock `create_clock -name clk -period 5.333 -waveform {0.000 2.667} [get_ports clk]`; no false_path / multicycle / clock group / IO constraint. Block-level IO unconstrained = recorded gap. |
| `01_synth.tcl` | 187.5 MHz synthesis `syn_1`; copies `*_gate.timing/.area` + `flow.status`; prints `AH_SYN_*`; exits 0 only if all three reports exist. |
| `02_route.tcl` | conditional `phy_1`; routed reports: timing summary/status/timing, QoR, area -io_info, clock utilization, check_timing (fallback report_check_timing), report_cdc. No bitgen. |
| `03_2096_analysis.tcl` | analysis-only tightened clock 4.777 ns on the same routed DB. **Not** a 209.6 MHz routed result. |

## Commands (cwd = `run-syn1` for synth; `run-route1` for route/analysis)

```
D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe ./01_synth.tcl
D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe ./02_route.tcl
D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe ./03_2096_analysis.tcl
```

Each attempt gets its own run directory; run-time project, TD logs and reports stay
there so the frozen scaffold is never overwritten.

## Quota (frozen)

1 synthesis (this is lifetime TD launch 2 of 3), route <= 2 (2nd only after a failed
1st with a written parameter difference, no seed sweep), analysis-only <= 1,
bitgen/CWC/download/Flash/board/network = 0. Route is attempted only when the gate DB
and reports exist **and** synth WNS >= -0.50 ns; otherwise `route=not_run` with reason.

## Lease v2 before any TD call

0 `pnmain/td/td_commands_prompt/tdsynth` processes **and** `INT.P4/td`, `INT.P4/r3`,
`20261027-0726_fpga-board-integration/T11.BRD.P1/td` each quiet for >= 20 min. Busy ->
`blocked=TOOL_UNAVAILABLE`, no retry, no shared project, no `-Force`. `T:` belongs to
the board-integration run and is never touched here. Residual risk (disclosed by the
planner): that run is still active and may start TD inside our window; if it does, this
task starts no second session and records the overlap.

## Eligibility gates (frozen)

routed WNS >= 0 AND hold >= 0 AND `flow.status` NUM_FEPS = 0 AND ERAM+CWC <= 300 AND
slice <= 71,680 AND IO <= 286, plus STA coverage / check_timing / report_cdc evidence
and >= 10 worst-path attribution. Otherwise `not_eligible` with real numbers - no
relaxed clock, no exception, no fabricated IO, no bitstream.

## Not proven by this scaffold

DUT function, timing, resource fit, CDC cleanliness, bitstream, board behaviour.
A build-only wrapper is not the candidate; analysis-only 209.6 is not routed 209.6.