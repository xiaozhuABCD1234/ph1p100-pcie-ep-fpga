# T11.BRD.P1 — round 3 result (r3 minimal merge, local scope)

## 0. Inherited facts (frozen; not rewritten)

- r2 integrated verdict: local G1 PASS (`CHECKS=150 FAILS=0 VERIFY_R2=PASS`), r2 manifest
  `BD2B983F4734DA06211FF973B4165E043FD94A09D023A896E4846821AC037B4B` unchanged.
- r0g export verdict: **blocked** (`T11.export-arm-sim:SCOPE_CLARIFICATION:store-pusher-beat-order`),
  manifest-r0g unchanged. r0g's T03 store oracle was PASS; its "payload reversed" observation
  was traced in r3 to the **TB payload decode**, not the DUT (see §2).
- User decision `docs/DECISION_r0g_20261027.md`: LSB-first slot byte order; word ×32 total;
  pusher mapping to be decided by a small TB, not guessed.
- **Local boundary**: RTL simulation, software/byte checks, static checks, evidence only.
  **No TD synthesis, route, STA, bitgen, CWC, JTAG/COM, download or Flash** was run (0 times).
  `G2p = teammate_required` (`not_run`), `G3/G4 = awaiting_hardware`.

## 1. What changed in round 3 (RTL semantic delta = 2 files)

| file | change |
|---|---|
| `rtl/brd_cdc_mailboxes.v` | `brd_ack_xing`: `o_ack_seq <= out_bus[63:32]; o_ack_session <= out_bus[31:0];` (r0d ACK-slice fix; `in_bus = {cancel, ack_seq, ack_session}`) |
| `rtl/brd_board_datapath.v` | reset `a_seq/b_seq` to `32'd1` (r0d capture identity starts at 1); release polarity kept (`rel_camera_id=0→A, 1→B`); C8/C9 and `+SLOT_BASE_WORD` kept; slot base `×32` kept |
| `rtl/ref/ep_side/ddr/ddr_frame_pusher.v` | **comment only** above `data_beat`: the T03 A/B/C mapping experiment; `bswap256` unchanged |

Not adopted from the export working copy: `BASE_WORD=SLOT_BASE_WORD`, pusher base `×128`,
`p2_ddr_bridge` `×32`, internal `utx_sel` grant (would double-drive the EP engine in
`brd_integrated_top`), removal of `brd_export_seq`.

Unchanged and verified byte-identical to r2: `a1_ddr_slot_store.v`, `a1_deflate_core.v`,
`a1_frame_top.v`, `a1_ddr_arb2.v`, P4 RTL, `brd_integrated_top.v`, `brd_cam_fe.v`,
`brd_ddr_rd_arb.v`, `brd_a1_core_pll.v`, `brd_export_seq.v`, `a1_raw_crop.v`,
`p2_ddr_bridge.v`, `constraints/**`, the 78-source set.

## 2. A — T03 70 B oracle (store + pusher)

`tb/tb_t03_pusher_map.v` writes the frozen T03 stream through `a1_ddr_slot_store` at word 2048
(byte `0x1_0000`), reads it back, then arms `ddr_frame_pusher` on the same memory and decodes the
TLP payload with the project host model (lane 7→0, MSB first inside a DW — the `push_beat()` of
`sim/tb/tb_ddr_frame_pusher_rka1.v`, `sim/tb/tb_t11_r10f_e2e.v`, `sim_do/tb_ddr_frame_pusher.v`).

```
PRODUCED_LEN=70 FROZEN_LEN=70 BYTE_DIFF=0
FIRST8_PRODUCED=78 9C 62 48 4A 4A 5A 01
FIRST8_FROZEN  =78 9C 62 48 4A 4A 5A 01
PUSHER_LEN=70 PUSHER_BYTE_DIFF=0 PUSHER_FIRST8=78 9C 62 48 4A 4A 5A 01
```

Mapping candidates from the same captured beats (no RTL edit for the test):

| candidate | FIRST8 | BYTE_DIFF |
|---|---|---|
| **A = current `bswap256`** | `78 9C 62 48 4A 4A 5A 01` | **0 / 70** |
| B = no bswap | `02 C2 02 40 2D 0C 79 C4` | 69 / 70 |
| C = DW-order only | `40 02 C2 02 C4 79 0C 2D` | 67 / 70 |

Conclusion: the current mapping is the only one that matches the oracle; the pusher is **not**
changed. r0g's `ad 72 8d 72` is reproduced by the legacy decode (`+HOST_MODEL=1`:
mismatch 3830/3845) and disappears with the documented decode (mismatch 0). The r0g result is
not overwritten; it remains bound to its own TB/manifest.

## 3. B — address unit

```
AWDBG (store)  addr=00010000  (word 2048 x32)
ARDBG (pusher) addr=00010000  (first AR)
0x40000 seen = 0
```

- store AW word = 2048 → byte `0x1_0000`; pusher AR first = `0x1_0000`.
- `0x4_0000` never appears; the export `×32 + ×4 = ×128` path is not present.
- bridge stays `×8` (`{wf_rdata[279:256],3'b000}` / `{af_rdata[23:0],3'b000}`); board remap `×4`.

## 4. C — r2 G1 six scenarios on r3 (ModelSim ASE 10.5b, 64×48)

| scenario | result |
|---|---|
| SCEN0 late ARM, bypass | **PASS**: exported=1, 32 MWr × 128 B = 4096 B, doorbell=1, slot `0x1_0000` starts `78 9c`, base 0 unused, 0 TLP mismatch, correct ACK → release+1 |
| SCEN3 early ARM (doubled) | **PASS**, identical slot stream |
| SCEN4 duplicate ARM while armed/held | **PASS**, `arm_ignored ≥ 1`, one export |
| SCEN1 missing EOF | **PASS negative**: committed=0 published=0 exported=0, 0 TLP, 0 doorbell, aborted + released |
| SCEN2 wrong ACK → correct ACK | **PASS negative**: `held_seq^1` holds; correct `held_seq` releases |
| `prep` PREP=1/PRED=1 | **PASS**: 32 MWr/4096 B, standard zlib decodes 3840 B, header/transport OK |
| `tb_brd_arb` | **PASS 6/6** |

`verify_slot_r3.py`: **CHECKS=150 FAILS=0 VERIFY_R3=PASS**. Independent byte criterion:
`zlib.decompress(slot) == expected_raw.bin` byte-for-byte in 3/3 bypass scenarios.
PREP substitute criteria (documented in `evidence/golden-r3.md`): zlib decode, length = xform_len,
Adler `5F1669E1`, `raw_crc=7269454A`, `xform_crc=7883ABAF ≠ raw_crc`.

## 5. D — export two-frame / backpressure / ACK / negative

`tb/tb_brd_export_r3.v` (derived from the r0g export TB, host payload decode corrected to the
documented model; `+HOST_MODEL=1` keeps the r0g decode as a diagnostic). NF=2, so two frames are
exported; the r2 F1 sequencer exports the pending frame (no "arming frame is consumed").

| run | frames | payload | ACK | X / deadlock |
|---|---|---|---|---|
| SCEN0 | 2/2 PASS | mismatch=0 both; `legacy_mismatch=3830/3845` | wrong ACK holds; correct ACK releases (+1 each) | x_cnt=0, no timeout |
| SCEN3 (TL wait + slow DDR) | 2/2 PASS | mismatch=0 both | correct ACK releases (+1 each) | x_cnt=0, no timeout |
| SCEN2 (wrong-ACK branch) | 2/2 PASS | mismatch=0 both | wrong ACK holds; correct ACK releases | x_cnt=0, no timeout |
| legacy host model | — | mismatch=3830/3845 (diagnostic) | — | reproduces r0g |
| `tb_brd_neg_both` | 0 MWr / 0 doorbell | illegal base + illegal cap rejected | — | `POS_RESULT=NEG_PASS id=1/2` |

`verify_export_r3.py`: **CHECKS=48 FAILS=0 EXPORT_REGRESSION=PASS**.

**Testbench corrections (documented, not criterion changes):**
1. payload decode: old = lane0-first + LSB-first (inconsistent with its own header decode and the
   three project TBs); new = lane 7-first + MSB-first in DW. The T03 A/B/C experiment selects the
   new model; the old one is still runnable and fails, so nothing is hidden.
2. `core_out_valid` capture is now gated by `core_out_ready`; the old capture duplicated bytes while
   the store backpressured (SCEN3 `expbuf` was 4202 B instead of 3966 B).
3. `utx_sel` is driven by the TB as the EP grant (same model as the r2 G1 TB); the datapath leaves
   the port undriven on purpose (the EP engine drives it in the real top).
4. `REQ=NF` and the first frame is exported (r2 F1 behaviour); the r0g "arming frame" branch belonged
   to a different ARM wiring.
5. `STREAM_DIFF` compares the last two published frames; the old indices assumed NF=3.

## 6. E — static

- `evidence/filelist-check.log`: **CHECK_FILELIST=PASS** — 78 sources, 0 missing, 0 duplicate modules,
  0 rejected r3-era paths, 0 guard failures.
- `evidence/static-checks.log`: **STATIC_CHECKS_R3=PASS** — 64 checks, 0 fails:
  43 top ports identical; R14 once; six SDC groups; two allowed false paths; C8/C9 2FF; F2 offsets;
  ACK slice; `m_slot_base_bytes` ×32; `PUSH_BASE*` ×32; bridge ×8; `bswap256` kept; seq=1.
- r3-vs-r2 delta: exactly 3 RTL files; comment-stripped diff is 2 reset lines + 2 ACK-slice lines;
  the pusher diff is comment-only; a1_core/constraints/other RTL byte-identical.
- No `.bit`/`.cwc` in the run or package. Old r0/r1/r2 manifests byte-identical; no r3 path in them;
  no r3 changed-file SHA in them.

## 7. Side effect: A1U1 header CRC

Capture identity now starts at 1, so the D6 header `frame_id` is 1. The header CRC changes
`5436BF73 → A5ECBAD9` (bypass) and `981E85CF → 69C48065` (PREP). The compressed slot stream is
unchanged (`2470 / 9909B919`). The verifier checks hcrc by recomputation; the candidate-bound table
is re-frozen in `evidence/golden-r3.json`.

## 8. Honest status

- Local evidence supports G0 static, G1 (six-scenario), G1-export, G1-T03 and G5 binding.
  **The integrated tester judges**; this is not a board result.
- Not run: TD synthesis/route/STA/CDC, bitgen, CWC, download/Flash, real PCIe/RK, real DDR, the A
  path, 1080p30, long-run, routed bitstream. No claim about them.
- No production RTL/constraint/build script, old run, old report or old manifest was modified;
  no commit/push; the teammate was not contacted.
- No criterion was relaxed: the T03 oracle, the independent raw model, the ACK behaviour and the
  export byte comparison are unchanged; the only TB changes are the five corrections in §5.

## 9. Evidence paths (repo-relative)

```text
workflow/runs/20261027-2359_fpga-r3-merge/
  manifest-r3.json  result-r3.md  lessons.md  README.md  filelist.tcl  gen_manifest_r3.py
  rtl/**  constraints/**  tb/{tb_brd_g1_r3.v,tb_brd_export_r3.v,tb_t03_pusher_map.v}
  sim/run_{t03,sim_r3,export}.ps1  sim/scen0|scen3|scen4|prep|scen1|scen2|arb|t03map/**
  sim/sim_export_s{0,2,3}_h0_*.log  sim/logs_export_{legacy,neg}.txt
  evidence/verify-t03.log  evidence/verify-slot-r3.log  evidence/verify-export-r3.log
  evidence/static-checks.log  evidence/filelist-check.log  evidence/golden-r3.{md,json}
  evidence/{gen_expected_raw.py,verify_slot_r3.py,verify_t03_r3.py,verify_export_r3.py,
            static_checks_r3.py,verify_manifest_r3.py}
handoff/brd-p1-r3-20261027/**   (teammate package)
docs/DECISION_r0g_20261027.md
```

## 10. Next step (teammate, not local)

1. `python handoff/brd-p1-r3-20261027/build/check_filelist.py` → `CHECK_FILELIST=PASS`.
2. `python handoff/brd-p1-r3-20261027/build/gen_al.py` (must run first; no pre-generated `.al`).
3. `01_synth → 02_route → 03_bitgen` (STA gate; no bit on fail); optionally `04_cwc`.
4. Board: real B-path frame, MWr/doorbell, slot read at `0x1_0000`, A1U1 header + zlib decode,
   ACK/slot reuse; then A path and long-run/fps (G4, deferred).
