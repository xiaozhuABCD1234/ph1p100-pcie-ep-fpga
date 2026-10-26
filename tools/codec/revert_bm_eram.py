# -*- coding: utf-8 -*-
"""Reverse T10.a1-bm-eram r0 edits: restore the frozen area-map baseline
58b216dfcb711a09a597dfe4023ef9a7a0caa49cd217d1b1cce87b8531a0fd47 in the
working tree, after archiving the candidate as
T10.a1-bm-eram/r0/candidate-2d2aa4b4.a1_deflate_core.v.

Every replacement is exact-match; the file is written only if every assertion
passes and the result hashes back to the baseline.  --check prints only.
"""
import hashlib
import io
import sys

sys.path.insert(0, "upstream/ph1p100-pcie-ep-fpga/tools/codec")
import patch_bm_eram as P          # noqa: E402  (R list: old/new pairs)
import fix_bm_eram_ports as F     # noqa: E402

CORE = P.CORE
BASE_SHA = P.BASE_SHA
CUR_SHA = "2d2aa4b4eb2668a0ccb7644d2d13bfcb9d7402c346c94ece7d724bdba1080178"

# manual edits made with the editor after the two patch scripts, newest first
MANUAL_REV = [
    ("mux_a",
     """    wire [12:0] bm_raddr_a = (state == S_EXT) ? ext_raddr
                           : ((state == S_SLEN) || (state == S_SDATA_R)) ? raddr
                           : praddr;""",
     """    wire [12:0] bm_raddr_a = bm_hit_a ? (p3_r + 13'd1)
                           : (state == S_EXT) ? ext_raddr
                           : ((state == S_SLEN) || (state == S_SDATA_R)) ? raddr
                           : praddr;"""),
    ("s_ext",
     """                S_EXT: begin
                    // Compare the byte prefetched in the previous cycle.  The
                    // first cycle compares the byte captured at the hit (cq_r =
                    // bm[pos+3]); from then on the synchronous read ports supply
                    // both bytes of the current cycle (bm_a_rd forward, bm_b_rd
                    // reference), with ext_raddr/ext_faddr issued one cycle early.
                    ext_first <= 1'b0;
                    if (((ext_first ? cq_r : bm_a_rd) != bm_b_rd)) begin""",
     """                S_EXT: begin
                    // Compare the byte prefetched in the previous cycle.  The
                    // registered ext_raddr/ext_faddr drive the synchronous bm
                    // read ports, so bm_b_rd is the reference byte of this
                    // cycle and bm_a_rd is the forward byte of the next one.
                    cq_r <= bm_a_rd;
                    if (cq_r != bm_b_rd) begin"""),
    ("hit_ext_first",
     """                            cq_r      <= x1_r;
                            ext_first <= 1'b1;
                            ext_raddr <= p3_r + 13'd1;""",
     """                            cq_r      <= x1_r;
                            ext_raddr <= p3_r + 13'd1;"""),
    ("reset_ext_first",
     """            ext_rem        <= 13'd0;
            ext_first      <= 1'b0;
            ext_raddr      <= 13'd0;""",
     """            ext_rem        <= 13'd0;
            ext_raddr      <= 13'd0;"""),
    ("decl_ext_first",
     """    reg [12:0] ext_rem;
    reg        ext_first;   // first S_EXT cycle: compare the byte loaded at the hit""",
     """    reg [12:0] ext_rem;"""),
    ("praddr_off",
     """            // Two-stage registered prefetch: x1_r = bm[pos+3] and the
            // synchronous bm_a read port (bm_a_rd) is the bm[pos+4] stage.
            // praddr is the bm_a read address issued one cycle before use.
            // In S_SCAN raddr = pos+3 (unchanged semantics), so the next
            // address is raddr+3 = pos+6.  In S_PRE/S_REPOS raddr is the
            // bm_b window address, which runs one ahead of the old schedule,
            // so the next prefetch address is raddr+2.
            if (htab_pref) begin
                x1_r   <= bm_a_rd;
                praddr <= (state == S_SCAN) ? (raddr + 13'd3)
                                            : (raddr + 13'd2);
            end
""",
     """            // Two-stage registered prefetch: x1_r = bm[pos+3] and the
            // synchronous bm_a read port (bm_a_rd) is the bm[pos+4] stage.
            // praddr is the bm_a read address issued one cycle before use:
            // S_SCAN p+4, S_REPOS rp0..rp3 pos+1..pos+4 (seed rp0 = pos+1,
            // S_MCHK = pos_next+1), S_PRE pre0..pre3 1..4 (seed pre0 = 1,
            // S_BHDR = 1).  raddr tracks the window read address, so the next
            // prefetch address is raddr+2.
            if (htab_pref) begin
                x1_r   <= bm_a_rd;
                praddr <= raddr + 13'd2;
            end
"""),
]


def chain(pairs):
    """new->old for each pair, in reverse application order."""
    out = [(p[0], p[2], p[1]) for p in pairs]
    out.reverse()
    return out


OVERRIDE = {
    # forward edits whose "new" text is empty need an anchor to re-insert
    "fq_r_reset": ("            cq_r           <= 8'd0;\n",
                   "            cq_r           <= 8'd0;\n"
                   "            fq_r           <= 8'd0;\n", 2),
    "x2_r_reset": ("            x1_r           <= 8'd0;\n",
                   "            x1_r           <= 8'd0;\n"
                   "            x2_r           <= 8'd0;\n", 2),
    "ld_tmp_decl": ("    reg [16:0] sum_a, sum_b, a_nxt, b_nxt;\n",
                    "    reg [16:0] sum_a, sum_b, a_nxt, b_nxt;\n"
                    "    reg        ld_bank_w;\n"
                    "    reg [12:0] ld_ptr_w;\n", 1),
    "ld_tmp_assign": ("            cand_bits_n = cand_bits + {27'd0, cp_nbits};\n",
                      "            cand_bits_n = cand_bits + {27'd0, cp_nbits};\n"
                      "            ld_bank_w = in_sop ? 1'b0 : ld_bank;\n"
                      "            ld_ptr_w  = in_sop ? 13'd0 : ld_ptr;\n", 1),
}


def main():
    with io.open(CORE, "r", encoding="utf-8", newline="") as f:
        txt = f.read()
    sha = hashlib.sha256(txt.encode("utf-8")).hexdigest()
    print("current_sha=%s" % sha)
    if sha != CUR_SHA:
        print("STOP: working file is not the frozen candidate")
        return 2
    work = [(n, o, nw) for (n, o, nw) in MANUAL_REV]
    wF = [p for p in chain(F.R) if p[0] != "remove_write_port"]
    wF.append(("remove_write_port_rev",
               "    // 16-bit candidate words (byte-packed bitstream of current block)\n",
               F.R[0][1] + "    // 16-bit candidate words (byte-packed bitstream of current block)\n"))
    work += wF
    bm_write_block = [p[1] for p in P.R if p[0] == "bm_write"][0]
    wP = []
    for (n, o, nw) in chain(P.R):
        if n == "bm_write":
            wP.append(("bm_write_rev",
                       "            if (in_acc) begin\n                if (in_sop) begin\n",
                       "            if (in_acc) begin\n" + bm_write_block
                       + "                if (in_sop) begin\n"))
        else:
            wP.append((n, o, nw))
    work += wP
    for name, old, new in work:
        want = 2 if name == "reset_ext_first" else 1
        if name in OVERRIDE:
            old, new, want = OVERRIDE[name]
        n = txt.count(old)
        if n != want:
            print("FAIL %-18s found %d (want %d)" % (name, n, want))
            return 3
        txt = txt.replace(old, new)
        print("ok   %s" % name)
    out = txt.encode("utf-8")
    got = hashlib.sha256(out).hexdigest()
    print("restored_sha=%s" % got)
    if got != BASE_SHA:
        print("STOP: restored content does not match the baseline hash")
        return 4
    if "--check" in sys.argv:
        print("CHECK_ONLY, not written")
        return 0
    with io.open(CORE, "wb") as f:
        f.write(out)
    print("written (baseline restored)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
