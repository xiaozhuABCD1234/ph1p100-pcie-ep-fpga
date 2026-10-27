`timescale 1ns/1ps
// tb_img_algo_rate.sv — T09.rk-align-algo throughput evidence on real RTL.
// Drives a constant RAW10 frame (512 -> Y8 128 through the whole chain) at
// 4 px/beat and measures, per branch, the cycles from the first to the last
// output beat, plus the total wall cycles per frame including the HE frame-end
// LUT work.  Constant expected values are literals (128), not DUT mirrors.
// Marker: ALGO_RATE_PASS / ALGO_RATE_FAIL.
module tb_img_algo_rate;
    parameter W = 1920;
    parameter H = 1080;
    parameter PHASE = 0;
    parameter NFRAMES = 2;
    localparam NP = W * H;
    localparam NB = NP / 4;

    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;

    reg         cfg_valid = 0;
    reg  [11:0] cfg_width = W[11:0], cfg_height = H[11:0];
    reg  [1:0]  cfg_phase = PHASE[1:0];
    wire        cfg_ready, cfg_error;

    reg         s_valid = 0;
    wire        s_ready;
    reg  [39:0] s_data = 40'h8020080200;   // 4 x 512 (10-bit) -> Y8 128
    reg         s_sof = 0, s_eol = 0, s_eof = 0, s_abort = 0;

    wire        y8_valid, gau_valid, he_valid;
    wire [31:0] y8_data, gau_data, he_data;
    wire        y8_sof, y8_eol, y8_eof, y8_abort;
    wire        gau_sof, gau_eol, gau_eof, gau_abort;
    wire        he_sof, he_eol, he_eof, he_abort;
    wire [15:0] st_good, st_abort, st_he_pub, st_he_rej, st_gau_ab;
    reg  [7:0]  he_lut_addr = 0;
    wire [7:0]  he_lut_data;

    img_algo_parallel_top #(.MAX_WORDS(512)) dut (
        .clk(clk), .rst_n(rst_n),
        .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
        .cfg_width(cfg_width), .cfg_height(cfg_height), .cfg_phase(cfg_phase),
        .cfg_error(cfg_error),
        .s_valid(s_valid), .s_ready(s_ready), .s_data(s_data),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof), .s_abort(s_abort),
        .y8_valid(y8_valid), .y8_ready(1'b1), .y8_data(y8_data),
        .y8_sof(y8_sof), .y8_eol(y8_eol), .y8_eof(y8_eof), .y8_abort(y8_abort),
        .gau_valid(gau_valid), .gau_ready(1'b1), .gau_data(gau_data),
        .gau_sof(gau_sof), .gau_eol(gau_eol), .gau_eof(gau_eof), .gau_abort(gau_abort),
        .he_valid(he_valid), .he_ready(1'b1), .he_data(he_data),
        .he_sof(he_sof), .he_eol(he_eol), .he_eof(he_eof), .he_abort(he_abort),
        .st_frames_good(st_good), .st_frames_abort(st_abort),
        .st_he_published(st_he_pub), .st_he_rejected(st_he_rej),
        .st_gau_abort(st_gau_ab),
        .he_lut_addr(he_lut_addr), .he_lut_data(he_lut_data)
    );

    integer cycles = 0, errs = 0;
    integer beats_y8 = 0, beats_gau = 0, beats_he = 0;
    integer sof_y8 = 0, eol_y8 = 0, eof_y8 = 0;
    integer sof_gau = 0, eol_gau = 0, eof_gau = 0;
    integer sof_he = 0, eol_he = 0, eof_he = 0;
    integer all3 = 0;
    integer t0 = 0, t1 = 0;
    integer f;
    integer fr_start [0:7], fr_end [0:7];
    integer fr_beats [0:7];

    always @(posedge clk) cycles <= cycles + 1;

    // per-branch output checking (constant 128, sideband counts)
    always @(negedge clk) begin
        if (rst_n) begin
            if (y8_valid) begin
                if (y8_data !== 32'h80808080) begin
                    if (errs < 10) $display("ALGO_RATE_MISMATCH y8 %08x", y8_data);
                    errs = errs + 1;
                end
                beats_y8 = beats_y8 + 1;
                if (y8_sof) sof_y8 = sof_y8 + 1;
                if (y8_eol) eol_y8 = eol_y8 + 1;
                if (y8_eof) eof_y8 = eof_y8 + 1;
            end
            if (gau_valid) begin
                if (gau_data !== 32'h80808080) begin
                    if (errs < 10) $display("ALGO_RATE_MISMATCH gau %08x", gau_data);
                    errs = errs + 1;
                end
                beats_gau = beats_gau + 1;
                if (gau_sof) sof_gau = sof_gau + 1;
                if (gau_eol) eol_gau = eol_gau + 1;
                if (gau_eof) eof_gau = eof_gau + 1;
            end
            if (he_valid) begin
                if (he_data !== 32'h80808080) begin
                    if (errs < 10) $display("ALGO_RATE_MISMATCH he %08x", he_data);
                    errs = errs + 1;
                end
                beats_he = beats_he + 1;
                if (he_sof) sof_he = sof_he + 1;
                if (he_eol) eol_he = eol_he + 1;
                if (he_eof) eof_he = eof_he + 1;
            end
            if (y8_valid && gau_valid && he_valid) all3 = all3 + 1;
        end
    end

    integer i, fr;
    initial begin
        rst_n = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        @(negedge clk);
        cfg_valid = 1;
        while (!cfg_ready) @(negedge clk);
        @(posedge clk);
        #1 cfg_valid = 0;
        if (cfg_error) begin
            $display("ALGO_RATE_FAIL cfg_error");
            $finish;
        end
        for (fr = 0; fr < NFRAMES; fr = fr + 1) begin
            fr_start[fr] = cycles;
            fr_beats[fr] = 0;
            for (i = 0; i < NB; i = i + 1) begin
                @(negedge clk);
                s_sof = (i == 0);
                s_eol = (i % (W/4) == W/4 - 1);
                s_eof = (i == NB - 1);
                s_valid = 1;
                while (!s_ready) @(negedge clk);
                @(posedge clk);
                #1 s_valid = 0;
                fr_beats[fr] = fr_beats[fr] + 1;
            end
            // wait for this frame's branches to finish
            t0 = beats_y8 + beats_gau + beats_he;
            for (i = 0; i < 4000000; i = i + 1) begin
                @(negedge clk);
                if ((beats_y8 >= (fr + 1) * NB) && (beats_gau >= (fr + 1) * NB) &&
                    (beats_he >= (fr + 1) * NB)) i = 5000000;
            end
            fr_end[fr] = cycles;
        end

        if (beats_y8 != NFRAMES * NB) begin $display("ALGO_RATE_FAIL y8 beats %0d", beats_y8); errs = errs + 1; end
        if (beats_gau != NFRAMES * NB) begin $display("ALGO_RATE_FAIL gau beats %0d", beats_gau); errs = errs + 1; end
        if (beats_he != NFRAMES * NB) begin $display("ALGO_RATE_FAIL he beats %0d", beats_he); errs = errs + 1; end
        if (sof_y8 != NFRAMES || sof_gau != NFRAMES || sof_he != NFRAMES) begin
            $display("ALGO_RATE_FAIL sof %0d/%0d/%0d", sof_y8, sof_gau, sof_he); errs = errs + 1; end
        if (eol_y8 != NFRAMES * H || eol_gau != NFRAMES * H || eol_he != NFRAMES * H) begin
            $display("ALGO_RATE_FAIL eol %0d/%0d/%0d", eol_y8, eol_gau, eol_he); errs = errs + 1; end
        if (eof_y8 != NFRAMES || eof_gau != NFRAMES || eof_he != NFRAMES) begin
            $display("ALGO_RATE_FAIL eof %0d/%0d/%0d", eof_y8, eof_gau, eof_he); errs = errs + 1; end
        if (all3 == 0) begin $display("ALGO_RATE_FAIL no concurrent output"); errs = errs + 1; end
        if (st_good != NFRAMES[15:0] || st_he_pub != NFRAMES[15:0]) begin
            $display("ALGO_RATE_FAIL counters good=%0d pub=%0d", st_good, st_he_pub); errs = errs + 1; end

        if (errs != 0) begin
            $display("ALGO_RATE_FAIL errs=%0d", errs);
        end else begin
            $display("ALGO_RATE_PASS W=%0d H=%0d frames=%0d beats_per_frame=%0d cyc_f0=%0d cyc_f1=%0d total_cyc=%0d all3=%0d",
                     W, H, NFRAMES, NB, fr_end[0]-fr_start[0], fr_end[1]-fr_start[1], cycles, all3);
        end
        $finish;
    end

    initial begin
        #400000000;
        $display("ALGO_RATE_FAIL timeout cycles=%0d beats=%0d/%0d/%0d", cycles, beats_y8, beats_gau, beats_he);
        $finish;
    end
endmodule
