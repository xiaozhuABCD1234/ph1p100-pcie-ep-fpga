# input-index -- T10.b20-a-timing

Exact paths and versions this package consumes. All b19/b18/b13 trees are **read-only** inputs.

## 1. Requirement and decision

| item | source |
|---|---|
| user decision (2026-10-26) | "尝试修 A"; freeze `T10.b20-a-timing`; only `a1_frame_top.v` abort->smem address path, +1 pipeline/register, cycle-neutral, no frame/CRC/protocol change, aborted data may be dropped, +1 cycle abort latency accepted |
| baseline | b19 changed-src (CAM_SEL=0, PAXI x8/mask=0, retry/R1, v6), SDC `0888b6a7...` |
| budgets | dev 100 min/55 calls; TD 3 sessions; synth <=2; route 1; bitgen 1; CWC 1; download 1 |

## 2. b19 evidence (FAIL at route, the reason for this package)

| item | path |
|---|---|
| developer result | `D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b19-cam-a\r0\result-r0.md` |
| routed STA | `...\T10.b19-cam-a\r0\td\routed_timing.rpt` (worst path L105-185), `routed_timing_status.rpt`, `routed_qor.rpt` |
| synthesis | `...\T10.b19-cam-a\r0\td\syn_gate_timing.rpt`, `syn_gate_area.rpt` |
| build console | `...\T10.b19-cam-a\r0\td\build_console_r0.log`, `run_build_b19.out`, `td_20261026_200955.log` |
| constraint diagnosis | `...\T10.b19-cam-a\r0\diag\build-constraint-finding.md`, `td\p2_board-b19.diff.txt`, `td\sdc-hashes.txt` |
| lessons | `...\T10.b19-cam-a\r0\lessons-r0.md` (L8 = this timing gap, L9 = gate rule) |
| manifest | `...\T10.b19-cam-a\CANDIDATE-MANIFEST-b19-cam-a-r0.json` |
| conformance checker | `...\T10.b19-cam-a\r0\check_merge_b19.py`, `r0\merge-conformance-r0.txt` |
| sim evidence | `...\T10.b19-cam-a\r0\sim\sim-results-b19-{chain,p1,native,status,camsel}.json` + `logs\` |
| board scripts (unused, ready) | `...\T10.b19-cam-a\r0\board\{run_board_b19.ps1,check_b19_board.py,parse_status_v6.py,dl_b19_r0.tcl,gate-selftest-b18\}` |

## 3. Frozen candidate inputs (copy from b19, do not edit)

`...\T10.b19-cam-a\r0\changed-src\` — SHA256:

| file | sha256 |
|---|---|
| `a1_ddr_arb2.v` | `b84019bda057afe82ff558e0848d6171fa12732bd8cdb7c6239cb71b3f81d6ba` |
| `a1_ddr_slot_store.v` | `6c619cf90e54385d667f1ec0f63cc87ee58aadd3c42143330ac4945eb47defe9` |
| `a1_deflate_core.v` | `a91c2ed82fbef654c4e065b64ae1cc268ca232feaa26fdd313c58d8740f81b3e` |
| `a1_frame_top.v` (baseline, to be changed) | `0064607aceb20ae3ef14133f0aaf5f8b3f489943011a66a1ddc005350dba7109` |
| `a1_raw_crop.v` | `33a6fee77fd1aa67a31cacf26dd5530e5e2ea474ee655cbd5f1d98d887c5d72d` |
| `a1_uart_export.v` | `b3d61597534aa0609c53634313e4d14f222839f8b9b8ed83afc140daa04c298d` |
| `camera_a1_uart_top.v` | `73d10388c4a802421563b5b4c66f9cc37d600e7ec49fc0fa94b3d3ea0cbd3ff2` |
| `cam_diag_mailbox.v` | `352af7c85094ea99b575e99da952af8d33871352140e4c6efddff9e6c2407278` |
| `f9p_camera_display_core.v` | `e17206fb2e15f7590ee55c2ccc072677356ab2cb8efa41fd95ad6d52ab080760` |
| `p2_a1_board_top.v` (CAM_SEL=0) | `b08438e82adcb82726e6632a765e4ac134caea3bb79e0c0a3468274c135981d0` |
| `p2_ddr_bridge.v` | `790d8226ec69499c87b92b0e4a05ac0f26915f57b96bd541affdcdac8e740a61` |

| constraint | path | sha256 |
|---|---|---|
| SDC | `...\T10.b19-cam-a\r0\td\p2_board.sdc` | `0888b6a705a039a6cbabebacf323244a36257b5f29fb51bab7d81ef003220f5e` |
| ADC | `...\T10.b19-cam-a\r0\td\board_p2.adc` | `1cb30346fa17da6bb0e77802ca72c4b4bb4aecc1445711e19391cf4ee2271580` |
| build scripts | `...\T10.b19-cam-a\r0\td\{01_build.tcl,02_bitgen.tcl,03_cwc.tcl,a1_board.al,run_build_b19.ps1,run_bitgen_cwc_b19.ps1}` | copies, paths only |
| TD project tree | `...\T10.b19-cam-a\r0\td\src\` (332 files, 3,402,767 B, keeps `*.v.stale`) | copy as-is |

## 4. Simulation inputs

- TB/scripts: `...\T10.b19-cam-a\r0\sim\` (`tb_b17_chain.sv`, `tb_b17_paxi_native.sv`,
  `tb_b19_status_v6.v`, `tb_b19_camsel.sv`, `tb_p1_chain.v`, `a1_ddr_model.v`,
  `p2_paxi_model_b17.v`, `gen_stubs_b19.py`, `check_b19.py`, `run_b19.py`, `stub\`, `caps\`).
- Baselines/expectations: `...\T10.b19-cam-a\r0\sim\sim-results-b19-*.json`; P1 goldens
  `fa513a2b...edef` (micro8x2), `ee61e620...9789` (mid64x8), `b992a8ad...dada9` (full_grad).
- Reference design (unchanged modules): `D:\fpga\ph1p100\upstream\ph1p100-pcie-ep-fpga`,
  `D:\fpga\ph1p100\fpga\csi2\src\mem\capture_async_fifo.v`.
- Decode tool: `D:\fpga\ph1p100\tools\a1\pc_decode.py`.

## 5. Board inputs

- `...\T10.b19-cam-a\r0\board\*` (copy; adapt paths, `-Secs 300`, `dl_b20_r0.tcl`, `B20_DL_OK`,
  `captures_a`); `check_b19_board.py` is the validated gate basis (tail-cut fix, lesson L3).
- Negative-control capture: `...\T10.b18-b17-b\r0\board\captures_full\com8_300s.bin`
  (B camera, `camsel_bit12=1`) — the b20 gate must reject it.
- Environment: FTDI `VID_0403&PID_6042`, `COM8`; TD `D:\anlogic\TD_Release_2026.2`.
- Operator: one R14 (`sys_rst_n`) pulse **after** the single download, **before** COM8 opens.

## 6. Versions / open items

- Adopted: b19 RTL/PAXI/v6/retry chain, b19 SDC (approved B-group removal), b17 r1 ADC, b19 sim set.
- Open: whether one pipeline stage is enough for `WNS >= +0.05`; whether A produces pixels on this
  chain (never downloaded before); b19 is FAIL and its route budget is spent — b20 has its own.
- Not in scope: B camera, dual-cam, RK/PCIe, DDR IP regeneration, G4 long-run, Flash, docs updates.
