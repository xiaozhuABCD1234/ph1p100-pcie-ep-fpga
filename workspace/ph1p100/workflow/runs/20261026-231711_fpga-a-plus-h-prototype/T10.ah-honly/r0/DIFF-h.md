# DIFF-h — T10.ah-honly H implementation (round0)

Scope: isolated copies in `T10.ah-honly/r0/changed-src/` only. The frozen `src/`
copies are never edited. No change to geometry, clock, reset, block format,
stored/fixed decision, candidate costing, A1U1 header layout or external
32-bit/UART packing. Machine diff: `out/DIFF-h.raw` (core) and
`out/DIFF-frame-top.raw` (frame top).

## 1. `a1_deflate_core.v`

| area | frozen | H |
|---|---|---|
| output port | `out_data[7:0]`, no keep | `#(parameter integer OUT_BYTES = 1)`, `out_data[8*OUT_BYTES-1:0]`, new `out_keep`; default 1 keeps the frozen b6 bench binding |
| candidate store | `cmem[0:4095]` x 16 b | `cmem[0:2047]` x 32 b (same 65,536 bits); packer still emits 16-bit words and a write-combine stage pairs even/odd halves; a pending low half is flushed in `S_DECIDE` |
| replay read | one 16-bit word per access, one wait state | one 32-bit word (4 stream bytes) per access, one wait state |
| replay emit | one byte per `S_REPLAY_E` | new `S_REPLAY_E2`: `S_REPLAY_R` issues the read, `S_REPLAY_RD` waits, `S_REPLAY_E` pushes bytes 0–1, `S_REPLAY_E2` pushes bytes 2–3 (4 B / 3 cycles = 0.75 cycles/B replay ceiling); last partial byte keeps its exact bit count |
| output FIFO | 16 x {last, byte} | 16 x {last, keep, byte1, byte0}; in `OUT_BYTES=1` a 2-byte entry is presented low byte first and the high byte is written back for the next transfer, so the frozen 8-bit consumer still sees one byte per transfer |
| skid FIFO | 4 x {last, nbits[3:0], byte} | 4 x {last, nbits1, nbits0, byte1, byte0} (1–2 bytes per entry) |
| accumulator | 16 b `oacc`, 1 byte/cycle | 24 b `oacc`, up to 2 whole bytes per cycle; `obits` keeps the <8-bit remainder |
| everything else | — | match selection, hash table, costing, abort, stored fallback, block headers, Adler, `S_TRAIL/S_DRAIN`, all `stat_*` meanings unchanged |

`out_keep` is constant 0 in 8-bit mode. A `keep=1` transfer means both bytes are
accepted in that cycle (no partial acceptance). `out_last` is asserted only on
a 1-byte transfer in this implementation (the final Adler byte); the adapter
still handles the generic `keep=1 + last` case via a held pending byte.

## 2. `a1_frame_top.v`

- core instance becomes `a1_deflate_core #(.OUT_BYTES(2))`; core data is 16 b
  and `out_keep` is connected.
- `core_out_ready = !svalid && !pend_valid`.
- output packing accepts 1- or 2-byte transfers. A 2-byte transfer at
  `scnt==3` writes the low byte to `sdata[31:24]`, publishes the word with
  `skeep=4'hF`, and holds the high byte in `pend_byte`; the pending byte is
  written to `sdata[7:0]` (`scnt<=1`) before any new transfer is accepted, or
  published as a 1-byte last word if `pend_last`.
- `str_crc_r` is updated per byte in stream order (two chained `crc32b` calls
  for a 2-byte transfer); `slen_r` counts bytes. External ports, `sdata`,
  `skeep`, `slast`, `frame_commit/frame_abort`, `st_*` and the 32-bit word
  order are unchanged.
- `pend_valid` is cleared on reset and on frame abort; a new frame is only
  started when `!svalid && !pend_valid`.

## 3. Test benches (changed-src only)

- `tb_ss_4run_wd.v` / `tb_ss_4run_wd_probe.v`: passive per-frame A1U1 monitor
  in the `clk_uart` domain (`+FRM=` file): detects the `41 31 55 31` magic,
  stores the 44 header bytes, parses `stream_len/raw_crc/xform_crc/stream_crc/
  header_crc`, counts the declared payload, records the last payload byte and
  writes one `FRAME ... header=<88 hex>` line per frame. No DUT, clock, reset,
  pacing or sink change. The probe TB additionally counts replay cycles,
  replay stalls, max output FIFO occupancy, `out_valid` duty, `core_out_ready`
  low cycles, core stalls, `svalid` waits and 2-byte transfers (read-only taps,
  printed in `CORE_STAGE`).
- `tb_a1_deflate_core_8b.v` is the frozen 8-bit bench (identical).
- `tb_a1_deflate_core_16b.v` instantiates `OUT_BYTES=2`, writes both bytes of
  a `keep=1` transfer to the OUT hex in stream order, and counts bytes 2/1.

## 4. Not changed / not claimed

- No change to `a1_uart_export.v`, `camera_a1_uart_top.v`, DDR/bridge, crop,
  `p2_*`, `capture_async_fifo.v`, `cam_diag_mailbox.v`.
- No A work (2-position literal scan) in this package.
- No TD/synthesis/timing/resource measurement. Resource numbers in
  `out/resource-estimate.json` are estimates from array/port widths.
