# T10.b18-b17-b -- input index (frozen 2026-10-26)

Task: merge the two independently proven branches into one candidate:
**b17 native-PAXI + v6 (base)** x **b14 camera-B tap / CAM_SEL=1**.
Parent `T10` stays blocked. New independent task, new developer, new integrated tester.

## 1. Baseline: b17 (PAXI fix, v6, R1 retry)

| item | path | note |
|---|---|---|
| result r0 | `../T10.b17-paxi-native/result-r0.md` | offline all-PASS |
| result r1 | `../T10.b17-paxi-native/r1/result-r1.md` | 1 bitgen+1 CWC, Routed +0.002, board blocked (FTDI absent) |
| manifest r0 | `../T10.b17-paxi-native/CANDIDATE-MANIFEST-b17-paxi-native-r0.json` | 11 changed-src hashes |
| changed-src | `../T10.b17-paxi-native/r0/changed-src/` | 11 files |
| sim | `../T10.b17-paxi-native/r0/sim/` | tb_b17_chain, tb_b17_paxi_native, tb_p1_chain, tb_status_v6, run_b17.py, check_b17*.py |
| sim results | `../T10.b17-paxi-native/r0/sim/sim-results-b17-*.json` | chain s1/s2/s3, native, p1, status |
| v6 fields | `../T10.b17-paxi-native/r0/diag/v6-fields.md` | 273 B / 67 fields |
| td scripts | `../T10.b17-paxi-native/r0/td/{01_build.tcl,02_bitgen.tcl,03_cwc.tcl}` | 01 hardcodes b17 paths -> must be rewritten |
| routed DB / bit | `../T10.b17-paxi-native/r0/td/a1_board_Runs/phy_1/a1_board_pr.db`, `r1/td/a1_board.bit` | reference only, not reused |

## 2. Overlay: b14 camera B (CAM_SEL=1)

| item | path | note |
|---|---|---|
| result r1 | `../T10.b14-cam-b/r1/result-r1.md` | B live (4,470 frames), CAM_SEL=1 in bit and on board; export FAIL (camera-independent) |
| CAM_SEL bit index | `../T10.b14-cam-b/r1/CAM_SEL-bit-index-finding.md` | CAM_SEL = **bit 12** (`cam_sysstat`), not bit 20 |
| changed-src | `../T10.b14-cam-b/r0/changed-src/` | r1 had **no RTL edit**, so r0 tree is the b14 RTL |
| core (B tap) | `../T10.b14-cam-b/r0/changed-src/f9p_camera_display_core.v` | 25 `o_b_*` / `o_dbg_b_*` ports |
| A-equivalence | `../T10.b14-cam-b/r0/diag/cam-sel-equivalence.md` | CAM_SEL=0 == b13 A wiring |
| SDC (B byte clk) | `../T10.b14-cam-b/r1/td/p2_board.sdc` | adds `mipi_b_byte_clk` generated clock |
| board record | `../T10.b14-cam-b/r1/board/board-run-r1.md`, `captures/board_gate.txt` | 150 s, 150 packets, B counters |
| board scripts | `../T10.b14-cam-b/r1/board/{run_board_r1.ps1,check_b14_board.py,parse_status_v5.py}` | v5 + bit12 logic |
| v6 board scripts | `../T10.b17-paxi-native/r1/board/{check_b17_board.py,parse_status_v6.py,run_board_b17_r1.ps1}` | v6 logic |

## 3. Evidence that the two defects are independent

- b14 r1 (B live, no PAXI fix): `timeout 13,410 / retry 8,940 / giveup 4,470`, `enc 0 / exported 0`.
- b15 r0 (camera A, no PAXI fix): identical export failure -> camera-independent DDR read defect.
- b17 r0 offline (PAXI native): 16-word readback 16/16, addresses 0/8/16..., `wstrb=0`,
  full-frame two-frame four-CRC+zlib, P1 three goldens, v6 273 B. Not yet on a live B stream.

## 4. Same-origin check

Both branches derive from b13. Diff of the 11 changed-src names (b14 vs b17):

| file | b14 | b17 | action in b18 |
|---|---|---|---|
| a1_ddr_arb2.v | B84019BD... | same | copy b17 (identical) |
| a1_ddr_slot_store.v | 6C619CF9... | same | copy b17 (identical) |
| a1_deflate_core.v | A91C2ED8... | same | copy b17 (identical) |
| a1_frame_top.v | 0064607A... | same | copy b17 (identical) |
| a1_raw_crop.v | 33A6FEE7... | same | copy b17 (identical) |
| cam_diag_mailbox.v | 352AF7C8... | same | copy b17 (identical) |
| f9p_camera_display_core.v | E17206FB... | C9DE0D9C... | **b14** (B tap) |
| p2_a1_board_top.v | D61C079B... | 9687D139... | **merge** (b17 base + b14 select) |
| p2_ddr_bridge.v | BFF1A358... | 790D8226... | **b17** (PAXI fix) |
| a1_uart_export.v | F8F9E4E3... | B3D61597... | **b17** (v6) |
| camera_a1_uart_top.v | ACC1EFF3... | 73D10388... | **b17** (512-bit dbg) |

## 5. Established conventions reused (not re-interviewed)

- Device PH1P100SBG484 speed 3, `Routed`, board `p2_a1_board_top`, PLL 187.5 MHz `clk_a1`.
- MIPI A/B byte clocks: A from `mipi_a_clk_hs_p`, B from `mipi_b_clk_hs_p` /4.
- Raw frame 2,592,000 B, 4 DDR slots, A+ v1 zlib stream, 115,200 8N1 UART, XOR8 status.
- Status packet v6 = 273 B / 67 fields / VER=6; v5 still parseable.
- FTDI `VID_0403&PID_6042`, COM8, 150 s capture, 1 SRAM download, no Flash.

## 6. Open items not in this package

- Full-rate sustained throughput, dual concurrent A/B export, PCIe/RK, Flash, G4.
- b14 note: B `lane_sticky=0x1` with complete frames (no action unless a lane-1 failure appears).
- A-camera MIPI pixel loss (b13) -- irrelevant here, B is the selected tap.
