# brd-p1-r3-20261027 — teammate build package (T11.BRD.P1 round 3)

Local scope: this package was produced by **RTL simulation and static checks only**.
No TD run, no route, no STA, no bitgen, no CWC, no download/Flash, no board.
Everything below must be re-run in the teammate environment. r0's 150 MHz numbers
and r3's `+0.072 ns` are historical and do not describe this source set.

## 1. What is r3

r3 is the **minimal merge** of the r2 board candidate with the two r0d fixes that
were still outside it, plus a re-verified data-beat mapping. It is the first package
where the ACK slice, the capture identity and the T03 oracle agree.

| item | r3 status |
|---|---|
| `rtl/brd_cdc_mailboxes.v` | **changed**: `o_ack_seq <= out_bus[63:32]`, `o_ack_session <= out_bus[31:0]` (r0d ACK slice) |
| `rtl/brd_board_datapath.v` | **changed**: `a_seq/b_seq` reset to `32'd1` (r0d capture identity starts at 1); release polarity kept (`0→A, 1→B`); C8/C9 and `+SLOT_BASE_WORD` kept; slot base `×32` kept |
| `rtl/ref/ep_side/ddr/ddr_frame_pusher.v` | **comment only**: the T03 A/B/C mapping experiment; `bswap256` unchanged |
| `rtl/a1_core_fix01/**` | byte-identical to the b20 originals and to r1/r2 (store/deflate/frame_top/arb unchanged) |
| P4 RTL, `brd_integrated_top.v`, `brd_cam_fe.v`, `brd_ddr_rd_arb.v`, `brd_a1_core_pll.v`, `brd_export_seq.v`, `a1_raw_crop.v`, `p2_ddr_bridge.v` | byte-identical to r2 |
| `constraints/**` | byte-identical to r2 |
| `filelist.tcl` | 78 sources; same set as r2, paths point at this package's `rtl/` and `external/` |

Not adopted from the export working copy: `BASE_WORD=SLOT_BASE_WORD`, pusher base
`×128`, bridge `×32`, internal `utx_sel` grant, removal of `brd_export_seq`.
The address unit is one `×8` (bridge) + one `×4` (board remap) = **×32**.

## 2. Path resolution (read this)

`filelist.tcl` resolves:

- board RTL and the pusher from **this package's** `rtl/` (no r1/r2 run dir);
- the EP base from **this package's** `external/pcie_integration/` (a byte copy of the
  frozen r0 snapshot, so the pusher/engine includes resolve);
- the A+ core from this package's `rtl/a1_core_fix01/`;
- the P4/img/FIFO/b18 inputs from the frozen repository tree
  `handoff/fpga-sim-only-20261027/inputs/` (read-only; unchanged).

`build/check_filelist.py` recomputes every SHA and prints `CHECK_FILELIST=PASS`;
`build/filelist-sha256.json` lists all 78 sources with **repository-relative** paths.

## 3. Files

| path (repo-relative) | purpose |
|---|---|
| `handoff/brd-p1-r3-20261027/filelist.tcl` | single guarded source list, 78 entries |
| `handoff/brd-p1-r3-20261027/build/check_filelist.py` | missing/duplicate-module/rejected-path/bitstream preflight + SHA JSON |
| `handoff/brd-p1-r3-20261027/build/filelist-sha256.json` | per-source SHA256 + size, repository-relative |
| `handoff/brd-p1-r3-20261027/build/01_synth.tcl` … `04_cwc.tcl` | phased TD entries (no download anywhere) |
| `handoff/brd-p1-r3-20261027/build/build.tcl` | one-session synth → route → final STA gate → bitgen |
| `handoff/brd-p1-r3-20261027/build/gen_al.py`, `brd_board.al.tmpl` | **generate** the TD `.al` (`@REPO_ROOT@` is the only placeholder) |
| `handoff/brd-p1-r3-20261027/constraints/brd_board.sdc` | r1/r2/r3 SDC (`clk_core` own async group, C8/C9) — N1 note in `known-risks.md` |
| `handoff/brd-p1-r3-20261027/constraints/ph1p_pcie_case_ep.adc` | board pins (R14 once) |
| `handoff/brd-p1-r3-20261027/rtl/` | r3 board RTL + `ref/` + `a1_core_fix01/` |
| `handoff/brd-p1-r3-20261027/external/pcie_integration/` | byte copy of the r0 EP snapshot + the two common includes |
| `handoff/brd-p1-r3-20261027/known-risks.md` | risks before trusting a bit (incl. D7 facts + reopen condition, N1) |
| `handoff/brd-p1-r3-20261027/expected-g1.md` | simulation expectation (NOT a hardware guarantee) |
| `handoff/brd-p1-r3-20261027/prohibitions.md` | what must not be done with this package |
| `handoff/brd-p1-r3-20261027/a1u1-header-contract.md` | 44 B host-owned A1U1 header contract (D6) |
| `handoff/brd-p1-r3-20261027/manifest-r3.json` | frozen local manifest (copy) |
| `handoff/brd-p1-r3-20261027/result-r3.md` | local result (copy) |

## 4. Build (teammate environment; no download/Flash anywhere)

```text
cd <ph1p100-pcie-ep-fpga>
python handoff/brd-p1-r3-20261027/build/check_filelist.py      # must print CHECK_FILELIST=PASS
python handoff/brd-p1-r3-20261027/build/gen_al.py              # MUST be run first: writes build/brd_board.al
td_commands_prompt.exe -f handoff/brd-p1-r3-20261027/build/01_synth.tcl
td_commands_prompt.exe -f handoff/brd-p1-r3-20261027/build/02_route.tcl
td_commands_prompt.exe -f handoff/brd-p1-r3-20261027/build/03_bitgen.tcl   # STA gate: no bit on fail
td_commands_prompt.exe -f handoff/brd-p1-r3-20261027/build/04_cwc.tcl      # optional CWC
```

Or in one session: `td_commands_prompt.exe -f .../build/build.tcl`.

**N3**: no pre-generated `brd_board.al` is shipped. Run `build/gen_al.py` first; it expands
`@REPO_ROOT@` from the actual checkout.

**N1**: `brd_board.sdc` still has the second `derive_clocks`; unchanged from r1/r2 and
restated in `known-risks.md` for the teammate STA.

## 5. Expected local G1 (simulation only)

See `expected-g1.md`. The judged byte criterion is
`zlib.decompress(slot) == expected_raw.bin`, where `expected_raw.bin` is built **only** from the
frozen stimulus contract (SHA256 `FBA49D330DB9196A9BD9B8F29419A5603CEF600FE7D08F73708674F4C3C5111E`),
plus Adler-32 `392578F9`, correct frame/slot transport and the D6 host header.

r3 measured (candidate-bound, not a contract):
`stream_len = 2470`, `frame_bytes = 4096`, 32 MWr, one doorbell,
`stream_crc = 9909B919`, `hcrc = A5ECBAD9` for SCEN0/3/4; PREP=1/PRED=1 `stream_len = 538`,
`hcrc = 69C48065`. The header CRC moved because r3 starts the capture identity at 1
(`frame_id 0→1`); the compressed stream itself is unchanged.

The T03 70 B oracle (`evidence/t03/rtl-slot-read.bin`) is reproduced byte-for-byte through
the store and through the pusher in the documented host order (`78 9c 62 48 4a 4a 5a 01`).
The pusher's `bswap256` is kept; the A/B/C experiment is in
`evidence/verify-t03.log` (A=0, B=69/70, C=67/70).

## 6. Required evidence to return

- `candidate_timing.rpt` (setup/hold WNS/TNS, 0 violated endpoints before bitgen),
  `candidate_ignored.rpt` (unconstrained IO list), `candidate_cdc.rpt`,
  clock interaction / comb loops, undriven inputs, resource fit.
- bit/CWC SHA256 + bit identity, source commit, tool version and exact commands,
  each item PASS/FAIL/not_run.
- Board: real B-path frame, MWr/doorbell, slot read at `0x1_0000`, A1U1 header +
  zlib decode, ACK/slot reuse, then A path (P3) and long-run/fps (G4, deferred).
- If a slot fails to decode or the raw does not match the contract, report it
  before touching RTL: D7's reopen condition in `known-risks.md` applies.

## 7. Not verified locally (must stay `not_run` / `teammate_required`)

G2p synthesis/route/STA/CDC, bit/CWC, download, real PCIe/RK, the A path,
1080p30, DDR address map on hardware, `cfg_phase`, BAR `0x130..0x13C` (D2
rejected in round 1), and every number in r0's 150 MHz report.
