# SCOPE-EXTENSION — T10.ah-honly-synthfix r0

**Result: no scope extension applied.**

## Why the question had to be asked

`r1-ruling.md §3.2` / `dev-plan.md §11.2` authorise, in addition to the two whitelist
edits, a bounded same-class extension: if the mandatory whole-file multi-driver scan finds
**other** registers that are written once in a reset branch and once in a functional
branch, they may be fixed the same way, provided every case is listed here and the total
added lines stay ≤ 8. A different class (functional-block-to-functional-block driving,
multi-driven wires, cross-module force) requires stopping and returning to the planner.

## Scan method

- Files scanned: `r0/changed-src/a1_deflate_core.v` (85,192 B, frozen copy),
  `r0/changed-src/a1_frame_top.v` (29,207 B, frozen copy).
- Tool: `%TEMP%/opencode/ah-synthfix/scan_multidriver.py` (statement-anchored LHS
  detection; comments stripped; `always` block extent tracked with a `begin/end` stack;
  classes: cross-block procedural, multiple continuous `assign`, mixed
  procedural+continuous, `force`/`release`).
- Artefacts: `r0/scan/pre-scan.json`, `r0/scan/post-scan.json`.

## Findings (pre-fix)

| File | Class | Register | Reset-branch driver | Functional driver(s) | Blocks |
|---|---|---|---|---|---|
| `a1_deflate_core.v` | cross-block (reset vs functional) | `cmem_lo[15:0]` | L1042 | L679 | 673 / 964 |
| `a1_deflate_core.v` | cross-block (reset vs functional) | `cmem_lo_pend` | L1043 | L676, L681, L684 | 673 / 964 |
| `a1_deflate_core.v` | cross-block (reset vs functional) | `cmem_lo_addr[11:0]` | L1044 | L680 | 673 / 964 |
| `a1_frame_top.v` | — | — | — | — | none |

No multi-driven wire, no functional-block-to-functional-block pair, no cross-module
`force`, no mixed procedural/continuous net was found in either file.

## Decision

All three findings are exactly the whitelist case (the same class the ruling already
specified), so **no extension was needed**: the fix consists only of hunk A (+4/-1) and
hunk B (-3) in `a1_deflate_core.v`. Extension-added lines: **0** (limit 8). If the
planner's own scan had differed, the difference would be recorded here — it did not.

## Post-fix scan

`r0/scan/post-scan.json`: core = 0 findings (0 cross-block), frame_top = 0 findings.
