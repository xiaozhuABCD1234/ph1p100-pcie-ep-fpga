// img_algo_parallel_top.v — T09.rk-align-algo hardware-parallel organisation of
// the three R2 preprocessing algorithms.
// Verilog-2001, async reset, synthesizable.  No IP, no pins inside.
//
// Structure (frozen, see algo/change-report.md):
//
//   RAW10 4px/beat + sidebands
//        |
//        v
//   bayer_raw10_demosaic4            (Bayer -> RGB8 4px, 3-bank row window)
//        |  4 x RGB8 lanes
//        v
//   4 x rgb8_gray_stream (worktree candidate, provenance in
//        fpga/csi2/src/img/PROVENANCE.md)   -> Y8 4px stream (grayscale result)
//        |
//        +----------------------------+---------------------------+
//        v (gray output)              v (Gaussian branch)         v (HE branch)
//     y8_* 4px stream        gray8_gaussian3x3_stream     gray8_he_cdfmin_frame
//                            (3x3, own row banks)         (4-bank histogram,
//                                                          ping-pong CDF-min LUT)
//
// The two remaining algorithms run as independent hardware branches on the same
// shared 4px stream; all three outputs are produced concurrently, one 4-pixel
// beat per accepted input beat plus the fixed frame flush.  Backpressure: any
// output ready low stalls the shared stream (single input stream design); the
// arithmetic units themselves are independent and never serialise.
//
// Sidebands: y8_/gau_/he_ *_sof/_eol/_eof are aligned with their data beats;
// *_abort is a one-cycle marker emitted after the beats accepted before an
// aborted frame have drained (the frame never gets an eof).
//
// Supported configuration (frozen): W%4==0, 8<=W<=MAX_WORDS*4, 2<=H<=2048.
// Throughput at one beat/cycle: 4 px/cycle; budget notes in build-entry.md.

module img_algo_parallel_top #(
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

    // ---------------- demosaic front end (RGB8 4px) ----------------
    wire        f_valid;
    wire        f_ready;
    wire [31:0] f_r, f_g, f_b;
    wire        f_sof, f_eol, f_eof, f_abort;

    bayer_raw10_demosaic4 #(.MAX_WORDS(MAX_WORDS)) u_front (
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

    // ---------------- 4 x rgb8_gray_stream (worktree candidate) ----------------
    wire        g0_s_ready, g1_s_ready, g2_s_ready, g3_s_ready;
    wire        g0_valid, g1_valid, g2_valid, g3_valid;
    wire [7:0]  g0_y, g1_y, g2_y, g3_y;
    wire        g0_sof, g0_last;
    wire        gau_s_ready;
    wire        he_s_ready;

    // Y8 stream ready = all three consumers (gray port, Gaussian, HE) can accept
    wire y8_stream_ready = y8_ready && gau_s_ready && he_s_ready;

    assign f_ready = g0_s_ready && g1_s_ready && g2_s_ready && g3_s_ready;

    rgb8_gray_stream u_g0 (
        .clk(clk), .rst_n(rst_n),
        .s_valid(f_valid), .s_ready(g0_s_ready),
        .s_r(f_r[7:0]), .s_g(f_g[7:0]), .s_b(f_b[7:0]),
        .s_sof(f_sof), .s_last(f_eol),
        .m_valid(g0_valid), .m_ready(y8_stream_ready),
        .m_y(g0_y), .m_sof(g0_sof), .m_last(g0_last)
    );
    rgb8_gray_stream u_g1 (
        .clk(clk), .rst_n(rst_n),
        .s_valid(f_valid), .s_ready(g1_s_ready),
        .s_r(f_r[15:8]), .s_g(f_g[15:8]), .s_b(f_b[15:8]),
        .s_sof(f_sof), .s_last(f_eol),
        .m_valid(g1_valid), .m_ready(y8_stream_ready),
        .m_y(g1_y), .m_sof(), .m_last()
    );
    rgb8_gray_stream u_g2 (
        .clk(clk), .rst_n(rst_n),
        .s_valid(f_valid), .s_ready(g2_s_ready),
        .s_r(f_r[23:16]), .s_g(f_g[23:16]), .s_b(f_b[23:16]),
        .s_sof(f_sof), .s_last(f_eol),
        .m_valid(g2_valid), .m_ready(y8_stream_ready),
        .m_y(g2_y), .m_sof(), .m_last()
    );
    rgb8_gray_stream u_g3 (
        .clk(clk), .rst_n(rst_n),
        .s_valid(f_valid), .s_ready(g3_s_ready),
        .s_r(f_r[31:24]), .s_g(f_g[31:24]), .s_b(f_b[31:24]),
        .s_sof(f_sof), .s_last(f_eol),
        .m_valid(g3_valid), .m_ready(y8_stream_ready),
        .m_y(g3_y), .m_sof(), .m_last()
    );

    // eof/abort are one cycle behind the Y8 data (rgb8_gray_stream latency)
    reg y8_eof_r, y8_abort_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y8_eof_r   <= 1'b0;
            y8_abort_r <= 1'b0;
        end else if (!(g0_valid && !y8_stream_ready)) begin
            y8_eof_r   <= f_eof;
            y8_abort_r <= f_abort;
        end
    end

    wire [31:0] y8_data_i = {g3_y, g2_y, g1_y, g0_y};

    assign y8_valid = g0_valid;
    assign y8_data  = y8_data_i;
    assign y8_sof   = g0_sof;
    assign y8_eol   = g0_last;
    assign y8_eof   = y8_eof_r;
    assign y8_abort = y8_abort_r;

    // ---------------- Gaussian branch ----------------
    wire [15:0] gau_good_unused;

    gray8_gaussian3x3_stream #(.MAX_WORDS(MAX_WORDS)) u_gau (
        .clk(clk), .rst_n(rst_n),
        .cfg_valid(cfg_valid), .cfg_ready(a_cfg_ready),
        .cfg_width(cfg_width), .cfg_height(cfg_height),
        .cfg_error(a_cfg_error),
        .s_valid(g0_valid), .s_ready(gau_s_ready), .s_data(y8_data_i),
        .s_sof(g0_sof), .s_eol(g0_last), .s_eof(y8_eof_r), .s_abort(y8_abort_r),
        .m_valid(gau_valid), .m_ready(gau_ready), .m_data(gau_data),
        .m_sof(gau_sof), .m_eol(gau_eol), .m_eof(gau_eof), .m_abort(gau_abort),
        .st_frames_good(gau_good_unused), .st_frames_abort(st_gau_abort)
    );

    // ---------------- HE branch ----------------
    wire [15:0] he_good_unused;

    gray8_he_cdfmin_frame u_he (
        .clk(clk), .rst_n(rst_n),
        .cfg_valid(cfg_valid), .cfg_ready(h_cfg_ready),
        .cfg_width(cfg_width), .cfg_height(cfg_height),
        .cfg_error(h_cfg_error),
        .s_valid(g0_valid), .s_ready(he_s_ready), .s_data(y8_data_i),
        .s_sof(g0_sof), .s_eol(g0_last), .s_eof(y8_eof_r), .s_abort(y8_abort_r),
        .m_valid(he_valid), .m_ready(he_ready), .m_data(he_data),
        .m_sof(he_sof), .m_eol(he_eol), .m_eof(he_eof), .m_abort(he_abort),
        .st_published(st_he_published), .st_rejected(st_he_rejected),
        .lut_rd_addr(he_lut_addr), .lut_rd_data(he_lut_data)
    );
endmodule
