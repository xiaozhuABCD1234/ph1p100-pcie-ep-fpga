#!/usr/bin/env python3
"""T10.a1-htab-eram r2: move the S_EXT loop-stop flag updates out of the
byte-compare-dependent else branch.

Base: a1_deflate_core.v == 3326a1fae89cd35d86acc44701937970cdc6edece4abb91996325c896c82e532

ext_zero_r/len_cap_r track (ext_rem == 1) / (len_r == 256) for the next S_EXT
cycle.  They are reloaded at every hit and are don't-care once S_EXT is left,
so updating them on every S_EXT cycle is exact; it removes bm_b_rd (ERAM clk2q)
from their D/enable path.  Nothing else changes.
"""
import hashlib
import sys

PATH = r"upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v"
BASE = "3326a1fae89cd35d86acc44701937970cdc6edece4abb91996325c896c82e532"

OLD = """                    ext_first <= 1'b0;
                    // bm_a_rd is bm[p3_r] on the first extension cycle (the
                    // hit-cycle bm_a address is p3_r) and bm[p3_r+k] after
                    // that, so the ext_first operand mux is gone.
                    if (bm_a_rd != bm_b_rd) begin
                        state <= S_MLEN;
                    end else if (ext_zero_r || len_cap_r) begin
                        len_r <= len_r + 9'd1;
                        state <= S_MLEN;
                    end else begin
                        len_r     <= len_r + 9'd1;
                        ext_rem   <= ext_rem - 13'd1;
                        ext_raddr <= ext_raddr + 13'd1;
                        ext_faddr <= ext_faddr + 13'd1;
                        ext_zero_r<= (ext_rem == 13'd1);
                        len_cap_r <= (len_r == 9'd256);
                    end
"""

NEW = """                    ext_first <= 1'b0;
                    // bm_a_rd is bm[p3_r] on the first extension cycle (the
                    // hit-cycle bm_a address is p3_r) and bm[p3_r+k] after
                    // that, so the ext_first operand mux is gone.
                    // r2: the loop-stop flags track ext_rem/len_r on every
                    // S_EXT cycle, independent of the byte compare.  They are
                    // reloaded at each hit and are don't-care once S_EXT is
                    // left, so this is exact and keeps bm_b_rd (ERAM clk2q)
                    // out of their D/enable path.
                    ext_zero_r <= (ext_rem == 13'd1);
                    len_cap_r  <= (len_r == 9'd256);
                    if (bm_a_rd != bm_b_rd) begin
                        state <= S_MLEN;
                    end else if (ext_zero_r || len_cap_r) begin
                        len_r <= len_r + 9'd1;
                        state <= S_MLEN;
                    end else begin
                        len_r     <= len_r + 9'd1;
                        ext_rem   <= ext_rem - 13'd1;
                        ext_raddr <= ext_raddr + 13'd1;
                        ext_faddr <= ext_faddr + 13'd1;
                    end
"""

CHECKS = [
    ("ext_zero_r<= (ext_rem == 13'd1);", 0),
    ("ext_zero_r <= (ext_rem == 13'd1);", 1),
    ("ext_zero_r", 5),
    ("len_cap_r", 5),
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
