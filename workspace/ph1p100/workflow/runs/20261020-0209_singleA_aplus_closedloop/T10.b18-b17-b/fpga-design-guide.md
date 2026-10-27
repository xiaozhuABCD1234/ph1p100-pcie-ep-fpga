# T10.b18-b17-b -- task design guide (frozen)

Scope: one merged candidate = b17 native-PAXI/v6 base + b14 B-tap/CAM_SEL=1 overlay.
All values below are frozen for this task; any deviation needs a planner waiver.

## 1. Data formats (unchanged)

| item | value |
|---|---|
| raw frame | 2,592,000 B = 1080 lines x 2400 B (1920 px, 40-bit beat = 4 px RAW10) |
| chain geometry | pix_beats 2,117,472 / line 2,192 / frame 1 per synthetic full frame |
| ROI | 972/556 -> 1920x1080, crop_groups 518,400 per frame |
| compressed | A+ v1 zlib stream, BFINAL on last block, stored fallback, Adler-32 |
| frame record | four CRCs (raw / xform / stream / record) + zlib decodable, no half frame |
| status packet | **v6: 273 B = 4 hdr + 67 x u32 LE + XOR8**, header `A5 5A 11 06`, XOR over bytes 0..271 |
| v6 field #13 | `cam_sysstat` = `{19'd0, CAM_SEL, sel_lane_sticky[3:0], 3'd0, cfg_rst_n, pll_locked, xclr_n, bus_err_lat, cfg_done}` -> **CAM_SEL = bit 12** (must read 1) |
| v6 fields #3..#8 | selected-camera counters (pix_beats/line_rises/frame_rises/frame_falls/last_frame_cycles/crop_roi_frames) |
| v6 fields #60..#67 | native AR addr/last3, timeout AR addr/last3, same_aw/w_ar_cnt, inflight_state, diag_flags |
| parser | accepts v5 (241/59/VER=5) and v6 (273/67/VER=6); board gate must use v6 |

Do not add fields, renumber, change XOR coverage, or change the frame/zlib path.

## 2. Interfaces

| interface | contract |
|---|---|
| camera select | `localparam CAM_SEL = 1'b1` in `p2_a1_board_top`; compile-time `generate`, never a LUT/clock mux |
| B tap | `f9p_camera_display_core` exposes `o_b_pixel[39:0]`, `o_b_pixel_valid/in_line/in_frame/vsync/byte_clk`, 18 `o_dbg_b_*`; all are plain assigns to existing internal B state |
| B delay tap | `CAM_B_IDELAY_TAP = 6'd46` (same as `CAM_IDELAY_TAP = 6'd46`; B eye not yet swept) |
| selected tap | `sel_pixel* / sel_byte_clk / sel_dbg_* / sel_nack_cnt` feed `u_a1` (`clk_cam`, `i_a_pixel*`, `i_dbg_*`) |
| A/B pins | `board_p2.adc` b13 assignment unchanged (MIPI-B J19/H19 J22/H22 G17/G18 J20/J21 L19/L20; B I2C H13/G13, MCLK G20, XCLR H20) |
| PAXI | native address x8 at the bridge boundary, `wstrb=0`, `ALLOW_CONCURRENT=0`, one AR until `rvalid&&rready&&rlast` |
| debug bus | bridge `dbg_a1` 512 bit (b17 block), `camera_a1_uart_top.i_dbg_bridge[511:0]`, `sts_ext_bus[767:0]` |
| UART | 115,200 8N1, `UART_DIV=1628`, `HB_DIV=4194304` (unchanged) |

## 3. Clocks and timing

| clock | source | constraint |
|---|---|---|
| `clk_a1` | 187.5 MHz PLL | existing `p2_board.sdc` |
| `clk_ddr` | DDR MC | existing |
| A byte clock | `mipi_a_clk_hs_p` | existing `mipi_a_clk_hs` async group |
| **B byte clock** | `mipi_b_clk_hs_p` -> `u_camera/u_csi_b/u_rx_phy/u_hs_clk_div.clkdivout` | **b14 r1 `p2_board.sdc` byte-for-byte**: `create_generated_clock -name {mipi_b_byte_clk} -source [get_ports {mipi_b_clk_hs_p}] -divide_by 4`, group `{mipi_b_clk_hs mipi_b_byte_clk}` |
| sys | 50 MHz | existing |

With `CAM_SEL=1`, `clk_cam` is driven by the B byte clock; the generated clock above is
therefore mandatory and must not be relaxed. No false path, multicycle, clock merge or
frequency reduction. `a1_small_top.sdc` stays untouched (small-top tests only).

## 4. Buffering / flow control (unchanged)

- 4 DDR slots; raw store reads one slot at a time; A1 guard 70,000 `clk_a1`,
  bridge guard 65,536, timeout 8192 `clk_a1`, retry <= 2, then `giveup` (no half frame).
- b17 keeps `ar_busy` until `rlast`, `paxi_rready` tied 1, `MAX_OS=1`, orphan R counted stale.
- A+ core abort/restart on retry; no `a1_commit` on abort.

## 5. Build entry

| item | value |
|---|---|
| TD | `D:\anlogic\TD_Release_2026.2`, `tools/td/td_env.ps1` first |
| project | copy `../T10.b17-paxi-native/r0/td/{01_build.tcl,02_bitgen.tcl,03_cwc.tcl}` into `r0/td/`, rewrite every source path to `Y:/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b18-b17-b/r0/changed-src/` |
| filelist guard | after synthesis parse `syn_1/*.prj`: `f9p_camera_display_core.v` exactly 1 from `r0/changed-src`, `p2_a1_board_top.v` exactly 1 from `r0/changed-src`, no `./src/<either>`, no `src/src/` ; else abort |
| .al / SDC / ADC | `a1_board.al` 59 sources same set; `p2_board.sdc` = b14 r1 file; `board_p2.adc` = b17 r1 file |
| device | PH1P100SBG484 speed 3, Routed |
| path maps | TD `T: = r0/td`, `Y: = D:\fpga\ph1p100`; sim `P: = project root`, `W: = r0/sim`; never `X:` |

## 6. Board entry

`r0/board/run_board_b18.ps1`: FTDI preflight -> SRAM download FIRST -> close JTAG -> open COM8 150 s ->
`parse_status_v6.py` -> `check_b18_board.py` (v6 + bit12 + export gate). One download, no Flash,
no second capture. If `giveup` still grows: keep `timeout_ar_addr` / `diag_flags` from v6 and stop.

## 7. Non-goals

No A-camera rework, no CSI PHY re-tune, no SDC relaxation, no seed sweep, no frequency/voltage change,
no new status field, no PCIe/RK/Flash/G4, no dual concurrent export, no batch delete.
