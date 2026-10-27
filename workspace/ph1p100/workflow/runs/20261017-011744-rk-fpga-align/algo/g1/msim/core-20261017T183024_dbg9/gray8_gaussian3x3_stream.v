// gray8_gaussian3x3_stream.v — 4px/beat streaming 3x3 Gaussian on Y8.
// T09.rk-align-algo. Verilog-2001, async reset, synthesizable.
//
// Frozen semantics (must match parallel/algorithms/image_algorithms_ref.py and
// the retained worktree candidate gray8_gaussian3x3_frame.v):
//   * kernel [1 2 1; 2 4 2; 1 2 1], one rounding (sum + 8) >> 4, replicate
//     borders with the same CFA-parity-preserving clamp rules as the demosaic
//     front end (left of column 0 is column 1, right of column W-1 is column
//     W-2, up of row 0 is row 1, down of row H-1 is row H-2);
//   * streaming organisation: production row y is emitted while input row y+1
//     streams; the last input row triggers the fixed flush (output row H-2 last
//     word, then all of output row H-1).  Same frame control/sideband contract
//     as bayer_raw10_demosaic4 (s_eol/s_eof exact, s_abort/s_sof-while-active/
//     misplaced sideband/over-length abort with a marker and no eof).
//   * 4 pixels per beat, fixed registered pipeline latency, stall holds data.
//
// Supported configuration (frozen): W % 4 == 0, 8 <= W <= MAX_WORDS*4,
// 2 <= H <= 2048.
// No hardware/timing claims in this package (G1 simulation; G2 small top).

module gray8_gaussian3x3_stream #(
    parameter MAX_WORDS = 512
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        cfg_valid,
    output wire        cfg_ready,
    input  wire [11:0] cfg_width,
    input  wire [11:0] cfg_height,
    output wire        cfg_error,
    input  wire        s_valid,
    output wire        s_ready,
    input  wire [31:0] s_data,
    input  wire        s_sof,
    input  wire        s_eol,
    input  wire        s_eof,
    input  wire        s_abort,
    output wire        m_valid,
    input  wire        m_ready,
    output wire [31:0] m_data,
    output wire        m_sof,
    output wire        m_eol,
    output wire        m_eof,
    output wire        m_abort,
    output wire [15:0] st_frames_good,
    output wire [15:0] st_frames_abort
);
    localparam LW = MAX_WORDS;

    // ---------------- configuration ----------------
    reg        cfg_lat;
    reg        cfg_err;
    reg [11:0] r_width, r_height;

    assign cfg_ready = rst_n && !cfg_lat;
    assign cfg_error = cfg_err;

    wire cfg_ok = cfg_lat && !cfg_err;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_lat  <= 1'b0;
            cfg_err  <= 1'b0;
            r_width  <= 12'd0;
            r_height <= 12'd0;
        end else if (cfg_valid && cfg_ready) begin
            cfg_lat  <= 1'b1;
            r_width  <= cfg_width;
            r_height <= cfg_height;
            cfg_err  <= !((cfg_width[1:0] == 2'd0) &&
                          (cfg_width >= 12'd8) &&
                          (cfg_width <= LW*4) &&
                          (cfg_height >= 12'd2) &&
                          (cfg_height <= 12'd2048));
        end
    end

    // ---------------- row-window front ----------------
    wire        prod_valid, prod_first, prod_last, prod_abort, evt_good, evt_abort;
    wire [11:0] prod_y, prod_j;
    wire [47:0] win_c, win_u, win_d;

    wire pipe_en = !(m_valid && !m_ready);

    algo_rowwin3 #(.MAX_WORDS(MAX_WORDS), .DW(32), .PARITY_CLAMP(0)) u_row (
        .clk(clk), .rst_n(rst_n),
        .cfg_width(r_width), .cfg_height(r_height), .cfg_ok(cfg_ok),
        .s_valid(s_valid), .s_ready(s_ready), .s_data(s_data),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof), .s_abort(s_abort),
        .en(pipe_en),
        .prod_valid(prod_valid), .prod_y(prod_y), .prod_j(prod_j),
        .prod_first(prod_first), .prod_last(prod_last), .prod_abort(prod_abort),
        .win_c(win_c), .win_u(win_u), .win_d(win_d),
        .evt_good(evt_good), .evt_abort(evt_abort)
    );

    // ---------------- stage P: latch production slot ----------------
    reg [47:0] p_wc, p_wu, p_wd;
    reg        p_valid, p_abort, p_sof, p_eol, p_eof;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p_wc <= 48'd0; p_wu <= 48'd0; p_wd <= 48'd0;
            p_valid <= 1'b0; p_abort <= 1'b0;
            p_sof <= 1'b0; p_eol <= 1'b0; p_eof <= 1'b0;
        end else if (pipe_en) begin
            p_valid <= prod_valid && !prod_abort;
            p_abort <= prod_valid && prod_abort;
            if (prod_valid && !prod_abort) begin
                p_wc  <= win_c;
                p_wu  <= win_u;
                p_wd  <= win_d;
                p_sof <= (prod_y == 12'd0) && (prod_j == 12'd0);
                p_eol <= prod_last;
                p_eof <= prod_last && (prod_y == r_height - 12'd1);
            end
        end
    end

    // ---------------- stage M1: horizontal weighted sums ----------------
    wire [7:0] c0 = p_wc[47:40], c1 = p_wc[39:32], c2 = p_wc[31:24];
    wire [7:0] c3 = p_wc[23:16], c4 = p_wc[15:8],  c5 = p_wc[7:0];
    wire [7:0] u0 = p_wu[47:40], u1 = p_wu[39:32], u2 = p_wu[31:24];
    wire [7:0] u3 = p_wu[23:16], u4 = p_wu[15:8],  u5 = p_wu[7:0];
    wire [7:0] d0 = p_wd[47:40], d1 = p_wd[39:32], d2 = p_wd[31:24];
    wire [7:0] d3 = p_wd[23:16], d4 = p_wd[15:8],  d5 = p_wd[7:0];

    function [10:0] hsum;
        input [7:0] l, m, r;
        begin
            hsum = {3'b0, l} + ({3'b0, m} << 1) + {3'b0, r};
        end
    endfunction

    wire [10:0] h0t = hsum(u0, u1, u2), h0m = hsum(c0, c1, c2), h0b = hsum(d0, d1, d2);
    wire [10:0] h1t = hsum(u1, u2, u3), h1m = hsum(c1, c2, c3), h1b = hsum(d1, d2, d3);
    wire [10:0] h2t = hsum(u2, u3, u4), h2m = hsum(c2, c3, c4), h2b = hsum(d2, d3, d4);
    wire [10:0] h3t = hsum(u3, u4, u5), h3m = hsum(c3, c4, c5), h3b = hsum(d3, d4, d5);

    reg [10:0] r0t, r0m, r0b, r1t, r1m, r1b, r2t, r2m, r2b, r3t, r3m, r3b;
    reg        r_valid, r_abort, r_sof, r_eol, r_eof;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r0t <= 11'd0; r0m <= 11'd0; r0b <= 11'd0;
            r1t <= 11'd0; r1m <= 11'd0; r1b <= 11'd0;
            r2t <= 11'd0; r2m <= 11'd0; r2b <= 11'd0;
            r3t <= 11'd0; r3m <= 11'd0; r3b <= 11'd0;
            r_valid <= 1'b0; r_abort <= 1'b0;
            r_sof <= 1'b0; r_eol <= 1'b0; r_eof <= 1'b0;
        end else if (pipe_en) begin
            r0t <= h0t; r0m <= h0m; r0b <= h0b;
            r1t <= h1t; r1m <= h1m; r1b <= h1b;
            r2t <= h2t; r2m <= h2m; r2b <= h2b;
            r3t <= h3t; r3m <= h3m; r3b <= h3b;
            r_valid <= p_valid; r_abort <= p_abort;
            r_sof <= p_sof; r_eol <= p_eol; r_eof <= p_eof;
        end
    end

    // ---------------- stage M2/output: vertical combine + round ----------------
    function [7:0] vcomb;
        input [10:0] t, m, b;
        reg [12:0] s;
        begin
            s = {2'b0, t} + ({2'b0, m} << 1) + {2'b0, b} + 13'd8;
            vcomb = s[11:4];
        end
    endfunction

    reg [31:0] o_data;
    reg        o_valid, o_abort, o_sof, o_eol, o_eof;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_data <= 32'd0;
            o_valid <= 1'b0; o_abort <= 1'b0;
            o_sof <= 1'b0; o_eol <= 1'b0; o_eof <= 1'b0;
        end else if (pipe_en) begin
            o_data  <= {vcomb(r3t, r3m, r3b), vcomb(r2t, r2m, r2b),
                        vcomb(r1t, r1m, r1b), vcomb(r0t, r0m, r0b)};
            o_valid <= r_valid; o_abort <= r_abort;
            o_sof <= r_sof; o_eol <= r_eol; o_eof <= r_eof;
        end
    end

    assign m_valid = o_valid;
    assign m_data  = o_data;
    assign m_sof   = o_sof;
    assign m_eol   = o_eol;
    assign m_eof   = o_eof;
    assign m_abort = o_abort;

    // ---------------- frame counters ----------------
    reg [15:0] cnt_good, cnt_abort;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_good  <= 16'd0;
            cnt_abort <= 16'd0;
        end else begin
            if (evt_good)  cnt_good  <= cnt_good + 16'd1;
            if (evt_abort) cnt_abort <= cnt_abort + 16'd1;
        end
    end
    assign st_frames_good  = cnt_good;
    assign st_frames_abort = cnt_abort;
endmodule
