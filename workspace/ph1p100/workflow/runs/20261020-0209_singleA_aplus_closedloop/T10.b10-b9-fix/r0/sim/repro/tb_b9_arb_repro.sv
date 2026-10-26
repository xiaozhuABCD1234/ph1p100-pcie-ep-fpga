`timescale 1ns/1ps
// Reproduce the unchanged b9 exporter arbitration failure through normal inputs.
module tb_b9_arb_repro;
    parameter integer STATUS_DIV = 64;
    reg clk = 0, rst_n = 0, desc_push = 0;
    always #5 clk = ~clk;
    reg [31:0] frame_id = 1;
    reg [31:0] store_id = 1;
    wire cmp_open, cmp_close, rd_take, dbg_valid, txd, busy;
    wire [7:0] dbg_byte;
    wire [31:0] exported, nbytes, errors;
    integer observed_bytes = 0, baseline_bytes = 0;
    always @(posedge clk) begin
        if (rst_n && dbg_valid) observed_bytes = observed_bytes + 1;
        if (rst_n && cmp_close) store_id <= store_id + 1;
    end
    a1_uart_export #(.W(8), .H(2), .UART_DIV(1), .HB_DIV(0),
                     .STS_DIV(STATUS_DIV)) dut (
        .clk(clk), .uart_clk(clk), .rst_n(rst_n), .desc_push(desc_push),
        .d_frame_id(frame_id), .d_raw_len(32'd20), .d_xform_len(32'd20),
        .d_stream_len(32'd1), .d_raw_crc(32'd0), .d_xform_crc(32'd0),
        .d_stream_crc(32'd0), .d_profile(2'd0),
        .cmp_open(cmp_open), .cmp_open_ready(1'b1), .cmp_len(32'd1),
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
        wait (dut.estate == 2 && dut.hdr_idx >= 4);
        @(negedge clk); frame_id = 2; desc_push = 1;
        @(negedge clk); desc_push = 0;
        repeat (2000) @(negedge clk);
        baseline_bytes = observed_bytes;
        repeat (3000) @(negedge clk);
        $display("OBS sts_div=%0d exported=%0d errors=%0d estate=%0d sstate=%0d sts_want=%0d dq_cnt=%0d tx_busy=%0d bytes=%0d later_bytes=%0d",
            STATUS_DIV, exported, errors, dut.estate, dut.sstate, dut.sts_want,
            dut.dq_cnt, dut.uart_busy, baseline_bytes, observed_bytes);
        if (STATUS_DIV != 0) begin
            if (exported === 1 && dut.estate === 0 && dut.sstate === 0 &&
                dut.sts_want === 1 && dut.dq_cnt === 1 &&
                observed_bytes == baseline_bytes && observed_bytes == 45)
                $display("REPRO_CONFIRMED unchanged_b9_status_queue_deadlock");
            else $fatal(1, "Expected deadlock not reproduced");
        end else begin
            if (exported === 2 && errors === 0 && observed_bytes == 90)
                $display("CONTROL_CONFIRMED same_two_frames_complete_without_status");
            else $fatal(1, "No-status control failed");
        end
        $finish;
    end
    initial begin
        #200000; $fatal(1, "Testbench watchdog expired");
    end
endmodule
