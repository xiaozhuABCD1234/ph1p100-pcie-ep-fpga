# T10.b9-rawstore r0 lessons

Reusable root cause / trigger / fix / verification entry points. Only what is
worth carrying into the next task.

## 1. Control events need their own beat (F1)

- **Trigger**: `a1_raw_crop` raises `out_abort` for exactly one `clk_cam` cycle
  with `out_valid = 0` in that cycle; the CDC writes only `crop_valid` beats.
- **Symptom**: the abort never reaches the A1 side, the slot store stays in
  `WRITE` forever, every later `wr_begin` is silently refused, and **no counter
  moves** (`raw_drop` stayed 0 for 3300 frames on the board).
- **Fix**: push the abort as its own FIFO beat (`w_valid = crop_valid |
  abort`), with `abort_hold` keeping the request until the FIFO accepts it, so a
  full FIFO cannot swallow the only abort of a frame. One abort = one FIFO
  entry, no DDR write.
- **Verification**: `tb_raw_store +CASE=abort` (slot returns to FREE,
  `abort_cnt=1`, `dropped=1`) and the camera-side abort/overflow case.

## 2. "Wait for ready" must never mean "drop the frame" (F2)

- **Trigger**: `e_sof` with `!raw_begin_ready` held `fifo_ready = 0`, and
  `capture_async_fifo.w_ready` was left unconnected.
- **Symptom**: the 512-deep FIFO fills, the write side silently discards beats
  (`push = w_valid && w_ready`), `raw_drop` still reads 0 — the board evidence
  "raw_drop = 0" therefore proved nothing.
- **Fix**: a rejected SOF latches `skip_frame`, the whole frame is consumed
  (`fifo_ready = 1`) and counted (`raw_begin_deny` + reason), and the camera
  side counts offers that were not accepted (`fifo_ovf_cnt`). Never a
  half-written frame, never a silent drop.
- **Verification**: `tb_raw_store +CASE=nofree` (3rd begin refused, no beat
  accepted, 0 store errors, recovery after readback).

## 3. Pop only on the handshake, drive only when the far side is ready (F3)

- **Trigger**: `af_pop = af_rvalid && paxi_arready && ddr_rdy` (no
  `paxi_arvalid`), `paxi_arvalid = af_rvalid && !ar_pending` (no `ddr_rdy`).
- **Symptom**: an address could be popped without ever being issued (read
  stalls on that word forever) or the same address re-issued while `ddr_rdy`
  was low (duplicate read data). Negative control with the b8 bridge on the same
  testbench: the store returns word 0 for every word and never finishes.
- **Fix**: `paxi_arvalid = af_rvalid && !ar_pending && ddr_rdy`,
  `af_pop = paxi_arvalid && paxi_arready`, `ar_pending` set by the AR handshake
  and cleared by `paxi_rvalid && paxi_rready` only.
- **Verification**: `tb_raw_store +CASE=rdy` (ddr_rdy bursts low during
  readback): 129,600 AR handshakes for 129,600 words, byte-exact, 0 duplicates.

## 4. A one-cycle request plus a dynamic ready loses the request (F4)

- Once `ddr_ready` is the real (synchronised) DDR readiness instead of `1'b1`,
  a 1-cycle `wr_begin` pulse can be sampled while `wr_begin_ready` is low and is
  then lost, leaving the store in `WRITE` with `wr_active = 0` and the beats
  silently discarded. `wr_begin` is now a **level held until the handshake**
  (`begin_pend` + `begin_hs`), and `raw_begin_ok` counts handshakes, not pulses.
- P2 drives `i_ddr_rdy` from the existing 2-FF `ddrphy_rdy` synchroniser, so no
  new clock-domain crossing was added.

## 5. Status packet v3: one edge, all 43 fields

- The v2 packet already latched 8+15 fields on the packet-start edge; v3 adds
  20 raw-store fields to the **same** edge (`{rawsnap, camsnap, ssnap}`), so no
  per-field resampling and no multi-bit CDC.
- Cheap tear test that actually rejects a bad implementation: drive field *k*
  with `cnt + k` where `cnt` increments every clock; inside one packet the set
  `{(field_k - k) mod 2^32}` must have exactly one member
  (`tb_status_v3 +MODE=1`). A per-field resample produces >1.
- `dbg_uart.v` is **not** the packer (it is the 50 MHz text logger inside
  `f9p_camera_display_core`, and its `O_uart_txd` is unconnected in
  `p2_a1_board_top`). The 97-byte v2 / 177-byte v3 packet is generated in
  `a1_uart_export.v`; planning text that points at `dbg_uart.v` is a naming
  error to check against the file list before editing.
- `sidx` had to grow from 7 to 8 bits with the 177-byte packet (176 > 127); the
  `sxacc`/`STS_LAST` mechanism itself is length-generic.

## 6. Testbench-own pitfalls that cost most of the debug time

- **Assert-then-wait race**: `req = 1; @(negedge clk); while (!ready) ...` lets
  the DUT accept the request during the posedge *before* the first check, then
  the TB waits for a ready that is already gone. Check ready **first**, then
  assert, then one posedge, then deassert.
- **A behavioural DDR model must reset its own timebase.** An unreset `tick`
  used in `awready = !(tick % N == 0)` is X forever, so nothing ever handshakes
  and the DUT looks broken.
- **Model counters are part of the test.** `n_ar_hs == words_read` caught the
  F3 defect; without that assertion a lost/duplicated AR looks like "slow".
- Two non-blocking assignments to the same counter in one `always` block (push
  and pop on the same edge) silently drop the increment; use a `case ({push,
  pop})`.
- An 8-entry address queue indexed by a full 4-bit pointer reads `X` from
  entries 8..15: mask the index (`ptr[2:0]`). This produced exactly 8 good words
  followed by X and looked like an RTL bug.
