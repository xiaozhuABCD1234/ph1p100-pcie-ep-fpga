# input-index -- T10.b19-cam-a

Run `20261020-0209_singleA_aplus_closedloop`. Package `T10.b19-cam-a` (new task, round0).
Planner: general (fpga-planner delegated). Date 2026-10-26. Batch size 1.

## 1. Requirement (user, verbatim intent)

Try the **A camera** on the chain that b18 proved with camera B. Baseline = b18 r0 changed-src,
change only `CAM_SEL 1 -> 0`; keep PAXI native x8 / mask=0 / retry / R1 / v6 / B code. Sim A
geometry, P1, 16-word native, drop-R retry, v6 bit12=0. Rebuild 0 violations / WNS >= +0.05
target; 1 bitgen + 1 CWC. Board: download first, then COM8 **300 s + reset alignment** (stored
frame ~225 s); require A pix/line/frame > 0, enc/exported > 0, >=1 frame four CRCs + zlib. If A
still has no pixels, stop and keep evidence (A hardware), no second bitstream.

## 2. Frozen inputs (read-only)

| id | path | state |
|---|---|---|
| b18 candidate | `..\T10.b18-b17-b\r0\changed-src\` (11 files) | B live full frame on board; this is the only source baseline |
| b18 top | `..\T10.b18-b17-b\r0\changed-src\p2_a1_board_top.v` | SHA256 `F5BADFE181A83140428EC6CB6C7B0740DB3320A123F45DC4E624DC996DA338F4`; line 97 `localparam CAM_SEL = 1'b1;` is the single edit point |
| b18 sim | `..\T10.b18-b17-b\r0\sim\` | `run_b18.py`, `tb_b17_chain.sv`, `tb_b17_paxi_native.sv`, `tb_status_v6.v`, `tb_b18_camsel.sv`, `gen_stubs.py`, `sim-results-b18-*.json` |
| b18 merge checker | `..\T10.b18-b17-b\r0\check_merge_b18.py` | C01-C18; C17 A-branch equivalence `pairs=17 diffs=0`; C18 real-top stub |
| b18 A-branch diag | `..\T10.b18-b17-b\r0\diag\cam-sel-equivalence.md` | A wiring pair list; CAM_SEL=0 expected `sysstat` bit12=0, lane sticky `4'hF` |
| b18 TD scripts | `..\T10.b18-b17-b\r0\td\{01_build.tcl,02_bitgen.tcl,03_cwc.tcl,a1_board.al,run_build_b18.ps1}` | copy + rewrite paths; do not reuse b18 bit/cwc |
| SDC | `..\T10.b18-b17-b\r0\td\p2_board.sdc` | SHA256 `3FE1641270EB0CD90A25A3D4724617F7F81103D83F8D364BB954CD41329CF2ED` (b14 r1, has `mipi_a_byte_clk` and `mipi_b_byte_clk`) |
| ADC | `..\T10.b18-b17-b\r0\td\board_p2.adc` | SHA256 `1CB30346FA17DA6BB0E77802CA72C4B4BB4AECC1445711E19391CF4EE2271580` |
| b18 board scripts | `..\T10.b18-b17-b\r0\board\{run_board_b18.ps1,capture_com8.py,parse_status_v6.py,check_b18_board.py,dl_b18_r0.tcl}` | copy + rewrite to b19; `-Secs 300`; new download tcl |
| b18 TD result | `..\T10.b18-b17-b\r0\td\{routed_qor.rpt,routed_timing_status.rpt,a1_board.bit,a1_board.cwc}` | reference only: WNS +0.066, 0 violations, ERAM 103; bit `F51FAA5D...68FC`, CWC `1F0C3173...26E1` |
| b18 board evidence | `..\T10.b18-b17-b\r0\board\captures_full\` | **the actual B success**: `com8_300s.bin` SHA256 `143AA87D...09E4`; `FRAME id=1 1920x1080 raw_len=2,592,000 stream_len=2,594,706 four_crcs=1 zlib_ok=1`; `exported=1 enc=2 raw_pub=4`; `ar=r=rlast=340,767`; `timeout/retry/giveup=0`; `sysstat=0x1F1D` bit12=1 |
| b18 result doc | `..\T10.b18-b17-b\r0\result-r0.md` | **stale on board**: it records the earlier FTDI-blocked run, not `captures_full`; use the capture as evidence |
| A history | `..\T10.b13-ddr-retry\` | r1 A-only board: 150 v5 packets, `bad_xor=0`, **A1U1 frames 0, `pix_beats=0`**; r1 Routed WNS +0.023 (thin-margin wording) |
| b13 A top | `..\T10.b13-ddr-retry\r0\changed-src\p2_a1_board_top.v` | SHA256 `48881D574352FD2C61F7587D3687F215BB11EA18D5B5D0B4772820A938DE561B` (A-wiring baseline for C17) |
| tools | `D:\fpga\ph1p100\tools\td\td_env.ps1`, `tools\td\PATH_CONTRACT.md`, `tools\a1\pc_decode.py` | mandatory TD env / decode |

## 3. Decision basis

- b18 proved the DDR read path, PAXI mask/address shift, retry, v6 export and the A1 chain on a
  real 1080p frame with B. The only remaining variable is the camera tap.
- A was last measured on b13, whose bit had no PAXI fix and no retry; its `pix_beats=0` result is
  not conclusive for the b18 chain. b19 is the cheapest decisive test: one localparam.
- Both camera cores stay instantiated; only the selected branch changes. B code (tap, config,
  diagnostics) is retained byte-for-byte and remains observable in v6 (`cam_*` counters are the
  selected tap; the B (unselected) core is not reported).
- A no-pixel result is a hardware/front-end conclusion, not a reason to rebuild. Stop there.

## 4. Open items

1. A physical camera/sensor path is unproven; this run is the test (no user answer required).
2. Reset alignment is an operator action (board R14 `sys_rst_n`); record it. No extra download.
3. b18 has no integrated tester report; b19 gets its own new tester at round0. No rounds inherited.
