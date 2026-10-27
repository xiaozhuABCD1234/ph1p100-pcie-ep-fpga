`timescale 1ns/1ps
// =============================================================================
// tb_status_v6.v -- T10.b17: status packet v6 (273 B / 67 fields) format check.
// Drives the real a1_uart_export with 67 known field values and checks magic,
// LEN=273, VER=6, XOR over bytes 0..271, every little-endian field in the frozen
// order, and packet length/back-to-back placement.
// =============================================================================
module tb_b19_status_v6;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #0.5 clk = ~clk;

    wire [7:0] dbg_byte;
    wire       dbg_byte_valid;
    wire       uart_txd;

    reg  [31:0] dq_frame_id   = 32'h1234_5678;
    reg  [31:0] dq_raw_len    = 32'd2592000;
    reg  [31:0] dq_xform_len  = 32'd2592000;
    reg  [31:0] dq_stream_len = 32'd100;
    reg  [31:0] dq_raw_crc    = 32'hAAAA_0001;
    reg  [31:0] dq_xform_crc  = 32'hAAAA_0002;
    reg  [31:0] dq_stream_crc = 32'hAAAA_0003;
    reg         desc_push = 1'b0;

    wire        cmp_open, cmp_close;
    reg         cmp_open_ready = 1'b1;
    reg  [31:0] cmp_len = 32'd100;
    reg  [31:0] cmp_id  = 32'h1234_5678;
    wire        rd_take;
    reg  [255:0] rd_data = 256'd0;
    reg         rd_valid = 1'b0;

    wire [31:0] st_exported, st_bytes, st_err;
    wire        st_busy;
    wire [31:0] dbg_st;

    reg  [255:0] ssnap;
    reg  [479:0] camsnap;
    reg  [639:0] rawsnap;
    reg  [767:0] extsnap;

    integer i;
    initial begin
        ssnap   = 256'd0;
        camsnap = 480'd0;
        rawsnap = 640'd0;
        extsnap = 768'd0;
        for (i = 0; i < 8; i = i + 1)  ssnap[i*32 +: 32]   = 32'h1111_0000 + i + 1;
        for (i = 0; i < 15; i = i + 1) camsnap[i*32 +: 32] = 32'h2222_0000 + i + 1;
        // T10.b19-cam-a: field #13 is cam_sysstat; CAM_SEL is bit 12 and must
        // read 0 when the merged top is built with CAM_SEL=1'b0.
        camsnap[4*32 +: 32] = 32'h0000_0F01;    // cfg_done=1, lane=F, CAM_SEL=bit12=0
        for (i = 0; i < 20; i = i + 1) rawsnap[i*32 +: 32] = 32'h3333_0000 + i + 1;
        for (i = 0; i < 16; i = i + 1) extsnap[i*32 +: 32] = 32'h4444_0000 + i + 1;
        // v6 #60..#67
        extsnap[16*32 +: 32] = 32'h0000_03C0;   // #60 last_issued_ar_addr = 960 (word 120)
        extsnap[17*32 +: 32] = 32'h0000_0000;   // #61 low3
        extsnap[18*32 +: 32] = 32'h0000_0000;   // #62 timeout_ar_addr
        extsnap[19*32 +: 32] = 32'h0000_0000;   // #63 timeout low3
        extsnap[20*32 +: 32] = 32'h0000_0000;   // #64 same_aw_ar_cnt
        extsnap[21*32 +: 32] = 32'h0000_0000;   // #65 same_w_ar_cnt
        extsnap[22*32 +: 32] = 32'h0000_0000;   // #66 inflight_state
        extsnap[23*32 +: 32] = 32'h0000_0000;   // #67 diag_flags
    end

    a1_uart_export #(.W(64), .H(8), .UART_DIV(1), .HB_DIV(0), .STS_DIV(3000)) u_exp (
        .clk (clk), .rst_n (rst_n),
        .desc_push (desc_push),
        .d_frame_id (dq_frame_id), .d_raw_len (dq_raw_len),
        .d_xform_len (dq_xform_len), .d_stream_len (dq_stream_len),
        .d_raw_crc (dq_raw_crc), .d_xform_crc (dq_xform_crc),
        .d_stream_crc (dq_stream_crc), .d_profile (2'b11),
        .cmp_open (cmp_open), .cmp_open_ready (cmp_open_ready), .cmp_len (cmp_len),
        .cmp_id (cmp_id), .cmp_close (cmp_close),
        .rd_data (rd_data), .rd_valid (rd_valid), .rd_take (rd_take),
        .dbg_byte (dbg_byte), .dbg_byte_valid (dbg_byte_valid),
        .uart_clk (clk), .uart_txd (uart_txd),
        .st_exported (st_exported), .st_bytes (st_bytes), .st_err (st_err),
        .st_busy (st_busy),
        .sts_cap_frames (ssnap[0*32 +: 32]),
        .sts_raw_pub    (ssnap[1*32 +: 32]),
        .sts_enc_frames (ssnap[2*32 +: 32]),
        .sts_exported   (ssnap[3*32 +: 32]),
        .sts_raw_drop   (ssnap[4*32 +: 32]),
        .sts_cmp_drop   (ssnap[5*32 +: 32]),
        .sts_errors     (ssnap[6*32 +: 32]),
        .sts_read_words (ssnap[7*32 +: 32]),
        .sts_cam        (camsnap),
        .sts_raw        (rawsnap),
        .sts_ext        (extsnap),
        .dbg_st         (dbg_st)
    );

    reg [7:0] pkt [0:272];
    integer   npkt = 0, nbyte = 0, nbad = 0, k;
    reg [7:0] xacc;

    always @(posedge clk) begin
        if (rst_n && dbg_byte_valid) begin
            pkt[nbyte] = dbg_byte;
            nbyte = nbyte + 1;
            if (nbyte == 273) begin
                nbyte = 0;
                npkt  = npkt + 1;
                if ((pkt[0] !== 8'hA5) || (pkt[1] !== 8'h5A) ||
                    (pkt[2] !== 8'h11) || (pkt[3] !== 8'd6)) begin
                    nbad = nbad + 1;
                    $display("B17_V6_BAD_HDR n=%0d %h %h %h %0d", npkt,
                             pkt[0], pkt[1], pkt[2], pkt[3]);
                end
                xacc = 8'd0;
                for (k = 0; k < 272; k = k + 1) xacc = xacc ^ pkt[k];
                if (xacc !== pkt[272]) begin
                    nbad = nbad + 1;
                    $display("B17_V6_BAD_XOR n=%0d got=%h exp=%h", npkt, pkt[272], xacc);
                end
                for (k = 0; k < 67; k = k + 1) begin
                    if ({pkt[7+4*k], pkt[6+4*k], pkt[5+4*k], pkt[4+4*k]} !==
                        ((k < 8)  ? ssnap[k*32 +: 32] :
                         (k < 23) ? camsnap[(k-8)*32 +: 32] :
                         (k < 43) ? rawsnap[(k-23)*32 +: 32] :
                                    extsnap[(k-43)*32 +: 32])) begin
                        nbad = nbad + 1;
                        $display("B17_V6_BAD_FIELD n=%0d f=%0d got=%h exp=%h", npkt, k+1,
                                 {pkt[7+4*k], pkt[6+4*k], pkt[5+4*k], pkt[4+4*k]},
                                 ((k < 8)  ? ssnap[k*32 +: 32] :
                                  (k < 23) ? camsnap[(k-8)*32 +: 32] :
                                  (k < 43) ? rawsnap[(k-23)*32 +: 32] :
                                             extsnap[(k-43)*32 +: 32]));
                    end
                end
                // T10.b19-cam-a: field #13 (k=12) bit 12 must read 0 (A selected).
                if ((({pkt[7+4*12], pkt[6+4*12], pkt[5+4*12], pkt[4+4*12]} >> 12) & 1) !== 1'b0) begin
                    nbad = nbad + 1;
                    $display("B19_V6_BAD_BIT12 n=%0d f13=%h", npkt,
                             {pkt[7+4*12], pkt[6+4*12], pkt[5+4*12], pkt[4+4*12]});
                end else begin
                    $display("B19_V6_F13_BIT12_OK n=%0d f13=%h", npkt,
                             {pkt[7+4*12], pkt[6+4*12], pkt[5+4*12], pkt[4+4*12]});
                end
            end
        end
    end

    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        wait (npkt >= 4);
        repeat (20) @(posedge clk);
        $display("B17_V6_DONE packets=%0d bad=%0d len=273 ver=6 fields=67", npkt, nbad);
        $display("B17_V6_RESULT pass=%0d", (npkt >= 4 && nbad == 0) ? 1 : 0);
        $finish;
    end

    initial begin
        #4000000;
        $display("B17_V6_TIMEOUT packets=%0d nbyte=%0d", npkt, nbyte);
        $display("B17_V6_RESULT pass=0");
        $finish;
    end
endmodule
