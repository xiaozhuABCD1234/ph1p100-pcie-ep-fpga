#!/usr/bin/env python3
"""T10.a1-htab-eram r2-b: keep hent_pos out of the stage-1 13-bit subtractor.

Base: a1_deflate_core.v == 0b084317db0608a56865a77fd18e7312add3ddb87c2a465a48f60816d8545396

0 < (s1_pos_r - hent_pos) <= MAX_DIST
  <=> hent_pos < s1_pos_r && hent_pos >= max(s1_pos_r - MAX_DIST, 0)

The saturating bound is derived from the s1_pos_r register, so only the two
13-bit compares launch from hent_pos (htab ERAM clk2q).  s1_hdist is kept for
hd_r/cand_pos.  Exact for unsigned 13-bit values.
"""
import hashlib
import sys

PATH = r"upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v"
BASE = "0b084317db0608a56865a77fd18e7312add3ddb87c2a465a48f60816d8545396"

OLD = """    wire [12:0] s1_hdist = s1_pos_r - hent_pos;
    wire        s1_rng = (s1_hdist <= MAX_DIST) && (hent_pos < s1_pos_r);
"""

NEW = """    wire [12:0] s1_hdist = s1_pos_r - hent_pos;
    // r2-b: keep hent_pos (htab ERAM clk2q) out of the 13-bit subtractor.
    // 0 < (s1_pos_r - hent_pos) <= MAX_DIST  <=>
    // hent_pos < s1_pos_r && hent_pos >= max(s1_pos_r - MAX_DIST, 0).
    // The saturating lower bound is derived from the s1_pos_r register, so
    // only the two 13-bit compares launch from hent_pos; s1_hdist is kept for
    // hd_r/cand_pos.  Exact for unsigned 13-bit values.
    wire [12:0] s1_lo = (s1_pos_r > MAX_DIST)
                        ? (s1_pos_r - MAX_DIST) : 13'd0;
    wire        s1_rng = (hent_pos < s1_pos_r) && (hent_pos >= s1_lo);
"""

CHECKS = [
    ("(s1_hdist <= MAX_DIST)", 0),
    ("s1_lo", 2),
    ("hent_pos >= s1_lo", 1),
]


def main() -> int:
    src = open(PATH, "r", encoding="utf-8").read()
    h = hashlib.sha256(src.encode("utf-8")).hexdigest()
    if h != BASE:
        print("BASE_HASH_MISMATCH", h)
        return 2
    if src.count(OLD) != 1:
        print("ANCHOR_COUNT", src.count(OLD))
        return 3
    src = src.replace(OLD, NEW, 1)
    for tok, want in CHECKS:
        got = src.count(tok)
        if got != want:
            print("RESIDUAL_%s=%d_want_%d" % (tok, got, want))
            return 4
    open(PATH, "w", encoding="utf-8", newline="\n").write(src)
    print("PATCHED", hashlib.sha256(src.encode("utf-8")).hexdigest())
    return 0


if __name__ == "__main__":
    sys.exit(main())
