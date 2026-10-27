`timescale 1ns/1ps
// =============================================================================
// a1_ddr_slot_store.v -- 2-slot variable-length frame store on a native
// 256-bit DDR port (P1 model port; P2 maps it to PH1P PAXI).
//
// Ownership contract (frozen in T10.b1 P1):
//  - a slot is FREE -> WRITING (wr_begin accepted) -> READY (wr_last) ->
//    READING (rd_open accepted) -> FREE (rd_close).
//  - wr_begin is only accepted when a FREE slot exists; a published (READY) or
//    being-exported (READING) frame is never overwritten.
//  - wr_abort frees a WRITING slot immediately; nothing is published.
//  - readout is sequential 256-bit streaming; the consumer must respect
//    rd_valid/rd_take and then assert rd_close.
//  - the exported length is the exact byte count of the accepted write data.
//
// MODE 0 (RAW path)   : 40-bit packed groups, 4 groups per 256-bit word
//                       (bits [159:0] used, upper 96 bits zero).
// MODE 1 (stream path): 32-bit stream words + keep, 8 words per 256-bit word.
// =============================================================================
module a1_ddr_slot_store #(
    parameter integer MODE       = 1,
    parameter integer SLOT_WORDS = 81085,
    parameter [31:0]  BASE_WORD  = 32'd0,
    parameter integer AWB        = 18,
    parameter integer EXPECT_BYTES = 0
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ddr_ready,

    input  wire        wr_begin,
    output wire        wr_begin_ready,
    input  wire [31:0] wr_id,
    input  wire [39:0] wr_data,
    input  wire [3:0]  wr_keep,
    input  wire        wr_valid,
    input  wire        wr_last,
    output wire        wr_ready,
    input  wire        wr_abort,

    input  wire        rd_open,
    output wire        rd_open_ready,
    output wire [31:0] rd_id,
    output wire [31:0] rd_len_bytes,
    input  wire        rd_close,
    output reg  [255:0] rd_data,
    output reg         rd_valid,
    input  wire        rd_take,

    output wire [31:0] ddr_awaddr,
    output wire        ddr_awvalid,
    input  wire        ddr_awready,
    output wire [255:0] ddr_wdata,
    output wire        ddr_wvalid,
    input  wire        ddr_wready,
    output wire [31:0] ddr_araddr,
    output wire        ddr_arvalid,
    input  wire        ddr_arready,
    input  wire [255:0] ddr_rdata,
    input  wire        ddr_rvalid,
    output wire        ddr_rready,

    output reg  [31:0] st_published,
    output reg  [31:0] st_dropped,
    output reg  [31:0] st_errors,
    output reg  [31:0] st_last_bytes,
    // P1 read-path observation: words delivered and adjacent identical read words
    output reg  [31:0] st_read_words,
    output reg  [31:0] st_dup_words,
    // ------------------------------------------------------------------
    // T10.b9-rawstore r0: WRITE/READ state observation for status packet v3.
    // Pure observation: none of these nets feeds back into the ownership or
    // data path.  Instances that do not need them leave the ports open and
    // synthesis removes the logic.
    // ------------------------------------------------------------------
    output reg  [31:0] st_wr_beats,     // accepted wr_valid beats (5 B each, MODE 0)
    output reg  [31:0] st_wr_words,     // flushed 256-bit words (AW/W handshakes)
    output wire [31:0] st_wr_ptr,       // current waddr (word offset inside the slot)
    output wire [31:0] st_wr_state,     // [31]wr_active [30]wr_slot [29:27]wcnt [26:0]nbytes
    output wire [31:0] st_rd_state,     // [1:0]rd_state [2]rd_armed [3]rd_sel [4]rd_valid
    output wire [31:0] st_slot_st,      // [1:0]slot0 [3:2]slot1 [4]seq0 [5]seq1
    output wire [31:0] st_slot_len0,    // slot_len[0] (bytes, level)
    output wire [31:0] st_slot_len1,    // slot_len[1] (bytes, level)
    output wire [31:0] st_rd_idx,       // read FSM word index
    output wire [31:0] st_rd_words,     // words this read is expected to deliver
    output reg  [31:0] st_ar_valid,     // cycles with ddr_arvalid = 1
    output reg  [31:0] st_ar_hs,        // AR handshakes (ddr_arvalid & ddr_arready)
    output reg  [31:0] st_rv_cnt,       // cycles with ddr_rvalid = 1
    output reg  [31:0] st_rd_open_ok,   // accepted rd_open
    output reg  [31:0] st_rd_close_cnt, // rd_close pulses that released a slot
    output reg  [31:0] st_abort_cnt,    // wr_abort that freed a WRITING slot
    output wire        st_free_valid,   // at least one FREE slot
    output wire        st_wr_active_out // mirror of the internal wr_active
);
    localparam [1:0] S_FREE = 2'd0, S_WRITE = 2'd1, S_READY = 2'd2, S_READING = 2'd3;
    localparam [1:0] R_IDLE = 2'd0, R_AR = 2'd1, R_RW = 2'd2, R_HOLD = 2'd3;

    reg [1:0]  slot_st [0:1];
    reg [31:0] slot_id [0:1];
    reg [31:0] slot_len[0:1];
    reg        slot_seq[0:1];
    reg        pub_tgl, rd_expect;

    reg        wr_active;
    reg [1:0]  wr_slot;
    reg [2:0]  wcnt;
    reg [255:0] pack_r;
    reg [31:0] nbytes;
    reg [AWB-1:0] waddr;

    reg [1:0]  rd_state;
    reg [1:0]  rd_sel;
    reg [31:0] rd_words;
    reg [31:0] rd_idx;
    reg [255:0] rd_prev;
    reg         rd_prev_v;
    reg         rd_armed;

    wire free_valid  = (slot_st[0] == S_FREE) || (slot_st[1] == S_FREE);
    wire [1:0] free_slot = (slot_st[0] == S_FREE) ? 2'd0 : 2'd1;
    wire ready_valid = (slot_st[0] == S_READY) || (slot_st[1] == S_READY);
    wire [1:0] ready_slot = (slot_st[0] == S_READY) ? 2'd0 : 2'd1;
    // oldest published slot (commit order), so descriptors pair with slots
    wire [1:0] oldest_slot =
        ((slot_st[0] == S_READY) && (slot_seq[0] == rd_expect)) ? 2'd0 :
        ((slot_st[1] == S_READY) && (slot_seq[1] == rd_expect)) ? 2'd1 : ready_slot;

    // ------------------------------------------------------------- write side
    localparam [2:0] FLUSH_CNT = (MODE == 0) ? 3'd3 : 3'd7;
    // Widened before adding: 1-bit + 1-bit is a 1-bit (truncated) sum in
    // Verilog, which silently reported 0 bytes for keep=0xF (probe-r1).
    wire [2:0] keep_cnt = {2'b0, wr_keep[0]} + {2'b0, wr_keep[1]} +
                          {2'b0, wr_keep[2]} + {2'b0, wr_keep[3]};
    // Word k of the group must land in lane k (bits [width*k +: width]).
    // The previous "newest at the LSB" form emitted every group in reverse
    // order, which the PC decoder caught as a non-zlib payload (r1 full frame).
    wire [511:0] wsh = (MODE == 0)
        ? ({472'd0, wr_data}      << (wcnt * 8'd40))
        : ({480'd0, wr_data[31:0]} << (wcnt * 8'd32));
    wire [255:0] pack_n = pack_r | wsh[255:0];
    wire [31:0]  add_bytes = (MODE == 0) ? 32'd5 : {29'd0, keep_cnt};
    wire flush   = (wcnt == FLUSH_CNT) || wr_last;
    // ------------------------------------------------------------------
    // T10.b12 R1 (c): abort wins over a same-cycle write and over a same-cycle
    // begin.  A beat that arrives together with wr_abort is *not* consumed
    // (wr_ready = 0) and a flush word is not pushed, so a same-cycle
    // wr_last + wr_abort can never publish a damaged frame.  Because the slot
    // that the abort frees is about to become free, a wr_begin in that same
    // cycle is accepted when the *other* slot is FREE: the old slot is
    // released and the new frame starts, so no begin is lost and there are
    // never two WRITE slots.
    wire abort_now = wr_abort && wr_active;
    wire begin_now = wr_begin && wr_begin_ready;
    wire accept  = wr_active && ddr_ready && wr_valid && !wr_abort;

    assign wr_ready      = accept && (!flush || ddr_wready);
    assign wr_begin_ready = rst_n && ddr_ready && free_valid &&
                            (!wr_active || abort_now);
    assign ddr_wvalid    = accept && flush;
    assign ddr_awvalid   = ddr_wvalid;
    assign ddr_wdata     = pack_n;
    assign ddr_awaddr    = BASE_WORD + (wr_slot ? SLOT_WORDS[31:0] : 32'd0) + {{(32-AWB){1'b0}}, waddr};

    // -------------------------------------------------------------- read side
    assign rd_open_ready = rst_n && ddr_ready && (rd_state == R_IDLE) && ready_valid;
    assign rd_id         = slot_id[oldest_slot];
    assign rd_len_bytes  = slot_len[oldest_slot];
    // MODE 0 packs 4 groups (20 bytes) per DDR word; MODE 1 packs 32 stream bytes.
    wire [31:0] words_of = (MODE == 0) ? ((slot_len[oldest_slot] + 32'd19) / 32'd20)
                                       : ((slot_len[oldest_slot] + 32'd31) >> 5);
    assign ddr_arvalid   = (rd_state == R_AR) && !rd_armed;
    assign ddr_araddr    = BASE_WORD + (rd_sel ? SLOT_WORDS[31:0] : 32'd0) + rd_idx;
    assign ddr_rready    = (rd_state == R_RW);

    // ------------------------------------------------ T10.b9 observation only
    // (packed exactly as status packet v3 fields 28..33 require)
    assign st_wr_ptr         = {{(32-AWB){1'b0}}, waddr};
    assign st_wr_state       = {wr_active, wr_slot[0], wcnt, nbytes[26:0]};
    assign st_rd_state       = {27'd0, rd_valid, rd_sel[0], rd_armed, rd_state};
    assign st_slot_st        = {26'd0, slot_seq[1], slot_seq[0], slot_st[1], slot_st[0]};
    assign st_slot_len0      = slot_len[0];
    assign st_slot_len1      = slot_len[1];
    assign st_rd_idx         = rd_idx;
    assign st_rd_words       = rd_words;
    assign st_free_valid     = free_valid;
    assign st_wr_active_out  = wr_active;
    wire   wr_word_hs        = ddr_wvalid && ddr_wready;
    wire   ar_hs             = ddr_arvalid && ddr_arready;

    always @(posedge clk) begin
        if (!rst_n) begin
            slot_st[0] <= S_FREE; slot_st[1] <= S_FREE;
            slot_id[0] <= 32'd0;  slot_id[1] <= 32'd0;
            slot_len[0] <= 32'd0; slot_len[1] <= 32'd0;
            slot_seq[0] <= 1'b0;  slot_seq[1] <= 1'b0;
            pub_tgl <= 1'b0; rd_expect <= 1'b0;
            wr_active <= 1'b0; wr_slot <= 2'd0; wcnt <= 3'd0;
            pack_r <= 256'd0; nbytes <= 32'd0; waddr <= {AWB{1'b0}};
            rd_state <= R_IDLE; rd_sel <= 2'd0; rd_words <= 32'd0; rd_idx <= 32'd0;
            rd_data <= 256'd0; rd_valid <= 1'b0;
            st_published <= 32'd0; st_dropped <= 32'd0; st_errors <= 32'd0;
            st_last_bytes <= 32'd0; st_read_words <= 32'd0; st_dup_words <= 32'd0;
            rd_prev <= 256'd0; rd_prev_v <= 1'b0; rd_armed <= 1'b0;
            st_wr_beats <= 32'd0; st_wr_words <= 32'd0; st_ar_valid <= 32'd0;
            st_ar_hs <= 32'd0; st_rv_cnt <= 32'd0; st_rd_open_ok <= 32'd0;
            st_rd_close_cnt <= 32'd0; st_abort_cnt <= 32'd0;
        end else begin
            // ------------------------------------------- T10.b9 observation
            if (wr_ready)      st_wr_beats <= st_wr_beats + 32'd1;
            if (wr_word_hs)    st_wr_words <= st_wr_words + 32'd1;
            if (ddr_arvalid)   st_ar_valid <= st_ar_valid + 32'd1;
            if (ar_hs)         st_ar_hs    <= st_ar_hs    + 32'd1;
            if (ddr_rvalid)    st_rv_cnt   <= st_rv_cnt   + 32'd1;

            // -------------------------------------- begin / abort (R1 order)
            // 1) abort + begin in the same cycle: release the aborted slot and
            //    start the new frame in the other (FREE) slot.  Counters follow
            //    the abort.  The two slot_st writes target different slots.
            // 2) abort alone: the WRITING slot is freed, nothing is published.
            // 3) begin alone: unchanged b9 semantics.
            if (abort_now && begin_now) begin
                slot_st[wr_slot]   <= S_FREE;
                slot_st[free_slot] <= S_WRITE;
                slot_id[free_slot] <= wr_id;
                slot_seq[free_slot] <= pub_tgl;
                pub_tgl   <= ~pub_tgl;
                wr_slot   <= free_slot;
                wr_active <= 1'b1;
                wcnt      <= 3'd0;
                pack_r    <= 256'd0;
                nbytes    <= 32'd0;
                waddr     <= {AWB{1'b0}};
                st_dropped   <= st_dropped + 32'd1;
                st_abort_cnt <= st_abort_cnt + 32'd1;
            end else if (abort_now) begin
                slot_st[wr_slot] <= S_FREE;
                wr_active <= 1'b0;
                st_dropped   <= st_dropped + 32'd1;
                st_abort_cnt <= st_abort_cnt + 32'd1;
            end else if (begin_now) begin
                wr_active <= 1'b1;
                wr_slot   <= free_slot;
                slot_st[free_slot] <= S_WRITE;
                slot_id[free_slot] <= wr_id;
                slot_seq[free_slot] <= pub_tgl;
                pub_tgl   <= ~pub_tgl;
                wcnt      <= 3'd0;
                pack_r    <= 256'd0;
                nbytes    <= 32'd0;
                waddr     <= {AWB{1'b0}};
            end

            // -------------------------------------------------------- write
            if (wr_ready) begin
                nbytes <= nbytes + add_bytes;
                if (flush) begin
                    wcnt   <= 3'd0;
                    pack_r <= 256'd0;
                    if (wr_last) begin
                        wr_active <= 1'b0;
                        if ((EXPECT_BYTES > 0) && ((nbytes + add_bytes) != EXPECT_BYTES[31:0])) begin
                            // incomplete / over-long frame: never publish a half frame
                            slot_st[wr_slot] <= S_FREE;
                            st_errors <= st_errors + 32'd1;
                            st_dropped <= st_dropped + 32'd1;
                        end else begin
                            slot_st[wr_slot] <= S_READY;
                            slot_len[wr_slot] <= nbytes + add_bytes;
                            st_published <= st_published + 32'd1;
                            st_last_bytes <= nbytes + add_bytes;
                        end
                    end else begin
                        waddr <= waddr + {{(AWB-1){1'b0}}, 1'b1};
                    end
                end else begin
                    wcnt   <= wcnt + 3'd1;
                    pack_r <= pack_n;
                end
            end

            // --------------------------------------------------------- read
            case (rd_state)
                R_IDLE: begin
                    if (rd_open && rd_open_ready) begin
                        rd_sel   <= oldest_slot;
                        slot_st[oldest_slot] <= S_READING;
                        rd_expect <= ~rd_expect;
                        rd_words <= words_of;
                        rd_idx   <= 32'd0;
                        rd_armed <= 1'b0;
                        rd_prev_v <= 1'b0;
                        rd_state <= R_AR;
                        st_rd_open_ok <= st_rd_open_ok + 32'd1;
                    end
                end
                R_AR: begin
                    if (ddr_arready && !rd_armed) begin
                        rd_armed <= 1'b1;   // one AR per word
                        rd_state <= R_RW;
                    end
                end
                R_RW: begin
                    if (ddr_rvalid) begin
                        rd_data  <= ddr_rdata;
                        rd_valid <= 1'b1;
                        rd_idx   <= rd_idx + 32'd1;
                        rd_armed <= 1'b0;
                        st_read_words <= st_read_words + 32'd1;
                        if (rd_prev_v && (ddr_rdata === rd_prev))
                            st_dup_words <= st_dup_words + 32'd1;
                        rd_prev   <= ddr_rdata;
                        rd_prev_v <= 1'b1;
                        rd_state <= R_HOLD;
                    end
                end
                R_HOLD: begin
                    if (rd_take) begin
                        rd_valid <= 1'b0;
                        if (rd_idx >= rd_words) rd_state <= R_HOLD;   // wait for close
                        else rd_state <= R_AR;
                    end
                    if (rd_close) begin
                        rd_valid <= 1'b0;
                        slot_st[rd_sel] <= S_FREE;
                        rd_state <= R_IDLE;
                        st_rd_close_cnt <= st_rd_close_cnt + 32'd1;
                    end
                end
                default: rd_state <= R_IDLE;
            endcase
        end
    end
endmodule
