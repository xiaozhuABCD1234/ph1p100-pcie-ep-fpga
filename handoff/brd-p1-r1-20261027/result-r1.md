# T11.BRD.P1 — round 1 result (local scope)

## 0. Inherited facts (frozen; not rewritten)

**P4 = ⚠**: `INT.P4` r2 functional/system pass, G2 fail (112 endpoints,
WNS −0.637 ns, TNS −69.776 ns @187.5 MHz); r3 G2 pass (+0.072 ns) but its
derived variants fail equivalence. **r2 and r3 are never spliced**; r3-derived
files are guarded out. This package uses P4 **r2** only.

**Local boundary (2026-10-27 AGENTS)**: only RTL simulation, software/byte
checks, static interface/constraint checks and evidence were done. **No TD
synthesis, route, STA, bitgen, CWC, JTAG/COM, download or Flash** was run.
G2p is `teammate_required` / `not_run` locally; G3/G4 are `awaiting_hardware`.
The r0 150 MHz numbers are historical and are not a round1 pass/fail.

## 1. What changed in r1

| item | change | file |
|---|---|---|
| F2 slot base | add `SLOT_BASE_WORD` (2048) to the P4 **write and drain read** word address before the bridge; store/descriptor/pusher now all use byte base 0x1_0000. P4 r2 sources unchanged. | `rtl/brd_board_datapath.v` |
| F1 ARM/source event | new `brd_export_seq` latches the host ARM, presents it only after a published descriptor, and emits exactly one board-owned source event; repeats are ignored/counted. | `rtl/brd_export_seq.v`, datapath |
| held_seq | P4 egress adapter now sees the pusher done count (= held_seq = doorbell value), not capture_seq. | datapath (track feed) |
| descriptor release | clear the **matching** camera's active flag on release (r0 cleared the wrong one). | datapath |
| pusher error | `pcie_err` is a pulse on a new error code, not a sticky level (a rejected ACK cannot abort a later frame). | `rtl/brd_cdc_mailboxes.v` |
| C8/C9 | `mps_code[2:0]` and `link_up` enter clk_core through 2FF only. | datapath |
| SDC | six one-clock async groups; `clk_core` no longer shares a group with `tl_clk_user`; still only R14/user_int_trigger false paths. | `constraints/brd_board.sdc` |
| TB | EP `utx_sel` driven, TLP DW lane order, per-DW byte order, ACK=held_seq, whole ROI row truncation, early/duplicate ARM scenarios, stable slot dump, host A1U1 header. | `sim/tb_brd_g1_r1.v` |

No P4/img/b20/EP production source was edited. b20 Adler (D7) finding: no RTL
delta; the r0 zero tail did not reproduce. See `evidence/adler-rootcause.md`.

## 2. G1 — actual local results (ModelSim ASE 10.5b, 64x48 ROI, 768 groups)

| scenario | log | result |
|---|---|---|
| SCEN 0, late ARM, bypass (PREP=0/PRED=0) | `evidence/sim_scen0.log` | **PASS**: 32 MWr / 4096 B, doorbell 1, exported 1, slot 0x10000 starts `78 9c`, base 0 unused, 0 mismatch/X, correct ACK -> release +1 |
| SCEN 3, early ARM (doubled) | `evidence/sim_scen3.log` | **PASS**: one export, 32/4096, one doorbell |
| SCEN 4, duplicate ARM while armed | `evidence/sim_scen4.log` | **PASS**: ignored/counted, one export |
| SCEN 1, missing EOF (last ROI row absent) | `evidence/sim_scen1.log` | **PASS negative**: committed=0, published=0, exported=0, 0 TLP, 0 doorbell, aborted and released (rel>=1) |
| SCEN 2, wrong ACK then correct | `evidence/sim_scen2.log` | **PASS negative**: held stays, no release; correct held_seq releases +1 |
| arbiter 6 checks | `evidence/arb.log` | **PASS**: no mid-burst handover, bridge single beat, late beat counted once and not rerouted, `o_switch_err=0` |
| SCEN 0 with PREP=1/PRED=1 | `evidence/sim_prep.log` | **PASS**: `stream_len=3966`, 32 MWr/4096 B, standard zlib OK 3840 B, Adler `d5cadeeb` |

Independent Python verification (`evidence/verify_slot.py`, standard
`zlib.decompress`): `VERIFY=PASS` — slot length = `stream_len`, decompressed
length = `xform_len`, raw bytes = packed RAW10 A+ input (bypass),
Adler = last 4 B, A1U1 header magic/version/fields/CRC/payload, MWr count and
bytes = `frame_bytes`, doorbell = `held_seq`, 0 mismatch, 0 X. See
`evidence/verify_scen0.log` (bypass) and `evidence/verify_prep.log` (PREP=1/PRED=1).

## 3. G0 / G5 — static (local)

- `evidence/static-checks.log`: **STATIC_CHECKS=PASS** — 43 top ports identical
  to `ph1p_pcie_ep_top`, R14 once and on `pcie_power_on_rst`, six SDC groups
  with `clk_core` alone, only the two allowed false paths, no multicycle, C8/C9
  2FF instances, F1/F2 edits present, no `.bit`/`.cwc`, and all 27 r0 manifest
  files byte-identical (no r0 rewrite).
- `evidence/filelist-check.log`: **CHECK_FILELIST=PASS** — 78 sources,
  0 missing, 0 duplicate modules, 0 r3 files/paths, guards pass; per-source
  SHA in `handoff/.../build/filelist-sha256.json`.
- `evidence/sdc-groups.md`, `cdc-list.md` (C1–C9), `evidence/cdc-static.log`.
- Handoff package: `handoff/brd-p1-r1-20261027/**` (filelist, constraints,
  RTL, build entries, expected/risks/prohibitions, header contract, manifest
  copy, result copy). No local bit/CWC anywhere.

## 4. G2p / bit / board (not local)

`not_run` / `teammate_required` / `awaiting_hardware`. The r1 source set is
different from r0, so the teammate must re-run 150/125 MHz synthesis, route,
final STA, CDC, resources/IO and bit/CWC. r0's `-2.273 ns / 79 endpoints` and
the r3 `+0.072 ns` are not this candidate's numbers.

## 5. Honest status

Local evidence supports G1 positive/negative, G0 static and G5 binding, and the
frozen r1 manifest is `ready_for_test`. The integrated tester judges. This is
not a board result: no real PCIe/RK transfer, no real DDR, no A path, no
1080p30, no long-run, and no routed/bitstream identity.
