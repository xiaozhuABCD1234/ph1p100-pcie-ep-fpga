`timescale 1ns/1ps
// =============================================================================
// tb_b10_export.sv -- T10.b10 exporter regression (B9-01 arbitration, B9-02
// descriptor queue).  The TB drives ONLY normal module ports and parses the
// byte stream that actually leaves the transmitter (dbg_byte/dbg_byte_valid is
// the byte loaded by a1_uart_tx).  Nothing is forced.
//
// Cases (+CASE=...):
//   arb       two descriptors, status tick due during frame 1 (the b9 deadlock
//             reproduction).  +EXP=old expects the b9 signature, +EXP=new
//             expects status at the boundary and frame 2 afterwards.
//   wrap      14 descriptors through a depth-2 queue (>=12 accepted, several
//             wraps), every frame header/payload byte checked in order, status
//             packets only at frame boundaries, XOR checked.
//   samecycle same as wrap but the producer also pushes into a FULL queue on
//             the exact boundary cycle (push+pop together, count stays 2).
//   reject    a long frame plus three more offers: the third hits a full queue
//             without a pop and must be rejected (dq_reject_cnt), nothing lost.
//   empty     no descriptors: status packets must still be emitted.
// =============================================================================
module tb_b10_export;
    parameter integer STATUS_DIV = 0;
    parameter integer W          = 8;
    parameter integer H          = 2;
    parameter integer NFRAMES    = 14;
    parameter integer EXPECT_OLD = 0;

    localparam integer NMAX = 24;
    localparam integer STS_LEN = 177;

    reg clk = 0, rst_n = 0, desc_push = 0;
    always #5 clk = ~clk;

    reg  [31:0] frame_id = 1;
    reg  [31:0] store_id = 1;
    wire        cmp_open, cmp_close, rd_take, dbg_valid, txd, busy;
    wire [7:0]  dbg_byte;
    wire [31:0] exported, nbytes, errors;

    // ------------------------------------------------------------- descriptor set
    reg [31:0] d_fid  [0:NMAX-1];
    reg [31:0] d_slen [0:NMAX-1];
    reg [31:0] d_rcrc [0:NMAX-1];
    reg [31:0] d_xcrc [0:NMAX-1];
    reg [31:0] d_scrc [0:NMAX-1];
    integer    push_idx;
    integer    offer_idx;
    integer    i;

    initial begin
        for (i = 0; i < NMAX; i = i + 1) begin
            d_fid [i] = 32'd1000 + i;
            d_slen[i] = 32'd1 + (i % 4);
            d_rcrc[i] = 32'h1111_0000 + i;
            d_xcrc[i] = 32'h2222_0000 + i;
            d_scrc[i] = 32'h3333_0000 + i;
        end
        offer_idx = 0;
    end

    // descriptor currently presented on the d_frame_* / d_*_crc ports
    integer sel;
    always @(*) sel = (offer_idx < NMAX) ? offer_idx : NMAX - 1;

    // ------------------------------------------------------------ observation
    integer  observed_bytes = 0;
    integer  frames_done = 0;
    integer  sts_done = 0;
    integer  samecycle_cnt = 0;
    integer  bad_bytes = 0;
    integer  parse_state = 0;       // 0=boundary 1=header 2=payload 3=status
    integer  fpos = 0;
    reg [7:0] sts_buf [0:STS_LEN-1];
    integer  spos = 0;
    reg [31:0] hdr_crc_r;
    reg [7:0]  exp_hdr [0:43];
    reg [31:0] hw_sel;
    integer    k;
    integer    status_pkts_xor_bad = 0;

    function [31:0] crc32b;
        input [31:0] c;
        input [7:0]  d;
        integer q;
        reg [31:0] x;
        begin
            x = c ^ {24'd0, d};
            for (q = 0; q < 8; q = q + 1)
                x = x[0] ? ((x >> 1) ^ 32'hEDB88320) : (x >> 1);
            crc32b = x;
        end
    endfunction

    task build_hdr(input integer idx);
        reg [31:0] hw0, hw1, hw2, hw3, hw4, hw5, hw6, hw7, hw8, hw9, hw10;
        reg [31:0] c;
        integer m;
        begin
            hw0  = 32'h31553141;
            hw1  = {8'h00, 8'd44, 6'd0, 2'd0, 8'h01};
            hw2  = d_fid[idx];
            hw3  = {H[15:0], W[15:0]};
            hw4  = 32'd20;
            hw5  = 32'd20;
            hw6  = d_slen[idx];
            hw7  = d_rcrc[idx];
            hw8  = d_xcrc[idx];
            hw9  = d_scrc[idx];
            c    = 32'hFFFFFFFF;
            for (m = 0; m < 10; m = m + 1) begin
                case (m)
                    0: hw_sel = hw0; 1: hw_sel = hw1; 2: hw_sel = hw2;
                    3: hw_sel = hw3; 4: hw_sel = hw4; 5: hw_sel = hw5;
                    6: hw_sel = hw6; 7: hw_sel = hw7; 8: hw_sel = hw8;
                    default: hw_sel = hw9;
                endcase
                exp_hdr[m*4+0] = hw_sel[7:0];
                exp_hdr[m*4+1] = hw_sel[15:8];
                exp_hdr[m*4+2] = hw_sel[23:16];
                exp_hdr[m*4+3] = hw_sel[31:24];
                c = crc32b(c, hw_sel[7:0]);
                c = crc32b(c, hw_sel[15:8]);
                c = crc32b(c, hw_sel[23:16]);
                c = crc32b(c, hw_sel[31:24]);
            end
            hw10 = ~c;
            exp_hdr[40] = hw10[7:0];  exp_hdr[41] = hw10[15:8];
            exp_hdr[42] = hw10[23:16]; exp_hdr[43] = hw10[31:24];
        end
    endtask

    task fail(input [1023:0] msg);
        begin
            bad_bytes = bad_bytes + 1;
            $display("B10_EXPORT_FAIL %0s (byte#%0d state=%0d)", msg, observed_bytes, parse_state);
        end
    endtask

    // ------------------------------------------------------------- byte parser
    always @(posedge clk) begin
        if (rst_n && dbg_valid) begin
            observed_bytes = observed_bytes + 1;
            case (parse_state)
                0: begin
                    if (dbg_byte == 8'h41) begin
                        if (frames_done >= NFRAMES) begin
                            fail("unexpected frame start");
                        end else begin
                            build_hdr(frames_done);
                            if (dbg_byte !== exp_hdr[0]) fail("frame magic byte0");
                            hdr_crc_r = crc32b(32'hFFFFFFFF, dbg_byte);
                            fpos = 1;
                            parse_state = 1;
                        end
                    end else if (dbg_byte == 8'hA5) begin
                        sts_buf[0] = dbg_byte; spos = 1; parse_state = 3;
                    end else begin
                        fail("unexpected byte at frame boundary");
                    end
                end
                1: begin
                    if (dbg_byte !== exp_hdr[fpos]) begin
                        $display("B10_HDR_MISMATCH frame=%0d pos=%0d exp=%02x got=%02x",
                                 frames_done, fpos, exp_hdr[fpos], dbg_byte);
                        fail("frame header byte");
                    end
                    if (fpos < 40) hdr_crc_r = crc32b(hdr_crc_r, dbg_byte);
                    if (fpos == 43) begin
                        if (~hdr_crc_r !== {exp_hdr[43], exp_hdr[42], exp_hdr[41], exp_hdr[40]})
                            fail("frame header CRC");
                        fpos = 0;
                        parse_state = (d_slen[frames_done] == 0) ? 0 : 2;
                        if (d_slen[frames_done] == 0) frames_done = frames_done + 1;
                    end else begin
                        fpos = fpos + 1;
                    end
                end
                2: begin
                    if (dbg_byte !== 8'h42) fail("payload byte");
                    fpos = fpos + 1;
                    if (fpos >= d_slen[frames_done]) begin
                        frames_done = frames_done + 1;
                        fpos = 0;
                        parse_state = 0;
                    end
                end
                3: begin
                    sts_buf[spos] = dbg_byte; spos = spos + 1;
                    if (spos == STS_LEN) begin
                        if (sts_buf[0] !== 8'hA5 || sts_buf[1] !== 8'h5A ||
                            sts_buf[2] !== 8'd177 || sts_buf[3] !== 8'd3) begin
                            $display("B10_STS_HDR_BAD %02x %02x %02x %02x",
                                     sts_buf[0], sts_buf[1], sts_buf[2], sts_buf[3]);
                            fail("status header");
                        end else begin
                            reg [7:0] x;
                            x = 8'd0;
                            for (k = 0; k < STS_LEN-1; k = k + 1) x = x ^ sts_buf[k];
                            if (x !== sts_buf[STS_LEN-1]) begin
                                $display("B10_STS_XOR_BAD exp=%02x got=%02x", x, sts_buf[STS_LEN-1]);
                                status_pkts_xor_bad = status_pkts_xor_bad + 1;
                                fail("status xor");
                            end
                        end
                        sts_done = sts_done + 1;
                        spos = 0;
                        parse_state = 0;
                    end
                end
                default: parse_state = 0;
            endcase
        end
    end

    // ----------------------------------------------------------- same-cycle pop
    always @(posedge clk) begin
        if (rst_n && dut.dq_push_ok && dut.dq_pop_ok) samecycle_cnt = samecycle_cnt + 1;
        if (rst_n && dut.dq_cnt > 2'd2) fail("dq_cnt > 2");
    end

    // ------------------------------------------------------------------- DUT
    a1_uart_export #(.W(W), .H(H), .UART_DIV(1), .HB_DIV(0), .STS_DIV(STATUS_DIV)) dut (
        .clk(clk), .uart_clk(clk), .rst_n(rst_n), .desc_push(desc_push),
        .d_frame_id(d_fid[sel]), .d_raw_len(32'd20), .d_xform_len(32'd20),
        .d_stream_len(d_slen[sel]), .d_raw_crc(d_rcrc[sel]),
        .d_xform_crc(d_xcrc[sel]), .d_stream_crc(d_scrc[sel]), .d_profile(2'd0),
        .cmp_open(cmp_open), .cmp_open_ready(1'b1),
        .cmp_len(d_slen[(frames_done < NMAX) ? frames_done : NMAX-1]),
        .cmp_id(d_fid[(frames_done < NMAX) ? frames_done : NMAX-1]),
        .cmp_close(cmp_close), .rd_data({8{32'h4242_4242}}),
        .rd_valid(1'b1), .rd_take(rd_take), .dbg_byte(dbg_byte),
        .dbg_byte_valid(dbg_valid), .uart_txd(txd), .st_exported(exported),
        .st_bytes(nbytes), .st_err(errors), .st_busy(busy),
        .sts_cap_frames(32'd0), .sts_raw_pub(32'd0), .sts_enc_frames(32'd0),
        .sts_exported(exported), .sts_raw_drop(32'd0), .sts_cmp_drop(32'd0),
        .sts_errors(errors), .sts_read_words(32'd0),
        .sts_cam(480'd0), .sts_raw(640'd0)
    );

    // --------------------------------------------------------------- producer
    reg [8*16-1:0] case_name;
    integer  reject_done;
    integer  boundary_seen;
    integer  arb_req;
    wire boundary = (dut.estate == 2'd0) && (dut.sstate == 2'd0) &&
                    dut.tx_ready && !dut.tx_valid_r;

    always @(negedge clk) begin
        desc_push <= 1'b0;
        if (rst_n) begin
            if (case_name == "arb") begin
                if (arb_req != 0) begin
                    offer_idx = (arb_req == 1) ? 0 : 1;
                    push_idx  = push_idx + 1;
                    arb_req   = 0;
                    desc_push <= 1'b1;
                end
            end else if (case_name == "wrap") begin
                if (push_idx < NFRAMES && dut.dq_cnt < 2'd2) begin
                    offer_idx = push_idx;
                    push_idx = push_idx + 1;
                    desc_push <= 1'b1;
                end
            end else if (case_name == "samecycle") begin
                // Push when there is room, and also exactly on a full-queue
                // pop.  push_idx only advances when the DUT really accepted
                // (see the posedge block below), so a rejected full-queue offer
                // is retried instead of silently shifting the expected order.
                if (push_idx < NFRAMES &&
                    (dut.dq_cnt < 2'd2 || (dut.dq_cnt == 2'd2 && boundary))) begin
                    offer_idx = push_idx;
                    desc_push <= 1'b1;
                end
            end else if (case_name == "reject") begin
                if (push_idx == 0) begin
                    offer_idx = 0;
                    push_idx = 1;
                    desc_push <= 1'b1;
                end else if (push_idx < 3 && dut.dq_cnt < 2'd2) begin
                    offer_idx = push_idx;
                    push_idx = push_idx + 1;
                    desc_push <= 1'b1;
                end else if (push_idx == 3 && dut.dq_cnt == 2'd2 && !boundary &&
                             reject_done == 0) begin
                    // full queue, no pop this cycle -> must be rejected
                    offer_idx = 3;
                    reject_done = 1;
                    push_idx = 4;
                    desc_push <= 1'b1;
                end
            end
        end
    end

    // accepted-offer tracking (samecycle retries a rejected full-queue push)
    always @(posedge clk) begin
        if (rst_n && (case_name == "samecycle") && desc_push && dut.dq_push_ok)
            push_idx = push_idx + 1;
    end

    // ----------------------------------------------------------------- control
    integer n;
    initial begin
        case_name = "arb";
        if (!$value$plusargs("CASE=%s", case_name)) case_name = "arb";
        reject_done = 0; push_idx = 0; boundary_seen = 0; arb_req = 0;
        repeat (5) @(negedge clk);
        rst_n = 1;
        repeat (5) @(negedge clk);
    end

    initial begin
        wait (rst_n);
        if (case_name == "arb") begin
            // frame 1 then, while it is on the wire, frame 2 plus a status tick
            @(posedge clk); arb_req = 1;
            wait (dut.estate == 2'd2 && dut.hdr_idx >= 8'd4);
            @(posedge clk); arb_req = 2;
            repeat (2000) @(negedge clk);
            if (EXPECT_OLD) begin
                if (exported === 1 && dut.estate === 0 && dut.sstate === 0 &&
                    dut.sts_want === 1 && dut.dq_cnt === 1 &&
                    observed_bytes == 45) begin
                    $display("B10_ARB_OLD_REPRO exported=%0d want=%0d cnt=%0d bytes=%0d",
                             exported, dut.sts_want, dut.dq_cnt, observed_bytes);
                    repeat (3000) @(negedge clk);
                    if (observed_bytes == 45)
                        $display("B10_ARB_OLD_CONFIRMED unchanged_b9_status_queue_deadlock bytes=%0d",
                                 observed_bytes);
                    else
                        $display("B10_ARB_OLD_UNEXPECTED extra_bytes=%0d", observed_bytes);
                    $display("B10_ARB_RESULT old_repro=1");
                    $finish;
                end else begin
                    $display("B10_ARB_OLD_NOT_REPRODUCED exported=%0d estate=%0d sstate=%0d want=%0d cnt=%0d bytes=%0d",
                             exported, dut.estate, dut.sstate, dut.sts_want, dut.dq_cnt, observed_bytes);
                    $display("B10_ARB_RESULT old_repro=0");
                    $finish;
                end
            end
        end
        // generic completion: all frames exported and the pipe is idle
        if (case_name == "empty") begin
            wait (sts_done >= 2);
            repeat (20) @(negedge clk);
            $display("B10_EXPORT_DONE case=%0s frames=%0d exported=%0d status=%0d bytes=%0d errors=%0d",
                     case_name, frames_done, exported, sts_done, observed_bytes, errors);
            $display("B10_EXPORT_RESULT pass=%0d",
                     (bad_bytes == 0) && (frames_done == 0) && (sts_done >= 2) &&
                     (status_pkts_xor_bad == 0) && (dut.b10_assert_fails == 0));
            $finish;
        end
        wait (frames_done >= NFRAMES &&
              dut.dq_cnt == 2'd0 && dut.estate == 2'd0 && dut.sstate == 2'd0 &&
              dut.tx_ready && !dut.tx_valid_r);
        repeat (40) @(negedge clk);
        $display("B10_EXPORT_DONE case=%0s frames=%0d exported=%0d status=%0d bytes=%0d errors=%0d reject=%0d samecycle=%0d asserts=%0d",
                 case_name, frames_done, exported, sts_done, observed_bytes, errors,
                 dut.dq_reject_cnt, samecycle_cnt, dut.b10_assert_fails);
        if (bad_bytes != 0)                 $display("B10_EXPORT_BAD bad_bytes=%0d", bad_bytes);
        if (frames_done != NFRAMES)         $display("B10_EXPORT_BAD frames=%0d want=%0d", frames_done, NFRAMES);
        if (exported != NFRAMES)            $display("B10_EXPORT_BAD exported=%0d want=%0d", exported, NFRAMES);
        if (errors != 0)                    $display("B10_EXPORT_BAD errors=%0d", errors);
        if (dut.b10_assert_fails != 0)      $display("B10_EXPORT_BAD internal_asserts=%0d", dut.b10_assert_fails);
        if (case_name == "samecycle" && samecycle_cnt == 0)
            $display("B10_EXPORT_BAD no same-cycle push/pop observed");
        if (case_name == "wrap" && sts_done == 0)
            $display("B10_EXPORT_BAD no status packet between frames");
        if (case_name == "reject" && dut.dq_reject_cnt != 1)
            $display("B10_EXPORT_BAD reject_cnt=%0d want=1", dut.dq_reject_cnt);
        $display("B10_EXPORT_RESULT pass=%0d",
                 (bad_bytes == 0) && (frames_done == NFRAMES) && (exported == NFRAMES) &&
                 (errors == 0) && (dut.b10_assert_fails == 0) &&
                 !((case_name == "samecycle") && (samecycle_cnt == 0)) &&
                 !((case_name == "wrap") && (sts_done == 0)) &&
                 !((case_name == "reject") && (dut.dq_reject_cnt != 1)));
        $finish;
    end

    initial begin
        #4000000;
        $display("B10_EXPORT_TIMEOUT case=%0s frames=%0d exported=%0d estate=%0d sstate=%0d cnt=%0d",
                 case_name, frames_done, exported, dut.estate, dut.sstate, dut.dq_cnt);
        $display("B10_EXPORT_RESULT pass=0");
        $finish;
    end
endmodule
