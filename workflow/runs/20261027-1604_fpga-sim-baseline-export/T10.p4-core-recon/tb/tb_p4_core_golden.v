// tb_p4_core_golden.v - T10.p4-core-recon round0 (candidate P4.core-recon-r0)
//
// Two independent checks in one run:
//   (a) DIFFERENTIAL: the frozen r2 bytes of fpga/csi2/src/img/img_algo_parallel_top.v
//       (base module set, r2 G1 functional PASS / SHA-bound in INT.P4-r2-manifest.json)
//       and the rebuilt candidate img_algo_parallel_top_p4 are driven with the same
//       stimulus and the same ready pattern; their y8/gau token sequences
//       {data[31:0], sof, eol, eof} + abort events + status counters must be identical.
//   (b) GOLDEN DUMP: the candidate's y8/gau tokens are written to +TOKFILE=<path> so the
//       independent Python reference model (model/compare_p4.py) recomputes every pixel
//       (Bayer demosaic -> Y8 -> 3x3 Gaussian) from the same documented stimulus formula.
//
// Stimulus is SYNTHETIC (not camera data): px(b,k) = (37*b + 211*k + 13*(b>>5) + 5) & 0x3FF,
// b = global beat index 0..(NF*BEATS-1), k = lane 0..3, W=64 H=48 phase=0 (RGGB), NF=2 good
// frames, no abort frame.  4 pixels per beat, lane 0 = bits[9:0] (leftmost).
//
// +BP=0 : ready always high.  +BP=1 : pseudo-random ready (>=30% stall cycles) plus one
//         contiguous 80-cycle stall (>=64 required) starting at input beat 300.
// Watchdog: 400000 cycles.  PASS/FAIL is the last line.
`timescale 1ns/1ps

module tb_p4_core_golden;

    localparam integer W     = 64;
    localparam integer H     = 48;
    localparam integer MPW   = W/4;
    localparam integer BEATS = MPW*H;
    localparam integer NF    = 2;
    localparam integer TOT   = NF*BEATS;
    localparam integer MAXW  = 512;
    localparam integer QD    = 2048;

    reg clk = 1'b0;
    always #2.6665 clk = ~clk;
    reg rst_n = 1'b0;

    integer bp;
    integer cyc, quiet, idx;
    integer err_diff, xerr, abt_ev;
    integer cy8, cg, py8, pg, yfr, gfr;
    integer fd;

    // ------------------------------------------------------------- stimulus
    reg [31:0] bi;
    reg        in_done;
    reg        started;
    reg        cfg_valid;
    reg [11:0] cfg_w, cfg_h;
    reg [1:0]  cfg_ph;

    function [9:0] pxv;
        input [31:0] b;
        input [2:0]  kk;
        begin
            pxv = (((b * 32'd37) + ({29'd0, kk} * 32'd211) + ((b >> 5) * 32'd13) + 32'd5) & 32'h3FF);
        end
    endfunction

    function [31:0] inner_of;
        input [31:0] b;
        begin inner_of = b % BEATS; end
    endfunction

    wire [39:0] s_data  = {pxv(bi, 3'd3), pxv(bi, 3'd2), pxv(bi, 3'd1), pxv(bi, 3'd0)};
    wire        s_sof   = (inner_of(bi) == 32'd0);
    wire        s_eol   = ((inner_of(bi) % MPW) == (MPW-1));
    wire        s_eof   = (inner_of(bi) == (BEATS-1));
    wire        s_abort = 1'b0;
    wire        s_valid = started && !in_done;

    // ------------------------------------------------------------- ready pattern
    reg [15:0] ls;
    reg [7:0]  lng;
    reg        lng_done;
    wire       rdy = (bp == 0) ? 1'b1
                   : ((lng != 8'd0) ? 1'b0 : !((ls[1:0] == 2'b00) || (ls[5] == 1'b1)));

    // ------------------------------------------------------------- base DUT (frozen r2 bytes)
    wire        b_cfg_rdy, b_cfg_err, b_s_rdy;
    wire        b_y8_v, b_y8_sof, b_y8_eol, b_y8_eof, b_y8_abt;
    wire [31:0] b_y8_d;
    wire        b_g_v, b_g_sof, b_g_eol, b_g_eof, b_g_abt;
    wire [31:0] b_g_d;
    wire        b_h_v, b_h_sof, b_h_eol, b_h_eof, b_h_abt;
    wire [31:0] b_h_d;
    wire [15:0] b_good, b_abt, b_hepub, b_herej, b_gauabt;

    img_algo_parallel_top #(.MAX_WORDS(MAXW)) u_base (
        .clk(clk), .rst_n(rst_n),
        .cfg_valid(cfg_valid), .cfg_ready(b_cfg_rdy),
        .cfg_width(cfg_w), .cfg_height(cfg_h), .cfg_phase(cfg_ph),
        .cfg_error(b_cfg_err),
        .s_valid(s_valid), .s_ready(b_s_rdy), .s_data(s_data),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof), .s_abort(s_abort),
        .y8_valid(b_y8_v), .y8_ready(rdy), .y8_data(b_y8_d),
        .y8_sof(b_y8_sof), .y8_eol(b_y8_eol), .y8_eof(b_y8_eof), .y8_abort(b_y8_abt),
        .gau_valid(b_g_v), .gau_ready(rdy), .gau_data(b_g_d),
        .gau_sof(b_g_sof), .gau_eol(b_g_eol), .gau_eof(b_g_eof), .gau_abort(b_g_abt),
        .he_valid(b_h_v), .he_ready(1'b1), .he_data(b_h_d),
        .he_sof(b_h_sof), .he_eol(b_h_eol), .he_eof(b_h_eof), .he_abort(b_h_abt),
        .st_frames_good(b_good), .st_frames_abort(b_abt),
        .st_he_published(b_hepub), .st_he_rejected(b_herej),
        .st_gau_abort(b_gauabt),
        .he_lut_addr(8'd0), .he_lut_data()
    );

    // ------------------------------------------------------------- candidate DUT (P4.core-recon-r0)
    wire        p_cfg_rdy, p_cfg_err, p_s_rdy;
    wire        p_y8_v, p_y8_sof, p_y8_eol, p_y8_eof, p_y8_abt;
    wire [31:0] p_y8_d;
    wire        p_g_v, p_g_sof, p_g_eol, p_g_eof, p_g_abt;
    wire [31:0] p_g_d;
    wire        p_h_v, p_h_sof, p_h_eol, p_h_eof, p_h_abt;
    wire [31:0] p_h_d;
    wire [15:0] p_good, p_abt, p_hepub, p_herej, p_gauabt;

    img_algo_parallel_top_p4 #(.MAX_WORDS(MAXW)) u_p4 (
        .clk(clk), .rst_n(rst_n),
        .cfg_valid(cfg_valid), .cfg_ready(p_cfg_rdy),
        .cfg_width(cfg_w), .cfg_height(cfg_h), .cfg_phase(cfg_ph),
        .cfg_error(p_cfg_err),
        .s_valid(s_valid), .s_ready(p_s_rdy), .s_data(s_data),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof), .s_abort(s_abort),
        .y8_valid(p_y8_v), .y8_ready(rdy), .y8_data(p_y8_d),
        .y8_sof(p_y8_sof), .y8_eol(p_y8_eol), .y8_eof(p_y8_eof), .y8_abort(p_y8_abt),
        .gau_valid(p_g_v), .gau_ready(rdy), .gau_data(p_g_d),
        .gau_sof(p_g_sof), .gau_eol(p_g_eol), .gau_eof(p_g_eof), .gau_abort(p_g_abt),
        .he_valid(p_h_v), .he_ready(1'b1), .he_data(p_h_d),
        .he_sof(p_h_sof), .he_eol(p_h_eol), .he_eof(p_h_eof), .he_abort(p_h_abt),
        .st_frames_good(p_good), .st_frames_abort(p_abt),
        .st_he_published(p_hepub), .st_he_rejected(p_herej),
        .st_gau_abort(p_gauabt),
        .he_lut_addr(8'd0), .he_lut_data()
    );

    // ------------------------------------------------------------- token records {abort,data,sof,eol,eof}
    reg [35:0] rby8 [0:QD-1];
    reg [35:0] rbg  [0:QD-1];
    reg [35:0] rpy8 [0:QD-1];
    reg [35:0] rpg  [0:QD-1];

    reg [255:0] tokname;

    initial begin
        if (!$value$plusargs("BP=%d", bp)) bp = 0;
        // relative to the (temporary) compile/run directory; run_sim.ps1 copies the dump
        // into sim/logs/tokens_bp<N>.txt after each run.
        $sformat(tokname, "tokens_bp%0d.txt", bp);
        fd = $fopen(tokname, "w");
        if (fd == 0) begin
            $display("TB_P4_CORE_GOLDEN FAIL cannot open token file %0s", tokname);
            $finish;
        end
    end

    initial begin
        rst_n = 1'b0;
        repeat (8) @(posedge clk);
        rst_n = 1'b1;
    end

    task cmp_task;
        begin
            if (cy8 != py8) begin
                $display("DIFF y8 token_count base=%0d p4=%0d", cy8, py8);
                err_diff = err_diff + 1;
            end else if (cy8 > QD) begin
                $display("DIFF y8 record_overflow %0d > %0d", cy8, QD);
                err_diff = err_diff + 1;
            end else begin
                for (idx = 0; idx < cy8; idx = idx + 1) begin
                    if (rby8[idx] !== rpy8[idx]) begin
                        if (err_diff < 5)
                            $display("DIFF y8 idx=%0d base=%h p4=%h", idx, rby8[idx], rpy8[idx]);
                        err_diff = err_diff + 1;
                    end
                end
            end

            if (cg != pg) begin
                $display("DIFF gau token_count base=%0d p4=%0d", cg, pg);
                err_diff = err_diff + 1;
            end else if (cg > QD) begin
                $display("DIFF gau record_overflow %0d > %0d", cg, QD);
                err_diff = err_diff + 1;
            end else begin
                for (idx = 0; idx < cg; idx = idx + 1) begin
                    if (rbg[idx] !== rpg[idx]) begin
                        if (err_diff < 5)
                            $display("DIFF gau idx=%0d base=%h p4=%h", idx, rbg[idx], rpg[idx]);
                        err_diff = err_diff + 1;
                    end
                end
            end

            if ((b_good !== p_good) || (b_abt !== p_abt) || (b_hepub !== p_hepub) ||
                (b_gauabt !== p_gauabt) || (b_cfg_err !== p_cfg_err)) begin
                $display("DIFF status base good=%0d abt=%0d hepub=%0d gauabt=%0d cfgerr=%0d / p4 good=%0d abt=%0d hepub=%0d gauabt=%0d cfgerr=%0d",
                         b_good, b_abt, b_hepub, b_gauabt, b_cfg_err,
                         p_good, p_abt, p_hepub, p_gauabt, p_cfg_err);
                err_diff = err_diff + 1;
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bi <= 32'd0;
            in_done <= 1'b0;
            started <= 1'b0;
            cfg_valid <= 1'b0;
            cfg_w <= 12'd0;
            cfg_h <= 12'd0;
            cfg_ph <= 2'd0;
            ls <= 16'hACE1;
            lng <= 8'd0;
            lng_done <= 1'b0;
            cyc <= 0;
            quiet <= 0;
            err_diff = 0;
            xerr = 0;
            abt_ev = 0;
            cy8 = 0;
            cg = 0;
            py8 = 0;
            pg = 0;
            yfr = 0;
            gfr = 0;
        end else begin
            cyc <= cyc + 1;
            ls <= {ls[14:0], ls[15] ^ ls[13] ^ ls[9]};

            if ((bp != 0) && (lng_done == 1'b0) && (bi >= 32'd300)) begin
                lng <= 8'd80;
                lng_done <= 1'b1;
            end else if (lng != 8'd0) begin
                lng <= lng - 8'd1;
            end

            if (!started) begin
                if (!cfg_valid) begin
                    cfg_valid <= 1'b1;
                    cfg_w <= W;
                    cfg_h <= H;
                    cfg_ph <= 2'd0;
                end else if (b_cfg_rdy && p_cfg_rdy) begin
                    started <= 1'b1;
                    cfg_valid <= 1'b0;
                end
            end

            if (s_valid && b_s_rdy && p_s_rdy) begin
                if (bi == (TOT-1)) in_done <= 1'b1;
                else bi <= bi + 32'd1;
            end

            // base records
            if (b_y8_v && rdy) begin
                if (cy8 < QD) rby8[cy8] = {1'b0, b_y8_d, b_y8_sof, b_y8_eol, b_y8_eof};
                cy8 = cy8 + 1;
            end
            if (b_g_v && rdy) begin
                if (cg < QD) rbg[cg] = {1'b0, b_g_d, b_g_sof, b_g_eol, b_g_eof};
                cg = cg + 1;
            end
            if ((b_y8_abt && !b_y8_v) || (b_g_abt && !b_g_v)) abt_ev = abt_ev + 1;

            // candidate records + golden dump + X check
            if (p_y8_v && rdy) begin
                if ((^{p_y8_d, p_y8_sof, p_y8_eol, p_y8_eof}) === 1'bx) xerr = xerr + 1;
                if (py8 < QD) rpy8[py8] = {1'b0, p_y8_d, p_y8_sof, p_y8_eol, p_y8_eof};
                py8 = py8 + 1;
                $fdisplay(fd, "Y %0d %08h %0d %0d %0d", yfr, p_y8_d, p_y8_sof, p_y8_eol, p_y8_eof);
                if (p_y8_sof) yfr = yfr + 1;
            end
            if (p_g_v && rdy) begin
                if ((^{p_g_d, p_g_sof, p_g_eol, p_g_eof}) === 1'bx) xerr = xerr + 1;
                if (pg < QD) rpg[pg] = {1'b0, p_g_d, p_g_sof, p_g_eol, p_g_eof};
                pg = pg + 1;
                $fdisplay(fd, "G %0d %08h %0d %0d %0d", gfr, p_g_d, p_g_sof, p_g_eol, p_g_eof);
                if (p_g_sof) gfr = gfr + 1;
            end
            if ((p_y8_abt && !p_y8_v) || (p_g_abt && !p_g_v)) begin
                abt_ev = abt_ev + 1;
                $display("NOTE p4 abort marker cycle=%0d", cyc);
            end
            if ((p_y8_v === 1'bx) || (p_g_v === 1'bx)) xerr = xerr + 1;

            if (in_done && !b_y8_v && !b_g_v && !p_y8_v && !p_g_v) quiet <= quiet + 1;
            else quiet <= 0;

            if (in_done && (quiet >= 400)) begin
                cmp_task;
                $display("TB_STATS y8=%0d gau=%0d good_b=%0d good_p=%0d abt_b=%0d abt_p=%0d hepub=%0d gauabt=%0d xerr=%0d abt_ev=%0d cyc=%0d diff=%0d",
                         py8, pg, b_good, p_good, b_abt, p_abt, p_hepub, p_gauabt, xerr, abt_ev, cyc, err_diff);
                $fdisplay(fd, "STATS y8=%0d gau=%0d good_b=%0d good_p=%0d abt_b=%0d abt_p=%0d hepub=%0d gauabt=%0d xerr=%0d abt_ev=%0d cyc=%0d diff=%0d",
                          py8, pg, b_good, p_good, b_abt, p_abt, p_hepub, p_gauabt, xerr, abt_ev, cyc, err_diff);
                if ((err_diff == 0) && (xerr == 0) && (abt_ev == 0))
                    $display("TB_P4_CORE_GOLDEN PASS");
                else
                    $display("TB_P4_CORE_GOLDEN FAIL errors=%0d xerr=%0d abt=%0d", err_diff, xerr, abt_ev);
                $fclose(fd);
                $finish;
            end

            if (cyc > 400000) begin
                $display("TB_P4_CORE_GOLDEN FAIL timeout cyc=%0d bi=%0d in_done=%0d", cyc, bi, in_done);
                $fclose(fd);
                $finish;
            end
        end
    end

endmodule
