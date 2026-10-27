# critical-path-attribution (r1) - T10.ah-honly-td

**Scope: synthesis gate (pre-placement) paths only.** No routed path list exists, so no
claim is made about the final implementation. The 10 worst setup paths below come from
`syn_gate_timing.rpt` (report scheme: 10 endpoints per path group, 1 path per endpoint),
confidence = Synthesized, corner slow_125c, clock skew 0.000 ns.

| # | Slack | Begin point | End point | Cone | Levels |
|---:|---:|---|---|---|---:|
| 1 | +0.029 | `u_dut/grp_in_row_reg[3]` | `u_dut/smem_waddr_r_reg[15].d` | frame_top (row/plane -> smem write addr) | 7 |
| 2 | +0.071 | `u_dut/grp_in_row_reg[3]` | `u_dut/smem_waddr_r_reg[14].d` | frame_top (same cone) | 7 |
| 3 | +0.154 | `u_dut/u_core/htab_b_syn_35` (hash RAM read) | `u_dut/u_core/hb_r_reg.d` | core scan/hash (htab -> match tag) | 5 |
| 4 | +0.213 | `u_dut/u_core/sdata_ptr_reg[4]` | `u_dut/u_core/state_reg[0].d` | core replay/emit -> FSM | 7 |
| 5 | +0.213 | `u_dut/u_core/sdata_ptr_reg[4]` | `u_dut/u_core/state_reg[2].d` | core replay/emit -> FSM | 7 |
| 6 | +0.213 | `u_dut/u_core/sdata_ptr_reg[4]` | `u_dut/u_core/state_reg[4].d` | core replay/emit -> FSM | 7 |
| 7 | +0.224 | `u_dut/u_core/len_r_reg[2]` | `u_dut/u_core/cand_bits_reg[31].d` | core cost/literal-abort cone | 6 |
| 8 | +0.276 | `u_dut/u_core/len_r_reg[2]` | `u_dut/u_core/cand_bits_reg[30].d` | core cost/literal-abort cone | 6 |
| 9 | +0.298 | `u_dut/u_core/len_r_reg[2]` | `u_dut/u_core/cand_bits_reg[27].d` | core cost/literal-abort cone | 6 |
| 10 | +0.316 | `u_dut/u_core/sdata_ptr_reg[4]` | `u_dut/u_core/state_reg[1].d` | core replay/emit -> FSM | 7 |

Corner/process note: all ten are `setup`, `slow_125c`; net delay is 52-58 % of the
datapath at gate level, which is why the synthesis margin (+0.029 ns) must not be read as
a placement-safe margin.

## Answers to the three required cones

1. **`a1_frame_top` dual CRC32 chain (`raw_crc`/`xform_crc`/`stream_crc` update
   networks): NOT in the worst 10.** The two frame_top entries are the
   `grp_in_row` -> `smem_waddr_r` plane/row address arithmetic. The CRC chains are not
   implicated by this report, but they are also not proven fast: they are simply outside
   the 10 reported endpoints, and STA coverage is 97.06 % (see
   `cdc-and-check-timing.md`).
2. **`a1_deflate_core` replay/emit cone: YES, dominant - 8 of 10 paths.** Six of them
   start at `sdata_ptr` (replay/emit byte pointer) or `len_r` (match length) and end in
   the core FSM (`state_reg`) or the cost accumulator `cand_bits`; the third is
   `htab_b` -> `hb_r` (hash table read into the match tag register).
3. **Scan cone (2-position literal scan / hash probe): present but not the worst.**
   P3 (`htab_b` RAM read -> `hb_r`) is the tail of the hash probe; P7-P9 (`len_r` ->
   `cand_bits`) are the candidate-cost arithmetic that the literal-abort decision uses.
   The literal-reverse / bit-packing scan itself does not appear in the top 10.

## Hierarchy and file attribution

`a1_ah_eng_top.u_dut` = `a1_frame_top` (frame_top paths reference
`.../T10.ah-honly-synthfix/r0/changed-src/a1_frame_top.v`); `u_dut.u_core` =
`a1_deflate_core` (references `.../a1_deflate_core.v`). No path in the list crosses a
clock domain; there is exactly one clock (`clk`, fanout 1,771).

## What is still missing

- A routed path list (start/end/hierarchy after placement) - absent.
- Any statement about `hold` paths per cone: `flow.status` hold `NUM_FEPS = 0` with the
  `2147483647 ps` sentinel means no hold endpoint failed at gate level; per-cone hold
  attribution is not available without a routed report.