# lessons-r0 — T10.ah-honly

Reusable root causes / triggers / fixes / verification entries only.

## 1. Synchronous cmem read: push only after the wait state

- Symptom: comp bench output bytes 2–3 were `X`; comp SHA
  `80dcdd95…` instead of `2601d57c…`; `cmem_rdata` read `X` although the
  memory word was valid.
- Root cause: the replay FSM pushed the bytes in `S_REPLAY_RD`, the same state
  that had just registered `cmem_raddr`; the synchronous read data lands one
  cycle later. The frozen design had `S_REPLAY_RD` as a pure wait state.
- Fix: keep `S_REPLAY_RD` as a wait state, push bytes 0–1 in `S_REPLAY_E` and
  bytes 2–3 in a new `S_REPLAY_E2`. Replay ceiling becomes 4 B / 3 cycles
  (0.75 cycles/B) instead of an unreachable 4 B / 2 cycles.
- Verification: frozen comp/rand SHAs on both TBs, cycles 304,961 / 161,479.

## 2. frame_top pending byte: count and CRC exactly once

- Symptom: the first H N probe header said `stream_len=1,837,973` (instead of
  1,677,912), wrong `stream_crc/header_crc`, and `exported=0` at MAX_CYCLES
  (the UART waited for bytes that did not exist). Difference = 160,061, the
  number of 2-byte core transfers that landed at `scnt=3`.
- Root cause: a 2-byte transfer at `scnt==3` wrote the low byte into the word,
  counted `slen += 2` and CRCed both bytes, then held the high byte. The held
  byte was counted and CRCed **again** when written at `scnt=0`. The data bytes
  were correct; only the length/CRC accounting (and therefore the UART length
  gate) was wrong.
- Fix: at `scnt==3` count/CRC only the low byte, publish the completed word and
  hold the high byte; the pending path counts/CRCs it once. At `scnt<3` keep the
  `+2` count and the chained CRC.
- Verification: repaired N probe frame-1 `stream_len 1,677,912`,
  `stream_crc 1,168,876,019`, `header_crc 657,705,490`, exp completed at
  11,161,098 cycles.
- General rule: whenever a transfer is split across a word boundary, keep the
  *byte accounting* at the point where the byte is committed to the output
  word, not where it is accepted.

## 3. 1-frame probe harness behaviour

- The frozen probe TB still executes the inherited `st_read < 2*129600` wait,
  so with `FRAMES=1` it always runs to `MAX_CYCLES` and `$finish` fires before
  the final `SS_STATS` print. The stats file is empty; this is not a new
  failure. The accepted evidence is `CORE_STAGE` + `SS_EVT` + the
  `B11_FULL_TIMEOUT … exported=1 read=129600` line (same shape as the P2
  reference probe).
- Keep `CORE_STAGE` reading only registered core counters; it must be dumped
  after the last `stat_*` increment (8 cycles after `st_enc` is enough).

## 4. Budget planning for a full-frame probe

- A broken full-chain probe is expensive: N probe ≈ 11 min, L 4-frame ≈ 33 min.
  A cheap directed differential test of the core→frame_top adapter (small
  W/H, real RTL on both sides) would have caught the pending-byte accounting
  before spending a full/probe slot. It was not in the frozen run list; note it
  for the next task.
- Two vsim runs on this 16-core/32-thread host are fine (the repaired N probe
  still finished in 679 s; the L 4-frame ran concurrently in 1,962 s).

## 5. Metrics that are not gates

- `stat_stall` is input-pacing dependent and differs from the baseline
  (1,509,741 vs 2,784,218 on N); it is diagnostic only.
- The `replay_stall` tap counts only `S_REPLAY_R && !out_space`. With a 2-byte
  output and a 16-entry FIFO, the replay backpressure actually appears as
  `core_ready_low` / `core_stall` (578,089 / 335,034) and `fifo_max=15`; report
  those, do not read `replay_stall=0` as "no backpressure".
- `ss_pass=0` on natural content is the known `dup=0` clause, not a
  performance gate.

## 6. Baseline control must stay exact

- Re-running the frozen b11 4-frame with only a passive UART monitor reproduced
  the P1 S_ss and frame-1 core_interval exactly (N 7,475,240 / 7,476,245;
  L 6,986,952 / 6,979,811). The monitor must live entirely in the `clk_uart`
  domain and never gate the DUT.
