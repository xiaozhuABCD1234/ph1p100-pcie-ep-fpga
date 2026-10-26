#!/usr/bin/env python3
"""T10.a1-htab-eram: split the 66-bit hash table into ERAM-friendly arrays.

Base: a1_deflate_core.v == 1dca732b19f1eb2fbe9866c0bae369d5b10b52e72330b28e25adf3ebeff37e4d

Changes (only a1_deflate_core.v):
  1. htab[0:1023] 66-bit + htab_v 1-bit -> htab_tag[16]/htab_p3v[14]/htab_pos[13]/htab_b[24]
     (valid folded into htab_p3v[13]).
  2. Unconditional registered read port for every array (ERAM template); the
     write-first same-address bypass is registered next to the RAM output
     (htab_byp/htab_byp_data) so the stage-1 consumer still sees the data one
     cycle after the read address and sees the new write data on a collision.
  3. Single no-reset write port per array.  The reset of the old htab_v array is
     replaced by a 1024-cycle valid-clear sweep through the htab_p3v write port;
     S_WAIT is gated on htab_clr_done so the first encode starts from an
     all-invalid table (identical reset semantics, no per-byte cost).
"""
import hashlib
import sys

PATH = r"upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v"
BASE = "1dca732b19f1eb2fbe9866c0bae369d5b10b52e72330b28e25adf3ebeff37e4d"

A_OLD = """    // 3-byte hash table: {tag[15:0], pos+3[12:0], pos[12:0], b0,b1,b2}
    reg [65:0] htab [0:1023];
    reg        htab_v [0:1023];
    reg [65:0] htab_rdata;
    reg        htab_rvalid;
"""

A_NEW = """    // 3-byte hash table, split into ERAM-friendly arrays (valid is folded into
    // the top bit of htab_p3v):
    //   htab_tag : blk_tag[15:0]
    //   htab_p3v : {valid, pos+3[12:0]}
    //   htab_pos : pos[12:0]
    //   htab_b   : {b0,b1,b2}
    // One unconditional registered read port per array is the ERAM template;
    // the same-address write-first bypass is re-applied on the registered
    // outputs (htab_byp) instead of inside the RAM read process.
    reg [15:0] htab_tag [0:1023];
    reg [13:0] htab_p3v [0:1023];
    reg [12:0] htab_pos [0:1023];
    reg [23:0] htab_b   [0:1023];
    reg [15:0] htab_tag_q;
    reg [13:0] htab_p3v_q;
    reg [12:0] htab_pos_q;
    reg [23:0] htab_b_q;
    reg        htab_byp;
    reg [65:0] htab_byp_data;
    // Valid-clear sweep after reset (replaces the old valid-bit reset loop).
    reg [9:0]  htab_clr_cnt;
    reg        htab_clr_act;
    reg        htab_clr_done;
"""

B_OLD = """    wire [65:0] hent  = htab_rdata;
    wire        hent_v = htab_rvalid;
    wire [12:0] hent_pos = hent[36:24];
"""

B_NEW = """    wire [65:0] htab_q  = {htab_tag_q, htab_p3v_q[12:0], htab_pos_q, htab_b_q};
    wire [65:0] hent    = htab_byp ? htab_byp_data : htab_q;
    wire        hent_v  = htab_byp ? 1'b1 : htab_p3v_q[13];
    wire [12:0] hent_pos = hent[36:24];
"""

C_OLD = """    always @(posedge clk) begin
        if (htab_pref) begin
            if (htab_we && (htab_rd_addr == s1_ins_addr)) begin
                htab_rdata  <= s1_ins_data;
                htab_rvalid <= 1'b1;
            end else begin
                htab_rdata  <= htab[htab_rd_addr];
                htab_rvalid <= htab_v[htab_rd_addr];
            end
        end
    end

    // Hash-table write port: single enable/address/data, no reset, so the
    // 1024x66 table can infer as ERAM instead of LUT-RAM (the read stays one
    // cycle; the same-address write-first bypass on htab_rdata is unchanged).
    always @(posedge clk) begin
        if (htab_we)
            htab[s1_ins_addr] <= s1_ins_data;
    end
"""

C_NEW = """    always @(posedge clk) begin
        htab_tag_q <= htab_tag[htab_rd_addr];
        htab_p3v_q <= htab_p3v[htab_rd_addr];
        htab_pos_q <= htab_pos[htab_rd_addr];
        htab_b_q   <= htab_b[htab_rd_addr];
    end

    // Same-address write-first bypass, registered next to the RAM output: the
    // stage-1 consumer sees the new entry exactly one cycle after the read
    // address was issued, as before.
    always @(posedge clk) begin
        htab_byp <= htab_we && (htab_rd_addr == s1_ins_addr);
        if (htab_we && (htab_rd_addr == s1_ins_addr))
            htab_byp_data <= s1_ins_data;
    end

    // Hash-table write ports: one enable/address/data per array, no reset.
    // htab_p3v also carries valid, so the post-reset sweep clears it through
    // this same single write port.
    wire htab_p3v_we = htab_clr_act | htab_we;
    wire [9:0] htab_p3v_waddr = htab_clr_act ? htab_clr_cnt : s1_ins_addr;
    wire [13:0] htab_p3v_wdata = htab_clr_act ? 14'd0
                                               : {1'b1, (s1_pos_r + 13'd3)};
    always @(posedge clk) begin
        if (htab_we) htab_tag[s1_ins_addr] <= blk_tag;
    end
    always @(posedge clk) begin
        if (htab_p3v_we) htab_p3v[htab_p3v_waddr] <= htab_p3v_wdata;
    end
    always @(posedge clk) begin
        if (htab_we) htab_pos[s1_ins_addr] <= s1_pos_r;
    end
    always @(posedge clk) begin
        if (htab_we) htab_b[s1_ins_addr] <= {s1_b0, s1_b1, s1_b2};
    end

    // Valid-clear sweep: 1024 entries after every reset.  The encoder waits in
    // S_WAIT until it finishes, so the first block sees an all-invalid table
    // exactly like the old valid-bit reset (a fixed 1024-cycle start-up latency,
    // not a per-byte cost).
    always @(posedge clk) begin
        if (!rst_n) begin
            htab_clr_cnt  <= 10'd0;
            htab_clr_act  <= 1'b1;
            htab_clr_done <= 1'b0;
        end else if (htab_clr_act) begin
            htab_clr_cnt <= htab_clr_cnt + 10'd1;
            if (htab_clr_cnt == 10'h3FF) begin
                htab_clr_act  <= 1'b0;
                htab_clr_done <= 1'b1;
            end
        end
    end
"""

D_OLD = """            for (i = 0; i < 1024; i = i + 1)
                htab_v[i] <= 1'b0;
"""
D_NEW = ""

E_OLD = """            if (htab_we) begin
                htab_v[s1_ins_addr] <= 1'b1;
            end
"""
E_NEW = ""

F_OLD = """                S_WAIT: begin
                    if (blk_avail) begin
"""
F_NEW = """                S_WAIT: begin
                    if (blk_avail && htab_clr_done) begin
"""

CHECKS = [
    ("htab[", 0),
    ("htab_v", 0),
    ("htab_rdata", 0),
    ("htab_rvalid", 0),
    ("htab_pref", 2),  # declaration + praddr/x1_r prefetch guard
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
    out = hashlib.sha256(src.encode("utf-8")).hexdigest()
    print("PATCHED", out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
