# T11.BRD.P1 r1 — lessons (root cause / trigger / fix / verification entry)

1. **A pusher "ARM" is not a status strobe.** `ddr_frame_pusher` latches
   `last_seq <= src_seq` on the accepted ARM and only pushes a **new** source
   sequence. With a `capture_seq` that only changes on the next admission (i.e.
   after ACK), the pipeline deadlocks: early ARM -> frame_bytes=0 rejected,
   late ARM -> no event. Fix: board `brd_export_seq` defers the ARM until a
   published descriptor exists and emits one board-owned event after the
   pusher enters G_ARMED. Entry point: `+SCEN=0/3/4`, `evt_cnt`, `armed_q`.
2. **The pusher 0xC4 bit order is bit0=ARMED, bit1=tx_active, bit2=HELD** (the
   old header comment is stale). The r0 datapath read bit1 as held and bit0 as
   busy, so the P4 egress adapter and the board both mis-saw the state. Entry
   point: `p_held_w/p_busy_w` and `tx_status` in the TB log.
3. **Descriptor release is by camera id.** r0 cleared `a_desc_active` when
   `rel_camera_id==1` (B) and vice versa, so the B descriptor never cleared and
   the board re-offered it. Fix: `if (rel_camera_id) b_desc_active<=0; else
   a_desc_active<=0`. Entry point: release counter, not `desc_active`.
4. **Two ACK identities existed.** The pusher ACKs against `held_seq`
   (doorbell value), the P4 egress adapter against `capture_seq`. They cannot
   both be right; align the adapter to the pusher done count. Entry point:
   wrong-ACK scenario (SCEN 2).
5. **A testbench that never drives the EP TX grant hides every TLP bug.** The
   r0 TB left `utx_sel` undriven; after F1/F2 the pusher hung in G_TX. Fix:
   drive the grant; then the DW lane order and per-DW byte swap matter
   (the pusher's first TLP DW is in the **highest** lane, and payload bytes are
   `bswap256`-ed). Entry point: TLP capture log, `mwr_count/bytes`.
6. **Publish is not "DDR committed".** The slot store asserts READY on the same
   cycle it issues the last 256-bit write. Dump/decode only after the export
   completion (or an explicit flush), otherwise the tail group can read zeros.
   This is the most plausible explanation of the r0 "Adler tail = 0" report;
   the unmodified b20 core passes both the core probe and the full path.
7. **`desc_active` is not a release flag.** The board immediately offers the
   next descriptor after a release; use the release counter (or a sticky
   release event) for PASS/FAIL.
8. **SDC groups are not documentation.** Putting `clk_core` in the same
   `set_clock_groups` line as `tl_clk_user` made the tool TIME the raw crossing
   (the r0 worst path). One clock per group + the C8/C9 2FF is the fix; the
   teammate must still run STA/CDC.
