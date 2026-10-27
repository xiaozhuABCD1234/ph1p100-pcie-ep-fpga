# synth-187.5 (r1) - T10.ah-honly-td

**Result: synthesis SUCCEEDED on the synthfix DUT.** Gate DB, timing, area and
`flow.status` all exist. This is a synthesis (pre-placement) result only - no routed
result was obtained (see `routed-sta.md`).

## Run record

| Item | Value |
|---|---|
| Tool | TD Release_2026.2, Build **6.2.3.210850** |
| Command | `D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe ./01_synth.tcl` |
| cwd | `T10.ah-honly-td/r1/td/run-syn1` |
| Script | `run-syn1/01_synth.tcl`, SHA `784639c5…e2747a` (= canonical `r1/td/01_synth.tcl`) |
| DUT | core `d2960cfe…aad8` (85,221 B, synthfix), frame_top `4afc26e2…e30a` (29,207 B) |
| Strategy | default (`enable_seed=off`, `speedup_effort=0`), no seed sweep |
| Hard timeout | 1,800 s; **actual 43.47 s**; not timed out |
| `wait_run syn_1` | `PRJ-1406 : Run syn_1 finished.` |
| Script end | `AH_SYN_RUN_COMPLETE` (the exit-0 branch: all three reports exist) |
| Reports | `a1_ah_gate.db` 2,324,352 B; `a1_ah_gate.timing` 103,446 B; `a1_ah_gate.area` 2,968 B; `flow.status` 1,513 B |

Flow statistics from `flow.status`: `optimize_rtl` 5 s, `optimize_gate` 31 s,
`import_device` 2 s, `read_sdc` 0 s; total 38 s (81 % in `optimize_gate`).

## Timing summary (synthesis gate, confidence = Synthesized)

| Metric | Value |
|---|---|
| SWNS (setup) | **+0.029 ns** |
| STNS (setup) | 0.000 ns |
| HWNS (hold) | +0.000 ns |
| HTNS (hold) | 0.000 ns |
| `flow.status` Setup | `WNS 29ps  TNS 0ps  NUM_FEPS 0` |
| `flow.status` Hold | `WNS 2147483647ps  TNS 0ps  NUM_FEPS 0` (sentinel = no failing hold endpoint) |
| Period Check WNS | 2.533 ns |
| STA coverage | **97.06 %** |
| Violated / total endpoints | **0 / 4,969** |
| Timing mode | basic, corners Slow+Fast, CRPR enabled |
| Clock | one: `clk` 187.512 MHz, fanout 1,771, period 5.333 ns |
| Report scheme | 10 endpoints per path group, 1 path per endpoint |

## Area (synthesis gate, `syn_gate_area.rpt`)

| Metric | Value | Device | Util |
|---|---:|---:|---:|
| `#slice*` | 3,337 | 71,680 | 4.66 % |
| `#reg` | 1,663 | 143,360 | 1.16 % |
| `#lut` | 4,188 (lut6 1,978) | - | - |
| `#eram` | 27 (all eram20k) | 300 | 9.00 % |
| `#fifo20k` | 0 | - | - |
| ERAM+CWC | **27** | 300 | 9.00 % |
| `#dsp` | 0 | 220 | 0.00 % |
| `#IO` | **121** (48 in / 73 out / 0 inout) | 286 | 42.31 % |
| `#pcie` | 0 | 1 | 0.00 % |
| f7mux / f8mux | 0 / 0 | - | 0.00 % |

The IO count 121 equals exactly the wrapper port total (2 + 40 + 6 + 41 + 32), so the
folded `st_dbg` bus works as intended and the design fits the 286-IO device at block
level. All these are **synthesis estimates**, not placed/routed numbers.

## Worst 10 setup paths (synthesis gate)

| # | Slack (ns) | Begin | End | Data delay | Levels |
|---:|---:|---|---|---:|---:|
| 1 | 0.029 | `u_dut/grp_in_row_reg[3]` | `u_dut/smem_waddr_r_reg[15]` | 5.240 | 7 |
| 2 | 0.071 | `u_dut/grp_in_row_reg[3]` | `u_dut/smem_waddr_r_reg[14]` | 5.198 | 7 |
| 3 | 0.154 | `u_dut/u_core/htab_b` (RAM out) | `u_dut/u_core/hb_r_reg` | 5.115 | 5 |
| 4 | 0.213 | `u_dut/u_core/sdata_ptr_reg[4]` | `u_dut/u_core/state_reg[0]` | 5.056 | 7 |
| 5 | 0.213 | `u_dut/u_core/sdata_ptr_reg[4]` | `u_dut/u_core/state_reg[2]` | 5.056 | 7 |
| 6 | 0.213 | `u_dut/u_core/sdata_ptr_reg[4]` | `u_dut/u_core/state_reg[4]` | 5.056 | 7 |
| 7 | 0.224 | `u_dut/u_core/len_r_reg[2]` | `u_dut/u_core/cand_bits_reg[31]` | 5.045 | 6 |
| 8 | 0.276 | `u_dut/u_core/len_r_reg[2]` | `u_dut/u_core/cand_bits_reg[30]` | 4.993 | 6 |
| 9 | 0.298 | `u_dut/u_core/len_r_reg[2]` | `u_dut/u_core/cand_bits_reg[27]` | 4.971 | 6 |
| 10 | 0.316 | `u_dut/u_core/sdata_ptr_reg[4]` | `u_dut/u_core/state_reg[1]` | 4.953 | 7 |

All ten are setup checks at `slow_125c`, clock skew 0.000 ns. P1/P2 are in
`a1_frame_top` (plane/row -> smem write address arithmetic, 7 LUT levels, 58 % net
delay); P3-P10 are inside `a1_deflate_core`.

## Interpretation guard

+0.029 ns of setup margin at synthesis is **not** evidence that the placed & routed
design closes: placement adds net delay (here 42-58 % of the datapath is already net
delay at gate level) and the same family historically landed near 0.0 ns. Only a routed
STA may be used for the eligibility decision. No clock was relaxed and no exception was
added to obtain this number.