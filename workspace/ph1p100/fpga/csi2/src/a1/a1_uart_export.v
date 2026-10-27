`timescale 1ns/1ps
// =============================================================================
// a1_uart_export.v -- A1 frame -> UART byte-stream exporter.
//
// Frozen wire contract (T10.b1 P1, little-endian, 44-byte header):
//   0  u32 magic      = 0x31553141  (file bytes 'A','1','U','1')
//   4  u8  version    = 0x01
//   5  u8  flags      = {6'b0, pred, prep}
//   6  u16 header_len = 44
//   8  u32 frame_id
//  12  u16 width
//  14  u16 height
//  16  u32 raw_len    (bytes, W*H*10/8)
//  20  u32 xform_len  (bytes fed to the A+ core)
//  24  u32 stream_len (zlib bytes)
//  28  u32 raw_crc    (zlib CRC-32 of the raw bytes)
//  32  u32 xform_crc  (zlib CRC-32 of the transform bytes)
//  36  u32 stream_crc (zlib CRC-32 of the zlib stream)
//  40  u32 header_crc (zlib CRC-32 of bytes 0..39)
// then stream_len payload bytes (the zlib stream).
//
// The exporter owns one published slot from open to close, so a frame that has
// been published is never overwritten while it is being exported.  A two-entry
// descriptor FIFO matches the two store slots.
//
// r4 (2026-10-24): the capture_async_fifo CDC stage between the exporter and
// the transmitter is removed.  Every board integration drives clk and uart_clk
// from the same net (P2: both = clk_a1), so the FIFO was pure overhead and a
// candidate for a stuck read side on hardware.  The exporter now holds exactly
// one byte in tx_byte_r and uses a real ready/valid handshake against
// a1_uart_tx: valid = tx_valid_r & ~uart_busy, request only accepted while
// ~uart_busy.  Byte order, frame format, CRC and the number of clock cycles
// spent per byte on the wire are unchanged (the transmitter still needs
// 10*UART_DIV cycles per byte).
//
// Optional idle beacon: with HB_DIV > 0 the exporter emits a single 0x55 byte
// every HB_DIV clk cycles, but only while it is completely idle (no descriptor
// pending, no frame open, no byte in flight).  It can therefore never appear
// inside a header or payload, and it is disabled by default (HB_DIV = 0) so the
// frozen P1 simulations are unaffected.
// =============================================================================
module a1_uart_export #(
    parameter integer W = 1920,
    parameter integer H = 1080,
    parameter integer UART_DIV = 434,
    parameter integer HB_DIV = 0
) (
    input  wire        clk,        // A1 domain
    input  wire        rst_n,

    input  wire        desc_push,
    input  wire [31:0] d_frame_id,
    input  wire [31:0] d_raw_len,
    input  wire [31:0] d_xform_len,
    input  wire [31:0] d_stream_len,
    input  wire [31:0] d_raw_crc,
    input  wire [31:0] d_xform_crc,
    input  wire [31:0] d_stream_crc,
    input  wire [1:0]  d_profile,

    output reg         cmp_open,
    input  wire        cmp_open_ready,
    input  wire [31:0] cmp_len,
    input  wire [31:0] cmp_id,
    output reg         cmp_close,
    input  wire [255:0] rd_data,
    input  wire        rd_valid,
    output wire        rd_take,

    output wire [7:0]  dbg_byte,
    output wire        dbg_byte_valid,

    input  wire        uart_clk,
    output wire        uart_txd,

    output reg  [31:0] st_exported,
    output reg  [31:0] st_bytes,
    output reg  [31:0] st_err,
    output wire        st_busy
);
    localparam [1:0] E_IDLE = 2'd0, E_OPEN = 2'd1, E_HDR = 2'd2, E_PAY = 2'd3;
    localparam [2:0] P_HDR = 3'd0, P_PAY = 3'd1, P_DONE = 3'd2;
    localparam [7:0] HDR_LAST = 8'd43;
    localparam [15:0] WP = W;
    localparam [15:0] HP = H;

    // ---------------------------------------------------------- descriptor fifo
    reg [255:0] dq [0:1];
    reg [1:0]   dq_wr, dq_rd, dq_cnt;

    reg [31:0]  w_frame_id, w_raw_len, w_xform_len, w_stream_len;
    reg [31:0]  w_raw_crc, w_xform_crc, w_stream_crc;
    reg [1:0]   w_profile;

    reg [1:0]   estate;
    reg [2:0]   pstate;
    reg [7:0]   hdr_idx;
    reg [31:0]  crc_r;
    reg [31:0]  crc_fin;
    reg [31:0]  sent;
    reg [255:0] wbuf;
    reg         wbuf_valid;
    reg [4:0]   pay_idx;
    reg [7:0]   tx_byte_r;
    reg         tx_valid_r;

    reg [31:0]  hb_cnt;             // idle beacon divider
    reg [7:0]   dbg_byte_r;         // byte actually handed to the transmitter
    reg         dbg_byte_valid_r;
    reg         dbg_hold;

    wire        tx_ready;
    wire        uart_busy;
    wire        hb_en   = (HB_DIV > 0);
    wire        hb_tick = hb_en && (hb_cnt == (HB_DIV - 1));

    wire [31:0] hw0 = 32'h31553141;
    wire [31:0] hw1 = {8'h00, 8'd44, 6'd0, w_profile, 8'h01};
    wire [31:0] hw2 = w_frame_id;
    wire [31:0] hw3 = {HP, WP};
    wire [31:0] hw4 = w_raw_len;
    wire [31:0] hw5 = w_xform_len;
    wire [31:0] hw6 = w_stream_len;
    wire [31:0] hw7 = w_raw_crc;
    wire [31:0] hw8 = w_xform_crc;
    wire [31:0] hw9 = w_stream_crc;
    wire [31:0] hw10 = crc_fin;

    reg [31:0] hw_sel;
    always @(*) begin
        case (hdr_idx[7:2])
            4'd0: hw_sel = hw0;
            4'd1: hw_sel = hw1;
            4'd2: hw_sel = hw2;
            4'd3: hw_sel = hw3;
            4'd4: hw_sel = hw4;
            4'd5: hw_sel = hw5;
            4'd6: hw_sel = hw6;
            4'd7: hw_sel = hw7;
            4'd8: hw_sel = hw8;
            4'd9: hw_sel = hw9;
            default: hw_sel = hw10;
        endcase
    end
    wire [7:0] hdr_byte = hw_sel >> {hdr_idx[1:0], 3'b000};

    function [31:0] crc32b;
        input [31:0] c;
        input [7:0]  d;
        integer k;
        reg [31:0] x;
        begin
            x = c ^ {24'd0, d};
            for (k = 0; k < 8; k = k + 1)
                x = x[0] ? ((x >> 1) ^ 32'hEDB88320) : (x >> 1);
            crc32b = x;
        end
    endfunction

    assign rd_take = (estate == E_PAY) && (pstate == P_PAY) && !wbuf_valid &&
                     rd_valid && (sent < w_stream_len);
    assign st_busy = (estate != E_IDLE) || (dq_cnt != 2'd0);

    always @(posedge clk) begin
        if (!rst_n) begin
            dq_wr <= 2'd0; dq_rd <= 2'd0; dq_cnt <= 2'd0;
            w_frame_id <= 32'd0; w_raw_len <= 32'd0; w_xform_len <= 32'd0;
            w_stream_len <= 32'd0; w_raw_crc <= 32'd0; w_xform_crc <= 32'd0;
            w_stream_crc <= 32'd0; w_profile <= 2'd0;
            estate <= E_IDLE; pstate <= P_HDR; hdr_idx <= 8'd0;
            crc_r <= 32'hFFFFFFFF; crc_fin <= 32'd0;
            sent <= 32'd0; wbuf <= 256'd0; wbuf_valid <= 1'b0; pay_idx <= 5'd0;
            tx_byte_r <= 8'd0; tx_valid_r <= 1'b0; hb_cnt <= 32'd0;
            cmp_open <= 1'b0; cmp_close <= 1'b0;
            st_exported <= 32'd0; st_bytes <= 32'd0; st_err <= 32'd0;
        end else begin
            cmp_open  <= 1'b0;
            cmp_close <= 1'b0;
            if (hb_en) begin
                if (hb_tick) hb_cnt <= 32'd0;
                else         hb_cnt <= hb_cnt + 32'd1;
            end

            // ---------------------------------------------------- descriptor in
            if (desc_push) begin
                if (dq_cnt == 2'd2) begin
                    st_err <= st_err + 32'd1;
                end else begin
                    dq[dq_wr] <= {6'd0, d_profile, d_stream_crc, d_xform_crc,
                                  d_raw_crc, d_stream_len, d_xform_len,
                                  d_raw_len, d_frame_id};
                    dq_wr  <= dq_wr + 2'd1;
                    dq_cnt <= dq_cnt + 2'd1;
                end
            end

            // ------------------------------------------------------ tx handshake
            // Single holding register (clk == uart_clk).  tx_valid_r is a
            // one-cycle request; the transmitter samples it on the next edge
            // and then holds busy for the whole 10-bit wire frame, so the next
            // byte can only be offered once the previous stop bit is done.
            tx_valid_r <= 1'b0;
            if (hb_tick && (estate == E_IDLE) && (dq_cnt == 2'd0) &&
                tx_ready && !tx_valid_r) begin
                tx_byte_r  <= 8'h55;
                tx_valid_r <= 1'b1;
            end

            case (estate)
                E_IDLE: begin
                    if (dq_cnt != 2'd0) begin
                        w_frame_id   <= dq[dq_rd][31:0];
                        w_raw_len    <= dq[dq_rd][63:32];
                        w_xform_len  <= dq[dq_rd][95:64];
                        w_stream_len <= dq[dq_rd][127:96];
                        w_raw_crc    <= dq[dq_rd][159:128];
                        w_xform_crc  <= dq[dq_rd][191:160];
                        w_stream_crc <= dq[dq_rd][223:192];
                        w_profile    <= dq[dq_rd][225:224];
                        dq_rd <= dq_rd + 2'd1;
                        dq_cnt <= dq_cnt - 2'd1;
                        estate <= E_OPEN;
                    end
                end
                E_OPEN: begin
                    if (cmp_open_ready) begin
                        cmp_open <= 1'b1;
                        if (cmp_id != w_frame_id) st_err <= st_err + 32'd1;
                        if (cmp_len != w_stream_len) st_err <= st_err + 32'd1;
                        hdr_idx    <= 8'd0;
                        crc_r      <= 32'hFFFFFFFF;
                        crc_fin    <= 32'd0;
                        sent       <= 32'd0;
                        wbuf_valid <= 1'b0;
                        pay_idx    <= 5'd0;
                        pstate     <= P_PAY;
                        estate     <= E_HDR;
                    end
                end
                E_HDR: begin
                    if (!tx_valid_r && tx_ready) begin
                        tx_byte_r  <= hdr_byte;
                        tx_valid_r <= 1'b1;
                        // byte 39 must be folded in AND the final CRC precomputed
                        // in the same cycle, otherwise the word emitted at byte 40
                        // still sees the old crc_fin (r1 header_crc defect).
                        if (hdr_idx < 8'd39) begin
                            crc_r <= crc32b(crc_r, hdr_byte);
                        end else if (hdr_idx == 8'd39) begin
                            crc_r   <= crc32b(crc_r, hdr_byte);
                            crc_fin <= ~crc32b(crc_r, hdr_byte);
                        end
                        if (hdr_idx == HDR_LAST) begin
                            hdr_idx <= 8'd0;
                            estate  <= E_PAY;
                        end else begin
                            hdr_idx <= hdr_idx + 8'd1;
                        end
                    end
                end
                E_PAY: begin
                    if (pstate == P_PAY) begin
                        if (sent >= w_stream_len) begin
                            pstate <= P_DONE;
                        end else if (!wbuf_valid) begin
                            if (rd_valid) begin
                                wbuf <= rd_data;
                                wbuf_valid <= 1'b1;
                                pay_idx <= 5'd0;
                            end
                        end else if (!tx_valid_r && tx_ready) begin
                            tx_byte_r  <= wbuf[{pay_idx, 3'b000} +: 8];
                            tx_valid_r <= 1'b1;
                            sent <= sent + 32'd1;
                            if (pay_idx == 5'd31) wbuf_valid <= 1'b0;
                            else pay_idx <= pay_idx + 5'd1;
                        end
                    end else begin
                        cmp_close   <= 1'b1;
                        st_exported <= st_exported + 32'd1;
                        st_bytes    <= st_bytes + sent;
                        pstate      <= P_HDR;
                        estate      <= E_IDLE;
                    end
                end
                default: estate <= E_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------- direct UART drive
    // No CDC stage: clk == uart_clk on every integration that instantiates this
    // exporter.  The transmitter is fed straight from the holding register.
    assign tx_ready = ~uart_busy;

    // Byte actually loaded by the transmitter (observation only; the P2 board
    // top leaves dbg_byte* unconnected).  dbg_hold makes the capture one-shot
    // per byte even when uart_clk is faster than clk in simulation.
    always @(posedge uart_clk) begin
        if (!rst_n) begin
            dbg_byte_r       <= 8'd0;
            dbg_byte_valid_r <= 1'b0;
            dbg_hold         <= 1'b0;
        end else begin
            dbg_byte_valid_r <= 1'b0;
            if (uart_busy) begin
                dbg_hold <= 1'b0;
            end else if (tx_valid_r && !dbg_hold) begin
                dbg_byte_r       <= tx_byte_r;
                dbg_byte_valid_r <= 1'b1;
                dbg_hold         <= 1'b1;
            end
        end
    end

    assign dbg_byte       = dbg_byte_r;
    assign dbg_byte_valid = dbg_byte_valid_r;

    a1_uart_tx #(.CLK_DIV(UART_DIV)) u_tx (
        .clk    (uart_clk),
        .rst_n  (rst_n),
        .data   (tx_byte_r),
        .valid  (tx_valid_r & ~uart_busy),
        .busy   (uart_busy),
        .txd    (uart_txd)
    );
endmodule

// ---------------------------------------------------------------------------
// Minimal 8N1 transmitter (one start bit, 8 data bits LSB first, one stop bit).
// ---------------------------------------------------------------------------
module a1_uart_tx #(
    parameter integer CLK_DIV = 434
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       valid,
    output reg        busy,
    output reg        txd
);
    reg [15:0] div;
    reg [3:0]  bit_i;
    reg [9:0]  sh;

    always @(posedge clk) begin
        if (!rst_n) begin
            div <= 16'd0; bit_i <= 4'd0; sh <= 10'h3FF; busy <= 1'b0; txd <= 1'b1;
        end else if (!busy) begin
            txd <= 1'b1;
            if (valid) begin
                sh    <= {1'b1, data, 1'b0};
                div   <= 16'd0;
                bit_i <= 4'd0;
                busy  <= 1'b1;
                txd   <= 1'b0;
            end
        end else begin
            if (div == (CLK_DIV - 1)) begin
                div <= 16'd0;
                if (bit_i == 4'd9) begin
                    busy <= 1'b0;
                    txd  <= 1'b1;
                end else begin
                    bit_i <= bit_i + 4'd1;
                    txd   <= sh[bit_i + 4'd1];
                end
            end else begin
                div <= div + 16'd1;
            end
        end
    end
endmodule
