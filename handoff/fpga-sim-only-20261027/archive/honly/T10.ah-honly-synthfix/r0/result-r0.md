# result-r0 — T10.ah-honly-synthfix (Line B precondition fix, 0 TD)

- **status**: `ready_for_test`
- **verdict (developer-local)**: **PASS** on every gate this package owns; final judgement
  belongs to the independent integrated tester.
- **scope**: remove the TD-elaboration multi-driver reject on the frozen H-only r1
  candidate; prove **zero behaviour change**. No TD / synthesis / PnR / STA / bitgen /
  CWC / download / Flash / board / COM / JTAG / RK / network action was performed.
- **frozen**: `r0/manifest-r0.json` (`stopped_modifying=true`, `active_commands=0`).

## 1. Candidate

| File | Frozen input | Fixed copy | Bytes | Changed |
|---|---|---|---|---|
| `a1_deflate_core.v` | `8acd20b244b27ddf992432c39bffc34cf00e8394b01443571d9bdb8e3717b17b` | `d2960cfe0111b7b61aff281e3f16427834dda26107f37867d5c7c89ac346aad8` | 85,221 | +4/-3 lines, 2 hunks |
| `a1_frame_top.v` | `4afc26e246fbae4e32c5ab7e88dffb496048d10966c5ee42b290b3e71f60e30a` | `4afc26e246fbae4e32c5ab7e88dffb496048d10966c5ee42b290b3e71f60e30a` | 29,207 | **byte-identical** |

Diff: `DIFF-synthfix.md` / `DIFF-synthfix.raw`. Scope decision: `SCOPE-EXTENSION.md`
(no extension needed, 0 added lines beyond the whitelist).

## 2. Gates

| Gate | Required | Measured | Result |
|---|---|---|---|
| multi-driver, post-fix static scan | 0 cross-block drivers (core + frame_top) | core 0 / frame_top 0 (0 in all classes) | **PASS** |
| compile `vlog -sv +define+SIMULATION` | 0 errors; warnings ≤ frozen 21 same-source | 4 builds (bench8, bench16, adapter, frame) all `Errors: 0, Warnings: 0` | **PASS** |
| b6 8b/16b × comp | 50,310 B, `2601d57c…a7c05`, 304,961 cyc | 8b 50,310 B / `2601d57c…a7c05` / 304,961; 16b identical | **PASS** |
| b6 8b/16b × rand | 153,766 B, `54f262f2…96dd`, 161,479 cyc | 8b 153,766 B / `54f262f2…96dd` / 161,479; 16b identical | **PASS** |
| bench zlib restore | `zlib.decompress` == source bytes | 4/4 `matches_input=true` (153,600 B each) | **PASS** |
| adapter directed | `ADAPTER_PASS cases=12 errors=0` | `ADAPTER_PASS cases=12 errors=0` | **PASS** |
| N4 `S_ss` | exactly 6,196,749.5 (S_23 6,196,750 / S_34 6,196,749) | 6,196,749.5 (S_23 6,196,750 / S_34 6,196,749) | **PASS** |
| L4 `S_ss` | exactly 5,834,940 (S_23 = S_34) | 5,834,940 (S_23 = S_34 = 5,834,940) | **PASS** |
| 4-frame byte-exact | 4/4 `.frm`/`.hdr` whole-file SHA equal to frozen | `n-4f.frm b9cb5359…` yes, `n-4f.hdr c7fe281c…` yes, `l-4f.frm 8aad9099…` yes, `l-4f.hdr 864d2fba…` yes — all four **whole-file SHA equal** to `T10.ah-honly/r1/sim/caps/*` | **PASS** |
| stall markers | no `SS_STALL*` / `B11_FULL_TIMEOUT` | none in `n-4f.log` / `l-4f.log` | **PASS** |
| 4-frame counters | `cap=enc=exported=4`, `read=518,400`, `raw_bad=err=wd=drops=0` | N and L exactly that | **PASS** |
| 1-frame probe | not run (0 probe this package) | not run | n/a (by ruling) |
| TD / synth / PnR / bitgen / CWC / board | 0 | 0 | **PASS** |

Note on the compile-warning baseline: the gate allows up to the 21 frozen
`camera_a1_uart_top.v:543`-family warnings. All four builds here report `Errors: 0,
Warnings: 0`, so the cap is not approached. A search of the frozen H-only r1 logs and of
`T10.ah-honly-td/r0` logs for the string `camera_a1_uart_top.v:543` returned no hits, i.e.
the 21-warning family is not reproducible from the frozen logs; it is recorded here as an
inherited planning reference, not as something this package re-measured.

Additional zero-change cross-checks (all equal to the frozen H-only r1 evidence):
`exp` event timestamps 4/4 (N `11161098 / 17356702 / 23553452 / 29750201`), frame-1
`core_interval` N `6,197,186` and L `5,832,040`, `cycles` N `29,752,200`, L `29,259,547`,
and the whole `.stats` key/value set (including `dup=3896` / `dup=568`).

## 3. Tooling and budget

| Item | Value |
|---|---|
| Simulator | ModelSim Intel FPGA Edition 10.5b, `D:/intelFPGA/18.1/modelsim_ase/win32aloem`; per-build `work/` + copied `D:/intelFPGA/18.1/modelsim_ase/modelsim.ini` |
| Python | 3.11 (`zlib.decompress`, SHA-256, stats parsing) |
| Commands | 15, all recorded in `r0/sim/commands-r0.jsonl` (argv, cwd, rc, timed_out, seconds, timeout_s, log) |
| vsim wall clock | n-4f 1,680.46 s + l-4f 1,655.24 s + 4 benches 21.82 s + adapter 2.09 s = **3,359.61 s** (cap 7,200 s) |
| Slowest single vsim | 1,680.46 s (cap 2,700 s) |
| bench / adapter per-run | 4.67–6.81 s / 2.09 s (cap 300 s each) |
| timeouts | 0 (no `timed_out=true` record) |
| TD | 0 calls, 0 processes started, `T:` untouched |
| probe | 0 runs (frozen TB copy present, deliberately not compiled or run) |
| No retry happened | every command succeeded on its first execution; no re-run of N4/L4 was needed (S_ss exact on first pass) |

Per-run `seconds` (from `commands-r0.jsonl`): vlib 0.11–0.24, vlog 0.20–0.45,
b8-comp 6.81, b8-rand 4.67, b16-comp 5.62, b16-rand 4.72, adapter 2.09, n-4f 1,680.46,
l-4f 1,655.24.

## 4. Evidence index

| Evidence | Path |
|---|---|
| Pre/post multi-driver scan | `r0/scan/pre-scan.json`, `r0/scan/post-scan.json` |
| Diff | `DIFF-synthfix.md`, `DIFF-synthfix.raw` |
| Compile logs (4) | `r0/sim/logs/vlog-{bench8,bench16,adapter,frame}.log` (+ `.stdout`, vlib logs) |
| Bench caps/stats | `r0/sim/caps/b{8,16}-{comp,rand}.{out.hex,stats}` |
| Adapter | `r0/sim/logs/adapter.log` -> `r0/out/adapter-r0.json` |
| 4-frame caps | `r0/sim/caps/{n,l}-4f.{evt,hdr,frm,stats}`, logs `r0/sim/logs/{n,l}-4f.log` |
| Derived JSON | `r0/out/{byte-exact-r0,cycles-r0,h-bench-r0,adapter-r0,compile-r0,summary-r0}.json` |
| Commands | `r0/sim/commands-r0.jsonl` |
| Manifest | `r0/manifest-r0.json` |

## 5. What this does and does not prove

Proves: with the fixed core (`d2960cfe…`) and an unchanged `a1_frame_top` (`4afc26e2…`),
the candidate (a) has no procedural multi-driver detectable by static scan, so the TD
`HDL-8007/5007` reject cause is removed at its root, and (b) produces **bit-identical**
b6 bench output, **identical** adapter behaviour, and **bit-identical** 4-frame N/L
`.frm`/`.hdr` with **exactly** the frozen `S_ss` values and cycle counts.

Does not prove: that TD now elaborates or synthesises this candidate (0 TD permitted
here — that is `T10.ah-honly-td` r1), 187.5 MHz timing, resources, CDC, bitstream or
board behaviour. A compile/scan pass is not an elaboration pass; TD remains the authority.

## 6. Retest input for the integrated tester

- Frozen DUT: `r0/changed-src/a1_deflate_core.v` (`d2960cfe…`) +
  `r0/changed-src/a1_frame_top.v` (`4afc26e2…`).
- TBs: `r0/changed-src/{tb_a1_deflate_core_8b.v, tb_a1_deflate_core_16b.v,
  tb_ss_4run_wd.v, tb_ss_4run_wd_probe.v, tb_adapter_directed.v}` (frozen copies, hashes in
  the manifest; the probe TB was not used).
- Required dimensions: functional (byte-exact / zlib / adapter / 4-frame counters),
  engineering (compile cleanliness, source immutability, manifest drift), 0 TD by design.
- Every gate above is reproducible from `r0/sim/commands-r0.jsonl` alone.
