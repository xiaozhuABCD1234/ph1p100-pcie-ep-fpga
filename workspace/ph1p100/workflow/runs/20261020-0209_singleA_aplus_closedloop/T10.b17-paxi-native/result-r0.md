# T10.b17-paxi-native r0 — result

Date: 2026-10-26.  Run: `20261020-0209_singleA_aplus_closedloop`.
Candidate: `r0` (one source set; two synthesis attempts, the first interrupted at
the gate-DB handoff; one completed route; **0 bitgen/CWC, 0 downloads**).

## 0. Verdict

| dimension | verdict | evidence |
|---|---|---|
| functional | **PASS (offline)** | 16-word native test; S1/S2/S3; P1 three goldens; v6 structure; five negative controls |
| engineering | **STOP (timing floor)** | Routed 0 violations, SWNS **+0.002 ns** < +0.003 floor; ERAM 102/300; **no bitgen/CWC** per dev-plan §6 |
| system / board | **blocked (FTDI absent)** | `r0/board/log/board_blocked.txt`: `FTDI_PRESENT=0`, 0 downloads, 0 COM8 |

The parent task T10 remains blocked; this package does not close it.  The board
branch is the contract's `board_blocked` branch (external hardware absent), not
a FAIL of the offline candidate.  The build branch is the contract's hard
stop: WNS below +0.003 stops before bitgen, so no bit/CWC exists to download.

## 1. The three native PAXI contracts

Implemented only at the bridge's PAXI output; store/arbiter/camera top/shell
keep 256-bit word indices (see `r0/diag/paxi-native-contract.md`).

| contract | implementation | independent check |
|---|---|---|
| address ×8 | `paxi_awaddr={wf_rdata[279:256],3'b000}`, `paxi_araddr={af_rdata[23:0],3'b000}` | 16-word TB records AW/AR = 0,8,…,120; b15 bridge control = 0,1 → `bad_low3=1` |
| write mask | `paxi_wstrb=32'h0000_0000` | model merges bit=0 as enable; all-ones overwrite leaves the first value; b15 bridge `mask=2`, word 0 mismatch |
| single command | `ALLOW_CONCURRENT=0`; `wr_start_req`, `rd_req`, write-priority AR suppression; AR only in `W_IDLE` | clean chain `same_req=same_hs=0`; `ALLOW_CONCURRENT=1` comparison `same_req=1/same_hs=1` |

Range/low-3 monitors: `oob_addr_seen`, `low3_nonzero_seen`,
`wstrb_nonzero_seen`; OOB in simulation is `$fatal`, no synthesized branch.
`PAXI_MAX_WORD=424313`; address 424313*8 = 3,394,504 fits 27 bits.

## 2. 16-word write-stop-read (first gate)

`r0/sim/tb_b17_paxi_native.sv`, CASE=main:

```text
B17_NATIVE_RESULT pass=1 words=16 aw_hs=16 w_hs=16 commit=16 ar_hs=16 r_hs=16
bad_low3=0 oob=0 mask=0 same_req=0 same_hs=0 last_ar=120 low3=0 wstrb_bad=0
```

- 16 distinct 256-bit patterns written to internal words 0..15; write stopped
  until all 16 commits were observed plus 40 `clk_ddr` cycles; 16/16 read back
  byte-identical.
- AW and AR address sequences are exactly 0,8,16,…,120; every W handshake has
  `paxi_wstrb=0`; `last_issued_ar_addr=120`, low3=0.

## 3. Chain matrix

`r0/sim/tb_b17_chain.sv` + `r0/sim/check_b17.py` (44 B header, four CRCs,
strict zlib EOF, independent RAW/xform reference, b15 read-path monitors, v6
status parser).

| ID | geometry | result |
|---|---|---|
| S1 | 3864×2192 → ROI 972/556 → 1920×1080, 1 frame | **PASS**: `exported=enc=cap=raw_pub=1`, `source_groups=2,117,472`, `crop_beats=518,400`, `line_rises=2,192`, `frame_rises=1`, `raw_len=2,592,000`, four CRCs+zlib, no half frame; `timeout=retry=giveup=stale_guard=0`; `ar=r=rlast=210,685`; 253 v6 status packets; all b17 counters 0 |
| S2 | same, 2 frames | **PASS**: `exported=enc=cap=raw_pub=2`, `source_groups=4,234,944`, `crop_beats=1,036,800`, `line_rises=4,384`, `frame_rises=2`, four CRCs+zlib both frames (ids 1,2), no half frame; `timeout=retry=giveup=0`; `ar=r=rlast=421,370`; 254 v6 status packets; all b17 counters 0 |
| S3 | 72×10 → ROI 4/2 → 64×8, one R dropped at native address 16 | `PASS`: exported=1, timeout=1, retry=1, giveup=0, stale_guard=0, four CRCs+zlib, late R only stale, dup_words=0, `ar=56 r=55 rlast=55` (the dropped AR is the one outstanding), all native counters 0 |
| P1 | micro8x2 / mid64x8 / full_grad | `PASS`: compressed bytes SHA256 `FA513A2B…EDEF`, `EE61E620…9789`, `B992A8AD…ADA9`, byte-identical to the b15 caps; four CRCs + zlib; dup=0 |

S1/S2 counters also assert `b17_model_commit == b17_aw_hs == b17_w_hs`,
`b17_model_bad_low3=oob=mask=0`, `b17_model_sreq=shs=0`, and the b15 read
monitors (`rready_low=ar_busy_hs=short_burst=0`, `max_os=1`, `rf_ovf=0`).
Last native AR addresses: S1 `2,745,824` (=343,228×8), S2 `3,394,504`
(=424,313×8, the maximum legal word), both low3=0; no OOB fired.

## 4. v6 status packet

`tb_status_v6.v`: 4 consecutive packets, `B17_V6_DONE packets=4 bad=0 len=273
ver=6 fields=67`, `B17_V6_RESULT pass=1`.  Every chain packet is 273 B / VER 6 /
67 fields; `last_issued_ar_low3=0`; `diag_flags` bits1..5=0; `same_*_cnt=0`.
`parse_status_v6.py` parses the b15 v5 capture (151 packets, 0 noise) and
rejects a corrupted XOR (mutated packet becomes 241 resync bytes); see
`r0/board/captures/parser_selftest.json`.

## 5. Negative controls (must fail the old contract)

| control | result |
|---|---|
| frozen b15 bridge + b17 model | `B17_B15NEG_RESULT pass=1 bad_low3=1 mask=2 commit=2 word0_ok=0` — address and mask violations caught |
| all-ones mask overwrite | `B17_MASK_RESULT pass=1 mask_nonzero=1 commit=2 value_kept=1` — no byte written |
| low3=4 and word 424314 reads/writes | `B17_ADDR_RESULT pass=1 bad_low3=2 oob=2 commit=2` — counted, poison returned, no hang |
| `ALLOW_CONCURRENT=1` + permissive model | `B17_CONC_RESULT pass=1 same_req=1 same_hs=1 aw=12 ar=12` — the single-command checker is live; this build is **not** the candidate |

## 6. Build

**STOP at the timing gate; no bitgen/CWC.**

| item | value |
|---|---|
| synthesis | 2 runs (first interrupted by a run-manager event before gate.db; retried once, gate DB OK), SWNS **+0.127 ns**, ERAM 72 |
| route | 1 completed run (plus 1 aborted launch from the interrupted session), **0 violations / 26,705 endpoints** |
| setup WNS | **+0.002 ns** (STNS 0) |
| hold WNS | **+0.020 ns** (HTNS 0) |
| period check WNS | +2.200 ns |
| ERAM / limit | **102 / 300** |
| slices / regs | 25,113 (35.03%) / 29,262 |
| worst path | `u_a1/u_a1/u_core/len_r_reg[5]` → `add9_syn_221.fci`, **`a1_deflate_core.v` (frozen)**, not the v6 diagnostics |
| bitgen / CWC | **0 / 0** |

Dev-plan §6 floors WNS at +0.003 ns.  The observed +0.002 ns is below that
floor, and the allowed “v6-only register/pipeline” fix does not apply because
the critical path is inside the frozen A+ deflate core.  Per the frozen rules
the build stops here: **no bitstream, no CWC, no download**.  The 02_bitgen
STA check alone would accept +0.002 (it only rejects negative slack), but the
project gate is deliberately stricter and is not being relaxed.

Evidence: `r0/td/routed_timing_status.rpt`, `r0/td/routed_qor.rpt`,
`r0/td/routed_timing_summary.rpt`, `r0/td/routed_area.rpt`,
`r0/td/phy_pr_timing_flow.rpt`; the first interrupted run is preserved under
`r0/td/failed_r1/`.

## 7. Board

`r0/board/log/board_blocked.txt`:

```text
FTDI_PRESENT=0
board_blocked_reason=FTDI_0403:6042_absent
downloads=0
```

- FTDI preflight run before any COM8 access: no `VID_0403&PID_6042` device,
  COM8 absent.  Per dev-plan §7.1 this is `board=blocked`, not FAIL.
- 0 downloads, 0 COM8 opens, no Flash, no second bitstream.
- No board candidate exists anyway: the timing gate stopped before bitgen, so
  there is no `a1_board.bit` to download.  The v6 packet and failure-AR latch
  are exercised offline (`tb_status_v6`; S3 latched the exact dropped native
  AR address 16, low3=0, `diag_flags=1`).  A future run needs a new timing fix
  and a new bitstream; this package must not fabricate one.

## 8. Limits and rollback

- Claimed only: A path, single-frame export path, the frozen bit, offline
  simulation and the build result.  Not claimed: DDR sustained bandwidth,
  dual-A/B, PCIe/RK, Flash, production timing sign-off.
- G4 not run (no Flash/long-term stability).  G2/G3 are bound to this single
  candidate; board is blocked.
- Rollback: only `T10.b17-paxi-native/**`; the b15/b13 trees and production
  files are untouched.  `p2_ddr_bridge.v` back to b15 restores the old
  (non-native) contract, which is not a candidate.

## 9. Artifact index

`CANDIDATE-MANIFEST-b17-paxi-native-r0.json`, `r0/artifact-hashes.txt`,
`r0/rtl-diff-r0.patch`, `r0/diag/paxi-native-contract.md`,
`r0/diag/v6-fields.md`, `r0/sim/sim-results-b17-*.json`,
`r0/td/*` (synthesis/route reports; **no bit/CWC**), `r0/td/failed_r1/*`
(first interrupted run), `r0/board/*`.
