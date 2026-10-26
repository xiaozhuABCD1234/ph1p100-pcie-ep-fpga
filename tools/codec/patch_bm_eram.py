# -*- coding: utf-8 -*-
"""T10.a1-bm-eram r0: convert bm_a/bm_b from async (distributed-RAM) reads to
synchronous ERAM reads with fixed one-cycle prefetch.

Every replacement is exact-match with an assertion, and the file is only written
when all of them succeed.  Usage: python patch_bm_eram.py [--check]
"""
import hashlib
import io
import sys

CORE = ("C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/"
        "upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v")
BASE_SHA = "58b216dfcb711a09a597dfe4023ef9a7a0caa49cd217d1b1cce87b8531a0fd47"

R = []  # (name, old, new, count)


def add(name, old, new, count=1):
    R.append((name, old, new, count))


# ---------------------------------------------------------------- 1. ports
add("ports",
    """    // Buffer read data is combinationally addressed.  The buffers are small
    // block-local memories; P4 may replace this with a registered-read variant
    // if the target ERAM mapping requires it (functional semantics unchanged).
    wire [7:0] cq = bm_a[{enc_bank, raddr}];
    wire [7:0] fq = bm_b[{enc_bank, faddr}];

    // Two-stage bm_a prefetch: x1_r = bm[pos+3], x2_r = bm[pos+4].  Both are
    // registers, so the htab read address uses registered bytes only
    // (w2/x1_r/x2_r in S_SCAN) and the bm_a async read never reaches the
    // hash3 -> htab path.  One position is retired per cycle.
    reg  [7:0] x1_r;
    reg  [7:0] x2_r;
    reg  [12:0] praddr;
""",
    """    // Buffer read data is synchronously addressed: one registered address and
    // one registered data word per array (a single read port each).  The two
    // arrays hold identical bytes, so in S_PRE/S_REPOS bm_a serves the x2
    // prefetch stream (praddr) while bm_b serves the w0..w2 window (raddr).
    // Every address is issued one cycle before the byte is consumed, so the
    // symbol rate stays one per cycle.  Synchronous read + registered address
    // + single write port is the ERAM template, which removes the 8,432 LUT
    // distributed-RAM read long lines found by the area-map route.
    reg  [7:0] bm_a_rd;
    reg  [7:0] bm_b_rd;
    wire       bm_hit_a = (state == S_SCAN) && hit2;
    wire [12:0] bm_raddr_a = bm_hit_a ? (p3_r + 13'd1)
                            : (state == S_EXT) ? ext_raddr
                            : ((state == S_SLEN) || (state == S_SDATA_R)) ? raddr
                            : praddr;
    wire [12:0] bm_raddr_b = bm_hit_a ? hf_r
                            : (state == S_EXT) ? ext_faddr
                            : raddr;
    always @(posedge clk) begin
        bm_a_rd <= bm_a[{enc_bank, bm_raddr_a}];
        bm_b_rd <= bm_b[{enc_bank, bm_raddr_b}];
    end

    // Registered two-stage prefetch: x1_r = bm[pos+3]; bm_a_rd itself is the
    // bm[pos+4] stage, so the htab read address still uses registered bytes
    // only (w2, x1_r, bm_a_rd in S_SCAN).  One position is retired per cycle.
    reg  [7:0] x1_r;
    reg  [12:0] praddr;
""")

# ------------------------------------------------------- 2. write ports
add("write_ports",
    """    // 16-bit candidate words (byte-packed bitstream of current block)
""",
    """    // Block loader write port: one enable/address/data per clock, no reset
    // (ERAM template).  Same structure frame_top uses for smem.  The loader
    // bank and the encoding bank are always different while enc_busy, so a
    // read and a write never target the same word during encoding.
    wire        bm_we_w    = in_acc;
    wire [13:0] bm_waddr_w = in_sop ? 14'd0 : {ld_bank, ld_ptr};
    always @(posedge clk) begin
        if (bm_we_w)
            bm_a[bm_waddr_w] <= in_data;
    end
    always @(posedge clk) begin
        if (bm_we_w)
            bm_b[bm_waddr_w] <= in_data;
    end

    // 16-bit candidate words (byte-packed bitstream of current block)
""")

# ------------------------------------------------------------- 3. cq_r decl
add("decl", "    reg [7:0]  cq_r, fq_r;", "    reg [7:0]  cq_r;")

# -------------------------------------------------------------- 4. fq_r reset
add("fq_r_reset", "            fq_r           <= 8'd0;\n", "", 2)

# ------------------------------------------------------------- 5. x2_r reset
add("x2_r_reset", "            x2_r           <= 8'd0;\n", "", 2)

# ------------------------------------------------------- 6. loader temps decl
add("ld_tmp_decl", "    reg        ld_bank_w;\n    reg [12:0] ld_ptr_w;\n", "")

# ------------------------------------------------ 7. loader temps assignment
add("ld_tmp_assign",
    """            ld_bank_w = in_sop ? 1'b0 : ld_bank;
            ld_ptr_w  = in_sop ? 13'd0 : ld_ptr;
""", "")

# ------------------------------------------------------ 8. remove bm writes
add("bm_write",
    """                bm_a[{ld_bank_w, ld_ptr_w}] <= in_data;
                bm_b[{ld_bank_w, ld_ptr_w}] <= in_data;

""", "")

# --------------------------------------------------------- 9. htab read addr
add("htab_rd_addr",
    """    wire [9:0] htab_rd_addr = (state == S_SCAN)
                              ? hash3(w2, x1_r, x2_r)
                              : ((((state == S_PRE) && (pre_cnt == 13'd3)) ||
                                  ((state == S_REPOS) && (rp_cnt == 13'd3)))
                                 ? hash3(w1, x1_r, x2_r)
                                 : hash3(w0, x1_r, x2_r));
""",
    """    wire [9:0] htab_rd_addr = (state == S_SCAN)
                              ? hash3(w2, x1_r, bm_a_rd)
                              : ((((state == S_PRE) && (pre_cnt == 13'd3)) ||
                                  ((state == S_REPOS) && (rp_cnt == 13'd3)))
                                 ? hash3(w1, x1_r, bm_a_rd)
                                 : hash3(w0, x1_r, bm_a_rd));
""")

# ------------------------------------------------------- 10. prefetch block
add("prefetch",
    """            // Two-stage registered prefetch: x1_r = bm[pos+3], x2_r =
            // bm[pos+4]; the bm_a read is address-register to data-register
            // and never appears in the hash3 -> htab address path.  praddr is
            // scheduled so that every read-address byte is a register:
            // S_SCAN raddr+3, S_REPOS rp1 raddr+2 (seed rp0 = pos+2,
            // S_MCHK = pos_next+1), S_PRE pre1..pre3 raddr+3 (seed pre0 = 2,
            // S_BHDR = 1).
            if (htab_pref) begin
                x1_r   <= x2_r;
                x2_r   <= bm_a[{enc_bank, praddr}];
                praddr <= raddr + 13'd3;
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
""")

# ------------------------------------------------------------- 11. S_BHDR
add("S_BHDR",
    """                S_BHDR: begin
                    praddr <= 13'd1;      // seed x2_r = bm[1] for the S_PRE window
                    state  <= S_PRE;
                end
""",
    """                S_BHDR: begin
                    praddr <= 13'd1;      // seed bm_a_rd = bm[1] for the S_PRE window
                    raddr  <= 13'd0;      // seed the bm_b window read at bm[0]
                    state  <= S_PRE;
                end
""")

# -------------------------------------------------------------- 12. S_PRE
add("S_PRE",
    """                S_PRE: begin
                    case (pre_cnt)
                        13'd0: begin
                            raddr   <= 13'd0;
                            praddr  <= 13'd2;
                            s1_pos_r<= 13'd0;
                            pre_cnt <= 13'd1;
                        end
                        13'd1: begin
                            w0      <= cq;
                            raddr   <= clamp_addr(13'd1, blk_n);
                            pre_cnt <= 13'd2;
                        end
                        13'd2: begin
                            w1      <= cq;
                            raddr   <= clamp_addr(13'd2, blk_n);
                            pre_cnt <= 13'd3;
                        end
                        default: begin
                            w2      <= cq;
                            raddr   <= clamp_addr(13'd3, blk_n);
                            pre_cnt <= 13'd0;
                            pos     <= 13'd0;
                            p3_r    <= 13'd3;
                            s1_pos_r<= 13'd1;
                            state   <= S_SCAN;
                        end
                    endcase
                end
""",
    """                S_PRE: begin
                    case (pre_cnt)
                        13'd0: begin
                            praddr  <= 13'd2;
                            s1_pos_r<= 13'd0;
                            raddr   <= clamp_addr(13'd1, blk_n);
                            pre_cnt <= 13'd1;
                        end
                        13'd1: begin
                            w0      <= bm_b_rd;
                            raddr   <= clamp_addr(13'd2, blk_n);
                            pre_cnt <= 13'd2;
                        end
                        13'd2: begin
                            w1      <= bm_b_rd;
                            raddr   <= clamp_addr(13'd3, blk_n);
                            pre_cnt <= 13'd3;
                        end
                        default: begin
                            w2      <= bm_b_rd;
                            raddr   <= clamp_addr(13'd3, blk_n);
                            pre_cnt <= 13'd0;
                            pos     <= 13'd0;
                            p3_r    <= 13'd3;
                            s1_pos_r<= 13'd1;
                            state   <= S_SCAN;
                        end
                    endcase
                end
""")

# ----------------------------------------------------------- 13. S_SCAN hit
add("S_SCAN_hit",
    """                            raddr     <= p3_r;
                            faddr     <= hf_r;
                            cq_r      <= bm_a[{enc_bank, p3_r}];
                            fq_r      <= bm_b[{enc_bank, hf_r}];
                            ext_raddr <= p3_r + 13'd1;
""",
    """                            raddr     <= p3_r;
                            faddr     <= hf_r;
                            // bm[pos+3] is already registered (x1_r); the
                            // synchronous bm_b port is issued hf_r = ref+3 and
                            // returns it in the first S_EXT cycle.
                            cq_r      <= x1_r;
                            ext_raddr <= p3_r + 13'd1;
""")

# ------------------------------------------------------------ 14. S_EXT
add("S_EXT",
    """                S_EXT: begin
                    // Compare the byte prefetched in the previous cycle.
                    // ext_raddr/ext_faddr are registered read addresses, so the
                    // cq_r capture path has no raddr+1 adder or raddr fanout.
                    cq_r <= bm_a[{enc_bank, ext_raddr}];
                    fq_r <= bm_b[{enc_bank, ext_faddr}];
                    if (cq_r != fq_r) begin
""",
    """                S_EXT: begin
                    // Compare the byte prefetched in the previous cycle.  The
                    // registered ext_raddr/ext_faddr drive the synchronous bm
                    // read ports, so bm_b_rd is the reference byte of this
                    // cycle and bm_a_rd is the forward byte of the next one.
                    cq_r <= bm_a_rd;
                    if (cq_r != bm_b_rd) begin
""")

# --------------------------------------------------- 15. S_MCHK raddr seed
add("S_MCHK",
    """                        end else begin
                            rp_cnt <= 13'd0;
                            praddr <= pos_next_r + 13'd1;  // seed x2_r = bm[pos+1]
                            state  <= S_REPOS;
""",
    """                        end else begin
                            rp_cnt <= 13'd0;
                            praddr <= pos_next_r + 13'd1;  // seed bm_a_rd = bm[pos+1]
                            raddr  <= pos_next_r;          // seed the bm_b window read
                            state  <= S_REPOS;
""")

# ----------------------------------------------------------- 16. S_REPOS
add("S_REPOS",
    """                        13'd0: begin
                            raddr  <= pos;
                            p3_r   <= pos + 13'd3;
                            praddr <= pos + 13'd2;
                            s1_pos_r <= pos;
                            rp_cnt <= 13'd1;
                        end
                        13'd1: begin
                            w0    <= cq;
                            raddr <= (pos < lim1) ? (pos + 13'd1) : last_a;
                            rp_cnt<= 13'd2;
                        end
                        13'd2: begin
                            w1    <= cq;
                            raddr <= (pos < lim2) ? (pos + 13'd2) : last_a;
                            rp_cnt<= 13'd3;
                        end
                        default: begin
                            w2    <= cq;
                            raddr <= (pos < lim3) ? (pos + 13'd3) : last_a;
                            s1_pos_r <= pos + 13'd1;
                            rp_cnt<= 13'd0;
                            state <= S_SCAN;
                        end
""",
    """                        13'd0: begin
                            raddr  <= (pos < lim1) ? (pos + 13'd1) : last_a;
                            p3_r   <= pos + 13'd3;
                            praddr <= pos + 13'd2;
                            s1_pos_r <= pos;
                            rp_cnt <= 13'd1;
                        end
                        13'd1: begin
                            w0    <= bm_b_rd;
                            raddr <= (pos < lim2) ? (pos + 13'd2) : last_a;
                            rp_cnt<= 13'd2;
                        end
                        13'd2: begin
                            w1    <= bm_b_rd;
                            raddr <= (pos < lim3) ? (pos + 13'd3) : last_a;
                            rp_cnt<= 13'd3;
                        end
                        default: begin
                            w2    <= bm_b_rd;
                            raddr <= (pos < lim3) ? (pos + 13'd3) : last_a;
                            s1_pos_r <= pos + 13'd1;
                            rp_cnt<= 13'd0;
                            state <= S_SCAN;
                        end
""")

# ------------------------------------------- 17a. stored path address lead
add("SDATA_addr",
    """                        end else begin
                            sdata_ptr <= sdata_ptr + 13'd1;
                            raddr     <= sdata_ptr + 13'd1;
                        end
""",
    """                        end else begin
                            sdata_ptr <= sdata_ptr + 13'd1;
                            // the synchronous read must be issued one byte ahead
                            raddr     <= sdata_ptr + 13'd2;
                        end
""")

# ------------------------------------------------- 17. stored path read byte
add("SDATA_op",
    """            S_SDATA_R: begin
                op_en    = 1'b1;
                op_value = cq;
                op_bits  = 4'd8;
            end
""",
    """            S_SDATA_R: begin
                op_en    = 1'b1;
                op_value = bm_a_rd;
                op_bits  = 4'd8;
            end
""")

# ------------------------------------------------- 18. stored path seed
add("SLEN_seed",
    """                        if (slen_idx == 4'd3) begin
                            sdata_ptr <= 13'd0;
                            raddr     <= 13'd0;
                            state     <= S_SDATA_R;
                        end else begin
                            slen_idx <= slen_idx + 4'd1;
                        end
""",
    """                        if (slen_idx == 4'd3) begin
                            sdata_ptr <= 13'd0;
                            raddr     <= 13'd1;   // bm[0] was issued at idx 2, bm[1] here
                            state     <= S_SDATA_R;
                        end else begin
                            // seed the synchronous bm_a read one cycle early so
                            // the first S_SDATA_R cycle already emits bm[0]
                            if (slen_idx == 4'd2) raddr <= 13'd0;
                            slen_idx <= slen_idx + 4'd1;
                        end
""")

# ------------------------------------------------------- 19. stale comment
add("reads_comment",
    """            // ------------------------------------------------------- reads
            // (combinationally addressed wires cq/fq above)
""",
    """            // ------------------------------------------------------- reads
            // (synchronous bm_a/bm_b read ports and bm_raddr_* muxes above)
""")


def main():
    with io.open(CORE, "r", encoding="utf-8", newline="") as f:
        src = f.read()
    raw = src.encode("utf-8")
    sha = hashlib.sha256(raw).hexdigest()
    print("cwd_file_sha256=%s" % sha)
    check_only = "--check" in sys.argv
    if sha == BASE_SHA:
        print("BASE_SHA_OK (area-map r0 candidate)")
    elif check_only:
        print("NOT_BASE_SHA (patched already?)")
        return 0
    else:
        print("STOP: unexpected base hash, refusing to patch")
        return 2
    txt = src
    for name, old, new, count in R:
        n = txt.count(old)
        if n != count:
            print("FAIL %-16s expected %d found %d" % (name, count, n))
            return 3
        txt = txt.replace(old, new)
        print("ok   %-16s x%d" % (name, count))
    out = txt.encode("utf-8")
    print("new_sha256=%s" % hashlib.sha256(out).hexdigest())
    print("lines %d -> %d" % (src.count("\n"), txt.count("\n")))
    if check_only:
        print("CHECK_ONLY, not written")
        return 0
    with io.open(CORE, "wb") as f:
        f.write(out)
    print("written")
    return 0


if __name__ == "__main__":
    sys.exit(main())
