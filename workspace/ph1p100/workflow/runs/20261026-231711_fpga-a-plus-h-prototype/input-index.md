# Input index — A+H isolated RTL prototype

- run: `20261026-231711_fpga-a-plus-h-prototype`
- project root: `D:/fpga/ph1p100`
- output dir: `D:/fpga/ph1p100/workflow/runs/20261026-231711_fpga-a-plus-h-prototype`
- user request (verbatim + background): `D:/fpga/ph1p100/workflow/runs/20261026-231711_fpga-a-plus-h-prototype/request.md`
- planner inputs: root `AGENTS.md`, `.agents/skills/fpga-planner/SKILL.md`, `.agents/skills/fpga-design-guide/SKILL.md`, `.agents/skills/fpga-orchestrator/references/work-limits.md`, `relay-contract.md`, `project-context.md`
- created: 2026-10-26; authority: current user request + latest evidence below. No older route is revived.

## 0. One-paragraph reading

The previous run `20261026-143924_fpga-1080p30-g0-production` closed at run headline `G0_not_closed`: natural content **N** measured S_ss = 7,475,240 cycles (25.08 fps, −16.39 % vs G0), low-light **L** measured S_ss = 6,986,952 cycles (26.84 fps, −10.55 %), both bottlenecked by `core_interval`. Its P2 core-gap model says the only 187.5 MHz arithmetic combination is **A+H = 6,008,078 cycles (2.3179 cycles/B, +4.027 %)** but with a **45.034 %** scheme envelope, so it is `conditional`, not a closure and not implemented. **H alone** is 6,260,648 cycles (2.4154 cycles/B, −0.17 % short); A alone is 7,223,675. This run builds only an **isolated RTL/simulation prototype**, H first and then A+H, with byte-identical A1U1/zlib output. No TD, synthesis, place & route, bitgen, CWC, download, Flash, board, COM/JTAG, RK or network work is authorised.

## 1. Frozen definitions of A and H (source: P2 `coregap-model/verdict`)

- **A**: 2-position / 2-symbol literal scan. The P2 matrix row A has a literals-only delta `−252,570` cycles (7,223,675) and a full-dual range down to 5,186,178; **this run adopts the conservative literals-only A delta (−252,570)**, which is the value used in the A+H combination. A is not "any matcher change"; it must implement the *same* sequential symbol sequence, only issuing/retiring two literal positions per cycle.
- **H**: emit/replay widened to 2 stream bytes/cycle (32-bit cmem replay port). Delta `−1,215,597` cycles → 6,260,648 (2.4154 cycles/B, −0.17 % vs G0).
- **A+H**: 6,008,078 cycles, 2.3179 cycles/B, +4.027 % margin, arithmetic-only, `conditional`; envelope 3,970,580–7,223,675 = 45.034 %. Not a closure, not implemented, no TD/STA.
- The model's H delta is `0.5 × r × stream_fixed` with `r = 1.9007` and `stream_fixed(N) = 1,279,097` B, `stream_fixed(L) = 1,147,818` B. Derived H probes: N 6,260,648; L 5,888,933 (L is not a row in the JSON; it is recomputed from the same formula and must be labelled derived).
- A/H must not change geometry, clock, reset, content, external packing or protocol. The core→frame_top path may be widened internally (see design guide §4) because a true 2 B/cycle emit is impossible on the frozen 8-bit core output; the **external** 32-bit word stream, A1U1 header, CRCs, lengths and UART byte order must be bit-identical.

## 2. Measured baselines and gate

| item | N | L | source |
|---|---:|---:|---|
| 4-frame S_ss (cycles) | 7,475,240 | 6,986,952 | `T10.ss-g0-prod-content/r0/out/content-verdict-r1.json` |
| frame-1 `core_interval` = t_enc(1) − t_pub(1) | 7,476,245 | 6,979,811 | `T10.ss-g0-prod-coregap/r0/out/stage-probe.json` |
| fixed blocks / stored blocks (1 frame) | 457 / 83 | 330 / 210 | same |
| literals / matches / candidate aborts | 505,140 / 397,627 / 83 | 673,657 / 254,493 / 210 | same |
| stream bytes frame 1 | 1,677,912 | 2,156,868 | P1 verdict |
| stream bytes frames 2–4 | 1,677,336 | 2,156,300 | P1 verdict |
| export tail mean (cycles) | 3,354,764 | 4,312,692 | P1 verdict |
| tail_frac (diagnostic flag ≥0.50) | 44.88 % | 61.72 % | P1/P4 |
| busy = export_time/S_ss (blocking rule ≥0.95) | 44.88 % | 61.72 % | P4 clarification |
| G0 gate | 6,250,000 | 6,250,000 | 187.5 MHz, 2,592,000 B/frame, 30 fps |
| target cycles/B | 2.411265 | 2.411265 | 6,250,000 / 2,592,000 |
| P1 run wall | 1,962.4 s | 1,802.0 s | `content-verdict-r1.json#/run.seconds` |
| 1-frame probe wall | 612 s | 788 s | `coregap/r0/sim/commands.jsonl` |

- `S_ss = (S_23 + S_34)/2`, `S_ab = t_exp(b) − t_exp(a)`.
- P4 clarified that `tail_frac ≥ 0.50` is a **diagnostic flag**, and the blocking rule for `G0_not_proven` is `busy = export_time/S_ss ≥ 0.95`. At the A+H target (~6.0 M) busy is ~0.56 (N) / ~0.72 (L), both < 0.95. **Nevertheless this run reports S_ss only and does not claim G0 closure**; G0 re-verdict is a separate package.

## 3. Byte-identical baseline evidence available now

A1U1 header is a frozen 44-byte little-endian packet (`a1_uart_export.v` header comment): offset 24 `stream_len`, 28 `raw_crc`, 32 `xform_crc`, 36 `stream_crc`, 40 `header_crc`; then `stream_len` payload bytes.

| frame-1 field | N | L |
|---|---:|---:|
| stream_len | 1,677,912 | 2,156,868 |
| stream_crc | 1,168,876,019 | 1,770,220,292 |
| header_crc | 657,705,490 | 2,924,387,436 |
| raw_crc | 3,665,401,424 (0xDA799650) | 707,927,594 (0x2A321E2A) |

- Frozen b6 core bench (byte-exact reference on two 153,600 B vectors): comp output 50,310 B SHA-256 `2601d57cd98d1fe69b2e46fe8423779a5d44bd14c00e1fe2d5faab6ff15a7c05`, 355,261 cycles; rand output 153,766 B SHA-256 `54f262f2a600a3e2f12129f2937a390737d1ec8018d8f0236979e604760496dd`, 161,479 cycles.
- The P1 4-frame runs used `CAPTURE=0` and only dumped the first 256 exported bytes, so **frames 2–4 CRCs are not in the frozen P1 evidence**. This run must re-run the frozen b11 baseline 4-frame for N and L with a passive per-frame 44-byte header capture, and must reproduce S_ss and frame-1 core_interval exactly. That local control is the frames 2–4 baseline. If it does not reproduce exactly, it is a control failure, not a new baseline.

## 4. RTL / TB / content inputs (read-only; copy into this run before use)

- P1 frozen package: `D:/fpga/ph1p100/workflow/runs/20261026-143924_fpga-1080p30-g0-production/T10.ss-g0-prod-content/r0/`
  - `manifest-r1.json` SHA-256 `e306ed42ed47dbcec6127bf2faee88925a9a88ae8a5ef07ecbda8dda91fe1fd9`, 70 artifacts (r0 report's "40" is a known typo corrected by P2 R9).
  - `out/content-verdict-r1.json`; `content/raw40_n.hex` SHA-256 `e44fe7bc89aaa3ada2422a41fcfb8e283d5f66cdffda29b2caf4da10d2cd7b53`; `content/raw40_l.hex` SHA-256 `e7e3c21cd2e4cc18e115b4cf18692596450cfcfc7605297046e3840c67deefa2` (each 5,702,400 B = 518,400 × 40-bit groups).
  - `src/` 12 DUT + `tb_ss_4run.v` + `tb_ss_4run_wd.v` (`tb_ss_4run_wd.v` SHA-256 `785c3ef1d044f8529b7232ae37ed3a67172b6c4cd512c47a713103675090b79a`).
  - 12 DUT list: `a1_ddr_arb2.v`, `a1_ddr_model.v`, `a1_ddr_slot_store.v`, `a1_deflate_core.v`, `a1_frame_top.v`, `a1_raw_crop.v`, `a1_uart_export.v`, `camera_a1_uart_top.v`, `cam_diag_mailbox.v`, `capture_async_fifo.v`, `p2_ddr_bridge.v`, `p2_paxi_model_b11.v`.
- P2 frozen package: `.../T10.ss-g0-prod-coregap/r0/`
  - `manifest-r1.json` SHA-256 `803d3efb0104376004eb46c2b633d9b19577ba746190edadea802f81e3b92a66`, 49 artifacts.
  - `out/coregap-model.json`, `out/coregap-verdict.json`, `out/stage-probe.json`, `model/assumptions.json`, `model/coregap_model.py`.
  - `src/tb_ss_4run_wd_probe.v` (1-frame probe TB with `CORE_STAGE` counters), `src/DIFF-probe.md/.raw`.
  - `sim/caps/{n,l}-probe.{evt,hdr}` and `sim/logs/{n,l}-probe.log` (measured anchors; the 1-frame probe core_interval exactly matched P1 frame 1).
- Current b11 core / frame top: `D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b11-aplus-read/r0/changed-src/a1_deflate_core.v` SHA-256 `a91c2ed82fbef654c4e065b64ae1cc268ca232feaa26fdd313c58d8740f81b3e` (80,501 B); `a1_frame_top.v` SHA-256 `0064607aceb20ae3ef14133f0aaf5f8b3f489943011a66a1ddc005350dba7109` (25,654 B); candidate manifest `CANDIDATE-MANIFEST-b11-aplus-read-r0.json`; full TB `sim/tb_b11_full.v` SHA-256 `e278cea5ad49d05a2cdddb2c27ed0b6353774cfa7a4a495b7366f917754ac699`.
- b6 baseline core / bench: `.../T10.b6-a1-htab-nw/r0/changed-src/a1_deflate_core.v` SHA-256 `6797db053cfc47497540d6345e3a46b7e79cc1d34fa25da5a4c501505fbf35bb` (80,196 B); integrated report `.../test-reports/T10.b6-a1-htab-nw-r0-integrated.md` (PASS); bench TB `D:/fpga/ph1p100/upstream/ph1p100-pcie-ep-fpga/sim/tb/codec/tb_a1_deflate_core.v` SHA-256 `910aea54e0d8d40a02a7d5e7844b053fff1f86e24cbfc43d1c33f083da5af09e`; vectors `D:/fpga/ph1p100/work/parallel-sim-20261024-2204/codec-throughput/{comp,rand}/in.{hex,meta,xform}` (read-only; copy in).
- P4 verdict: `.../T10.ss-g0-prod-verdict/r0/g0-production-verdict.json` SHA-256 `4f98a48f834d6df5a8a294e59d75b2d39819e275296f67ed00058b5fa7342ff7`; `manifest-r0.json` SHA-256 `8460fb8da43a2e21a9b39074bf99815d445a82852874100df1a97aad3a5a7a28`.

## 5. Tools / environment

- ModelSim Intel FPGA Edition 10.5b: `D:/intelFPGA/18.1/modelsim_ase/win32aloem/{vlib,vlog,vsim}.exe` (existence checked; the `vsim.exe` path is present). Every task/build uses its own `work` library, `modelsim.ini` and log. Scratch under `C:/Users/czz/AppData/Local/Temp/opencode/a-plus-h/<task>/`.
- Python 3.11.5 (hash / JSON / log parsing only), PowerShell `Get-FileHash`, git `diff --no-index`.
- TD install exists at `D:/anlogic/TD_Release_2026.2` but is **not used** (0 TD this run).
- No board, COM, JTAG, Flash, RK or network access is authorised.

## 6. Resolved conflicts / decisions

1. **b11 hash**: the request wrote "`6797db05…35bb?`" for the b11 core. That SHA is actually the **b6** core. The b11 core is `a91c2ed8…f81b3e` per its candidate manifest. This run uses `a91c2ed8…` for b11 and `6797db05…` only as the b6 bench baseline. Resolved; no user input needed.
2. **4-frame wall**: request says "~22 min"; measured P1 runs were 1,962.4 s (N) and 1,802.0 s (L). Freeze 2,700 s per 4-frame run (5,400 s for the two baseline 4-frame runs), 900 s per P1 probe, 120 min total full/probe ModelSim wall; use measured values.
3. **`ss_pass=0`**: the frozen TB's `dup=0` clause fails on natural content (N 3,896 / L 568 adjacent identical raw words). P4 clarified `dup` is a content statistic, not duplicate DDR traffic, and the blocking rule is `busy ≥ 0.95`. This run records `dup` and both rules but **does not use `ss_pass` as the performance gate**; it does require cap=enc=exported=4, read=518,400, raw_drop=cmp_drop=geom=err=0, wd=0, no SS_STALL/SS_STALL_COLD/B11_FULL_TIMEOUT before the final stats.
4. **`tail_frac ≥ 0.50`**: kept as a diagnostic flag only; the run reports it but does not turn it into a G0 pass/fail. The S_ss gate is the prototype gate.
5. **H model vs 8-bit port**: the frozen core output is 8-bit and frame_top's `core_out_ready = !svalid` accepts 4 bytes per 5 cycles (0.8 B/cycle), so a pure 8-bit H cannot reach the modelled 1 cycle/B; H must include the internal 16-bit core→frame_top transfer (external 32-bit packing unchanged). This is an internal interface change, frozen in the design guide §4, not a change to the external protocol.
6. **A definitions**: P2's A row has a literals-only delta and a full-dual range. This run adopts the conservative literals-only target (−252,570) and does not claim the full-dual 5.19 M number. A is a required part of P2, but if A cannot be made byte-exact it is killed and H-only is reported.
7. **Parent task**: `workflow/tasks.json` T10 remains active/blocked; this offline prototype does not set it done and does not change its state.

## 7. Read-only / protected (no writes)

`workflow/runs/20261026-2138_fpga-integrated-delivery/**`, `workflow/runs/20261026-144617_fpga-chain-detail-review/**`, b18/b19/b20 task dirs, old P1–P4 frozen dirs (all under `20261026-143924_fpga-1080p30-g0-production` and `20261020-0209_singleA_aplus_closedloop`), `fpga/csi2/src/**`, `upstream/**`, `D:/TD/work/csi2/**`, `D:/fpga_work/**`, `workflow/tasks.json`, `docs/**`, `work/**`, `.agents/**`, and all other runs. Reads/copies into this run are allowed; in-place edits are not. No batch deletion; one explicit file at a time only if ever needed (and prefer not deleting at all).

## 8. Adopted version set

- Content: P1 manifest-r1 (`e306ed42…`) + `raw40_{n,l}.hex` hashes above.
- Core/frame baseline: b11 `a91c2ed8…` / `0064607a…` + P1 `tb_ss_4run_wd.v` + P2 probe TB.
- Bench baseline: b6 `6797db05…` + `tb_a1_deflate_core.v` `910aea54…` + `work/.../codec-throughput` vectors.
- Model/verdict: P2 manifest-r1 (`803d3efb…`), P4 verdict (`4f98a48f…`).
- Not adopted: any active candidate from the integrated-delivery or chain-detail-review runs; any TD/bitstream from b18/b19/b20; any production source.

## 9. Unresolved / pending

- **None blocking.** TD/timing/resource qualification is explicitly deferred to a later package after a simulation PASS and a separate user authorization.
- The exact H measured cycles/B and the exact A gain are **unknown until P1/P2 run**; all numbers in this plan are model expectations, not measurements.
