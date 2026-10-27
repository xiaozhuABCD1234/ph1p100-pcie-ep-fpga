# T10.b18-b17-b -- merge specification (line-level, frozen)

Base = `../T10.b17-paxi-native/r0/changed-src/` (PAXI native + v6 + R1 retry).
Overlay = `../T10.b14-cam-b/r0/changed-src/` (B tap, CAM_SEL, B diagnostics).

## 1. File-level recipe (`r0/changed-src/`, 11 files)

| file | source | mode |
|---|---|---|
| `p2_ddr_bridge.v` | b17 `790D8226EC69499C87B92B0E4A05AC0F26915F57B96BD541AFFDCDAC8E740A61` | copy |
| `a1_uart_export.v` | b17 `B3D61597534AA0609C53634313E4D14F222839F8B9B8ED83AFC140DAA04C298D` | copy (v6) |
| `camera_a1_uart_top.v` | b17 `73D10388C4A802421563B5B4C66F9CC37D600E7EC49FC0FA94B3D3EA0CBD3FF2` | copy (512-bit dbg) |
| `f9p_camera_display_core.v` | b14 `E17206FB2E15F7590EE55C2CCC072677356AB2CB8EFA41FD95AD6D52AB080760` | copy (B tap) |
| `p2_a1_board_top.v` | b17 `9687D13906B4199FADDAC2C387C9433624DCA68EF03441F8796C65612C442B17` | **merge, 8 edits (§2)** |
| `a1_ddr_arb2.v` | b17 (`B84019BDA057...`, == b14) | copy |
| `a1_ddr_slot_store.v` | b17 (`6C619CF90E54...`, == b14) | copy |
| `a1_deflate_core.v` | b17 (`A91C2ED82FBE...`, == b14) | copy |
| `a1_frame_top.v` | b17 (`0064607ACEB2...`, == b14) | copy |
| `a1_raw_crop.v` | b17 (`33A6FEE77FD1...`, == b14) | copy |
| `cam_diag_mailbox.v` | b17 (`352AF7C85094...`, == b14) | copy |

TD side files: `r0/td/p2_board.sdc` = b14 r1 `3FE1641270EB0CD90A25A3D4724617F7F81103D83F8D364BB954CD41329CF2ED`
(4,317 B); `r0/td/board_p2.adc` = `1CB30346FA17DA6BB0E77802CA72C4B4BB4AECC1445711E19391CF4EE2271580` (7,154 B, unchanged).

## 2. `p2_a1_board_top.v`: the 8 merge edits

All anchors are from the b17 file. Keep b17 text/order otherwise; do not reflow unrelated lines.

1. **CAM_SEL localparam** after the camera front-end header (before `wire [39:0] a_pixel;`):
   ```verilog
   // T10.b18-b17-b: compile-time camera select. 0 = A (b13 wiring), 1 = B.
   // A localparam, never a register or LUT clock mux; the selected byte clock
   // is a direct BUFG connection.
   localparam CAM_SEL = 1'b1;
   ```
2. **B tap wires** next to the existing A tap wires:
   ```verilog
   wire [39:0] b_pixel;
   wire        b_pixel_valid, b_in_line, b_in_frame, b_vsync, b_byte_clk;
   wire        b_dbg_cfg_done, b_dbg_bus_err_lat;
   wire [31:0] b_dbg_nack_cnt;
   wire [3:0]  b_dbg_lane_sticky;
   wire [5:0]  b_dbg_delay_tap;
   wire        b_dbg_delay_done, b_dbg_rst_out, b_dbg_sync_wait;
   wire        b_dbg_pkt_tgl, b_dbg_vs_tgl, b_dbg_clk_tgl;
   wire        b_dbg_in_frame, b_dbg_vsync;
   ```
3. **Camera core port map**: add all 25 B port connections from b14 after `.o_dbg_cfg_rst_n (cam_cfg_rst_n),`
   (`o_b_*` 6 + `o_dbg_b_*` 19; the 6 `o_dbg_b_*_frames/crc/header/last_*` stay unconnected `()` as in b14).
4. **Select mux**: insert b14's `sel_*` wire block and `generate / g_cam_sel_b / g_cam_sel_a / endgenerate`
   verbatim (CAM_SEL=1 -> B, else A; A branch line-identical to b13).
5. **`u_a1` selection**: `clk_cam(sel_byte_clk)`, `i_a_pixel(sel_pixel)`, `i_a_pixel_valid(sel_pixel_valid)`,
   `i_a_in_line(sel_in_line)`, `i_a_in_frame(sel_in_frame)`, `i_a_vsync(sel_vsync)`,
   `i_dbg_tap..i_dbg_clk_tgl` = `sel_*`.
6. **`cam_sysstat` at bit 12**:
   ```verilog
   wire [31:0] cam_sysstat = {19'd0, CAM_SEL, sel_lane_sticky, 3'd0,
                              cam_cfg_rst_n, cam_pll_locked, cam_xclr_n,
                              sel_bus_err_lat, sel_cfg_done};
   ```
   and mailbox `.i_data({cam_sysstat, sel_nack_cnt})`.
7. **Keep b17 v6 plumbing untouched**: `wire [511:0] dbg_bridge`, `dbg_a1` 512-bit connection,
   `camera_a1_uart_top.i_dbg_bridge` 512, `sts_ext_bus[767:0]`, v6 export constants.
8. **Comments**: replace the stale `bit20` comment in b14 with `bit 12 records the selected camera`.

## 3. Conformance checks (dev writes `r0/check_merge_b18.py`)

Must all be true; script prints one line per check, exit != 0 on any failure.

```
C01 f9p_camera_display_core.v sha256 == E17206FB...080760
C02 p2_ddr_bridge.v           sha256 == 790D8226...740A61
C03 a1_uart_export.v          sha256 == B3D61597...4C298D
C04 camera_a1_uart_top.v      sha256 == 73D10388...0CBD3FF2
C05 other 6 changed-src       sha256 == list in §1
C06 top: count("localparam CAM_SEL = 1'b1;") == 1
C07 top: count("g_cam_sel_b") == 1 and count("g_cam_sel_a") == 1
C08 top: count("{19'd0, CAM_SEL, sel_lane_sticky, 3'd0") == 1
C09 top: count("20'd0, cam_lane_sticky") == 0
C10 top: o_b_pixel / o_b_byte_clk / o_dbg_b_lane_sticky / o_dbg_b_last_lines connections == 1 each
C11 top: ".clk_cam             (sel_byte_clk)" == 1 ; ".i_a_pixel           (sel_pixel)" == 1
C12 top: "wire [511:0] dbg_bridge" == 1 ; "wire [255:0] dbg_bridge" == 0
C13 export: STS_LEN 9'd273, STS_VER 8'd6, allsnap [2143:0], extsnap 768 -- unchanged from b17
C14 SDC == 3FE16412...9CF2ED ; contains mipi_b_byte_clk generated clock (divide_by 4) and
    group {mipi_b_clk_hs mipi_b_byte_clk}; no extra false_path/multicycle
C15 board_p2.adc == 1CB30346...2271580
C16 sync prj: each of f9p_camera_display_core.v / p2_a1_board_top.v exactly 1 entry, path under
    T10.b18-b17-b/r0/changed-src ; no "./src/<either>" ; no "src/src/"  (build guard, hard abort)
C17 CAM_SEL=0 static equivalence: regenerate the b14 `cam-sel-equivalence` comparison against the
    b13 A wiring on the merged file; 0 differences in the A branch
C18 v6 field #13 bit12 test: TB-visible cam_sysstat bit12 == 1 with CAM_SEL=1
```

## 4. Explicitly unchanged (byte-identical or zero-diff)

`a1_ddr_slot_store.v`, `a1_ddr_arb2.v`, `a1_frame_top.v`, `a1_raw_crop.v`, `a1_deflate_core.v`,
`cam_diag_mailbox.v`, `board_p2.adc`, `a1_small_top.sdc`, frame/CRC/zlib path, 4-slot layout,
UART divisors, PLL, pins, ERAM budget. No new ports on the UART side.

## 5. If the merge cannot be made to conform

Stop after 2 mechanical attempts (no source rewrite beyond §2), return `blocked` with the failing
check id and the diff; do not fall back to a hand-edited selective rewrite of b17's v6 logic.
