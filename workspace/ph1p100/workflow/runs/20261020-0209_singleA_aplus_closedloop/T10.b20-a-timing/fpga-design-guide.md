# fpga-design-guide -- T10.b20-a-timing

Frozen for `T10.b20-a-timing` r0. Reuse the b19 data/interface/protocol contract unchanged; this
package changes one RTL cone and nothing else. Authoritative numbers below; do not re-interpret
from older packages.

## 1. Identity and baseline

| item | value |
|---|---|
| top (synthesis) | `p2_a1_board_top.v` = b19 `B08438E8...981D0` (`CAM_SEL = 1'b0`) |
| changed-src | 11 files; 10 byte-identical to b19, `a1_frame_top.v` = b19 `0064607A...27109` + the approved pipeline change |
| SDC | `0888B6A7...20F5E` (b19: b18 file minus the `mipi_b` clock group) — byte-identical, no new SDC edit |
| ADC | `1CB30346...7158` (b17 r1) — byte-identical |
| device | PH1P100SBG484 speed 3; `clk_a1` = 187.5 MHz (5.333 ns); `ddr_user` 166.667 MHz |
| proven chain | PAXI x8 / mask=0 / retry / R1 raw store / v6 status |

frozen-in: b18 B board frame, b19 A sim set, b13/b14 history. frozen-out: b18 bit/CWC (reference
only), b19 (no bit exists), any seed/frequency/SDC relaxation.

## 2. The one change: abort -> smem read-address cone

b19 routed (`..\T10.b19-cam-a\r0\td\routed_timing.rpt` L105-185):

```
Slack -0.098  Begin u_a1/a1_abort_reg   End u_a1/u_a1/smem_syn_29.addrb[10]
Data 4.663 (cell 1.636 / net 3.027)  Skew 0.072  Uncertainty 0.211  Budget 5.333
Logic 6 (LUT6x2 LUT4x2 LUT3x1 ERAM)   -> smem_syn_29.addrb[12] is second at -0.091
```

The launch is `camera_a1_uart_top.a1_abort` (a real 1-cycle pulse, set on raw-read timeout or
`WD_LIMIT`). Inside `a1_frame_top` the same-cycle abort branch (`frame_active && (abort ||
proto_abort) && !commit`) feeds the drain teardown and the ERAM read-address next-state logic, so
the raw input lands 5 LUT levels in front of the ERAM address register.

Design rule for this package:

1. The ERAM read-address cone (`smem.addrb[*]`) must be launched only from registers whose D-cone
   does **not** contain the raw `abort`, `proto_abort` or `core_abort`. Exactly one extra register
   stage is allowed; it may delay the drain-side abort teardown by one cycle.
2. `core_abort` must stay combinational (`abort || proto_abort || core_flush`): the deflate core has
   to see the abort in the same cycle, otherwise an orphan block can be published.
3. `in_ready` keeps its immediate `!abort` term; `frame_abort` timing/width, CRC/length/stat
   updates, sample/block counts, output packing, `dbg` map and all protocol fields are unchanged.
4. Normal frames (no abort) must be **cycle-identical**: no extra D_GATH/D_EMIT bubble, same
   `cmp_words`, same `cycles`.
5. Aborted data is discarded (already the b19 behaviour); the extra cycle may only extend the
   teardown, never publish, never change `frame_abort`.

Do not use `ifdef`/`force`/test hooks; the simulated DUT must be the synthesized RTL. Do not touch
`a1_deflate_core.v`, `camera_a1_uart_top.v`, the top, SDC, ADC.

## 3. Data and interface contract (unchanged)

- Frame: 1920x1080 ROI from a 3864x2192 A sensor frame; raw 2,592,000 B; stream typical 2,594,706 B.
- u_a1 boundary: 40-bit group `in_pix`, `in_valid`, `in_sof`; 32-bit `out_data/out_keep/out_last`;
  `frame_commit`/`frame_abort` single-cycle semantics.
- Status: v6, 273 B, 67 fields, camera select = field #13 bit **12** (A=0), bit20=0; the parser map
  is b19 lesson L5 (`cam3`=pix_beats).
- Board export: raw slot -> `a1_frame_top` -> `a1_deflate_core` -> `a1_uart_export`; four CRCs
  (raw/xform/stream + container) and zlib-decodable stream.
- DDR: PAXI x8, mask=0, low3=0, retry/R1 store; `timeout/retry/giveup` counters; A and B do not
  share a bitstream.

## 4. Timing / buffering budget

| gate | value |
|---|---|
| synth | `SWNS >= 0`, `STNS >= 0`, 0 violations; route pre-condition `SWNS >= +0.127` |
| routed | 0 violated endpoints, `HWNS >= 0`, `WNS >= +0.05`; `+0.003..<+0.05` = thin-margin caveat |
| per group | `clk_a1 >= +0.05`, `ddr_user >= +0.003`, `mipi_a_byte_clk >= +0.05`, `sys_clk50m >= +1.0`, `pclkx1 >= +0.5`, others 0 violations |
| resources | slices <= 25,800, ERAM <= 103, DSP 0, GCLK 9 |
| cone break | 0 routed paths `a1_abort_reg -> smem.addrb[*]`; quote new worst `clk_a1` path |
| latency | +0..+1 cycle on abort teardown only; T1 `cycles` exactly 37,465,298 |

`post_route_opt` and retiming stay at the b19 frozen setting. No seed sweep, no frequency change,
no multicycle/false-path, no `set_clock_groups` edit.

## 5. Work directories and entry points

- TD: `T: = <pkg>\r0\td`, `Y: = D:\fpga\ph1p100`; run `tools\td\td_env.ps1 -TdDir <pkg>\r0\td -Force`
  first; never map `X:` to the project root.
- Sim: `P: = D:\fpga\ph1p100`, `W: = <pkg>\r0\sim`; ModelSim ASE, `vlog/vsim` from `tools`.
- Board: `<pkg>\r0\board\`; COM8 115200 8N1; captures in `captures_a\`.
- All generated paths must point into `T10.b20-a-timing`; a stale `..\T10.b19-cam-a\...` path in a
  build script is a hard failure (it silently builds b19).

## 6. Existing constraints to respect

- `td/src` is copied from b19 (332 files, 3.4 MB) including `*.v.stale`; keep the renames, never add
  `./src/p2_a1_board_top.v`, `./src/f9p_camera_display_core.v`, `./src/src/*` (duplicate modules).
- The SDC keeps the expected `create_generated_clock ... mipi_b_byte_clk` warning (the B divider is
  trimmed); it is harmless once the B group is gone. Do not "fix" it.
- `01_build.tcl` exits 0 even when route STA is negative; the gate is `P2_ROUTED_SWNS/VIOL_EP`
  (b19 lesson L9).
- bitgen/CWC are separate single attempts with fail-closed final STA; compiled `cw/` must be
  byte-identical to `td/`.
