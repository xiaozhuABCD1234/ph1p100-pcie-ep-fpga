// =============================================================================
// a1_deflate_core.v -- T10 A+ v1 DEFLATE encoder core (test-only, P2)
//
// Input : a sequence of transform-domain blocks (1 block = 1 two-row Bayer
//         pair, <= 4800 B), byte handshake, stream framed by in_sop /
//         in_blk_end / in_stream_end.
// Output: one standard zlib member (RFC1950), 0x78 0x9C + DEFLATE subset
//         (fixed Huffman BTYPE=01 or stored BTYPE=00) + big-endian Adler-32.
//
// Real LZ77: 3-byte hash table (1024 entries, 16-bit per-stream tag),
// block-local 2048 B window, greedy length 3..258, single candidate.
// Fixed-Huffman candidate is costed exactly; block-level stored fallback
// (including byte-align cost).  Early abort once the fixed candidate can no
// longer beat stored -- this is the "candidate overflow" guard.
//
// No dynamic Huffman.  No cross-block references.  Synthesizable style.
//
// T10.b6-a1-htab-nw r0: the bm_b ERAM read address is driven by fabric flops
// only (no htab ERAM clk2q -> bm_b address path) and the r4 hit-cycle
// first-extension compare is restored, so no per-match wait cycle is spent.
// The reference byte bm[ref+3] that r4 fetched from bm_b on the hit cycle is
// carried inside the hash-table entry instead, as a fourth byte field
// (htab_b3), written by the same insert port and read/bypassed by the same
// registered port as the tag/pos/b0..b2 fields.  Table encoding of
// tag/pos/b0..b2, block format, CRCs and the emitted byte stream are
// unchanged.
// =============================================================================
`timescale 1ns / 1ps

module a1_deflate_core #(
    // T10.ah-honly H: 1 = frozen 8-bit output (b6 bench), 2 = 16-bit output
    // (2 stream bytes per accepted transfer, internal core->frame_top only).
    parameter integer OUT_BYTES = 1
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        abort,
    input  wire        in_valid,
    output wire        in_ready,
    input  wire [7:0]  in_data,
    input  wire        in_sop,
    input  wire        in_blk_end,
    input  wire        in_stream_end,
    output wire        out_valid,
    input  wire        out_ready,
    output wire [8*OUT_BYTES-1:0] out_data,
    output wire        out_keep,
    output wire        out_last,
    output reg         done,
    output wire        busy,
    output reg  [31:0] stat_blocks,
    output reg  [31:0] stat_fixed,
    output reg  [31:0] stat_stored,
    output reg  [31:0] stat_literals,
    output reg  [31:0] stat_matches,
    output reg  [31:0] stat_cand_aborts,
    output reg  [31:0] stat_stall,
    output reg  [31:0] stat_max_match,
    output reg  [31:0] stat_max_dist,
    // T10.b11-aplus-read: pure observation tap of the main FSM register.  No
    // logic, no protocol and no output change; only used by the status packet.
    output wire [4:0]  dbg_state
);

    localparam [4:0] S_IDLE      = 5'd0;
    localparam [4:0] S_HDR       = 5'd1;
    localparam [4:0] S_WAIT      = 5'd2;
    localparam [4:0] S_BHDR      = 5'd3;
    localparam [4:0] S_PRE       = 5'd4;
    localparam [4:0] S_SCAN      = 5'd5;
    localparam [4:0] S_EXT       = 5'd6;
    localparam [4:0] S_MLEN      = 5'd7;
    localparam [4:0] S_MDIST     = 5'd8;
    localparam [4:0] S_REPOS     = 5'd9;
    localparam [4:0] S_EOB       = 5'd10;
    localparam [4:0] S_EODONE    = 5'd11;
    localparam [4:0] S_DECIDE    = 5'd12;
    localparam [4:0] S_REPLAY_R  = 5'd13;
    localparam [4:0] S_REPLAY_E  = 5'd14;
    localparam [4:0] S_SHDR      = 5'd15;
    localparam [4:0] S_SALIGN    = 5'd16;
    localparam [4:0] S_SLEN      = 5'd17;
    localparam [4:0] S_SDATA_R   = 5'd18;
    localparam [4:0] S_SDATA_D   = 5'd19;
    localparam [4:0] S_TRAIL     = 5'd20;
    localparam [4:0] S_TALIGN    = 5'd21;
    localparam [4:0] S_TADLER    = 5'd22;
    localparam [4:0] S_DRAIN     = 5'd23;
    localparam [4:0] S_EODONE2   = 5'd24;
    localparam [4:0] S_REPLAY_RD = 5'd25;
    localparam [4:0] S_MCHK      = 5'd26;
    localparam [4:0] S_REPLAY_E2 = 5'd27;

    localparam [12:0] MAX_BLOCK  = 13'd4800;
    localparam [12:0] MAX_MATCH  = 13'd258;
    localparam [12:0] MAX_DIST   = 13'd2048;

    // ------------------------------------------------------------------ state
    reg [4:0]  state;
    reg        stream_active;
    reg        enc_busy;

    // T10.b11: observation tap (see port comment).  Reads the FSM register only.
    assign dbg_state = state;

    // block loader
    reg        ld_bank;
    reg [12:0] ld_ptr;
    reg [12:0] blk_len0, blk_len1;
    reg        blk_final0, blk_final1;
    reg        blk_full0, blk_full1;

    // active block
    reg        enc_bank;
    reg [12:0] blk_n;
    // r1: precomputed insert/hit limit = blk_n - 2 (removes the 13-bit adder from s1_ok)
    reg [12:0] lim2;
    // r0 (area-map): precomputed clamp limits for the bm_a read address.  The
    // S_REPOS case used clamp_addr(pos + k, blk_n) = (pos+k < blk_n) ? pos+k :
    // blk_n-1, which serialises a 13-bit adder and a 13-bit comparator from
    // pos_reg in the same cycle.  With limk = blk_n - k (saturating at 0) the
    // compare is (pos < limk), so the adder and the comparator start from pos
    // in parallel.  Equivalent for blk_n >= 1 and pos+k < 2^13 (blk_n <= 4800).
    reg [12:0] lim1, lim3;
    reg [12:0] last_a;   // blk_n - 1 : the clamp fallback address
    reg        blk_last;
    reg [15:0] blk_tag;
    reg [12:0] pos;
    reg [12:0] raddr, faddr;
    reg [7:0]  w0, w1, w2;
    reg [12:0] cand_pos;
    reg [7:0]  cq_r;
    reg [12:0] ext_rem;
    reg        ext_first;   // first S_EXT cycle: compare the byte loaded at the hit
    // 1-bit precomputed loop-stop tests (updated with ext_rem / len_r) so the
    // S_EXT state-enable path does not contain the 13-bit/9-bit compares.
    reg        ext_zero_r;  // ext_rem == 0
    reg        len_cap_r;   // len_r == 257
    reg [12:0] ext_raddr, ext_faddr;
    reg [12:0] dist_r;
    reg [8:0]  len_r;
    reg [12:0] pre_cnt, rp_cnt;
    reg [31:0] cand_bits, stored_bits;
    reg        cand_abort;
    reg [12:0] rem_blk;
    reg [31:0] thresh_base, thresh_lit;
    reg [31:0] thresh_lit8, thresh_lit9;   // thresh_lit - 8 / thresh_lit - 9
    reg [31:0] cand_after_len, thresh_match_r;

    // candidate bit packer: 3-stage pipeline + 4-entry write FIFO.
    // p0 = registered code/extra-bit value, p1 = registered shift result,
    // p2 = accumulate/word select.  cmem writes are from the FIFO head.
    reg [31:0] cacc;
    reg [3:0]  pbit_off;
    reg [15:0] cstage;
    reg        clane;
    reg [12:0] cwptr;
    reg [12:0] cand_nbytes;
    reg        p0_valid;
    reg [15:0] p0_value;
    reg [4:0]  p0_nbits;
    reg [3:0]  p0_off;
    reg        p0_rst;
    reg        p1_valid;
    reg [31:0] p1_pshift;
    reg [4:0]  p1_nbits;
    reg [3:0]  p1_off;
    reg        p1_rst;
    reg [15:0] p2_wdata;
    reg        p2_we;
    reg [28:0] wq_mem [0:3];   // {cmem addr[12:0], data[15:0]}
    reg [1:0]  wq_wptr, wq_rptr;
    reg [2:0]  wq_count;
    // 4-entry output skid FIFO: {last, nbits1[3:0], nbits0[3:0], byte1[7:0], byte0[7:0]}.
    // One entry can carry one or two stream bytes so the replay can move
    // 2 B/cycle while the non-replay paths keep their single-byte pushes.
    reg [24:0] opq_mem [0:3];
    reg [1:0]  opq_wptr, opq_rptr;
    reg [2:0]  opq_count;
    reg [3:0]  opq_bit_off;

    // match pipeline stage: distance code and position update are registered
    // between S_MLEN and S_MDIST so the distance arithmetic does not feed
    // pos_reg[*].ce in the same cycle.
    reg [13:0] dval_r;
    reg [4:0]  dtot_r;
    reg [12:0] pos_next_r;
    reg [12:0] rem_next_r;

    // replay (cmem is a synchronous-read memory; one wait state per 32-bit word)
    reg [12:0] rb_word;      // 16-bit packet-word index (even; 2 words per read)
    reg [10:0] cmem_raddr;   // 32-bit cmem address
    reg [31:0] cmem_rdata;
    reg [15:0] rbits_left;

    // stored path
    reg [3:0]  hdr_idx;
    reg [3:0]  slen_idx;
    reg [12:0] sdata_ptr;
    // Byte holding register: the synchronous bm read is issued two cycles ahead,
    // so the byte for the current cycle is kept here and only advanced when the
    // output FIFO accepts it (stall safe: a stalled cycle re-presents the same
    // byte instead of the next read word).
    reg [7:0]  sd_byte;
    // Stall hold: the registered read data is bm[raddr(t-1)], i.e. correct in a
    // continuously advancing stream.  On the first stalled cycle the address
    // stops moving, so latch that cycle's value here and use it for the next
    // accepted byte instead of the (one too far) drifted read data.
    reg [7:0]  sd_hold;
    reg        sd_in_q;    // previous cycle was S_SDATA_R
    reg        sd_acc_q;   // previous S_SDATA_R cycle accepted
    reg [3:0]  tadler_idx;

    // stream output bit accumulator
    reg [23:0] oacc;
    reg [3:0]  obits;

    // output FIFO: 16 entries, {last, keep(2-byte), byte1[7:0], byte0[7:0]}.
    // In 8-bit mode a keep=1 entry is split over two cycles on the read side,
    // so the frozen 8-bit consumer still sees exactly one byte per transfer.
    reg [17:0] fifo_mem [0:15];
    reg [3:0]  fifo_wptr, fifo_rptr;
    reg [4:0]  fifo_count;

    // Adler-32 over transform-domain bytes.  The per-byte path uses wide
    // block-local accumulators; modulo 65521 is folded at block end.
    reg [15:0] adler_a, adler_b;
    reg [7:0]  adler_data_r;
    reg        adler_sop_r;
    reg        adler_pend;
    reg        adler_blk_q;
    reg [1:0]  adler_red_st;
    reg [21:0] adler_a_w;
    reg [34:0] adler_b_w;
    reg [16:0] adler_fold_a;
    reg [20:0] adler_fold_b;
    reg [16:0] adler_red_a;

    // buffers: two ping-pong blocks, each duplicated (current / reference read)
    reg [7:0]  bm_a [0:16383];
    reg [7:0]  bm_b [0:16383];

    // 3-byte hash table, split into ERAM-friendly arrays (valid is folded into
    // the top bit of htab_p3v):
    //   htab_tag : blk_tag[15:0]
    //   htab_p3v : {valid, pos+3[12:0]}
    //   htab_pos : pos[12:0]
    //   htab_b   : {b0,b1,b2}
    //   htab_b3  : b3 = byte at pos+3 (T10.b6: the hit-cycle first-extension
    //              reference byte, replacing the speculative bm_b read)
    // One unconditional registered read port per array is the ERAM template;
    // the same-address write-first bypass is re-applied on the registered
    // outputs (htab_byp) instead of inside the RAM read process.
    reg [15:0] htab_tag [0:1023];
    reg [13:0] htab_p3v [0:1023];
    reg [12:0] htab_pos [0:1023];
    reg [23:0] htab_b   [0:1023];
    reg [7:0]  htab_b3  [0:1023];
    reg [15:0] htab_tag_q;
    reg [13:0] htab_p3v_q;
    reg [12:0] htab_pos_q;
    reg [23:0] htab_b_q;
    reg [7:0]  htab_b3_q;
    reg        htab_byp;
    reg [65:0] htab_byp_data;
    reg [7:0]  htab_byp_b3;
    // Valid-clear sweep after reset (replaces the old valid-bit reset loop).
    reg [9:0]  htab_clr_cnt;
    reg        htab_clr_act;
    reg        htab_clr_done;

    // T10.ah-honly H: 32-bit candidate words.  2048x32 holds exactly the same
    // bits as the frozen 4096x16; the packer still emits 16-bit words and a
    // write-combine stage pairs them (address bit 0 selects the half).  The
    // replay reads one 32-bit word per access and emits 4 stream bytes.
    reg [31:0] cmem [0:2047];
    reg [15:0] cmem_lo;
    reg        cmem_lo_pend;
    reg [11:0] cmem_lo_addr;
    // Single registered write port for cmem.  All write sources are merged into
    // one enable/address/data and applied by a dedicated no-reset always block
    // (the same structure frame_top uses for smem, which maps to ERAM).  Before
    // this, the writes came from several branches of the main reset-controlled
    // process and TD expanded cmem into 65536 registers (SYN-5114), which is
    // what pushed the slice count over the device limit.
    reg        cmem_we_c;
    reg [11:0] cmem_waddr_c;
    reg [15:0] cmem_wdata_c;

    // Buffer read data is synchronously addressed: one registered address and
    // one registered data word per array (a single read port each).  The two
    // arrays hold identical bytes, so in S_PRE/S_REPOS bm_a serves the x2
    // prefetch stream (praddr) while bm_b serves the w0..w2 window (raddr).
    // Every address is issued one cycle before the byte is consumed, so the
    // symbol rate stays one per cycle.  Synchronous read + registered address
    // + single write port is the ERAM template, which removes the 8,432 LUT
    // distributed-RAM read long lines found by the area-map route.
    reg  [7:0] bm_a_rd;
    // r0 (bm-prefetch): second read-data stage.  The bm_a ERAM clk2q output now
    // feeds only this flop, so the scan byte stream consumed by hash3 and by the
    // x1_r window shift comes from bm_a_rd2 instead of the ERAM output register.
    reg  [7:0] bm_a_rd2;
    reg  [7:0] bm_b_rd;
    // Registered two-stage prefetch: x1_r = bm[pos+3]; bm_a_rd itself is the
    // bm[pos+4] stage, so the htab read address still uses registered bytes
    // only (w2, x1_r, bm_a_rd in S_SCAN).  One position is retired per cycle.
    reg  [7:0] x1_r;
    reg  [12:0] praddr;
    // r10: registered pos+3 for the S_SCAN match read address (no per-position adder)
    reg [12:0] p3_r;

    // ------------------------------------------------------------------
    // c-lite two-cycle hit/threshold path.
    //   stage 1 (registered): hdist = s1_pos - hent_pos, tag/byte compare,
    //     distance range and the htab insert for the speculative position
    //     s1_pos (= pos+1 while scanning, = pos in the last PRE/REPOS cycle).
    //   stage 2: hit decision + literal/threshold enable from those registers.
    // The S_SCAN pointer only moves in stage 2, so the symbol rate is still
    // one per cycle; the speculative position is inserted one cycle early and
    // covered by the same-cycle write-first read bypass.
    // ------------------------------------------------------------------
    reg [12:0] s1_pos_r;        // stage-1 position
    reg [12:0] hp_r;            // stage-1 hent_pos (feeds cand_pos / hdist)
    reg [12:0] hf_r;            // stage-1 hent pos+3 field (feeds faddr)
    reg [12:0] hf1_r;           // r0 (bm-addr): hf_r + 1 = ref+4, precomputed
                                // in the same s1_en cycle (hit-cycle bm_b
                                // address, i.e. the ref+4 byte for the k=1
                                // extension compare)
    reg [7:0]  h4_r;            // r0 (htab-nw): entry byte b3 = bm[ref+3],
                                // registered together with hf_r; it is the
                                // hit-cycle k=0 reference byte (previously read
                                // from bm_b through the speculative address)
    reg        hb_r;            // stage-1 tag/byte/valid compare
    reg        rng1_r;          // stage-1 distance/range test (registered with hb_r)
    reg        s1_ok_r;         // stage-1 (s1_pos_r < lim2) (registered with hb_r)
    reg        s1_last_r;       // stage-1 (s1_pos_r + 1 >= blk_n) (registered with hb_r)
    reg        s1_vld_r;        // stage-1 result valid
    // r0 (hit-pipe): the stage-1 distance/range test moved to stage 2 (it is
    // computed from the hp_r register and pos), so no ERAM clk2q signal drives
    // the hit/state logic any more.  hd_r/hrg_r are gone.
    // T10.a1-pipe-split r0: the range test is now registered at stage 1
    // (rng1_r, computed from hent_pos/s1_pos_r/lim2 next to hb_r), so stage 2
    // (hit2) is built from flops only.
    // Extension-byte mismatch, registered: cycle k holds the compare result for
    // extension byte k, so the S_EXT state enable is driven by a flop only.
    reg        ext_mis_r;

    // ------------------------------------------------------------- functions
    function [8:0] rev9;
        input [8:0] v;
        input [3:0] n;
        integer i;
        begin
            rev9 = 9'd0;
            for (i = 0; i < 9; i = i + 1)
                if (i < n) rev9 = (rev9 << 1) | ((v >> i) & 1'b1);
        end
    endfunction

    // fixed Huffman literal/length code (RFC1951 3.2.6), bit-reversed
    function [8:0] lit_rev;
        input [8:0] sym;
        begin
            if (sym < 9'd144)
                lit_rev = rev9(9'h030 + sym, 4'd8);
            else if (sym < 9'd256)
                lit_rev = rev9(9'h190 + (sym - 9'd144), 4'd9);
            else if (sym < 9'd280)
                lit_rev = rev9(sym - 9'd256, 4'd7);
            else
                lit_rev = rev9(9'h0C0 + (sym - 9'd280), 4'd8);
        end
    endfunction

    function [3:0] lit_len;
        input [8:0] sym;
        begin
            if (sym < 9'd144)       lit_len = 4'd8;
            else if (sym < 9'd256)  lit_len = 4'd9;
            else if (sym < 9'd280)  lit_len = 4'd7;
            else                    lit_len = 4'd8;
        end
    endfunction

    function [8:0] len_code;
        input [8:0] l;
        begin
            if (l <= 9'd10)        len_code = 9'd257 + (l - 9'd3);
            else if (l == 9'd258)  len_code = 9'd285;
            else if (l <= 9'd18)   len_code = 9'd265 + ((l - 9'd11) >> 1);
            else if (l <= 9'd34)   len_code = 9'd269 + ((l - 9'd19) >> 2);
            else if (l <= 9'd66)   len_code = 9'd273 + ((l - 9'd35) >> 3);
            else if (l <= 9'd130)  len_code = 9'd277 + ((l - 9'd67) >> 4);
            else                   len_code = 9'd281 + ((l - 9'd131) >> 5);
        end
    endfunction

    function [3:0] len_extra_bits;
        input [8:0] l;
        begin
            if (l <= 9'd10 || l == 9'd258) len_extra_bits = 4'd0;
            else if (l <= 9'd18)   len_extra_bits = 4'd1;
            else if (l <= 9'd34)   len_extra_bits = 4'd2;
            else if (l <= 9'd66)   len_extra_bits = 4'd3;
            else if (l <= 9'd130)  len_extra_bits = 4'd4;
            else                   len_extra_bits = 4'd5;
        end
    endfunction

    function [4:0] len_extra_val;
        input [8:0] l;
        begin
            if (l <= 9'd10 || l == 9'd258) len_extra_val = 5'd0;
            else if (l <= 9'd18)   len_extra_val = l - 9'd11;
            else if (l <= 9'd34)   len_extra_val = l - 9'd19;
            else if (l <= 9'd66)   len_extra_val = l - 9'd35;
            else if (l <= 9'd130)  len_extra_val = l - 9'd67;
            else if (l <= 9'd257)  len_extra_val = l - 9'd131;
            else                   len_extra_val = 5'd0;
        end
    endfunction

    function [4:0] dist_code;
        input [12:0] d;
        begin
            if (d <= 13'd4)        dist_code = d[4:0] - 5'd1;
            else if (d <= 13'd6)   dist_code = 5'd4;
            else if (d <= 13'd8)   dist_code = 5'd5;
            else if (d <= 13'd12)  dist_code = 5'd6;
            else if (d <= 13'd16)  dist_code = 5'd7;
            else if (d <= 13'd24)  dist_code = 5'd8;
            else if (d <= 13'd32)  dist_code = 5'd9;
            else if (d <= 13'd48)  dist_code = 5'd10;
            else if (d <= 13'd64)  dist_code = 5'd11;
            else if (d <= 13'd96)  dist_code = 5'd12;
            else if (d <= 13'd128) dist_code = 5'd13;
            else if (d <= 13'd192) dist_code = 5'd14;
            else if (d <= 13'd256) dist_code = 5'd15;
            else if (d <= 13'd384) dist_code = 5'd16;
            else if (d <= 13'd512) dist_code = 5'd17;
            else if (d <= 13'd768) dist_code = 5'd18;
            else if (d <= 13'd1024)dist_code = 5'd19;
            else if (d <= 13'd1536)dist_code = 5'd20;
            else                   dist_code = 5'd21;
        end
    endfunction

    function [11:0] dist_base;
        input [4:0] c;
        begin
            case (c)
                5'd0:  dist_base = 12'd1;
                5'd1:  dist_base = 12'd2;
                5'd2:  dist_base = 12'd3;
                5'd3:  dist_base = 12'd4;
                5'd4:  dist_base = 12'd5;
                5'd5:  dist_base = 12'd7;
                5'd6:  dist_base = 12'd9;
                5'd7:  dist_base = 12'd13;
                5'd8:  dist_base = 12'd17;
                5'd9:  dist_base = 12'd25;
                5'd10: dist_base = 12'd33;
                5'd11: dist_base = 12'd49;
                5'd12: dist_base = 12'd65;
                5'd13: dist_base = 12'd97;
                5'd14: dist_base = 12'd129;
                5'd15: dist_base = 12'd193;
                5'd16: dist_base = 12'd257;
                5'd17: dist_base = 12'd385;
                5'd18: dist_base = 12'd513;
                5'd19: dist_base = 12'd769;
                5'd20: dist_base = 12'd1025;
                5'd21: dist_base = 12'd1537;
                default: dist_base = 12'd1;
            endcase
        end
    endfunction

    function [3:0] dist_extra_bits;
        input [4:0] c;
        begin
            if (c < 5'd4) dist_extra_bits = 4'd0;
            else          dist_extra_bits = (c >> 1) - 4'd1;
        end
    endfunction

    function [9:0] hash3;
        input [7:0] a, b, c;
        begin
            hash3 = {a, b[1:0]} ^ {b[5:0], c[3:0]} ^ {c[7:0], a[1:0]};
        end
    endfunction

    function [12:0] clamp_addr;
        input [12:0] a;
        input [12:0] n;
        begin
            clamp_addr = (a < n) ? a : (n - 13'd1);
        end
    endfunction

    function [31:0] stored_cost;
        input [3:0]  off;
        input [12:0] n;
        reg [4:0]    pad;
        begin
            pad = (5'd8 - ({1'b0, off} + 5'd3)) & 5'd7;
            stored_cost = 32'd3 + {27'd0, pad} + 32'd32 + ({19'd0, n} << 3);
        end
    endfunction

    // --------------------------------------------------------- combinational
    wire blk_avail   = blk_full0 | blk_full1;
    wire sel_is_b0   = blk_full0;
    wire [12:0] sel_len   = sel_is_b0 ? blk_len0 : blk_len1;
    wire        sel_final = sel_is_b0 ? blk_final0 : blk_final1;

    wire [65:0] htab_q  = {htab_tag_q, htab_p3v_q[12:0], htab_pos_q, htab_b_q};
    wire [65:0] hent    = htab_byp ? htab_byp_data : htab_q;
    wire        hent_v  = htab_byp ? 1'b1 : htab_p3v_q[13];
    wire [12:0] hent_pos = hent[36:24];

    // Stage 1: the speculative position (s1_pos_r) is compared against the
    // entry that the previous cycle's htab read returned.
    wire        s1_en = (state == S_SCAN) ||
                        ((state == S_PRE)   && (pre_cnt == 13'd3)) ||
                        ((state == S_REPOS) && (rp_cnt == 13'd3));
    // Bytes of the stage-1 window: (pos+1,pos+2,pos+3) in S_SCAN,
    // (pos,pos+1,pos+2) in the last PRE/REPOS cycle (cq is that cycle's read).
    wire [7:0]  s1_b0 = (state == S_SCAN) ? w1 : w0;
    wire [7:0]  s1_b1 = (state == S_SCAN) ? w2 : w1;
    wire [7:0]  s1_b2 = x1_r;
    wire        s1_bytes = hent_v && (hent[65:50] == blk_tag) &&
                           (hent[23:16] == s1_b0) &&
                           (hent[15:8]  == s1_b1) &&
                           (hent[7:0]   == s1_b2);
    wire        s1_ok = (s1_pos_r < lim2);
    // T10.a1-pipe-split r0: stage-1 form of the distance/range test,
    // registered with hb_r.  At the cycle the stage-1 result is consumed, pos
    // equals stage-1's s1_pos_r of the previous cycle (they advance in lock
    // step on the literal path; on the S_PRE/S_REPOS rewind cycle s1_pos_r was
    // loaded with pos and pos is held), so the old stage-2 predicate
    //   (hp_r < pos) && (pos - hp_r <= MAX_DIST) && (pos < lim2)
    // is, with hp_r/pos replaced by hent_pos/s1_pos_r, exactly
    //   (hent_pos < s1_pos_r) && (s1_pos_r - hent_pos <= MAX_DIST) && s1_ok.
    // The two bounds are precomputed from s1_pos_r (a flop, ready before the
    // htab ERAM clk2q), so only two 13-bit compares sit behind the RAM output:
    //   hent_pos <= s1_lo   <=> hent_pos < s1_pos_r          (s1_lo = s1 - 1)
    //   hent_pos >= s1_hi   <=> s1_pos_r - hent_pos <= MAX_DIST
    //   s1_hi = (s1_pos_r > MAX_DIST) ? s1_pos_r - MAX_DIST : 0
    // Both hent sources are compared in parallel and the 1-bit results are
    // selected, so the ERAM clk2q cone is compare + one LUT (no data mux in
    // front of the compare).  s1_ok is registered separately (s1_ok_r) and
    // consumed by hit2.
    wire [12:0] s1_lo = s1_pos_r - 13'd1;
    wire [12:0] s1_hi = (s1_pos_r > MAX_DIST) ? (s1_pos_r - MAX_DIST) : 13'd0;
    wire        s1_nz = (s1_pos_r != 13'd0);
    wire [12:0] hent_pos_ram = htab_q[36:24];
    wire [12:0] hent_pos_byp = htab_byp_data[36:24];
    wire        rng1_ram = s1_nz && (hent_pos_ram <= s1_lo) && (hent_pos_ram >= s1_hi);
    wire        rng1_byp = s1_nz && (hent_pos_byp <= s1_lo) && (hent_pos_byp >= s1_hi);
    wire        rng1     = htab_byp ? rng1_byp : rng1_ram;
    wire [9:0]  s1_ins_addr = hash3(s1_b0, s1_b1, s1_b2);
    wire [65:0] s1_ins_data = {blk_tag, (s1_pos_r + 13'd3), s1_pos_r,
                               s1_b0, s1_b1, s1_b2};
    // Stage 2: hit decision from flops only (no ERAM clk2q in the cone).
    // T10.a1-pipe-split r0: the range test is split off at stage 1 (rng1_r for
    // the distance part, s1_ok_r for pos < lim2); stage 2 consumes
    // s1_vld_r/hb_r/rng1_r/s1_ok_r, four flops, so hit2 is one LUT away from
    // the clock edge.  hp_r/hdist2 stay for the hit-branch data
    // (cand_pos <= hp_r, dist_r <= hdist2).
    wire [12:0] hdist2 = pos - hp_r;
    wire        hit2   = s1_vld_r && hb_r && rng1_r && s1_ok_r;

    // Synchronous read port: the address is one position ahead of the stage-1
    // window so every scanned position still completes one lookup per cycle.
    // The same-address write-first bypass (stage-1 insert) preserves the
    // distance-1 match after a table insert. cmem uses a registered address
    // plus one replay wait state.
    wire htab_pref = (state == S_SCAN) || (state == S_PRE) || (state == S_REPOS);
    // r0 (bm-prefetch): the third hash byte is bm_a_rd2 (a flop), so the htab
    // read address no longer starts at the bm_a ERAM clk2q output.
    wire [9:0] htab_rd_addr = (state == S_SCAN)
                              ? hash3(w2, x1_r, bm_a_rd2)
                              : ((((state == S_PRE) && (pre_cnt == 13'd3)) ||
                                  ((state == S_REPOS) && (rp_cnt == 13'd3)))
                                 ? hash3(w1, x1_r, bm_a_rd2)
                                 : hash3(w0, x1_r, bm_a_rd2));
    // Stage-1 insert for the speculative position; dropped when stage 2
    // reports a hit (that position is then inside the match).
    wire htab_we = s1_en && s1_ok &&
                   ((state != S_SCAN) || !hit2);
    always @(posedge clk) begin
        htab_tag_q <= htab_tag[htab_rd_addr];
        htab_p3v_q <= htab_p3v[htab_rd_addr];
        htab_pos_q <= htab_pos[htab_rd_addr];
        htab_b_q   <= htab_b[htab_rd_addr];
        htab_b3_q  <= htab_b3[htab_rd_addr];
    end

    // Same-address write-first bypass, registered next to the RAM output: the
    // stage-1 consumer sees the new entry exactly one cycle after the read
    // address was issued, as before.
    always @(posedge clk) begin
        htab_byp <= htab_we && (htab_rd_addr == s1_ins_addr);
        if (htab_we && (htab_rd_addr == s1_ins_addr)) begin
            htab_byp_data <= s1_ins_data;
            htab_byp_b3   <= bm_a_rd2;
        end
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
    // b3 = the stream byte one past the 3-byte window (bm_a_rd2 is the byte
    // after x1_r in every htab_pref phase because the bm_a stream advances by
    // one byte per cycle there).  Written by the same insert enable/address as
    // htab_b; entries cleared by the valid sweep have htab_p3v[13] = 0, so a
    // stale b3 is never used.  Bank contents are stable while a block is
    // encoded, so this byte is exactly the bm[ref+3] that r4 read from bm_b.
    always @(posedge clk) begin
        if (htab_we) htab_b3[s1_ins_addr] <= bm_a_rd2;
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

    // cmem read port: registered address, one full cycle of read latency.  H
    // reads a 32-bit word (4 stream bytes) per replay access.
    always @(posedge clk) begin
        cmem_rdata <= cmem[cmem_raddr];
    end

    // cmem write port: the packer still produces 16-bit words in order.  Pair
    // them into 2048x32: an even address latches the low half, the following
    // odd address writes {high, low}.  If the block ends on an even word the
    // pending low half is flushed with a zero high half in S_DECIDE (the
    // replay starts at the next edge, so it always sees the finished word).
    // The flush has priority: S_DECIDE is only entered after the packer and
    // write FIFO are empty, so no legitimate 16-bit write can collide with it.
    wire cmem_flush = cmem_lo_pend && (state == S_DECIDE);
    always @(posedge clk) begin
        if (cmem_flush) begin
            cmem[cmem_lo_addr[11:1]] <= {16'd0, cmem_lo};
            cmem_lo_pend <= 1'b0;
        end else if (cmem_we_c) begin
            if (!cmem_waddr_c[0]) begin
                cmem_lo      <= cmem_wdata_c;
                cmem_lo_addr <= cmem_waddr_c;
                cmem_lo_pend <= 1'b1;
            end else begin
                cmem[cmem_waddr_c[11:1]] <= {cmem_wdata_c, cmem_lo};
                cmem_lo_pend <= 1'b0;
            end
        end
    end

    wire [8:0] litcode = lit_rev({1'b0, w0});
    wire [3:0] litlen  = lit_len({1'b0, w0});
    // Literal threshold: cand_bits + litlen >= thresh_lit is equivalent to
    // cand_bits >= thresh_lit - litlen.  Literals are bytes, so litlen is 8
    // (w0 < 144) or 9; thresh_lit8/thresh_lit9 are kept as registers updated
    // with thresh_lit, so the 32-bit subtract/carry chain runs from registers
    // and the w0 -> state.ce path is only the 2:1 select.  Range proof:
    // MAX_BLOCK = 4800 -> stored_cost <= 3+7+32+8*4800 = 38,442, thresh_lit
    // <= 38,450, and the literal abort guard keeps cand_bits below it.
    wire lit_ge = (litlen == 4'd9) ? (cand_bits >= thresh_lit9)
                                   : (cand_bits >= thresh_lit8);

    wire [8:0] lsym  = len_code(len_r);
    wire [8:0] lrev  = lit_rev(lsym);
    wire [3:0] llen  = lit_len(lsym);
    wire [3:0] leb   = len_extra_bits(len_r);
    wire [4:0] lev   = len_extra_val(len_r);
    wire [13:0] lval = {5'd0, lrev} | ({9'd0, lev} << llen);
    wire [4:0] ltot  = {1'b0, llen} + {1'b0, leb};

    wire [4:0]  dsym = dist_code(dist_r);
    wire [8:0]  drev = rev9({4'd0, dsym}, 4'd5);
    wire [3:0]  deb  = dist_extra_bits(dsym);
    wire [11:0] dbase = dist_base(dsym);
    wire [12:0] dev  = dist_r - dbase;
    wire [13:0] dval = {5'd0, drev} | ({9'd0, dev} << 5);
    wire [4:0]  dtot = 5'd5 + {1'b0, deb};

    wire out_space = (fifo_count < 5'd15);

    // Next extension remaining count for the hit that enters S_EXT (same
    // expression the FSM used to assign to ext_rem).
    wire [12:0] ext_rem_new = (p3_r + 13'd1 >= blk_n)
                              ? 13'd0 : (blk_n - (p3_r + 13'd1));

    // Adler fold/reduce (block end only, outside the per-byte path).
    // 2^16 mod 65521 = 15, 2^32 mod 65521 = 225.
    wire [16:0] adler_fold_a_c = {1'b0, adler_a_w[15:0]}
        + (({11'd0, adler_a_w[21:16]} << 4) - {11'd0, adler_a_w[21:16]});
    wire [20:0] adler_fold_b_c = {5'd0, adler_b_w[15:0]}
        + (({5'd0, adler_b_w[31:16]} << 4) - {5'd0, adler_b_w[31:16]})
        + ({13'd0, adler_b_w[34:32]} * 9'd225);
    wire [16:0] adler_fold2_b_c = {1'b0, adler_fold_b[15:0]}
        + (({12'd0, adler_fold_b[20:16]} << 4) - {12'd0, adler_fold_b[20:16]});
    wire [16:0] adler_red_a_c = (adler_fold_a >= 17'd65521)
        ? (adler_fold_a - 17'd65521) : adler_fold_a;
    wire [16:0] adler_red_b_c = (adler_fold_b[16:0] >= 17'd65521)
        ? (adler_fold_b[16:0] - 17'd65521) : adler_fold_b[16:0];

    // candidate push control
    reg        cp_en;
    reg        cp_rst;
    reg [15:0] cp_value;
    reg [4:0]  cp_nbits;

    // stream output bit push control (up to two bytes per cycle)
    reg        op_en;
    reg [7:0]  op_b0, op_b1;
    reg [3:0]  op_nb0, op_nb1;
    reg        op_last;

    wire [7:0]  opq_b0   = opq_mem[opq_rptr][7:0];
    wire [7:0]  opq_b1   = opq_mem[opq_rptr][15:8];
    wire [3:0]  opq_nb0  = opq_mem[opq_rptr][19:16];
    wire [3:0]  opq_nb1  = opq_mem[opq_rptr][23:20];
    wire        opq_last = opq_mem[opq_rptr][24];
    wire [15:0] op_mask0 = (16'd1 << opq_nb0) - 16'd1;
    wire [15:0] op_mask1 = (16'd1 << opq_nb1) - 16'd1;
    wire [23:0] op_word  = oacc
                         | (({8'd0, opq_b0} & op_mask0) << obits)
                         | (({8'd0, opq_b1} & op_mask1) << (obits + opq_nb0));
    wire [4:0]  op_tot   = {1'b0, obits} + {1'b0, opq_nb0} + {1'b0, opq_nb1};
    wire        op_emit2 = (op_tot >= 5'd16);
    wire        op_emit1 = (op_tot >= 5'd8) && !op_emit2;
    wire        opq_accept = op_en && (opq_count < 3'd4);
    wire        op_go = (opq_count != 3'd0) && out_space;

    wire        pop = (fifo_count != 5'd0) && out_ready;
    // In 8-bit mode a 2-byte entry is presented low byte first, then the high
    // byte is written back into the same entry (keep cleared) for the next
    // transfer.  In 16-bit mode the whole entry is one accepted transfer.
    wire        fifo_keep = fifo_mem[fifo_rptr][16];
    wire        pop_full  = pop && !(fifo_keep && (OUT_BYTES == 1));
    wire        talign_en = (state == S_TALIGN) && (fifo_count < 5'd16);

    wire sop_accept = in_valid && in_ready && in_sop;
    wire in_acc     = in_valid && in_ready;

    assign in_ready = rst_n && !abort && !adler_blk_q &&
                      (adler_red_st == 2'd0) &&
                      (stream_active
                         ? (!(enc_busy && (enc_bank == ld_bank)) &&
                            !(ld_bank ? blk_full1 : blk_full0) &&
                            (ld_ptr < MAX_BLOCK))
                         : in_sop);
    assign out_valid = (fifo_count != 5'd0);
    assign out_data  = fifo_mem[fifo_rptr][8*OUT_BYTES-1:0];
    assign out_keep  = (OUT_BYTES == 2) ? fifo_mem[fifo_rptr][16] : 1'b0;
    assign out_last  = (fifo_count != 5'd0) && fifo_mem[fifo_rptr][17];
    assign busy      = stream_active | enc_busy;

    // ------------------------------------------------------------- bm ports
    // Block loader write port: one enable/address/data per clock, no reset
    // (ERAM template, same structure frame_top uses for smem).  The loader bank
    // and the encoding bank are always different while enc_busy, so a read and
    // a write never target the same word during encoding.
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

    // Read port: one registered address and one registered data word per array.
    // r0 (hit-pipe): the extension byte pair is prefetched so the mismatch flag
    // can be registered without losing a cycle.  On the hit cycle the bm_a port
    // issues pos+4, and from the first S_EXT cycle on the bm_b port issues
    // ref+4; the first extension byte pair is the already-registered
    // cq_r = bm[pos+3] against the bm_b data returned by the speculative read
    // that was issued on the hit cycle.  During S_SCAN the bm_b port is
    // otherwise idle (the window comes from the w0..w2/x1_r shift chain), so it
    // speculatively reads the candidate entry's pos+3 byte.
    wire        bm_hit_a   = (state == S_SCAN) && hit2;
    // Forward byte of the registered extension compare: the hit cycle uses the
    // already-registered x1_r (bm[pos+3]), every S_EXT cycle the current bm_a
    // read data.
    wire [7:0]  ext_fw_byte = (state == S_EXT) ? bm_a_rd : x1_r;
    // Reference byte of the same compare: on the hit cycle it is the entry
    // field b3 (bm[ref+3], a flop registered with hf_r), in S_EXT the current
    // bm_b read data.  r0 (htab-nw): this replaces r4's speculative bm_b read
    // (address from the htab ERAM clk2q output) without adding a wait cycle.
    wire [7:0]  ext_rf_byte = (state == S_EXT) ? bm_b_rd : h4_r;
    wire [12:0] bm_raddr_a = (state == S_EXT) ? ext_raddr
                           : bm_hit_a ? (p3_r + 13'd1)
                           : ((state == S_SLEN) || (state == S_SDATA_R)) ? raddr
                           : praddr;
    // r0 (htab-nw): the bm_b port no longer carries a speculative candidate
    // read, so every source of its address is a fabric flop (hf1_r / ext_faddr
    // / raddr) and no htab ERAM clk2q output reaches a RAM address.  Priority
    // is unchanged: hit-cycle prefetch (ref+4) > S_EXT reference byte > window
    // read.  During S_SCAN the port reads the (unused) window address.
    wire [12:0] bm_raddr_b = bm_hit_a          ? hf1_r
                           : (state == S_EXT)  ? ext_faddr
                           :                     raddr;
    always @(posedge clk) begin
        bm_a_rd  <= bm_a[{enc_bank, bm_raddr_a}];
        bm_b_rd  <= bm_b[{enc_bank, bm_raddr_b}];
        bm_a_rd2 <= bm_a_rd;      // r0 (bm-prefetch): scan-path stage 2
    end

    // ----------------------------------------------------------- combinational
    always @* begin
        cp_en    = 1'b0;
        cp_rst   = 1'b0;
        cp_value = 16'd0;
        cp_nbits = 5'd0;
        case (state)
            S_BHDR: begin
                cp_en    = 1'b1;
                cp_rst   = 1'b1;
                cp_value = 16'd2 | {15'd0, blk_last};
                cp_nbits = 5'd3;              // BFINAL + BTYPE=01
            end
            S_SCAN: begin
                // Literal data path is independent of the hash datapath: the
                // stage-2 hit bit alone decides whether this literal is packed.
                cp_en    = !hit2 && (pos < blk_n);
                cp_value = {7'd0, litcode};
                cp_nbits = {1'b0, litlen};
            end
            S_MLEN: begin
                cp_en    = 1'b1;
                cp_value = {2'd0, lval};
                cp_nbits = ltot;              // length code + extra bits
            end
            S_MCHK: begin
                cp_en    = 1'b1;
                cp_value = {2'd0, dval_r};
                cp_nbits = dtot_r;            // registered distance code + extra bits
            end
            S_EOB: begin
                cp_en    = 1'b1;
                cp_value = 16'd0;
                cp_nbits = 5'd7;              // EOB symbol 256
            end
            default: ;
        endcase
    end

    always @* begin
        op_en    = 1'b0;
        op_b0    = 8'd0;
        op_b1    = 8'd0;
        op_nb0   = 4'd0;
        op_nb1   = 4'd0;
        op_last  = 1'b0;
        case (state)
            S_HDR: begin
                op_en    = 1'b1;
                op_b0    = hdr_idx[0] ? 8'h9C : 8'h78;
                op_nb0   = 4'd8;
            end
            S_SHDR: begin
                op_en    = 1'b1;
                op_b0    = {7'd0, blk_last};   // BFINAL + BTYPE=00
                op_nb0   = 4'd3;
            end
            S_SALIGN: begin
                op_en    = 1'b1;
                op_b0    = 8'h00;
                op_nb0   = 4'd8 - opq_bit_off;
            end
            S_SLEN: begin
                op_en    = 1'b1;
                op_nb0   = 4'd8;
                case (slen_idx)
                    4'd0: op_b0 = blk_n[7:0];
                    4'd1: op_b0 = {5'd0, blk_n[12:8]};
                    4'd2: op_b0 = ~blk_n[7:0];
                    4'd3: op_b0 = ~{5'd0, blk_n[12:8]};
                    default: op_b0 = 8'h00;
                endcase
            end
            S_SDATA_R: begin
                op_en    = 1'b1;
                op_b0    = sd_byte;
                op_nb0   = 4'd8;
            end
            S_REPLAY_E: begin
                // first 1-2 bytes of the 32-bit replay word
                op_en    = 1'b1;
                op_b0    = cmem_rdata[7:0];
                op_nb0   = (rbits_left >= 16'd8) ? 4'd8 : rbits_left[3:0];
                if (rbits_left > 16'd8) begin
                    op_b1  = cmem_rdata[15:8];
                    op_nb1 = (rbits_left >= 16'd16) ? 4'd8 : (rbits_left - 16'd8);
                end
            end
            S_REPLAY_E2: begin
                // next 1-2 bytes of the same 32-bit replay word
                op_en    = 1'b1;
                op_b0    = cmem_rdata[23:16];
                op_nb0   = (rbits_left >= 16'd24) ? 4'd8 : (rbits_left - 16'd16);
                if (rbits_left > 16'd24) begin
                    op_b1  = cmem_rdata[31:24];
                    op_nb1 = (rbits_left >= 16'd32) ? 4'd8 : (rbits_left - 16'd24);
                end
            end
            S_TADLER: begin
                op_en   = 1'b1;
                op_nb0  = 4'd8;
                op_last = (tadler_idx == 4'd3);
                case (tadler_idx)
                    4'd0: op_b0 = adler_b[15:8];
                    4'd1: op_b0 = adler_b[7:0];
                    4'd2: op_b0 = adler_a[15:8];
                    4'd3: op_b0 = adler_a[7:0];
                    default: op_b0 = 8'h00;
                endcase
            end
            default: ;
        endcase
    end

    // ------------------------------------------------------------- sequential
    integer i;
    reg [16:0] sum_a, sum_b, a_nxt, b_nxt;
    reg [31:0] ctot, cand_bits_n;
    reg [31:0] accw;
    reg [1:0]  nbw;

    always @(posedge clk) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            stream_active  <= 1'b0;
            enc_busy       <= 1'b0;
            ld_bank        <= 1'b0;
            ld_ptr         <= 13'd0;
            blk_len0       <= 13'd0;
            blk_len1       <= 13'd0;
            blk_final0     <= 1'b0;
            blk_final1     <= 1'b0;
            blk_full0      <= 1'b0;
            blk_full1      <= 1'b0;
            enc_bank       <= 1'b0;
            blk_n          <= 13'd0;
            lim2           <= 13'd0;
            blk_last       <= 1'b0;
            blk_tag        <= 16'd0;
            pos            <= 13'd0;
            p3_r           <= 13'd3;
            faddr          <= 13'd0;
            hp_r           <= 13'd0;
            hf_r           <= 13'd0;
            hf1_r          <= 13'd0;
            hb_r           <= 1'b0;
            rng1_r         <= 1'b0;
            s1_ok_r        <= 1'b0;
            s1_last_r      <= 1'b0;
            ext_mis_r      <= 1'b0;
            s1_vld_r       <= 1'b0;
            cand_pos       <= 13'd0;
            dval_r         <= 14'd0;
            dtot_r         <= 5'd0;
            pos_next_r     <= 13'd0;
            rem_next_r     <= 13'd0;
            dist_r         <= 13'd0;
            len_r          <= 9'd3;
            cq_r           <= 8'd0;
            ext_rem        <= 13'd0;
            ext_first      <= 1'b0;
            ext_zero_r     <= 1'b0;
            len_cap_r      <= 1'b0;
            pre_cnt        <= 13'd0;
            rp_cnt         <= 13'd0;
            cand_bits      <= 32'd0;
            stored_bits    <= 32'd0;
            cand_abort     <= 1'b0;
            cacc           <= 32'd0;
            pbit_off       <= 4'd0;
            cstage         <= 16'd0;
            clane          <= 1'b0;
            cwptr          <= 13'd0;
            cand_nbytes    <= 13'd0;
            p0_valid       <= 1'b0;
            p0_value       <= 16'd0;
            p0_nbits       <= 5'd0;
            p0_off         <= 4'd0;
            p0_rst         <= 1'b0;
            p1_valid       <= 1'b0;
            p1_pshift      <= 32'd0;
            p1_nbits       <= 5'd0;
            p1_off         <= 4'd0;
            p1_rst         <= 1'b0;
            p2_wdata       <= 16'd0;
            p2_we          <= 1'b0;
            wq_wptr        <= 2'd0;
            wq_rptr        <= 2'd0;
            wq_count       <= 3'd0;
            opq_wptr       <= 2'd0;
            opq_rptr       <= 2'd0;
            opq_count      <= 3'd0;
            opq_bit_off    <= 4'd0;
            opq_bit_off    <= 4'd0;
            opq_wptr       <= 2'd0;
            opq_rptr       <= 2'd0;
            opq_count      <= 3'd0;
            rb_word        <= 13'd0;
            rbits_left     <= 13'd0;
            cmem_lo        <= 16'd0;
            cmem_lo_pend   <= 1'b0;
            cmem_lo_addr   <= 12'd0;
            hdr_idx        <= 4'd0;
            slen_idx       <= 4'd0;
            sdata_ptr      <= 13'd0;
            sd_byte        <= 8'd0;
            sd_hold        <= 8'd0;
            sd_in_q        <= 1'b0;
            sd_acc_q       <= 1'b0;
            tadler_idx     <= 4'd0;
            oacc           <= 24'd0;
            obits          <= 4'd0;
            fifo_wptr      <= 4'd0;
            fifo_rptr      <= 4'd0;
            fifo_count     <= 5'd0;
            adler_a        <= 16'd1;
            adler_b        <= 16'd0;
            rem_blk        <= 13'd0;
            thresh_base    <= 32'd0;
            thresh_lit     <= 32'd0;
            thresh_lit8    <= 32'd0;
            thresh_lit9    <= 32'd0;
            cand_after_len <= 32'd0;
            thresh_match_r <= 32'd0;
            adler_data_r   <= 8'd0;
            adler_sop_r    <= 1'b0;
            adler_pend     <= 1'b0;
            adler_blk_q    <= 1'b0;
            adler_red_st   <= 2'd0;
            adler_a_w      <= 22'd1;
            adler_b_w      <= 35'd0;
            done           <= 1'b0;
            stat_blocks    <= 32'd0;
            stat_fixed     <= 32'd0;
            stat_stored    <= 32'd0;
            stat_literals  <= 32'd0;
            stat_matches   <= 32'd0;
            stat_cand_aborts <= 32'd0;
            stat_stall     <= 32'd0;
            stat_max_match <= 32'd0;
            stat_max_dist  <= 32'd0;
        end else if (abort) begin
            state          <= S_IDLE;
            stream_active  <= 1'b0;
            enc_busy       <= 1'b0;
            blk_full0      <= 1'b0;
            blk_full1      <= 1'b0;
            ld_bank        <= 1'b0;
            ld_ptr         <= 13'd0;
            fifo_wptr      <= 4'd0;
            fifo_rptr      <= 4'd0;
            fifo_count     <= 5'd0;
            oacc           <= 24'd0;
            obits          <= 4'd0;
            cacc           <= 32'd0;
            pbit_off       <= 4'd0;
            cstage         <= 16'd0;
            clane          <= 1'b0;
            cwptr          <= 13'd0;
            p0_valid       <= 1'b0;
            p0_value       <= 16'd0;
            p0_nbits       <= 5'd0;
            p0_off         <= 4'd0;
            p0_rst         <= 1'b0;
            p1_valid       <= 1'b0;
            p1_pshift      <= 32'd0;
            p1_nbits       <= 5'd0;
            p1_off         <= 4'd0;
            p1_rst         <= 1'b0;
            p2_wdata       <= 16'd0;
            p2_we          <= 1'b0;
            wq_wptr        <= 2'd0;
            wq_rptr        <= 2'd0;
            wq_count       <= 3'd0;
            done           <= 1'b0;
            cand_abort     <= 1'b0;
            cq_r           <= 8'd0;
            ext_rem        <= 13'd0;
            ext_first      <= 1'b0;
            s1_vld_r       <= 1'b0;
            hb_r           <= 1'b0;
            rng1_r         <= 1'b0;
            s1_ok_r        <= 1'b0;
            s1_last_r      <= 1'b0;
            ext_mis_r      <= 1'b0;
            rem_blk        <= 13'd0;
            thresh_base    <= 32'd0;
            thresh_lit     <= 32'd0;
            thresh_lit8    <= 32'd0;
            thresh_lit9    <= 32'd0;
            cand_after_len <= 32'd0;
            thresh_match_r <= 32'd0;
            adler_data_r   <= 8'd0;
            adler_sop_r    <= 1'b0;
            adler_pend     <= 1'b0;
            adler_blk_q    <= 1'b0;
            adler_red_st   <= 2'd0;
            adler_a_w      <= 22'd1;
            adler_b_w      <= 35'd0;
        end else begin
            done <= 1'b0;
            cand_bits_n = cand_bits + {27'd0, cp_nbits};

            // stored-path stall tracking (see sd_hold declaration)
            sd_in_q  <= (state == S_SDATA_R);
            sd_acc_q <= (state == S_SDATA_R) && opq_accept;
            if ((state == S_SDATA_R) && !opq_accept && !(sd_in_q && !sd_acc_q))
                sd_hold <= bm_a_rd;

            // -------------------------------------------------- input loader
            if (in_acc) begin
                if (in_sop) begin
                    adler_a <= 16'd1;
                    adler_b <= 16'd0;
                end

                if (sop_accept) begin
                    stream_active <= 1'b1;
                    state         <= S_HDR;
                    hdr_idx       <= 4'd0;
                    blk_full0     <= 1'b0;
                    blk_full1     <= 1'b0;
                    enc_busy      <= 1'b0;
                    ld_bank       <= 1'b0;
                    ld_ptr        <= 13'd0;
                    if (in_blk_end) begin
                        blk_len0   <= 13'd1;
                        blk_final0 <= in_stream_end;
                        blk_full0  <= 1'b1;
                        ld_bank    <= 1'b1;
                        ld_ptr     <= 13'd0;
                    end else begin
                        ld_ptr <= 13'd1;
                    end
                end else begin
                    if (in_blk_end) begin
                        if (ld_bank == 1'b0) begin
                            blk_len0   <= ld_ptr + 13'd1;
                            blk_final0 <= in_stream_end;
                            blk_full0  <= 1'b1;
                        end else begin
                            blk_len1   <= ld_ptr + 13'd1;
                            blk_final1 <= in_stream_end;
                            blk_full1  <= 1'b1;
                        end
                        ld_bank <= ~ld_bank;
                        ld_ptr  <= 13'd0;
                    end else begin
                        ld_ptr <= ld_ptr + 13'd1;
                    end
                end

                // Adler-32: register the accepted byte, then fold it into the
                // wide block-local accumulators in the next cycle.  Modulo is
                // applied at block end (adler_red_st), not per byte.
                adler_data_r <= in_data;
                adler_sop_r  <= in_sop;
                if (in_sop) begin
                    adler_blk_q  <= 1'b0;
                    adler_red_st <= 2'd0;
                end
                if (in_blk_end) adler_blk_q <= 1'b1;
            end

            // Adler fold of the previously accepted byte.
            if (adler_pend) begin
                if (adler_sop_r) begin
                    adler_a_w <= 22'd1 + {14'd0, adler_data_r};
                    adler_b_w <= 35'd0 + 22'd1 + {14'd0, adler_data_r};
                end else begin
                    adler_a_w <= adler_a_w + {14'd0, adler_data_r};
                    adler_b_w <= adler_b_w + adler_a_w + {14'd0, adler_data_r};
                end
            end
            adler_pend <= in_acc;

            // Three-stage registered prefetch of the scan window.  In S_SCAN
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

            // ---- two-cycle hit/threshold path: stage 1 + table insert ------
            // Stage 1 registers the ERAM read data (entry position, pos+3
            // field and the tag/byte compare) plus the distance/range test
            // (rng1_r, T10.a1-pipe-split r0), so the hit decision and the
            // state enable are driven by flops only: htab/bm ERAM clk2q never
            // reaches them.
            s1_vld_r <= s1_en;
            if (s1_en) begin
                hp_r  <= hent_pos;
                hf_r  <= hent[49:37];
                // r0 (bm-addr): precompute ref+4 for the hit-cycle bm_b read
                // so the hit-cycle port address is a flop instead of a
                // pos/hit2 -> adder -> address chain.
                hf1_r <= hent[49:37] + 13'd1;
                h4_r  <= htab_byp ? htab_byp_b3 : htab_b3_q;
                hb_r  <= s1_bytes;
                // T10.a1-pipe-split r0: register the stage-1 range test with
                // hb_r; consumed one cycle later by hit2 (s1_vld_r-gated).
                rng1_r   <= rng1;
                s1_ok_r  <= s1_ok;
                // step 4 (bounded, one predicate): the S_SCAN literal CE test
                // pos + 1 >= blk_n is the stage-1 predicate s1_pos_r + 1 >=
                // blk_n (pos == s1_pos_r of the previous stage-1 cycle), so the
                // 13-bit increment+compare leaves the pos/thresh_base CE cone.
                s1_last_r <= (s1_pos_r + 13'd1 >= blk_n);
            end
            // Registered extension-byte mismatch: cycle k holds the compare for
            // extension byte k.  On the hit cycle the forward byte is the
            // prefetched x1_r (bm[pos+3]); on every S_EXT cycle both ports are
            // one byte ahead, i.e. they hold the pair for the following cycle.
            // Two independent compares (no hit2-dependent mux in the data path)
            // keep the late pos-derived hit2 out of this flop's D cone; it only
            // reaches the clock enable.
            // r0 (bm-prefetch): unconditional load, no clock enable.  The
            // source bytes are the same as before (x1_r on the hit cycle,
            // bm_a read data in S_EXT), so the flag timing is unchanged.
            ext_mis_r <= (ext_fw_byte != ext_rf_byte);

            // Adler block-end reduction: 3 cycles, input held by in_ready.
            case (adler_red_st)
                2'd0: begin
                    if (adler_blk_q && !adler_pend) begin
                        adler_blk_q  <= 1'b0;
                        adler_red_st <= 2'd1;
                    end
                end
                2'd1: begin
                    adler_fold_a <= adler_fold_a_c;
                    adler_fold_b <= adler_fold_b_c;
                    adler_red_st <= 2'd2;
                end
                2'd2: begin
                    adler_red_a  <= adler_red_a_c;
                    adler_fold_b <= adler_fold2_b_c;
                    adler_red_st <= 2'd3;
                end
                default: begin
                    adler_a   <= adler_red_a[15:0];
                    adler_b   <= adler_red_b_c[15:0];
                    adler_a_w <= {6'd0, adler_red_a[15:0]};
                    adler_b_w <= {19'd0, adler_red_b_c[15:0]};
                    adler_red_st <= 2'd0;
                end
            endcase

            // ------------------------------------------- candidate bit packer
            // Stage 0: register the generated code and the pre-symbol bit
            // offset, so len_r/lval is no longer in the shift/accumulate path.
            p0_valid <= cp_en;
            if (cp_en) begin
`ifdef A1_DEBUG
                $display("CP0 st=%0d nbits=%0d val=%04x off=%0d cand_bits=%0d",
                         state, cp_nbits, cp_value, pbit_off, cand_bits);
`endif
                p0_value <= cp_value;
                p0_nbits <= cp_nbits;
                p0_off   <= cp_rst ? 4'd0 : pbit_off;
                p0_rst   <= cp_rst;
                pbit_off <= cp_rst ? cp_nbits[2:0]
                                   : ((pbit_off + cp_nbits[2:0]) & 4'h7);
                cand_bits <= (cp_rst ? 32'd0 : cand_bits)
                             + {27'd0, cp_nbits};
            end

            // Stage 1: variable shift, registered.
            p1_valid <= p0_valid;
            if (p0_valid) begin
                p1_pshift <= ({16'd0, p0_value}
                              & ((32'd1 << p0_nbits) - 32'd1))
                             << p0_off;
                p1_nbits <= p0_nbits;
                p1_off   <= p0_off;
                p1_rst   <= p0_rst;
            end

            // Stage 2: combine with pending bits, enqueue 16-bit words.
            p2_we = 1'b0;
            p2_wdata = 16'd0;
            if (p1_valid) begin
                accw = (p1_rst ? 32'd0 : cacc) | p1_pshift;
                ctot = (p1_rst ? 32'd0 : {28'd0, p1_off})
                       + {27'd0, p1_nbits};
                nbw  = ctot[4:3];
                if (p1_rst) begin
                    cstage <= 16'd0;
                    clane  <= 1'b0;
                    cwptr  <= 13'd0;
                end
                case (nbw)
                    2'd0: ;
                    2'd1: begin
                        if (!clane) begin
                            cstage   <= accw[15:0];
                            clane    <= 1'b1;
                        end else begin
                            p2_wdata = {accw[7:0], cstage[7:0]};
                            clane    <= 1'b0;
                        end
                    end
                    2'd2: begin
                        if (!clane) begin
                            p2_wdata = accw[15:0];
                            clane    <= 1'b0;
                        end else begin
                            p2_wdata = {accw[7:0], cstage[7:0]};
                            cstage   <= {8'd0, accw[15:8]};
                            clane    <= 1'b1;
                        end
                    end
                    default: ;
                endcase
                if ((nbw == 2'd2) || ((nbw == 2'd1) && clane))
                    p2_we = 1'b1;
                cacc <= accw >> {nbw, 3'b000};
            end

            // 4-entry write FIFO: registered data/address.  The drain itself is
            // applied by the single cmem write port (cmem_we_c); only the read
            // pointer moves here.
            if (wq_count != 3'd0) begin
                wq_rptr <= wq_rptr + 2'd1;
            end
            if (p2_we) begin
                wq_mem[wq_wptr] <= {p1_rst ? 13'd0 : cwptr, p2_wdata};
                wq_wptr <= wq_wptr + 2'd1;
                cwptr   <= (p1_rst ? 13'd0 : cwptr) + 13'd1;
            end
            wq_count <= wq_count + (p2_we ? 3'd1 : 3'd0)
                                 - ((wq_count != 3'd0) ? 3'd1 : 3'd0);

            // ------------------------------------------- stream bit push/fifo
            // Enqueue the FSM's next output bytes into the 4-entry skid FIFO.
            if (opq_accept) begin
                opq_mem[opq_wptr] <= {op_last, op_nb1, op_nb0, op_b1, op_b0};
                opq_wptr <= opq_wptr + 2'd1;
                opq_bit_off <= (opq_bit_off + {1'b0, op_nb0} + {1'b0, op_nb1}) & 4'h7;
            end
            // Drain the skid FIFO through the bit packer into fifo_mem.  Up to
            // two whole stream bytes per cycle (H); a partial byte stays in
            // oacc/obits for the next push, exactly as before.
            if (op_go) begin
                if (op_emit2) begin
                    fifo_mem[fifo_wptr] <= {opq_last, 1'b1, op_word[15:8], op_word[7:0]};
                    fifo_wptr <= fifo_wptr + 4'd1;
                    oacc      <= op_word >> 16;
                    obits     <= op_tot[2:0];
                end else if (op_emit1) begin
                    fifo_mem[fifo_wptr] <= {opq_last, 1'b0, 8'd0, op_word[7:0]};
                    fifo_wptr <= fifo_wptr + 4'd1;
                    oacc      <= op_word >> 8;
                    obits     <= op_tot[2:0];
                end else begin
                    oacc  <= op_word;
                    obits <= op_tot[2:0];
                end
                opq_rptr <= opq_rptr + 2'd1;
            end
            opq_count <= opq_count + (opq_accept ? 3'd1 : 3'd0)
                                   - (op_go ? 3'd1 : 3'd0);
            if (pop_full) begin
                fifo_rptr <= fifo_rptr + 4'd1;
                if (fifo_mem[fifo_rptr][17]) done <= 1'b1;
            end else if (pop) begin
                // 8-bit mode: present the high byte of a 2-byte entry next
                fifo_mem[fifo_rptr] <= {fifo_mem[fifo_rptr][17], 1'b0,
                                        8'd0, fifo_mem[fifo_rptr][15:8]};
            end
            fifo_count <= fifo_count + ((op_go && (op_emit1 || op_emit2)) ? 5'd1 : 5'd0)
                                      + (talign_en ? 5'd1 : 5'd0)
                                      - (pop_full ? 5'd1 : 5'd0);

            // --------------------------------------------------- main FSM
            case (state)
                S_IDLE: begin
                    if (sop_accept) begin
                        state     <= S_HDR;
                        hdr_idx   <= 4'd0;
                    end
                end

                S_HDR: begin
                    if (opq_accept) begin
                        if (hdr_idx == 4'd0) hdr_idx <= 4'd1;
                        else begin
                            hdr_idx <= 4'd0;
                            state   <= S_WAIT;
                        end
                    end
                end

                S_WAIT: begin
                    if (blk_avail && htab_clr_done) begin
                        // r1 (bm-prefetch): prime the bm_a prefetch one cycle
                        // before S_BHDR.  The extra read-data stage makes the
                        // S_PRE lookup address use x1_r, whose value at
                        // pre_cnt=2 comes from the address issued during
                        // S_BHDR; without this seed that address is the stale
                        // previous-block praddr (out-of-block read).
                        praddr      <= 13'd1;
                        enc_bank    <= sel_is_b0 ? 1'b0 : 1'b1;
                        blk_n       <= sel_len;
                        lim2        <= (sel_len > 13'd2) ? (sel_len - 13'd2) : 13'd0;
                        lim1        <= (sel_len > 13'd1) ? (sel_len - 13'd1) : 13'd0;
                        lim3        <= (sel_len > 13'd3) ? (sel_len - 13'd3) : 13'd0;
                        last_a      <= (sel_len > 13'd0) ? (sel_len - 13'd1) : 13'd0;
                        blk_last    <= sel_final;
                        blk_tag     <= blk_tag + 16'd1;
                        stored_bits <= stored_cost(obits, sel_len);
                        rem_blk     <= sel_len;
                        thresh_base <= stored_cost(obits, sel_len)
                                       - ({19'd0, sel_len} << 3);
                        thresh_lit  <= stored_cost(obits, sel_len)
                                       - ({19'd0, sel_len} << 3) + 32'd8;
                        thresh_lit8 <= stored_cost(obits, sel_len)
                                       - ({19'd0, sel_len} << 3);
                        thresh_lit9 <= stored_cost(obits, sel_len)
                                       - ({19'd0, sel_len} << 3) - 32'd1;
                        cand_abort  <= 1'b0;
                        pos         <= 13'd0;
                        p3_r        <= 13'd3;
                        pre_cnt     <= 13'd0;
                        enc_busy    <= 1'b1;
                        stat_blocks <= stat_blocks + 32'd1;
                        if (sel_is_b0) blk_full0 <= 1'b0;
                        else           blk_full1 <= 1'b0;
                        state       <= S_BHDR;
                    end
                end

                S_BHDR: begin
                    praddr <= 13'd2;      // seed bm_a_rd2 = bm[1] for the S_PRE window
                    raddr  <= 13'd0;      // seed the bm_b window read at bm[0]
                    state  <= S_PRE;
                end

                S_PRE: begin
                    case (pre_cnt)
                        13'd0: begin
                            praddr  <= 13'd3;
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

                S_SCAN: begin
                    // r0 (bm-addr): shift the window unconditionally.  The hit
                    // and end-of-block paths leave S_SCAN and S_REPOS/S_PRE
                    // reload w0..w2 from bm_b_rd before they are read again, so
                    // this is functionally identical and keeps hit2 (the pos
                    // cone) out of the w0/w1/w2 clock enables.
                    w0 <= w1;
                    w1 <= w2;
                    w2 <= x1_r;
`ifdef A1_DEBUG
                    $display("SCAN pos=%0d blk_n=%0d w=%02x%02x%02x hit2=%b hent_pos=%0d hdist=%0d",
                             pos, blk_n, w0, w1, w2, hit2, hp_r, hdist2);
`endif
                    if (pos >= blk_n) begin
                        state <= S_EOB;
                    end else if (hit2) begin
                        // stage-2 hit: match starts at pos with the registered
                        // distance / candidate / reference-pos fields.
                        cand_pos <= hp_r;
                        dist_r   <= hdist2;
                        len_r    <= 9'd3;
                        if (p3_r >= blk_n) begin
                            state <= S_MLEN;
                        end else begin
                            raddr     <= p3_r;
                            faddr     <= hf_r;
                            // r0 (htab-nw): bm[pos+3] is already registered
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
                            ext_rem   <= ext_rem_new;
                            ext_zero_r<= (ext_rem_new == 13'd0);
                            len_cap_r <= 1'b0;
                            state     <= S_EXT;
                        end
                    end else begin
                        // literal w0
                        stat_literals <= stat_literals + 32'd1;
                        if (lit_ge) begin
                            cand_abort      <= 1'b1;
                            stat_cand_aborts<= stat_cand_aborts + 32'd1;
                            state           <= S_DECIDE;
                        end else if (s1_last_r) begin
                            state <= S_EOB;
                        end else begin
                            pos         <= pos + 13'd1;
                            rem_blk     <= rem_blk - 13'd1;
                            thresh_base <= thresh_base + 32'd8;
                            thresh_lit  <= thresh_lit + 32'd8;
                            thresh_lit8 <= thresh_lit;
                            thresh_lit9 <= thresh_lit - 32'd1;
                            raddr <= raddr + 13'd1;
                            p3_r  <= p3_r + 13'd1;
                            s1_pos_r <= s1_pos_r + 13'd1;
                        end
                    end
                end

                S_EXT: begin
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

                S_MLEN: begin
                    // r2 (bm-prefetch): the 2-stage bm_a prefetch needs one more
                    // cycle of history before the S_REPOS re-prime.  Issue the
                    // pos+1 address now so that the address presented in the
                    // S_MCHK cycle is pos_next+1, exactly the value the 1-stage
                    // base obtained from its S_MCHK seed.
                    praddr         <= pos + {4'd0, len_r} + 13'd1;
                    dval_r         <= dval;
                    dtot_r         <= dtot;
                    pos_next_r     <= pos + {4'd0, len_r};
                    rem_next_r     <= rem_blk - {4'd0, len_r};
                    thresh_match_r <= thresh_base
                                      + ({19'd0, len_r} << 3);
                    state          <= S_MCHK;
                end

                S_MCHK: begin
`ifdef A1_DEBUG
                    $display("MDIST pos=%0d cand=%0d dist=%0d len=%0d dsym=%0d dbase=%0d dev=%0d dval=%04x dtot=%0d",
                             pos, cand_pos, dist_r, len_r, dsym, dbase, dev, dval, dtot);
`endif
                    stat_matches <= stat_matches + 32'd1;
                    if ({19'd0, len_r} > stat_max_match)
                        stat_max_match <= {19'd0, len_r};
                    if ({19'd0, dist_r} > stat_max_dist)
                        stat_max_dist <= {19'd0, dist_r};
                    if ((cand_bits + {27'd0, dtot_r}) >= thresh_match_r) begin
                        cand_abort       <= 1'b1;
                        stat_cand_aborts <= stat_cand_aborts + 32'd1;
                        state            <= S_DECIDE;
                    end else begin
                        pos         <= pos_next_r;
                        rem_blk     <= rem_next_r;
                        thresh_base <= thresh_match_r;
                        thresh_lit  <= thresh_match_r + 32'd8;
                        thresh_lit8 <= thresh_match_r;
                        thresh_lit9 <= thresh_match_r - 32'd1;
                        if (pos_next_r >= blk_n) begin
                            state <= S_EOB;
                        end else begin
                            rp_cnt <= 13'd0;
                            praddr <= pos_next_r + 13'd2;  // seed bm_a_rd2 = bm[pos+1]
                            raddr  <= pos_next_r;          // seed the bm_b window read
                            state  <= S_REPOS;
                        end
                    end
                end

                S_REPOS: begin
                    case (rp_cnt)
                        13'd0: begin
                            raddr  <= (pos < lim1) ? (pos + 13'd1) : last_a;
                            p3_r   <= pos + 13'd3;
                            praddr <= pos + 13'd3;
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
                    endcase
                end

                S_EOB: begin
                    state <= S_EODONE;
                end

                S_EODONE: begin
                    if (p0_valid || p1_valid || (wq_count != 3'd0)) begin
                        // drain the packer pipeline and write FIFO
                    end else if (clane) begin
                        cwptr       <= cwptr + 13'd1;
                        clane       <= 1'b0;
                        if (pbit_off != 4'd0) begin
                            state <= S_EODONE2;
                        end else begin
                            state <= S_DECIDE;
                        end
                    end else if (pbit_off != 4'd0) begin
                        cwptr       <= cwptr + 13'd1;
                        state       <= S_DECIDE;
                    end else begin
                        state <= S_DECIDE;
                    end
                end

                S_EODONE2: begin
                    cwptr       <= cwptr + 13'd1;
                    state       <= S_DECIDE;
                end

                S_DECIDE: begin
                    if (cand_abort || (cand_bits >= stored_bits) ||
                        (cwptr > 13'd2700)) begin
                        stat_stored <= stat_stored + 32'd1;
                        slen_idx    <= 4'd0;
                        state       <= S_SHDR;
                    end else begin
                        stat_fixed  <= stat_fixed + 32'd1;
                        rb_word     <= 13'd0;
                        rbits_left  <= cand_bits[15:0];
                        state       <= S_REPLAY_R;
                    end
                end

                S_REPLAY_R: begin
                    if (out_space) begin
                        cmem_raddr <= rb_word[11:1];
                        state      <= S_REPLAY_RD;
                    end
                end

                S_REPLAY_RD: begin
                    // synchronous cmem read latency: data is valid in S_REPLAY_E
                    state <= S_REPLAY_E;
                end

                S_REPLAY_E: begin
                    // First 1-2 stream bytes of the 32-bit word.
                    if (opq_accept) begin
                        if (rbits_left <= 16'd16) begin
                            rbits_left <= 16'd0;
                            if (blk_last) begin
                                state <= S_TRAIL;
                            end else begin
                                enc_busy <= 1'b0;
                                state    <= S_WAIT;
                            end
                        end else begin
                            state <= S_REPLAY_E2;
                        end
                    end
                end

                S_REPLAY_E2: begin
                    // Remaining 1-2 stream bytes of the same 32-bit word.
                    if (opq_accept) begin
                        if (rbits_left <= 16'd32) begin
                            rbits_left <= 16'd0;
                            if (blk_last) begin
                                state <= S_TRAIL;
                            end else begin
                                enc_busy <= 1'b0;
                                state    <= S_WAIT;
                            end
                        end else begin
                            rbits_left <= rbits_left - 16'd32;
                            rb_word    <= rb_word + 13'd2;
                            state      <= S_REPLAY_R;
                        end
                    end
                end

                S_SHDR: begin
                    if (opq_accept) begin
                        if (((opq_bit_off + 4'd3) & 4'h7) != 4'd0) begin
                            state <= S_SALIGN;
                        end else begin
                            slen_idx <= 4'd0;
                            state    <= S_SLEN;
                        end
                        // oacc/obits updated by the shared bit push above
                    end
                end

                S_SALIGN: begin
                    if (opq_accept) begin
                        slen_idx <= 4'd0;
                        state    <= S_SLEN;
                    end
                end

                S_SLEN: begin
                    if (opq_accept) begin
                        if (slen_idx == 4'd3) begin
                            sdata_ptr <= 13'd0;
                            sd_byte   <= bm_a_rd;   // bm[0], fetched during idx 2
                            raddr     <= 13'd2;     // fetch stream stays two ahead
                            state     <= S_SDATA_R;
                        end else begin
                            // prime the synchronous read: bm[0] issued at idx 1,
                            // bm[1] at idx 2, so bm_a_rd is ready one byte ahead
                            if (slen_idx == 4'd1) raddr <= 13'd0;
                            if (slen_idx == 4'd2) raddr <= 13'd1;
                            slen_idx <= slen_idx + 4'd1;
                        end
                    end
                end

                S_SDATA_R: begin
                    if (opq_accept) begin
                        if (sdata_ptr + 13'd1 >= blk_n) begin
                            if (blk_last) begin
                                state <= S_TRAIL;
                            end else begin
                                enc_busy <= 1'b0;
                                state    <= S_WAIT;
                            end
                        end else begin
                            sdata_ptr <= sdata_ptr + 13'd1;
                            sd_byte   <= (sd_in_q && !sd_acc_q) ? sd_hold : bm_a_rd;
                            raddr     <= raddr + 13'd1;
                        end
                    end
                end

                S_SDATA_D: begin
                    state <= S_SDATA_R;
                end

                S_TRAIL: begin
                    if (opq_count != 3'd0) begin
                        // wait for the output skid FIFO to drain
                    end else if (obits != 4'd0) begin
                        state <= S_TALIGN;
                    end else begin
                        tadler_idx <= 4'd0;
                        state      <= S_TADLER;
                    end
                end

                S_TALIGN: begin
                    if (talign_en) begin
                        fifo_mem[fifo_wptr] <= {2'b00, 8'd0, oacc[7:0]};
                        fifo_wptr <= fifo_wptr + 4'd1;
                        oacc      <= 24'd0;
                        obits     <= 4'd0;
                        tadler_idx<= 4'd0;
                        state     <= S_TADLER;
                    end
                end

                S_TADLER: begin
                    if (opq_accept) begin
                        if (tadler_idx == 4'd3) state <= S_DRAIN;
                        else                    tadler_idx <= tadler_idx + 4'd1;
                    end
                end

                S_DRAIN: begin
                    if (fifo_count == 5'd0) begin
                        stream_active <= 1'b0;
                        state         <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase

            // ------------------------------------------------------- reads
            // (synchronous bm_a/bm_b read ports and bm_raddr_* muxes above)

            // --------------------------------------------------- observations
            if (in_valid && !in_ready && stream_active)
                stat_stall <= stat_stall + 32'd1;
            if (ld_ptr >= MAX_BLOCK)
                stat_stall <= stat_stall + 32'd1;
        end
    end



    // ------------------------------------------------------------------
    // cmem single write port (ERAM inference).
    // The three original write sources -- the write-FIFO drain, the tail byte
    // taken from cstage and the tail byte taken from cacc -- are merged into
    // one enable/address/data here.  The tail writes can only fire after the
    // packer pipeline and the FIFO are empty (S_EODONE waits on
    // p0_valid/p1_valid/wq_count), so they never collide with the drain; the
    // tail still has priority so the original last-assignment order is kept.
    // cwptr never exceeds 2700 before S_DECIDE aborts the candidate, so the
    // low 12 bits of the address are exactly the 4096-word array range.
    // ------------------------------------------------------------------
    always @* begin
        cmem_we_c    = 1'b0;
        cmem_waddr_c = 12'd0;
        cmem_wdata_c = 16'd0;
        if (wq_count != 3'd0) begin
            cmem_we_c    = 1'b1;
            cmem_waddr_c = wq_mem[wq_rptr][27:16];
            cmem_wdata_c = wq_mem[wq_rptr][15:0];
        end
        if (state == S_EODONE) begin
            if (!(p0_valid || p1_valid || (wq_count != 3'd0))) begin
                if (clane) begin
                    cmem_we_c    = 1'b1;
                    cmem_waddr_c = cwptr[11:0];
                    cmem_wdata_c = {8'd0, cstage[7:0]};
                end else if (pbit_off != 4'd0) begin
                    cmem_we_c    = 1'b1;
                    cmem_waddr_c = cwptr[11:0];
                    cmem_wdata_c = {8'd0, cacc[7:0]};
                end
            end
        end else if (state == S_EODONE2) begin
            cmem_we_c    = 1'b1;
            cmem_waddr_c = cwptr[11:0];
            cmem_wdata_c = {8'd0, cacc[7:0]};
        end
    end

endmodule
