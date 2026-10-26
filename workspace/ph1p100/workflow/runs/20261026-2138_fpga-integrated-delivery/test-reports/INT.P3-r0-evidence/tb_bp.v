`timescale 1ns/1ps
module tb_bp;
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

    initial begin
        reset();
        // A accepted, output held (no ready)
        a_desc_valid=1; a_desc_camera_id=0; a_desc_slot_id=0;
        a_desc_epoch=1; a_desc_session=2; a_desc_capture_seq=3;
        wait (o_valid==1);
        a_desc_valid=0;
        // B arrives while output not consumed
        b_desc_valid=1; b_desc_camera_id=1; b_desc_slot_id=1;
        b_desc_epoch=4; b_desc_session=5; b_desc_capture_seq=6;
        repeat(5) @(posedge clk);
        $display("BP: o_capture_seq=%0d b_desc_ready=%0d a_desc_ready=%0d st_accepted=%0d", o_capture_seq, b_desc_ready, a_desc_ready, st_accepted);
        b_desc_valid=0;
        // consume
        o_ready=1; @(posedge clk); o_ready=0;
        repeat(2) @(posedge clk);
        // release whichever accepted
        if (st_a_busy) begin
            rel_valid=1; rel_camera_id=0; rel_slot_id=0; rel_epoch=1; rel_session=2; rel_capture_seq=3; rel_status=0;
            @(posedge clk); rel_valid=0;
        end
        if (st_b_busy) begin
            rel_valid=1; rel_camera_id=1; rel_slot_id=1; rel_epoch=4; rel_session=5; rel_capture_seq=6; rel_status=0;
            @(posedge clk); rel_valid=0;
        end
        repeat(2) @(posedge clk);
        $display("BP DONE accepted=%0d completed=%0d rejected=%0d a_busy=%0d b_busy=%0d", st_accepted, st_completed, st_rejected, st_a_busy, st_b_busy);
        $finish;
    end
    initial begin #100000; $display("TIMEOUT"); $finish; end
endmodule