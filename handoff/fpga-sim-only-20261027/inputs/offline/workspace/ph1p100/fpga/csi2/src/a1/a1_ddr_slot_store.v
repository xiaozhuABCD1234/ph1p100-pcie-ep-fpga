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
    output reg  [31:0] st_dup_words
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
    wire accept  = wr_active && ddr_ready && wr_valid;

    assign wr_ready      = accept && (!flush || ddr_wready);
    assign wr_begin_ready = rst_n && ddr_ready && !wr_active && free_valid;
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
        end else begin
            // -------------------------------------------------------- begin
            if (wr_begin && wr_begin_ready) begin
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

            // ------------------------------------------------------- abort
            if (wr_abort && wr_active) begin
                slot_st[wr_slot] <= S_FREE;
                wr_active <= 1'b0;
                st_dropped <= st_dropped + 32'd1;
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
                    end
                end
                default: rd_state <= R_IDLE;
            endcase
        end
    end
endmodule
