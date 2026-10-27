# result-blocked-r0 - T10.ah-honly-td (Line B)

- **status**: `blocked`
- **reason_code**: `DEVICE_MISSING`
- **semantics**: the exclusive TD resource is busy / the TD lease is not granted to this
  task. This is **not** a missing user input, missing file or missing permission.
- **round**: r0 = TD-free preparation only (dispatch instruction). 0 TD invocations.
- **frozen**: `r0/manifest-inputs-r0.json` (`stopped_modifying=true`, `active_commands=0`).

## 1. What was actually done

| # | Item | Result |
|---|---|---|
| 1 | Re-hashed DUT + all templates, wrote repo binding | `a1_deflate_core.v` 85,192 B `8acd20b2…b17b`; `a1_frame_top.v` 29,207 B `4afc26e2…e30a`; manifest-r1 `f752ae09…`; `r0/prepared/REPO-BINDING.md`; raw table `r0/prepared/readonly-inputs-r0.json` |
| 2 | Isolated TD scaffold (not executed) | `r0/td/a1_ah_eng_top.v`, `a1_ah_small_top.sdc`, `01_synth.tcl`, `02_route.tcl`, `03_2096_analysis.tcl`, `README.md` |
| 3 | One port-binding compile check | `vlib` + `vlog -sv +define+SIMULATION` on wrapper + 2 frozen candidates: **Errors 0, Warnings 0, undriven-port warnings 0**, rc 0/0, 0.24 s / 0.19 s. No `vsim`, no testbench. Logs in `r0/lint/`. |
| 4 | Lease preflight (read-only) | `r0/preflight-r0.json` |
| 5 | Freeze | this report, `r0/lessons-r0.md`, `r0/manifest-inputs-r0.json` |

## 2. Lease evidence (read-only, no TD call, no drive mapping)

- TD processes (`pnmain,td,td_commands_prompt,run,tdsynth`): **0** at probe time.
- `20261026-2138_fpga-integrated-delivery/INT.P4/td` latest write: **06:07:52**
  (`README-EVIDENCE.md`); `INT.P4/r3` latest write: **06:08:17**.
- `INT.P4-r3-manifest.json`: **present at preflight**, although the dispatch recorded it
  as absent. The lease state therefore changed between dispatch and preflight.
- `T:` still points at the finished b20 TD dir (stale); it was only read; **not** mapped,
  remapped or released. `Y:` = project root, unchanged.
- **Decision**: r0 stays TD-free exactly as dispatched. Granting TD to this task now
  requires the planner to re-verify all three dev-plan §8 conditions; this task does not
  self-grant, does not wait/poll/sleep and does not retry.

## 3. Port/clock binding of the scaffold (observed, not a functional claim)

- DUT `a1_frame_top` was read only to bind ports: it exposes 8 x 32-bit `st_*` status
  buses + `st_busy` + `dbg[31:0]` (the dispatch text said "7 status buses"). The wrapper
  connects **all** of them and folds them with `st_busy` and `dbg` into `st_dbg`, so no
  output is undriven (compile shows 0 undriven warnings).
- Wrapper port list is exactly the dispatched one: `clk, rst_n, in_pix[39:0], in_valid,
  in_ready, in_sof, prep_en, pred_en, abort, out_data[31:0], out_valid, out_ready,
  out_keep[3:0], out_last, frame_commit, frame_abort, st_dbg[31:0]`.
- SDC: one `create_clock -name clk -period 5.333 -waveform {0.000 2.667} [get_ports clk]`,
  no false_path / multicycle / clock group. Block-level IO unconstrained = recorded gap.
- The wrapper is build-only and is **not** a candidate RTL file; candidate SHAs are
  unchanged (`stopped_modifying`).

## 4. Explicitly NOT done / NOT proven

- No `td_commands_prompt.exe`, `td.exe`, `run.exe`, Tcl flow, synthesis, place & route,
  STA, resource, CDC or 209.6 analysis. G2 = `not_run`.
- No bitgen/CWC/download/Flash/board/COM/JTAG/RK/network; no git commit/push/fork.
- No DUT function, no timing number, no resource-fit statement, no eligibility statement.
- No file written outside `T10.ah-honly-td/**`; no deletion of any kind.
- One read-only deep scan of `INT.P4/td` + `INT.P4/r3` exceeded the 180 s shell timeout
  after printing all needed facts; it launched nothing and wrote nothing outside this
  task directory (recorded in `preflight-r0.json.notes`).

## 5. Recovery entrance (dev-plan §8)

```
恢复：D:\fpga\ph1p100\workflow\runs\20261027-055621_fpga-honly-td-and-ah；本轮目标：恢复 T10.ah-honly-td 的 TD 执行（先核 TD 租约）；Line A 按既有状态不动
```

Recovery must first re-verify: r3 manifest frozen (or user says TD idle), 0 TD
processes, no INT.P4/td or INT.P4/r3 write in the last 20 min. Then run
`01_synth.tcl` (1 synth), conditionally `02_route.tcl` (<=2 route), optionally
`03_2096_analysis.tcl` (analysis-only). Budget: 1 synth + <=2 route + 0 bitgen.