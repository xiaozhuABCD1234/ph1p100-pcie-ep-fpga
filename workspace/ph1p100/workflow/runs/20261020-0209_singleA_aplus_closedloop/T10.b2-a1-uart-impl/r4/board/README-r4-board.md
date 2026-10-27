# r4 board runbook (SRAM only, no Flash)

Candidate: `r4/td/a1_board.bit` (hashes in `../CANDIDATE-MANIFEST-b2-a1-uart-impl-r4.json`).

Preconditions verified by the dev role on 2026-10-24:

* `hwserver.exe` already running: `hwserver -r -s 5555 -f 12 -v -w 5556 -i 0`
  (PID 77088, started 17:05, `D:\anlogic\TD_Release_2026.2\bin\hwserver.exe`).
  The scripts below never start or stop it.
* Cable 0 = on-board FTDI, JTAG on channel A, UART on channel B = **COM8**.
* TD drive letters: run `tools/td/td_env.ps1 -TdDir <r4>\td` first; `T:` must point at
  `r4/td` and `Y:` at `D:\fpga\ph1p100` (the saved `a1_board.al` stores `Path="T:/"`).
  WARNING: during r4 another session/agent remapped `T:` to
  `T10.a1-eng-freeze/r10/td` at ~17:42; always re-check `subst` before a TD
  command, otherwise the project opens against the wrong directory.

## 1. one SRAM download

```
cd <r4>\board
td_commands_prompt.exe ./download_sram_r4.tcl        REM -mode jtag = SRAM, never program_spi
```

Expected prints: `R4_DL_DEVICE=...` and `R4_DL_OK mode=jtag(sram) ...`.

## 2. 120 s UART capture (115200 8N1, read only)

```
python capture_com8.py --port COM8 --baud 115200 --secs 120 --outdir <r4>\captures
```

Writes `captures/com8_120s.bin`, `.dec` (one decimal byte per line) and `.stats`.

## 3. decode

```
python resync_decode.py <r4>\captures\com8_120s.bin <r4>\decode
```

`resync_decode.py` skips the idle beacon (`0x55`, ~44.7 Hz, only emitted while no
frame is open) and hands contiguous frames to the frozen
`tools/a1/pc_decode.py`, so header/stream/xform/raw CRCs and the zlib and RAW10
reconstruction are checked exactly as before. `all_checks_ok=true` plus
`gap_all_beacon_0x55=true` is the expected result when frames are present.

Interpretation matrix:

| capture content | meaning |
|---|---|
| `0x55` beacons + full frames, `all_checks_ok=true` | FIFO bypass fixed the export path |
| `0x55` beacons only, no `A1U1` magic | transmitter/pin/clock alive; descriptor/read path is the blocker |
| nothing at all | transmitter/pin/clock or `clk_a1` is the blocker (not the FIFO) |
