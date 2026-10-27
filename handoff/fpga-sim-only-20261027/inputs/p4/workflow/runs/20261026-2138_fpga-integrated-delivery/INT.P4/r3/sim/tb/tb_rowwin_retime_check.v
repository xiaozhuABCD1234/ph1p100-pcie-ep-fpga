// tb_rowwin_retime_check.v — INT.P4 r3 debug TB (not part of the delivered set).
// Drives algo_rowwin3 (base) and algo_rowwin3_p4 with *identical per-DUT beat
// sequences* (independent sources, each holding its beat until that DUT's
// s_ready) and the same en pattern, then compares the production token
// sequences in order (win_c/u/d + y/j/first/last/abort).  The +1 fixed latency
// is allowed because the streams are compared in order.
`timescale 1ns/1ps
module tb_rowwin_retime_check;
    localparam W = 64, H = 48, MPW = W/4, BEATS = MPW*H;

    reg clk = 0;
    always #2.6665 clk = ~clk;
    reg rst_n = 0;
    reg [15:0] elsr = 16'hACE1;
    reg        en_i = 1'b1;
    always @(posedge clk) begin
        elsr <= {elsr[14:0], elsr[15] ^ elsr[13] ^ elsr[9]};
        en_i <= (elsr[1:0] != 2'b00);
    end

    reg  [11:0] cfg_w = W, cfg_h = H;
    reg         cfg_ok = 1'b0;

    wire        b_s_ready, p_s_ready;
    wire        b_pv, b_pf, b_pl, b_pa, b_eg, b_ea;
    wire [11:0] b_py, b_pj;
    wire [59:0] b_wc, b_wu, b_wd;
    wire        p_pv, p_pf, p_pl, p_pa, p_eg, p_ea;
    wire [11:0] p_py, p_pj;
    wire [59:0] p_wc, p_wu, p_wd;

    reg  [39:0] b_data = 0, p_data = 0;
    reg         b_sof = 0, b_eol = 0, b_eof = 0, p_sof = 0, p_eol = 0, p_eof = 0;
    reg  [31:0] b_bi = 0, p_bi = 0;
    reg         b_val = 1'b0, p_val = 1'b0;

    algo_rowwin3 #(.MAX_WORDS(512), .DW(40), .PARITY_CLAMP(1)) u_base (
        .clk(clk), .rst_n(rst_n),
        .cfg_width(cfg_w), .cfg_height(cfg_h), .cfg_ok(cfg_ok),
        .s_valid(b_val), .s_ready(b_s_ready), .s_data(b_data),
        .s_sof(b_sof), .s_eol(b_eol), .s_eof(b_eof), .s_abort(1'b0),
        .en(en_i),
        .prod_valid(b_pv), .prod_y(b_py), .prod_j(b_pj),
        .prod_first(b_pf), .prod_last(b_pl), .prod_abort(b_pa),
        .win_c(b_wc), .win_u(b_wu), .win_d(b_wd),
        .evt_good(b_eg), .evt_abort(b_ea)
    );
    algo_rowwin3_p4 #(.MAX_WORDS(512), .DW(40), .PARITY_CLAMP(1)) u_p4 (
        .clk(clk), .rst_n(rst_n),
        .cfg_width(cfg_w), .cfg_height(cfg_h), .cfg_ok(cfg_ok),
        .s_valid(p_val), .s_ready(p_s_ready), .s_data(p_data),
        .s_sof(p_sof), .s_eol(p_eol), .s_eof(p_eof), .s_abort(1'b0),
        .en(en_i),
        .prod_valid(p_pv), .prod_y(p_py), .prod_j(p_pj),
        .prod_first(p_pf), .prod_last(p_pl), .prod_abort(p_pa),
        .win_c(p_wc), .win_u(p_wu), .win_d(p_wd),
        .evt_good(p_eg), .evt_abort(p_ea)
    );

    function [9:0] px; input [31:0] b; input [2:0] kk;
        begin px = ((b * 32'd37) + ({29'd0, kk} * 32'd211) + ((b >> 5) * 32'd13) + 32'd5) & 32'h3FF; end
    endfunction

    // independent per-DUT source (same beat sequence, each holds until its own ready)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            b_bi <= 0; p_bi <= 0; b_val <= 1'b0; p_val <= 1'b0;
        end else if (cfg_ok) begin
            if (b_bi < 2*BEATS) begin
                b_val <= 1'b1;
                b_data <= {px(b_bi,3'd3), px(b_bi,3'd2), px(b_bi,3'd1), px(b_bi,3'd0)};
                b_sof  <= (b_bi % BEATS) == 0;
                b_eol  <= ((b_bi % MPW) == (MPW-1));
                b_eof  <= (b_bi % BEATS) == (BEATS-1);
                if (b_s_ready) b_bi <= b_bi + 1;
            end else begin
                b_val <= 1'b0;
            end
            if (p_bi < 2*BEATS) begin
                p_val <= 1'b1;
                p_data <= {px(p_bi,3'd3), px(p_bi,3'd2), px(p_bi,3'd1), px(p_bi,3'd0)};
                p_sof  <= (p_bi % BEATS) == 0;
                p_eol  <= ((p_bi % MPW) == (MPW-1));
                p_eof  <= (p_bi % BEATS) == (BEATS-1);
                if (p_s_ready) p_bi <= p_bi + 1;
            end else begin
                p_val <= 1'b0;
            end
        end
    end

    reg [56:0] rb [0:2047];
    reg [56:0] rp [0:2047];
    integer nb = 0, np = 0, err = 0, k;

    // first-production trace with the internal read state
    integer shown = 0;
    always @(posedge clk) begin
        if (rst_n && (b_pv === 1'b1 || p_pv === 1'b1) && shown < 10) begin
            shown = shown + 1;
            $display("TRACE t=%0d en=%b b[pv=%b y=%0d j=%0d wc=%h] evt_en=%b ra0=%0d rb0=%h cbq=%0d cpa_b=%0d | p[pv=%b y=%0d j=%0d wc=%h] evt_en=%b ra0_r=%0d rb0=%h cbq=%0d cbq_d=%0d",
                     $time, en_i,
                     b_pv, b_py, b_pj, b_wc[9:0],
                     u_base.evt_en, u_base.ra0, u_base.rb0[9:0], u_base.cbq, u_base.cpa_b,
                     p_pv, p_py, p_pj, p_wc[9:0],
                     u_p4.evt_en, u_p4.ra0_r, u_p4.rb0[9:0], u_p4.cbq, u_p4.cbq_d);
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            nb <= 0; np <= 0;
        end else begin
            if (b_pv === 1'b1 && en_i === 1'b1) begin
                rb[nb] <= {b_pa, b_pl, b_pf, b_pj, b_py, b_wc[9:0], b_wu[9:0], b_wd[9:0]};
                nb <= nb + 1;
            end
            if (p_pv === 1'b1 && en_i === 1'b1) begin
                rp[np] <= {p_pa, p_pl, p_pf, p_pj, p_py, p_wc[9:0], p_wu[9:0], p_wd[9:0]};
                np <= np + 1;
            end
        end
    end

    initial begin
        repeat (8) @(posedge clk);
        rst_n = 1;
        cfg_ok = 1'b1;
        repeat (4*BEATS + 800) @(posedge clk);
        for (k = 0; k < ((nb < np) ? nb : np); k = k + 1) begin
            if (rb[k] !== rp[k]) begin
                err = err + 1;
                if (err <= 5)
                    $display("RETIME_MISMATCH k=%0d base[y=%0d j=%0d f=%0b l=%0b a=%0b wc=%h wu=%h wd=%h] p4[y=%0d j=%0d f=%0b l=%0b a=%0b wc=%h wu=%h wd=%h]",
                             k,
                             rb[k][41:30], rb[k][53:42], rb[k][54], rb[k][55], rb[k][56],
                             rb[k][29:20], rb[k][19:10], rb[k][9:0],
                             rp[k][41:30], rp[k][53:42], rp[k][54], rp[k][55], rp[k][56],
                             rp[k][29:20], rp[k][19:10], rp[k][9:0]);
            end
        end
        $display("RETIME_COUNTS base=%0d p4=%0d err=%0d", nb, np, err);
        if (err == 0 && nb == np) $display("TB_ROW_WIN_RETIME_CHECK PASS");
        else                      $display("TB_ROW_WIN_RETIME_CHECK FAIL errors=%0d", err);
        $finish;
    end
endmodule
