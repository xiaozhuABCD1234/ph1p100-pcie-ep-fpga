# T10.b14-cam-b r1 -- board run (2026-10-26 17:44-17:48)

## 0. Preflight

- FTDI `VID_0403&PID_6042` present (3 nodes OK), `\Device\VCP0 -> COM8` present.
- COM8 closed during the download; hwserver killed before download.

## 1. Download -- exactly one SRAM (JTAG, volatile) program

- Script: `r1/board/dl_b14_r1.tcl` (copied into `r1/td/`, run with cwd = T:).
- Log: `r1/board/log/download_r1.log`
  - `B14_R1_DL_DEVICE=PH1P100`
  - `PRG-2014 : Chip validation success: PH1P100`
  - `B14_R1_DL_OK mode=jtag(sram) bit=.../r1/td/a1_board.bit` (32.6 s)
- No Flash/eflash write. hwserver stopped again before opening COM8.

## 2. COM8 capture -- 150 s, 115200 8N1, read only

- Script: `r1/board/capture_com8.py`
- Raw: `r1/board/captures/com8_150s.bin` (36,150 B,
  sha256 `f18fb058d90d4f6264566d5afccc0d5a9516f9013958f168d68a8783d3bb1fd7`)
- `com8_150s.stats`: `wall_elapsed=150.165`, `magic_a1u1=0`, `byte_0x55=19`.

## 3. Parse + gate

- Parser: `r1/board/parse_status_v5.py` (v5 = 241 B, 59 fields, XOR) --
  **fixed in r1**: CAM_SEL is read at bit 12, not bit 20.
- Gate: `r1/board/check_b14_board.py` -> `captures/board_gate.txt`.

| check | value |
|---|---|
| status packets | **150**, `bad_xor=0` |
| CAM_SEL (bit12) | **1 in every packet**, `sysstat=0x00001F1D` (min=max) |
| clk_tgl delta | 506,435 |
| pkt_tgl delta | 9,972,570 |
| vs_tgl delta | 4,470 |
| **pix_beats delta** | **875,164,816** |
| **line_rises delta** | **9,798,239** |
| **frame_rises / falls** | **4,470 / 4,470** |
| roi_frames delta | **4,470** |
| crop_groups delta | 2,358,720,000 (518,400/frame, 1920x1080 ROI) |
| crop_geom_err / crop_short | 0 / 0 |
| cap_frames / raw_pub | 4,470 / 4,470 |
| **enc_frames / exported** | **0 / 0** |
| A1U1 frames with 4 CRCs + strict zlib | **0** |
| timeout / retry / giveup | 13,410 / 8,940 / 4,470 |
| cmp_drop | 13,650 |
| A1 ar / r delta | 16,485,957 / 16,468,547 |

Gate result: **FAIL** only on `delta_enc_gt_0: 0`, `delta_exported_gt_0: 0`,
`frame_with_four_crcs_zlib: []`. All B front-end and CAM_SEL checks passed.

## 4. Reading

- Camera B is physically live and the B tap is the one feeding the A+ chain:
  MIPI clock/packet toggles, 4,470 complete 1080p30 frames in 150 s
  (29.8 fps), ROI 1920x1080 groups exact, zero geometry errors.
- The failure is downstream: every published RAW frame is followed by
  3 timeouts / 2 retries / 1 give-up, so the compressed frame never appears
  (`enc=0`), nothing is exported, and no A1U1 frame is produced.
- Exactly the same signature occurs with camera A in
  `T10.b15-ddr-pace/r0` (cap 4,500, enc 0, exported 0, giveup 4,500). It is
  not a B-select regression; it is the open b13/b15 store/encode/retry bug.
- No second download, no Flash, no re-capture. Evidence kept as-is.
