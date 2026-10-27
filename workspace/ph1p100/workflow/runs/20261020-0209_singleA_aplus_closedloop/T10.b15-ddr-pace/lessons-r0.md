# lessons — T10.b15-ddr-pace r0

Only reusable root cause / trigger / fix / verification entry points.

## 0. 本轮最重要的结论（先看这条）

- b15 把 bridge 改成“严格单笔 AR + `rready` 恒 1 + 每拍必入队”后，**用合规单拍模型仿真
  `ar = r = rlast = 210,685`、0 超时 0 丢拍、整帧四 CRC+zlib 通过**；
- **但板上仍是每尝试少 1 个 R**（`timeout 3/帧 retry 2/帧 giveup 1/帧`、`enc=exported=0`、
  `ar−r = ar−rlast = 尝试数`、`stale_r = stale_guard = 0`）。
- 因此“`ar_pending` 首拍清零 + rready 背压”这个 b13 机制**确实存在**、也确实被消除，
  但它**不是**板级丢拍的根因；根因是 **DDR MC/PAXI 侧有一个被接受却永不应答的读请求**
  （或某个地址不可被应答）。后续排查应从 MC/PAXI 响应侧入手，而不是继续改 bridge。

## 1. "One outstanding AR" must be owned until `rlast`, not until the first beat

- **Symptom (board, b14 r0):** every read attempt lost exactly one R
  (`ar_cnt − r_cnt = 13,650` over 13,410 attempts), then stalled 8 192 clk_a1 →
  `timeout = 3`, `retry = 2`, `giveup = 1` per frame, `enc = exported = 0`;
  `stale_r = stale_guard = 0` (the missing beat never arrived at all).
- **What b15 changed and proved:** `ar_pending` was cleared by the *first* R
  handshake and `paxi_rready` was gated by `rf_wready`, so "one outstanding AR"
  was nominal and the RF was protected by R-channel back-pressure. b15 replaces
  that with `ar_busy` (cleared only by `rvalid && rready && rlast`), constant-1
  `paxi_rready`, and an AR issue gate on an empty read-data path. With a
  compliant responder this is loss-free (full frame `ar=r=rlast=210,685`,
  `max_os=1`, `rf_ovf=0`, `max_rf_level=1`).
- **What it did NOT fix (b15 r0 board):** the board still loses exactly one AR
  answer per attempt (`ar − r = ar − rlast = 13,740 = attempts`,
  `stale_r = stale_guard = 0`, `exported = 0`) → `H4_UNRESOLVED`.
  **Do not re-blame the bridge without new evidence.**
- **Verify:** `b15_rready_low == 0`, `b15_rf_ovf == 0`, `b15_max_os == 1`,
  `b15_short_burst == 0` (outside the purge path), and the board triple
  `ar − rlast` (it grows by 1 per failed attempt, which is the diagnostic).
- **Trap:** do not "prove" no-overflow with a simulation that only back-pressures
  a compliant FIFO. `capture_async_fifo` **drops** a beat when `w_ready = 0`
  (`wire push = w_valid && w_ready`), so the TB must count
  `rf_push && !rf_wready` explicitly (here: `b15_rf_ovf`).


## 2. A cross-domain occupancy counter must only ever over-estimate

- `rf_level = pushes (clk_ddr) − pops (clk_a1, Gray, 2FF)` is safe because a
  Gray-coded pop count sampled across the domain gives a real, possibly stale,
  value: the level is never *under*-estimated, so `level == 0` really means
  "empty" and the AR gate can never allow an overflow. A binary multi-bit
  counter sampled across domains (or a toggle-per-pop) can under-count and would
  reopen the bug.

## 3. Where the b15 development time actually goes

- A full 1920×1080 frame through the real chain (real A+ core + real bridge +
  PAXI model + physical 8N1 UART decode) costs ~15-20 min of ModelSim ASE wall
  time, dominated by the UART export (2.6 MB × 10 clk_a1/byte ≈ 26 M cycles).
  Plan full-frame cases as background jobs, or budget a smaller geometry for
  every case whose only purpose is FSM/boundary coverage.
- `run_b12.py::build()` recompiles into a fixed work library; two case processes
  must use distinct `B15_BUILD` names or the library is corrupted.

## 4. Harness pitfalls that cost a round

- A "burst closed without rlast" monitor must remember that the `rlast`
  handshake happens *one cycle before* `ar_busy` falls; checking `rvalid &&
  rlast` in the falling-edge cycle reports every normal burst as short
  (measured: 69 false short bursts).
- A dropped R never produces a "short burst": the store's timeout → `rd_abort`
  → purge force-clear is what closes `ar_busy`, so it lands in the
  `purge_close` bucket, not in `short_burst`.
- Injection knobs must be ordinal (the N-th AR), not absolute cycle numbers:
  absolute cycles silently miss the read phase when the write phase length
  changes with the geometry.
