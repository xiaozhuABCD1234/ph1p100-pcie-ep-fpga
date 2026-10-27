# result-r0 - T10.ah-honly-td (Line B), TD execution round

- **status**: `blocked`
- **reason_code**: `DUT_SYNTH_ELABORATION_ERROR`
- **semantics**: the frozen candidate is rejected by TD elaboration (multiple drivers on
  `cmem_lo`). The TD resource itself was available and used correctly; this is **not**
  `TOOL_UNAVAILABLE`, not a license/lease problem, and not a request for user input.
- **eligible_for_next_stage**: **false** (reason: synthesizability, not timing)
- **frozen**: `r0/manifest-r0.json` (`stopped_modifying=true`, `active_commands=0`)

## 1. Lease (re-verified immediately before the TD call)

`r0/preflight-r1.json`, 2026-10-27 07:39:14: TD processes (`pnmain,td,td_commands_prompt,
run,tdsynth`) = **0**; `INT.P4/td` latest write 06:07:52 (**91.4 min** quiet);
`INT.P4/r3` latest 06:08:17 (**91.0 min**); `INT.P4-r3-manifest.json` present
(06:10:50). Verdict `GRANTED_ok_to_run`. `T:` was **not** mapped/remapped (still the
stale b20 target); all script paths are absolute. No other TD session was started.

## 2. What ran

| Step | Quota | Result |
|---|---|---|
| synth `./01_synth.tcl` | 1 of 1 | **FAILED** at elaborate after 6.49 s wall (`HDL-8007`), no gate DB |
| route `./02_route.tcl` | 0 of 2 | not_run (no gate DB; guard would exit `AH_ROUTE_NO_GATE_DB`) |
| 209.6 analysis | 0 of 1 | not_run (needs routed DB) |
| bitgen/CWC/download/Flash/board | 0 of 0 | not attempted |

Command (cwd `r0/td/run-syn1`):
`D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe ./01_synth.tcl`,
hard timeout 1,800 s, actual 6.49 s, not timed out. TD 6.2.3.210850.

## 3. The blocker

```
HDL-8007 ERROR: net 'cmem_lo[15]' is constantly driven from multiple places in
a1_deflate_core.v(673); HDL-5007 another driver at (964)
-> module 'a1_deflate_core' remains a black box -> syn_1 failed (PRJ-5303 / PRJ-8806)
```

`reg [15:0] cmem_lo` (L277) is assigned in the reset-free cmem write-port block
(L673-687, at L679) **and** in the main sequential reset branch (L964, at L1042). One
`reg` may have only one procedural driver. The header comment at L280-285 shows the
intent (merge cmem writes into one block so TD infers ERAM), but the three
write-combine registers were not moved out of the reset process.

Note: `vlog` (ModelSim 10.5b) compiled the same file with 0 errors / 0 warnings. A
compile pass is not an elaboration/synthesis pass - only TD exposed this.

## 4. Gates

| Gate | Required | Measured |
|---|---|---|
| synthesis completes, gate DB + reports exist | yes | **no** |
| routed WNS >= 0 | yes | not evaluated (no DB) |
| hold >= 0 | yes | not evaluated |
| NUM_FEPS = 0 | yes | not evaluated |
| ERAM+CWC <= 300 | yes | not evaluated |
| slice <= 71,680 | yes | not evaluated |
| IO <= 286 | yes | not evaluated |
| STA coverage / check_timing / CDC evidence | yes | absent |
| 0 bitgen | yes | satisfied (never attempted) |

No estimate, no relaxed clock and no exception was introduced to fill a missing number.

## 5. What this does and does not prove

Proves: with the frozen SHAs (`8acd20b2…` core / `4afc26e2…` frame_top), TD 2026.2.3
cannot elaborate this candidate; the reopen path requires an RTL change (out of Line B's
allowed scope) followed by a new TD round with its own quota.

Does not prove: anything about 187.5 MHz timing, Fmax, resources, CDC, bitstream or
board behaviour. The N-side +0.859 % margin remains unproven for implementation.

## 6. Next-step options for the planner (not executed here)

1. New RTL-only task: remove the reset-branch drivers of `cmem_lo`/`cmem_lo_pend`/
   `cmem_lo_addr` (add an explicit reset in the write-port block or drop the reset),
   prove byte-identical 4-frame output in simulation, then a fresh TD quota.
2. Or accept "not synthesizable" as the H-only verdict for this run and record it in the
   dual-verdict as a boundary of the candidate.