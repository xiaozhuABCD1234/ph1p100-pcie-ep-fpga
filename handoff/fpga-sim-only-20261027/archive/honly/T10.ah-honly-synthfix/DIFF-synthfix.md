# DIFF-synthfix — T10.ah-honly-synthfix r0

Scope: eliminate the TD-elaboration multi-driver rejection (`HDL-8007` on `cmem_lo[15]`,
`HDL-5007` at the second driver) on the frozen H-only r1 candidate, **without changing
behaviour**. Whitelist per `r1-ruling.md §3.2` / `dev-plan.md §11.2`. 0 TD calls in this
package.

## 1. Files

| File | Frozen input (SHA-256) | Fixed copy (SHA-256) | Bytes | Changed |
|---|---|---|---|---|
| `a1_deflate_core.v` | `8acd20b244b27ddf992432c39bffc34cf00e8394b01443571d9bdb8e3717b17b` | `d2960cfe0111b7b61aff281e3f16427834dda26107f37867d5c7c89ac346aad8` | 85,192 -> 85,221 | **yes, 2 hunks** |
| `a1_frame_top.v` | `4afc26e246fbae4e32c5ab7e88dffb496048d10966c5ee42b290b3e71f60e30a` | `4afc26e246fbae4e32c5ab7e88dffb496048d10966c5ee42b290b3e71f60e30a` | 29,207 -> 29,207 | **no, byte-identical** |

Raw unified diff: `DIFF-synthfix.raw` (git diff --no-index, read-only comparison against
`20261026-231711_fpga-a-plus-h-prototype/T10.ah-honly/r0/changed-src/`).

## 2. Hunk A (edit A, required) — reset merged into the single cmem write-port block

```verilog
     // ... unchanged header comment ...
     wire cmem_flush = cmem_lo_pend && (state == S_DECIDE);
     always @(posedge clk) begin
-        if (cmem_flush) begin
+        if (!rst_n) begin
+            cmem_lo      <= 16'd0;
+            cmem_lo_pend <= 1'b0;
+            cmem_lo_addr <= 12'd0;
+        end else if (cmem_flush) begin
             cmem[cmem_lo_addr[11:1]] <= {16'd0, cmem_lo};
             cmem_lo_pend <= 1'b0;
         end else if (cmem_we_c) begin
```

- +4 / -1 lines in this region (net +4 after removing the three duplicated resets in hunk B).
- **No assignment to the `cmem` array inside the reset branch** — the RAM body is still
  written only from the `cmem_flush` / `cmem_we_c` branches, so RAM inference is untouched
  (`HDL-1007 extracting RAM for identifier 'cmem'` was emitted by TD for the frozen file
  and is unaffected by this edit).
- `cmem_flush` definition, the `cmem_flush`-before-`cmem_we_c` priority, and every other
  line of the block are unchanged.

## 3. Hunk B (edit B, required) — three duplicate reset drivers deleted

```verilog
             rbits_left     <= 13'd0;
-            cmem_lo        <= 16'd0;
-            cmem_lo_pend   <= 1'b0;
-            cmem_lo_addr   <= 12'd0;
             hdr_idx        <= 4'd0;
```

Deleted lines were the main sequential block's reset branch (frozen L1042–1044). Nothing
else in that block was touched. Net diff for the whole file: **+4 / -3 lines**.

## 4. Why behaviour is unchanged

1. Both blocks are `always @(posedge clk)` — the reset is **synchronous** in both the old
   and the new placement (there was no `posedge rst_n` in either). Moving the three resets
   from block 15 into block 9 therefore preserves "on a clock edge with `rst_n == 0`, the
   three registers become 0" exactly.
2. In the frozen file these three registers had **two** drivers (block at L673 and block at
   L964). ModelSim resolves that as last-write-wins, i.e. the reset branch won on a reset
   edge; TD rejects the construct outright. After the fix there is exactly **one** driver,
   and on a reset edge it assigns the same three values (0). Same edge, same values, same
   state machine.
3. Priority inside the single block: `!rst_n` > `cmem_flush` > `cmem_we_c`. The only
   semantic edge this introduces is on a clock edge where `rst_n` is low **and** the
   combinatorial `cmem_flush`/`cmem_we_c` would have been high: the frozen file would still
   have performed the `cmem[]` array write in that same edge (array writes were never
   reset-gated), the fixed file suppresses it. This is unobservable in the verified scope
   because (a) reset discards the whole encoder state (`state`, block pointers, packer) and
   the replay restarts from the stream base, so every `cmem` word is rewritten before it
   can be read, and (b) the frozen TBs assert `rst_n` only during initial reset, before any
   input group is accepted. No byte, counter or cycle number moved (see `result-r0.md`).
4. Nothing else in the file changed: geometry, clock, reset polarity, A1U1 header layout,
   CRC ranges, literal/match/hash logic, emit/replay logic, `cmem_we_c` generation, ROM/RAM
   shapes, `ifdef`/`force`/`initial` — all untouched. `a1_frame_top.v` is byte-identical.

## 5. Multi-driver scan (own scan, `r0/scan/`)

Scanner: `%TEMP%/opencode/ah-synthfix/scan_multidriver.py` (statement-anchored assignment
detection, `//` + `/* */` stripped, `always` block extent by `begin/end` balance; classes:
cross-block, multi-assign, mixed procedural/continuous, force/release).

| Scan | core findings | frame_top findings |
|---|---|---|
| `pre-scan.json` (frozen copies) | 3 cross-block: `cmem_lo` (L679 + L1042), `cmem_lo_pend` (L676/681/684 + L1043), `cmem_lo_addr` (L680 + L1044); blocks 673 and 964 | 0 |
| `post-scan.json` (fixed copies) | **0** (0 cross-block, 0 multi-assign, 0 mixed, 0 force) | **0** |

Matches the planner's independent scan (only these three registers). Hence no scope
extension was needed — see `SCOPE-EXTENSION.md`.
