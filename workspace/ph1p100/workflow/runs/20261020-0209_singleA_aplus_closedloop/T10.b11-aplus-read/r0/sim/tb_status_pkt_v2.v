`timescale 1ns/1ps
// =============================================================================
// tb_status_pkt_v2.v -- format self-check for the 97-byte v2 status packet.
//
// Instantiates a1_uart_export alone (UART_DIV=1, STS_DIV=2048) with 23 fixed
// constants and captures every byte the transmitter is handed.  The companion
// parser (board/parse_status_v2.py) then checks magic/LEN/VER/XOR and every
// field value; this TB additionally fails loudly on a short/long packet.
//
//   legacy: 0x11111111 .. 0x88888888
//   cam   : 0xA1A1A1A1 + k  (k = 0..14, so a field-order swap is visible)
//
// Plusargs: +OUT=<one decimal byte per line>  +NPKT=<packets to wait for>
// =============================================================================
module tb_status_pkt_v2;
    localparam integer NPKT_DEF = 6;

    reg clk = 1'b0;
    reg uart_clk = 1'b0;
    reg rst_n = 1'b0;
    always #2.6665 clk = ~clk;                  // 187.5 MHz
    initial begin #1.0; forever #2.6665 uart_clk = ~uart_clk; end

    reg         desc_push = 1'b0;
    reg  [31:0] d_frame_id = 32'd0, d_raw_len = 32'd0, d_xform_len = 32'd0;
    reg  [31:0] d_stream_len = 32'd0, d_raw_crc = 32'd0, d_xform_crc = 32'd0;
    reg  [31:0] d_stream_crc = 32'd0;
    reg  [1:0]  d_profile = 2'd0;

    wire        cmp_open, cmp_close, rd_take;
    reg         cmp_open_ready = 1'b1;
    reg  [31:0] cmp_len = 32'd0, cmp_id = 32'd0;
    reg  [255:0] rd_data = 256'd0;
    reg         rd_valid = 1'b0;

    wire [7:0]  dbg_byte;
    wire        dbg_byte_valid;
    wire        uart_txd;

    wire [31:0] st_exported, st_bytes, st_err;
    wire        st_busy;

    // 15 camera constants, field k = 0xA1A1A1A1 + k
    wire [479:0] cam_const = {
        32'hA1A1A1A1 + 32'd14, 32'hA1A1A1A1 + 32'd13,
        32'hA1A1A1A1 + 32'd12, 32'hA1A1A1A1 + 32'd11,
        32'hA1A1A1A1 + 32'd10, 32'hA1A1A1A1 + 32'd9,
        32'hA1A1A1A1 + 32'd8,  32'hA1A1A1A1 + 32'd7,
        32'hA1A1A1A1 + 32'd6,  32'hA1A1A1A1 + 32'd5,
        32'hA1A1A1A1 + 32'd4,  32'hA1A1A1A1 + 32'd3,
        32'hA1A1A1A1 + 32'd2,  32'hA1A1A1A1 + 32'd1,
        32'hA1A1A1A1 };

    a1_uart_export #(
        .W (8), .H (2), .UART_DIV (1), .HB_DIV (0), .STS_DIV (2048)
    ) dut (
        .clk (clk), .rst_n (rst_n),
        .desc_push (desc_push),
        .d_frame_id (d_frame_id), .d_raw_len (d_raw_len), .d_xform_len (d_xform_len),
        .d_stream_len (d_stream_len), .d_raw_crc (d_raw_crc),
        .d_xform_crc (d_xform_crc), .d_stream_crc (d_stream_crc),
        .d_profile (d_profile),
        .cmp_open (cmp_open), .cmp_open_ready (cmp_open_ready), .cmp_len (cmp_len),
        .cmp_id (cmp_id), .cmp_close (cmp_close),
        .rd_data (rd_data), .rd_valid (rd_valid), .rd_take (rd_take),
        .dbg_byte (dbg_byte), .dbg_byte_valid (dbg_byte_valid),
        .uart_clk (uart_clk), .uart_txd (uart_txd),
        .st_exported (st_exported), .st_bytes (st_bytes), .st_err (st_err),
        .st_busy (st_busy),
        .sts_cap_frames (32'h11111111), .sts_raw_pub    (32'h22222222),
        .sts_enc_frames (32'h33333333), .sts_exported   (32'h44444444),
        .sts_raw_drop   (32'h55555555), .sts_cmp_drop   (32'h66666666),
        .sts_errors     (32'h77777777), .sts_read_words (32'h88888888),
        .sts_cam        (cam_const)
    );

    integer fd;
    integer cap_bytes = 0;
    integer npkt = 0;
    integer npkt_want = NPKT_DEF;
    reg [1023:0] out_path;
    integer i = 0;

    // packet bookkeeping: every 97th byte starts a new packet
    always @(posedge uart_clk) begin
        if (rst_n && dbg_byte_valid) begin
            $fwrite(fd, "%0d\n", dbg_byte);
            cap_bytes = cap_bytes + 1;
            $display("BYTE %0d %02h", cap_bytes - 1, dbg_byte);
            if (((cap_bytes % 97) == 0)) npkt = npkt + 1;
        end
    end

    initial begin
        if (!$value$plusargs("OUT=%s", out_path)) out_path = "status_v2_bytes.txt";
        if (!$value$plusargs("NPKT=%d", npkt_want)) npkt_want = NPKT_DEF;
        fd = $fopen(out_path, "w");
        if (fd == 0) begin
            $display("TB_OPEN_FAIL %0s", out_path);
            $finish;
        end

        repeat (10) @(negedge clk);
        rst_n = 1'b1;
        repeat (20) @(negedge clk);

        while ((npkt < npkt_want) && (i < 200000)) begin
            @(negedge clk);
            i = i + 1;
        end
        repeat (400) @(negedge clk);

        $display("TB_STATUS bytes=%0d packets=%0d stop_err=%0d busy=%0d",
                 cap_bytes, npkt, st_err, st_busy);
        if (cap_bytes != npkt_want * 97)
            $display("TB_STATUS_BAD_LEN want=%0d got=%0d", npkt_want * 97, cap_bytes);
        if (npkt != npkt_want)
            $display("TB_STATUS_BAD_PACKETS want=%0d got=%0d", npkt_want, npkt);
        $fclose(fd);
        $finish;
    end
endmodule
