# r1-diag (T10.b5-a1-htab-pipe) board runbook -- SRAM only, no Flash

Candidate: `r1-diag/td/a1_board.bit` (hashes in `../CANDIDATE-MANIFEST-b5-a1-htab-pipe-r1diag.json`).
Authorisation: this diagnostic package -- **exactly one** SRAM download for this candidate.

## What this candidate changes

`a1_uart_export.v` + `camera_a1_uart_top.v` only (package-local copies in
`../changed-src/`).  The idle `0x55` heartbeat is replaced by a 35-byte status
packet, emitted about once per second while the exporter is idle:

```
A5 5A | cap_frames u32 | raw_pub u32 | enc_frames u32 | exported u32 |
        raw_drop u32 | cmp_drop u32 | errors u32 | read_words u32 | XOR
```

All integers are little-endian; XOR covers bytes 0..33.  The A1U1 frame
format, CRCs, DDR layout, clocks and pinout are unchanged, and no packet is
ever inserted inside a frame.

## Preconditions

* `hwserver.exe` running: `hwserver -r -s 5555 -f 12 -v -w 5556 -i 0`
  (`D:\anlogic\TD_Release_2026.2\bin\hwserver.exe`).
* Cable 0 = on-board FTDI, JTAG channel A, UART channel B = **COM8** 115200 8N1.
* `T:` = `r1-diag/td`, `Y:` = `D:\fpga\ph1p100` (`tools/td/td_env.ps1`).

## 1. the one SRAM download

```
cd <r1-diag>\board
td_commands_prompt.exe ./download_sram_r1diag.tcl      REM -mode jtag = SRAM
```

Expected: `R1D_DL_DEVICE=PH1P100` and `R1D_DL_OK mode=jtag(sram) ...`.

## 2. 60 s UART capture (115200 8N1, read only)

```
python capture_com8.py --port COM8 --baud 115200 --secs 60 --outdir <r1-diag>\captures
```

## 3. decode the status packets

```
python parse_status.py --in <r1-diag>\captures\com8_60s.bin --out <r1-diag>\captures\status.txt
```

Prints every packet and the first/last values of the eight counters.

## Interpretation matrix (this diagnostic)

| observation | meaning |
|---|---|
| no bytes at all | TX/pin/clock or `clk_a1` dead |
| packets only, `cap_frames=0` | camera tap / crop / CDC into A1 is the blocker |
| `cap_frames>0`, `raw_pub=0` | raw DDR store never publishes (write/abort) |
| `raw_pub>0`, `enc_frames=0` | feeder or A+ core never commits |
| `enc_frames>0`, `exported=0` | compressed store read / exporter open is the blocker |
| `exported>0` but no A1U1 frame on the wire | exporter/descriptor/TX mismatch (re-check) |
| `raw_drop`/`cmp_drop`/`errors` growing | slot overrun / descriptor overflow / CRC-length mismatch |

Failure = stop. No second download, no Flash, no retry with a new bit.
