# r0 (T10.b5-a1-htab-pipe) board runbook -- SRAM only, no Flash

Candidate: `r0/td/a1_board.bit` (hashes in `../CANDIDATE-MANIFEST-b5-a1-htab-pipe-r0.json`).
Authorisation: `dispatch-r5.json` -- **exactly one** SRAM download for this candidate.

Preconditions:

* `hwserver.exe` running: `hwserver -r -s 5555 -f 12 -v -w 5556 -i 0`
  (PID 77088 since 2026-10-24 17:05, `D:\anlogic\TD_Release_2026.2\bin\hwserver.exe`).
  The scripts below never start or stop it.
* Cable 0 = on-board FTDI, JTAG on channel A, UART on channel B = **COM8** 115200 8N1.
* `T:` = `r0/td`, `Y:` = `D:\fpga\ph1p100` (`tools/td/td_env.ps1`); re-check `subst`
  before every TD command (another session once remapped `T:`).

## 1. the one SRAM download

```
cd <r0>\board
td_commands_prompt.exe ./download_sram_r0.tcl      REM -mode jtag = SRAM, never program_spi
```

Expected prints: `R5_DL_DEVICE=...` and `R5_DL_OK mode=jtag(sram) ...`.

## 2. 120 s UART capture (115200 8N1, read only)

```
python capture_com8.py --port COM8 --baud 115200 --secs 120 --outdir <r0>\captures
```

Writes `captures/com8_120s.bin`, `.dec` and `.stats`.

## 3. decode

```
python resync_decode.py <r0>\captures\com8_120s.bin <r0>\decode
```

`resync_decode.py` is byte-identical to the r4 file
(`76678f4e...e30b2`): it skips the idle beacon (`0x55`, ~44.7 Hz, only emitted
while no frame is open) and hands contiguous frames to the frozen
`tools/a1/pc_decode.py`, so header/stream/xform/raw CRCs and the zlib/RAW10
reconstruction are checked exactly as before.

Pass = `frames_found >= 1`, every frame's four CRCs true, `decoded_trailing=0`,
`all_checks_ok=true`.

Interpretation matrix:

| capture content | meaning |
|---|---|
| `0x55` beacons + full frames, `all_checks_ok=true` | UART bypass + core both work on silicon |
| `0x55` beacons only, no `A1U1` magic | TX/pin/clock alive; descriptor/read path is the blocker |
| nothing at all | TX/pin/clock or `clk_a1` is the blocker |

Failure = stop. No second download, no Flash, no re-try with a new bit.
