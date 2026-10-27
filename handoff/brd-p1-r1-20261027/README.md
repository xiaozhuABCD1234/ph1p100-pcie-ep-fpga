# brd-p1-r1-20261027 — teammate build package (T11.BRD.P1 round 1)

Local scope: this package was produced by **simulation and static checks only**.
No TD run, no route, no STA, no bitgen, no CWC, no download/Flash, no board.
Everything below must be re-run in the teammate environment; r0 timing numbers
are historical and do not describe this source set.

## 1. What this is

- Candidate: `brd_integrated_top` (43 ports, same set as `ph1p_pcie_ep_top`).
- Board path: 2x IMX415 CSI-2 -> crop -> 43b CDC -> P4 r2 A+ -> 2-slot DDR
  store -> descriptor -> `ddr_frame_pusher` -> MWr + doorbell -> PCIe EP.
- P4 = INT.P4 **r2** (functional/system pass, G2 fail). r3 is **not** used and
  its two derived files are guarded out.
- r1 fixes vs r0: F2 slot base self-consistency (word 2048 = byte 0x1_0000 on
  write and drain), F1 ARM/source-event alignment, held-seq alignment,
  descriptor release camera-id fix, SDC clock groups, mps_code/link_up 2FF
  (C8/C9). No P4/b20/img source is edited.
- Adler (D7): the r0 zero-tail did **not** reproduce; the unmodified b20 core
  emits a valid RFC1950 member and the r1 slot decodes with the standard
  Python zlib in both bypass and prep/pred modes. No RTL delta was invented.
  See `../workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/evidence/adler-rootcause.md`.
- A1U1 44B header is a **host/offline tool** responsibility (D6); the DUT slot
  stores only the zlib bytes. Contract: `a1u1-header-contract.md`.

## 2. Files

| path (repo-relative) | purpose |
|---|---|
| `handoff/brd-p1-r1-20261027/filelist.tcl` | single guarded source list, 78 entries |
| `handoff/brd-p1-r1-20261027/build/check_filelist.py` | SHA / missing / duplicate-module / r3 preflight |
| `handoff/brd-p1-r1-20261027/build/filelist-sha256.json` | per-source SHA256 + size |
| `handoff/brd-p1-r1-20261027/build/01_synth.tcl` ... `04_cwc.tcl` | phased TD entries (no download) |
| `handoff/brd-p1-r1-20261027/build/build.tcl` | one-session synth+route+STA gate+bitgen |
| `handoff/brd-p1-r1-20261027/build/gen_al.py`, `brd_board.al.tmpl` | generate the TD `.al` (only `@REPO_ROOT@` placeholder) |
| `handoff/brd-p1-r1-20261027/constraints/brd_board.sdc` | r1 SDC (clk_core own async group, C8/C9) |
| `handoff/brd-p1-r1-20261027/constraints/ph1p_pcie_case_ep.adc` | board pins (R14 once) |
| `handoff/brd-p1-r1-20261027/rtl/` | r1 board files + `a1_core_fix01/` (byte-identical b20 closure) |
| `handoff/brd-p1-r1-20261027/external/pcie_integration/` | byte copy of the r0 EP snapshot + the two missing common includes |
| `handoff/brd-p1-r1-20261027/known-risks.md` | risks before trusting a bit |
| `handoff/brd-p1-r1-20261027/expected-g1.md` | simulation expectation (NOT a hardware guarantee) |
| `handoff/brd-p1-r1-20261027/prohibitions.md` | what must not be done with this package |
| `handoff/brd-p1-r1-20261027/manifest-brd-p1-r1.json` | frozen local manifest (copy) |
| `handoff/brd-p1-r1-20261027/result-r1.md` | local result (copy) |

Read-only sources used in place (repo-relative):
`handoff/fpga-sim-only-20261027/inputs/board-filelist/...` (P4 r2, img, mem,
b18) and `.../inputs/p4/.../T10.b20-a-timing/r0/changed-src/` (b20 A+).

## 3. Build (teammate environment; no download anywhere)

```text
cd <ph1p100-pcie-ep-fpga>
python handoff/brd-p1-r1-20261027/build/check_filelist.py      # must print CHECK_FILELIST=PASS
python handoff/brd-p1-r1-20261027/build/gen_al.py              # writes build/brd_board.al
td_commands_prompt.exe -f handoff/brd-p1-r1-20261027/build/01_synth.tcl
td_commands_prompt.exe -f handoff/brd-p1-r1-20261027/build/02_route.tcl
td_commands_prompt.exe -f handoff/brd-p1-r1-20261027/build/03_bitgen.tcl   # STA gate, no bit on fail
td_commands_prompt.exe -f handoff/brd-p1-r1-20261027/build/04_cwc.tcl      # optional CWC
```

Or, in one session: `td_commands_prompt.exe -f .../build/build.tcl`
(`synth -> route -> final STA gate -> bitgen`; CWC still via 04).

The scripts run from the repository root and never invoke download/Flash/JTAG.
The 150/125 MHz decision rule is in `result-r1.md` §4 and the frozen guide §5.

## 4. Required evidence to return

- `candidate_timing.rpt` (setup/hold WNS/TNS, 0 violated endpoints to bitgen),
  `candidate_ignored.rpt` (unconstrained IO list), `candidate_cdc.rpt`,
  clock interaction/comb loops, undriven-input list, resource fit.
- bit/CWC SHA256 + bit identity, source Git commit, actual tool version and
  commands, each item PASS/FAIL/not_run.
- Board: real B-path frame, MWr/doorbell, slot read, A1U1 header + zlib decode,
  ACK/slot reuse, then A path (P3) and long-run/fps (G4, user deferred).

## 5. Not verified locally (must stay `not_run` / `teammate_required`)

G2p synthesis/route/STA/CDC, bit/CWC, download, real PCIe/RK, A path, 1080p30,
DDR address map on hardware, `cfg_phase`, BAR `0x130..0x13C` (D2 rejected in
round1), and every number in r0's 150 MHz report.
