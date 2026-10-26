"""T10.a1-bm-prefetch r2 (corrected): restore the r0 REPOS seeds and add the
missing one-cycle history seed in S_MLEN.

Trace evidence (odd20x5_p1d1): with the shrunk seeds the reposition hit at
SCAN(19)/SCAN(42) was still missed (hash3 second byte wrong) - w2 showed
bm[P+1] instead of bm[P+2].

Address algebra for the 2-stage read (A(k) = bm_a address in cycle k,
bm_a_rd2(k)=bm[A(k-2)], x1_r(k)=bm[A(k-3)]), reposition at pos = P:
  x1_r(R2)        = bm[P+1] -> A(M)  = P+1   <- S_MLEN seed (added here)
  bm_a_rd2(R2)    = bm[P+2] -> A(R0) = P+2   <- S_MCHK seed pos_next_r+2 (r0)
  x1_r(R3)        = bm[P+2] -> A(R0) = P+2
  bm_a_rd2(R3)    = bm[P+3] -> A(R1) = P+3   <- R0 seed pos+3 (r0)
  x1_r(SCAN0)     = bm[P+3] -> A(R1) = P+3
  bm_a_rd2(SCAN0) = bm[P+4] -> A(R2) = P+4   <- raddr+3 chain (r0)
  bm_a_rd2(SCAN1) = bm[P+5] -> A(R3) = P+5   <- raddr+3 chain (r0)
The 1-stage base got x1_r(R2) from A(R0); the extra stage needs A(M) instead,
i.e. one more cycle of lead time that only S_MLEN can supply (P = pos + len_r).
"""
import hashlib

F = r"upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v"
IN_SHA = "6840162202bf9b2875ff36e15286603f825529e421d52200050a6e099f2669ea"

src = open(F, "r", encoding="utf-8", newline="").read()
assert hashlib.sha256(src.encode()).hexdigest() == IN_SHA, "worktree is not the r2 candidate"

# 1) restore the r0 REPOS seeds (undo the r2 shrink)
old1 = """                            // r2: keep the base REPOS re-prime (A(M)=pos+1); the
                            // +1 prefetch shift is applied from R1 on (raddr+3).
                            praddr <= pos_next_r + 13'd1;  // seed bm_a = bm[pos+1]
"""
new1 = """                            praddr <= pos_next_r + 13'd2;  // seed bm_a_rd2 = bm[pos+1]
"""
old2 = """                            praddr <= pos + 13'd2;
"""
new2 = """                            praddr <= pos + 13'd3;
"""
for o, n in ((old1, new1), (old2, new2)):
    assert src.count(o) == 1, (o, src.count(o))
    src = src.replace(o, n, 1)

# 2) add the one-cycle history seed in S_MLEN: A(S_MCHK) = pos_next + 1
old3 = """                S_MLEN: begin
                    dval_r         <= dval;
"""
new3 = """                S_MLEN: begin
                    // r2 (bm-prefetch): the 2-stage bm_a prefetch needs one more
                    // cycle of history before the S_REPOS re-prime.  Issue the
                    // pos+1 address now so that the address presented in the
                    // S_MCHK cycle is pos_next+1, exactly the value the 1-stage
                    // base obtained from its S_MCHK seed.
                    praddr         <= pos + {4'd0, len_r} + 13'd1;
                    dval_r         <= dval;
"""
assert src.count(old3) == 1, src.count(old3)
src = src.replace(old3, new3, 1)

open(F, "w", encoding="utf-8", newline="").write(src)
print("R2B PATCH OK")
print("new_sha256 =", hashlib.sha256(src.encode()).hexdigest())
print("size =", len(src))
