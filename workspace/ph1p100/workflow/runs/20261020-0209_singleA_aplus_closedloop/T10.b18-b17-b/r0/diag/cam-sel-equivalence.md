# T10.b18-b17-b — CAM_SEL=0 A-branch equivalence (merged top, static)

Baseline A wiring: `T10.b13-ddr-retry/r0/changed-src/p2_a1_board_top.v`
(SHA256 `48881d574352fd2c61f7587d3687f215bb11ea18d5b5d0b4772820a938de561b`).
Merged file: `r0/changed-src/p2_a1_board_top.v` (b17 base + 8 B-side edits,
SHA256 recorded in `CANDIDATE-MANIFEST-b18-b17-b-r0.json`).
Produced by `r0/check_merge_b18.py` check **C17** (`r0/merge-conformance-r0.txt`).

`CAM_SEL` is a `localparam` (`1'b1` in this candidate); every selection is a
`generate` continuous assignment.  A build picks exactly one branch — there is
no register, no LUT mux, no runtime switch.

## 1. A branch (`g_cam_sel_a`), 17 assignments, compared pair by pair

| b13 A connection | merged `CAM_SEL=0` |
|---|---|
| `.clk_cam(a_byte_clk)` | `sel_byte_clk = a_byte_clk` |
| `.i_a_pixel(a_pixel)` | `sel_pixel = a_pixel` |
| `.i_a_pixel_valid(a_pixel_valid)` | `sel_pixel_valid = a_pixel_valid` |
| `.i_a_in_line(a_in_line)` | `sel_in_line = a_in_line` |
| `.i_a_in_frame(a_in_frame)` | `sel_in_frame = a_in_frame` |
| `.i_a_vsync(a_vsync)` | `sel_vsync = a_vsync` |
| `.i_dbg_tap(cam_delay_tap)` | `sel_delay_tap = cam_delay_tap` |
| `.i_dbg_delay_done(cam_delay_done)` | `sel_delay_done = cam_delay_done` |
| `.i_dbg_rst_out(cam_rst_out)` | `sel_rst_out = cam_rst_out` |
| `.i_dbg_sync_wait(cam_sync_wait)` | `sel_sync_wait = cam_sync_wait` |
| `.i_dbg_pkt_tgl(cam_pkt_tgl)` | `sel_pkt_tgl = cam_pkt_tgl` |
| `.i_dbg_vs_tgl(cam_vs_tgl)` | `sel_vs_tgl = cam_vs_tgl` |
| `.i_dbg_clk_tgl(cam_clk_tgl)` | `sel_clk_tgl = cam_clk_tgl` |
| *(status)* | `sel_cfg_done = cam_cfg_done` |
| *(status)* | `sel_bus_err_lat = cam_bus_err_lat` |
| *(status)* | `sel_nack_cnt = cam_nack_cnt` |
| *(status)* | `sel_lane_sticky = cam_lane_sticky` |

C17 result: `pairs=17 diffs=0`.

## 2. `cam_sysstat` with `CAM_SEL=0`

b13:
```verilog
wire [31:0] cam_sysstat = {20'd0, cam_lane_sticky, 3'd0,
                           cam_cfg_rst_n, cam_pll_locked, cam_xclr_n,
                           cam_bus_err_lat, cam_cfg_done};
```
merged (C08 / C17):
```verilog
wire [31:0] cam_sysstat = {19'd0, CAM_SEL, sel_lane_sticky, 3'd0,
                           cam_cfg_rst_n, cam_pll_locked, cam_xclr_n,
                           sel_bus_err_lat, sel_cfg_done};
```
With `CAM_SEL=0` the leading `19'd0 + 1'b0` is bit-for-bit the b13 `20'd0`, and
`sel_lane_sticky / sel_bus_err_lat / sel_cfg_done / sel_nack_cnt` are the b13
A nets (§1), so the 32-bit word and the `{cam_sysstat, nack_cnt}` mailbox
payload are identical to b13.  With `CAM_SEL=1` only bit 12 differs (set to 1).

Field position: v6 field #13 = `cam_sysstat`, so `CAM_SEL` is **bit 12** of
status field #13 (the b14 "bit20" comment was stale; see
`T10.b14-cam-b/r1/CAM_SEL-bit-index-finding.md`).

## 3. Dynamic cross-check (this package)

`r0/sim/tb_b18_camsel.sv` elaborates the **real merged top** with structural
stubs (PLL, DDR shell, MCU, camera core, A1 chain, PAXI bridge) whose A and B
taps carry different signatures.  With `CAM_SEL=1'b1` it observes

```
B18_CAMSEL_SYSSTAT=0000111d  NACK=000000b1
B18_CAMSEL_U_A1_PIXEL=b18b18b18b CLK_EDGES=67 I_VALID=1
B18_CAMSEL_RESULT pass=1 bit12=1 b_selected=1
```

i.e. `cam_sysstat[12]=1`, `sel_lane_sticky=4'h1` (B value, A would be `4'hF`),
`u_a1.i_a_pixel` = the B signature and the selected byte clock toggling.
A wrong mux or a wrong concat pack fails this test.

## 4. What is *not* equivalent

With `CAM_SEL=1` the A counters are not exported (the A core keeps running);
that is the documented observation boundary, not a change to the A path —
rebuilding with `CAM_SEL=0` restores the b13 candidate.
