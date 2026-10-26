`timescale 1ns/1ps
// tb_rgb8_gray_stream.sv — T09 module-level check for the retained worktree
// candidate rgb8_gray_stream.v (provenance: fpga/csi2/src/img/PROVENANCE.md).
// Expected Y values come from the Python generator (independent arithmetic).
// Marker: ALGO_GRAYMOD_PASS / ALGO_GRAYMOD_FAIL.
module tb_rgb8_gray_stream;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg  s_valid = 0, s_sof = 0, s_last = 0;
    reg  [7:0] s_r = 0, s_g = 0, s_b = 0;
    reg  m_ready = 0;
    wire s_ready, m_valid, m_sof, m_last;
    wire [7:0] m_y;

    rgb8_gray_stream dut (
        .clk(clk), .rst_n(rst_n),
        .s_valid(s_valid), .s_ready(s_ready),
        .s_r(s_r), .s_g(s_g), .s_b(s_b), .s_sof(s_sof), .s_last(s_last),
        .m_valid(m_valid), .m_ready(m_ready), .m_y(m_y), .m_sof(m_sof), .m_last(m_last)
    );

    integer errs = 0, accepted = 0, emitted = 0, stalls = 0, gaps = 0, resets = 0;
    integer hold_checked = 0;
    reg [9:0] held;
    integer stall_cnt = 0;

    always @(posedge clk) if (stall_cnt > 0) stall_cnt <= stall_cnt - 1;
    always @* m_ready = (stall_cnt == 0);

    task fail(input string msg);
        begin
            errs = errs + 1;
            if (errs < 20) $display("ALGO_GRAYMOD_MISMATCH %s", msg);
        end
    endtask

    // pending expected token (module has a 1-deep pipeline)
    integer exp_y = 0, exp_sof = 0, exp_last = 0;
    reg     have_exp = 0;
    reg     stalled_prev = 0;

    always @(negedge clk) begin
        if (rst_n) begin
            if (m_valid && !m_ready) begin
                if (stalled_prev && ({m_y, m_sof, m_last} !== held))
                    fail("output changed while stalled");
                held = {m_y, m_sof, m_last};
                stalled_prev = 1;
                hold_checked = hold_checked + 1;
            end else begin
                if (m_valid && m_ready) begin
                    if (!have_exp) fail("unexpected output beat");
                    else if ((m_y !== exp_y[7:0]) || (m_sof !== exp_sof[0]) || (m_last !== exp_last[0]))
                        fail($sformatf("payload mismatch got y=%0d sof=%0d last=%0d exp y=%0d sof=%0d last=%0d",
                                       m_y, m_sof, m_last, exp_y, exp_sof, exp_last));
                    emitted = emitted + 1;
                    have_exp = 0;
                end
                stalled_prev = 0;
            end
        end
    end

    integer fd, rc, i;
    string vector_path;
    string cmd;
    integer a1, a2;
    integer v_r, v_g, v_b, v_sof, v_last, v_y;
    reg [8*256-1:0] line;

    task drive(input integer r, g, b, sof, last, y);
        begin
            @(negedge clk);
            s_r = r[7:0]; s_g = g[7:0]; s_b = b[7:0]; s_sof = sof[0]; s_last = last[0];
            s_valid = 1;
            while (!s_ready) @(negedge clk);
            @(posedge clk);
            #1 s_valid = 0;
            accepted = accepted + 1;
            exp_y = y; exp_sof = sof; exp_last = last; have_exp = 1;
        end
    endtask

    initial begin
        if (!$value$plusargs("VECTORS=%s", vector_path)) begin
            $display("ALGO_GRAYMOD_FAIL no +VECTORS"); $finish;
        end
        fd = $fopen(vector_path, "r");
        if (!fd) begin $display("ALGO_GRAYMOD_FAIL open"); $finish; end
        rst_n = 0; repeat (3) @(negedge clk); rst_n = 1;
        while (!$feof(fd)) begin
            rc = $fgets(line, fd);
            if (rc > 0) begin
                if ($sscanf(line, "%s", cmd) == 1) begin
                    if (cmd == "V") begin
                        rc = $sscanf(line, "%s %d %d %d %d %d %d", cmd, v_r, v_g, v_b, v_sof, v_last, v_y);
                        drive(v_r, v_g, v_b, v_sof, v_last, v_y);
                    end else if (cmd == "STALL") begin
                        rc = $sscanf(line, "%s %d", cmd, a1);
                        stall_cnt = a1; stalls = stalls + a1;
                    end else if (cmd == "GAP") begin
                        rc = $sscanf(line, "%s %d", cmd, a1);
                        @(negedge clk);
                        s_valid = 0;
                        for (i = 0; i < a1; i = i + 1) begin
                            @(negedge clk);
                            gaps = gaps + 1;
                        end
                    end else if (cmd == "RESET") begin
                        rst_n = 0;
                        s_valid = 0;
                        repeat (3) @(negedge clk);
                        if ({s_ready, m_valid} !== 2'b00) fail("reset left handshake active");
                        rst_n = 1;
                        resets = resets + 1;
                        have_exp = 0;
                        repeat (2) @(negedge clk);
                    end
                end
            end
        end
        $fclose(fd);
        repeat (10) @(negedge clk);
        if (emitted + 1 < accepted) fail($sformatf("token loss accepted=%0d emitted=%0d", accepted, emitted));
        if (stalls == 0) fail("no stall coverage");
        if (gaps == 0) fail("no gap coverage");
        if (resets == 0) fail("no reset coverage");
        if (errs != 0) begin
            $display("ALGO_GRAYMOD_FAIL errs=%0d accepted=%0d emitted=%0d", errs, accepted, emitted);
        end else begin
            $display("ALGO_GRAYMOD_PASS accepted=%0d emitted=%0d stalls=%0d gaps=%0d resets=%0d hold=%0d",
                     accepted, emitted, stalls, gaps, resets, hold_checked);
        end
        $finish;
    end

    initial begin
        #20000000;
        $display("ALGO_GRAYMOD_FAIL timeout");
        $finish;
    end
endmodule
