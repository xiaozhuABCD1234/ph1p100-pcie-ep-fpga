# W1 — PAXI read-path facts (T10.b15-ddr-pace r0)

Every number below is taken from a frozen file or a frozen board capture; nothing
is assumed. Absolute paths are relative to the project root `D:/fpga/ph1p100`.

## 1. `L_max` = 1 beat per AR (evidence, not assumption)

| # | Evidence | Value | Source path |
|---|---|---|---|
| E1 | The PAXI port has **no burst-length input**: `paxi_araddr/arvalid/arready` and `paxi_rdata/rlast/rvalid/rready` only. `axi_arlen` exists only in the unused AXI variant of the same wrapper (`axi_arlen; 0` = not generated) | length is fixed by the MC | `workflow/runs/.../T10.b13-ddr-retry/r1/td/src/vendor/ip/ddrmc_x32/.ports_ddrmc_x32.txt` |
| E2 | Port widths: `MC_ADDR_WIDTH 27`, `MC_DATA_WIDTH 256`, `MC_MASK_WIDTH 32` (one 32 B word per beat) | 256 bit / 32 B | same IP `.params_ddrmc_x32.txt` lines 110-112 |
| E3 | Board capture b14 r0 (150 v5 packets, 4 550 frames): `ar_cnt = 17,213,681`, `r_cnt = 17,200,031`, `rlast_cnt = 17,200,031` | **r/ar = 0.99921 → exactly one R per AR**; if the MC returned L ≥ 2 beats per AR, r would be ≥ 2×ar | `workflow/runs/.../T10.b14-cam-b/r0/board/captures/status_v5.json` (last packet) |
| E4 | Same capture: `ar_cnt − r_cnt = 13,650 = ar_cnt − rlast_cnt = 13,650`, `stale_r_cnt = 0`, `stale_guard_cnt = 0` | the missing beat is the **only** beat of the failed AR; nothing arrived late | same |
| E5 | The frozen b13 simulation model answers every AR with exactly one beat and `rlast = 1` (`assign rlast = 1'b1;`) | 1 beat, rlast on that beat | `.../T10.b13-ddr-retry/r0/sim/p2_paxi_model_b13.v` line 73 |

**Conclusion: `L_max = 1`, `paxi_rlast` is asserted on the single beat of every
AR.** Design-guide §2.1 also allows the conservative fallback `L_max =
RF_DEPTH`; with `RF_DEPTH = 16` the no-overflow argument below holds for both
`L_max = 1` and the conservative `L_max = 16`, so **no `ADDR_BITS` change is
needed** (RF stays `WIDTH=256, ADDR_BITS=4`, 16 entries) and none was made.

## 2. `paxi_rdata` / `paxi_rlast`

- `paxi_rdata[255:0]` = 32 B per beat (E2). One AR = one 32 B store word; the
  A1 slot store issues one AR per packed word (`a1_ddr_slot_store.v`,
  `ddr_arvalid = (rd_state == R_AR) && !rd_armed`, `rd_armed` set by the AR
  handshake, cleared by one `ddr_rvalid`).
- `paxi_rlast` is the only signal that identifies the end of an owned burst
  (E5). T10.b15 therefore closes `ar_busy` on `rvalid && rready && rlast`
  only, never on the first R handshake.

## 3. Read-data FIFO (RF)

- Instance: `capture_async_fifo #(.WIDTH(256), .ADDR_BITS(4)) u_rf`
  (`p2_ddr_bridge.v` line 207) → **16 entries × 256 bit**.
- Write side `clk_ddr`, read side `clk_a1`, `w_ready = wr_reset[1] && !full`
  (`fpga/csi2/src/mem/capture_async_fifo.v` line 21): a beat presented while
  `w_ready = 0` is **dropped** by the FIFO, which is why the bridge must
  guarantee space instead of back-pressuring the PAXI R channel.
- One-deep output skid `s_rdata_r/s_rvalid_r` in `clk_a1` (unchanged, b12).

## 4. Occupancy counter (how "empty" is proved)

`rf_level = rf_push_cnt (clk_ddr) − rf_pop_sync (clk_a1, Gray, 2FF)`:

- the pop counter is Gray coded, so a sampled value is always a real (possibly
  stale) pop count → `rf_level` can only be **over**-estimated, never
  under-estimated → `rf_level == 0` really means the FIFO is empty;
- `rf_path_empty = (rf_level == 0) && skid_s1` (skid-empty level through 2FF).
- `rf_push_cnt` only counts beats the FIFO actually took (`rf_push && rf_wready`),
  so the counter cannot leak if the impossible happens.

## 5. Board-visible "one R short" and what the fix changes

b14 r0 measured `timeout=3, retry=2, giveup=1` per frame with `timeout=13,410`,
`retry=8,940`, `giveup=4,470` and `ar − r = 13,650 ≈ 1 per attempt`. The b13
bridge cleared `ar_pending` on the **first** R handshake and drove
`paxi_rready = r_expected ? rf_wready : 1`, i.e. it used R-channel
back-pressure to protect the RF. Every attempt lost exactly one beat and then
stalled for the 8 192-cycle timeout. T10.b15 removes both mechanisms:
`ar_busy` closes only on `rlast`, `paxi_rready` is constant 1, and a new AR is
only issued into an empty read-data path, so the RF can never overflow.
