#!/usr/bin/env python3
"""T10.a1-htab-eram r1: narrow only the literal-threshold compare.

Base: a1_deflate_core.v == b374f6fcc161ffe0b9c8fd703cc04fb3fab0411a674a8e0cf1ad06e64173fb6d

The r0 s2 critical path is
  w0_reg -> litlen -> 32-bit (cand_bits + litlen) adder -> thresh_lit compare
  -> state.ce (5.412 ns, 4 ADDER cells).
For MAX_BLOCK=4800 the stored cost is at most 3+7+32+8*4800 = 38,442, so
thresh_lit <= 38,450 and the literal abort guard keeps cand_bits below it.
Both therefore fit in 16 bits.  The compare is rewritten as a 17-bit low-half
sum (carry exact) against the 16-bit threshold, which removes the 32-bit carry
chain from the path.  No other logic is touched.
"""
import hashlib
import sys

PATH = r"upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v"
BASE = "b374f6fcc161ffe0b9c8fd703cc04fb3fab0411a674a8e0cf1ad06e64173fb6d"

A_OLD = """    wire [3:0] litlen  = lit_len({1'b0, w0});
"""
A_NEW = """    wire [3:0] litlen  = lit_len({1'b0, w0});
    // Literal-threshold compare, narrowed to the proven value range.
    // MAX_BLOCK = 4800: stored_cost <= 3 + 7 + 32 + 8*4800 = 38,442, so
    // thresh_lit = stored_cost - 8*len + 8 + 8*literals <= 38,450 and the
    // literal abort guard keeps cand_bits below thresh_lit.  Both fit in
    // 16 bits; the 17-bit low-half sum keeps the carry exact, and the 32-bit
    // carry chain leaves the w0 -> litlen -> state.ce path.
    wire [16:0] lit_sum = {1'b0, cand_bits[15:0]} + {13'd0, litlen};
    wire        lit_ge  = (lit_sum >= {1'b0, thresh_lit[15:0]});
"""

B_OLD = """                        if ((cand_bits + {28'd0, litlen}) >= thresh_lit) begin
"""
B_NEW = """                        if (lit_ge) begin
"""

CHECKS = [
    ("(cand_bits + {28'd0, litlen})", 0),
    ("lit_sum", 2),
    ("lit_ge", 2),
]


def main() -> int:
    src = open(PATH, "r", encoding="utf-8").read()
    h = hashlib.sha256(src.encode("utf-8")).hexdigest()
    if h != BASE:
        print("BASE_HASH_MISMATCH", h)
        return 2
    for old, new, tag in ((A_OLD, A_NEW, "A"), (B_OLD, B_NEW, "B")):
        if src.count(old) != 1:
            print("ANCHOR_%s_COUNT_%d" % (tag, src.count(old)))
            return 3
        src = src.replace(old, new, 1)
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
