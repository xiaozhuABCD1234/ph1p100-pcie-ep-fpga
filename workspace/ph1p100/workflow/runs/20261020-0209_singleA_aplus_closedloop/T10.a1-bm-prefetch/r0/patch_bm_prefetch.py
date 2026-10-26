"""T10.a1-bm-prefetch r0 patch: bm read-data stage 2 + scan prefetch one cycle
earlier + unconditional ext_mis_r.  Exact-string replacements with assertions.
Scope: a1_deflate_core.v only (bm read data / prefetch / ext_mis_r).
"""
import hashlib
import sys

F = r"upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v"
BASE_SHA = "587ef708967fbe2f3bb27b0bccdbc6af942b61639ad95d8d9ec9eca2b24a2f16"

src = open(F, "r", encoding="utf-8", newline="").read()
h = hashlib.sha256(src.encode("utf-8")).hexdigest()
assert h == BASE_SHA, "base core hash mismatch: " + h
assert "\r\n" not in src, "unexpected CRLF"

reps = []

# 1) declaration of the second read-data stage
reps.append((
"""    reg  [7:0] bm_a_rd;
    reg  [7:0] bm_b_rd;
""",
"""    reg  [7:0] bm_a_rd;
    // r0 (bm-prefetch): second read-data stage.  The bm_a ERAM clk2q output now
    // feeds only this flop, so the scan byte stream consumed by hash3 and by the
    // x1_r window shift comes from bm_a_rd2 instead of the ERAM output register.
    reg  [7:0] bm_a_rd2;
    reg  [7:0] bm_b_rd;
"""))

# 2) hash3 read address: third byte from the registered stage-2 read data
reps.append((
"""    wire [9:0] htab_rd_addr = (state == S_SCAN)
                              ? hash3(w2, x1_r, bm_a_rd)
                              : ((((state == S_PRE) && (pre_cnt == 13'd3)) ||
                                  ((state == S_REPOS) && (rp_cnt == 13'd3)))
                                 ? hash3(w1, x1_r, bm_a_rd)
                                 : hash3(w0, x1_r, bm_a_rd));
""",
"""    // r0 (bm-prefetch): the third hash byte is bm_a_rd2 (a flop), so the htab
    // read address no longer starts at the bm_a ERAM clk2q output.
    wire [9:0] htab_rd_addr = (state == S_SCAN)
                              ? hash3(w2, x1_r, bm_a_rd2)
                              : ((((state == S_PRE) && (pre_cnt == 13'd3)) ||
                                  ((state == S_REPOS) && (rp_cnt == 13'd3)))
                                 ? hash3(w1, x1_r, bm_a_rd2)
                                 : hash3(w0, x1_r, bm_a_rd2));
"""))

# 3) read port: add the stage-2 register
reps.append((
"""    always @(posedge clk) begin
        bm_a_rd <= bm_a[{enc_bank, bm_raddr_a}];
        bm_b_rd <= bm_b[{enc_bank, bm_raddr_b}];
    end
""",
"""    always @(posedge clk) begin
        bm_a_rd  <= bm_a[{enc_bank, bm_raddr_a}];
        bm_b_rd  <= bm_b[{enc_bank, bm_raddr_b}];
        bm_a_rd2 <= bm_a_rd;      // r0 (bm-prefetch): scan-path stage 2
    end
"""))

# 4) prefetch: one cycle earlier, x1_r from the stage-2 register
reps.append((
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
"""            // Three-stage registered prefetch of the scan window.  In S_SCAN
            //   bm_a_rd2 = bm[pos+4], x1_r = bm[pos+3], w2 = bm[pos+2],
            // so both hash3 (w2, x1_r, bm_a_rd2) and the stage-1 window are
            // built from flops; bm_a_rd is the bm[pos+5] ERAM output register
            // and now drives only the bm_a_rd2 flop.  The read address is
            // issued one cycle earlier, so the symbol rate stays one per cycle.
            // In S_SCAN raddr = pos+3 (unchanged semantics), so the next
            // address is raddr+4.  In S_PRE/S_REPOS raddr is the bm_b window
            // address, which runs one ahead, so the next address is raddr+3.
            if (htab_pref) begin
                x1_r   <= bm_a_rd2;
                praddr <= (state == S_SCAN) ? (raddr + 13'd4)
                                            : (raddr + 13'd3);
            end
"""))

# 5) ext_mis_r: unconditional load (no clock enable) via a data mux
reps.append((
"""    wire        bm_hit_a   = (state == S_SCAN) && hit2;
""",
"""    wire        bm_hit_a   = (state == S_SCAN) && hit2;
    // Forward byte of the registered extension compare: the hit cycle uses the
    // already-registered x1_r, every S_EXT cycle the current bm_a read data.
    wire [7:0]  ext_fw_byte = (state == S_EXT) ? bm_a_rd : x1_r;
"""))
reps.append((
"""            if (state == S_EXT) ext_mis_r <= (bm_a_rd != bm_b_rd);
            if (bm_hit_a)        ext_mis_r <= (x1_r     != bm_b_rd);
""",
"""            // r0 (bm-prefetch): unconditional load, no clock enable.  The
            // source bytes are the same as before (x1_r on the hit cycle,
            // bm_a read data in S_EXT), so the flag timing is unchanged.
            ext_mis_r <= (ext_fw_byte != bm_b_rd);
"""))

# 6-9) prefetch seeds: +1 cycle of head start
reps.append((
"""                    praddr <= 13'd1;      // seed bm_a_rd = bm[1] for the S_PRE window
""",
"""                    praddr <= 13'd2;      // seed bm_a_rd2 = bm[1] for the S_PRE window
"""))
reps.append((
"""                            praddr  <= 13'd2;
""",
"""                            praddr  <= 13'd3;
"""))
reps.append((
"""                            praddr <= pos_next_r + 13'd1;  // seed bm_a_rd = bm[pos+1]
""",
"""                            praddr <= pos_next_r + 13'd2;  // seed bm_a_rd2 = bm[pos+1]
"""))
reps.append((
"""                            praddr <= pos + 13'd2;
""",
"""                            praddr <= pos + 13'd3;
"""))

for old, new in reps:
    n = src.count(old)
    assert n == 1, "expected exactly 1 match, got %d for:\n%s" % (n, old[:90])
    src = src.replace(old, new, 1)

open(F, "w", encoding="utf-8", newline="").write(src)
out = hashlib.sha256(src.encode("utf-8")).hexdigest()
print("PATCH OK")
print("new_sha256 =", out)
print("size =", len(src))
