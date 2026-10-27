# T11.BRD.P1 r2 — build entry (local pointer)

The buildable teammate package is:

`handoff/brd-p1-r2-20261027/`

Entry point and full steps: `README.md` in that package.
Single source list: `filelist.tcl` (78 repository-relative entries, byte-identical
to r1: sha256 `41A61493335B84FA8AAFB1FF41FB99C2F8AC71D5E73F018187F567BA277A84A3`;
guard + `build/check_filelist.py`).
Build entries: `build/01_synth.tcl`, `02_route.tcl`, `03_bitgen.tcl`,
`04_cwc.tcl`, `build.tcl`.
The `.al` is **not shipped**: run `build/gen_al.py` first, which expands
`@REPO_ROOT@` in `brd_board.al.tmpl` (N3 fix).
Constraints: `constraints/brd_board.sdc`, `constraints/ph1p_pcie_case_ep.adc`
(byte-identical to r1; N1 = second `derive_clocks`, teammate STA item).

Round-2 status: **RTL/constraints/filelist delta = 0** versus r1; only the
testbench, golden, evidence, manifest and handoff package changed. A teammate
build of r1 with the same source hashes is the same design.

No TD/bitgen/CWC/download was run locally; the local evidence is under
`workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/`
(`result-r2.md`, `evidence/`).
