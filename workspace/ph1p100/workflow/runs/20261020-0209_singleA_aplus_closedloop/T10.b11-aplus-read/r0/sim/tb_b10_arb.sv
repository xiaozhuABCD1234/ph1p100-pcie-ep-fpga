`timescale 1ns/1ps
// =============================================================================
// tb_b10_arb.sv -- T10.b10 B9-01 old-vs-new control (single TB, two libraries).
//
// Same stimulus as the frozen b9 reproduction: two descriptors through the
// normal ports, the second one queued while frame 1 is on the wire, and the
// 1 Hz status tick due during frame 1.
//
//   +EXP=old : the unchanged b9 exporter must deadlock (exported=1, want=1,
//              dq_cnt=1, 45 bytes, UART idle and no further byte).
//   +EXP=new : the fixed exporter must send the status packet at the frame
//              boundary and then export frame 2 (45 + 177 + 45 = 267 bytes,
//              status magic at offset 45, frame-2 magic at offset 222).
//
// The TB only reads ports and the state names that exist in BOTH versions
// (estate/sstate/sts_want/dq_cnt/uart_busy), so one source compiles against
// either RTL.
// =============================================================================
module tb_b10_arb;
    parameter integer STATUS_DIV = 64;
    parameter integer EXPECT_OLD = 0;
    parameter integer FRAME_BYTES = 1;

    reg clk = 0, rst_n = 0, desc_push = 0;
    always #5 clk = ~clk;
    reg [31:0] frame_id = 1;
    reg [31:0] store_id = 1;
    wire cmp_open, cmp_close, rd_take, dbg_valid, txd, busy;
    wire [7:0] dbg_byte;
    wire [31:0] exported, nbytes, errors;

    integer observed_bytes = 0;
    integer baseline_bytes = 0;
    reg [7:0] cap [0:4095];
    integer cap_n = 0;
    integer both_grant = 0;
    reg e_prev = 0, s_prev = 0;
    integer i, x;
    integer off1, off2;
    reg [7:0] xacc;

    always @(posedge clk) begin
        if (rst_n && dbg_valid) begin
            observed_bytes = observed_bytes + 1;
            if (cap_n < 4096) begin cap[cap_n] = dbg_byte; cap_n = cap_n + 1; end
        end
        if (rst_n && cmp_close) store_id <= store_id + 1;
        // count cycles where a frame dequeue and a status start happen together
        if (rst_n) begin
            if ((dut.estate == 2'd1) && (e_prev == 1'b0) &&
                (dut.sstate == 2'd1) && (s_prev == 1'b0)) both_grant = both_grant + 1;
            e_prev = (dut.estate != 2'd0);
            s_prev = (dut.sstate != 2'd0);
        end
    end

    a1_uart_export #(.W(8), .H(2), .UART_DIV(1), .HB_DIV(0),
                     .STS_DIV(STATUS_DIV)) dut (
        .clk(clk), .uart_clk(clk), .rst_n(rst_n), .desc_push(desc_push),
        .d_frame_id(frame_id), .d_raw_len(32'd20), .d_xform_len(32'd20),
        .d_stream_len(FRAME_BYTES), .d_raw_crc(32'd0), .d_xform_crc(32'd0),
        .d_stream_crc(32'd0), .d_profile(2'd0),
        .cmp_open(cmp_open), .cmp_open_ready(1'b1), .cmp_len(FRAME_BYTES),
        .cmp_id(store_id), .cmp_close(cmp_close), .rd_data(256'h42),
        .rd_valid(1'b1), .rd_take(rd_take), .dbg_byte(dbg_byte),
        .dbg_byte_valid(dbg_valid), .uart_txd(txd), .st_exported(exported),
        .st_bytes(nbytes), .st_err(errors), .st_busy(busy),
        .sts_cap_frames(32'd0), .sts_raw_pub(32'd0), .sts_enc_frames(32'd0),
        .sts_exported(exported), .sts_raw_drop(32'd0), .sts_cmp_drop(32'd0),
        .sts_errors(errors), .sts_read_words(32'd0),
        .sts_cam(480'd0), .sts_raw(640'd0)
    );

    initial begin
        repeat (5) @(negedge clk);
        rst_n = 1;
        repeat (5) @(negedge clk);
        desc_push = 1;
        @(negedge clk); desc_push = 0;
        wait (dut.estate == 2'd2 && dut.hdr_idx >= 4);
        @(negedge clk); frame_id = 2; desc_push = 1;
        @(negedge clk); desc_push = 0;
        repeat (FRAME_BYTES*12 + 6000) @(negedge clk);
        baseline_bytes = observed_bytes;
        repeat (FRAME_BYTES*14 + 6000) @(negedge clk);
        $display("OBS sts_div=%0d exp_old=%0d exported=%0d errors=%0d estate=%0d sstate=%0d sts_want=%0d dq_cnt=%0d tx_busy=%0d bytes=%0d later_bytes=%0d both=%0d",
            STATUS_DIV, EXPECT_OLD, exported, errors, dut.estate, dut.sstate, dut.sts_want,
            dut.dq_cnt, dut.uart_busy, baseline_bytes, observed_bytes, both_grant);
        if (EXPECT_OLD) begin
            if (exported === 1 && dut.estate === 0 && dut.sstate === 0 &&
                dut.sts_want === 1 && dut.dq_cnt === 1 && both_grant === 0 &&
                observed_bytes == baseline_bytes && observed_bytes == (44 + FRAME_BYTES))
                $display("B10_ARB_RESULT old_repro=1");
            else
                $display("B10_ARB_RESULT old_repro=0");
        end else begin
            off1 = 44 + FRAME_BYTES;
            off2 = off1 + 177;
            xacc = 8'd0;
            for (i = off1; i < off1 + 176 && i < cap_n; i = i + 1) xacc = xacc ^ cap[i];
            if (exported === 2 && errors === 0 && both_grant === 0 &&
                observed_bytes >= (2*(44+FRAME_BYTES) + 177) &&
                cap[off1] == 8'hA5 && cap[off1+1] == 8'h5A &&
                cap[off1+2] == 8'd177 && cap[off1+3] == 8'd3 &&
                xacc === cap[off1+176] &&
                cap[off2] == 8'h41 && cap[off2+1] == 8'h31 && cap[off2+2] == 8'h55 && cap[off2+3] == 8'h31)
                $display("B10_ARB_RESULT new_pass=1 status_at=%0d frame2_at=%0d bytes=%0d", off1, off2, observed_bytes);
            else begin
                $display("B10_ARB_NEW_BAD exported=%0d errors=%0d bytes=%0d both=%0d sts=%02x%02x%02x%02x xor=%02x/%02x f2=%02x%02x%02x%02x",
                    exported, errors, observed_bytes, both_grant,
                    cap[off1], cap[off1+1], cap[off1+2], cap[off1+3], xacc, cap[off1+176],
                    cap[off2], cap[off2+1], cap[off2+2], cap[off2+3]);
                $display("B10_ARB_RESULT new_pass=0");
            end
        end
        $finish;
    end

    initial begin
        #2000000;
        $display("B10_ARB_TIMEOUT sts_div=%0d exported=%0d bytes=%0d", STATUS_DIV, exported, observed_bytes);
        $display("B10_ARB_RESULT timeout=1");
        $finish;
    end
endmodule
