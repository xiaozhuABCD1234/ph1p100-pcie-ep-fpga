`timescale 1ns/1ps
// INT.P3 round1 integrated-test independent testbench (tester-owned).
// Independent criteria vs development:
//  1) Per-cycle valid/ready protocol monitor: while output is stalled (o_valid && !o_ready)
//     the presented descriptor must be held (o_valid + full identity) and NO accept
//     handshake may occur on either input port.
//  2) Consumption scoreboard: every consumed descriptor must equal, field by field, the
//     next descriptor accepted in acceptance order (detects overwrite / frame loss / mixing).
//  3) Scenario state checks on busy/status counters independent of dev-TB expectations.
module tb_intp3_indep;
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

    initial clk = 1'b0;
    always #5 clk = ~clk;

    integer errors = 0;
    reg [15:0] e_acc = 16'd0;
    reg [15:0] e_comp = 16'd0;
    reg [15:0] e_fail = 16'd0;
    reg [15:0] e_rej = 16'd0;

    // ---------------- scoreboard queue (acceptance order) ----------------
    reg [97:0] q [0:255];
    integer aq = 0;
    integer cq = 0;
    integer ta = 0; // cumulative accept handshakes (survives reset scenarios)
    integer tc = 0; // cumulative consume handshakes
    integer ta_t7 = 0; // accept count before the intentional mid-flight reset case
    integer tc_t7 = 0;

    wire [97:0] o_pack = {o_camera_id, o_slot_id, o_epoch, o_session, o_capture_seq};
    wire [97:0] a_pack = {a_desc_camera_id, a_desc_slot_id, a_desc_epoch, a_desc_session, a_desc_capture_seq};
    wire [97:0] b_pack = {b_desc_camera_id, b_desc_slot_id, b_desc_epoch, b_desc_session, b_desc_capture_seq};

    // ---------------- stall-hold monitor state ----------------
    reg m_stall;
    reg m_cam, m_slot;
    reg [31:0] m_epoch, m_session, m_seq;

    task err;
        input [8*80-1:0] msg;
        begin
            $display("FAIL: %0s (t=%0t)", msg, $time);
            errors = errors + 1;
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            m_stall <= 1'b0;
            aq = 0;
            cq = 0;
        end else begin
            // P1: if the previous cycle was stalled and the consumer is still not ready,
            // the presented descriptor must be held (o_valid + full identity).
            if (m_stall && !(o_valid && o_ready)) begin
                if (o_valid !== 1'b1) err("P1 o_valid dropped during stall");
                if ({o_camera_id,o_slot_id,o_epoch,o_session,o_capture_seq} !==
                    {m_cam,m_slot,m_epoch,m_session,m_seq}) err("P1 presented identity overwritten during stall");
            end
            // P2: no accept handshake may complete in a cycle where output is stalled
            if (o_valid && !o_ready) begin
                if (a_desc_valid && a_desc_ready) err("P2 channel A accepted during output stall");
                if (b_desc_valid && b_desc_ready) err("P2 channel B accepted during output stall");
            end

            // record acceptances in order
            if (a_desc_valid && a_desc_ready) begin
                q[aq] = a_pack;
                aq = aq + 1;
                ta = ta + 1;
            end
            if (b_desc_valid && b_desc_ready) begin
                q[aq] = b_pack;
                aq = aq + 1;
                ta = ta + 1;
            end
            // consumption must match the oldest accepted descriptor
            if (o_valid && o_ready) begin
                if (cq >= aq) begin
                    err("P3 consumed descriptor with no prior accept");
                end else if (q[cq] !== o_pack) begin
                    $display("FAIL: P3 consumed identity mismatch exp=%h got=%h (t=%0t)", q[cq], o_pack, $time);
                    errors = errors + 1;
                end
                cq = cq + 1;
                tc = tc + 1;
            end

            m_stall <= o_valid && !o_ready;
            m_cam <= o_camera_id;
            m_slot <= o_slot_id;
            m_epoch <= o_epoch;
            m_session <= o_session;
            m_seq <= o_capture_seq;
        end
    end

    task chk_stats;
        begin
            #1;
            if (st_accepted !== e_acc) begin
                $display("FAIL: st_accepted exp=%0d got=%0d (t=%0t)", e_acc, st_accepted, $time);
                errors = errors + 1;
            end
            if (st_completed !== e_comp) begin
                $display("FAIL: st_completed exp=%0d got=%0d (t=%0t)", e_comp, st_completed, $time);
                errors = errors + 1;
            end
            if (st_failed !== e_fail) begin
                $display("FAIL: st_failed exp=%0d got=%0d (t=%0t)", e_fail, st_failed, $time);
                errors = errors + 1;
            end
            if (st_rejected !== e_rej) begin
                $display("FAIL: st_rejected exp=%0d got=%0d (t=%0t)", e_rej, st_rejected, $time);
                errors = errors + 1;
            end
        end
    endtask

    // busy ownership is checked on the DUT state registers (the exported st_*_busy
    // outputs are one-cycle delayed copies and cannot be sampled same-cycle).
    task chk_busy;
        input exp_a, exp_b;
        begin
            #1;
            if (dut.a_busy !== exp_a) begin
                $display("FAIL: a_busy exp=%b got=%b (t=%0t)", exp_a, dut.a_busy, $time);
                errors = errors + 1;
            end
            if (dut.b_busy !== exp_b) begin
                $display("FAIL: b_busy exp=%b got=%b (t=%0t)", exp_b, dut.b_busy, $time);
                errors = errors + 1;
            end
        end
    endtask

    task chk_out;
        input exp_v, exp_cam;
        input [31:0] exp_seq;
        begin
            #1;
            if (o_valid !== exp_v) begin
                $display("FAIL: o_valid exp=%b got=%b (t=%0t)", exp_v, o_valid, $time);
                errors = errors + 1;
            end
            if (exp_v === 1'b1) begin
                if (o_camera_id !== exp_cam) begin
                    $display("FAIL: o_camera_id exp=%b got=%b (t=%0t)", exp_cam, o_camera_id, $time);
                    errors = errors + 1;
                end
                if (o_capture_seq !== exp_seq) begin
                    $display("FAIL: o_capture_seq exp=%0d got=%0d (t=%0t)", exp_seq, o_capture_seq, $time);
                    errors = errors + 1;
                end
            end
        end
    endtask

    // one-cycle output ready pulse (sampled exactly once at a posedge)
    task pulse_ready;
        begin
            @(negedge clk);
            o_ready = 1'b1;
            @(negedge clk);
            o_ready = 1'b0;
        end
    endtask

    // one-cycle release pulse
    task pulse_release;
        input cam;
        input slot;
        input [31:0] ep, sess, seq;
        input [2:0] st;
        begin
            @(negedge clk);
            rel_valid = 1'b1;
            rel_camera_id = cam;
            rel_slot_id = slot;
            rel_epoch = ep;
            rel_session = sess;
            rel_capture_seq = seq;
            rel_status = st;
            @(negedge clk);
            rel_valid = 1'b0;
        end
    endtask

    task do_reset;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            a_desc_valid = 1'b0; b_desc_valid = 1'b0;
            a_desc_camera_id = 1'b0; b_desc_camera_id = 1'b1;
            a_desc_slot_id = 1'b0; b_desc_slot_id = 1'b1;
            a_desc_epoch = 32'd0; a_desc_session = 32'd0; a_desc_capture_seq = 32'd0;
            b_desc_epoch = 32'd0; b_desc_session = 32'd0; b_desc_capture_seq = 32'd0;
            o_ready = 1'b0;
            rel_valid = 1'b0; rel_camera_id = 1'b0; rel_slot_id = 1'b0;
            rel_epoch = 32'd0; rel_session = 32'd0; rel_capture_seq = 32'd0; rel_status = 3'd0;
            a_enable = 1'b1; b_priority = 1'b0;
            repeat (4) @(negedge clk);
            rst_n = 1'b1;
            @(negedge clk);
        end
    endtask

    initial begin
        rst_n = 1'b0;
        a_desc_valid = 0; b_desc_valid = 0;
        a_desc_camera_id = 0; b_desc_camera_id = 1;
        a_desc_slot_id = 0; b_desc_slot_id = 1;
        a_desc_epoch = 0; a_desc_session = 0; a_desc_capture_seq = 0;
        b_desc_epoch = 0; b_desc_session = 0; b_desc_capture_seq = 0;
        o_ready = 0;
        rel_valid = 0; rel_camera_id = 0; rel_slot_id = 0;
        rel_epoch = 0; rel_session = 0; rel_capture_seq = 0; rel_status = 0;
        a_enable = 1; b_priority = 0;

        do_reset();
        chk_out(1'b0, 1'b0, 32'd0);
        chk_busy(1'b0, 1'b0);
        chk_stats();

        // ============ T1: A presented; B offered during stall; second A offered ============
        @(negedge clk);
        a_desc_valid = 1'b1; a_desc_camera_id = 1'b0; a_desc_slot_id = 1'b0;
        a_desc_epoch = 32'h0000_00A1; a_desc_session = 32'h0000_00A2; a_desc_capture_seq = 32'd7;
        wait (o_valid == 1'b1);
        chk_out(1'b1, 1'b0, 32'd7);
        chk_busy(1'b1, 1'b0);
        e_acc = e_acc + 16'd1;
        chk_stats();
        @(negedge clk);
        a_desc_valid = 1'b0;
        b_desc_valid = 1'b1; b_desc_camera_id = 1'b1; b_desc_slot_id = 1'b1;
        b_desc_epoch = 32'h0000_00B1; b_desc_session = 32'h0000_00B2; b_desc_capture_seq = 32'd9;
        repeat (8) begin
            @(negedge clk);
            chk_out(1'b1, 1'b0, 32'd7);
            if (a_desc_ready !== 1'b0) err("T1 a_desc_ready during stall");
            if (b_desc_ready !== 1'b0) err("T1 b_desc_ready during stall");
            if (st_accepted !== e_acc) err("T1 accepted count changed during stall");
        end
        a_desc_valid = 1'b1; a_desc_slot_id = 1'b0;
        a_desc_epoch = 32'h0000_00A3; a_desc_session = 32'h0000_00A4; a_desc_capture_seq = 32'd8;
        repeat (3) begin
            @(negedge clk);
            chk_out(1'b1, 1'b0, 32'd7);
            if (a_desc_ready !== 1'b0) err("T1 second A accepted while stalled/busy");
        end
        a_desc_valid = 1'b0;
        // consume A; B pending must be presented at the same edge, A remains busy
        pulse_ready();
        e_acc = e_acc + 16'd1;
        chk_out(1'b1, 1'b1, 32'd9);
        chk_busy(1'b1, 1'b1);
        chk_stats();
        @(negedge clk);
        b_desc_valid = 1'b0;
        // consume B
        pulse_ready();
        chk_out(1'b0, 1'b0, 32'd0);
        chk_busy(1'b1, 1'b1);
        // wrong epoch release of A -> rejected, A stays busy
        pulse_release(1'b0, 1'b0, 32'h0000_00FF, 32'h0000_00A2, 32'd7, 3'd0);
        e_rej = e_rej + 16'd1;
        chk_stats();
        chk_busy(1'b1, 1'b1);
        // correct A release
        pulse_release(1'b0, 1'b0, 32'h0000_00A1, 32'h0000_00A2, 32'd7, 3'd0);
        e_comp = e_comp + 16'd1;
        chk_stats();
        chk_busy(1'b0, 1'b1);
        // wrong camera release for B (A id while A not busy) -> rejected
        pulse_release(1'b0, 1'b0, 32'h0000_00A1, 32'h0000_00A2, 32'd7, 3'd0);
        e_rej = e_rej + 16'd1;
        chk_stats();
        chk_busy(1'b0, 1'b1);
        // correct B release with non-zero status -> failed count, busy cleared
        pulse_release(1'b1, 1'b1, 32'h0000_00B1, 32'h0000_00B2, 32'd9, 3'd2);
        e_fail = e_fail + 16'd1;
        chk_stats();
        chk_busy(1'b0, 1'b0);

        // ============ T2: B presented; A offered during stall ============
        @(negedge clk);
        b_desc_valid = 1'b1; b_desc_camera_id = 1'b1; b_desc_slot_id = 1'b1;
        b_desc_epoch = 32'h0000_00C1; b_desc_session = 32'h0000_00C2; b_desc_capture_seq = 32'd21;
        wait (o_valid == 1'b1);
        chk_out(1'b1, 1'b1, 32'd21);
        e_acc = e_acc + 16'd1;
        chk_stats();
        @(negedge clk);
        b_desc_valid = 1'b0;
        a_desc_valid = 1'b1; a_desc_camera_id = 1'b0; a_desc_slot_id = 1'b0;
        a_desc_epoch = 32'h0000_00C3; a_desc_session = 32'h0000_00C4; a_desc_capture_seq = 32'd22;
        repeat (6) begin
            @(negedge clk);
            chk_out(1'b1, 1'b1, 32'd21);
            if (a_desc_ready !== 1'b0) err("T2 A accepted during stall");
            if (st_accepted !== e_acc) err("T2 accepted count changed during stall");
        end
        pulse_ready(); // consume B, A accepted at same edge
        e_acc = e_acc + 16'd1;
        chk_out(1'b1, 1'b0, 32'd22);
        chk_busy(1'b1, 1'b1);
        chk_stats();
        @(negedge clk);
        a_desc_valid = 1'b0;
        pulse_ready(); // consume A
        chk_out(1'b0, 1'b0, 32'd0);
        pulse_release(1'b1, 1'b1, 32'h0000_00C1, 32'h0000_00C2, 32'd21, 3'd0);
        e_comp = e_comp + 16'd1;
        pulse_release(1'b0, 1'b0, 32'h0000_00C3, 32'h0000_00C4, 32'd22, 3'd0);
        e_comp = e_comp + 16'd1;
        chk_stats();
        chk_busy(1'b0, 1'b0);

        // ============ T3: two descriptors queued, held-ready back-to-back ============
        @(negedge clk);
        a_desc_valid = 1'b1; a_desc_camera_id = 1'b0; a_desc_slot_id = 1'b0;
        a_desc_epoch = 32'h0000_00D1; a_desc_session = 32'h0000_00D2; a_desc_capture_seq = 32'd31;
        b_desc_valid = 1'b1; b_desc_camera_id = 1'b1; b_desc_slot_id = 1'b1;
        b_desc_epoch = 32'h0000_00D3; b_desc_session = 32'h0000_00D4; b_desc_capture_seq = 32'd32;
        // last_sel==0 (A was last selected in T2) and b_priority=0 -> B first
        wait (o_valid == 1'b1);
        chk_out(1'b1, 1'b1, 32'd32);
        e_acc = e_acc + 16'd1;
        chk_stats();
        @(negedge clk);
        b_desc_valid = 1'b0;
        // hold ready two cycles: consume B, A accepted same edge, then consume A
        @(negedge clk); o_ready = 1'b1;
        @(negedge clk);
        @(negedge clk); o_ready = 1'b0;
        e_acc = e_acc + 16'd1;
        chk_out(1'b0, 1'b0, 32'd0);
        chk_busy(1'b1, 1'b1);
        chk_stats();
        @(negedge clk);
        a_desc_valid = 1'b0;
        pulse_release(1'b1, 1'b1, 32'h0000_00D3, 32'h0000_00D4, 32'd32, 3'd0);
        e_comp = e_comp + 16'd1;
        pulse_release(1'b0, 1'b0, 32'h0000_00D1, 32'h0000_00D2, 32'd31, 3'd0);
        e_comp = e_comp + 16'd1;
        chk_stats();
        chk_busy(1'b0, 1'b0);

        // ============ T4: A disabled does not block B; A descriptor preserved ============
        a_enable = 1'b0;
        @(negedge clk);
        a_desc_valid = 1'b1; a_desc_camera_id = 1'b0; a_desc_slot_id = 1'b0;
        a_desc_epoch = 32'h0000_00E1; a_desc_session = 32'h0000_00E2; a_desc_capture_seq = 32'd41;
        b_desc_valid = 1'b1; b_desc_camera_id = 1'b1; b_desc_slot_id = 1'b1;
        b_desc_epoch = 32'h0000_00E3; b_desc_session = 32'h0000_00E4; b_desc_capture_seq = 32'd42;
        wait (o_valid == 1'b1);
        chk_out(1'b1, 1'b1, 32'd42);
        e_acc = e_acc + 16'd1;
        chk_stats();
        if (a_desc_ready !== 1'b0) err("T4 A accepted while disabled");
        @(negedge clk);
        b_desc_valid = 1'b0;
        pulse_ready();
        chk_out(1'b0, 1'b0, 32'd0);
        pulse_release(1'b1, 1'b1, 32'h0000_00E3, 32'h0000_00E4, 32'd42, 3'd0);
        e_comp = e_comp + 16'd1;
        chk_stats();
        repeat (4) begin
            @(negedge clk);
            chk_out(1'b0, 1'b0, 32'd0);
            if (a_desc_ready !== 1'b0) err("T4 A accepted while disabled after B drain");
            if (st_accepted !== e_acc) err("T4 accepted count changed while A disabled");
        end
        a_enable = 1'b1;
        wait (o_valid == 1'b1);
        chk_out(1'b1, 1'b0, 32'd41);
        e_acc = e_acc + 16'd1;
        chk_stats();
        @(negedge clk);
        a_desc_valid = 1'b0;
        pulse_ready();
        pulse_release(1'b0, 1'b0, 32'h0000_00E1, 32'h0000_00E2, 32'd41, 3'd0);
        e_comp = e_comp + 16'd1;
        chk_stats();
        chk_busy(1'b0, 1'b0);

        // ============ T5: b_priority forces B; round-robin alternates without identity mix ============
        b_priority = 1'b1;
        @(negedge clk);
        a_desc_valid = 1'b1; a_desc_camera_id = 1'b0; a_desc_slot_id = 1'b0;
        a_desc_epoch = 32'h0000_00F1; a_desc_session = 32'h0000_00F2; a_desc_capture_seq = 32'd51;
        b_desc_valid = 1'b1; b_desc_camera_id = 1'b1; b_desc_slot_id = 1'b1;
        b_desc_epoch = 32'h0000_00F3; b_desc_session = 32'h0000_00F4; b_desc_capture_seq = 32'd52;
        wait (o_valid == 1'b1);
        chk_out(1'b1, 1'b1, 32'd52);
        e_acc = e_acc + 16'd1;
        chk_stats();
        @(negedge clk);
        b_desc_valid = 1'b0;
        pulse_ready();
        pulse_release(1'b1, 1'b1, 32'h0000_00F3, 32'h0000_00F4, 32'd52, 3'd0);
        e_comp = e_comp + 16'd1;
        wait (o_valid == 1'b1);
        chk_out(1'b1, 1'b0, 32'd51);
        e_acc = e_acc + 16'd1;
        chk_stats();
        @(negedge clk);
        a_desc_valid = 1'b0;
        pulse_ready();
        pulse_release(1'b0, 1'b0, 32'h0000_00F1, 32'h0000_00F2, 32'd51, 3'd0);
        e_comp = e_comp + 16'd1;
        b_priority = 1'b0;
        chk_stats();
        chk_busy(1'b0, 1'b0);

        // alternation: last selected A -> B first
        @(negedge clk);
        a_desc_valid = 1'b1; a_desc_slot_id = 1'b0;
        a_desc_epoch = 32'h0000_0101; a_desc_session = 32'h0000_0102; a_desc_capture_seq = 32'd53;
        b_desc_valid = 1'b1; b_desc_camera_id = 1'b1; b_desc_slot_id = 1'b1;
        b_desc_epoch = 32'h0000_0103; b_desc_session = 32'h0000_0104; b_desc_capture_seq = 32'd54;
        wait (o_valid == 1'b1);
        chk_out(1'b1, 1'b1, 32'd54);
        e_acc = e_acc + 16'd1;
        chk_stats();
        @(negedge clk);
        b_desc_valid = 1'b0;
        pulse_ready();
        pulse_release(1'b1, 1'b1, 32'h0000_0103, 32'h0000_0104, 32'd54, 3'd0);
        e_comp = e_comp + 16'd1;
        wait (o_valid == 1'b1);
        chk_out(1'b1, 1'b0, 32'd53);
        e_acc = e_acc + 16'd1;
        chk_stats();
        @(negedge clk);
        a_desc_valid = 1'b0;
        pulse_ready();
        pulse_release(1'b0, 1'b0, 32'h0000_0101, 32'h0000_0102, 32'd53, 3'd0);
        e_comp = e_comp + 16'd1;

        // alternation: last selected B (B-only round) -> A first when both pending
        @(negedge clk);
        b_desc_valid = 1'b1; b_desc_camera_id = 1'b1; b_desc_slot_id = 1'b1;
        b_desc_epoch = 32'h0000_0111; b_desc_session = 32'h0000_0112; b_desc_capture_seq = 32'd57;
        wait (o_valid == 1'b1); // only B pending, so B accepted; last_sel=1
        chk_out(1'b1, 1'b1, 32'd57);
        e_acc = e_acc + 16'd1;
        pulse_ready();
        @(negedge clk);
        b_desc_valid = 1'b0;
        pulse_release(1'b1, 1'b1, 32'h0000_0111, 32'h0000_0112, 32'd57, 3'd0);
        e_comp = e_comp + 16'd1;
        chk_stats();
        @(negedge clk);
        a_desc_valid = 1'b1; a_desc_camera_id = 1'b0; a_desc_slot_id = 1'b0;
        a_desc_epoch = 32'h0000_0113; a_desc_session = 32'h0000_0114; a_desc_capture_seq = 32'd58;
        b_desc_valid = 1'b1; b_desc_camera_id = 1'b1; b_desc_slot_id = 1'b1;
        b_desc_epoch = 32'h0000_0115; b_desc_session = 32'h0000_0116; b_desc_capture_seq = 32'd59;
        wait (o_valid == 1'b1);
        chk_out(1'b1, 1'b0, 32'd58);
        e_acc = e_acc + 16'd1;
        chk_stats();
        @(negedge clk);
        a_desc_valid = 1'b0;
        pulse_ready(); // consume A; B pending accepted at same edge
        e_acc = e_acc + 16'd1;
        chk_out(1'b1, 1'b1, 32'd59);
        chk_busy(1'b1, 1'b1);
        chk_stats();
        @(negedge clk);
        b_desc_valid = 1'b0;
        pulse_ready();
        pulse_release(1'b0, 1'b0, 32'h0000_0113, 32'h0000_0114, 32'd58, 3'd0);
        e_comp = e_comp + 16'd1;
        pulse_release(1'b1, 1'b1, 32'h0000_0115, 32'h0000_0116, 32'd59, 3'd0);
        e_comp = e_comp + 16'd1;
        chk_stats();
        chk_busy(1'b0, 1'b0);

        // ============ T6: invalid camera_id never accepted ============
        @(negedge clk);
        a_desc_valid = 1'b1; a_desc_camera_id = 1'b1; // invalid for A
        a_desc_epoch = 32'h0000_0121; a_desc_session = 32'h0000_0122; a_desc_capture_seq = 32'd61;
        b_desc_valid = 1'b1; b_desc_camera_id = 1'b0; // invalid for B
        b_desc_epoch = 32'h0000_0123; b_desc_session = 32'h0000_0124; b_desc_capture_seq = 32'd62;
        repeat (3) begin
            @(negedge clk);
            chk_out(1'b0, 1'b0, 32'd0);
            if (a_desc_ready !== 1'b0) err("T6 invalid A camera_id accepted");
            if (b_desc_ready !== 1'b0) err("T6 invalid B camera_id accepted");
            if (st_accepted !== e_acc) err("T6 accepted count changed on invalid id");
        end
        a_desc_valid = 1'b0;
        b_desc_valid = 1'b0;

        // ============ T6b: release identity matching across all fields ============
        @(negedge clk);
        a_desc_valid = 1'b1; a_desc_camera_id = 1'b0; a_desc_slot_id = 1'b1;
        a_desc_epoch = 32'h0000_0141; a_desc_session = 32'h0000_0142; a_desc_capture_seq = 32'd63;
        wait (o_valid == 1'b1);
        chk_out(1'b1, 1'b0, 32'd63);
        e_acc = e_acc + 16'd1;
        chk_stats();
        @(negedge clk);
        a_desc_valid = 1'b0;
        pulse_ready();
        chk_out(1'b0, 1'b0, 32'd0);
        // slot mismatch
        pulse_release(1'b0, 1'b0, 32'h0000_0141, 32'h0000_0142, 32'd63, 3'd0);
        e_rej = e_rej + 16'd1;
        chk_stats(); chk_busy(1'b1, 1'b0);
        // session mismatch
        pulse_release(1'b0, 1'b1, 32'h0000_0141, 32'h0000_0143, 32'd63, 3'd0);
        e_rej = e_rej + 16'd1;
        chk_stats(); chk_busy(1'b1, 1'b0);
        // capture_seq mismatch
        pulse_release(1'b0, 1'b1, 32'h0000_0141, 32'h0000_0142, 32'd64, 3'd0);
        e_rej = e_rej + 16'd1;
        chk_stats(); chk_busy(1'b1, 1'b0);
        // camera mismatch: B identity while B not busy
        pulse_release(1'b1, 1'b1, 32'h0000_0141, 32'h0000_0142, 32'd63, 3'd0);
        e_rej = e_rej + 16'd1;
        chk_stats(); chk_busy(1'b1, 1'b0);
        // exact identity finally releases ownership
        pulse_release(1'b0, 1'b1, 32'h0000_0141, 32'h0000_0142, 32'd63, 3'd0);
        e_comp = e_comp + 16'd1;
        chk_stats(); chk_busy(1'b0, 1'b0);

        // ============ T7: reset mid-flight clears presentation and ownership ============
        ta_t7 = ta;
        tc_t7 = tc;
        @(negedge clk);
        a_desc_valid = 1'b1; a_desc_camera_id = 1'b0;
        a_desc_epoch = 32'h0000_0131; a_desc_session = 32'h0000_0132; a_desc_capture_seq = 32'd71;
        wait (o_valid == 1'b1);
        chk_out(1'b1, 1'b0, 32'd71);
        e_acc = e_acc + 16'd1;
        chk_stats();
        @(negedge clk);
        a_desc_valid = 1'b0;
        // assert reset while descriptor is presented and stalled
        @(negedge clk);
        rst_n = 1'b0;
        repeat (2) @(negedge clk);
        if (o_valid !== 1'b0) err("T7 o_valid not cleared by reset");
        if (st_a_busy !== 1'b0) err("T7 a_busy not cleared by reset");
        if (st_b_busy !== 1'b0) err("T7 b_busy not cleared by reset");
        if (st_accepted !== 16'd0) err("T7 st_accepted not cleared by reset");
        @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);
        e_acc = 16'd0; e_comp = 16'd0; e_fail = 16'd0; e_rej = 16'd0;
        chk_out(1'b0, 1'b0, 32'd0);
        chk_busy(1'b0, 1'b0);
        chk_stats();

        // ============ final: no accepted descriptor may be left unconsumed ============
        if (aq !== cq) begin
            $display("FAIL: scoreboard accepted=%0d consumed=%0d (lost/extra descriptor)", aq, cq);
            errors = errors + 1;
        end
        if (ta !== tc + 1) begin
            $display("FAIL: cumulative accepted=%0d consumed=%0d (expected exactly one reset-discarded descriptor)", ta, tc);
            errors = errors + 1;
        end
        if (ta !== ta_t7 + 1 || tc !== tc_t7) begin
            $display("FAIL: reset case bookkeeping unexpected ta=%0d ta_t7=%0d tc=%0d tc_t7=%0d", ta, ta_t7, tc, tc_t7);
            errors = errors + 1;
        end

        if (errors == 0) $display("TB_INTP3_INDEP PASS cumulative_accepted=%0d cumulative_consumed=%0d reset_discarded=1", ta, tc);
        else $display("TB_INTP3_INDEP FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #2000000;
        $display("TB_INTP3_INDEP TIMEOUT");
        $finish;
    end
endmodule
