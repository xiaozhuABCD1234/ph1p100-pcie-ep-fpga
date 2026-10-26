`timescale 1ns/1ps
// tb_gray8_gaussian3x3_frame.sv — T09 module-level check for the retained
// worktree candidate gray8_gaussian3x3_frame.v (provenance:
// fpga/csi2/src/img/PROVENANCE.md).  Expected frames come from the independent
// Python oracle (tools/algo/oracle_algo.py); no DUT internals are used.
// Marker: ALGO_GAUMOD_PASS / ALGO_GAUMOD_FAIL.
module tb_gray8_gaussian3x3_frame;
    parameter MAX_WIDTH = 64;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg cfg_valid = 0, s_valid = 0, done_ready = 0;
    reg m_ready = 1;   // driven by the always @* below; init must match its value
                       // (a conflicting init would win at time 0 and the block
                       // would not re-trigger until stall_cnt changes)
    reg [11:0] cfg_width = 0, cfg_height = 0;
    reg [7:0] s_data = 0;
    wire cfg_ready, s_ready, m_valid, m_sof, m_eol, m_eof, done_valid, done_error;
    wire [7:0] m_data;

    gray8_gaussian3x3_frame #(.MAX_WIDTH(MAX_WIDTH)) dut (
        .clk(clk), .rst_n(rst_n),
        .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
        .cfg_width(cfg_width), .cfg_height(cfg_height),
        .s_valid(s_valid), .s_ready(s_ready), .s_data(s_data),
        .m_valid(m_valid), .m_ready(m_ready), .m_data(m_data),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof),
        .done_valid(done_valid), .done_ready(done_ready), .done_error(done_error)
    );

    integer errs = 0, frames = 0, pixels_out = 0, pixels_in = 0;
    integer stalls = 0, resets = 0, invalid_frames = 0;
    reg [31:0] rng = 32'h13579bdf;
    integer stall_cnt = 0;
    always @(posedge clk) if (stall_cnt > 0) stall_cnt <= stall_cnt - 1;
    always @* m_ready = (stall_cnt == 0);

    task fail(input string msg);
        begin
            errs = errs + 1;
            if (errs < 25) $display("ALGO_GAUMOD_MISMATCH %s", msg);
        end
    endtask

    integer fd, rc, i, k, ww, hh, kind, abort_at, total;
    string vector_path;
    string cmd;
    integer v_in, v_exp;
    reg [8*256-1:0] line;
    integer src [0:4095];
    integer expd [0:4095];
    integer frame_in, frame_out, guard;

    // output checker
    integer exp_ptr = 0;
    always @(negedge clk) begin
        if (rst_n && m_valid) begin
            if (m_data !== expd[exp_ptr][7:0])
                fail($sformatf("payload mismatch idx=%0d got=%0d exp=%0d", exp_ptr, m_data, expd[exp_ptr]));
            if (m_sof !== (exp_ptr == 0) ||
                m_eol !== ((exp_ptr % ww) == ww - 1) ||
                m_eof !== (exp_ptr == total - 1))
                fail($sformatf("sideband mismatch idx=%0d", exp_ptr));
            if (m_ready) begin
                exp_ptr = exp_ptr + 1;
                pixels_out = pixels_out + 1;
            end else begin
                stalls = stalls + 1;
            end
        end
    end

    task do_reset;
        begin
            rst_n = 0;
            cfg_valid = 0; s_valid = 0; done_ready = 0;
            stall_cnt = 0;
            repeat (3) @(negedge clk);
            rst_n = 1;
            repeat (2) @(negedge clk);
            resets = resets + 1;
        end
    endtask

    initial begin
        if (!$value$plusargs("VECTORS=%s", vector_path)) begin
            $display("ALGO_GAUMOD_FAIL no +VECTORS"); $finish;
        end
        fd = $fopen(vector_path, "r");
        if (!fd) begin $display("ALGO_GAUMOD_FAIL open"); $finish; end
        rst_n = 0; repeat (3) @(negedge clk); rst_n = 1;

        while (!$feof(fd)) begin
            rc = $fgets(line, fd);
            if (rc > 0) begin
                if ($sscanf(line, "%s", cmd) == 1) begin
                    if (cmd == "F") begin
                        rc = $sscanf(line, "%s %d %d %d %d %d", cmd, ww, hh, kind, abort_at, total);
                        for (i = 0; i < total; i = i + 1) begin
                            rc = $fscanf(fd, "%d %d\n", v_in, v_exp);
                            src[i] = v_in; expd[i] = v_exp;
                        end
                        frames = frames + 1;
                        exp_ptr = 0; frame_in = 0; frame_out = 0;

                        // configure
                        @(negedge clk);
                        while (!cfg_ready) @(negedge clk);
                        cfg_width = ww[11:0]; cfg_height = hh[11:0]; cfg_valid = 1;
                        @(posedge clk);
                        #1 cfg_valid = 0;
                        @(negedge clk);

                        if (kind == 1) begin
                            invalid_frames = invalid_frames + 1;
                            s_valid = 1; s_data = 8'hee;
                            guard = 0;
                            while (!done_valid) begin
                                @(negedge clk);
                                if (s_ready || m_valid) fail("invalid descriptor accepted traffic");
                                guard = guard + 1;
                                if (guard > 10) fail("invalid descriptor not rejected");
                            end
                            if (!done_error) fail("invalid descriptor without error flag");
                            @(negedge clk);
                            done_ready = 1;
                            @(posedge clk);
                            #1 done_ready = 0;
                            s_valid = 0;
                            repeat (3) @(negedge clk);
                            if (!cfg_ready) fail("did not return to idle after invalid cfg");
                        end else begin
                            guard = 0;
                            while (!done_valid && guard >= 0) begin
                                @(negedge clk);
                                rng = {rng[30:0], rng[31]^rng[21]^rng[1]^rng[0]};
                                stall_cnt = (rng[5:0] >= 48) ? rng[3:0] : 0;
                                if (frame_in < total && s_ready) begin
                                    s_data = src[frame_in][7:0];
                                    s_valid = 1;
                                    @(posedge clk);
                                    #1 s_valid = 0;
                                    frame_in = frame_in + 1;
                                    pixels_in = pixels_in + 1;
                                end
                                guard = guard + 1;
                                if (guard > total * 40 + 200) begin
                                    fail("frame progress timeout");
                                    guard = -1;
                                end
                                if ((kind == 2 && frame_in >= abort_at) ||
                                    (kind == 3 && pixels_out >= abort_at)) begin
                                    do_reset();
                                    done_ready = 0;
                                    guard = -1;
                                end
                            end
                            if (guard > 0) begin
                                if (kind == 0) begin
                                    if (frame_in != total || pixels_out != total)
                                        fail($sformatf("frame count mismatch in=%0d out=%0d of %0d", frame_in, pixels_out, total));
                                end
                                @(negedge clk);
                                done_ready = 1;
                                @(posedge clk);
                                #1 done_ready = 0;
                                repeat (3) @(negedge clk);
                                if (kind == 0 && !cfg_ready) fail("did not return to idle after frame");
                            end
                        end
                    end
                end
            end
        end
        $fclose(fd);
        if (!stalls) fail("no output stall coverage");
        if (resets < 2) fail("no reset coverage");
        if (invalid_frames < 1) fail("no invalid cfg coverage");
        if (errs != 0) begin
            $display("ALGO_GAUMOD_FAIL errs=%0d frames=%0d in=%0d out=%0d", errs, frames, pixels_in, pixels_out);
        end else begin
            $display("ALGO_GAUMOD_PASS frames=%0d pixels_in=%0d pixels_out=%0d stalls=%0d resets=%0d invalid=%0d",
                     frames, pixels_in, pixels_out, stalls, resets, invalid_frames);
        end
        $finish;
    end

    initial begin
        #50000000;
        $display("ALGO_GAUMOD_FAIL timeout");
        $finish;
    end
endmodule
