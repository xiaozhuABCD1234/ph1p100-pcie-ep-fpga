`timescale 1ns/1ps
module tb_dual_channel_capture_scheduler;
    reg clk, rst_n;
    reg a_desc_valid, a_desc_camera_id, a_desc_slot_id;
    reg [31:0] a_desc_epoch, a_desc_session, a_desc_capture_seq;
    reg b_desc_valid, b_desc_camera_id, b_desc_slot_id;
    reg [31:0] b_desc_epoch, b_desc_session, b_desc_capture_seq;
    wire a_desc_ready, b_desc_ready;
    wire o_valid; reg o_ready;
    wire o_camera_id, o_slot_id;
    wire [31:0] o_epoch, o_session, o_capture_seq;
    reg rel_valid, rel_camera_id, rel_slot_id;
    reg [31:0] rel_epoch, rel_session, rel_capture_seq;
    reg [2:0] rel_status;
    wire rel_ready;
    reg a_enable, b_priority;

    dual_channel_capture_scheduler dut (
        .clk(clk), .rst_n(rst_n),
        .a_desc_valid(a_desc_valid), .a_desc_ready(a_desc_ready),
        .a_desc_camera_id(a_desc_camera_id), .a_desc_slot_id(a_desc_slot_id),
        .a_desc_epoch(a_desc_epoch), .a_desc_session(a_desc_session), .a_desc_capture_seq(a_desc_capture_seq),
        .b_desc_valid(b_desc_valid), .b_desc_ready(b_desc_ready),
        .b_desc_camera_id(b_desc_camera_id), .b_desc_slot_id(b_desc_slot_id),
        .b_desc_epoch(b_desc_epoch), .b_desc_session(b_desc_session), .b_desc_capture_seq(b_desc_capture_seq),
        .o_valid(o_valid), .o_ready(o_ready),
        .o_camera_id(o_camera_id), .o_slot_id(o_slot_id),
        .o_epoch(o_epoch), .o_session(o_session), .o_capture_seq(o_capture_seq),
        .rel_valid(rel_valid), .rel_ready(rel_ready),
        .rel_camera_id(rel_camera_id), .rel_slot_id(rel_slot_id),
        .rel_epoch(rel_epoch), .rel_session(rel_session), .rel_capture_seq(rel_capture_seq),
        .rel_status(rel_status),
        .a_enable(a_enable), .b_priority(b_priority),
        .st_accepted(), .st_completed(), .st_failed(), .st_rejected(),
        .st_busy(), .st_a_busy(), .st_b_busy(), .st_last_camera()
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task reset;
    begin
        rst_n = 0;
        a_desc_valid = 0; b_desc_valid = 0;
        a_desc_camera_id = 0; b_desc_camera_id = 1;
        a_desc_slot_id = 0; b_desc_slot_id = 0;
        a_desc_epoch = 0; a_desc_session = 0; a_desc_capture_seq = 0;
        b_desc_epoch = 0; b_desc_session = 0; b_desc_capture_seq = 0;
        o_ready = 0;
        rel_valid = 0; rel_camera_id = 0; rel_slot_id = 0;
        rel_epoch = 0; rel_session = 0; rel_capture_seq = 0; rel_status = 0;
        a_enable = 1; b_priority = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
    end
    endtask

    integer errors = 0;
    initial begin
        reset();

        // Scenario 1: B-only
        b_desc_valid = 1; b_desc_camera_id = 1; b_desc_slot_id = 1;
        b_desc_epoch = 10; b_desc_session = 20; b_desc_capture_seq = 30;
        a_desc_valid = 0;
        // wait for accept
        wait (o_valid == 1);
        if (o_camera_id !== 1) begin $display("FAIL B-only camera_id"); errors=errors+1; end
        if (o_capture_seq !== 30) begin $display("FAIL B-only seq"); errors=errors+1; end
        b_desc_valid = 0;
        o_ready = 1; @(posedge clk); o_ready = 0;
        // release B
        rel_valid = 1; rel_camera_id = 1; rel_slot_id = 1;
        rel_epoch = 10; rel_session = 20; rel_capture_seq = 30; rel_status = 0;
        @(posedge clk); rel_valid = 0;
        repeat(2) @(posedge clk);

        b_priority = 1;
        // Scenario 2: A+B both, B first
        a_desc_valid = 1; a_desc_camera_id = 0; a_desc_slot_id = 0;
        a_desc_epoch = 11; a_desc_session = 21; a_desc_capture_seq = 31;
        b_desc_valid = 1; b_desc_camera_id = 1; b_desc_slot_id = 1;
        b_desc_epoch = 12; b_desc_session = 22; b_desc_capture_seq = 32;
        wait (o_valid == 1);
        if (o_camera_id !== 1) begin $display("FAIL tie first not B"); errors=errors+1; end
        b_desc_valid = 0;
        o_ready = 1; @(posedge clk); o_ready = 0;
        // release B
        rel_valid = 1; rel_camera_id = 1; rel_slot_id = 1;
        rel_epoch = 12; rel_session = 22; rel_capture_seq = 32; rel_status = 0;
        @(posedge clk); rel_valid = 0;
        // next should be A
        wait (o_valid == 1);
        if (o_camera_id !== 0) begin $display("FAIL second not A"); errors=errors+1; end
        a_desc_valid = 0;
        o_ready = 1; @(posedge clk); o_ready = 0;
        rel_valid = 1; rel_camera_id = 0; rel_slot_id = 0;
        rel_epoch = 11; rel_session = 21; rel_capture_seq = 31; rel_status = 0;
        @(posedge clk); rel_valid = 0;
        b_priority = 0;
        repeat(2) @(posedge clk);

        // Scenario 3: slot ownership (A twice without release)
        a_desc_valid = 1; a_desc_camera_id = 0; a_desc_slot_id = 0;
        a_desc_epoch = 13; a_desc_session = 23; a_desc_capture_seq = 33;
        wait (o_valid == 1);
        a_desc_valid = 0;
        o_ready = 1; @(posedge clk); o_ready = 0;
        // second A while busy, should not be accepted (ready 0)
        a_desc_valid = 1; a_desc_epoch = 14; a_desc_session = 24; a_desc_capture_seq = 34;
        repeat(3) @(posedge clk);
        if (o_valid == 1 && o_capture_seq == 34) begin $display("FAIL overwrite before release"); errors=errors+1; end
        a_desc_valid = 0;
        // release first
        rel_valid = 1; rel_camera_id = 0; rel_slot_id = 0;
        rel_epoch = 13; rel_session = 23; rel_capture_seq = 33; rel_status = 0;
        @(posedge clk); rel_valid = 0;
        repeat(2) @(posedge clk);

        // Scenario 4: A disabled
        a_enable = 0;
        a_desc_valid = 1; a_desc_camera_id = 0; a_desc_slot_id = 0;
        a_desc_epoch = 15; a_desc_session = 25; a_desc_capture_seq = 35;
        b_desc_valid = 1; b_desc_camera_id = 1; b_desc_slot_id = 1;
        b_desc_epoch = 16; b_desc_session = 26; b_desc_capture_seq = 36;
        wait (o_valid == 1);
        if (o_camera_id !== 1) begin $display("FAIL A disabled did not select B"); errors=errors+1; end
        b_desc_valid = 0; a_desc_valid = 0;
        o_ready = 1; @(posedge clk); o_ready = 0;
        rel_valid = 1; rel_camera_id = 1; rel_slot_id = 1;
        rel_epoch = 16; rel_session = 26; rel_capture_seq = 36; rel_status = 0;
        @(posedge clk); rel_valid = 0;
        a_enable = 1;
        repeat(2) @(posedge clk);

        if (errors == 0) $display("TB_DUAL_CHANNEL_CAPTURE_SCHEDULER PASS");
        else $display("TB_DUAL_CHANNEL_CAPTURE_SCHEDULER FAIL errors=%0d", errors);
        $finish;
    end

    // timeout watchdog
    initial begin
        #100000;
        $display("TIMEOUT");
        $finish;
    end
endmodule