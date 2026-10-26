`timescale 1ns/1ps
module tb_independent_edge;
    reg clk, rst_n;
    reg push_en;
    reg [31:0] cap_bytes, session_id;
    reg [63:0] dst_base, db_addr;
    reg [2:0] mps_code;
    reg link_up;
    reg slot_ready;
    reg [31:0] slot_id, slot_stream_len, slot_base_word;
    reg pcie_busy, pcie_held, pcie_done, pcie_err;
    reg [31:0] pcie_held_seq, pcie_held_sess;
    reg ack_pulse, cancel_pulse;
    reg [31:0] ack_seq, ack_session;
    reg [7:0] e_save;

    wire arm_pulse;
    wire [31:0] o_cap_bytes, o_session_id, o_frame_bytes, o_stream_len, o_slot_base_word;
    wire [63:0] o_dst_base, o_db_addr;
    wire o_src_sel, o_cam_sel;
    wire slot_release;
    wire [31:0] st_exported, st_bytes;
    wire [7:0] st_err;
    wire st_busy, st_held;

    aplus_pcie_egress_adapter #(.SLOT_BYTES(4096), .ALIGN_BYTES(4096)) dut (
        .clk(clk), .rst_n(rst_n),
        .push_en(push_en), .cap_bytes(cap_bytes), .session_id(session_id),
        .dst_base(dst_base), .db_addr(db_addr), .mps_code(mps_code), .link_up(link_up),
        .slot_ready(slot_ready), .slot_id(slot_id), .slot_stream_len(slot_stream_len),
        .slot_base_word(slot_base_word),
        .pcie_busy(pcie_busy), .pcie_held(pcie_held), .pcie_done(pcie_done),
        .pcie_err(pcie_err), .pcie_held_seq(pcie_held_seq), .pcie_held_sess(pcie_held_sess),
        .ack_pulse(ack_pulse), .ack_seq(ack_seq), .ack_session(ack_session),
        .cancel_pulse(cancel_pulse),
        .arm_pulse(arm_pulse), .o_cap_bytes(o_cap_bytes), .o_session_id(o_session_id),
        .o_dst_base(o_dst_base), .o_db_addr(o_db_addr), .o_frame_bytes(o_frame_bytes),
        .o_stream_len(o_stream_len), .o_slot_base_word(o_slot_base_word),
        .o_src_sel(o_src_sel), .o_cam_sel(o_cam_sel), .slot_release(slot_release),
        .st_exported(st_exported), .st_bytes(st_bytes), .st_err(st_err),
        .st_busy(st_busy), .st_held(st_held)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer errors = 0;

    initial begin
        rst_n = 0; push_en = 0; cap_bytes = 0; session_id = 0;
        dst_base = 0; db_addr = 0; mps_code = 0; link_up = 0;
        slot_ready = 0; slot_id = 0; slot_stream_len = 0; slot_base_word = 0;
        pcie_busy = 0; pcie_held = 0; pcie_done = 0; pcie_err = 0;
        pcie_held_seq = 0; pcie_held_sess = 0;
        ack_pulse = 0; cancel_pulse = 0; ack_seq = 0; ack_session = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;
        push_en = 1; cap_bytes = 32'd8192; session_id = 32'd7;
        dst_base = 64'd128; db_addr = 64'd2596896; mps_code = 3'd3; link_up = 1;
        @(posedge clk); #1;

        // invalid: push_en=0
        push_en = 0; slot_stream_len = 32'd1000; slot_base_word=32'd256; slot_id=1;
        e_save=st_err; slot_ready=1; @(posedge clk); #1; slot_ready=0;
        if (arm_pulse) begin $display("FAIL: arm push_en=0"); errors=errors+1; end
        if (st_err==e_save) begin $display("FAIL: no err push_en=0"); errors=errors+1; end
        push_en = 1; @(posedge clk); #1;

        // session=0
        session_id=0;
        e_save=st_err; slot_ready=1; @(posedge clk); #1; slot_ready=0;
        if (arm_pulse) begin $display("FAIL: arm session=0"); errors=errors+1; end
        if (st_err==e_save) begin $display("FAIL: no err session=0"); errors=errors+1; end
        session_id=32'd7; @(posedge clk); #1;

        // cap=0
        cap_bytes=0;
        e_save=st_err; slot_ready=1; @(posedge clk); #1; slot_ready=0;
        if (arm_pulse) begin $display("FAIL: arm cap=0"); errors=errors+1; end
        if (st_err==e_save) begin $display("FAIL: no err cap=0"); errors=errors+1; end
        cap_bytes=32'd8192; @(posedge clk); #1;

        // stream=0
        slot_stream_len=0;
        e_save=st_err; slot_ready=1; @(posedge clk); #1; slot_ready=0;
        if (arm_pulse) begin $display("FAIL: arm stream=0"); errors=errors+1; end
        if (st_err==e_save) begin $display("FAIL: no err stream=0"); errors=errors+1; end
        slot_stream_len=32'd1000; @(posedge clk); #1;

        // stream>slot
        slot_stream_len=32'd5000;
        e_save=st_err; slot_ready=1; @(posedge clk); #1; slot_ready=0;
        if (arm_pulse) begin $display("FAIL: arm stream>slot"); errors=errors+1; end
        if (st_err==e_save) begin $display("FAIL: no err stream>slot"); errors=errors+1; end
        slot_stream_len=32'd1000; @(posedge clk); #1;

        // mps>5
        mps_code=3'd6;
        e_save=st_err; slot_ready=1; @(posedge clk); #1; slot_ready=0;
        if (arm_pulse) begin $display("FAIL: arm mps>5"); errors=errors+1; end
        if (st_err==e_save) begin $display("FAIL: no err mps>5"); errors=errors+1; end
        mps_code=3'd3; @(posedge clk); #1;

        // link down
        link_up=0;
        e_save=st_err; slot_ready=1; @(posedge clk); #1; slot_ready=0;
        if (arm_pulse) begin $display("FAIL: arm link_down"); errors=errors+1; end
        if (st_err==e_save) begin $display("FAIL: no err link_down"); errors=errors+1; end
        link_up=1; @(posedge clk); #1;

        // dst misalign
        dst_base=64'd64;
        e_save=st_err; slot_ready=1; @(posedge clk); #1; slot_ready=0;
        if (arm_pulse) begin $display("FAIL: arm dst misalign"); errors=errors+1; end
        if (st_err==e_save) begin $display("FAIL: no err dst misalign"); errors=errors+1; end
        dst_base=64'd128; @(posedge clk); #1;

        // db misalign
        db_addr=64'd2596897;
        e_save=st_err; slot_ready=1; @(posedge clk); #1; slot_ready=0;
        if (arm_pulse) begin $display("FAIL: arm db misalign"); errors=errors+1; end
        if (st_err==e_save) begin $display("FAIL: no err db misalign"); errors=errors+1; end
        db_addr=64'd2596896; @(posedge clk); #1;

        // valid publish
        slot_id=32'd1; slot_stream_len=32'd1000; slot_base_word=32'd256;
        slot_ready=1; @(posedge clk); #1; slot_ready=0;
        if (!arm_pulse) begin $display("FAIL: no arm valid"); errors=errors+1; end
        if (o_frame_bytes != 32'd4096) begin $display("FAIL: frame_bytes=%0d", o_frame_bytes); errors=errors+1; end
        if (o_stream_len != 32'd1000) begin $display("FAIL: stream_len=%0d", o_stream_len); errors=errors+1; end
        if (o_src_sel != 1'b0) begin $display("FAIL: src_sel not DDR"); errors=errors+1; end
        @(posedge clk); #1;

        // pcie_err in S_ARM -> release
        pcie_err=1; @(posedge clk); #1; pcie_err=0;
        if (!slot_release) begin $display("FAIL: no release pcie_err ARM"); errors=errors+1; end
        @(posedge clk); #1;

        // publish + busy -> done -> held
        slot_ready=1; @(posedge clk); #1; slot_ready=0; // S_ARM
        pcie_busy=1; @(posedge clk); #1; // S_TX
        $display("DBG after busy posedge state=%0d", dut.state);
        pcie_busy=0;
        pcie_done=1; pcie_held_seq=32'd5; pcie_held_sess=32'd7; @(posedge clk); #1; pcie_done=0;
        $display("DBG after done posedge state=%0d st_held=%b", dut.state, st_held);
        if (dut.state != 3) begin $display("FAIL: not held (state=%0d)", dut.state); errors=errors+1; end
        @(posedge clk); #1;

        // bad ack
        ack_pulse=1; ack_seq=32'd999; ack_session=32'd7; @(posedge clk); #1; ack_pulse=0;
        if (!st_held) begin $display("FAIL: held dropped bad ack"); errors=errors+1; end
        @(posedge clk); #1;

        // good ack
        ack_pulse=1; ack_seq=32'd5; ack_session=32'd7; @(posedge clk); #1; ack_pulse=0;
        if (!slot_release) begin $display("FAIL: no release good ack"); errors=errors+1; end
        if (dut.state != 0) begin $display("FAIL: still held good ack (state=%0d)", dut.state); errors=errors+1; end
        @(posedge clk); #1;

        // cancel in held
        // publish + done to held
        slot_ready=1; @(posedge clk); #1; slot_ready=0;
        pcie_busy=1; @(posedge clk); #1;
        pcie_busy=0;
        pcie_done=1; pcie_held_seq=32'd6; pcie_held_sess=32'd7; @(posedge clk); #1; pcie_done=0;
        cancel_pulse=1; @(posedge clk); #1; cancel_pulse=0;
        if (!slot_release) begin $display("FAIL: no release cancel held"); errors=errors+1; end
        @(posedge clk); #1;

        // pcie_err in S_TX
        slot_ready=1; @(posedge clk); #1; slot_ready=0;
        pcie_busy=1; @(posedge clk); #1;
        pcie_busy=0;
        pcie_err=1; @(posedge clk); #1; pcie_err=0;
        if (!slot_release) begin $display("FAIL: no release pcie_err TX"); errors=errors+1; end
        @(posedge clk); #1;

        if (st_exported < 1) begin $display("FAIL: exported=%0d", st_exported); errors=errors+1; end
        if (errors==0) $display("TB_INDEPENDENT_EDGE PASS");
        else $display("TB_INDEPENDENT_EDGE FAIL errors=%0d", errors);
        $finish;
    end
endmodule