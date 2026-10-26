# T10.b14-cam-b r1 -- why "the last bit compiled the old A-only version" is not supported

Status: **finding recorded during r1 build repair; no RTL edit.**

## 1. The r0 bit was built from `changed-src`, not from `./src`

The synthesis run writes the exact list of sources it consumed to
`r0/td/a1_board_Runs/syn_1/a1_board.prj` (`RunTime="2026-10-26T00:13:04"`).
That file contains exactly one entry for each of the two B-select files:

| file | occurrences in syn_1/a1_board.prj | path |
|---|---|---|
| `f9p_camera_display_core.v` | 1 | `.../T10.b14-cam-b/r0/changed-src/` |
| `p2_a1_board_top.v` | 1 | `.../T10.b14-cam-b/r0/changed-src/` |

No `./src/f9p_...`, no `./src/p2_a1_board_top.v`, no `src/src/` entry.
`r0/td/a1_board.al` agrees (only changed-src entries), and the post-route
netlist `r0/td/routed_netlist.v` carries
`// localparam CAM_SEL = 1'b1;` with cell source comments pointing at
`changed-src/p2_a1_board_top.v`.

The stale A-only copies do exist on disk (`r0/td/src/f9p_camera_display_core.v`,
`r0/td/src/p2_a1_board_top.v`, and a whole nested `r0/td/src/src/` tree), but
`add_files` never referenced them in r0 and does not in r1. r1 adds a
fail-closed guard that parses `syn_1/a1_board.prj` after synthesis and aborts
unless each basename appears exactly once, from `changed-src`.

## 2. `bit20` is a wrong bit index; the RTL packs CAM_SEL at bit 12

`p2_a1_board_top.v`:

```verilog
cam_sysstat = {19'd0, CAM_SEL, sel_lane_sticky, 3'd0,
               cam_cfg_rst_n, cam_pll_locked, cam_xclr_n,
               sel_bus_err_lat, sel_cfg_done};
```

Widths: 19 + 1 + 4 + 3 + 1 + 1 + 1 + 1 + 1 = 32.
`sel_cfg_done`=bit0 ... `3'd0`=bits 7:5, `sel_lane_sticky`=bits 11:8,
**`CAM_SEL`=bit 12**, `19'd0`=bits 31:13. The b13 packing was
`{20'd0, lane_sticky, 3'd0, ...}` with the same low bits and no bit 12.

Hardware proof (r0 capture, same bit, 2026-10-26 00:45-00:47):

| build | cam_sysstat on COM8 | meaning |
|---|---|---|
| b12/b13 | `0x00000F1D` | lane_sticky=0xF, bit12=0 |
| b14 r0 running bit | `0x00001F1D` | lane_sticky=0x1, **bit12=1 => CAM_SEL=1** |

`0x1F1D = 0x0F1D | 0x1000`; bit20 is 0 in every packet. The parser/checker
that demanded `(cam13 >> 20) & 1` could therefore never pass, and its "sel=0"
line was reporting bit20, not CAM_SEL. The r0 simulation evidence for "bit20"
came from `r0/sim/tb_status_v5_b14.v`, which *hardcodes*
`camsnap[13] = 32'h2232_000E` (i.e. it re-asserts the wrong index instead of
sampling the wrapper's real packing).

r1 corrects only the host-side tools (`parse_status_v5.py`,
`check_b14_board.py`): CAM_SEL is read at bit 12 and cross-checked against the
b13-invariant low bits (`cam13 & 0x1D == 0x1D`: cfg_done, xclr_n, pll_locked,
cfg_rst_n). RTL, SDC and the pin constraints are unchanged.

## 3. Consequence for the B question

The r0 capture was therefore already a real B run, and B is live:

- `pix_beats` delta 875,164,742, `line_rises` 9,798,240, `frame_rises` 4,470,
  `frame_falls` 4,470, `roi_frames` 4,470, `crop_geom_err` 0 in 150 s
  (~29.8 fps, 1080p ROI groups = 518,400 per frame).
- BUT `enc_frames`=0 and `exported`=0, with `timeout=13,410`, `retry=8,940`,
  `giveup=4,470` (3 timeouts / 2 retries / 1 give-up per frame).
- The identical export failure is present with the A camera in
  `T10.b15-ddr-pace/r0` (`cam_sysstat=0x00000F1D`, cap=4,500, enc=0,
  exported=0, giveup=4,500). So the store/encode failure is camera-independent
  and belongs to the b13/b15 DDR retry work, not to the B-select patch.

r1 still rebuilds and re-measures so the planner gets a clean, hash-bound
candidate and a fresh 150 s B capture; no RTL fix is attempted here.
