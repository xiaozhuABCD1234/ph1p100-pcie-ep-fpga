`timescale 1ns/1ps
// =============================================================================
// tb_status_v3.v -- format + single-snapshot self-check for the 177-byte v3
// status packet.
//
// Instantiates a1_uart_export alone (UART_DIV=1, STS_DIV=4096) and captures
// every byte handed to the transmitter.  All 43 fields are driven from ONE
// source, so the companion parser (board/parse_status_v3.py) can prove:
//
//   MODE 0 (const): field k == 0xA1B2C300 + k  -> order/length/version/XOR
//   MODE 1 (tear) : field k == cnt + k with cnt incrementing every clk, so a
//                   torn (per-field resampled) packet would show more than one
//                   value of (field_k - k) inside one packet.
//
// Plusargs: +OUT=<one decimal byte per line>  +NPKT=<packets>  +MODE=<0|1>
// =============================================================================
module tb_status_v3;
    localparam integer NPKT_DEF = 4;
    localparam integer PKT      = 177;

    reg clk = 1'b0;
    reg uart_clk = 1'b0;
    reg rst_n = 1'b0;
    always #2.6665 clk = ~clk;
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

    integer mode = 0;
    reg [31:0] tear = 32'd0;
    always @(posedge clk) if (rst_n) tear <= tear + 32'd1;

    // 43 fields, field k in bits [32k +: 32]
    wire [1375:0] allf;
    genvar k;
    generate
        for (k = 0; k < 43; k = k + 1) begin : g_field
            assign allf[k*32 +: 32] = (mode == 1) ? (tear + k) : (32'hA1B2C300 + k);
        end
    endgenerate

    a1_uart_export #(
        .W (8), .H (2), .UART_DIV (1), .HB_DIV (0), .STS_DIV (4096)
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
        .sts_cap_frames (allf[31:0]),    .sts_raw_pub    (allf[63:32]),
        .sts_enc_frames (allf[95:64]),   .sts_exported   (allf[127:96]),
        .sts_raw_drop   (allf[159:128]), .sts_cmp_drop   (allf[191:160]),
        .sts_errors     (allf[223:192]), .sts_read_words (allf[255:224]),
        .sts_cam        (allf[735:256]),
        .sts_raw        (allf[1375:736])
    );

    integer fd;
    integer cap_bytes = 0;
    integer npkt = 0;
    integer npkt_want = NPKT_DEF;
    reg [1023:0] out_path;
    integer i = 0;

    always @(posedge uart_clk) begin
        if (rst_n && dbg_byte_valid) begin
            $fwrite(fd, "%0d\n", dbg_byte);
            cap_bytes = cap_bytes + 1;
            if ((cap_bytes % PKT) == 0) npkt = npkt + 1;
        end
    end

    initial begin
        if (!$value$plusargs("MODE=%d", mode)) mode = 0;
        if (!$value$plusargs("OUT=%s", out_path)) out_path = "status_v3_bytes.txt";
        if (!$value$plusargs("NPKT=%d", npkt_want)) npkt_want = NPKT_DEF;
        fd = $fopen(out_path, "w");
        if (fd == 0) begin
            $display("TB_OPEN_FAIL %0s", out_path);
            $finish;
        end

        repeat (10) @(negedge clk);
        rst_n = 1'b1;
        repeat (20) @(negedge clk);

        while ((npkt < npkt_want) && (i < 2000000)) begin
            @(negedge clk);
            i = i + 1;
        end
        repeat (400) @(negedge clk);

        $display("TB_STATUS_V3 mode=%0d bytes=%0d packets=%0d stop_err=%0d busy=%0d",
                 mode, cap_bytes, npkt, st_err, st_busy);
        if (cap_bytes != npkt_want * PKT)
            $display("TB_STATUS_V3_BAD_LEN want=%0d got=%0d", npkt_want * PKT, cap_bytes);
        if (npkt != npkt_want)
            $display("TB_STATUS_V3_BAD_PACKETS want=%0d got=%0d", npkt_want, npkt);
        $display("TB_DONE mode=%0d packets=%0d bytes=%0d", mode, npkt, cap_bytes);
        $fclose(fd);
        $finish;
    end
endmodule
