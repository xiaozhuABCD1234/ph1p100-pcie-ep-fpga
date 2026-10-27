# BINDING - T10.ah-honly-td r1 (Line B, TD execution round)

Frozen 2026-10-27 for round r1. Scope: source binding / Tcl / README / hashes only.
No RTL, no geometry, no clock, no SDC exception, no wrapper port change.

## 1. DUT switch (old -> new)

| Role | Path (absolute, read-only) | Bytes | SHA-256 | Status |
|---|---|---:|---|---|
| core OLD (r0, rejected by TD) | `.../20261026-231711_fpga-a-plus-h-prototype/T10.ah-honly/r0/changed-src/a1_deflate_core.v` | 85,192 | `8acd20b244b27ddf992432c39bffc34cf00e8394b01443571d9bdb8e3717b17b` | superseded (HDL-8007) |
| **core NEW (r1)** | `.../20261027-055621_fpga-honly-td-and-ah/T10.ah-honly-synthfix/r0/changed-src/a1_deflate_core.v` | **85,221** | **`d2960cfe0111b7b61aff281e3f16427834dda26107f37867d5c7c89ac346aad8`** | used |
| frame_top (unchanged) | `.../T10.ah-honly-synthfix/r0/changed-src/a1_frame_top.v` | 29,207 | `4afc26e246fbae4e32c5ab7e88dffb496048d10966c5ee42b290b3e71f60e30a` | used, byte-identical to H-only r1 |
| synthfix manifest | `.../T10.ah-honly-synthfix/r0/manifest-r0.json` | - | `034777c55d5a7857f18d9860afbb73f7554940f65213d9228c449bbc5855e510` | tester PASS (r2-ruling §1) |

Both r1 SHAs were re-computed in this round before the TD call; the synthfix manifest SHA
also matches the planner's value. The only difference vs the old core is the whitelisted
multi-driver fix (+4/-3 lines, 29 B), so behaviour is unchanged (synthfix proved exact
S_ss 6,196,749.5 / 5,834,940 and byte-identical 4-frame output).

## 2. r1 scripts and byte-identity evidence

| File | SHA-256 | Note |
|---|---|---|
| `r1/td/a1_ah_eng_top.v` | `3e2be8eaf88fc1196d1565de19d6ca41b35e85470f3bbd9271af5067526670c7` | byte-identical copy of `r0/td` (verified equal) |
| `r1/td/a1_ah_small_top.sdc` | `6d948bba2087d1b86e772ef4a05486b261c2ddb445950739701bdcc0655b94bf` | byte-identical copy (5.333 ns, no exception) |
| `r1/td/01_synth.tcl` | `784639c50e6fc8914db9136d3f506ee3475e6f94625dc3ade99e1009a5e2747a` | header (DUT/SHA, lease v2) + 4 `add_files` paths changed; **parse/report section byte-identical** (span SHA `615fbc0358d2082f0d0e42cb40a8e41846ec46f23627295c7749f634fa199b44`) |
| `r1/td/02_route.tcl` | `f5bfe0bad9815110943697b0ec5f4af7b32aab200e9f81b169b0b4b3185de94a` | comment line only, command sequence unchanged |
| `r1/td/03_2096_analysis.tcl` | `5eb5a78e3e4c077273da65618f38b05ad728715393e2da23c70d6bf098b330a0` | comment line only, command sequence unchanged |

`add_files` paths in `01_synth.tcl`: wrapper/SDC point to `r1/td` (same bytes as r0),
frame_top/core point to the synthfix task. Unknown/new files: none.

## 3. Repo binding (unchanged)

`D:/fpga/repos/ph1p100-pcie-ep-fpga` is **not** a source (H-only/synthfix diff is not
migrated): 0 writes, 0 commits, 0 pushes, 0 forks, 0 `main` changes, 0 git commands.

## 4. Quota and lease

- TD lifetime launches <= 3; r0 used 1 (elaborate reject); **this round = launch 2**.
- synthesis result: 1; route <= 2 (2nd only after a failed 1st with a written parameter
  difference); 209.6 analysis-only <= 1; bitgen/CWC/download/Flash/board/network = 0.
- Lease v2 (holder-agnostic, r2-ruling §2): 0 TD processes AND `INT.P4/td`,
  `INT.P4/r3`, `20261027-0726_fpga-board-integration/T11.BRD.P1/td` each quiet >= 20 min.
  Re-verified in `r1/preflight-r1.json` immediately before the TD call. `T:` belongs to
  the board-integration run: **never** remapped, released or `-Force`d here.

## 5. Write scope

Only `T10.ah-honly-td/r1/**`. Not written: `r0/**`, synthfix, Line A, other runs,
integrated delivery, board-integration, b18-b20, old P1-P4, production sources,
`docs`, `.agents`, `workflow/tasks.json`, `D:/fpga/repos/**`, `D:/TD/**`. No deletions.