# T10.b17-paxi-native r0 — lessons

## 1. Why the b15 simulation stayed green while the board failed

The b15 model made three assumptions that the native PAXI port does not share:

1. **Address unit**: it indexed memory with `awaddr[18:0]`/`araddr` as if the
   port address were a 256-bit word index.  The bridge forwarded the internal
   word index unchanged, so a “correct” model test never saw a byte-unit
   address.  The vendor `paxi_stg_cmd_gen` and `ddr_frame_store` both emit
   `{word_index,3'b000}`; the audit's conditional models reproduced wrong
   readback as soon as the native unit was assumed.
2. **Write mask**: it wrote the whole word regardless of `wstrb`.  b15 drove
   `32'hFFFF_FFFF` (all-ones) while the native full-word write is mask 0, so a
   real byte-enable interpretation would have dropped every write.  The model
   could still decompress and CRC-PASS from its own memory.
3. **Command concurrency**: the model had independent `awready`/`arready`, and
   the b15 write and read engines could handshake AW/W and AR in the same
   cycle.  The native mtest uses one `cmd_type` per cycle and gates on
   `awready & arready`.  No b15 test could observe a same-cycle command.

The common failure mode was therefore **self-consistent simulation against a
model that implemented the wrong contract**, not a missing test count.

## 2. What this package changed and how each fix is falsifiable

| contract | fix | test that would fail without the fix |
|---|---|---|
| address ×8 | bridge AW/AR `{word[23:0],3'b000}` only at the PAXI output | 16-word test asserts AW/AR = 0,8,…,120; b15 bridge negative control drives 0,1 and is counted as `bad_low3=1` |
| mask=0 | `paxi_wstrb=32'h0` | all-ones overwrite keeps the first value; b15 bridge negative control has `mask=2` and word 0 does not read back |
| single command | `ALLOW_CONCURRENT=0`, write-priority `rd_req`, AR held in W_IDLE | clean chain runs report `same_req=same_hs=0`; `ALLOW_CONCURRENT=1` control reports `same_req=1/same_hs=1` |

## 3. Debug procedure that paid off

- A **16-word write-stop-read** isolated the boundary before the camera/A+
  chain: it immediately exposed the model's address unit and mask semantics
  and gives a 2-second regression for every future bridge change.
- The model counters are deliberately independent of the bridge counters, and
  the TB also watches the PAXI pins directly.  A single model bug cannot make
  both agree.
- The status packet now carries `last_issued_ar_addr` / `timeout_ar_addr` and
  same-cycle counters, so a future board failure has the failing native
  address instead of only a cumulative AR−R difference.

## 4. If the board still misses one R per frame

Do not change CRC/compression/retry/FIRST-R counters.  Use the v6 evidence:

- `timeout_ar_valid=1`, `timeout_ar_addr`/`low3` = the exact failed native AR;
- `last_issued_ar_addr` first/last and `same_aw_ar_cnt`/`same_w_ar_cnt` = 0
  would exclude a command-acceptance collision in this candidate;
- `diag_flags[3]`/`[4]`/`[5]` = 0 excludes OOB/low3/mask misuse;
- `inflight_state` at rest distinguishes a stuck `ar_busy` from a DDR-ready or
  RF-empty stall.

Only then move to DDR MC/IP read-response investigation (new run needed).

## 5. Process lessons

- `vsim -modelsimini` on Windows requires forward slashes; backslashes fail
  with `vsim-7` before loading the design.
- Three concurrent `vsim` instances on this ASE seat caused a license watchdog
  to kill the two long full-frame runs (`Exiting VSIM license process`).  Two
  concurrent instances are stable; the full S1/S2 rerun with only two seats
  completed.
- TB handshakes must sample at the **posedge** and deassert at the next
  negedge; a negedge polling loop can hold a valid for two posedges and push a
  duplicate FIFO entry.
- A model that forbids `awready & arready` must key the exclusion on the
  actual `AW` acceptance, not on the idle `awready` level, otherwise AR can
  starve forever.
- `a1_uart_export.sts_ext` must be widened in the **port list**, not only in
  the internal snapshot registers; otherwise fields #60..#67 silently read 0.
- The first TD synthesis was interrupted at the run-manager/gate-db handoff
  (likely a shared license/resource event while three simulators were active).
  Re-running synthesis once with a guard that waits for `a1_board_gate.db`
  before launching route produced a clean run; always gate route on the DB
  artifact, not only on `wait_run` status.
- The routed candidate is **1 ps short** of the +0.003 ns floor (SWNS +0.002).
  The worst path is in the frozen `a1_deflate_core`, so the permitted v6-only
  pipelining fix does not apply; do not “round up” or run bitgen.  A future
  package needs explicit timing authority (e.g. a new route attempt with a
  permitted netlist perturbation), not a threshold change.
