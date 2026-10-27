# T10.b14-cam-b r0 — result

- **Task**: T10.b14-cam-b (parent T10 stays blocked)
- **Run**: 20261020-0209_singleA_aplus_closedloop
- **Overall status**: **blocked** — offline RTL/sim/build complete; board blocked
  at FTDI preflight (`FTDI_0403:6042_absent`, 0 downloads, 0 COM8).
- **Candidate**: bit `fb9eb3e8d7b8a67e615f2ba8b9bb81d0208f0c7c3d3b213f3c89b2058735e262`,
  CWC `2e624fab566c14414802ae1d183c0ddab285dab9e56367984222611870cb4c10`,
  BID `48e325139fb048ce97c43248db053875dbc9b9c3519ee53f883e793cb5d07156`;
  `cw/compiled.bit` / `cw/compiled.cwc` are **byte-identical to the parents**.

## 1. What changed (minimum B-select patch)

| File | Change |
|---|---|
| `f9p_camera_display_core.v` | B tap (6 outputs) + B diagnostics (19 outputs) are pure `assign`s to existing `w_b_*`/`r_b_*`; six previously-open `u_csi_b` frame/CRC outputs now wired; `CAM_B_IDELAY_TAP = 6'd46` for `u_csi_b`. A ports/instances/logic untouched. |
| `p2_a1_board_top.v` | `localparam CAM_SEL = 1'b1` + `generate` direct connection for `clk_cam`/tap/`i_dbg_*`; `cam_sysstat[20] = CAM_SEL`; A core still instantiated; one stale comment fixed. |
| `p2_board.sdc` | + `create_generated_clock mipi_b_byte_clk` (source `mipi_b_clk_hs_p`, ÷4, `u_csi_b/u_rx_phy/u_hs_clk_div.clkdivout`); added to the existing `mipi_b_clk_hs` async group. Nothing else. |
| `01_build.tcl` / `a1_board.al` | 11 changed-src paths only (TD rewrites the live `.al`; the hand-edited input is kept as `r0/diag/a1_board.al.pre_build`). |

`CAM_SEL=0` maps every A+ input back to the exact b13 A nets
(`r0/diag/cam-sel-equivalence.md`). P1 frame/44 B header/CRC/zlib/DDR/UART/pins/
clock frequencies are untouched.

## 2. Directed simulation (all on the frozen `r0/changed-src`)

| ID | Result | Evidence |
|---|---|---|
| **S1 B geometry full chain** | **PASS** | 3864×2192 RAW10, ROI 972/556 → 1920×1080: `source/pix_beats=2,117,472`, `line_rises=2,192`, `frame_rises=1`, `frame_falls=1`, `crop_roi_frames=1`, `crop_groups=518,400`, `raw_len=2,592,000`, `enc=1`, `exported=1`, `exp_bytes=2,594,706`; 44 B header + **four CRCs** + strict zlib + independent RAW/xform reference; `raw_drop=0`, `cmp_drop=0`, `dup=0`, no half frame. 37.46 M clk_a1, 1068 s. |
| **S2 P1 three goldens** | **PASS** | compressed bytes byte-identical to the b13 baseline: micro8x2 `fa513a2b…`, mid64x8 `ee61e620…`, full_grad `b992a8ad…` (all == b13 r0 `sim/caps/*.dec`), `vlog 0/0`. |
| **S3 v5 structure + bit20** | **PASS** | 241 B / 59 fields / VER 5 / XOR ok for 3 packets; field #13 = `0x2232000E` (b13 value `0x2222000E` + bit20 only) → cam_sel=1; S1's captured packets also carry `sysstat=0x00100000`, `#3/#4/#5/#6/#8 = 2,117,472 / 2,192 / 1 / 1 / 1`. Exporter's "status inside a frame" assertion did not fire. |
| **S4 dead B byte clock** | **PASS** | `clk_cam` stopped after POR: 7 valid v5 packets, `bad_xor=0`, cam fields 0, `cap=enc=exp=raw_pub=0`, no A1 start, no hang/watchdog, no half frame. |
| **S5 B short line / geom error** | **PASS** | 96×12 proxy: frame 1 short line → `crop_geom_err=1`, `crop_short=0`, partial RAW dropped (`raw_drop=1`, `crop_sofs=2`, `crop_lasts=1`), never published/exported; frame 2 exported with four CRCs + reference. |

## 3. Build (TD 6.2.3, 2 sessions: build + bitgen/CWC)

- Synthesis (1 run): `SWNS +0.218 / STNS 0.000`, slice 19,406, ERAM 72, reg 20,566.
- Routed (1 run): **`SWNS +0.110 ns`** (target ≥ +0.05 → met), `STNS 0.000`,
  `HWNS +0.020`, `HTNS 0.000`, **0 violated endpoints / 26,354**, period check
  positive, slice 25,783, LUT6 20,769, reg 30,094, **ERAM 103 / 300**.
- **1 bitgen + 1 CWC**; `P2_BITGEN_STA_SETUP=0.110/0.000 HOLD=0.020/0.000 PERIOD=2.200`;
  parent bit/CWC == `cw/compiled.*`. No false path / multicycle / seed change /
  downclock / new ERAM instance. SDC diff is exactly the 2 B-clock lines.
- Timing caveat: none (`+0.110 ≥ +0.05`, 0 violations).

## 4. Board

- User confirmed the second IMX415 is physically connected to port B.
- FTDI preflight: **`VID_0403&PID_6042` absent**, only COM3/COM4 (Bluetooth);
  no COM8. → **board=blocked**, `board_blocked_reason=FTDI_0403:6042_absent`,
  **0 SRAM downloads, 0 COM8** (dev-plan §7.1 step 2). No retry, no Flash.
- Therefore there is **no hardware B pixel/export claim** in this round; see
  `r0/board/board-run-r0.md` for the single-shot re-entry procedure.

## 5. Budget used

- Dev: ~65 min / ~55 tool calls; TD sessions 2; synth 1; route 1; bitgen 1;
  CWC 1; downloads 0; Flash 0. No batch delete.

## 6. Open risks / limits

1. B eye has not been swept; both cameras use IDELAY tap 46. If B shows packets
   without pixels on hardware, tap is the first suspect (new package).
2. MIPI differential path passes the baseboard FEP1B C-row / 100 R series —
   hardware condition, recorded not fixed.
3. S1 uses the synthetic tap through the real `camera_a1_uart_top`; the camera
   core/PHY itself is not simulated (validated by TD elaboration only).
4. With `CAM_SEL=1` the A counters are not visible in v5 (A core keeps running);
   documented observation boundary, not an A-path change.
5. Board evidence is missing, so the B hardware question remains open.
