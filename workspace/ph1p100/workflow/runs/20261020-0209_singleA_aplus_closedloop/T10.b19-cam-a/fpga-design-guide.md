# fpga-design-guide -- T10.b19-cam-a (delta of the b18 guide)

Frozen data formats, interfaces and build/board entries. Reuse b18 conventions; only the deltas
below change. If this file and `dev-plan.md` disagree, `dev-plan.md` gates win.

## 1. Camera select (only RTL delta)

- File: `r0/changed-src/p2_a1_board_top.v`, line 97:
  `localparam CAM_SEL = 1'b1;` -> `localparam CAM_SEL = 1'b0;`.
- No other character may change in `changed-src/`: the other 10 files are byte-identical to b18
  r0 (hashes in `dispatch.json.frozen.changed_src`); SDC/ADC byte-identical.
- Both `f9p_camera_display_core` instances stay; `generate g_cam_sel_a` is selected. A byte
  clock comes from the A PHY; `mipi_a_byte_clk` in the inherited SDC constrains it. Keep the B
  generated clock in the SDC (B core is still instantiated).
- `cam_sysstat = {19'd0, CAM_SEL, sel_lane_sticky, ...}`; with A selected and the stub test,
  expected `0x00000F1D` (bit12=0, lane sticky `4'hF`, cfg_done=1). Board value may differ in
  status bits; the gate is bit12=0, bit20=0 and A counters.

## 2. Status / frame formats (inherited, unchanged)

- v6 status: 273 B, VER=6, 67 u32 fields, XOR over bytes; field #13 `cam_sysstat` bit12 = CAM_SEL
  (must be **0**), bit20 must stay 0.
- A1U1 frame: 44 B header + stream; full frame `1920x1080`, `raw_len=2,592,000`; worst-case
  stored `stream_len<=2,594,706`; four CRCs (header/stream/xform/raw) + strict zlib.
- UART 115200 8N1: 2,594,706 B -> **225.2 s**; hence a 300 s capture window is mandatory for a
  stored frame. A 150 s window can truncate it (b18 used 300 s for the successful B frame).

## 3. Interface / clock / reset

- A camera tap: 40-bit pixel, valid/line/frame/vsync, byte clock; A core configured by its
  existing I2C init. `sys_rst_n` = board pin R14 (reset button, pull-up). A reset pulse restarts
  both camera cores and zeroes the counters; it is not a download.
- DDR/PAXI/v6/retry: b18 files unchanged (native x8 address, mask=0, single outstanding AR
  policy, R1 retry). No SDC, ADC, seed or frequency change.

## 4. Simulation conventions

- ModelSim ASE 10.5b, `P: = D:\fpga\ph1p100`, `W: = r0\sim`; every case `vlog Errors:0`, no X.
- Chain TB (`tb_b17_chain.sv`) drives the `camera_a1_uart_top` boundary; geometry/CRC/zlib are
  proven there. The A/B select is proven on the real top with verbatim-port stubs
  (`tb_b18_camsel.sv` pattern), because the D-PHY/photo-site path is not simulatable (b18 L4).
- A-specific stimulus uses A's tap signature; do not compare A frame bytes to B's, only the
  structural gates and self-consistent CRCs. P1 goldens are compared byte-for-byte.

## 5. Build entry (TD)

- `T: = r0\td`, `Y: = D:\fpga\ph1p100`; run `tools\td\td_env.ps1` first; never map `X:`.
- Scripts are b18 copies with paths rewritten to `T10.b19-cam-a\r0` (including `a1_board.al`
  absolute `<File Path>` entries). The filelist guard must see `p2_a1_board_top.v` and
  `f9p_camera_display_core.v` exactly once from this package, never `./src`.
- One synthesis, one route, one bitgen, one CWC; fail-closed STA at bitgen.

## 6. Board entry

- Preflight `VID_0403&PID_6042` + `HKLM\...\SERIALCOMM` COM8 with COM8 closed.
- One SRAM download of `r0\td\a1_board.bit` (JTAG, volatile), then release hwserver, pulse R14
  reset, then COM8 300 s. Capture to `r0\board\captures_a\`, parse v6 + frames, run the b19 gate.
- No Flash, no second download, no second capture. If A has no pixels, keep the capture and stop.
