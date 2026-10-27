// img_algo_parallel_top_p4.v — INT.P4 round2 TIMING-ONLY derived variant of
// fpga/csi2/src/img/img_algo_parallel_top.v (base file read-only this round;
// base sha256 recorded in INT.P4-r2-manifest.json).
//
// Identical module name/ports/parameters to the base module: the same
// three-algorithm organisation, the same four rgb8_gray_stream lanes, the same
// Gaussian and HE branches, the same three algo_obuf output buffers and the same
// all-or-nothing shared-stream semantics (a beat is offered to all three
// consumers only when all three can take it; no beat is lost or duplicated).
//
// WHY THIS FILE EXISTS (INT.P4 r1 G2 failure E1)
// ----------------------------------------------
// r1 synthesis: u_p1/u_algo/u_obuf_gau/count_reg[0] -> u_p1/u_algo/u_front/
// u_row/rb0_reg[0].d = 6.818ns (net 4.199ns, fanout 320, 8 levels).  The
// all-or-nothing ready of the shared stream reached the front-end row-buffer
// path combinationally.  Two registered boundaries are added:
//
//   * u_front is the derived bayer_raw10_demosaic4_p4 (2-beat elastic output
//     stage; its internal pipeline enable no longer depends on m_ready).  This
//     is the only unavoidable submodule variant: the remaining ~4.6ns of the
//     failing chain (pipe_en -> en -> evt_en -> row-buffer read address ->
//     DRAM read -> bank mux -> rb0.d) lives inside that module.
//   * stage B: a 2-beat elastic slice between the four gray streams and the
//     three output consumers.  The ready presented to the gray streams comes
//     from stage B's own count register, so the output-FIFO occupancy /
//     Gaussian / HE ready network no longer reaches the gray-stream pipeline
//     enables combinationally.
//
// No CDC, no asynchronous FIFO, no clock change, no timing exception,
// no change of pixel or frame semantics.  Observable latency may grow by a few
// clocks; data order and sof/eol/eof/abort markers are unchanged (equivalence
// evidence: tb_img_algo_equiv_p4.v, same stimulus, compared beat by beat).
//
// INT.P4 ROUND 3 (r3) — additional timing-derived instance change:
//   * u_front (bayer_raw10_demosaic4_p4) now instantiates algo_rowwin3_p4 and
//     u_gau is the derived gray8_gaussian3x3_stream_p4 (same module semantics;
//     its u_row is algo_rowwin3_p4).  Both row-window fronts register the
//     320-deep LUT-RAM read address/bank and add the SAME fixed +1 cycle to
//     win_*/prod_*, which removes the r2 worst path (row-buffer read
//     enable/address + LUT-RAM read mux in one cycle).  All arithmetic,
//     all-or-nothing rules, obufs, HE branch, port list and stage B are
//     unchanged; only the fixed cycle of latency is new.

module img_algo_parallel_top_p4 #(
    parameter MAX_WORDS = 512
)(
    input  wire        clk,
    input  wire        rst_n,
    // configuration (latched once; cfg_error=1 on unsupported geometry)
    input  wire        cfg_valid,
    output wire        cfg_ready,
    input  wire [11:0] cfg_width,
    input  wire [11:0] cfg_height,
    input  wire [1:0]  cfg_phase,
    output wire        cfg_error,
    // RAW10 4px input stream
    input  wire        s_valid,
    output wire        s_ready,
    input  wire [39:0] s_data,
    input  wire        s_sof,
    input  wire        s_eol,
    input  wire        s_eof,
    input  wire        s_abort,
    // grayscale (Y8) output stream
    output wire        y8_valid,
    input  wire        y8_ready,
    output wire [31:0] y8_data,
    output wire        y8_sof,
    output wire        y8_eol,
    output wire        y8_eof,
    output wire        y8_abort,
    // Gaussian (Y8) output stream
    output wire        gau_valid,
    input  wire        gau_ready,
    output wire [31:0] gau_data,
    output wire        gau_sof,
    output wire        gau_eol,
    output wire        gau_eof,
    output wire        gau_abort,
    // HE (Y8) output stream
    output wire        he_valid,
    input  wire        he_ready,
    output wire [31:0] he_data,
    output wire        he_sof,
    output wire        he_eol,
    output wire        he_eof,
    output wire        he_abort,
    // status / monitor
    output wire [15:0] st_frames_good,
    output wire [15:0] st_frames_abort,
    output wire [15:0] st_he_published,
    output wire [15:0] st_he_rejected,
    output wire [15:0] st_gau_abort,
    input  wire [7:0]  he_lut_addr,
    output wire [7:0]  he_lut_data
);
    // ---------------- config distribution ----------------
    wire f_cfg_ready, a_cfg_ready, h_cfg_ready;
    wire f_cfg_error, a_cfg_error, h_cfg_error;

    assign cfg_ready = f_cfg_ready && a_cfg_ready && h_cfg_ready;
    assign cfg_error = f_cfg_error || a_cfg_error || h_cfg_error;

    // ---------------- demosaic front end (derived variant) ----------------
    wire        f_valid;
    wire        f_ready;
    wire [31:0] f_r, f_g, f_b;
    wire        f_sof, f_eol, f_eof, f_abort;

    bayer_raw10_demosaic4_p4 #(.MAX_WORDS(MAX_WORDS)) u_front (
        .clk(clk), .rst_n(rst_n),
        .cfg_valid(cfg_valid), .cfg_ready(f_cfg_ready),
        .cfg_width(cfg_width), .cfg_height(cfg_height), .cfg_phase(cfg_phase),
        .cfg_error(f_cfg_error),
        .s_valid(s_valid), .s_ready(s_ready), .s_data(s_data),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof), .s_abort(s_abort),
        .m_valid(f_valid), .m_ready(f_ready),
        .m_r(f_r), .m_g(f_g), .m_b(f_b),
        .m_sof(f_sof), .m_eol(f_eol), .m_eof(f_eof), .m_abort(f_abort),
        .st_frames_good(st_frames_good), .st_frames_abort(st_frames_abort)
    );

    // ---------------- 4 x rgb8_gray_stream (unchanged) ----------------
    wire        g0_s_ready, g1_s_ready, g2_s_ready, g3_s_ready;
    wire        g0_valid, g1_valid, g2_valid, g3_valid;
    wire [7:0]  g0_y, g1_y, g2_y, g3_y;
    wire        g0_sof, g0_last;
    wire        gau_s_ready;
    wire        he_s_ready;
    wire        y8_fifo_ready;
    wire        gau_fifo_ready;
    wire        he_fifo_ready;
    wire        gau_w_valid, gau_w_sof, gau_w_eol, gau_w_eof, gau_w_abort;
    wire [31:0] gau_w_data;
    wire        he_w_valid, he_w_sof, he_w_eol, he_w_eof, he_w_abort;
    wire [31:0] he_w_data;

    // ---------------- stage B: elastic boundary (the only handshake change) ----
    // The gray streams see a registered ready; the three consumers see a
    // registered head.  The all-or-nothing transfer rule is unchanged: a beat
    // leaves stage B only when the selected output buffer AND both unselected
    // branches can take it.
    wire        b_s_ready;             // stage B ready towards the gray streams
    wire        b_valid;               // stage B head valid
    wire [35:0] b_data;                // {abort, eof, eol, sof, y8_data[31:0]}
    wire        y8_stream_ready = y8_fifo_ready && gau_s_ready && he_s_ready;
    wire        y8_xfer       = b_valid && y8_stream_ready;

    assign f_ready = g0_s_ready && g1_s_ready && g2_s_ready && g3_s_ready;

    rgb8_gray_stream u_g0 (
        .clk(clk), .rst_n(rst_n),
        .s_valid(f_valid), .s_ready(g0_s_ready),
        .s_r(f_r[7:0]), .s_g(f_g[7:0]), .s_b(f_b[7:0]),
        .s_sof(f_sof), .s_last(f_eol),
        .m_valid(g0_valid), .m_ready(b_s_ready),
        .m_y(g0_y), .m_sof(g0_sof), .m_last(g0_last)
    );
    rgb8_gray_stream u_g1 (
        .clk(clk), .rst_n(rst_n),
        .s_valid(f_valid), .s_ready(g1_s_ready),
        .s_r(f_r[15:8]), .s_g(f_g[15:8]), .s_b(f_b[15:8]),
        .s_sof(f_sof), .s_last(f_eol),
        .m_valid(g1_valid), .m_ready(b_s_ready),
        .m_y(g1_y), .m_sof(), .m_last()
    );
    rgb8_gray_stream u_g2 (
        .clk(clk), .rst_n(rst_n),
        .s_valid(f_valid), .s_ready(g2_s_ready),
        .s_r(f_r[23:16]), .s_g(f_g[23:16]), .s_b(f_b[23:16]),
        .s_sof(f_sof), .s_last(f_eol),
        .m_valid(g2_valid), .m_ready(b_s_ready),
        .m_y(g2_y), .m_sof(), .m_last()
    );
    rgb8_gray_stream u_g3 (
        .clk(clk), .rst_n(rst_n),
        .s_valid(f_valid), .s_ready(g3_s_ready),
        .s_r(f_r[31:24]), .s_g(f_g[31:24]), .s_b(f_b[31:24]),
        .s_sof(f_sof), .s_last(f_eol),
        .m_valid(g3_valid), .m_ready(b_s_ready),
        .m_y(g3_y), .m_sof(), .m_last()
    );

    // eof/abort are two cycles behind the demosaic output (rgb8_gray_stream
    // latency): a two-stage delay clocked by the gray-stream advance, exactly as
    // in the base file.  The advance is now driven by stage B's registered ready.
    reg y8_eof_r, y8_abort_r, y8_eof_r1, y8_abort_r1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y8_eof_r   <= 1'b0;
            y8_abort_r <= 1'b0;
            y8_eof_r1  <= 1'b0;
            y8_abort_r1 <= 1'b0;
        end else if (!(g0_valid && !b_s_ready)) begin
            y8_eof_r1   <= f_eof;
            y8_abort_r1 <= f_abort;
            y8_eof_r    <= y8_eof_r1;
            y8_abort_r  <= y8_abort_r1;
        end
    end

    wire [31:0] y8_data_i = {g3_y, g2_y, g1_y, g0_y};

    int_p4_elastic_beats #(.DW(36)) u_stage_b (
        .clk(clk), .rst_n(rst_n),
        .s_valid(g0_valid), .s_ready(b_s_ready),
        .s_data({y8_abort_r, y8_eof_r, g0_last, g0_sof, y8_data_i}),
        .m_valid(b_valid), .m_ready(y8_stream_ready), .m_data(b_data)
    );

    // ---------------- output buffers (one per port; see algo_obuf.v) ----------------
    algo_obuf #(.DW(32), .DEPTH(8)) u_obuf_y8 (
        .clk(clk), .rst_n(rst_n),
        .w_valid(y8_xfer), .w_ready(y8_fifo_ready), .w_data(b_data[31:0]),
        .w_sof(b_data[32]), .w_eol(b_data[33]), .w_eof(b_data[34]), .w_abort(b_data[35]),
        .r_valid(y8_valid), .r_ready(y8_ready), .r_data(y8_data),
        .r_sof(y8_sof), .r_eol(y8_eol), .r_eof(y8_eof), .r_abort(y8_abort)
    );

    algo_obuf #(.DW(32), .DEPTH(8)) u_obuf_gau (
        .clk(clk), .rst_n(rst_n),
        .w_valid(gau_w_valid), .w_ready(gau_fifo_ready), .w_data(gau_w_data),
        .w_sof(gau_w_sof), .w_eol(gau_w_eol), .w_eof(gau_w_eof), .w_abort(gau_w_abort),
        .r_valid(gau_valid), .r_ready(gau_ready), .r_data(gau_data),
        .r_sof(gau_sof), .r_eol(gau_eol), .r_eof(gau_eof), .r_abort(gau_abort)
    );

    algo_obuf #(.DW(32), .DEPTH(8)) u_obuf_he (
        .clk(clk), .rst_n(rst_n),
        .w_valid(he_w_valid), .w_ready(he_fifo_ready), .w_data(he_w_data),
        .w_sof(he_w_sof), .w_eol(he_w_eol), .w_eof(he_w_eof), .w_abort(he_w_abort),
        .r_valid(he_valid), .r_ready(he_ready), .r_data(he_data),
        .r_sof(he_sof), .r_eol(he_eol), .r_eof(he_eof), .r_abort(he_abort)
    );

    // ---------------- Gaussian branch (unchanged) ----------------
    wire [15:0] gau_good_unused;

    // r3: derived Gaussian branch (handshake/instance-only variant of the base
    // gray8_gaussian3x3_stream; its u_row is the retimed algo_rowwin3_p4)
    gray8_gaussian3x3_stream_p4 #(.MAX_WORDS(MAX_WORDS)) u_gau (
        .clk(clk), .rst_n(rst_n),
        .cfg_valid(cfg_valid), .cfg_ready(a_cfg_ready),
        .cfg_width(cfg_width), .cfg_height(cfg_height),
        .cfg_error(a_cfg_error),
        .s_valid(y8_xfer), .s_ready(gau_s_ready), .s_data(b_data[31:0]),
        .s_sof(b_data[32]), .s_eol(b_data[33]), .s_eof(b_data[34]),
        .s_abort(b_data[35]),
        .m_valid(gau_w_valid), .m_ready(gau_fifo_ready), .m_data(gau_w_data),
        .m_sof(gau_w_sof), .m_eol(gau_w_eol), .m_eof(gau_w_eof),
        .m_abort(gau_w_abort),
        .st_frames_good(gau_good_unused), .st_frames_abort(st_gau_abort)
    );

    // ---------------- HE branch (unchanged) ----------------
    wire [15:0] he_good_unused;

    gray8_he_cdfmin_frame u_he (
        .clk(clk), .rst_n(rst_n),
        .cfg_valid(cfg_valid), .cfg_ready(h_cfg_ready),
        .cfg_width(cfg_width), .cfg_height(cfg_height),
        .cfg_error(h_cfg_error),
        .s_valid(y8_xfer), .s_ready(he_s_ready), .s_data(b_data[31:0]),
        .s_sof(b_data[32]), .s_eol(b_data[33]), .s_eof(b_data[34]),
        .s_abort(b_data[35]),
        .m_valid(he_w_valid), .m_ready(he_fifo_ready), .m_data(he_w_data),
        .m_sof(he_w_sof), .m_eol(he_w_eol), .m_eof(he_w_eof),
        .m_abort(he_w_abort),
        .st_published(st_he_published), .st_rejected(st_he_rejected),
        .lut_rd_addr(he_lut_addr), .lut_rd_data(he_lut_data)
    );
endmodule
