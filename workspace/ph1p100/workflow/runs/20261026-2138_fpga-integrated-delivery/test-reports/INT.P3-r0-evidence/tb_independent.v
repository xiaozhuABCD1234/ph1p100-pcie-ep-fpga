`timescale 1ns/1ps
module tb_independent;
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
    wire [15:0] st_accepted, st_completed, st_failed, st_rejected;
    wire st_busy, st_a_busy, st_b_busy, st_last_camera;

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
        .st_accepted(st_accepted), .st_completed(st_completed), .st_failed(st_failed), .st_rejected(st_rejected),
        .st_busy(st_busy), .st_a_busy(st_a_busy), .st_b_busy(st_b_busy), .st_last_camera(st_last_camera)
    );

    initial clk=0; always #5 clk=~clk;

    task reset;
    begin
        rst_n=0;
        a_desc_valid=0; b_desc_valid=0;
        a_desc_camera_id=0; b_desc_camera_id=1;
        a_desc_slot_id=0; b_desc_slot_id=0;
        a_desc_epoch=0; a_desc_session=0; a_desc_capture_seq=0;
        b_desc_epoch=0; b_desc_session=0; b_desc_capture_seq=0;
        o_ready=0;
        rel_valid=0; rel_camera_id=0; rel_slot_id=0;
        rel_epoch=0; rel_session=0; rel_capture_seq=0; rel_status=0;
        a_enable=1; b_priority=0;
        repeat(3) @(posedge clk);
        rst_n=1;
        @(posedge clk);
    end
    endtask

    integer errors=0;
    initial begin
        reset();

        // T1: identity mismatch release keeps busy and increments rejected
        a_desc_valid=1; a_desc_camera_id=0; a_desc_slot_id=0;
        a_desc_epoch=100; a_desc_session=200; a_desc_capture_seq=300;
        wait (o_valid==1);
        a_desc_valid=0;
        o_ready=1; @(posedge clk); o_ready=0;
        // mismatched epoch release
        rel_valid=1; rel_camera_id=0; rel_slot_id=0;
        rel_epoch=999; rel_session=200; rel_capture_seq=300; rel_status=0;
        @(posedge clk); rel_valid=0;
        repeat(2) @(posedge clk);
        if (st_a_busy !== 1) begin $display("FAIL T1 busy cleared on mismatch"); errors = errors + 1; end
        if (st_rejected !== 1) begin $display("FAIL T1 rejected not incremented got %0d", st_rejected); errors = errors + 1; end
        // correct release
        rel_valid=1; rel_camera_id=0; rel_slot_id=0;
        rel_epoch=100; rel_session=200; rel_capture_seq=300; rel_status=0;
        @(posedge clk); rel_valid=0;
        repeat(2) @(posedge clk);
        if (st_a_busy !== 0) begin $display("FAIL T1 correct release did not clear"); errors = errors + 1; end
        if (st_completed !== 1) begin $display("FAIL T1 completed not incremented"); errors = errors + 1; end

        // T2: failed release increments st_failed
        a_desc_valid=1; a_desc_camera_id=0; a_desc_slot_id=0;
        a_desc_epoch=101; a_desc_session=201; a_desc_capture_seq=301;
        wait (o_valid==1);
        a_desc_valid=0;
        o_ready=1; @(posedge clk); o_ready=0;
        rel_valid=1; rel_camera_id=0; rel_slot_id=0;
        rel_epoch=101; rel_session=201; rel_capture_seq=301; rel_status=3'd1;
        @(posedge clk); rel_valid=0;
        repeat(2) @(posedge clk);
        if (st_failed !== 1) begin $display("FAIL T2 st_failed not incremented got %0d", st_failed); errors = errors + 1; end
        if (st_a_busy !== 0) begin $display("FAIL T2 busy not cleared on failed release"); errors = errors + 1; end

        // T3: A disabled selects B
        a_enable=0;
        a_desc_valid=1; a_desc_camera_id=0; a_desc_slot_id=0;
        a_desc_epoch=102; a_desc_session=202; a_desc_capture_seq=302;
        b_desc_valid=1; b_desc_camera_id=1; b_desc_slot_id=1;
        b_desc_epoch=103; b_desc_session=203; b_desc_capture_seq=303;
        wait (o_valid==1);
        if (o_camera_id !== 1) begin $display("FAIL T3 A disabled did not select B"); errors = errors + 1; end
        b_desc_valid=0; a_desc_valid=0;
        o_ready=1; @(posedge clk); o_ready=0;
        rel_valid=1; rel_camera_id=1; rel_slot_id=1;
        rel_epoch=103; rel_session=203; rel_capture_seq=303; rel_status=0;
        @(posedge clk); rel_valid=0;
        a_enable=1;
        repeat(2) @(posedge clk);

        // T4: backpressure holds output and blocks new accept
        a_desc_valid=1; a_desc_camera_id=0; a_desc_slot_id=0;
        a_desc_epoch=104; a_desc_session=204; a_desc_capture_seq=304;
        wait (o_valid==1);
        // do not ready; attempt B descriptor while A inflight
        b_desc_valid=1; b_desc_camera_id=1; b_desc_slot_id=1;
        b_desc_epoch=105; b_desc_session=205; b_desc_capture_seq=305;
        repeat(3) @(posedge clk);
        if (o_capture_seq !== 304) begin $display("FAIL T4 output changed under backpressure"); errors = errors + 1; end
        b_desc_valid=0; a_desc_valid=0;
        o_ready=1; @(posedge clk); o_ready=0;
        rel_valid=1; rel_camera_id=0; rel_slot_id=0;
        rel_epoch=104; rel_session=204; rel_capture_seq=304; rel_status=0;
        @(posedge clk); rel_valid=0;
        repeat(2) @(posedge clk);

        // T5: invalid camera id not accepted
        a_desc_valid=1; a_desc_camera_id=1; // invalid for A
        a_desc_slot_id=0; a_desc_epoch=106; a_desc_session=206; a_desc_capture_seq=306;
        repeat(3) @(posedge clk);
        if (a_desc_ready !== 0) begin $display("FAIL T5 invalid A camera_id accepted"); errors = errors + 1; end
        a_desc_valid=0;
        repeat(2) @(posedge clk);

        // T6: B priority false alternates (last_sel logic)
        b_priority=0;
        a_desc_valid=1; a_desc_camera_id=0; a_desc_slot_id=0;
        a_desc_epoch=107; a_desc_session=207; a_desc_capture_seq=307;
        b_desc_valid=1; b_desc_camera_id=1; b_desc_slot_id=1;
        b_desc_epoch=108; b_desc_session=208; b_desc_capture_seq=308;
        wait (o_valid==1);
        if (o_camera_id !== 1) begin $display("FAIL T6 first not B got %0d", o_camera_id); errors = errors + 1; end
        b_desc_valid=0;
        o_ready=1; @(posedge clk); o_ready=0;
        // release B
        rel_valid=1; rel_camera_id=1; rel_slot_id=1;
        rel_epoch=108; rel_session=208; rel_capture_seq=308; rel_status=0;
        @(posedge clk); rel_valid=0;
        a_desc_valid=1; // keep A pending
        wait (o_valid==1);
        if (o_camera_id !== 0) begin $display("FAIL T6 second not A got %0d", o_camera_id); errors = errors + 1; end
        a_desc_valid=0;
        o_ready=1; @(posedge clk); o_ready=0;
        rel_valid=1; rel_camera_id=0; rel_slot_id=0;
        rel_epoch=107; rel_session=207; rel_capture_seq=307; rel_status=0;
        @(posedge clk); rel_valid=0;
        repeat(2) @(posedge clk);

        if (errors==0) $display("TB_INDEPENDENT PASS");
        else $display("TB_INDEPENDENT FAIL errors=%0d", errors);
        $finish;
    end

    initial begin #1000000; $display("TIMEOUT"); $finish; end
endmodule
