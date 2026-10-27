import io, sys, hashlib, pathlib

p = pathlib.Path(r'D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b6-a1-htab-nw\r0\changed-src\a1_deflate_core.v')
raw = p.read_bytes()
crlf = b'\r\n' in raw
src = raw.decode('utf-8').replace('\r\n', '\n')
orig = src

def rep(old, new, tag):
    global src
    n = src.count(old)
    if n != 1:
        print('FAIL', tag, 'count=', n)
        sys.exit(2)
    src = src.replace(old, new)
    print('ok  ', tag)

# ---------------------------------------------------------------- A: header
rep("""// T10.b5-a1-htab-pipe r0: one local change only -- the bm_b speculative
// address is registered (bm_b_spec_q) so the htab ERAM clk2q output never
// drives the bm_b ERAM address in the same cycle.  htab encoding, block
// format, CRCs and the emitted byte stream are unchanged.
""",
"""// T10.b6-a1-htab-nw r0: the bm_b ERAM read address is driven by fabric flops
// only (no htab ERAM clk2q -> bm_b address path) and the r4 hit-cycle
// first-extension compare is restored, so no per-match wait cycle is spent.
// The reference byte bm[ref+3] that r4 fetched from bm_b on the hit cycle is
// carried inside the hash-table entry instead, as a fourth byte field
// (htab_b3), written by the same insert port and read/bypassed by the same
// registered port as the tag/pos/b0..b2 fields.  Table encoding of
// tag/pos/b0..b2, block format, CRCs and the emitted byte stream are
// unchanged.
""", 'header')

# ---------------------------------------------------------------- B/C/D: table
rep("""    //   htab_b   : {b0,b1,b2}
""",
"""    //   htab_b   : {b0,b1,b2}
    //   htab_b3  : b3 = byte at pos+3 (T10.b6: the hit-cycle first-extension
    //              reference byte, replacing the speculative bm_b read)
""", 'htab_b comment')

rep("""    reg [23:0] htab_b   [0:1023];
""",
"""    reg [23:0] htab_b   [0:1023];
    reg [7:0]  htab_b3  [0:1023];
""", 'htab_b3 array')

rep("""    reg [23:0] htab_b_q;
    reg        htab_byp;
    reg [65:0] htab_byp_data;
""",
"""    reg [23:0] htab_b_q;
    reg [7:0]  htab_b3_q;
    reg        htab_byp;
    reg [65:0] htab_byp_data;
    reg [7:0]  htab_byp_b3;
""", 'htab_b3 regs')

# ---------------------------------------------------------------- E: remove bm_b_spec_q
rep("""    // r0 (htab-pipe): registered speculative bm_b address.  The htab read data
    // (candidate pos+3 field) is captured here one cycle before the bm_b port
    // needs it, so no htab ERAM clk2q output ever drives the bm_b ERAM address
    // in the same cycle.  The first extension compare is therefore registered
    // one cycle after the hit (one S_EXT wait cycle); the emitted bytes, the
    // match lengths and the positions are unchanged.
    reg  [12:0] bm_b_spec_q;

""", "", 'remove bm_b_spec_q decl')

# ---------------------------------------------------------------- F: hf1_r / h4_r
rep("""    reg [12:0] hf1_r;           // r0 (htab-pipe): hf_r + 1 = ref+4, precomputed
                                // in the same s1_en cycle (first S_EXT-cycle
                                // bm_b reference address; was the pre-r0
                                // hit-cycle bm_b address)
""",
"""    reg [12:0] hf1_r;           // r0 (bm-addr): hf_r + 1 = ref+4, precomputed
                                // in the same s1_en cycle (hit-cycle bm_b
                                // address, i.e. the ref+4 byte for the k=1
                                // extension compare)
    reg [7:0]  h4_r;            // r0 (htab-nw): entry byte b3 = bm[ref+3],
                                // registered together with hf_r; it is the
                                // hit-cycle k=0 reference byte (previously read
                                // from bm_b through the speculative address)
""", 'hf1_r/h4_r')

# ---------------------------------------------------------------- G: read port
rep("""        htab_b_q   <= htab_b[htab_rd_addr];
    end
""",
"""        htab_b_q   <= htab_b[htab_rd_addr];
        htab_b3_q  <= htab_b3[htab_rd_addr];
    end
""", 'htab_b3 read port')

# ---------------------------------------------------------------- H: bypass
rep("""        if (htab_we && (htab_rd_addr == s1_ins_addr))
            htab_byp_data <= s1_ins_data;
""",
"""        if (htab_we && (htab_rd_addr == s1_ins_addr)) begin
            htab_byp_data <= s1_ins_data;
            htab_byp_b3   <= bm_a_rd2;
        end
""", 'htab_b3 bypass')

# ---------------------------------------------------------------- I: write port
rep("""    always @(posedge clk) begin
        if (htab_we) htab_b[s1_ins_addr] <= {s1_b0, s1_b1, s1_b2};
    end
""",
"""    always @(posedge clk) begin
        if (htab_we) htab_b[s1_ins_addr] <= {s1_b0, s1_b1, s1_b2};
    end
    // b3 = the stream byte one past the 3-byte window (bm_a_rd2 is the byte
    // after x1_r in every htab_pref phase because the bm_a stream advances by
    // one byte per cycle there).  Written by the same insert enable/address as
    // htab_b; entries cleared by the valid sweep have htab_p3v[13] = 0, so a
    // stale b3 is never used.  Bank contents are stable while a block is
    // encoded, so this byte is exactly the bm[ref+3] that r4 read from bm_b.
    always @(posedge clk) begin
        if (htab_we) htab_b3[s1_ins_addr] <= bm_a_rd2;
    end
""", 'htab_b3 write port')

# ---------------------------------------------------------------- J: s1_en -> h4_r
rep("""                hf1_r <= hent[49:37] + 13'd1;
""",
"""                hf1_r <= hent[49:37] + 13'd1;
                h4_r  <= htab_byp ? htab_byp_b3 : htab_b3_q;
""", 'h4_r load')

# ---------------------------------------------------------------- K: ext bytes
rep("""    // Forward byte of the registered extension compare: the first S_EXT cycle
    // uses the byte registered on the hit cycle (cq_r = bm[pos+3]), every later
    // S_EXT cycle the current bm_a read data.
    // r0 (htab-pipe): the hit cycle no longer compares (its bm_b data is only
    // the previous entry's speculation), so ext_first selects cq_r.
    wire [7:0]  ext_fw_byte = (state == S_EXT)
                              ? (ext_first ? cq_r : bm_a_rd) : x1_r;
""",
"""    // Forward byte of the registered extension compare: the hit cycle uses the
    // already-registered x1_r (bm[pos+3]), every S_EXT cycle the current bm_a
    // read data.
    wire [7:0]  ext_fw_byte = (state == S_EXT) ? bm_a_rd : x1_r;
    // Reference byte of the same compare: on the hit cycle it is the entry
    // field b3 (bm[ref+3], a flop registered with hf_r), in S_EXT the current
    // bm_b read data.  r0 (htab-nw): this replaces r4's speculative bm_b read
    // (address from the htab ERAM clk2q output) without adding a wait cycle.
    wire [7:0]  ext_rf_byte = (state == S_EXT) ? bm_b_rd : h4_r;
""", 'ext bytes')

# ---------------------------------------------------------------- L: bm_b address
rep("""    // r0 (htab-pipe): the bm_b speculative address is the last ERAM-clk2q ->
    // address path in the scan loop.  It is now taken from bm_b_spec_q, a
    // fabric flop loaded one cycle earlier from the htab read data (or from the
    // same-address write-first bypass data, also a flop), so the RAM output
    // register only ever drives a plain flop.  Every other source of this port
    // address is a flop as well (hf1_r / ext_faddr / raddr).  Priority is
    // unchanged: s1 entry speculation > S_EXT reference byte > window read.
    wire [12:0] bm_raddr_b = s1_en                ? bm_b_spec_q
                           : (state == S_EXT)     ? ext_faddr
                           :                        raddr;
    always @(posedge clk) begin
        if (s1_en)
            bm_b_spec_q <= htab_byp ? htab_byp_data[49:37] : htab_q[49:37];
    end
""",
"""    // r0 (htab-nw): the bm_b port no longer carries a speculative candidate
    // read, so every source of its address is a fabric flop (hf1_r / ext_faddr
    // / raddr) and no htab ERAM clk2q output reaches a RAM address.  Priority
    // is unchanged: hit-cycle prefetch (ref+4) > S_EXT reference byte > window
    // read.  During S_SCAN the port reads the (unused) window address.
    wire [12:0] bm_raddr_b = bm_hit_a          ? hf1_r
                           : (state == S_EXT)  ? ext_faddr
                           :                     raddr;
""", 'bm_raddr_b')

# ---------------------------------------------------------------- M: hit path
rep("""                            // r0 (htab-pipe): the speculative bm_b read issued
                            // one cycle before this hit (address bm_b_spec_q =
                            // ref+3) returns bm[ref+3] on the next cycle, so the
                            // first extension compare is cq_r = bm[pos+3] versus
                            // that registered byte.  S_EXT waits one cycle for it,
                            // then the ports run one byte ahead (pos+4 / ref+4) as
                            // before: one registered compare per cycle, one
                            // matching byte per cycle.
                            cq_r      <= x1_r;
                            ext_first <= 1'b1;
                            ext_raddr <= p3_r + 13'd1;
                            ext_faddr <= hf1_r;
""",
"""                            // r0 (htab-nw): bm[pos+3] is already registered
                            // (x1_r) and the reference byte bm[ref+3] is the
                            // entry field h4_r, so the first compare is
                            // available on the hit cycle without any bm_b read.
                            // The ports are then shifted one byte ahead
                            // (pos+4 / ref+4) so every later compare is
                            // registered one cycle before it is consumed.
                            cq_r      <= x1_r;
                            ext_first <= 1'b1;
                            ext_raddr <= p3_r + 13'd2;
                            ext_faddr <= hf_r + 13'd2;
""", 'hit path ext addr')

# ---------------------------------------------------------------- N: ext_mis_r
rep("""            ext_mis_r <= (ext_fw_byte != bm_b_rd);
""",
"""            ext_mis_r <= (ext_fw_byte != ext_rf_byte);
""", 'ext_mis_r')

# ---------------------------------------------------------------- O: S_EXT body
rep("""                S_EXT: begin
                    // r0 (htab-pipe): the first S_EXT cycle only waits for the
                    // registered first-extension compare (cq_r vs the bm_b data
                    // of the speculative read issued on the hit cycle).  The
                    // addresses loaded on the hit cycle already point at the
                    // k=1 pair and the loop-stop flags keep the values loaded by
                    // the hit, so the decision sequence (and therefore len_r and
                    // every emitted byte) is identical, shifted by one cycle.
                    if (ext_first) begin
                        ext_first <= 1'b0;
                        // The pair loaded on the hit cycle is consumed by the
                        // first registered compare; advance the ports to the
                        // k=1 pair now so the decision cycles below see exactly
                        // the same one-byte-per-cycle stream as before.
                        ext_raddr <= ext_raddr + 13'd1;
                        ext_faddr <= ext_faddr + 13'd1;
                    end else begin
                        ext_zero_r <= (ext_rem == 13'd1);
                        len_cap_r  <= (len_r == 9'd256);
                        if (ext_mis_r) begin
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
                    end
                end
""",
"""                S_EXT: begin
                    // The forward/reference byte pair for extension byte k was
                    // compared during cycle k-1 and lives in ext_mis_r, so the
                    // state enable is driven by a flop, not by ERAM clk2q.
                    ext_first <= 1'b0;
                    // ext_raddr/ext_faddr run one byte ahead of the compare
                    // (pos+4+k / ref+4+k); the flag itself is exact: registered
                    // at cycle k-1, consumed at cycle k, same cycle count as
                    // the combinational compare it replaces.
                    // r2: the loop-stop flags track ext_rem/len_r on every
                    // S_EXT cycle, independent of the byte compare.
                    ext_zero_r <= (ext_rem == 13'd1);
                    len_cap_r  <= (len_r == 9'd256);
                    if (ext_mis_r) begin
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
                end
""", 'S_EXT body')

p.write_bytes(src.replace('\n', '\r\n').encode('utf-8') if crlf else src.encode('utf-8'))
out = p.read_bytes()
print('crlf', crlf, 'bytes', len(out), 'sha', hashlib.sha256(out).hexdigest())
