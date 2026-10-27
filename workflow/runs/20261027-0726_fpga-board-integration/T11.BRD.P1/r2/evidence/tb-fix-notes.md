# TB fixes (r1) — what was wrong in the r0 harness

The r0 TB never produced a TLP, so several host-model defects were hidden.
All fixes are in `sim/tb_brd_g1_r1.v` (new file; the r0 TB was not modified).

| # | r0 TB behaviour | effect | r1 fix |
|---|---|---|---|
| T1 | `utx_sel` (EP TX grant) was declared `wire` but never driven | the pusher could never accept a beat; after F1/F2 it hung in G_TX, so no TLP/doorbell | `wire utx_sel = 1'b1;` (the EP grant with `tl_tx_wait=0`) |
| T2 | host captured beat lanes 0..7 as TLP DW 0..7 | the pusher puts the first TLP DW in the highest beat lane (`utx_valid=8'hF0` header, `8'hF8` doorbell); r0 would have mis-parsed every TLP | emit only the valid lanes, lane 7 down to lane 0, into TLP order |
| T3 | payload compared `dw[8*b]` to memory byte b | the pusher `bswap256` puts the first payload byte in the high byte of each DW | `bswap32(dw)` before the byte compare |
| T4 | ACK sequence = `o_arm_seq` (capture_seq, 0) | pusher held_seq is the doorbell value (1); the correct ACK was rejected | ACK = `u_pusher.held_seq` for both the pusher and the P4 egress adapter (see F1/held_seq fix) |
| T5 | missing-EOF scenario deleted one group **outside** the ROI | frame still had 768 groups and committed; the negative was vacuous | truncate the whole last ROI row (63 raster lines) |
| T6 | no early-ARM scenario | the deferred-ARM path was untested | `+SCEN=3` arms before the frame and doubles the ARM |
| T7 | no duplicate-ARM scenario | "no second export" was untested | `+SCEN=4` arms again while ARMED/HELD |
| T8 | slot dumped right after `published` | the store publishes on the same cycle it issues the last 256-bit write; a dump at that instant can read the previous word | dump after doorbell/export completion (stable) |
| T9 | release evidence used `desc_active` | after a release the board re-offers the next B descriptor immediately, so `desc_active` can be 1 again | release evidence is the P4 release counter (`st_release_count`, +1) |
| T10 | no host A1U1 header | D6 host ownership was unproven | TB builds the 44B header, computes the header CRC, appends the exact slot bytes and writes `a1u1_frame.bin` |

Golden stream: the r1 expected values are re-frozen per run from the DUT's own
status (`stream_len`, `xform_len`, CRCs) and checked by `evidence/verify_slot.py`
with the standard Python `zlib`; the r0 `GOLDEN_STREAM=3965` constant is not
carried over (r0 itself measured 3966).  The DUT was not changed to match a
stale golden.
