# T10.b17 native PAXI boundary contract — implementation evidence

Package: `T10.b17-paxi-native` r0.  Baseline: `T10.b15-ddr-pace/r0/changed-src`
(11 files, hashes frozen in `CANDIDATE-MANIFEST-b17-paxi-native-r0.json`).

The three contracts below are implemented in exactly one place, the PAXI output
of `r0/changed-src/p2_ddr_bridge.v`.  Store / arbiter / camera top / shell keep
using 256-bit **word indices**; there is no second `*8` anywhere.

## 1. Address unit

Internal word index (unchanged, 27-bit FIFO payload):

| path | baseline | b17 |
|---|---|---|
| WF payload | `{s_awaddr[26:0], s_wdata[255:0]}` | unchanged |
| AF payload | `s_araddr[26:0]` | unchanged |
| store/arb/camera top | `BASE_WORD + slot*SLOT_WORDS + idx` | unchanged |

Only conversion (bridge, AW and AR):

```verilog
assign paxi_awaddr = {wf_rdata[279:256], 3'b000};  // word index * 8
assign paxi_araddr = {af_rdata[23:0],   3'b000};   // word index * 8
```

- Word 0/1/2 appears on PAXI as 0/8/16; word 15 as 120.
- `PAXI_MAX_WORD = 24'd424313`; 424313*8 = 3,394,504 fits the 27-bit port.
- Range check (combinational, evaluated only while the source FIFO holds a
  word): `aw_idx_oob = wf_rdata[282:256] > PAXI_MAX_WORD`,
  `ar_idx_oob = af_rdata > PAXI_MAX_WORD`; sticky `oob_addr_seen`.
- Low-3 monitor on the actual output: `paxi_awaddr[2:0]` / `paxi_araddr[2:0]`
  must be 0; sticky `low3_nonzero_seen`.
- Simulation (`ifdef SIMULATION`): an OOB word reaching a valid PAXI command
  raises `$fatal("B17_PAXI_OOB_ADDR ...")`.  No synthesized deadlock branch.
- 16-word test observes AW/AR addresses 0,8,16,...,120 (TB arrays
  `aw_seen_addr[]`/`ar_seen_addr[]`), `last_issued_ar_addr==120`.

Model (`r0/sim/p2_paxi_model_b17.v`): `word = addr[26:3]`, `addr[2:0]` must be
0, `word > 424313` is OOB.  Bad writes are consumed and counted, never written;
bad reads return poison (`BAD0…`) with `rlast=1`, so they neither alias nor hang.

## 2. Write mask

```verilog
assign paxi_wstrb = 32'h0000_0000;   // native contract: mask 0 writes every byte
```

Native semantics (from the vendor mtest full-write path `wmask_phase=0` and the
repo-native `ddr_frame_store`: “mask 0 writes every byte”):

- `wstrb[i] == 0` enables byte i; `wstrb[i] == 1` preserves the old byte.
- all-zero = full 32-byte word write; all-ones = write nothing.

The model merges byte-wise and counts any non-zero mask (`n_mask_nonzero`).
Negative controls (all PASS as *failures* of the old contract):

| control | observation |
|---|---|
| all-ones-mask overwrite | memory keeps the first value; `n_mask_nonzero=1` |
| b15 bridge (all-ones) | `mask=2`, word 0 does not read back |

Board monitor: sticky `wstrb_nonzero_seen` (`diag_flags[5]`), must be 0.

## 3. Single-command acceptance (AW/W vs AR)

Parameter `ALLOW_CONCURRENT = 0` (bitgen/board value).  Arbitration:

```verilog
wr_start_req = wf_rvalid && !wf_pop && ddr_rdy && !ar_busy;
rd_req       = af_rvalid && !ar_busy && rf_path_empty && ddr_rdy && !rd_hold &&
               (ALLOW_CONCURRENT || wstate == W_IDLE);
paxi_arvalid = rd_req && (ALLOW_CONCURRENT || !wr_start_req);
```

- `W_IDLE -> W_RUN` only on `wr_start_req`; `paxi_awvalid/paxi_wvalid` exist only
  in `W_RUN`; `paxi_arvalid` exists only in `W_IDLE`.  Therefore AW+AR and
  W+AR can never handshake in the same cycle.
- Write priority: if a write start and an AR request coincide, the AR valid is
  dropped before any ready, the AF entry is kept, and the AR is re-presented
  after the write command completes.
- AW and W still handshake together as one single-beat write (`wlast=1`).
- `ALLOW_CONCURRENT=1` is comparison-only.  It also removes the `W_IDLE` term
  so the generated request concurrency is observable.  Negative control with a
  permissive model: `n_same_req=1`, `n_same_hs=1`.  It is **not** used by the
  bitgen/board candidate (verified in `r0/td` and the manifest parameter view).

Model side: `awready`/`arready` are never high in the same cycle except in the
explicit `ALLOW_BOTH_READY=1` comparison instance; every clean run reports
`n_same_req=n_same_hs=0`, `n_write_commit == n_aw_hs == n_whs`.

## 4. Preserved b15 read strictness

Unchanged semantics: `ar_busy` set by AR handshake and cleared only by
`rvalid && rlast` (or b13 purge/guard force-clear); `paxi_rready=1`;
`rf_path_empty` pre-gate; `TIMEOUT=8192`, `RETRY_MAX=2`, `A1_GUARD_N=70000`,
`BRIDGE_GUARD_N=65536`, `A1_PURGE_N=4`, `DDR_PURGE_N=4`, `rd_abort` toggle
synchronizer, `s_arready` guard window.  All b15 read monitors are still
asserted by `check_b17.py` (`b15_rready_low`, `b15_ar_busy_hs`,
`b15_short_burst`, `b15_rf_ovf`, `b15_max_os`, `b15_stale_r`).
