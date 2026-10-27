# T08.codex-sync-offline partial development — blocked

Developer `/root/fpga_dev_sync_offline`; B02A size 1; round0 independent acceptance has NOT occurred. This is a partial input freeze, NOT ready_for_test. No production integration, camera writes, download, Flash, host traffic or push occurred. Source implementation stopped after the second compiler failure. No third compile is authorized in this dispatch.

## Actual implementation and frozen interface

New sources are confined to production `rtl/ep_side/cam/sync_offline/`, one new `sim/tb/tb_sync_offline.sv`, and this run's `sync-offline/`. Existing B01 files, global filelist, active top, I2C tables, production constraints and IP were not modified. Before/after audits independently hash the 236 B01 manifest entries and the B01 manifest itself. Exact absolute files and SHA256 are in this package manifest.

The new prototype comprises domain reset release, a stable-bus SOF mailbox per source, timestamp pairing, a startup controller and an unconnected small-top diagnostic carrier. All behavior below describes implemented intent; compilation did not pass and none is claimed verified.

| Interface | Implemented contract |
|---|---|
| `clk_ctrl`, `clk_a`, `clk_b`, `rst_n` | Intended 50MHz / independent 187.5MHz / independent 187.5MHz; async assert and two-local-cycle reset release. No SDC has yet been generated or implemented. |
| `start`, `abort_req`, `prereq_ok` | Control-domain synchronous. `prereq_ok` is an explicit offline prerequisite: same mode/exposure/line/frame periods, continuous common reference, confirmed safe physical wiring/electrical behavior and manufacturer timing resolution. TB sets it synthetically. It is not evidence these conditions exist on hardware. |
| `req_valid`, `req_ready`, `camera_id`, `reg_addr[15:0]`, `reg_data[7:0]` | At most one outstanding request. A=0, B=1. Valid and payload remain until handshake; rsp must occur after acceptance. Camera slave bus address/I2C wire engine are outside this package. |
| `rsp_valid`, `rsp_ok` | Control-domain completion/NACK. Accepted-request timeout poisons the transport until global reset; a late reply must not be reused for a new session. Hardware reset/transport flush must accompany any eventual real integration. |
| `ready`, `busy`, `stopped_confirmed`, `error_code[3:0]` | `ready` requires ninth paired frame. Errors 1 prerequisites, 2 NACK, 3 I2C timeout, 4 abort, 5 frame timeout. Cleanup enters standby before S-class Hi-Z writes. A failed cleanup/accepted timeout cannot establish physical stopped state. Logical reset does not reset a real sensor. |
| `sof_a`, `sof_b` | One source-domain pulse per event. Source ordinal increments even on rejected events. Occupied mailbox cannot be overwritten. Stable payload held through req/ack roundtrip. Rejected count is delivered on the next successfully accepted event; it is not an immediately asynchronous status bus. |
| Pair diagnostics | Common control-clock timestamp, signed modular `time_b-time_a`, pair window, source sequence ordinals, missing counters, cumulative mailbox rejected counts, relock count. Pairing is by bounded time window and records both ordinals; equal ordinals are not assumed after a missing source frame. Difference is valid only for distances below 2^31 cycles. CDC phase latency adds measurement uncertainty. None measures exposure. |

Whitelist: `3000` standby (local original table has 01 and local start table has 00), `3002` XMSTA, `3003` XMASTER, `30C0`=2A, `30C1` low four bits 0F/00. Original sources read only: `ui_imx415_reg.v` lines 49,51,52,108,109 and `ui_cfg_imx415.v` `REG_DATA_ST` table. This is not a full mode driver. Existing evidence's S-class/standby restrictions and unresolved manufacturer XMASTER reset ordering remain applicable.

Startup transaction intent: A standby/stop/Hi-Z; B standby/stop/Hi-Z/slave/output-selection; A master/output-selection/drive while in standby and after B Hi-Z ACK; B exits standby, waits at least N; A exits standby, waits at least N; A XMSTA start. Default N=1,200,000 control cycles, 50MHz ×24ms. Default warmup=8. TB N=12, timeout=40, frame timeout=120, pair window=15 are synthetic accelerated test values and do not replace production defaults or establish a real sensor window.

## Commands actually executed and failures

Python 3.11 executable: `C:/Program Files/Python311/python.exe`; compiler prints ModelSim Intel FPGA 10.5b, 2016.10. Read/search commands used Start-Job / Wait-Job -Timeout60. vlib deadline 60s, vlog/vsim deadline 300s are implemented with owned Popen PID plus wait(timeout) and owned taskkill tree on timeout. No deadline was reached. The process-owned T: alias was removed in finally; the pre-existing unrelated R: alias was left intact. Logs include exact argv/cwd/PID/deadline/elapsed/exit_code. No environment dump was sent externally.

1. From actual project root, `python sync-offline/scripts/run_g1.py positive` (full script path in logs): vlib exit0; vlog exit7. `g1/positive/vlog.log` records sqlite open failure on non-ASCII pathname before RTL compilation. This was the first actual compile attempt and is retained.
2. After the specific ASCII T: alias correction, `python sync-offline/scripts/run_g1.py positive positive-r2`: vlib exit0; vlog exit2. `g1/positive-r2/vlog.log` records exactly two vlog-13069 errors at new `sync_offline_top.v` lines19/20, near `)`. Positional output disconnects were written as `()`; this is invalid syntax. The compiler proceeds to list the other five modules; that is not a passing compile.

The corrected-path invocation is the sole retry of the same compile operation, despite its separately retained output directory. Attempts=2; retries_used=1; retries_max=1. No vsim invocation, no positive marker, no negative control, no STA/CDC/area implementation or independent tester report exists. TD attempts=0. No G2 Tcl/SDC/ADC was completed. The existing running TD GUI was not terminated or used.

## Planned but NOT executed checks / remaining risks

TB contains a synthetic transaction scoreboard, stalled request check, busy start, >=N waits, first8/ninth frame boundary, NACK cleanup, poisoned accepted timeout, missing source/relock, event overrun, timestamp wrap, abort and reset recovery. `run_g1.py negative` creates only an isolated copy changing B Hi-Z 0F to00 and requires intended order rejection; it has NOT run and is not evidence. The TB itself and its assumptions remain unverified. N-1 exact stop, source sequence counter rollover, fault at each phase and synchronous responses require subsequent review. The source RTL may contain further functional or engineering defects.

CDC review is NOT complete: request/ack synchronizers and held bundle are designed but not checked in final placement. A future G2 must preserve all three clocks at 20ns/5.333ns/5.333ns, prove every crossing is confined to mailbox/reset release, add bounded bundle/first-stage exceptions with explicit constraint coverage, and report same Routed DB setup/hold WNS>=0/TNS0/all clock groups, resources and source preservation. Broad timing cuts cannot stand in for this proof. The new smalltop diagnostic mux is only a partial carrier, not a built candidate.

G0 partial/fail (known syntax); G1 blocked; G2 not_run/blocked by compile cap. G3/G4 not_applicable per planning: isolated prototype not wired to active top or sensors. G5 not_applicable/no publishing. Parent T08 hardware/exposure synchronization is unproven. workflow README5.1: input SHA freeze yes; negative evidence missing; native completion/STA/CDC/resource missing; CWC not applicable to this offline nondebugger prototype; independent integrated review not run; no current downloadable artifact; push prohibited by user. No engineering gate is waived.

## Minimal recovery and rollback

Stable problem `T08.codex-sync-offline:LIMIT_REACHED:offline-tb-compile`. Original planner must preserve attempts=2 and round0-not-occurred. The immediate technical correction is to replace the two invalid positional output placeholders using named `.src_busy()` connections (or valid empty positional syntax), but this was NOT applied after the limit. Only genuine new user input/condition and an explicitly frozen additional finite authorization may resume the original developer. Then review all unverified RTL/TB, run the authorized compile/simulation/negative control and G2 without touching B01.

Resume from this manifest/development-result and original task-T08-sync-offline.md, original planner `/root/fpga_planner_b2`, original developer `/root/fpga_dev_sync_offline`. No independent tester should be spawned for this blocked partial candidate. Rollback requires leaving new isolated files unreferenced; no file deletion or active top edit is necessary.

DeepSeek bounded auxiliary task c3b9c99a37e249e89d35f65d17804dbc received only the 14-entry mapping, 3216 total API tokens. Its proposed root `expected_function.sv` write was explicitly denied as outside T08 scope, and actual denial returned once for its call_id. Worker then completed with text. Reviewed values informed the TB table; worker did not execute commands, access project files or perform verification.
