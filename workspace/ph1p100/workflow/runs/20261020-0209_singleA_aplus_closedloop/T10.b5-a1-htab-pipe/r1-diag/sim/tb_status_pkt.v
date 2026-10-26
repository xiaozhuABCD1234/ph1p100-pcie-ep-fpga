`timescale 1ns/1ps
// =============================================================================
// tb_status_pkt.v -- r1-diag focused testbench for the A5/5A status packet.
//
// Instantiates a1_uart_export alone (no DDR, no A+ core) with UART_DIV=1 so one
// UART bit lasts exactly one clk cycle.  The eight counter inputs carry
// distinct constants, so the little-endian packing and the XOR byte are
// checked byte-for-byte against the frozen contract.  Received bytes are
// written as hex lines for board/parse_status.py.
//
// Expected packet for the constants below:
//   A5 5A | 11 11 11 11 | 22 22 22 22 | 33 33 33 33 | 44 44 44 44 |
//          55 55 55 55 | 66 66 66 66 | 77 77 77 77 | 88 88 88 88 | XOR
// =============================================================================
module tb_status_pkt;
    localparam integer UART_DIV = 1;
    localparam integer STS_DIV  = 2048;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg [31:0] c_cap = 32'h11111111;
    reg [31:0] c_raw = 32'h22222222;
    reg [31:0] c_enc = 32'h33333333;
    reg [31:0] c_exp = 32'h44444444;
    reg [31:0] c_rdp = 32'h55555555;
    reg [31:0] c_cdp = 32'h66666666;
    reg [31:0] c_err = 32'h77777777;
    reg [31:0] c_rdw = 32'h88888888;

    wire txd;
    wire [7:0] dbg_byte;
    wire dbg_valid;
    wire st_busy;

    a1_uart_export #(
        .W(8), .H(2), .UART_DIV(UART_DIV), .HB_DIV(0), .STS_DIV(STS_DIV)
    ) dut (
        .clk (clk), .rst_n (rst_n),
        .desc_push (1'b0),
        .d_frame_id (32'd0), .d_raw_len (32'd0), .d_xform_len (32'd0),
        .d_stream_len (32'd0), .d_raw_crc (32'd0), .d_xform_crc (32'd0),
        .d_stream_crc (32'd0), .d_profile (2'd0),
        .cmp_open (), .cmp_open_ready (1'b1), .cmp_len (32'd0), .cmp_id (32'd0),
        .cmp_close (),
        .rd_data (256'd0), .rd_valid (1'b0), .rd_take (),
        .dbg_byte (dbg_byte), .dbg_byte_valid (dbg_valid),
        .uart_clk (clk), .uart_txd (txd),
        .st_exported (), .st_bytes (), .st_err (), .st_busy (st_busy),
        .sts_cap_frames (c_cap), .sts_raw_pub (c_raw), .sts_enc_frames (c_enc),
        .sts_exported (c_exp), .sts_raw_drop (c_rdp), .sts_cmp_drop (c_cdp),
        .sts_errors (c_err), .sts_read_words (c_rdw)
    );

    // ------------------------------------------------------------- RX monitor
    // Samples on the negedge, i.e. the value driven by the previous posedge.
    // With UART_DIV=1 each negedge lands in the middle of one wire bit.
    integer fd;
    integer nbytes = 0;
    reg     in_pkt = 1'b0;
    integer bi = 0;
    reg [7:0] sh = 8'd0;
    integer stop_err = 0;

    always @(negedge clk) begin
        if (rst_n) begin
            if (!in_pkt) begin
                if (!txd) begin
                    in_pkt <= 1'b1;
                    bi     <= 0;
                end
            end else begin
                if (bi < 8) begin
                    sh[bi] <= txd;
                    bi     <= bi + 1;
                end else begin
                    if (txd !== 1'b1) stop_err = stop_err + 1;
                    $fdisplay(fd, "%02x", sh);
                    nbytes = nbytes + 1;
                    in_pkt <= 1'b0;
                    bi     <= 0;
                end
            end
        end
    end

    integer nstart;
    initial begin
        fd = $fopen("status_bytes.txt", "w");
        repeat (6) @(posedge clk);
        rst_n <= 1'b1;
        // run long enough for at least 5 packets (2048 cycles each)
        repeat (STS_DIV * 7) @(posedge clk);
        $fclose(fd);
        $display("TB_STATUS bytes=%0d stop_err=%0d busy=%b", nbytes, stop_err,
                 st_busy);
        if (nbytes == 0) $display("TB_STATUS_FAIL no_bytes");
        else if (nbytes % 35 != 0) $display("TB_STATUS_FAIL partial_packet");
        else $display("TB_STATUS_PACKETS %0d", nbytes / 35);
        $finish;
    end
endmodule
