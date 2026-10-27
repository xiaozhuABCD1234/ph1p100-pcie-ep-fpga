# cdc-and-check-timing (r1) - T10.ah-honly-td

**Status: `check_timing` and `report_cdc` were NOT executed.** They are issued by
`02_route.tcl` after a routed database exists; both route attempts crashed inside
`import_db` (see `routed-sta.md`), so the flow never reached them. No CDC report, no
unconstrained-path report, no generated-clock or loop report exists for r1.

## What is known from the design and the synthesis run

| Item | Evidence |
|---|---|
| Clock domains | Exactly one: `clk`, 187.512 MHz, fanout 1,771 (timing report clock summary); `a1_ah_eng_top` has no other clock port |
| Constraint file | `r1/td/a1_ah_small_top.sdc`: a single `create_clock -name clk -period 5.333 -waveform {0.000 2.667}`; no false_path, no multicycle, no clock group, no generated clock, no IO exception |
| Reset | asynchronous active-low `rst_n`, single domain, no synchroniser needed |
| CDC structures | none instantiated in this block-level top (no asynchronous FIFO; the UART export subsystem with `clk_uart` is outside this wrapper) |
| STA coverage | **97.06 %** at synthesis (4,969 total endpoints, 0 violated). The uncovered ~2.94 % is not itemised here because `check_timing` never ran; it must not be described as "clean" |
| Timing mode | `basic`; corners Slow+Fast; CRPR enabled; `Period Check WNS` 2.533 ns |

## Known, recorded gaps (unchanged from the frozen design guide)

1. **Block-level I/O are unconstrained** (internal SoC ports, not package pins). I/O
   timing is therefore out of scope for this flow and no IO constraint was fabricated to
   make a check pass.
2. **No per-domain CDC evidence** - there is only one domain, but the formal
   `report_cdc` output that would document it is missing.
3. **No `check_timing -verbose` output**, so unconstrained endpoints inside the 2.94 %
   coverage gap are unlisted rather than proven benign.

Verdict wording for the record: CDC/constraints are **unverified**, not verified-clean.