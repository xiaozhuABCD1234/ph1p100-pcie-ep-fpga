# T10.b14-cam-b r1 -- result

- **Task**: T10.b14-cam-b (parent T10 stays blocked)
- **Run**: 20261020-0209_singleA_aplus_closedloop
- **Round**: r1 (build-engineering repair; **no RTL edit**)
- **Overall**: **FAIL** on the export gate.
  Build = PASS, CAM_SEL/B selection = PASS (really in bit and on board),
  **camera B = LIVE**, A+ store/encode/export = FAIL (camera-independent).
- **Candidate**: bit `90bb06dabd87cdeb9ae95c51e7b7e8d277a9a7db78efc89660a40fcfbd94b22f`,
  CWC `2e624fab566c14414802ae1d183c0ddab285dab9e56367984222611870cb4c10`
  (byte-identical to r0's CWC), BID `48e325139fb048ce97c43248db053875dbc9b9c3519ee53f883e793cb5d07156`
  (identical to r0). `cw/compiled.bit|cwc` == parent bit/cwc.
- **Manifest**: `../CANDIDATE-MANIFEST-b14-cam-b-r1.json`

## 1. Build-engineering repair (task 1)

**The dispatch premise ("the last bit compiled the old A-only version") is not
supported.** `r0/td/a1_board_Runs/syn_1/a1_board.prj` (written by the r0
synthesis run at 00:13:04) already lists exactly one copy of each file, under
`r0/changed-src/`; `r0/td/a1_board.al` agrees and `r0/td/routed_netlist.v`
carries `// localparam CAM_SEL = 1'b1;` with changed-src line comments. The
stale copies in `r0/td/src/` and `r0/td/src/src/` were on disk but never added.
Details: `r1/CAM_SEL-bit-index-finding.md`.

r1 nevertheless rebuilds with a hard guard: after synthesis, `01_build.tcl`
parses `syn_1/<prj>.prj` and aborts unless
- `f9p_camera_display_core.v` occurs exactly **1** time, from `changed-src/`;
- `p2_a1_board_top.v` occurs exactly **1** time, from `changed-src/`;
- no `/src/<either file>` and no `src/src/` path is present.

Observed: `B14_FILELIST_COUNT f9p_camera_display_core.v=1`,
`...p2_a1_board_top.v=1`, `B14_FILELIST_OK`; zero duplicate-module
diagnostics in the build console. Files were not deleted; they are simply not
part of the project (list above in the manifest).

## 2. Build (task 2)

One synthesis + one route + one bitgen + one CWC (2 TD console invocations:
build; bitgen then CWC).

| stage | value |
|---|---|
| Syn | SWNS **+0.218 ns**, STNS 0.000; slice 19,406; ERAM 72; reg 20,566 |
| Routed | SWNS **+0.110 ns**, STNS 0.000; HWNS +0.020, HTNS 0.000; **0 violated endpoints / 26,354**; period check WNS 2.200 ns |
| Resources | slice 25,783 (35.97%), LUT6 20,769, reg 30,094, ERAM 103/300 |
| Bitgen STA | `SETUP=0.110/0.000 HOLD=0.020/0.000 PERIOD=2.200` (fail-closed checks passed) |

WNS +0.110 >= +0.05 -> target met, **no timing caveat**. Bit/CWC produced once
each; CWC has 31 `<phy_eram` mappings and zero incomplete `<logic_eram/>`;
debug bit is byte-identical to the parent bit.

## 3. CAM_SEL verification (task 3)

- Netlist: `// localparam CAM_SEL = 1'b1;` (routed_netlist.v:86).
- Board: `cam_sysstat = 0x00001F1D` in **all 150** status packets. The b13
  baseline on hardware was `0x00000F1D`; `0x1F1D = 0x0F1D | 0x1000`.
- The RTL packing is `{19'd0, CAM_SEL, lane_sticky[3:0], 3'd0, cfg_rst_n,
  pll_locked, xclr_n, bus_err_lat, cfg_done}`, i.e. **CAM_SEL = bit 12**, not
  bit 20. r0's comment/manifest and its S3 testbench ("bit20") were wrong; the
  TB hardcoded `camsnap[13]=32'h2232_000E`, so simulation could not catch it.
  r1 fixes only the host parser/checker (bit12 + `(sysstat & 0x1D)==0x1D`);
  RTL/SDC are untouched.

## 4. Board (task 4)

One SRAM download (`B14_R1_DL_OK`, 32.6 s, `PRG-2014` OK), then one 150 s COM8
capture (36,150 B, sha256 `f18fb058...3bb1fd7`). Record:
`r1/board/board-run-r1.md`, gate `r1/board/captures/board_gate.txt`.

- **B front end: LIVE.** clk_tgl 506,435; pkt_tgl 9,972,570; vs_tgl 4,470;
  **pix_beats 875,164,816; line_rises 9,798,239; frame_rises/falls 4,470/4,470;
  roi_frames 4,470; crop_groups 2,358,720,000; crop_geom_err 0** (~29.8 fps,
  1920x1080 ROI exact).
- **A+ chain: FAIL.** cap 4,470, raw_pub 4,470, **enc 0, exported 0**, 0 A1U1
  frames, timeout 13,410 / retry 8,940 / giveup 4,470, cmp_drop 13,650.
- Gate: FAIL only on `delta_enc_gt_0`, `delta_exported_gt_0`,
  `frame_with_four_crcs_zlib`; every B-count and CAM_SEL check passed.
- The identical failure is present with **camera A** in `T10.b15-ddr-pace/r0`
  (sysstat 0x0F1D, cap 4,500, enc 0, exported 0, giveup 4,500), so this is the
  open b13/b15 DDR store/encode/retry defect, not a B-select defect.
- No second download / no Flash / no re-capture.

## 5. Budget used

- Dev: ~50 min / ~30 tool calls (this round). TD console invocations 2;
  synth 1; route 1; bitgen 1; CWC 1; SRAM downloads 1; COM8 captures 1; Flash 0.
- No batch delete.

## 6. Open items / next entry

1. Fix the frame give-up in `a1_ddr_slot_store` / `a1_ddr_arb2` (b13/b15 work);
   then reuse this exact 150 s gate. B needs no further proving at CSI level.
2. B `lane_sticky=0x1` (A was 0xF) while frames are complete -- worth one look
   if a lane-1-only failure ever appears.
3. r1 bit hash differs from r0 while the CWC is identical; both builds are
   STA-identical (+0.110 / 0.020). Use r1's hashes going forward.
