#!/usr/bin/env python3
"""T10.a1-htab-eram step 2: remove the remaining ERAM clk2q launch of the
match-extension decision without changing any cycle or value.

After step 1 the worst synthesised path is
  bm_a ERAM clk2q -> bm_a_rd -> ext_first mux -> byte compare -> state CE.
The first extension byte is bm[p3_r] (x1_r).  The hit-cycle bm_a read is
currently praddr (a prefetch that is re-seeded after every match anyway), so
this step makes the hit-cycle bm_a port read p3_r instead.  bm_a_rd then holds
the first extension byte at S_EXT cycle 0 and the next forward bytes in the
following cycles, and the 8-bit ext_first mux is no longer needed.

It also precomputes the two loop-stop tests (ext_rem == 0, len_r == 257) into
1-bit registers updated with the counters, so the state clock-enable path after
the ERAM data does not carry the 13-bit/9-bit compares.

Both are exact: same compared bytes, same stop cycles, same stream.
"""
import hashlib
import sys

PATH = r"upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v"
BASE = "da676bc4f0ffeced5ef3e577909945ef8c3a4ea16f72bcb6a40353ddcba0be94"

A_OLD = """    wire [12:0] bm_raddr_a = (state == S_EXT) ? ext_raddr
                           : ((state == S_SLEN) || (state == S_SDATA_R)) ? raddr
                           : praddr;
"""
A_NEW = """    wire [12:0] bm_raddr_a = (state == S_EXT) ? ext_raddr
                           : bm_hit_a ? p3_r
                           : ((state == S_SLEN) || (state == S_SDATA_R)) ? raddr
                           : praddr;
"""

B_OLD = """    reg [12:0] ext_rem;
    reg        ext_first;   // first S_EXT cycle: compare the byte loaded at the hit
"""
B_NEW = """    reg [12:0] ext_rem;
    reg        ext_first;   // first S_EXT cycle: compare the byte loaded at the hit
    // 1-bit precomputed loop-stop tests (updated with ext_rem / len_r) so the
    // S_EXT state-enable path does not contain the 13-bit/9-bit compares.
    reg        ext_zero_r;  // ext_rem == 0
    reg        len_cap_r;   // len_r == 257
"""

C_OLD = """            cq_r           <= 8'd0;
            ext_rem        <= 13'd0;
            ext_first      <= 1'b0;
            ext_raddr      <= 13'd0;
            ext_faddr      <= 13'd0;
            pre_cnt        <= 13'd0;
"""
C_NEW = """            cq_r           <= 8'd0;
            ext_rem        <= 13'd0;
            ext_first      <= 1'b0;
            ext_zero_r     <= 1'b0;
            len_cap_r      <= 1'b0;
            ext_raddr      <= 13'd0;
            ext_faddr      <= 13'd0;
            pre_cnt        <= 13'd0;
"""

D_OLD = """                            ext_rem   <= (p3_r + 13'd1 >= blk_n)
                                         ? 13'd0
                                         : (blk_n - (p3_r + 13'd1));
"""
D_NEW = """                            ext_rem   <= ext_rem_new;
                            ext_zero_r<= (ext_rem_new == 13'd0);
                            len_cap_r <= 1'b0;
"""

E_OLD = """    wire out_space = (fifo_count < 5'd15);
"""
E_NEW = """    wire out_space = (fifo_count < 5'd15);

    // Next extension remaining count for the hit that enters S_EXT (same
    // expression the FSM used to assign to ext_rem).
    wire [12:0] ext_rem_new = (p3_r + 13'd1 >= blk_n)
                              ? 13'd0 : (blk_n - (p3_r + 13'd1));
"""

F_OLD = """                    ext_first <= 1'b0;
                    if (((ext_first ? cq_r : bm_a_rd) != bm_b_rd)) begin
                        state <= S_MLEN;
                    end else if ((ext_rem == 13'd0) || (len_r == 9'd257)) begin
                        len_r <= len_r + 9'd1;
                        state <= S_MLEN;
                    end else begin
                        len_r     <= len_r + 9'd1;
                        ext_rem   <= ext_rem - 13'd1;
                        ext_raddr <= ext_raddr + 13'd1;
                        ext_faddr <= ext_faddr + 13'd1;
                    end
"""
F_NEW = """                    ext_first <= 1'b0;
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

CHECKS = [
    ("(ext_first ? cq_r : bm_a_rd)", 0),
    ("(ext_rem == 13'd0) || (len_r == 9'd257)", 0),
    ("ext_rem_new", 3),
    ("ext_zero_r", 5),
    ("len_cap_r", 5),
]


def main() -> int:
    src = open(PATH, "r", encoding="utf-8").read()
    h = hashlib.sha256(src.encode("utf-8")).hexdigest()
    if h != BASE:
        print("BASE_HASH_MISMATCH", h)
        return 2
    for old, new, tag in ((A_OLD, A_NEW, "A"), (B_OLD, B_NEW, "B"),
                          (C_OLD, C_NEW, "C"), (D_OLD, D_NEW, "D"),
                          (E_OLD, E_NEW, "E"), (F_OLD, F_NEW, "F")):
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
