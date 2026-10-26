"""T10.a1-bm-prefetch r2: REPOS re-prime fix on candidate 3cfdda78.

Trace evidence (odd20x5_p1d1, base vs candidate): after a match the reposition
cycle SCAN(42) shows a real hit in the base (hit2=1 hent_pos=7 hdist=35) but
hit2=0/hent_pos=x in the candidate, so the match is missed and an extra literal
is emitted (stream 108 vs 107, cycles 1462 vs 1459).

Address algebra (A(k) = bm_a read address presented in cycle k; with the extra
read-data stage bm_a_rd2(k)=bm[A(k-2)], x1_r(k)=bm[A(k-3)]):
  S_REPOS requirements for pos = P
    x1_r(R2)      = bm[P+1]  -> A(M)  = P+1   (S_MCHK seed)
    bm_a_rd2(R2)  = bm[P+2]  -> A(R0) = P+2   (R0 seed)
    x1_r(R3)      = bm[P+2]  -> A(R0) = P+2
    bm_a_rd2(R3)  = bm[P+3]  -> A(R1) = P+3   (raddr+3 chain)
    x1_r(SCAN0)   = bm[P+3]  -> A(R1) = P+3
    bm_a_rd2(SCAN0)= bm[P+4] -> A(R2) = P+4
  r0 bumped the M seed and the R0 seed by +1, which shifted the reposition
  window one byte too far (hash3 used bm[P],bm[P+2],bm[P+3]).  r2 restores both
  seeds to the base values and keeps the +1 shift only on the R1..R3 chain
  (praddr <= raddr + 3).  S_PRE priming (S_WAIT praddr<=1, BHDR 2, cnt0 3) is
  already consistent and is left untouched.
"""
import hashlib

F = r"upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v"
IN_SHA = "3cfdda78a23465a73fd0ec57fcd1aa9ff96aa6a9ce924fd06f0e8d9a7761adcf"

src = open(F, "r", encoding="utf-8", newline="").read()
assert hashlib.sha256(src.encode()).hexdigest() == IN_SHA, "worktree is not the r1 candidate"

old1 = """                            praddr <= pos_next_r + 13'd2;  // seed bm_a_rd2 = bm[pos+1]
"""
new1 = """                            // r2: keep the base REPOS re-prime (A(M)=pos+1); the
                            // +1 prefetch shift is applied from R1 on (raddr+3).
                            praddr <= pos_next_r + 13'd1;  // seed bm_a = bm[pos+1]
"""
old2 = """                            praddr <= pos + 13'd3;
"""
new2 = """                            praddr <= pos + 13'd2;
"""
for o, n in ((old1, new1), (old2, new2)):
    assert src.count(o) == 1, (o, src.count(o))
    src = src.replace(o, n, 1)

open(F, "w", encoding="utf-8", newline="").write(src)
print("R2 PATCH OK")
print("new_sha256 =", hashlib.sha256(src.encode()).hexdigest())
print("size =", len(src))
