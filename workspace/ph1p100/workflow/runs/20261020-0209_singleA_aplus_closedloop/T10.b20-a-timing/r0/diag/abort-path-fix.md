# diag -- abort -> smem read-address cone (T10.b20-a-timing r0)

## 1. Pre-fix structure (b19, `a1_frame_top.v` sha256 `0064607a...27109`)

The frame-level abort branch tore down the whole frame -- including the drain FSM --
in the abort cycle itself:

```verilog
if (frame_active && (abort || proto_abort) &&
    !(svalid && out_ready && slast && !killed)) begin
    frame_abort_r <= 1'b1;
    killed        <= 1'b1;
    frame_active  <= 1'b0;
    istate        <= I_ABORT;
    dstate        <= D_IDLE;        // drain FSM
    dblk          <= 16'd0;         // drain FSM
    bank_busy     <= 2'b00;         // drain FSM / address seeding
    ...
end else begin
    ...normal input path + drain path...
end
```

Because the raw `abort` input is a term of the branch select, every register assigned
inside that branch -- and every register that merely "holds" there -- gets an
`abort`-controlled mux in front of its D input. The ERAM read address
(`rd_addr`, absorbed into the ERAM as `smem.addrb[*]`) is a function of
`dstate`, `bank_busy`, `primed`, `n_samp`, `rd_s`; with `rtl retiming on` (frozen
b19 setting) the drain-side register boundary was retimed so that the raw abort term
ended up in the combinational cone of the ERAM address pin.

b19 routed evidence (`..\..\T10.b19-cam-a\r0\td\routed_timing.rpt` L105-185):

```
Slack -0.098  Begin u_a1/a1_abort_reg_syn_6.clk
              End   u_a1/u_a1/smem_syn_29.addrb[10]
Data 4.663 ns (cell 1.636 / net 3.027)  Logic 6 (LUT6x2 LUT4x2 LUT3x1 ERAM)
Second: -0.091 -> smem_syn_29.addrb[12]; 10 violated clk_a1 endpoints total
```

## 2. Fix (b20, `a1_frame_top.v` sha256 `cda28c94...2160c`)

One new 1-bit register `abort_d` carries the frame-level abort to the **drain side
only**, one cycle later. The raw abort remains combinational for everything the
protocol needs (`frame_abort`, `killed`, `frame_active`, `istate`, `core_abort`,
`in_ready`, the input-side counters and `scnt`).

```verilog
abort_d <= frame_active && (abort || proto_abort) &&
           !(svalid && out_ready && slast && !killed);      // same select as the branch

if (frame_active && (abort || proto_abort) && !(...)) begin
    frame_abort_r <= 1'b1;
    killed        <= 1'b1;
    frame_active  <= 1'b0;
    istate        <= I_ABORT;
    blk_idx       <= 16'd0;
    row_in_blk    <= 16'd0;
    grp_in_row    <= 16'd0;
    scnt          <= 2'd0;
    first_byte    <= 1'b0;      // no sop into the already-aborted core
    // dstate/dblk/bank_busy are NOT touched here any more
end else begin
    ...
    if (abort_d) begin          // one cycle later, registered control
        dstate    <= D_IDLE;
        dblk      <= 16'd0;
        bank_busy <= 2'b00;
    end else case (dstate)
        ...unchanged drain FSM...
    endcase
end
```

Diff: `r0/diag/a1_frame_top-b20.diff` (b19 -> b20), 27 added / 4 removed lines, all
inside the abort/drain region; no port, no `ifdef`/`force`, no reset/CRC/stat/output
logic touched. `r0/check_merge_b20.py` C20 re-extracts 22 frozen anchors from both
files and requires equality.

Line ranges in `r0/changed-src/a1_frame_top.v`:

| lines | content |
|---|---|
| 110-119 | `reg abort_d;` declaration + rationale |
| 301 | `abort_d <= 1'b0;` in reset |
| 335-339 | `abort_d` next state (same select as the abort branch) |
| 340-355 | immediate abort branch: protocol/input teardown only |
| 458-468 | drain path: `if (abort_d) ... else case (dstate)` teardown |

## 3. Cone-break argument

* The ERAM read-address register (`smem.addrb[*]`) is driven from `dstate`,
  `bank_busy`, `primed`, `n_samp`, `rd_s`, `gcnt`, `rd_bank`, `core_in_ready` -- all
  registers.
* Every drain-side register's next state now depends on `abort_d` (a register), never
  on `abort`, `proto_abort` or `core_abort`. The raw abort still feeds only
  `frame_abort_r`, `killed`, `frame_active`, `istate`, the input counters, `scnt`,
  `first_byte` and `abort_d`.
* Those immediate registers drive primary outputs / protocol fields
  (`frame_abort`, `out_last`, `frame_commit`, `st_busy`, `in_ready`, `out_keep`,
  `dbg`) and are therefore anchored; the drain cluster is separated from the raw
  abort by the `abort_d` flop.
* A retiming sweep would have to move `abort_d` (multi-fanout, feeds the dstate /
  bank_busy / primed / rd_* muxes) into the address cone; it would still be a
  register boundary. Post-route proof: the routed timing report must contain zero
  paths launched by `a1_abort_reg` into `smem*.addrb*`; `r0/cone_check_b20.py`
  additionally walks the routed netlist (LUT-only combinational reachability) from
  the `a1_abort_reg` Q net to every `smem*.addrb` pin.

## 4. Accepted latency / semantics

* Normal frames (no abort): `abort_d` stays 0, the drain case is executed exactly as
  in b19 -> cycle-identical. Proof: T1 `cycles = 37,465,298` exact, `cmp_words
  = 648,677`, `cmp_writes = 81,085`, `read_words = 129,600`, `exp_bytes = 2,594,706`.
* Aborted frame: `frame_abort`/`killed`/`frame_active`/`istate` are unchanged and
  immediate; only the drain teardown (`dstate`/`bank_busy`/`dblk`) lands one cycle
  later. The aborted frame's data is discarded, no block is published, no CRC/stat
  register is updated by the extra cycle, and the next frame cannot start before the
  teardown (istate = I_ABORT for that cycle). `first_byte` is cleared so the core
  (already aborted in the abort cycle) cannot accept a stale SOP byte in the extra
  cycle.
* T4 (`drop-1-R`, 3-frame middle retry) proves the abort-recovery path end to end:
  `timeout=retry=1`, `giveup=0`, `exported=1/3`, four CRCs + zlib per frame, and a
  cycle delta within the accepted +0..+16.

## 5. Post-fix routed path

Single route attempt (`r0/td`, `P2_BUILD_DONE`, `P2_ROUTED_SWNS=0.012 ... VIOL_EP=0`):

```
SWNS +0.012  STNS 0.000  HWNS +0.020  HTNS 0.000   0 violated endpoints, 26,698 total
worst clk_a1: u_a1/u_a1/u_core/sdata_ptr_reg[1]_syn_2.clk
           -> u_a1/u_a1/u_core/state_reg[4]_syn_102.imb   (+0.012 ns)
```

* The routed timing report contains **0 paths** beginning at `a1_abort_reg` and
  ending at `smem*.addrb`; with 0 violated endpoints the violated-path list is
  empty. The three b19 abort paths (-0.098 / -0.091 / -0.059) are gone, and the
  synthesis worst-10 no longer contains `a1_abort_reg` either.
* Synthesis moved from `SWNS +0.127` (b19) to `SWNS +0.204`, i.e. the abort cone
  stopped being the critical cone.
* Routed result is a **thin-margin caveat** (`WNS +0.012`, inside +0.003..<+0.05):
  it clears the frozen gate for bitgen/board but is not a robust-timing claim.
* Supplementary netlist walk (`cone_check_b20.py`, `cone_trace_b20.py`): the
  LUT-agnostic reachability still reaches `smem*.addrb` from the abort net (4-hop
  LUT route via `istate`/`hdr_idx`/`rd_addr` LUT cells). That walk follows any
  combinational output of a reached cell regardless of the LUT function, so it is
  a conservative upper bound and is **not** evidence of a real path; the LUT-level
  dependency decoder was validated negative on the b19 netlist (which certainly had
  a path), so it is not used either. The authoritative cone evidence for this
  candidate is the routed STA: no such path in the reported worst endpoints and
  zero violations.

