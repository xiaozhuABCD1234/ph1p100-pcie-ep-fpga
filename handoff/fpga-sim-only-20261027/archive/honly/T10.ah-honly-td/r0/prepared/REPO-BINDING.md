# REPO-BINDING - T10.ah-honly-td (Line B), round r0

Frozen 2026-10-27 by the Line B developer. All values below were re-measured
read-only in this round (full SHA-256, bytes). Nothing outside
`workflow/runs/20261027-055621_fpga-honly-td-and-ah/T10.ah-honly-td/**` was written.

## 1. DUT = frozen pre-migration H-only r1 candidate (absolute read-only paths)

| File | Bytes | SHA-256 |
|---|---:|---|
| `D:/fpga/ph1p100/workflow/runs/20261026-231711_fpga-a-plus-h-prototype/T10.ah-honly/r0/changed-src/a1_deflate_core.v` | 85,192 | `8acd20b244b27ddf992432c39bffc34cf00e8394b01443571d9bdb8e3717b17b` |
| `D:/fpga/ph1p100/workflow/runs/20261026-231711_fpga-a-plus-h-prototype/T10.ah-honly/r0/changed-src/a1_frame_top.v` | 29,207 | `4afc26e246fbae4e32c5ab7e88dffb496048d10966c5ee42b290b3e71f60e30a` |
| `D:/fpga/ph1p100/workflow/runs/20261026-231711_fpga-a-plus-h-prototype/T10.ah-honly/r1/manifest-r1.json` | 24,979 | `f752ae09790cbbbaa5828c5fe1b6ed786a97485b400ef374fb191191b2c1a112` |

Both candidate SHAs match `manifest-r1.json` `candidate.core` / `candidate.frame_top`
and `input-index.md` §1. These absolute paths - not any repo copy - are what every
TD tcl in `../td/` compiles.

## 2. New authoritative repo is NOT a source in this round

`D:/fpga/repos/ph1p100-pcie-ep-fpga` (branch `main`) does **not** yet contain the
H-only diff. It was not read into the project, not used to substitute any file, and
nothing was written there. Repo binding is therefore satisfied by "frozen old
candidate + isolated TD project inside this task directory", as allowed by
`input-index.md` §5 and `fpga-design-guide.md` §3.1.

- commits: **0**; pushes: **0**; forks: **0**; `main` changes: **0**; `git` commands: **0**.
- driver repo `ph1p100-pcie-ep-driver`: not touched (0 RK / 0 network).

## 3. Reference inputs and templates (read-only, re-hashed)

| Item | Bytes | SHA-256 |
|---|---:|---|
| `T10.ah-honly/r0/changed-src/tb_ss_4run_wd.v` | 29,468 | `d86456dddb0aaa72a55f605c04cb8f51e9bd201b5cc11980dff89eb9afcbce6b` |
| `T10.ah-honly/r0/changed-src/tb_ss_4run_wd_probe.v` | 33,371 | `c8c19a176a5cd7e0ef0fa6835f00662569b0f335d41456d4dfa454cadb721bc5` |
| `T10.ah-honly/r0/changed-src/tb_a1_deflate_core_8b.v` | 7,539 | `910aea54e0d8d40a02a7d5e7844b053fff1f86e24cbfc43d1c33f083da5af09e` |
| `T10.ah-honly/r0/changed-src/tb_a1_deflate_core_16b.v` | 7,692 | `91e52cf5fcb5c395d4434d3238f2e931014ad16219cf357f8144d0bf14115a06` |
| `T10.ah-honly/r1/changed-src/tb_adapter_directed.v` | 9,752 | `56066e703003a2948dd9c59437d2c8d163677a78e52d017cac289a6bbe824f27` |
| `T10.ah-honly/r0/src/content/raw40_n.hex` | 5,702,400 | `e44fe7bc89aaa3ada2422a41fcfb8e283d5f66cdffda29b2caf4da10d2cd7b53` |
| `T10.ah-honly/r0/src/content/raw40_l.hex` | 5,702,400 | `e7e3c21cd2e4cc18e115b4cf18692596450cfcfc7605297046e3840c67deefa2` |
| b11 `r0/td/a1_eng_top.v` (wrapper template) | 2,671 | `544cecfc2eb34a3ab5c03ebf3965730b4ce60b2ff73ac4c2ec2d87772faaf9aa` |
| b11 `r0/td/a1_small_top.sdc` (SDC template) | 399 | `227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311` |
| b11 `r0/td/01_build.tcl` (flow template) | 10,929 | `a8e9283e8413afd844f2429e6002560a2e791523c147fb764ee31fc7d8a2f356` |
| b11 `r0/td/route_flow.status` (format template) | 1,822 | `f9ce8bb1ef35afae17e5995126f3d4cc96097130ab792c7543714ed3188c9acf` |
| b11 `r0/td/routed_timing_status.rpt` (format template) | 62 | `3bbe7b1f717fda1aedc7aaccc2c6338035bab6288451c47467ddb1b81f395cf4` |
| r10 `T10.a1-eng-freeze/r10/td/00_all.tcl` (same-family block flow) | 1,902 | `d847d891a5924f4b7d34337e49043a1404203469de1b812a629a22d69b1e4cb1` |
| `tools/integrated_delivery/td/01_synth.tcl` (validated report parsing) | 7,756 | `e9a7522a26a8af81b99cd4a0e3f1ed01e1007fa5d2be85d080671a111720adad` |
| `tools/integrated_delivery/td/02_route.tcl` (validated route sequence) | 720 | `68f1dffd37db1c76d9b8424d0547570aa2d64c4b96aa26d071cacde717bbd5a2` |
| `tools/td/td_env.ps1` (drive contract) | 3,527 | `04bb700f39e6f5cfee4d0490f001ed544e2487a7b91755dce68256789a5ee1e2` |
| `tools/td/PATH_CONTRACT.md` (drive contract) | 2,688 | `54ab4d85ee7f9151385a202b01c4becc0bc285dbc52cf0fa8f5b2a84103e917f` |

Missing / not used: `T10.a1-eng-freeze/r10/td/lessons-r10.md` does not exist at that
path (`input-index.md` §3 lists `r10/lessons-r10.md`, one level up). It is a lesson
reference only, not a source, and was not needed for r0. Recorded as an input-index
path mismatch for the planner; no file was created or modified to "fix" it.

## 4. TD tool binding (not invoked this round)

- entry: `D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe`, 123,372,304 B,
  mtime 2026-09-09T14:46:26 (present; only `Get-Item` was used).
- 0 invocations of `td_commands_prompt.exe`, `td.exe`, `run.exe`, any TD flow, any
  Tcl script in this directory, and no drive mapping change (`T:` untouched).
- project location: only `T10.ah-honly-td/r0/td/**` (to be created by TD at run time).

## 5. Write-scope statement

Written this round: `r0/prepared/{REPO-BINDING.md,readonly-inputs-r0.json}`,
`r0/td/{a1_ah_eng_top.v,a1_ah_small_top.sdc,01_synth.tcl,02_route.tcl,03_2096_analysis.tcl,README.md}`,
`r0/lint/**`, `r0/preflight-r0.json`, `r0/manifest-inputs-r0.json`,
`r0/result-blocked-r0.md`, `r0/lessons-r0.md`.
Not written: other runs, H-only candidates/reports, integrated delivery, b18-b20,
old P1-P4, production `fpga/csi2/**`, `upstream/**`, `D:/fpga/repos/**`, `docs`,
`.agents`, `workflow/tasks.json`, `D:/TD/**`, hardware. No deletions of any kind.