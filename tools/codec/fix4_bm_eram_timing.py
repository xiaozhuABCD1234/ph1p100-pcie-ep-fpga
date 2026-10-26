# -*- coding: utf-8 -*-
"""T10.a1-bm-eram r0 fix4: take the ERAM clock-to-out out of the hash3 -> htab
path, and let the hash table infer as ERAM.

Symptom (s1 synth): worst path 6.363 ns =
  bm_a ERAM clk2q (1.515+0.506) -> hash3 LUT3 -> htab_rd_addr (fanout 1409)
  -> htab_v 1024x1 LUT-RAM read (LUT3+f7mux+f78mux+LUT6+LUT6) -> htab_rvalid_reg.

Fix A (bm): add one fabric shadow stage xf_r so every hash3 operand is a fabric
register:
  x1_r <= xf_r;  xf_r <= bm_a_rd;  praddr = raddr + 3 everywhere
  -> w0..w2 = bm[p..p+2], x1_r = bm[p+3], xf_r = bm[p+4]
  -> hash3(w2, x1_r, xf_r) is exactly the window at p+2 (unchanged value, so the
     hash-table read address and every code stream stay identical).
  Pre/REPOS seeds shift by one to keep the last PRE/REPOS comparison window
  (w0,w1,x1_r) and its speculative hash3(w1,x1_r,xf_r) correct.

Fix B (htab): move the htab write out of the reset-controlled process into its own
no-reset always block (same transformation as cmem/bm) so the 1024x66 table can
infer as ERAM.  htab_v keeps its reset loop and stays in fabric/LUT-RAM; the
same-address write-first bypass on the read data is untouched, so behaviour is
unchanged.
"""
import hashlib
import io
import sys

CORE = ("C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/"
        "upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v")

R = [
    # ---------------- A1: fabric shadow register -------------------------
    ("decl_xf",
     """    reg  [7:0] x1_r;
    reg  [12:0] praddr;
""",
     """    reg  [7:0] x1_r;    // bm[pos+3] (fabric)
    reg  [7:0] xf_r;    // bm[pos+4]: fabric shadow of the ERAM read port, so
                        // hash3 never launches from an ERAM output register
    reg  [12:0] praddr;
"""),

    ("reset_xf",
     """            x1_r           <= 8'd0;
            praddr         <= 13'd0;
""",
     """            x1_r           <= 8'd0;
            xf_r           <= 8'd0;
            praddr         <= 13'd0;
"""),

    # ---------------- A2: hash3 operands --------------------------------
    ("htab_rd_addr",
     """    wire [9:0] htab_rd_addr = (state == S_SCAN)
                              ? hash3(w2, x1_r, bm_a_rd)
                              : ((((state == S_PRE) && (pre_cnt == 13'd3)) ||
                                  ((state == S_REPOS) && (rp_cnt == 13'd3)))
                                 ? hash3(w1, x1_r, bm_a_rd)
                                 : hash3(w0, x1_r, bm_a_rd));
""",
     """    wire [9:0] htab_rd_addr = (state == S_SCAN)
                              ? hash3(w2, x1_r, xf_r)
                              : ((((state == S_PRE) && (pre_cnt == 13'd3)) ||
                                  ((state == S_REPOS) && (rp_cnt == 13'd3)))
                                 ? hash3(w1, x1_r, xf_r)
                                 : hash3(w0, x1_r, xf_r));
"""),

    # ---------------- A3: prefetch chain --------------------------------
    ("prefetch",
     """            if (htab_pref) begin
                x1_r   <= bm_a_rd;
                praddr <= (state == S_SCAN) ? (raddr + 13'd3)
                                            : (raddr + 13'd2);
            end
""",
     """            if (htab_pref) begin
                x1_r   <= xf_r;
                xf_r   <= bm_a_rd;
                praddr <= raddr + 13'd3;
            end
"""),

    # ---------------- A4: seeds -----------------------------------------
    ("seed_bhdr",
     """                    praddr <= 13'd1;      // seed bm_a_rd = bm[1] for the S_PRE window
""",
     """                    praddr <= 13'd2;      // seed the bm_a read stream (xf_r = bm[2] at pre3)
"""),
    ("seed_pre0",
     """                        13'd0: begin
                            praddr  <= 13'd2;
""",
     """                        13'd0: begin
                            praddr  <= 13'd3;
"""),
    ("seed_mchk",
     """                            praddr <= pos_next_r + 13'd1;  // seed bm_a_rd = bm[pos+1]
""",
     """                            praddr <= pos_next_r + 13'd2;  // seed the bm_a read stream
"""),
    ("seed_repos0",
     """                            raddr  <= (pos < lim1) ? (pos + 13'd1) : last_a;
                            p3_r   <= pos + 13'd3;
                            praddr <= pos + 13'd2;
""",
     """                            raddr  <= (pos < lim1) ? (pos + 13'd1) : last_a;
                            p3_r   <= pos + 13'd3;
                            praddr <= pos + 13'd3;
"""),

    # ---------------- B: htab write port --------------------------------
    ("htab_write_out",
     """            if (htab_we) begin
                htab[s1_ins_addr]   <= s1_ins_data;
                htab_v[s1_ins_addr] <= 1'b1;
            end
""",
     """            if (htab_we) begin
                htab_v[s1_ins_addr] <= 1'b1;
            end
"""),
    ("htab_write_new",
     """    // cmem read port: registered address, one full cycle of read latency, which
""",
     """    // Hash-table write port: single enable/address/data, no reset, so the
    // 1024x66 table infers as ERAM instead of LUT-RAM (the read stays one cycle;
    // the same-address write-first bypass on htab_rdata is unchanged).
    always @(posedge clk) begin
        if (htab_we)
            htab[s1_ins_addr] <= s1_ins_data;
    end

    // cmem read port: registered address, one full cycle of read latency, which
"""),
]


def main():
    with io.open(CORE, "r", encoding="utf-8", newline="") as f:
        txt = f.read()
    print("before_sha=%s" % hashlib.sha256(txt.encode("utf-8")).hexdigest())
    for name, old, new in R:
        n = txt.count(old)
        want = 2 if name == "reset_xf" else 1
        if n != want:
            print("FAIL %-16s found %d (want %d)" % (name, n, want))
            return 3
        txt = txt.replace(old, new)
        print("ok   %s" % name)
    out = txt.encode("utf-8")
    print("after_sha=%s" % hashlib.sha256(out).hexdigest())
    if "--check" in sys.argv:
        print("CHECK_ONLY")
        return 0
    with io.open(CORE, "wb") as f:
        f.write(out)
    print("written")
    return 0


if __name__ == "__main__":
    sys.exit(main())
