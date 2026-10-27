# T10.b14-cam-b — board run r0 (BLOCKED at preflight)

Status: **board = blocked** (0 downloads, 0 COM8). This is the dev-plan §7.1
"FTDI absent" branch, not a FAIL of the offline candidate.

## 0. User precondition

The spawning session relayed: **"用户已确认第二颗 IMX415 物理连接在 B 口"**
(B camera physically connected). Recorded in `connection-confirmation.md`.
So the board precondition for a run is satisfied.

## 1. FTDI preflight (COM8 closed) — 2026-10-26T00:16:42+08:00

- Command: `Get-PnpDevice -PresentOnly | Where InstanceId -match 'VID_0403&PID_6042'`
- Result: **FTDI_PRESENT=0** — no `VID_0403&PID_6042` device enumerated.
- Visible serial ports: **COM3, COM4 only** (both Bluetooth); **no COM8**.
- Raw output: `log/ftdi_preflight.txt`.

## 2. Consequence

Per dev-plan §7.1 step 2: FTDI not present → `board=blocked`,
`board_blocked_reason=FTDI_0403:6042_absent`, **0 downloads, 0 COM8, no retry**.
`run_board_b14.ps1` was therefore not executed (it would stop at the same STEP0).

## 3. What is still valid

- The offline candidate (bit `fb9eb3e8…e262`, CWC `2e624fab…4c10`) is built and
  hash-frozen; the B selection, v5 mapping and full-chain behaviour are proven
  in simulation (S1–S5).
- No hardware claim is made for B: whether B actually produces pixels, and
  whether the A+ chain exports a frame on B, remains unmeasured.

## 4. Next entry point (when the board is enumerated again)

1. Confirm `FTDI_PRESENT=1` and `COM8` exists; confirm B is still plugged.
2. Run `r0/board/run_board_b14.ps1 -Secs 150` once: 1 SRAM download first
   (`B14_DL_OK`), then COM8 150 s, then parser + `check_b14_board.py`.
3. Board gate: v5 ≥120 packets/bad_xor=0, `cam0/1/3/4/5` and `cap_frames`
   deltas >0, then `enc/exported` >0 and ≥1 frame with four CRCs + strict zlib.
   If B still has `pix_beats=0`, stop and keep the A/B hardware evidence — no
   second download.
