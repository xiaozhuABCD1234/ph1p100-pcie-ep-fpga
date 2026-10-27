# tb-stimulus-fix.md — V1 `T11.BRD.P1:TB_CAM_STIMULUS_WIDTH` (round 2)

Scope: **testbench only**. No DUT/RTL/constraint/filelist byte changed
(`evidence/r1-r2-sha-diff.md`: `rtl_delta=0`, `constraints_delta=0`,
`filelist_delta=0`). The DUT was not touched to match any golden.

## 1. The r1 defect

`r1/sim/tb_brd_g1_r1.v` L693:

```verilog
cam_pix <= {4{(line*32 + grp) & 10'h3FF}};
```

`(line*32 + grp) & 10'h3FF` is a **32-bit** expression, so `{4{...}}` is a
128-bit replication truncated to the 40-bit `cam_pix`. The four 10-bit lanes
became `(v, 0, 0, v[7:0]<<2)` instead of the documented `(v, v, v, v)`:

| lane | r1 value |
|---|---|
| P0 = cam_pix[9:0] | `v` |
| P1 = cam_pix[19:10] | `0` |
| P2 = cam_pix[29:20] | `0` |
| P3 = cam_pix[39:30] | `{v[7:0], 2'b0}` = `(v & 0xFF) << 2` |

The DUT then faithfully packed those malformed beats, so the r1 TB scoreboard
(`raw == pk_bytes.bin`, the DUT's own packer output) passed while proving
nothing about pixel correctness (r1 §5.3 V1).

## 2. The r2 fix (`sim/tb_brd_g1_r2.v`)

| location | change |
|---|---|
| L328 | `reg [9:0] cam_val = 10'd0;` — dedicated 10-bit stimulus value |
| L768-L776 (stimulus loop) | `cam_val = (line*32 + grp) & 10'h3FF;` (**blocking**) then `cam_pv <= 1'b1; cam_pix <= {4{cam_val}};` |
| L546-L597 | stimulus probe: writes `tb_probe_r2.txt`, counts `stim_lane_bad` / `stim_chain_bad`, latches `stim_first_v` / `pk_first` |
| L730-L736 | probe values also written into `sim_meta.txt` (`stim_*`, `pk_first`, `pk_bytes_len`, `raw_crc`, `xform_crc`) |
| L863-L869 | prints `STIM first_v=… lane_bad=… chain_bad=… pk_first=…` and `STIM_PROBE=PASS/FAIL` |

Why blocking: `cam_val` must carry the **current** group on the beat that is
driven. A non-blocking `cam_val <= …` would replicate the *previous* value and
shift every group by one beat — exactly the 1-group lag the r1 tester measured
on their own variant (first pixel 519 instead of 520).

Frozen contract the stimulus now satisfies (dev-plan §12.2 S2.2 / design guide
R2 §2): rows `r∈[16,63]`, groups `g∈[8,23]`, `v=(r*32+g)&0x3FF`, four identical
pixels per beat, packed offset `((r-16)*16+(g-8))*5`, `byte0..3=v[9:2]`,
`byte4={v[1:0] x4}`, raw `48*16*5 = 3840 B`, first group `v=520`.

## 3. Probe evidence (frozen r2 TB, `sim/scen0`, PREP=0 PRED=0)

`sim/scen0/tb_probe_r2.txt` (first 8 accepted A+ groups):

```text
n=0 v=520 cam=83a0e83a0e bpix=8220882208 cap=8220882208 sdata=8220882208 pk=0082828282 lanes=520,520,520,520
n=1 v=521 cam=8561585615 bpix=8260982609 cap=8260982609 sdata=8260982609 pk=5582828282 lanes=521,521,521,521
n=2 v=522 cam=8761d8761d bpix=82a0a82a0a cap=82a0a82a0a sdata=82a0a82a0a pk=aa82828282 lanes=522,522,522,522
n=3 v=523 cam=88a2288a22 bpix=82e0b82e0b cap=82e0b82e0b sdata=82e0b82e0b pk=ff82828282 lanes=523,523,523,523
n=4 v=524 cam=8aa2a8aa2a bpix=8320c8320c cap=8320c8320c sdata=8320c8320c pk=0083838383 lanes=524,524,524,524
n=5 v=525 cam=8c6318c631 bpix=8360d8360d cap=8360d8360d sdata=8360d8360d pk=5583838383 lanes=525,525,525,525
n=6 v=526 cam=8e6398e639 bpix=83a0e83a0e cap=83a0e83a0e sdata=83a0e83a0e pk=aa83838383 lanes=526,526,526,526
n=7 v=527 cam=8fe3f8fe3f bpix=83e0f83e0f cap=83e0f83e0f sdata=83e0f83e0f pk=ff83838383 lanes=527,527,527,527
```

| evidence item | required | measured |
|---|---|---|
| four 10-bit lanes of `cam_pix` | all equal | `stim_lane_bad = 0` over all 768 accepted groups |
| `bpix` (FE/crop) == `cap` (P4 capture) == `sdata` (packer input) | equal | `stim_chain_bad = 0` |
| first accepted group value | 520 = `(16*32+8)&0x3FF` | `stim_first_v = 520` |
| first packed bytes | `82 82 82 82 00` | `pk_first = 0082828282` |
| packed byte count | 3840 | `pk_bytes_len = 3840` |
| no group lag | first group 520, then 521,522,… | probe `n=0..7` = 520..527 (increment of 1, no shift) |

`cam=` in the probe is sampled in the core-clock domain and therefore shows a
later group than the accepted beat (camera byte clock 187.5 MHz vs core
150 MHz); only its **lane equality** is asserted, not its group index.

The TB's own `STIM_PROBE=PASS` marker is emitted by all four top-level runs
(SCEN0/3/4 and PREP) and the values are re-checked independently from
`sim_meta.txt` by `evidence/verify_slot_r2.py`
(`stim_lane_equal`, `stim_chain_equal`, `stim_first_v_520`, `stim_pk_first`,
`stim_pk_len`).

## 4. What the fix does NOT change

- The DUT, the SDC/ADC, the filelist, the P4/img/b20 sources: byte-identical to
  r1 (SHA table in `evidence/r1-r2-sha-diff.md`).
- The r1 scoreboard checks in the TB are unchanged; `raw == pk_bytes` was and
  remains an **additional** self-consistency check only. The judged byte
  criterion is now `raw == expected_raw.bin` from the independent model
  (`evidence/gen_expected_raw.py`).
- No golden value was used to tune the stimulus; the stimulus follows the frozen
  contract and the golden is derived from that contract.
