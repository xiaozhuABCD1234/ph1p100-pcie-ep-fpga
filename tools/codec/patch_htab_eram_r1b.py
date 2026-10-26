#!/usr/bin/env python3
"""T10.a1-htab-eram r1 variant b: precompute thresh_lit - 8 / thresh_lit - 9.

Base: a1_deflate_core.v == 06d59a9def7c55b959054c6ca414d5a485c410269e71e27adb294bf26706aa87
(the 17-bit low-half variant of r1, whose synthesis exposed a worse bm path).

cand_bits + litlen >= thresh_lit  <=>  cand_bits >= thresh_lit - litlen.
Literals are bytes: litlen is 8 for w0 < 144 and 9 otherwise.  Maintain
thresh_lit8 = thresh_lit - 8 and thresh_lit9 = thresh_lit - 9 in registers
updated wherever thresh_lit is assigned.  The w0 path is then only
litlen -> 2:1 select -> state CE; the 32-bit compare runs from registers.
Exact for all cases because thresh_lit >= 43 > 9 (no underflow).
"""
import hashlib
import sys

PATH = r"upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v"
BASE = "06d59a9def7c55b959054c6ca414d5a485c410269e71e27adb294bf26706aa87"

A_OLD = """    reg [31:0] thresh_base, thresh_lit;
"""
A_NEW = """    reg [31:0] thresh_base, thresh_lit;
    reg [31:0] thresh_lit8, thresh_lit9;   // thresh_lit - 8 / thresh_lit - 9
"""

B_OLD = """    // Literal-threshold compare, narrowed to the proven value range.
    // MAX_BLOCK = 4800: stored_cost <= 3 + 7 + 32 + 8*4800 = 38,442, so
    // thresh_lit = stored_cost - 8*len + 8 + 8*literals <= 38,450 and the
    // literal abort guard keeps cand_bits below thresh_lit.  Both fit in
    // 16 bits; the 17-bit low-half sum keeps the carry exact, and the 32-bit
    // carry chain leaves the w0 -> litlen -> state.ce path.
    wire [16:0] lit_sum = {1'b0, cand_bits[15:0]} + {13'd0, litlen};
    wire        lit_ge  = (lit_sum >= {1'b0, thresh_lit[15:0]});
"""
B_NEW = """    // Literal threshold: cand_bits + litlen >= thresh_lit is equivalent to
    // cand_bits >= thresh_lit - litlen.  Literals are bytes, so litlen is 8
    // (w0 < 144) or 9; thresh_lit8/thresh_lit9 are kept as registers updated
    // with thresh_lit, so the 32-bit subtract/carry chain runs from registers
    // and the w0 -> state.ce path is only the 2:1 select.  Range proof:
    // MAX_BLOCK = 4800 -> stored_cost <= 3+7+32+8*4800 = 38,442, thresh_lit
    // <= 38,450, and the literal abort guard keeps cand_bits below it.
    wire lit_ge = (litlen == 4'd9) ? (cand_bits >= thresh_lit9)
                                   : (cand_bits >= thresh_lit8);
"""

C_OLD = """            thresh_base    <= 32'd0;
            thresh_lit     <= 32'd0;
            cand_after_len <= 32'd0;
"""
C_NEW = """            thresh_base    <= 32'd0;
            thresh_lit     <= 32'd0;
            thresh_lit8    <= 32'd0;
            thresh_lit9    <= 32'd0;
            cand_after_len <= 32'd0;
"""

D_OLD = """                        thresh_lit  <= stored_cost(obits, sel_len)
                                       - ({19'd0, sel_len} << 3) + 32'd8;
"""
D_NEW = """                        thresh_lit  <= stored_cost(obits, sel_len)
                                       - ({19'd0, sel_len} << 3) + 32'd8;
                        thresh_lit8 <= stored_cost(obits, sel_len)
                                       - ({19'd0, sel_len} << 3);
                        thresh_lit9 <= stored_cost(obits, sel_len)
                                       - ({19'd0, sel_len} << 3) - 32'd1;
"""

E_OLD = """                            thresh_lit  <= thresh_lit + 32'd8;
"""
E_NEW = """                            thresh_lit  <= thresh_lit + 32'd8;
                            thresh_lit8 <= thresh_lit;
                            thresh_lit9 <= thresh_lit - 32'd1;
"""

F_OLD = """                        thresh_lit  <= thresh_match_r + 32'd8;
"""
F_NEW = """                        thresh_lit  <= thresh_match_r + 32'd8;
                        thresh_lit8 <= thresh_match_r;
                        thresh_lit9 <= thresh_match_r - 32'd1;
"""

CHECKS = [
    ("lit_sum", 0),
    ("thresh_lit8", 8),
    ("thresh_lit9", 8),
]


def main() -> int:
    src = open(PATH, "r", encoding="utf-8").read()
    h = hashlib.sha256(src.encode("utf-8")).hexdigest()
    if h != BASE:
        print("BASE_HASH_MISMATCH", h)
        return 2
    for old, new, tag, n in ((A_OLD, A_NEW, "A", 1), (B_OLD, B_NEW, "B", 1),
                             (C_OLD, C_NEW, "C", 2), (D_OLD, D_NEW, "D", 1),
                             (E_OLD, E_NEW, "E", 1), (F_OLD, F_NEW, "F", 1)):
        if src.count(old) != n:
            print("ANCHOR_%s_COUNT_%d_want_%d" % (tag, src.count(old), n))
            return 3
        src = src.replace(old, new)
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
