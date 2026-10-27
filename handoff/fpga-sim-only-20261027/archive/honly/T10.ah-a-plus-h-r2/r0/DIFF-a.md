# DIFF-a — T10.ah-a-plus-h-r2 r0 (A added to the frozen H-only r1 candidate)

DUT base (read-only reference, unchanged in the H-only run):

- `a1_deflate_core.v` = H-only r1 `8acd20b244b27ddf992432c39bffc34cf00e8394b01443571d9bdb8e3717b17b`
- `a1_frame_top.v` = H-only r1 `4afc26e246fbae4e32c5ab7e88dffb496048d10966c5ee42b290b3e71f60e30a` (**byte-identical here — no edit**)

Machine diff: `out/DIFF-a.raw` (`git diff --no-index --unified=3`), 8 hunks, +173 / −122 lines,
all in `a1_deflate_core.v`. `tb_*` files are frozen copies (TB-only SHA recorded in the manifest).

## 1. What A does (scheduling only)

A = **2-position literal scan** (two adjacent positions hashed/compared per cycle, dual-port hash-table
read) + **dual-symbol packer** (two symbols per cycle only when the combined code length is ≤16 bit).
The output port stays `OUT_BYTES=2` (≤2 B/cycle); nothing is widened.

Every cycle the scan now evaluates **two adjacent positions**:

| lane | position | window bytes | hash-table entry must reflect |
|---|---|---|---|
| A | `pos+1` (= H's stage-1 position) | `(w1, w2, x1_r)` in `S_SCAN`, `(w0, w1, x1_r)` on the last `S_PRE`/`S_REPOS` cycle | all inserts through `pos` |
| B | `pos+2` | `(w2, x1_r, bm_a_rd2)` | all inserts through `pos+1` |

The stage-2 register set (`hp/hf/hf1/h4/hb/rng1/s1_ok/s1_last`) is loaded from **lane B** when a pair
is committed (next `pos` = `pos+2`) and from **lane A** otherwise — i.e. always from the lane whose
position the next cycle will decide. `dual_step` (the pair commit) requires ALL of:

```
state==S_SCAN && !hit2 && pos<blk_n && !lit_ge && (pos+1)<blk_n
              && !hit_a_w && w0<144 && w1<144 && !lit_ge2
```

`hit_a_w` = the unregistered lane-A hit (`s1_bytes && rng1 && s1_ok`), i.e. exactly the predicate H
registers into `hb_r/rng1_r/s1_ok_r`. `lit_ge2` = `(cand_bits+8) >= thresh_lit`, which is H's literal
abort guard evaluated at `pos+1` (`thresh_lit == stored − 8·(n−(p+1))`).

On a pair commit: `stat_literals += 2`, `pos += 2`, `rem_blk −= 2`, `thresh_* += 16/16/8/7`,
`raddr/p3_r/s1_pos_r += 2`, the window shifts by two bytes, and the candidate packer receives **one
16-bit symbol** `{litcode(w1), litcode(w0)}` (`cp_nbits = 16`, low byte = first stream byte, so bit
order and the byte stream are unchanged). The existing 3-stage packer already handles 16-bit symbols:
`p0_nbits=16`, `p1_pshift` ≤ 23 bit, `ctot ≤ 23`, `nbw=2` (one 16-bit cmem word per cycle, `cacc`
keeps ≤7 bits), and `pbit_off` is unchanged because 16 mod 8 = 0.

## 2. Required hazard handling (proved by construction, then by byte-exactness)

**(a) first literal ends the block ⇒ second position must not enter the old block.**
A pair is only taken when `(pos+1) < blk_n` and `!lit_ge`; therefore the last position of a block
(`s1_last_r`, `pos+1 >= blk_n`) and the abort position are always handled by the **single** path,
which then goes to `S_EOB`/`S_DECIDE` exactly as H. The second position of a pair is therefore always
inside the same block; when it is the last one, the next cycle's `pos >= blk_n` ends the block (H
reaches the same token stream one cycle later). No literal is ever written into a finished block.

**(b) first literal, second position starts a match ⇒ commit only 1 literal.**
`hit_a_w` is the lane-A hit for `pos+1` evaluated *in the same cycle*; the pair is refused when it is
set, only `w0` is packed, and the next cycle's `hit2` is the registered lane-A result for `pos+1`, so
the match path starts at `pos+1` with `hp_r/hf_r/h4_r` = lane-A entry fields — bit-identical to H.
The p+2 insert is likewise gated by `!hit_a_w`, so a position inside the match is never inserted.

**(c) hash-table state.** The table visible at a cycle contains all inserts through `pos` (H's
stage-1 view), because this cycle's `pos+1` insert is applied on the clock edge. Lane A therefore
needs no bypass; lane B needs exactly the same-cycle `pos+1` write-first bypass (`byp_b`, data =
`s1_ins_data`, b3 = `bm_a_rd2`), which reproduces H's "read for `pos+2` issued at the `pos+1` insert
cycle". The second (p+2) insert is written **only on a pair commit** and carries exactly the values H
would write one cycle later (`{tag, pos+5, pos+2, w2, x1_r, bm_a_rd2}`, b3 = `bm_a_rd`), gated by
`pos+2 < lim2` — identical data, identical gate, one cycle earlier; all reads in between already see
"through pos+1" as shown above. On a bucket collision the later position (p+2) wins, which is the same
final state as inserting p+1 then p+2 in order.

**(d) window/prefetch alignment after a 2-position jump.** A pair consumes two bytes of the bm_a
stream in one cycle: the bm_a port presents `praddr+1` (= bm[pos+7]) into `bm_a_rd`, and bm[pos+6]
(= `praddr`) goes straight into `bm_a_rd2`; the window then shifts by two (`w0<=w2, w1<=x1_r,
w2<=bm_a_rd2, x1_r<=bm_a_rd`). The next cycle's flops are exactly `(pos+2 … pos+6)` and `praddr`
is re-seeded to `raddr+3`. Match-hit cycles are unaffected (`dual_step` implies `!hit2`, so the
existing `bm_hit_a`/`p3_r+1` prefetch is untouched).

**(e) everything else unchanged.** Literal codes (`lit_rev`), candidate selection (single entry,
same hash, same `lim2`/`MAX_DIST`), costing/abort thresholds, stored/fixed decision, block
boundaries, Adler-32, trailer, header layout, geometry, clock and reset are the H-only code.
`a1_frame_top.v` is not modified.

## 3. Implementation structure (prototype choice, not measured)

The hash table moved from "1 registered read port + registered bypass" to **2 combinational read
ports + 2 write ports** (the 2nd write is a second procedural write in the same always block, later
position last), and the bm_a window array gained a second read (dual cycles). This is a simulation
prototype of the A schedule; the ERAM/timing consequences are **not** measured in this task
(G2 = not_applicable, 0 TD) and would require re-pipelining before any implementation claim.

## 4. Observable counter difference

`stat_literals` can differ from H-only in blocks whose candidate aborts (stored path): the pair may
commit the literal at which H's guard fires before the abort is taken. The byte stream cannot change
(the stored path emits `bm`, not the candidate) and byte-exactness is proven on 4 bench streams,
the 4-frame header/CRC/length/last byte and independent zlib decoding. Probe/4-frame literal,
match and abort counts are recorded in `out/` for the tester.
