# T10.b14-cam-b — CAM_SEL=0 A-branch equivalence (static, line by line)

Baseline: `T10.b13-ddr-retry/r0/changed-src/p2_a1_board_top.v`
(SHA256 `48881d574352fd2c61f7587d3687f215bb11ea18d5b5d0b4772820a938de561b`)
Compare: `T10.b14-cam-b/r0/changed-src/p2_a1_board_top.v`
(SHA256 `d61c079b6e1302f51463c3f9b9aef3e716d5b8d05bca04be44d4bb6b355287ca`)

`CAM_SEL` is a `localparam` (1'b0 = A, 1'b1 = B) and every selection is a
`generate`-branch continuous assignment.  There is no register, no LUT mux, no
runtime switch: a build picks exactly one branch.

## 1. A+ camera-side signals into `camera_a1_uart_top`

| b13 A connection            | b14 `CAM_SEL=0` (g_cam_sel_a) | b14 `CAM_SEL=1` (g_cam_sel_b) |
|---|---|---|
| `.clk_cam(a_byte_clk)`      | `sel_byte_clk = a_byte_clk`   | `sel_byte_clk = b_byte_clk`   |
| `.i_a_pixel(a_pixel)`       | `sel_pixel = a_pixel`         | `sel_pixel = b_pixel`         |
| `.i_a_pixel_valid(a_pixel_valid)` | `= a_pixel_valid`       | `= b_pixel_valid`             |
| `.i_a_in_line(a_in_line)`   | `= a_in_line`                 | `= b_in_line`                 |
| `.i_a_in_frame(a_in_frame)` | `= a_in_frame`                | `= b_in_frame`                |
| `.i_a_vsync(a_vsync)`       | `= a_vsync`                   | `= b_vsync`                   |
| `.i_dbg_tap(cam_delay_tap)` | `sel_delay_tap = cam_delay_tap` | `= b_dbg_delay_tap`         |
| `.i_dbg_delay_done`         | `cam_delay_done`              | `b_dbg_delay_done`            |
| `.i_dbg_rst_out`            | `cam_rst_out`                 | `b_dbg_rst_out`               |
| `.i_dbg_sync_wait`          | `cam_sync_wait`               | `b_dbg_sync_wait`             |
| `.i_dbg_pkt_tgl`            | `cam_pkt_tgl`                 | `b_dbg_pkt_tgl`               |
| `.i_dbg_vs_tgl`             | `cam_vs_tgl`                  | `b_dbg_vs_tgl`                |
| `.i_dbg_clk_tgl`            | `cam_clk_tgl`                 | `b_dbg_clk_tgl`               |
| `.i_dbg_sys(dbg_sys_snap)`  | unchanged                     | unchanged                     |

`cam_delay_tap`, `cam_delay_done`, `cam_rst_out`, `cam_sync_wait`,
`cam_pkt_tgl`, `cam_vs_tgl`, `cam_clk_tgl`, `cam_cfg_done`, `cam_bus_err_lat`,
`cam_nack_cnt`, `cam_lane_sticky` are still produced by the **A** core ports,
exactly as in b13; the `else` branch re-uses those exact nets.  Therefore with
`CAM_SEL=0` `sel_*` are the b13 nets (possibly renamed by the synthesizer, same
connectivity) and the A+ instance sees the b13 values.

## 2. `cam_sysstat` / `u_dbg_sys_mail`

b13:
```verilog
wire [31:0] cam_sysstat = {20'd0, cam_lane_sticky, 3'd0,
                           cam_cfg_rst_n, cam_pll_locked, cam_xclr_n,
                           cam_bus_err_lat, cam_cfg_done};
.i_data ({cam_sysstat, cam_nack_cnt})
```
b14:
```verilog
wire [31:0] cam_sysstat = {19'd0, CAM_SEL, sel_lane_sticky, 3'd0,
                           cam_cfg_rst_n, cam_pll_locked, cam_xclr_n,
                           sel_bus_err_lat, sel_cfg_done};
.i_data ({cam_sysstat, sel_nack_cnt})
```
With `CAM_SEL=0` this is bit-for-bit the b13 word (bit20 was 0) because
`sel_lane_sticky = cam_lane_sticky`, `sel_bus_err_lat = cam_bus_err_lat`,
`sel_cfg_done = cam_cfg_done`, `sel_nack_cnt = cam_nack_cnt`.
`cam_xclr_n / cam_pll_locked / cam_cfg_rst_n` are shared A/B and unchanged.
`CAM_SEL=1` only adds bit20 = 1.

## 3. Core A ports/instances

The 26 new core outputs are appended after `o_dbg_cfg_rst_n`; the existing A
ports/order, `u_csi_a`, `CAM_IDELAY_TAP = 6'd46`, HDMI/TPG, A I2C and
`dbg_uart` are untouched.  The only functional core additions are pure
`assign`s to pre-existing `w_b_*`/`r_b_*` state, six `u_csi_b` status wires and
`CAM_B_IDELAY_TAP = 6'd46` for `u_csi_b`.

## 4. What is *not* equivalent

With `CAM_SEL=1` the A counters are not in the v5 packet (they still run inside
the core).  That is the documented observation boundary of this package, not a
change to the A path: rebuilding with `CAM_SEL=0` restores the b13 candidate.
