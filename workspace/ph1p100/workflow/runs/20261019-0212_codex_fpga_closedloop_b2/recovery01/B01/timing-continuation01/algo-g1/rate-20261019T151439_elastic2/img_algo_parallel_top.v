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

    // Two-slot elastic RGB boundary. Occupancy alone drives upstream ready:
    // HE/Gaussian/output backpressure cannot propagate into the row-bank enable.
    // A token includes all four lanes and every sideband (including abort).
    // Pop uses the common gray enable, keeping markers aligned with its pipe.
    reg [99:0] rgb_slot0, rgb_slot1;
    reg rgb_wr, rgb_rd;
    reg [1:0] rgb_count;
    wire rgb_gray_ready;
    wire rgb_push = f_valid && f_ready;
    wire rgb_pop = (rgb_count != 0) && rgb_gray_ready;
    wire [99:0] rgb_head = rgb_rd ? rgb_slot1 : rgb_slot0;
    wire p_valid = (rgb_count != 0);
    wire p_sof = p_valid && rgb_head[99];
    wire p_eol = p_valid && rgb_head[98];
    wire p_eof = p_valid && rgb_head[97];
    wire p_abort = p_valid && rgb_head[96];
    wire [31:0] p_r = rgb_head[95:64];
    wire [31:0] p_g = rgb_head[63:32];
    wire [31:0] p_b = rgb_head[31:0];
    assign f_ready = (rgb_count != 2);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            rgb_wr<=0; rgb_rd<=0; rgb_count<=0;
        end else begin
            if(rgb_push) begin
                if(rgb_wr) rgb_slot1 <= {f_sof,f_eol,f_eof,f_abort,f_r,f_g,f_b};
                else rgb_slot0 <= {f_sof,f_eol,f_eof,f_abort,f_r,f_g,f_b};
                rgb_wr <= !rgb_wr;
            end
            if(rgb_pop) rgb_rd <= !rgb_rd;
            case({rgb_push,rgb_pop})
                2'b10: rgb_count <= rgb_count + 1'b1;
                2'b01: rgb_count <= rgb_count - 1'b1;
                default: rgb_count <= rgb_count;
            endcase
        end
    end

    // ---------------- 4 x rgb8_gray_stream (worktree candidate) ----------------
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

    // Y8 stream ready = the output buffer + both branch inputs can accept.
    // A beat is presented to all three consumers only when all can take it
    // (single shared stream: all-or-nothing transfer, no loss, no duplicates).
    wire y8_stream_ready = y8_fifo_ready && gau_s_ready && he_s_ready;
    wire y8_xfer         = g0_valid && y8_stream_ready;

    assign rgb_gray_ready = g0_s_ready && g1_s_ready && g2_s_ready && g3_s_ready;

    rgb8_gray_stream u_g0 (
        .clk(clk), .rst_n(rst_n),
        .s_valid(p_valid), .s_ready(g0_s_ready),
        .s_r(p_r[7:0]), .s_g(p_g[7:0]), .s_b(p_b[7:0]),
        .s_sof(p_sof), .s_last(p_eol),
        .m_valid(g0_valid), .m_ready(y8_stream_ready),
        .m_y(g0_y), .m_sof(g0_sof), .m_last(g0_last)
    );
    rgb8_gray_stream u_g1 (
        .clk(clk), .rst_n(rst_n),
        .s_valid(p_valid), .s_ready(g1_s_ready),
        .s_r(p_r[15:8]), .s_g(p_g[15:8]), .s_b(p_b[15:8]),
        .s_sof(p_sof), .s_last(p_eol),
        .m_valid(g1_valid), .m_ready(y8_stream_ready),
        .m_y(g1_y), .m_sof(), .m_last()
    );
    rgb8_gray_stream u_g2 (
        .clk(clk), .rst_n(rst_n),
        .s_valid(p_valid), .s_ready(g2_s_ready),
        .s_r(p_r[23:16]), .s_g(p_g[23:16]), .s_b(p_b[23:16]),
        .s_sof(p_sof), .s_last(p_eol),
        .m_valid(g2_valid), .m_ready(y8_stream_ready),
        .m_y(g2_y), .m_sof(), .m_last()
    );
    rgb8_gray_stream u_g3 (
        .clk(clk), .rst_n(rst_n),
        .s_valid(p_valid), .s_ready(g3_s_ready),
        .s_r(p_r[31:24]), .s_g(p_g[31:24]), .s_b(p_b[31:24]),
        .s_sof(p_sof), .s_last(p_eol),
        .m_valid(g3_valid), .m_ready(y8_stream_ready),
        .m_y(g3_y), .m_sof(), .m_last()
    );

    // eof/abort are two cycles behind the demosaic output (rgb8_gray_stream
    // latency, round1 pipelining): a two-stage delay matched to the module
    reg y8_eof_r, y8_abort_r, y8_eof_r1, y8_abort_r1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y8_eof_r   <= 1'b0;
            y8_abort_r <= 1'b0;
            y8_eof_r1  <= 1'b0;
            y8_abort_r1 <= 1'b0;
        end else if (!(g0_valid && !y8_stream_ready)) begin
            y8_eof_r1   <= p_eof;
            y8_abort_r1 <= p_abort;
            y8_eof_r    <= y8_eof_r1;
            y8_abort_r  <= y8_abort_r1;
        end
    end

    wire [31:0] y8_data_i = {g3_y, g2_y, g1_y, g0_y};

    // (y8_valid/y8_data/... are driven by u_obuf_y8 below)

    // ---------------- output buffers (one per port; see algo_obuf.v) ----------------
    algo_obuf #(.DW(32), .DEPTH(8)) u_obuf_y8 (
        .clk(clk), .rst_n(rst_n),
        .w_valid(y8_xfer), .w_ready(y8_fifo_ready), .w_data(y8_data_i),
        .w_sof(g0_sof), .w_eol(g0_last), .w_eof(y8_eof_r), .w_abort(y8_abort_r),
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

    // ---------------- Gaussian branch ----------------
    wire [15:0] gau_good_unused;

    gray8_gaussian3x3_stream #(.MAX_WORDS(MAX_WORDS)) u_gau (
        .clk(clk), .rst_n(rst_n),
        .cfg_valid(cfg_valid), .cfg_ready(a_cfg_ready),
        .cfg_width(cfg_width), .cfg_height(cfg_height),
        .cfg_error(a_cfg_error),
        .s_valid(y8_xfer), .s_ready(gau_s_ready), .s_data(y8_data_i),
        .s_sof(g0_sof), .s_eol(g0_last), .s_eof(y8_eof_r), .s_abort(y8_abort_r),
        .m_valid(gau_w_valid), .m_ready(gau_fifo_ready), .m_data(gau_w_data),
        .m_sof(gau_w_sof), .m_eol(gau_w_eol), .m_eof(gau_w_eof), .m_abort(gau_w_abort),
        .st_frames_good(gau_good_unused), .st_frames_abort(st_gau_abort)
    );

    // ---------------- HE branch ----------------
    wire [15:0] he_good_unused;

    gray8_he_cdfmin_frame u_he (
        .clk(clk), .rst_n(rst_n),
        .cfg_valid(cfg_valid), .cfg_ready(h_cfg_ready),
        .cfg_width(cfg_width), .cfg_height(cfg_height),
        .cfg_error(h_cfg_error),
        .s_valid(y8_xfer), .s_ready(he_s_ready), .s_data(y8_data_i),
        .s_sof(g0_sof), .s_eol(g0_last), .s_eof(y8_eof_r), .s_abort(y8_abort_r),
        .m_valid(he_w_valid), .m_ready(he_fifo_ready), .m_data(he_w_data),
        .m_sof(he_w_sof), .m_eol(he_w_eol), .m_eof(he_w_eof), .m_abort(he_w_abort),
        .st_published(st_he_published), .st_rejected(st_he_rejected),
        .lut_rd_addr(he_lut_addr), .lut_rd_data(he_lut_data)
    );
endmodule
