# lessons-r0 - T10.ah-honly-td (Line B, r0)

Only reusable root cause -> trigger -> fix -> verification entries; no restatement of
the report.

1. **TD lease evidence is time-varying; a dispatch snapshot is not a lease.**
   Trigger: dispatch recorded `INT.P4-r3-manifest.json` absent; my read-only preflight
   found it present (and INT.P4 latest writes 06:07:52 / 06:08:17) while 0 TD processes
   ran. Fix: treat the lease as a three-part fresh probe taken immediately before the
   first TD command, and treat any changed fact as "planner must re-decide" - never
   self-grant. Verification: `r0/preflight-r0.json` stores the observation with its
   timestamp and explicit `written_by_this_task=false`.

2. **Do not copy the dispatch's port count; read the DUT header.**
   Trigger: dispatch says "7 status buses"; frozen `a1_frame_top` has 8 x 32-bit `st_*`
   + `st_busy` + `dbg[31:0]`. Fix: connect every DUT output and fold all into `st_dbg`
   (XOR), including the H-only `dbg` bus. Verification: `vlog` reports 0 errors,
   0 warnings, 0 undriven-port hits.

3. **Tcl inside PowerShell here-strings must use single-quoted here-strings.**
   Trigger: TD tcl uses `$prj`, `$rd`, `$tf`; a double-quoted PowerShell here-string
   would expand them to empty strings and silently produce a broken script. Fix:
   `@' ... '@` + `[IO.File]::WriteAllText(..., UTF8Encoding($false))` (also avoids a BOM).

4. **Recursive `Get-ChildItem` over `INT.P4/td` is expensive.**
   Trigger: one read-only deep scan (two recursions over a TD project tree) hit the
   180 s shell timeout after printing the facts. Fix: for lease checks prefer
   `Get-ChildItem -File` on the known chain, or `Get-Item` on the manifest plus a
   targeted top-level listing; record the probe time so staleness is visible.

5. **Per-build ModelSim library isolation still applies to a 3-file compile.**
   Trigger: `vlog` needs a writable `work` and an `modelsim.ini`; a shared lib invites
   cross-task contamination. Fix: `r0/lint/{modelsim.ini,work}` copied/created locally,
   `vlib work` then `vlog -sv +define+SIMULATION`; 0.2 s runtime, so the port check is
   cheap enough to always run before freezing a TD scaffold.

6. **`a1_frame_top`'s only RTL dependency is `a1_deflate_core`.**
   Trigger: TD `add_files` list must be complete or synth fails on a black box.
   Fix: grep instantiations (`a1_deflate_core #(` at line 243) - no UART/DDR/camera
   modules are instantiated by the frame top; the 12-file r0 `src/` set is a
   simulation scaffold, not a synthesis requirement. (Recovery round still validates
   this empirically from the first synth log.)

7. **Repo binding needs an explicit negative statement.**
   Trigger: `D:/fpga/repos/ph1p100-pcie-ep-fpga` is authoritative but lacks the H-only
   diff; a "repo path" in a manifest could be misread as the source. Fix: DUT entries
   carry the H-only run's absolute paths plus `repo_copy_used=false`,
   `honly_diff_migrated=false`, `commits/pushes/forks/main_changes=0`
   (`r0/prepared/REPO-BINDING.md`).

Path mismatch to note for the planner: `input-index.md` §3 lists
`T10.a1-eng-freeze/r10/lessons-r10.md`, but the file is not at
`.../r10/td/lessons-r10.md`. It was not needed for r0 and nothing was created to
"repair" the path.
---

# TD execution segment (2026-10-27 07:40, recovery round)

1. **A `vlog` pass does not imply TD can elaborate.** Trigger: ModelSim compiled the
   frozen core with 0 errors / 0 warnings; TD failed in 6.5 s with `HDL-8007`.
   Root cause: `cmem_lo` is assigned in two `always` blocks (write-port L673-687 and
   main reset branch L1042). Fix/verification for a future round: count procedural
   drivers per `reg` before freezing a TD candidate
   (`grep -c "<reg>\s*<=" ` plus block partitioning), or simply run the 1-synthesis
   gate early - it is the cheapest check in this flow (6.5 s, not minutes).

2. **H-only's cmem write-combine is half-moved.** Trigger: the block comment at
   core L280-285 says cmem writes were merged into one reset-free `always` block to stop
   TD expanding `cmem` into 65536 registers, but the three write-combine regs
   (`cmem_lo`, `cmem_lo_pend`, `cmem_lo_addr`) still carry reset assignments in the main
   process. That is exactly the class of defect this TD package exists to find; it was
   invisible to simulation. Lesson: when a comment claims a structural merge, diff the
   assigned signal list of the old and new blocks - do not trust the comment.

3. **A failed synthesis still consumes the quota; the evidence must be frozen as data.**
   Trigger: 1 of 1 synth used, 0 of 2 route, 0 of 1 analysis. Fix: record the sentinel
   values as sentinels (`-99.0`/`-1`/`n/a`) and mark every downstream report `not_run`
   instead of back-filling estimates; state that the process exit code was not exposed
   by `Start-Process` and rely on the script's own terminal marker.

4. **Run each TD attempt in its own directory from the start.** Trigger: running with
   cwd `run-syn1` kept the project, TD logs (`td_20261027_074021.log`) and the run log
   separate from the r0 scaffold; nothing had to be moved afterwards. Fix: copy the
   canonical tcl into the run directory and give every input an absolute path, so the
   same script works from any cwd.

5. **Lease re-verification is cheap if the scan is targeted.** Trigger: r0's recursive
   `Get-ChildItem` probe had timed out at 180 s; this round used
   `[IO.Directory]::EnumerateFiles` + `GetLastWriteTimeUtc` and finished the two trees
   in 0.09 s. Fix: use that primitive for lease freshness checks.
