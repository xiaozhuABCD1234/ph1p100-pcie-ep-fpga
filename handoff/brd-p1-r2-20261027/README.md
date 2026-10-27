# brd-p1-r2-20261027 — teammate build package (T11.BRD.P1 round 2)

Local scope: this package was produced by **RTL simulation and static checks
only**. No TD run, no route, no STA, no bitgen, no CWC, no download/Flash, no
board. Everything below must be re-run in the teammate environment. The r0
150 MHz numbers are historical and do not describe this source set.

## 1. What changed in round 2 (RTL delta = 0)

Round 2 fixes **only the testbench camera stimulus and the evidence/golden**
(`T11.BRD.P1:TB_CAM_STIMULUS_WIDTH`). The buildable design is unchanged:

| item | r2 status |
|---|---|
| `rtl/**` (13 board files + `a1_core_fix01/`) | **byte-identical to r1** (`rtl_delta = 0`, 16/16 SHA equal) |
| `constraints/**` (`.sdc`, `.adc`) | **byte-identical to r1** (`constraints_delta = 0`, 2/2) |
| `filelist.tcl` (78 sources) | **byte-identical to r1** `sha256 41A61493335B84FA8AAFB1FF41FB99C2F8AC71D5E73F018187F567BA277A84A3` |
| `sim/tb_brd_g1_r2.v` | r1 TB + the 10-bit stimulus latch (`reg [9:0] cam_val` then `{4{cam_val}}`) + a stimulus probe |
| golden / evidence | re-frozen from the **independent** expected-raw model (see §5) |

Therefore: **if the teammate already built/tested r1, this candidate is the same
design** and the same synthesis/route/STA result may be declared with a matching
input hash; otherwise build this package. The r2 package still ships the
identical `rtl/` + `constraints/` copies for audit and portability.

RTL/constraint/filelist SHA table and the "no DUT change" statement:
`workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/evidence/r1-r2-sha-diff.md`
(repo-relative). The local round-2 result is
`workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/result-r2.md`.

## 2. Path resolution of the frozen filelist (read this)

`filelist.tcl` is kept byte-identical to r1 on purpose (it is the frozen,
guarded source list). It therefore still resolves:

- board RTL via `workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/rtl` — present in
  this repository and **byte-identical** to this package's `rtl/` (16/16 SHA,
  see the table above);
- the EP mirror via `handoff/brd-p1-r1-20261027/external/pcie_integration` — present in this
  repository and **byte-identical** to this package's `external/pcie_integration`
  (mirrored r0 snapshot).

Both r1 directories are frozen read-only inputs of the same repository, so the
compiled bytes are exactly the r2 bytes. `build/check_filelist.py` recomputes
every SHA and prints `CHECK_FILELIST=PASS`; `build/filelist-sha256.json` lists
all 78 sources with **repository-relative** paths and their SHA256.

If those r1 directories are ever pruned, regenerate an equivalent list from
`build/filelist-sha256.json` (path + SHA per source) instead of editing the
frozen `filelist.tcl`.

## 3. Files

| path (repo-relative) | purpose |
|---|---|
| `handoff/brd-p1-r2-20261027/filelist.tcl` | single guarded source list, 78 entries, SHA-identical to r1 |
| `handoff/brd-p1-r2-20261027/build/check_filelist.py` | missing/duplicate-module/r3/bitstream preflight + SHA JSON (repo-relative, N2 fixed) |
| `handoff/brd-p1-r2-20261027/build/filelist-sha256.json` | per-source SHA256 + size, repository-relative paths |
| `handoff/brd-p1-r2-20261027/build/01_synth.tcl` … `04_cwc.tcl` | phased TD entries (no download anywhere) |
| `handoff/brd-p1-r2-20261027/build/build.tcl` | one-session synth → route → final STA gate → bitgen |
| `handoff/brd-p1-r2-20261027/build/gen_al.py`, `brd_board.al.tmpl` | **generate** the TD `.al` (`@REPO_ROOT@` is the only placeholder) |
| `handoff/brd-p1-r2-20261027/constraints/brd_board.sdc` | r1/r2 SDC (`clk_core` own async group, C8/C9) — N1 note in `known-risks.md` |
| `handoff/brd-p1-r2-20261027/constraints/ph1p_pcie_case_ep.adc` | board pins (R14 once) |
| `handoff/brd-p1-r2-20261027/rtl/` | identical to r1; `a1_core_fix01/` is `alias_of_b20=true`, `behavioral_variant=false`, `filelist_included=false` |
| `handoff/brd-p1-r2-20261027/external/pcie_integration/` | byte copy of the r0 EP snapshot + the two common includes |
| `handoff/brd-p1-r2-20261027/known-risks.md` | risks before trusting a bit (incl. D7 facts + reopen condition, N1) |
| `handoff/brd-p1-r2-20261027/expected-g1.md` | simulation expectation (NOT a hardware guarantee) |
| `handoff/brd-p1-r2-20261027/prohibitions.md` | what must not be done with this package |
| `handoff/brd-p1-r2-20261027/a1u1-header-contract.md` | 44 B host-owned A1U1 header contract (D6) |
| `handoff/brd-p1-r2-20261027/manifest-brd-p1-r2.json` | frozen local manifest (copy) |
| `handoff/brd-p1-r2-20261027/result-r2.md` | local result (copy) |

## 4. Build (teammate environment; no download/Flash anywhere)

```text
cd <ph1p100-pcie-ep-fpga>
python handoff/brd-p1-r2-20261027/build/check_filelist.py      # must print CHECK_FILELIST=PASS
python handoff/brd-p1-r2-20261027/build/gen_al.py              # MUST be run first: writes build/brd_board.al
td_commands_prompt.exe -f handoff/brd-p1-r2-20261027/build/01_synth.tcl
td_commands_prompt.exe -f handoff/brd-p1-r2-20261027/build/02_route.tcl
td_commands_prompt.exe -f handoff/brd-p1-r2-20261027/build/03_bitgen.tcl   # STA gate: no bit on fail
td_commands_prompt.exe -f handoff/brd-p1-r2-20261027/build/04_cwc.tcl      # optional CWC
```

Or in one session: `td_commands_prompt.exe -f .../build/build.tcl`.

**N3 (fixed in r2):** the package no longer ships a pre-generated
`brd_board.al`. The r1 copy contained 81 absolute `D:/fpga/repos/...` paths and
would fail if opened as-is. Run `build/gen_al.py` first; it expands
`@REPO_ROOT@` from the actual checkout.

**N2 (fixed in r2):** `build/filelist-sha256.json` now stores genuinely
repository-relative `path` values (r1 claimed `repo_relative` but wrote absolute
paths).

## 5. Expected local G1 (simulation only)

See `expected-g1.md`. The judged byte criterion is
`zlib.decompress(slot) == expected_raw.bin`, where `expected_raw.bin` is built
**only** from the frozen stimulus contract
(`workflow/.../r2/evidence/gen_expected_raw.py`, SHA256
`FBA49D330DB9196A9BD9B8F29419A5603CEF600FE7D08F73708674F4C3C5111E`), plus
Adler-32 `392578F9`, correct frame/slot transport and the D6 host header.
Round 2 measured (candidate-bound, not a contract):
`stream_len = 2470`, `frame_bytes = 4096`, 32 MWr, one doorbell,
`hcrc = 5436BF73` for SCEN0/3/4; PREP=1/PRED=1 `stream_len = 538`.

## 6. Required evidence to return

- `candidate_timing.rpt` (setup/hold WNS/TNS, 0 violated endpoints before
  bitgen), `candidate_ignored.rpt` (unconstrained IO list), `candidate_cdc.rpt`,
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
