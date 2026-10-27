// tb_bayer_retime_check.v — INT.P4 r3 debug TB (not part of the delivered set).
// Compares bayer_raw10_demosaic4 (base) and bayer_raw10_demosaic4_p4 token by
// token with identical per-DUT beat sequences (independent sources) and the
// same ready pattern (+STALL = 75% random, aligned in time for both DUTs).
`timescale 1ns/1ps
module tb_bayer_retime_check;
    localparam W = 64, H = 48, MPW = W/4, BEATS = MPW*H, FRAMES = 2, NB = FRAMES*BEATS;

    reg clk = 0;
    always #2.6665 clk = ~clk;
    reg rst_n = 0;
    reg [15:0] elsr = 16'h1D2B;
    reg        stall_mode = 1'b0;
    always @(posedge clk) elsr <= {elsr[14:0], elsr[15] ^ elsr[13] ^ elsr[9]};
    reg [15:0] cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;
    wire b_ready = stall_mode ? ((cyc % 16'd5) != 16'd0) : 1'b1;
    wire p_ready = b_ready;

    reg  [11:0] cfg_w = W, cfg_h = H;
    reg  [1:0]  cfg_ph = 2'd0;
    reg         cfg_valid = 0;
    wire        b_cfg_ready, p_cfg_ready, b_cfg_err, p_cfg_err;
    wire        b_s_ready, p_s_ready;
    reg  [39:0] b_data = 0, p_data = 0;
    reg         b_sof = 0, b_eol = 0, b_eof = 0, p_sof = 0, p_eol = 0, p_eof = 0;
    reg         b_val = 0, p_val = 0;
    reg  [31:0] b_bi = 0, p_bi = 0;

    wire        b_v, b_sof_o, b_eol_o, b_eof_o, b_ab;
    wire [31:0] b_r, b_g, b_b;
    wire        p_v, p_sof_o, p_eol_o, p_eof_o, p_ab;
    wire [31:0] p_r, p_g, p_b;
    wire [15:0] b_good, b_abt, p_good, p_abt;

    bayer_raw10_demosaic4 #(.MAX_WORDS(512)) u_base (
        .clk(clk), .rst_n(rst_n),
        .cfg_valid(cfg_valid), .cfg_ready(b_cfg_ready),
        .cfg_width(cfg_w), .cfg_height(cfg_h), .cfg_phase(cfg_ph),
        .cfg_error(b_cfg_err),
        .s_valid(b_val), .s_ready(b_s_ready), .s_data(b_data),
        .s_sof(b_sof), .s_eol(b_eol), .s_eof(b_eof), .s_abort(1'b0),
        .m_valid(b_v), .m_ready(b_ready), .m_r(b_r), .m_g(b_g), .m_b(b_b),
        .m_sof(b_sof_o), .m_eol(b_eol_o), .m_eof(b_eof_o), .m_abort(b_ab),
        .st_frames_good(b_good), .st_frames_abort(b_abt)
    );
    bayer_raw10_demosaic4_p4 #(.MAX_WORDS(512)) u_p4 (
        .clk(clk), .rst_n(rst_n),
        .cfg_valid(cfg_valid), .cfg_ready(p_cfg_ready),
        .cfg_width(cfg_w), .cfg_height(cfg_h), .cfg_phase(cfg_ph),
        .cfg_error(p_cfg_err),
        .s_valid(p_val), .s_ready(p_s_ready), .s_data(p_data),
        .s_sof(p_sof), .s_eol(p_eol), .s_eof(p_eof), .s_abort(1'b0),
        .m_valid(p_v), .m_ready(p_ready), .m_r(p_r), .m_g(p_g), .m_b(p_b),
        .m_sof(p_sof_o), .m_eol(p_eol_o), .m_eof(p_eof_o), .m_abort(p_ab),
        .st_frames_good(p_good), .st_frames_abort(p_abt)
    );

    function [9:0] px; input [31:0] b; input [2:0] kk;
        begin px = ((b * 32'd37) + ({29'd0, kk} * 32'd211) + ((b >> 5) * 32'd13) + 32'd5) & 32'h3FF; end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            b_bi <= 0; p_bi <= 0; b_val <= 0; p_val <= 0;
        end else if (cfg_valid) begin
            if (b_bi < NB) begin
                b_val  <= 1'b1;
                b_data <= {px(b_bi,3'd3), px(b_bi,3'd2), px(b_bi,3'd1), px(b_bi,3'd0)};
                b_sof  <= (b_bi % BEATS) == 0;
                b_eol  <= ((b_bi % MPW) == (MPW-1));
                b_eof  <= (b_bi % BEATS) == (BEATS-1);
                if (b_s_ready) b_bi <= b_bi + 1;
            end else b_val <= 1'b0;
            if (p_bi < NB) begin
                p_val  <= 1'b1;
                p_data <= {px(p_bi,3'd3), px(p_bi,3'd2), px(p_bi,3'd1), px(p_bi,3'd0)};
                p_sof  <= (p_bi % BEATS) == 0;
                p_eol  <= ((p_bi % MPW) == (MPW-1));
                p_eof  <= (p_bi % BEATS) == (BEATS-1);
                if (p_s_ready) p_bi <= p_bi + 1;
            end else p_val <= 1'b0;
        end
    end

    reg [99:0] rb [0:4095];
    reg [99:0] rp [0:4095];
    integer nb = 0, np = 0, err = 0, k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            nb <= 0; np <= 0;
        end else begin
            if (b_v && b_ready) begin
                rb[nb] <= {b_ab, b_eof_o, b_eol_o, b_sof_o, b_r, b_g, b_b};
                nb <= nb + 1;
            end
            if (p_v && p_ready) begin
                rp[np] <= {p_ab, p_eof_o, p_eol_o, p_sof_o, p_r, p_g, p_b};
                np <= np + 1;
            end
        end
    end

    initial begin
        if ($test$plusargs("STALL")) stall_mode = 1'b1;
        repeat (8) @(posedge clk);
        rst_n = 1;
        cfg_valid = 1;
        repeat (NB*2 + 1200) @(posedge clk);
        for (k = 0; k < ((nb < np) ? nb : np); k = k + 1) begin
            if (rb[k] !== rp[k]) begin
                err = err + 1;
                if (err <= 5)
                    $display("BAYER_MISMATCH k=%0d base[sof=%b eol=%b eof=%b ab=%b r=%h g=%h b=%h] p4[same]=%b/%b/%b/%b %h/%h/%h",
                             k, rb[k][96], rb[k][97], rb[k][98], rb[k][99], rb[k][95:64], rb[k][63:32], rb[k][31:0],
                             rp[k][96], rp[k][97], rp[k][98], rp[k][99], rp[k][95:64], rp[k][63:32], rp[k][31:0]);
            end
        end
        $display("BAYER_COUNTS base=%0d p4=%0d err=%0d", nb, np, err);
        if (err == 0 && nb == np) $display("TB_BAYER_RETIME_CHECK PASS");
        else                      $display("TB_BAYER_RETIME_CHECK FAIL errors=%0d", err);
        $finish;
    end
endmodule
