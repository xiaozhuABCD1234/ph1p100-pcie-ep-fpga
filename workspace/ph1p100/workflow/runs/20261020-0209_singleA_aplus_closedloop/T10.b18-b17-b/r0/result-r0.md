# result -- T10.b18-b17-b r0 (merged B tap + native PAXI + v6)

Run `20261020-0209_singleA_aplus_closedloop`. Package `T10.b18-b17-b`, round **r0**.
Developer: general (fpga-dev delegated). 2026-10-26.

**Verdict: offline candidate COMPLETE and self-consistent (merge, T1-T6, Routed,
bitgen, CWC all pass); board = BLOCKED at preflight (no FTDI `0403:6042`, no
COM8) -> 0 downloads, 0 captures, no board claim.**

## 1. What was built

`r0/changed-src/` = b17 native-PAXI/v6/R1-retry base + b14 camera-B overlay:

| file | source | sha256 (short) |
|---|---|---|
| `p2_ddr_bridge.v` | b17 (byte copy) | `790d8226...740a61` |
| `a1_uart_export.v` | b17 (v6, byte copy) | `b3d61597...4c298d` |
| `camera_a1_uart_top.v` | b17 (512-bit dbg, byte copy) | `73d10388...0cbd3ff2` |
| `f9p_camera_display_core.v` | b14 (B tap, byte copy) | `e17206fb...080760` |
| `p2_a1_board_top.v` | **merge** | `f5badfe1...a338f4` |
| 6 shared files | b17 == b14 (byte copy) | `b84019bd/6c619cf9/a91c2ed8/0064607a/33a6fee7/352af7c8` |
| `td/p2_board.sdc` | b14 r1 (mipi_b_byte_clk) | `3fe16412...9cf2ed` |
| `td/board_p2.adc` | b17 r1 | `1cb30346...2271580` |

Merge edits in the top: 1 CAM_SEL localparam, 2 B tap wires, 3 25 B core ports,
4 `sel_*` + `generate/g_cam_sel_b/g_cam_sel_a`, 5 `u_a1` on `sel_*`,
6 `cam_sysstat` bit 12 + mailbox `sel_nack_cnt`, 7 b17 v6 plumbing untouched.
Documented extras: the b14 camera-control header comment line, and moving
`wire [511:0] dbg_bridge;` / `wire a1_rd_abort;` **above** their first use (a
Verilog-2001 forward reference otherwise creates 1-bit implicit nets; see
lessons L1).  No net, width, name or connectivity change.

## 2. Merge conformance — `r0/merge-conformance-r0.txt`

`C01..C18 ALL_PASS` (`r0/check_merge_b18.py`, exit 0).  C18 is filled by the
stub-top simulation; the other 17 are static.  C16 also guards the TD filelist:
`P2_PRJ_GUARD_PASS` from `syn_1/a1_board.prj` (each of the merged top and the
B-tap core appears exactly once from this package; the stale `./src` shadow
copies were renamed `*.v.stale`).

## 3. Simulation (ModelSim ASE 10.5b, `r0/sim/run_b18.py`, every build `vlog Errors:0`)

| id | case | result |
|---|---|---|
| T1 | `chain/t1_b_geometry` (b14 S1 shape, 3864x2192, ROI 972/556, 1920x1080) | **PASS** `source_groups=2,117,472` `line_rises=2,192` `frame_rises=1` ROI frames 1/1 `crop_beats=518,400` `raw_len=2,592,000` `enc=1` `exported=1` four CRCs + strict zlib, timeout/retry/giveup 0, 23:57 run |
| T2 | `native` 16-word readback + mask/addr/conc/b15 negatives | **PASS** 5/5 cases (`native_*` in `sim-results-b18-native.json`), addresses 0,8,...,120, wstrb=0, model mask/oob/concurrency 0 |
| T3 | `p1` micro8x2 / mid64x8 / full_grad | **PASS** all three compressed captures byte-identical to `r0/sim/caps/*.dec` goldens |
| T4 | `t4a_drop1` (drop 1 R) and `t4b_drop_mid3` (3 frames, 1 drop) | **PASS** timeout 1 / retry 1 / giveup 0, frames export with four CRCs + zlib, no deadlock; a 2-drop variant also recovered 3/3 frames (noted in `run_b18.py`; the inherited "<=1 unanswered AR at rest" rule rejects 2 injected drops by construction) |
| T5 | `status` v6 structure | **PASS** `273 B / VER=6 / 67 fields / XOR ok`, 4 packets, field #13 `0x00001001` -> **bit12=1**, diag_flags bits1..5 = 0; parser copy still accepts v5, board gate requires v6 |
| T6 | CAM_SEL=0 static equivalence (C17) | **PASS** 17 A-branch pairs, `diffs=0`, `cam_sysstat` with CAM_SEL=0 == b13 word (`r0/diag/cam-sel-equivalence.md`) |
| C18 | `tb_b18_camsel.sv`: **real merged top** + verbatim-port stubs, A/B taps with different signatures | **PASS** `sysstat=0x0000111D` (`bit12=1`, `sel_lane_sticky=4'h1` = B, A would be `4'hF`), `u_a1.i_a_pixel=0xb18b18b18b` (B tap), selected byte clock toggling |

Note: the frozen chain TB writes `b15_pix_beats = crop_beats (518,400)` and
`b15_crop_groups = source_groups (2,117,472)` — the two labels are swapped in
`tb_b17_chain.sv`; the gate therefore asserts the unambiguous keys
`source_groups` / `crop_beats` / `b15_raw_len`.

## 4. Build (`r0/td`, 2 TD sessions, 1 synth, 1 route, 1 bitgen, 1 CWC)

- Synthesis: `SWNS=+0.426  STNS=0.000  SLICE=19405  ERAM=72  REG=20734`.
- Routed: **`SWNS=+0.066` `STNS=0.000` `HWNS=+0.020` `HTNS=0.000`
  `0 violated endpoints / 26624`**, `#eram 103 / 300`, `#slice 25968 (36.23%)`,
  `#gclk 10`, period check positive.  **WNS +0.066 >= +0.05 target -> no
  timing caveat.**  (`routed_qor.rpt`, `routed_timing_status.rpt`,
  `phy_pr_timing_flow.rpt`, `build_console_r0.log`)
- No SDC/seed/frequency change: `p2_board.sdc` is the b14 r1 file, false-path /
  multicycle lines unchanged (C14), `mipi_b_byte_clk` generated clock present.
- bitgen (1): fail-closed STA `SETUP=0.066/0.000 HOLD=0.020/0.000 PERIOD=2.200`
  -> `a1_board.bit` `f51faa5dc97fda66f9ecfcf24c77a7364ce9df1e8e91f6c10d7366e36d2868fc`
  (5,224,022 B).
- CWC (1): `a1_board.cwc` `1f0c31738a8e588274f3a96c53b84fc8340e795633679976d0d0ab9ecc8726e1`
  (111,266 B), `<phy_eram` present, no incomplete `<logic_eram/>`,
  `cw/compiled.bit|.cwc` byte-identical to the parent, bid
  `32e180702d5657309fb0a7a20aeb4936053224c360fcc604b815adf632e80ce0`.

## 5. Board — **blocked at preflight**

`r0/board/run_board_b18.ps1` STEP0: `Get-PnpDevice -PresentOnly` shows **no**
`VID_0403&PID_6042` device (5 non-present 0403 instances, i.e. the cable
enumerated earlier and dropped) and `HKLM\...\SERIALCOMM` does not exist -> no
COM8.  A first preflight (18:5x) briefly saw `FTDI_PRESENT=1` but no COM
mapping, so the script refused before STEP1.  Therefore, by the dispatch rule:

- **downloads = 0, captures = 0, COM8 never opened, no Flash**;
- no v6 packet, no delta, no frame CRC evidence on hardware;
- `board/log/board_blocked.txt` + `board/log/ftdi_preflight.txt` are the record;
- `board = blocked` (not FAIL) and **this candidate must not be reported as
  board-passed**.  The b14-on-board timeout/retry/giveup/export question is
  still open.

## 6. Budget / deviations

- Dev calls ~58, wall ~3 h 50 m (sim T1 alone 24 min, synth 327 s, route ~16 min,
  bitgen+CWC ~5 min).  TD sessions 2, synth 1, route 1 (786 s opt+place +
  201 s route), bitgen 1, CWC 1, downloads 0, Flash 0.
- Deviations from `merge-spec.md` (all documented above): 2 cosmetic/ordering
  edits in the top (comment line, declaration order), `.al` source paths
  rewritten to this package (bitgen opens `./a1_board.al`), three stale
  `r0/td/src/*.v` renamed `*.v.stale`, `tb_status_v6.v` sets field #13 to
  `0x00001001`, T4b accepted case uses one injected drop.
- Untested boundaries: real MIPI-B photo-site path is hardware-only (geometry
  and select are proven at the tap/top level, not through the D-PHY); B eye /
  IDELAY tap not swept (`CAM_B_IDELAY_TAP = 6'd46`, unchanged); no sustained
  full-rate throughput, dual-export, Flash, PCIe/RK.
