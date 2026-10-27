# result-r1 - T10.ah-honly-td (Line B, r1)

- **status**: `blocked`
- **reason_code**: `TOOL_UNAVAILABLE` (TD 6.2.3 coredumps importing its own gate DB;
  no second parameter set is plausible, route quota exhausted at 2 attempts)
- **eligible_for_next_stage**: **false** - `eligibility_basis = not_evaluated`
  (routed evidence absent). This is **not** a timing failure and must not be recorded as
  one.
- **frozen**: `r1/manifest-r1.json` (`stopped_modifying=true`, `active_commands=0`)

## 1. Lease (v2, holder-agnostic)

`r1/preflight-r1.json`, 2026-10-27 09:33:45: TD processes = **0**;
`INT.P4/td` quiet 205.9 min, `INT.P4/r3` quiet 205.5 min,
`20261027-0726_fpga-board-integration/T11.BRD.P1/td` quiet 75.3 min -> `GRANTED`.
`T:` belongs to the board-integration run; it was **not** remapped/released/forced (all
paths absolute). A second lease check was taken immediately before route attempt 2
(09:35:40: 0 processes, 207.8/207.4/77.2 min).

## 2. DUT binding

| Role | Bytes | SHA-256 |
|---|---:|---|
| `a1_deflate_core.v` (synthfix revision) | 85,221 | `d2960cfe0111b7b61aff281e3f16427834dda26107f37867d5c7c89ac346aad8` |
| `a1_frame_top.v` (unchanged) | 29,207 | `4afc26e246fbae4e32c5ab7e88dffb496048d10966c5ee42b290b3e71f60e30a` |
| synthfix manifest | - | `034777c55d5a7857f18d9860afbb73f7554940f65213d9228c449bbc5855e510` |

Previous DUT core `8acd20b2…b17b` was rejected by TD (`HDL-8007`, `cmem_lo` multiple
drivers); the synthfix revision removes exactly that. Wrapper and SDC are byte-identical
r0 copies (`3e2be8ea…`, `6d948bba…`). No RTL/SDC/clock/port change was made by this
round.

## 3. What ran

| Step | Quota | Result |
|---|---|---|
| synth `./01_synth.tcl` | 1 result (lifetime launch 2 of 3) | **SUCCESS**, 43.47 s: SWNS **+0.029 ns**, STNS 0.000, HWNS 0.000, HTNS 0.000, Period Check WNS 2.533, coverage 97.06 %, 0/4,969 violated endpoints |
| route `./02_route.tcl` | 1 of 2 | **FAILED** in `import_db` -> `Import ChipWatcher` -> coredump `minidump-20261027-093503.dmp` (1.44 s) |
| route `./02_route.tcl` (2nd) | 2 of 2 | **FAILED identically** -> `minidump-20261027-093540.dmp` (1.22 s); only difference: original project dir instead of a copy |
| 209.6 analysis-only | 0 of 1 | not_run (needs routed DB) |
| bitgen / CWC / download / Flash / board | 0 | not attempted |

## 4. Synthesis numbers (the only real measurements this round)

- setup WNS **+0.029 ns**, TNS 0.000, 0 violated / 4,969 endpoints, period-check 2.533 ns
- hold WNS +0.000 ns (`flow.status` sentinel `2147483647 ps` = no failing hold endpoint)
- area: slice 3,337 / 71,680; reg 1,663; lut 4,188 (lut6 1,978); ERAM 27 + fifo20k 0;
  DSP 0; IO 121 / 286 (48 in, 73 out)
- worst 10 gate paths: 2 in frame_top (`grp_in_row` -> `smem_waddr_r`, +0.029/+0.071 ns),
  8 in core (`htab_b`->`hb_r`; `sdata_ptr`->`state`; `len_r`->`cand_bits`)

## 5. Gates

| Gate | Required | Measured |
|---|---|---|
| synthesis completes with gate DB + 3 reports | yes | **yes** |
| routed WNS >= 0 | yes | **not evaluated** (no routed DB) |
| routed hold >= 0 | yes | **not evaluated** |
| `flow.status` NUM_FEPS = 0 | yes | synth gate 0; routed **absent** |
| ERAM+CWC <= 300 | yes | synth 27; routed absent |
| slice <= 71,680 | yes | synth 3,337; routed absent |
| IO <= 286 | yes | synth 121; routed absent |
| STA coverage / check_timing / report_cdc | yes | coverage 97.06 % (synth); check_timing/CDC **not_run** |
| 0 bitgen | yes | satisfied (never attempted) |

## 6. Blocker detail

Both route attempts crashed at the same TD statement while importing the just-produced
`a1_ah_gate.db`:

```
import_db ./a1_ah_Runs/syn_1/a1_ah_gate.db
... Import Inst constraints
Import ChipWatcher
Oops! coredump minidump-20261027-093503.dmp
```

The gate DB itself is valid for STA (read by `optimize_gate` and reported), and the crash
happens before any placement. Per `r2-ruling.md §2.2` this class is recorded as
`TOOL_UNAVAILABLE` with the raw error, not as a candidate/timing defect, and not retried
beyond the authorised attempts.

## 7. Next-step options for the planner (not executed)

1. Probe whether TD 6.2.3 can route this DB when `ChipWatcher` data is excluded
   (e.g. a tool option or a re-generated DB without debug payload), then run route in a
   fresh round with its own quota. Evidence would have to note the changed parameter.
2. Accept the synthesis-gate result as a bound only: +0.029 ns setup at gate level with
   net delay already 52-58 % of the datapath suggests the placed result is likely thin
   and possibly negative; that is a hypothesis, **not** a measurement.
3. If the import crash cannot be worked around, record H-only as
   `implementation not evaluated (tool defect)` and keep the synthfix candidate
   provisionally, without claiming timing closure.