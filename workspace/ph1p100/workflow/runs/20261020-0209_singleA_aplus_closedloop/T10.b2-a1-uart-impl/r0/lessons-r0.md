# T10.b2-a1-uart-impl r0 lessons

## Root cause
TD synthesis treats multiple procedural drivers on the same `reg` as HDL-8007 (fatal),
while ModelSim accepted the same P1 file: `camera_a1_uart_top.v` assigns
`raw_rd_close_r` (and `raw_rd_open`, `raw_rd_take`) in both the raw-skid always block
(reset/default, lines 162/166-167) and the feeder/sequencer always block
(305/310/317/331/364/368). P1's simulation evidence was obtained with the ambiguous file;
P2 is the first TD elaboration of that exact file.

## Trigger / detection
Any P2 board build of the frozen r3 A1 top. TD reports it immediately at read_design
(5 s), then black-boxes `camera_a1_uart_top`; `wait_run syn_1` returns "run failed",
and the subsequent phy wait never sees `.opt_route.begin.f` (do not wait 30 min again:
check `syn_1/.read_design.error.f` / `run.log` first).

## Correct fix (for the authorized repair round)
In the skid always block, delete only the duplicate assignments:
`raw_rd_open <= 1'b0; raw_rd_close_r <= 1'b0; raw_rd_take <= 1'b0;` in the reset branch,
and `raw_rd_open <= 1'b0; raw_rd_take <= 1'b0;` in the else branch. Leave the sequencer
block as the single owner. No protocol/frame/CRC/DEFLATE change; re-run the P1 8x2/64x8
(micro) sim to re-bind the evidence hash.

## Verification entry
- `td/syn_failure_excerpt.txt` (exact HDL-8007/HDL-5007 lines).
- Re-run `01_build.tcl` after the repair; expect `P2_SYN_*` markers then route.
- P2 files statically compile clean with ModelSim `vlog -lint` (0/0).

## Process notes
- The r4 manifest hash table (`e88de0910ff0`, `5196c07aed52`) contradicts the r3/r4
  narrative and no such files exist; always verify full digests, not prefixes, before
  binding P1 evidence.
- TD command timeout: the build tcl waited 3000 s for opt_route after synth had already
  failed. Add a synth-status fail-fast (`if {[file exists .../.read_design.error.f]}`)
  before launching phy.
- Dev call budget was exceeded (~67/60) while diagnosing; next time read the P1 top's
  mutli-driver risk (TD vs ModelSim) before starting the TD session.
