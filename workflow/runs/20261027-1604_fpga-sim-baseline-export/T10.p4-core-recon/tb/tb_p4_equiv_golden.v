// tb_img_algo_equiv_p4.v — INT.P4 round2 data-sequence equivalence test.
//
// Compares the r2 timing-only derived variant img_algo_parallel_top_p4 (which
// instantiates bayer_raw10_demosaic4_p4) against the frozen original
// img_algo_parallel_top + bayer_raw10_demosaic4 under IDENTICAL stimulus.
//
// Three DUTs, same beat sequence (each source holds its beat until its own
// s_ready, so only WHEN a beat is offered differs, never WHICH beat):
//   dut0 = base   img_algo_parallel_top      ready pattern A (LFSR seed A)
//   dut1 = variant img_algo_parallel_top_p4  ready pattern A (LFSR seed A)
//   dut2 = base   img_algo_parallel_top      ready pattern B (other seeds)
//
//   CHECK_REF_NEW : dut0 vs dut1 (same ready pattern).  The required evidence:
//                   identical token sequences for y8 / gau / he (order, data,
//                   sof/eol/eof and abort markers).  Latency is irrelevant here
//                   because the streams are recorded and compared in order.
//   CONTROL_REF_REF2 : dut0 vs dut2 (identical RTL, different ready pattern).
//                   Informational control: a difference here means the frozen
//                   HE/Gaussian modules are sensitive to the *stall pattern*
//                   themselves (pre-existing property, not this variant) — the
//                   log records it and the gap is reported honestly.
//
// Token = {marker, data[31:0], sof, eol, eof}.  A data token is sampled on
// valid&&ready; an abort marker is the one-cycle r_valid=0/r_abort=1 event
// (popped regardless of ready, see algo_obuf.v) and is compared as a token.
//
// Stimulus: W=64, H=48 (reduced), frame 1 good, frame 2 good, frame 3 aborted
// at beat 200 (no eof).  PASS/FAIL is the last line.
`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// thin wrapper so the three DUTs share one port list (VARIANT=0 base, 1 p4)
// ---------------------------------------------------------------------------
module int_p4_equiv_dut #(
    parameter integer VARIANT = 0,
    parameter integer MAXW    = 512
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        cfg_valid,
    output wire        cfg_ready,
    input  wire [11:0] cfg_width,
    input  wire [11:0] cfg_height,
    input  wire [1:0]  cfg_phase,
    output wire        cfg_error,
    input  wire        s_valid,
    output wire        s_ready,
    input  wire [39:0] s_data,
    input  wire        s_sof,
    input  wire        s_eol,
    input  wire        s_eof,
    input  wire        s_abort,
    output wire        y8_valid,
    input  wire        y8_ready,
    output wire [31:0] y8_data,
    output wire        y8_sof,
    output wire        y8_eol,
    output wire        y8_eof,
    output wire        y8_abort,
    output wire        gau_valid,
    input  wire        gau_ready,
    output wire [31:0] gau_data,
    output wire        gau_sof,
    output wire        gau_eol,
    output wire        gau_eof,
    output wire        gau_abort,
    output wire        he_valid,
    input  wire        he_ready,
    output wire [31:0] he_data,
    output wire        he_sof,
    output wire        he_eol,
    output wire        he_eof,
    output wire        he_abort,
    output wire [15:0] st_good,
    output wire [15:0] st_abort,
    output wire [15:0] st_he_pub,
    output wire [15:0] st_he_rej,
    output wire [15:0] st_gau_abt
);
    generate
    if (VARIANT == 0) begin : g_base
        img_algo_parallel_top #(.MAX_WORDS(MAXW)) u_impl (
            .clk(clk), .rst_n(rst_n),
            .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
            .cfg_width(cfg_width), .cfg_height(cfg_height), .cfg_phase(cfg_phase),
            .cfg_error(cfg_error),
            .s_valid(s_valid), .s_ready(s_ready), .s_data(s_data),
            .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof), .s_abort(s_abort),
            .y8_valid(y8_valid), .y8_ready(y8_ready), .y8_data(y8_data),
            .y8_sof(y8_sof), .y8_eol(y8_eol), .y8_eof(y8_eof), .y8_abort(y8_abort),
            .gau_valid(gau_valid), .gau_ready(gau_ready), .gau_data(gau_data),
            .gau_sof(gau_sof), .gau_eol(gau_eol), .gau_eof(gau_eof), .gau_abort(gau_abort),
            .he_valid(he_valid), .he_ready(he_ready), .he_data(he_data),
            .he_sof(he_sof), .he_eol(he_eol), .he_eof(he_eof), .he_abort(he_abort),
            .st_frames_good(st_good), .st_frames_abort(st_abort),
            .st_he_published(st_he_pub), .st_he_rejected(st_he_rej),
            .st_gau_abort(st_gau_abt),
            .he_lut_addr(8'd0), .he_lut_data()
        );
    end else begin : g_p4
        img_algo_parallel_top_p4 #(.MAX_WORDS(MAXW)) u_impl (
            .clk(clk), .rst_n(rst_n),
            .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
            .cfg_width(cfg_width), .cfg_height(cfg_height), .cfg_phase(cfg_phase),
            .cfg_error(cfg_error),
            .s_valid(s_valid), .s_ready(s_ready), .s_data(s_data),
            .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof), .s_abort(s_abort),
            .y8_valid(y8_valid), .y8_ready(y8_ready), .y8_data(y8_data),
            .y8_sof(y8_sof), .y8_eol(y8_eol), .y8_eof(y8_eof), .y8_abort(y8_abort),
            .gau_valid(gau_valid), .gau_ready(gau_ready), .gau_data(gau_data),
            .gau_sof(gau_sof), .gau_eol(gau_eol), .gau_eof(gau_eof), .gau_abort(gau_abort),
            .he_valid(he_valid), .he_ready(he_ready), .he_data(he_data),
            .he_sof(he_sof), .he_eol(he_eol), .he_eof(he_eof), .he_abort(he_abort),
            .st_frames_good(st_good), .st_frames_abort(st_abort),
            .st_he_published(st_he_pub), .st_he_rejected(st_he_rej),
            .st_gau_abort(st_gau_abt),
            .he_lut_addr(8'd0), .he_lut_data()
        );
    end
    endgenerate
endmodule

// ---------------------------------------------------------------------------
module tb_img_algo_equiv_p4;

    localparam W     = 64;
    localparam H     = 48;
    localparam MPW   = W/4;               // 16 beats per row
    localparam BEATS = MPW*H;             // 768
    localparam TOT   = BEATS + BEATS + 201;
    localparam integer MAXW = 512;
    localparam integer QD   = 2048;

    reg clk = 1'b0;
    always #2.6665 clk = ~clk;
    reg rst_n = 1'b0;

    // ------------------------------------------------------------- scoreboard
    // rec slot index = dut*3 + stream  (stream 0=y8 1=gau 2=he), 3 duts
    reg [35:0] rec [0:9*QD-1];
    integer    cnt [0:9];
    integer    err_ref_new;

    // ---- T10 attempt2 addition: token dump for the independent reference model ----
    // The frame-control contract below is the r2 TB verbatim; only this dump (a pure
    // observation tap on the already-recorded tokens) is added.
    integer     fd;
    integer     seed_mode_dump;
    integer     dump_tag;
    reg [255:0] dumpname;

    task dump_tok;
        input integer dd;
        input integer ss;
        input         ab;
        input [31:0]  dat;
        input         sf;
        input         el;
        input         ef;
        begin
            if (ab) $fdisplay(fd, "%0d %0d A 0 0 0 0", dd, ss);
            else    $fdisplay(fd, "%0d %0d D %08h %0d %0d %0d", dd, ss, dat, sf, el, ef);
        end
    endtask

    initial begin
        if (!$value$plusargs("SEEDMODE=%d", seed_mode_dump)) seed_mode_dump = 0;
        if (!$value$plusargs("TAG=%d", dump_tag)) dump_tag = 0;
        $sformat(dumpname, "tokens_sm%0d_t%0d.txt", seed_mode_dump, dump_tag);
        fd = $fopen(dumpname, "w");
        if (fd == 0) begin
            $display("TB_IMG_ALGO_EQUIV_P4 FAIL cannot open dump file");
            $finish;
        end
    end
    integer    err_ctl;
    integer    cyc;
    integer    quiet;
    integer    k, j, dut, strm, side;
    reg        first_ref_new_printed;

    task tsk_rec;
        input integer d;
        input integer s;
        input [35:0]  t;
        begin
            if (cnt[d*3+s] < QD) rec[(d*3+s)*QD + cnt[d*3+s]] = t;
            cnt[d*3+s] = cnt[d*3+s] + 1;
        end
    endtask

    // ------------------------------------------------------------- stimulus
    function [9:0] px;
        input [31:0] b;
        input [2:0]  kk;
        begin
            px = ((b * 32'd37) + ({29'd0, kk} * 32'd211) + ((b >> 5) * 32'd13) + 32'd5) & 32'h3FF;
        end
    endfunction

    function [31:0] frame_of; input [31:0] b; begin
        frame_of = (b < BEATS) ? 32'd0 : (b < 2*BEATS) ? 32'd1 : 32'd2; end
    endfunction

    function [31:0] inner_of; input [31:0] b; begin
        inner_of = (b < BEATS) ? b : (b < 2*BEATS) ? (b - BEATS) : (b - 2*BEATS); end
    endfunction

    reg [31:0] bi [0:2];
    reg        sdone [0:2];
    integer    seedmode;

    reg         cfg_valid;
    reg  [11:0] cfg_w, cfg_h;
    reg  [1:0]  cfg_ph;
    reg         started;

    // ready generators: dut0 and dut1 share seeds, dut2 uses different seeds
    reg [15:0] ls [0:8];      // 3 duts x 3 streams
    reg        rdy [0:8];
    reg [15:0] seed_a [0:2];
    reg [15:0] seed_b [0:2];

    // DUT port wires: [dut][...]
    wire        d_s_ready [0:2];
    wire        d_cfg_ready [0:2];
    wire        d_cfg_error [0:2];
    wire        d_y8_v [0:2];
    wire [31:0] d_y8_d [0:2];
    wire        d_y8_sof [0:2], d_y8_eol [0:2], d_y8_eof [0:2], d_y8_abt [0:2];
    wire        d_gau_v [0:2];
    wire [31:0] d_gau_d [0:2];
    wire        d_gau_sof [0:2], d_gau_eol [0:2], d_gau_eof [0:2], d_gau_abt [0:2];
    wire        d_he_v [0:2];
    wire [31:0] d_he_d [0:2];
    wire        d_he_sof [0:2], d_he_eol [0:2], d_he_eof [0:2], d_he_abt [0:2];
    wire [15:0] d_good [0:2], d_abort [0:2], d_hepub [0:2], d_herej [0:2], d_gauabt [0:2];

    // per-DUT beat index wires
    wire [31:0] in_of [0:2];
    wire [31:0] fr_of [0:2];
    wire [39:0] ddat [0:2];
    wire        dsof [0:2], deol [0:2], deof [0:2], dabt [0:2];

    genvar gi;
    generate
    for (gi = 0; gi < 3; gi = gi + 1) begin : g_dut
        assign in_of[gi] = inner_of(bi[gi]);
        assign fr_of[gi] = frame_of(bi[gi]);
        assign ddat[gi]  = {px(bi[gi],3'd3), px(bi[gi],3'd2), px(bi[gi],3'd1), px(bi[gi],3'd0)};
        assign dsof[gi]  = (in_of[gi] == 32'd0);
        assign deol[gi]  = ((in_of[gi] % MPW) == (MPW-1));
        assign deof[gi]  = (in_of[gi] == (BEATS-1)) && (fr_of[gi] != 32'd2);
        assign dabt[gi]  = (fr_of[gi] == 32'd2) && (in_of[gi] == 32'd200);

        int_p4_equiv_dut #(.VARIANT((gi == 1) ? 1 : 0), .MAXW(MAXW)) u_dut (
            .clk(clk), .rst_n(rst_n),
            .cfg_valid(cfg_valid), .cfg_ready(d_cfg_ready[gi]),
            .cfg_width(cfg_w), .cfg_height(cfg_h), .cfg_phase(cfg_ph),
            .cfg_error(d_cfg_error[gi]),
            .s_valid(!sdone[gi]), .s_ready(d_s_ready[gi]), .s_data(ddat[gi]),
            .s_sof(dsof[gi]), .s_eol(deol[gi]), .s_eof(deof[gi]), .s_abort(dabt[gi]),
            .y8_valid(d_y8_v[gi]), .y8_ready(rdy[gi*3+0]), .y8_data(d_y8_d[gi]),
            .y8_sof(d_y8_sof[gi]), .y8_eol(d_y8_eol[gi]), .y8_eof(d_y8_eof[gi]),
            .y8_abort(d_y8_abt[gi]),
            .gau_valid(d_gau_v[gi]), .gau_ready(rdy[gi*3+1]), .gau_data(d_gau_d[gi]),
            .gau_sof(d_gau_sof[gi]), .gau_eol(d_gau_eol[gi]), .gau_eof(d_gau_eof[gi]),
            .gau_abort(d_gau_abt[gi]),
            .he_valid(d_he_v[gi]), .he_ready(rdy[gi*3+2]), .he_data(d_he_d[gi]),
            .he_sof(d_he_sof[gi]), .he_eol(d_he_eol[gi]), .he_eof(d_he_eof[gi]),
            .he_abort(d_he_abt[gi]),
            .st_good(d_good[gi]), .st_abort(d_abort[gi]),
            .st_he_pub(d_hepub[gi]), .st_he_rej(d_herej[gi]),
            .st_gau_abt(d_gauabt[gi])
        );
    end
    endgenerate

    // ------------------------------------------------------------------- run
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (j = 0; j < 3; j = j + 1) begin
                bi[j] <= 32'd0;
                sdone[j] <= 1'b0;
            end
            ls[0] <= 16'hACE1; ls[1] <= 16'h1D2B; ls[2] <= 16'h77E5;
            ls[3] <= 16'hACE1; ls[4] <= 16'h1D2B; ls[5] <= 16'h77E5;   // dut1 = same seeds as dut0
            ls[6] <= 16'hB33D; ls[7] <= 16'h4C9F; ls[8] <= 16'h95A7;   // dut2 = other seeds
            // +SEEDMODE selects the *matched* pattern for dut0/dut1 (and a
            // different one for the dut2 control): 0 = 75% random, 1 = other
            // random set, 2 = always ready.
            if (seedmode == 1) begin
                ls[0] <= 16'h1357; ls[1] <= 16'h2468; ls[2] <= 16'h9BDF;
                ls[3] <= 16'h1357; ls[4] <= 16'h2468; ls[5] <= 16'h9BDF;
                ls[6] <= 16'hC0DE; ls[7] <= 16'h5EED; ls[8] <= 16'h0F1D;
            end else if (seedmode == 2) begin
                ls[0] <= 16'hFFFF; ls[1] <= 16'hFFFF; ls[2] <= 16'hFFFF;
                ls[3] <= 16'hFFFF; ls[4] <= 16'hFFFF; ls[5] <= 16'hFFFF;
                ls[6] <= 16'hB33D; ls[7] <= 16'h4C9F; ls[8] <= 16'h95A7;
            end
            for (j = 0; j < 9; j = j + 1) rdy[j] <= 1'b1;
            for (j = 0; j < 9; j = j + 1) cnt[j] <= 0;
            err_ref_new <= 0; err_ctl <= 0;
            cyc <= 0; quiet <= 0; started <= 1'b0;
            first_ref_new_printed <= 1'b0;
            cfg_valid <= 1'b0; cfg_w <= 12'd0; cfg_h <= 12'd0; cfg_ph <= 2'd0;
        end else begin
            cyc <= cyc + 1;

            // configuration: one handshake beat, accepted by all three
            if (!started) begin
                if (!cfg_valid) begin
                    cfg_valid <= 1'b1;
                    cfg_w <= W[11:0]; cfg_h <= H[11:0]; cfg_ph <= 2'd0;
                end else if (d_cfg_ready[0] && d_cfg_ready[1] && d_cfg_ready[2]) begin
                    started   <= 1'b1;
                    cfg_valid <= 1'b0;
                end
            end

            // sources
            for (j = 0; j < 3; j = j + 1) begin
                if (!sdone[j] && d_s_ready[j]) begin
                    if (bi[j] == (TOT-1)) sdone[j] <= 1'b1;
                    bi[j] <= bi[j] + 32'd1;
                end
            end

            // ready patterns
            for (j = 0; j < 9; j = j + 1) begin
                ls[j]  <= {ls[j][14:0], ls[j][15] ^ ls[j][13] ^ ls[j][9]};
                rdy[j] <= (ls[j][1:0] != 2'b00);
            end

            // record tokens
            for (j = 0; j < 3; j = j + 1) begin
                if (d_y8_abt[j]  || (d_y8_v[j]  && rdy[j*3+0])) begin
                    tsk_rec(j, 0, d_y8_abt[j]  ? {1'b1, 35'd0} : {1'b0, d_y8_d[j],  d_y8_sof[j],  d_y8_eol[j],  d_y8_eof[j]});
                    if (j < 2) dump_tok(j, 0, d_y8_abt[j], d_y8_d[j], d_y8_sof[j], d_y8_eol[j], d_y8_eof[j]);
                end
                if (d_gau_abt[j] || (d_gau_v[j] && rdy[j*3+1])) begin
                    tsk_rec(j, 1, d_gau_abt[j] ? {1'b1, 35'd0} : {1'b0, d_gau_d[j], d_gau_sof[j], d_gau_eol[j], d_gau_eof[j]});
                    if (j < 2) dump_tok(j, 1, d_gau_abt[j], d_gau_d[j], d_gau_sof[j], d_gau_eol[j], d_gau_eof[j]);
                end
                if (d_he_abt[j]  || (d_he_v[j]  && rdy[j*3+2]))
                    tsk_rec(j, 2, d_he_abt[j]  ? {1'b1, 35'd0} : {1'b0, d_he_d[j],  d_he_sof[j],  d_he_eol[j],  d_he_eof[j]});
            end

            // settle / finish
            if (sdone[0] && sdone[1] && sdone[2] &&
                !d_y8_v[0] && !d_y8_v[1] && !d_y8_v[2] &&
                !d_he_v[0] && !d_he_v[1] && !d_he_v[2] &&
                !d_gau_v[0] && !d_gau_v[1] && !d_gau_v[2] &&
                !d_y8_abt[0] && !d_y8_abt[1] && !d_y8_abt[2] &&
                !d_he_abt[0] && !d_he_abt[1] && !d_he_abt[2] &&
                !d_gau_abt[0] && !d_gau_abt[1] && !d_gau_abt[2]) begin
                if (quiet >= 400) begin
                    $display("EQUIV_COUNTS dut0=%0d/%0d/%0d dut1=%0d/%0d/%0d dut2=%0d/%0d/%0d cyc=%0d",
                             cnt[0], cnt[1], cnt[2], cnt[3], cnt[4], cnt[5],
                             cnt[6], cnt[7], cnt[8], cyc);
                    for (strm = 0; strm < 3; strm = strm + 1) begin
                        $display("EQUIV_STATUS stream=%0d dut0 good=%0d abort=%0d hepub=%0d herej=%0d gauabt=%0d",
                                 strm, d_good[0], d_abort[0], d_hepub[0], d_herej[0], d_gauabt[0]);
                        $display("EQUIV_STATUS stream=%0d dut1 good=%0d abort=%0d hepub=%0d herej=%0d gauabt=%0d",
                                 strm, d_good[1], d_abort[1], d_hepub[1], d_herej[1], d_gauabt[1]);
                        $display("EQUIV_STATUS stream=%0d dut2 good=%0d abort=%0d hepub=%0d herej=%0d gauabt=%0d",
                                 strm, d_good[2], d_abort[2], d_hepub[2], d_herej[2], d_gauabt[2]);
                    end
                    // CHECK_REF_NEW: dut0 vs dut1 (must be identical)
                    for (strm = 0; strm < 3; strm = strm + 1) begin
                        if (cnt[0*3+strm] != cnt[1*3+strm]) begin
                            $display("CHECK_REF_NEW COUNT_MISMATCH stream=%0d base=%0d p4=%0d",
                                     strm, cnt[0*3+strm], cnt[1*3+strm]);
                            err_ref_new = err_ref_new + 1;
                        end else if (cnt[0*3+strm] > QD) begin
                            $display("CHECK_REF_NEW RECORD_OVERFLOW stream=%0d n=%0d", strm, cnt[0*3+strm]);
                            err_ref_new = err_ref_new + 1;
                        end else begin
                            for (k = 0; k < cnt[0*3+strm]; k = k + 1) begin
                                if (rec[(0*3+strm)*QD + k] !== rec[(1*3+strm)*QD + k]) begin
                                    if (!first_ref_new_printed)
                                        $display("CHECK_REF_NEW MISMATCH stream=%0d idx=%0d base=%h p4=%h",
                                                 strm, k, rec[(0*3+strm)*QD + k], rec[(1*3+strm)*QD + k]);
                                    first_ref_new_printed <= 1'b1;
                                    err_ref_new = err_ref_new + 1;
                                end
                            end
                        end
                    end
                    if ((d_good[0] !== d_good[1]) || (d_abort[0] !== d_abort[1]) ||
                        (d_hepub[0] !== d_hepub[1]) || (d_herej[0] !== d_herej[1]) ||
                        (d_gauabt[0] !== d_gauabt[1]) || (d_cfg_error[0] !== d_cfg_error[1]))
                        err_ref_new = err_ref_new + 1;

                    // CONTROL_REF_REF2: dut0 vs dut2 (identical RTL, other stalls)
                    for (strm = 0; strm < 3; strm = strm + 1) begin
                        if (cnt[0*3+strm] != cnt[2*3+strm]) begin
                            $display("CONTROL_REF_REF2 COUNT_DIFF stream=%0d a=%0d b=%0d",
                                     strm, cnt[0*3+strm], cnt[2*3+strm]);
                            err_ctl = err_ctl + 1;
                        end else if (cnt[0*3+strm] <= QD) begin
                            for (k = 0; k < cnt[0*3+strm]; k = k + 1) begin
                                if (rec[(0*3+strm)*QD + k] !== rec[(2*3+strm)*QD + k]) begin
                                    $display("CONTROL_REF_REF2 MISMATCH stream=%0d idx=%0d a=%h b=%h",
                                             strm, k, rec[(0*3+strm)*QD + k], rec[(2*3+strm)*QD + k]);
                                    err_ctl = err_ctl + 1;
                                end
                            end
                        end
                    end

                    if (err_ref_new == 0) $display("CHECK_REF_NEW PASS");
                    else                 $display("CHECK_REF_NEW FAIL errors=%0d", err_ref_new);
                    $display("CONTROL_REF_REF2 diffs=%0d (informational: frozen-module stall sensitivity)", err_ctl);
                    $fdisplay(fd, "STATS sm=%0d tag=%0d cyc=%0d y8_0=%0d gau_0=%0d y8_1=%0d gau_1=%0d y8_2=%0d gau_2=%0d err_ref_new=%0d err_ctl=%0d status=done",
                              seedmode, dump_tag, cyc, cnt[0], cnt[1], cnt[3], cnt[4], cnt[6], cnt[7],
                              err_ref_new, err_ctl);
                    $fclose(fd);
                    if (err_ref_new == 0) $display("TB_IMG_ALGO_EQUIV_P4 PASS");
                    else                 $display("TB_IMG_ALGO_EQUIV_P4 FAIL errors=%0d", err_ref_new);
                    $finish;
                end else begin
                    quiet <= quiet + 1;
                end
            end else begin
                quiet <= 0;
            end

            if (cyc > 120000) begin
                $display("TB_IMG_ALGO_EQUIV_P4 FAIL timeout cyc=%0d done=%0d%0d%0d", cyc, sdone[0], sdone[1], sdone[2]);
                $fdisplay(fd, "STATS sm=%0d tag=%0d cyc=%0d status=timeout", seedmode, dump_tag, cyc);
                $fclose(fd);
                $finish;
            end
        end
    end

    initial begin
        rst_n = 1'b0;
        if (!$value$plusargs("SEEDMODE=%d", seedmode)) seedmode = 0;
        repeat (8) @(posedge clk);
        rst_n = 1'b1;
    end

endmodule
