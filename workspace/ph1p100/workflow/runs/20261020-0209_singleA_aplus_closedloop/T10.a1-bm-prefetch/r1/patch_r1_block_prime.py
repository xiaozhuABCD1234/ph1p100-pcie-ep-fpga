"""T10.a1-bm-prefetch r1: replay r0 candidate de59bddc and fix the block-start
first-literal loss with a single S_WAIT prefetch prime.

Root cause (r1 diagnosis, A1_DEBUG CP0/SCAN trace): with the extra read-data
stage the S_PRE lookup address at pre_cnt=2 is hash3(w0, x1_r, bm_a_rd2) and
x1_r(P2) = bm_a_rd2(P1) = bm[praddr during S_BHDR].  S_BHDR only seeds the *next*
cycle (praddr(P0)=2), so praddr during S_BHDR is the stale value carried from the
previous block (~4805), i.e. an out-of-block read: x1_r(P2) is X in simulation
(block 0 is clean only because reset leaves praddr=0).  The X poisons the htab
read data loaded at P3 -> hp_r/hb_r/hit2 are X at the first S_SCAN cycle ->
cp_en = !hit2 && (pos<blk_n) is X -> the first literal of every block after the
first is never pushed into the candidate bit stream (1199 symbols / 4799 B per
block, E_BAD_ADLER).

Fix (one seed, no timing/cycle change): prime praddr = 1 in S_WAIT, one cycle
before S_BHDR, exactly restoring the base's in-block read (bm[1]) for the
PRE-phase pipeline.  Steady-state S_SCAN/S_EXT alignment, bm prefetch, ext_mis_r,
cycles and all other logic are untouched.
"""
import hashlib
import shutil

F = r"upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v"
SRC = r"workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.a1-bm-prefetch/r0/candidate-bm-prefetch.a1_deflate_core.v"
BASE_SHA = "587ef708967fbe2f3bb27b0bccdbc6af942b61639ad95d8d9ec9eca2b24a2f16"
CAND_SHA = "de59bddc0e4323348e05c3ae1dc16a14e16652da4d34553a3218beb4bf6f840b"

cur = open(F, "r", encoding="utf-8", newline="").read()
assert hashlib.sha256(cur.encode()).hexdigest() == BASE_SHA, "worktree is not the locked baseline"
src = open(SRC, "r", encoding="utf-8", newline="").read()
assert hashlib.sha256(src.encode()).hexdigest() == CAND_SHA, "replayed candidate hash mismatch"
assert "\r\n" not in src

old = """                S_WAIT: begin
                    if (blk_avail && htab_clr_done) begin
                        enc_bank    <= sel_is_b0 ? 1'b0 : 1'b1;
"""
new = """                S_WAIT: begin
                    if (blk_avail && htab_clr_done) begin
                        // r1 (bm-prefetch): prime the bm_a prefetch one cycle
                        // before S_BHDR.  The extra read-data stage makes the
                        // S_PRE lookup address use x1_r, whose value at
                        // pre_cnt=2 comes from the address issued during
                        // S_BHDR; without this seed that address is the stale
                        // previous-block praddr (out-of-block read).
                        praddr      <= 13'd1;
                        enc_bank    <= sel_is_b0 ? 1'b0 : 1'b1;
"""
assert src.count(old) == 1
src = src.replace(old, new, 1)

open(F, "w", encoding="utf-8", newline="").write(src)
print("R1 PATCH OK")
print("new_sha256 =", hashlib.sha256(src.encode()).hexdigest())
print("size =", len(src))
