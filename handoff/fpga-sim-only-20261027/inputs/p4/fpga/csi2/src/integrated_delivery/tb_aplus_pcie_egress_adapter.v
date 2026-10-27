`timescale 1ns/1ps
module tb_aplus_pcie_egress_adapter;
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
        #20 rst_n = 1;
        // configure
        push_en = 1; cap_bytes = 32'd8192; session_id = 32'd7;
        dst_base = 64'd128; db_addr = 64'd2596896;
        mps_code = 3'd3; link_up = 1;
        #10;
        // publish a slot
        slot_ready = 1; slot_id = 32'd1; slot_stream_len = 32'd1000; slot_base_word = 32'd256;
        #10 slot_ready = 0;
        if (!arm_pulse) begin $display("FAIL: no arm_pulse"); errors = errors + 1; end
        if (o_frame_bytes != 32'd4096) begin $display("FAIL: frame_bytes=%0d", o_frame_bytes); errors=errors+1; end
        if (o_stream_len != 32'd1000) begin $display("FAIL: stream_len=%0d", o_stream_len); errors=errors+1; end
        if (o_src_sel != 1'b0) begin $display("FAIL: src_sel not DDR"); errors=errors+1; end
        // pusher busy then done
        #10 pcie_busy = 1;
        #10 pcie_busy = 0;
        #10 pcie_done = 1; pcie_held_seq = 32'd1; pcie_held_sess = 32'd7;
        #10 pcie_done = 0;
        #10;
        if (!st_held) begin $display("FAIL: not held"); errors=errors+1; end
        // bad ack
        ack_pulse = 1; ack_seq = 32'd999; ack_session = 32'd7; #10 ack_pulse = 0;
        if (st_err == 0) begin $display("FAIL: bad ack not recorded"); errors=errors+1; end
        // good ack
        ack_pulse = 1; ack_seq = 32'd1; ack_session = 32'd7; #10 ack_pulse = 0;
        if (!slot_release) begin $display("FAIL: no slot_release"); errors=errors+1; end
        #20;
        if (st_exported != 32'd1) begin $display("FAIL: exported=%0d", st_exported); errors=errors+1; end
        if (errors == 0) $display("TB_APLUS_PCIE_EGRESS_ADAPTER PASS");
        else $display("TB_APLUS_PCIE_EGRESS_ADAPTER FAIL errors=%0d", errors);
        $finish;
    end
endmodule
