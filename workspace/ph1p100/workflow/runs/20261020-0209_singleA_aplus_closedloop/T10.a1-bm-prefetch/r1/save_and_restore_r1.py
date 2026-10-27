"""T10.a1-bm-prefetch r1: save the r1 candidate and restore the locked baseline
core (587ef708) in the working tree.  Also restore r0/p2/result.json, which was
overwritten by a mis-targeted P2 script run (its $run still pointed at r0 while
W: pointed at r1, so the verifier saw no streams and wrote a spurious FAIL).
The r0 sim outputs under r0/p2/runs are untouched, so the verifier is re-run
against them.
"""
import hashlib
import shutil

F = r"upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v"
OUT = r"workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.a1-bm-prefetch/r1/candidate-r1-blockprime.a1_deflate_core.v"
BASE_SHA = "587ef708967fbe2f3bb27b0bccdbc6af942b61639ad95d8d9ec9eca2b24a2f16"
R1_SHA = "3cfdda78a23465a73fd0ec57fcd1aa9ff96aa6a9ce924fd06f0e8d9a7761adcf"

src = open(F, "r", encoding="utf-8", newline="").read()
h = hashlib.sha256(src.encode("utf-8")).hexdigest()
assert h == R1_SHA, "worktree is not the r1 candidate: " + h
shutil.copyfile(F, OUT)
print("saved r1 candidate:", OUT)

# restore the r0 candidate and then invert the single r1 insertion
r0 = r"workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.a1-bm-prefetch/r0/candidate-bm-prefetch.a1_deflate_core.v"
base = open(r0, "r", encoding="utf-8", newline="").read()
assert hashlib.sha256(base.encode("utf-8")).hexdigest() == "de59bddc0e4323348e05c3ae1dc16a14e16652da4d34553a3218beb4bf6f840b"

# inverse of the r1 fix, then inverse of the r0 patch (reuse the r0 restore logic)
old = """                S_WAIT: begin
                    if (blk_avail && htab_clr_done) begin
                        // r1 (bm-prefetch): prime the bm_a prefetch one cycle
                        // before S_BHDR.  The extra read-data stage makes the
                        // S_PRE lookup address use x1_r, whose value at
                        // pre_cnt=2 comes from the address issued during
                        // S_BHDR; without this seed that address is the stale
                        // previous-block praddr (out-of-block read).
                        praddr      <= 13'd1;
                        enc_bank    <= sel_is_b0 ? 1'b0 : 1'b1;
"""
new = """                S_WAIT: begin
                    if (blk_avail && htab_clr_done) begin
                        enc_bank    <= sel_is_b0 ? 1'b0 : 1'b1;
"""
assert base.count(old) == 1
base = base.replace(old, new, 1)
h1 = hashlib.sha256(base.encode("utf-8")).hexdigest()
assert h1 == "de59bddc0e4323348e05c3ae1dc16a14e16652da4d34553a3218beb4bf6f840b", h1

inv = [
("""    reg  [7:0] bm_a_rd;
    // r0 (bm-prefetch): second read-data stage.  The bm_a ERAM clk2q output now
    // feeds only this flop, so the scan byte stream consumed by hash3 and by the
    // x1_r window shift comes from bm_a_rd2 instead of the ERAM output register.
    reg  [7:0] bm_a_rd2;
    reg  [7:0] bm_b_rd;
""",
"""    reg  [7:0] bm_a_rd;
    reg  [7:0] bm_b_rd;
"""),
("""    // r0 (bm-prefetch): the third hash byte is bm_a_rd2 (a flop), so the htab
    // read address no longer starts at the bm_a ERAM clk2q output.
    wire [9:0] htab_rd_addr = (state == S_SCAN)
                              ? hash3(w2, x1_r, bm_a_rd2)
                              : ((((state == S_PRE) && (pre_cnt == 13'd3)) ||
                                  ((state == S_REPOS) && (rp_cnt == 13'd3)))
                                 ? hash3(w1, x1_r, bm_a_rd2)
                                 : hash3(w0, x1_r, bm_a_rd2));
""",
"""    wire [9:0] htab_rd_addr = (state == S_SCAN)
                              ? hash3(w2, x1_r, bm_a_rd)
                              : ((((state == S_PRE) && (pre_cnt == 13'd3)) ||
                                  ((state == S_REPOS) && (rp_cnt == 13'd3)))
                                 ? hash3(w1, x1_r, bm_a_rd)
                                 : hash3(w0, x1_r, bm_a_rd));
"""),
("""    always @(posedge clk) begin
        bm_a_rd  <= bm_a[{enc_bank, bm_raddr_a}];
        bm_b_rd  <= bm_b[{enc_bank, bm_raddr_b}];
        bm_a_rd2 <= bm_a_rd;      // r0 (bm-prefetch): scan-path stage 2
    end
""",
"""    always @(posedge clk) begin
        bm_a_rd <= bm_a[{enc_bank, bm_raddr_a}];
        bm_b_rd <= bm_b[{enc_bank, bm_raddr_b}];
    end
"""),
("""            // Three-stage registered prefetch of the scan window.  In S_SCAN
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
""",
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
"""),
("""    wire        bm_hit_a   = (state == S_SCAN) && hit2;
    // Forward byte of the registered extension compare: the hit cycle uses the
    // already-registered x1_r, every S_EXT cycle the current bm_a read data.
    wire [7:0]  ext_fw_byte = (state == S_EXT) ? bm_a_rd : x1_r;
""",
"""    wire        bm_hit_a   = (state == S_SCAN) && hit2;
"""),
("""            // r0 (bm-prefetch): unconditional load, no clock enable.  The
            // source bytes are the same as before (x1_r on the hit cycle,
            // bm_a read data in S_EXT), so the flag timing is unchanged.
            ext_mis_r <= (ext_fw_byte != bm_b_rd);
""",
"""            if (state == S_EXT) ext_mis_r <= (bm_a_rd != bm_b_rd);
            if (bm_hit_a)        ext_mis_r <= (x1_r     != bm_b_rd);
"""),
("""                    praddr <= 13'd2;      // seed bm_a_rd2 = bm[1] for the S_PRE window
""",
"""                    praddr <= 13'd1;      // seed bm_a_rd = bm[1] for the S_PRE window
"""),
("""                            praddr  <= 13'd3;
""",
"""                            praddr  <= 13'd2;
"""),
("""                            praddr <= pos_next_r + 13'd2;  // seed bm_a_rd2 = bm[pos+1]
""",
"""                            praddr <= pos_next_r + 13'd1;  // seed bm_a_rd = bm[pos+1]
"""),
("""                            praddr <= pos + 13'd3;
""",
"""                            praddr <= pos + 13'd2;
"""),
]
for old_, new_ in inv:
    n = base.count(old_)
    assert n == 1, "inverse: expected 1 match, got %d for %r" % (n, old_[:70])
    base = base.replace(old_, new_, 1)
h2 = hashlib.sha256(base.encode("utf-8")).hexdigest()
assert h2 == BASE_SHA, "restore did not reach the baseline hash: " + h2
open(F, "w", encoding="utf-8", newline="").write(base)
print("RESTORED baseline", h2, "size", len(base))
