# W2 — strict single-AR read serialisation (R1–R5 → code)

Only `r0/changed-src/p2_ddr_bridge.v` changed (504 lines). Line numbers below
are from the frozen r0 file; the diff is `r0/rtl-diff-r0.patch`.

## R1 — `ar_busy` is the single "AR outstanding" flag

| item | code |
|---|---|
| declaration | `reg ar_busy;` — line 203 |
| set | `else if (af_pop_normal) ar_busy <= 1'b1;` — line 405 (`af_pop_normal = paxi_arvalid && paxi_arready`, line 397) |
| clear | `else if (paxi_rvalid && paxi_rready && paxi_rlast) ar_busy <= 1'b0;` — line 407 |
| purge/guard force-clear (b13 semantics kept) | `else if (purge_evt || rd_hold) ar_busy <= 1'b0;` — line 404 |
| b13 behaviour removed | `else if (paxi_rvalid && paxi_rready) ar_pending <= 1'b0;` (first-beat clear) |

`af_pop` still happens only on the AR handshake (`af_pop_normal`) or by the b13
purge (`af_pop_purge = rd_hold && af_rvalid`, line 399); no other path pops AF.

## R2 — AR issue condition (strict serial, MAX_OS = 1)

```verilog
assign paxi_arvalid = af_rvalid && !ar_busy && rf_path_empty &&
                      ddr_rdy && !rd_hold;                    // line 396-397
wire   rf_path_empty = (rf_level == 5'd0) && skid_s1;         // line 241
wire [4:0] rf_level  = rf_push_cnt - rf_pop_sync_bin;         // line 240
```

- `rf_level` = clk_ddr push counter minus the clk_a1 pop counter (Gray, 2FF,
  lines 229-270); it over-estimates occupancy, so `0` = empty.
- `skid_s1` = `!s_rvalid_r` through 2FF (lines 233, 258-270) → the one-deep
  output skid must be empty too.
- With `L_max = 1` (see `paxi-read-facts.md`) and this gate, the RF has ≥ 15
  free entries at every AR handshake → overflow is structurally impossible.
- `MAX_OS = 1`: there is no second outstanding-AR register, and
  `paxi_arvalid` is blocked while `ar_busy` is set. Simulated monitor
  `b15_max_os` (TB) must read 1 and `b15_ar_busy_hs` (AR handshake observed
  while `ar_busy`) must read 0.
- `MAX_OS = 2` was **not** used: the sims show 1 outstanding AR sustains the
  read stream far above the 77.76 MB/s frame budget (S1/S4 full frames export
  with `timeout = 0`; see `result-r0.md`).

## R3 — `paxi_rready` is constant 1

```verilog
assign paxi_rready = 1'b1;                                    // line 336
```
b13: `rd_hold ? 1'b1 : (r_expected ? rf_wready : 1'b1)`. The R channel is never
back-pressured; TB monitor `b15_rready_low` must be 0 for every clk_ddr cycle.

## R4 — every beat of an owned burst is pushed

```verilog
wire ar_busy_win = ar_busy;                                   // line 204
wire rf_push     = paxi_rvalid && paxi_rready && ar_busy_win;  // line 205
```
b13: `rf_push = paxi_rvalid && ar_pending` — a beat arriving with
`ar_pending = 0` was absorbed (`rready = 1`, no push). Now an owned beat is
always pushed; an orphan beat (`ar_busy = 0`, e.g. the timed-out attempt) is
still absorbed and only counted (`stale_r_cnt`, line 439; `stale_guard_cnt`,
line 433-434), never queued. TB monitor `b15_rf_ovf` (push while `!rf_wready`)
must be 0.

## R5 — b13 fallback kept verbatim

| item | value | location |
|---|---|---|
| store read timeout | 8 192 clk_a1 | `a1_ddr_slot_store.v` `TIMEOUT_N` (unchanged file) |
| retry budget | 2 | `a1_ddr_slot_store.v` `MAX_RETRY` (unchanged) |
| A1 guard | 70 000 clk_a1 | `A1_GUARD_N`, line 165 |
| bridge guard | 65 536 clk_ddr | `BRIDGE_GUARD_N`, line 277 |
| DDR / A1 purge | 4 / 4 | lines 142, 276 |
| `rd_abort` toggle + 2FF | unchanged | lines 278-295 |
| `s_arready` gate (`!a1_purge_act && !a1_ar_hold_act`) | unchanged | line 173 |
| timeout / retry / giveup counters (v5 #56/#57/#58) | unchanged semantics | `a1_ddr_slot_store.v` |

Regression: b13 store `clean/retry/guard/budget` and b12 R1 `clean/loss`,
T7 SOF, b12 store T3–T6 all re-ran on the b15 source set and pass
(`r0/sim/sim-results-b15-regress.json`).

## Observation bits (unchanged packet)

- `br0[1]` (v5 debug word) keeps the meaning "an AR is outstanding" and is now
  driven by `ar_busy` (`br0_ddr`, line 468).
- No field was added, removed or reordered: v5 stays 241 B / 59 fields
  (S5 re-ran `tb_status_v5` → `B13_V5_RESULT pass=1`).
