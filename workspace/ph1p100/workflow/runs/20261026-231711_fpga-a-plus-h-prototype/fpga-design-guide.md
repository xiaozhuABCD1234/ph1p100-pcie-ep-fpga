# FPGA design guide — A+H isolated prototype (frozen)

- run: `20261026-231711_fpga-a-plus-h-prototype`
- applies to: `T10.ah-honly` (P1, H only) and `T10.ah-a-plus-h` (P2, H+A), both offline RTL/simulation only.
- this guide freezes only the task-relevant items. The frozen upstream sources and their comments remain the authority for the block format and protocol; this guide does not re-invent them.
- **No TD, synthesis, place & route, bitgen, CWC, download, Flash, board, COM/JTAG, RK or network work in this run.** All resource/timing numbers below are estimates, never measurements.

## 1. Scope and non-goals

In scope: an isolated copy of the b11 single-stream 1920×1080 chain; change only the A1 compress core (and the internal core→frame_top transfer) to implement H, then A+H; run the frozen 4-frame N/L harness and the frozen b6 core bench; prove byte-identical A1U1/zlib output; measure S_ss / core_interval / cycles/B; report resource and critical-path risk as estimates.

Out of scope: TD/STA, bitstream, CWC, board, production `fpga/csi2/src/**`, `upstream/**` in place, integrated-delivery / chain-detail-review candidates, b18/b19/b20 candidates, tasks.json, docs/work/.agents, RK, dual stream, and any change to the external frame format.

## 2. Data and content contract (unchanged)

| item | frozen value |
|---|---|
| sensor/packing | RAW10 packed, 40-bit group = 4 pixels; b0..b3 = px[9:2], b4 = four 2-bit LSBs, b4[1:0] = pixel 0 |
| camera / ROI | CAM_W 3864, CAM_H 2192, ROI_X 972, ROI_Y 556, W 1920, H 1080 |
| Bayer | declared RGGB phase 0; 2-row pair → one transform block |
| block | ≤4800 B per block, 540 blocks per full frame, 2,592,000 transform bytes/frame |
| content | N = `raw40_n.hex`, L = `raw40_l.hex` (frozen P1 hashes); 518,400 groups each; `CONTENT=2` |
| pacing / sink | `PACING=0`, `SINK=1` (2 GHz UART clock, 2 clk_a1 per byte = 93.75 MB/s TB proxy), `CAPTURE=0` |
| prov | transform-domain bytes are the block stream; raw CRC/self-check is unchanged |

The content labels remain `natural_scene_image` / `low_light_natural_scene`, `proxy_not_natural_raw`, `not_sensor_raw`, `proxy_not_worst`, `display_referred`. This run does not claim sensor RAW, worst-case or full-content coverage.

## 3. Stream / format contract (unchanged, byte-exact)

- A1U1 44-byte little-endian header, `magic = "A1U1"`, `version=1`, `header_len=44`; fields at offsets 24 `stream_len`, 28 `raw_crc`, 32 `xform_crc`, 36 `stream_crc`, 40 `header_crc`; then exactly `stream_len` payload bytes.
- Payload: one standard zlib member (RFC1950) `0x78 0x9C`, DEFLATE subset BTYPE=01 (fixed Huffman) or BTYPE=00 (stored), no dynamic Huffman, no cross-block references, big-endian Adler-32 at the end. Block-level stored/fixed decision, candidate costing and early-abort rule are unchanged.
- Frame top output: 32-bit words, **low byte first**; `out_keep` marks the valid bytes of the last word; `out_last` marks the last word; `frame_commit`/`frame_abort` and CRC/length semantics are unchanged.
- The external UART byte stream, 32-bit word stream, header, CRC, length, tail byte and frame order must be **identical** to the frozen baseline. Any difference is a functional failure, not a "new format".

## 4. Clock / reset / geometry (unchanged)

- `clk_a1` 187.5 MHz (5.333 ns), `clk_cam` 187.5 MHz, `clk_ddr` 200 MHz; the existing bridge/CDC is unchanged.
- `rst_n` active-low, existing assertion/release behavior; no new CDC, no new clock domain, no PLL change.
- Geometry, block count, content and frame order are not parameterized in this run.

## 5. A and H — exact meaning and arithmetic targets

### 5.1 H (P1)

H = replay/emit widened to **2 stream bytes per cycle** (32-bit cmem replay port) plus the internal 2-byte core→frame_top transfer required to make that rate observable. Model delta `−1,215,597` cycles; expected 1-frame N `6,260,648` (2.4154 cycles/B, −0.17 % vs G0), L `5,888,933` (derived from the same `0.5·r·stream_fixed` formula; not a JSON matrix row). H alone is not expected to close N; it is the correctness/step toward A+H.

### 5.2 A (P2)

A = 2-position / 2-symbol literal scan with the **conservative literals-only** delta `−252,570` cycles (7,223,675 alone). The full-dual range down to 5,186,178 is not claimed. A must be an implementation of the **same sequential algorithm**, not a different matcher: same hash table contents, same candidate order, same match decisions, same literals/matches/aborts.

### 5.3 A+H (P2)

A+H = 6,008,078 cycles, 2.3179 cycles/B, +4.027 % arithmetic margin, envelope 45.034 % (3,970,580–7,223,675), `conditional`. The gate for this run is **N and L 4-frame S_ss ≤ 6,250,000** with byte-identical output. This is a prototype S_ss gate, **not** a G0 closure claim.

## 6. H interface / buffering / timing freeze

### 6.1 Core output port

The core gains a parameter `OUT_BYTES` (default **1**, for the frozen b6 bench) and an output `out_keep`:

| signal | direction | width | semantics |
|---|---|---|---|
| `out_data` | out | `8*OUT_BYTES` (8 or 16) | stream bytes, **low byte first**; in 16-bit mode `{byte1, byte0}` with byte0 = earlier stream byte |
| `out_valid` | out | 1 | output FIFO non-empty |
| `out_ready` | in | 1 | in 16-bit mode a `keep=1` transfer means **both** bytes are accepted in this cycle; partial acceptance is never allowed |
| `out_keep` | out | 1 | 0 = only the low byte is valid (1-byte transfer); 1 = both bytes valid (2-byte transfer); constant 0 in 8-bit mode |
| `out_last` | out | 1 | this transfer contains the last stream byte |

- The frozen b6 TB instantiates the core without `OUT_BYTES` (default 1) and leaves `out_keep` unconnected; the resulting missing-connection warning is acceptable, and the frozen output SHA must still match.
- In 16-bit mode, `out_ready` low holds **both** bytes and all sideband; no byte may be dropped or duplicated.
- `done`, `busy`, `stat_blocks/fixed/stored/literals/matches/cand_aborts/stall/max_match/max_dist` keep their existing meanings. New diagnostic counters (replay stall, FIFO occupancy, out_valid duty) are test-only and must not change the external behavior.

### 6.2 cmem and replay

- Candidate bitstream storage may be reorganized from 4096×16 to 2048×32 (same total bits) or kept 4096×16 with two read ports. The chosen structure must store the **same candidate bitstream bits** and produce the **same byte sequence**, including the last partial word.
- The replay must read 32 bits (4 stream bytes) per access where possible and emit 2 bytes/cycle in 16-bit mode; the last word may contain 0–4 valid stream bytes; the last transfer may be 1 byte (`keep=0`). `cand_bits`/`cand_nbytes` remain the authority for the exact byte count.
- The packer write path may use a 16-bit write-combine into the 32-bit cmem; the write path must never lose or reorder a 16-bit word. The aggregate write bandwidth must remain ≥16 bits/cycle for H and ≥18 bits/cycle for the A dual-symbol packer (see §7.3).
- The replay FSM may be restructured (e.g., a 2-byte beat with a FIFO), but the stream must be produced in the same order and the `S_TRAIL`/Adler/`S_DRAIN`/`done` sequence must remain equivalent.

### 6.3 frame_top adapter (2-byte transfers)

The frame_top keeps its external ports (32-bit `out_data`, `out_valid`, `out_ready`, `out_keep`, `out_last`, `frame_commit`, `frame_abort`, `st_*`, `dbg`). Internally it accepts 1- or 2-byte transfers from the core:

- `scnt` = byte index 0..3 in the current 32-bit word. A `keep=1` transfer writes `sdata[scnt] = out_data[7:0]` and `sdata[scnt+1] = out_data[15:8]`; a `keep=0` transfer writes only `sdata[scnt] = out_data[7:0]`.
- If `scnt == 3` and a `keep=1` transfer arrives, the low byte fills `sdata[3]`, the word completes (`svalid=1`, `skeep=4'hF`, `slast` from `out_last` only if this is the last byte), and the high byte is held in a **pending byte** register. `core_out_ready` is low until the pending byte can be written at `scnt=0` of the next word. No byte may be lost.
- `str_crc_r` is updated per byte in stream order; `slen_r` increments per byte; `svalid/skeep/slast` and the word content must equal the frozen frame_top for the same byte stream.
- The adapter must be unit-tested with even and odd stream lengths, `scnt=3` + `keep=1`, backpressure (`out_ready` low), and the last byte/`out_last` case. At minimum, one directed odd-length case must be added to the core bench.

### 6.4 Backpressure and buffering evidence

Record per run: replay cycles, replay stall cycles (waiting for cmem/out space), max output FIFO occupancy, `out_valid` duty, `core_out_ready` low cycles, and the frame_top word-assembly stalls. The expected 16-bit-port limit is 4 bytes per 3 cycles (0.75 cycles/B) once `svalid` inserts one stall per 32-bit word; the measured value decides. FIFO depth changes are allowed only if they do not change the stream; no unbounded buffering.

## 7. A equivalence freeze (P2)

### 7.1 Sequential semantics

- Positions are retired in ascending order. A hash lookup/insert at position p sees the table state after all positions < p. A match at p is taken before any decision at p+1; the scan resumes at p+len.
- The dual-position path may compute the pos+1 lookup/insert speculatively, but it must **squash** the pos+1 insert when pos is a hit (the sequential algorithm would not insert p+1). When pos is a literal and pos+1 is a hit, the table write for pos must be visible to the pos+1 decision; if that is not possible in one cycle, fall back to single issue for this pair.
- If `bucket(pos) == bucket(pos+1)` (or the two writes hit the same bank/port), fall back to single issue for this pair. The fallback is a correctness guard, not a performance failure; its frequency must be reported.
- Block boundaries (`lim2`, `s1_last`, end-of-block, abort, stored fallback, `cwptr > 2700`) must be handled exactly as the scalar sequence.

### 7.2 Counters and table state

`stat_literals`, `stat_matches`, `stat_cand_aborts`, `stat_max_match`, `stat_max_dist` must equal the baseline for the same content; `stat_blocks/fixed/stored` must also match. A mismatch is an equivalence failure even if the stream bytes happen to match.

### 7.3 Packer / write-bandwidth dependency

A literal-only dual issue halves the literal scan cycles only if the fixed-Huffman packer consumes **2 symbol codes/cycle** and the cmem write path sustains **≥18 bits/cycle** (two 9-bit codes) without stalling. The H cmem 32-bit write path is the intended enabler; if the packer cannot be widened, A's measured gain is capped by the 16-bit write port and A+H will likely miss 6.25 M. The dev must measure and report the actual packer/write stall; it must not assume the −252,570 delta.

### 7.4 Kill rule

If A cannot preserve §7.1–§7.2 in the available budget, or the measured gain is below the threshold needed for A+H, **kill A**, keep the H-only result and report `A_killed=true` with evidence. No approximate matcher, no relaxed equivalence, no output-changing "optimisation".

## 8. Byte-exact evidence contract

A run is byte-exact only if **all** of the following hold on the same frozen inputs:

1. **Core bench** (b6 vectors, 153,600 B each): comp output SHA-256 `2601d57c…a7c05` (50,310 B) and rand output SHA-256 `54f262f2…496dd` (153,766 B), byte-for-byte, with the 8-bit frozen TB and the 16-bit adapted TB. Cycles must not exceed the frozen 355,261 / 161,479 (they are expected to fall).
2. **Frame 1** (1-frame probe and 4-frame run): `stream_len`, `stream_crc`, `header_crc` must equal the P1 frozen values (N 1,677,912 / 1,168,876,019 / 657,705,490; L 2,156,868 / 1,770,220,292 / 2,924,387,436); the last payload byte and byte count must match the local frozen b11 baseline control (the P1 evidence did not store the last byte separately).
3. **Frames 2–4** (4-frame run): per-frame 44-byte header (`stream_len`, `stream_crc`, `header_crc`) must equal the local frozen b11 baseline control's headers, and the last payload byte and byte count must match that control.
4. **Counters**: blocks/fixed/stored/literals/matches/cand_aborts/max_match/max_dist equal the baseline for the same content.
5. **Protocol**: the external 32-bit word stream, `out_keep`, `out_last`, `frame_commit`, `stream_crc`, `slen` and the UART byte order are unchanged; the A1U1 header layout is unchanged.

The passive per-frame header capture is a testbench-only addition (detect the `A1U1` magic and store the next 44 bytes; track the last payload byte per frame). It must not change the DUT, clocks, pacing or sink. The baseline control and the prototype must use the same capture.

## 9. Measurement and metrics

| metric | definition | use |
|---|---|---|
| `S_ss` | `(S_23+S_34)/2`, `S_ab = t_exp(b) − t_exp(a)`; requires 4 `exp` events | **P2 gate ≤ 6,250,000** |
| `core_interval(k)` | `t_enc(k) − t_enc(k−1)`, k≥2; frame 1 from the 1-frame probe (`t_enc(1) − t_pub(1)`) | cycles/B, bottleneck |
| `cycles/B` | `core_interval / 2,592,000` | H/A/H+A throughput |
| `tail(k)` | `t_exp(k) − t_enc(k)`; mean over k=2..4 | diagnostic |
| `tail_frac` | `tail_mean / S_ss`; ≥0.50 is a **diagnostic flag only** | reported, not a gate |
| `busy` | `export_time_mean / S_ss`; `export_time = 2 × bytes(k)` | P4 blocking rule ≥0.95; report |
| `margin` | `6,250,000 / S_ss − 1` | gate margin |
| `dup` | adjacent bit-identical 256-bit raw words (content statistic) | report; not a performance gate |

- **Timeout / stall / frame loss**: `SS_STALL`, `SS_STALL_COLD`, `B11_FULL_TIMEOUT` before the final stats, or fewer than 4 `exp` events ⇒ **partial/not_proven**. A 2- or 3-frame result must never be reported as a 4-frame S_ss; no extrapolation.
- The 1-frame probe's `B11_FULL_TIMEOUT` after the export is a harness artifact (the TB runs to `MAX_CYCLES`); it is acceptable only if the `CORE_STAGE` line is present, `cap=enc=exported=1`, `read=129,600`, and there is no `SS_STALL`/`SS_STALL_COLD`.
- `ss_pass=0` is expected on natural content because the frozen TB's `dup=0` clause fails; it is not the performance gate (see input-index §6.3). The run must still require cap=enc=exported=4, read=518,400, raw_drop=cmp_drop=geom=err=0, wd=0.

## 10. Resource / critical-path estimate contract (no TD)

- Budget: 300 ERAM / 71,680 LUT6 / 143,360 REG (PH1P100; from the frozen budget context).
- H estimate: +0 ERAM (2048×32 vs 4096×16 is the same bits), +300..800 LUT6, +200..500 REG; frame_top adapter +50..150 LUT6, +40..120 REG. Combined H +350..950 LUT6, +240..620 REG, 0 ERAM.
- A estimate (P2): +2..4 ERAM (dual-port/banked htab), +3,500..6,000 LUT6, +1,500..2,500 REG.
- A+H estimate: +2..4 ERAM, +3.8k..6.8k LUT6, +1.7k..3k REG.
- Timing risk: b11 routed WNS at 187.5 MHz is only +0.015 ns (P4). H is a separate replay FSM → medium risk. A puts a second hash lookup, a match arbiter and a dual-symbol packer into the scan cone → **high** risk. No TD/STA this run; the report must say "estimate only, not a TD result", and must list the paths that would need STA.
- Resource estimate basis must be shown (array sizes, port widths, mux/adder widths); no fabricated TD numbers.

## 11. Work dirs, build entry, isolation, timeouts

- Task dirs: `.../T10.ah-honly/r0/{src,changed-src,sim,out}` and `.../T10.ah-a-plus-h/r0/{src,changed-src,sim,out}`.
- `src/` = frozen copies (never edited in place). `changed-src/` = the A/H DUT edits. `sim/` = `modelsim.ini`, work libs, logs, caps, commands. `out/` = JSON/MD results.
- ModelSim scratch: `C:/Users/czz/AppData/Local/Temp/opencode/a-plus-h/<task>/<build>/` with its own `modelsim.ini`, `work`, logs. One task/build per library; no sharing across tasks.
- Build entry: `vlib` + `vlog` of the 12 DUT + the chosen TB; `vsim -c -lib work <tb>` with the frozen plusargs:
  - 4-frame: `+STAT= +EVT= +HDR= +RAW40= -gFRAMES=4 -gCONTENT=2 -gPACING=0 -gSINK=1 -gCAPTURE=0 -gMAX_CYCLES=60000000 -do "run -all; quit -f"`.
  - 1-frame probe: same with `-gFRAMES=1 -gMAX_CYCLES=13300000`, TB `tb_ss_4run` from `tb_ss_4run_wd_probe.v`.
  - bench: `+IN= +META= +OUT= +STAT= +BP=0 +GAP=0 +TIMEOUT=2000000`.
- Timeouts: each 4-frame run ≤2,700 s; each probe ≤1,200 s (P1 uses 900 s, P2 uses 1,200 s); each bench ≤300 s (P1 ≤4 runs / P2 ≤2 runs); all commands must have a real timeout/kill mechanism. `yield` is not a timeout.
- Logs must retain the exact command, rc, wall time, `SS_META`, `SS_EVT`, `SS_STATS`, `SS_RAW_MATCH`, `CORE_STAGE` (probe) and the final `B11_FULL_RESULT`.

## 12. G layers and three-dimension boundaries

| layer | this run | reason |
|---|---|---|
| G0 | **P2 only** (S_ss ≤6.25 M); P1 n/a | P1 is a correctness/cycles probe, not the 4-frame gate; no G0 claim |
| G1 | **P1 and P2** | manifest hash, frozen inputs, byte-exact evidence, reproducible commands |
| G2 | not applicable | 0 synthesis/place & route/timing/resource measurement; estimates only |
| G3 | not applicable | 0 bitgen/CWC/download/Flash |
| G4 | not applicable | 0 board/real interface/stability measurement |

- functional: byte-exact (bench + per-frame header/last byte/length), counters, 4 frames, no stall/timeout, S_ss (P2).
- engineering: manifest 100 % hash, frozen copies unchanged, DUT diff scope, isolated ModelSim libs, resource estimate sanity, no TD claims, no writes outside scope.
- system: external protocol/geometry/clock/reset/content/packing unchanged, 32-bit word stream and A1U1 header unchanged, sink/pacing unchanged, scope/limitations stated.

## 13. Frozen / pending / not applicable

**Frozen now**: content hashes; baseline S_ss and frame-1 core intervals; byte-exact baseline values; H/A definitions and arithmetic targets; H interface (16-bit internal transfer, 2 B/cycle replay); A equivalence rules and kill rule; metrics and gate; resource/timing estimate contract; work dirs and build plusargs; G layers.

**Pending (evidence, not design choices)**: measured H cycles/B and byte-exact result; measured A gain and equivalence; measured A+H S_ss; actual per-frame CRCs for frames 2–4 (from the baseline control); actual replay/FIFO/backpressure counters; actual resource estimate table.

**Not applicable this run**: TD/STA/resources, bitgen/CWC/download/Flash, board/COM/JTAG/RK/network, dual stream, production sink, sensor RAW/worst content, G0 system closure claim.

## 14. Write scope

Allowed: `D:/fpga/ph1p100/workflow/runs/20261026-231711_fpga-a-plus-h-prototype/**` (task dirs, test-reports, plan updates) and `C:/Users/czz/AppData/Local/Temp/opencode/a-plus-h/**`. Everything else is read-only, including the protected list in `input-index.md §7`. No batch deletion; delete at most one explicit file at a time and only if unavoidable.
