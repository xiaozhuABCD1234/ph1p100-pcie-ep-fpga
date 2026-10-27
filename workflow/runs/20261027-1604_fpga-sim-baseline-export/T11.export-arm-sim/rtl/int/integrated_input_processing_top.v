// integrated_input_processing_top.v — INT.P1 real input & processing integration.
// Wraps the existing three-algorithm parallel block (img_algo_parallel_top) and
// adds RAW10 packing correction, mode/output routing and RAW bypass.  Formats
// are kept distinct: raw output carries packed/unpacked RAW samples, processed
// output carries Y8 bytes.  Mode switching is gated by cfg_valid and only takes
// effect at a frame boundary (idle) to avoid mixing frames.

module integrated_input_processing_top #(
    parameter MAX_WORDS = 512,
    parameter WIDTH     = 1920,
    parameter HEIGHT    = 1080
)(
    input  wire        clk,
    input  wire        rst_n,

    // configuration
    input  wire        cfg_valid,
    output wire        cfg_ready,
    input  wire [11:0] cfg_width,
    input  wire [11:0] cfg_height,
    input  wire [1:0]  cfg_phase,
    input  wire [2:0]  cfg_mode,   // 0 raw passthrough,1 gray,2 gaussian,3 HE,4 raw bypass
    output wire        cfg_error,

    // RAW10 4-sample input stream
    input  wire        s_valid,
    output wire        s_ready,
    input  wire [39:0] s_data,
    input  wire        s_sof,
    input  wire        s_eol,
    input  wire        s_eof,
    input  wire        s_abort,

    // selected output stream
    input  wire        m_ready,
    output wire        m_valid,
    output wire [2:0]  m_mode,
    output wire        m_is_raw,
    output wire [39:0] m_raw_data,
    output wire [31:0] m_proc_data,
    output wire        m_sof,
    output wire        m_eol,
    output wire        m_eof,
    output wire        m_abort,

    // packed RAW10 byte stream for A+ entrance
    input  wire        pk_ready,
    output wire        pk_valid,
    output wire [39:0] pk_data,
    output wire        pk_sof,
    output wire        pk_eol,
    output wire        pk_eof,
    output wire        pk_abort,

    // status
    output wire [15:0] st_frames_good,
    output wire [15:0] st_frames_abort
);
    // ---- mode register ----
    reg        cfg_err;
    reg [11:0] r_width, r_height;
    reg [1:0]  r_phase;
    reg [2:0]  r_mode;
    reg        busy; // frame in progress (simplified: any valid since sof until eof/abort)

    wire mode_ok = (cfg_mode <= 3'd4);
    wire algo_cfg_ready;
    wire algo_cfg_error;
    assign cfg_ready = rst_n && algo_cfg_ready && !busy;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_err <= 1'b0;
            r_width <= WIDTH[11:0]; r_height <= HEIGHT[11:0];
            r_phase <= 2'd3; r_mode <= 3'd0; busy <= 1'b0;
        end else begin
            if (s_valid && s_sof) busy <= 1'b1;
            if (s_valid && (s_eof || s_abort)) busy <= 1'b0;

            if (cfg_valid && !busy) begin
                r_width <= cfg_width;
                r_height <= cfg_height;
                r_phase <= cfg_phase;
                r_mode <= cfg_mode;
                cfg_err <= !mode_ok ||
                           !(cfg_width[1:0]==2'd0) ||
                           (cfg_width < 12'd8) || (cfg_width > MAX_WORDS*4) ||
                           (cfg_height < 12'd2) || (cfg_height > 12'd2048);
            end else if (cfg_valid && busy) begin
                cfg_err <= 1'b1; // do not mix mid-frame
            end
        end
    end
    assign cfg_error = cfg_err || algo_cfg_error;

    // raw_mode must be declared before use in u_algo instance (D2)
    wire raw_mode = (r_mode==3'd0) || (r_mode==3'd4);

    // ---- INT.P4 r1: single-beat handshake between the capture source and the
    // two shared consumers (selected monitor output / three-algorithm branch and
    // the packed-RAW10 A+ entrance).
    //
    // r0 defect (F1/F3): the algorithm branch and the pack branch were both
    // driven from the raw capture valid while only the pack branch was gated by
    // pk_ready.  With monitor backpressure (m_ready low) or A+ backpressure
    // (pk_ready low) one consumer could accept a beat that the source had not
    // surrendered (s_ready was low), so the held beat was fed to that consumer
    // repeatedly: duplicated 5-byte RAW10 groups, an early A+ frame end and a
    // permanent capture stall (r0 S5/T2).  In mode 1 the same mismatch plus the
    // unselected Gaussian/HE outputs also gating the shared stream stopped the
    // Y8 monitor stream entirely.
    //
    // r1 rule: a capture beat is offered to each consumer only when the OTHER
    // consumer can take it in the same cycle, and it is transferred exactly once
    // (s_ready = both sides ready).  Neither side can therefore over-consume a
    // held beat, and any backpressure simply stretches the frame in time.
    // INT.P4 r2: 2-beat elastic stage in front of the algorithm branch.  The
    // ready the capture side sees is now this stage's registered "not full", so
    // the P1 front-end accept chain (which reaches the row-buffer read address
    // inside the frozen img/ modules) no longer starts at the capture/admit
    // logic.  The r1 both-consumer exactly-once rule is unchanged: a capture
    // beat is accepted only when the packed-RAW10 consumer AND this stage can
    // take it, and the stage delivers it to the algorithm branch exactly once.
    wire        algo_in_ready;
    wire        algo_s_valid;
    wire        algo_s_ready;
    wire [39:0] algo_s_data;
    wire        algo_s_sof, algo_s_eol, algo_s_eof, algo_s_abort;

    wire mon_side_ready = raw_mode ? m_ready : algo_in_ready;
    wire pk_side_ready  = pk_ready;
    // packed-RAW10 offer: only when the monitor side also accepts this beat
    wire pk_s_valid     = s_valid && mon_side_ready;
    // algorithm offer: only when the A+ entrance also accepts this beat
    wire algo_in_valid  = s_valid && pk_side_ready && !raw_mode;

    int_p4_elastic_beats #(.DW(44)) u_algo_in (
        .clk(clk), .rst_n(rst_n),
        .s_valid(algo_in_valid), .s_ready(algo_in_ready),
        .s_data({s_abort, s_eof, s_eol, s_sof, s_data}),
        .m_valid(algo_s_valid), .m_ready(algo_s_ready),
        .m_data({algo_s_abort, algo_s_eof, algo_s_eol, algo_s_sof, algo_s_data})
    );

    // status wires for img_algo_parallel_top outputs (D5)
    wire [15:0] st_he_published;
    wire [15:0] st_he_rejected;
    wire [15:0] st_gau_abort;

    // ---- RAW10 packing correction ----
    wire        pk_valid_i;
    wire [39:0] pk_data_i;
    wire        pk_sof_i, pk_eol_i, pk_eof_i, pk_abort_i;
    raw10_sample_vector_to_packed u_pack (
        .clk(clk), .rst_n(rst_n),
        .s_valid(pk_s_valid), .s_ready(), .s_data(s_data),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof), .s_abort(s_abort),
        .m_ready(pk_side_ready),
        .m_valid(pk_valid_i), .m_data(pk_data_i),
        .m_sof(pk_sof_i), .m_eol(pk_eol_i), .m_eof(pk_eof_i), .m_abort(pk_abort_i)
    );
    assign pk_valid = pk_valid_i;
    assign pk_data  = pk_data_i;
    assign pk_sof   = pk_sof_i;
    assign pk_eol   = pk_eol_i;
    assign pk_eof   = pk_eof_i;
    assign pk_abort = pk_abort_i;

    // ---- three algorithms ----
    wire        y8_valid, gau_valid, he_valid;
    wire [31:0] y8_data, gau_data, he_data;
    wire        y8_sof, y8_eol, y8_eof, y8_abort;
    wire        gau_sof, gau_eol, gau_eof, gau_abort;
    wire        he_sof, he_eol, he_eof, he_abort;
    // Only the algorithm selected by the current mode may apply backpressure to
    // the shared stream; the other two branches are drained (ready=1) so their
    // 8-deep output buffers can never stall capture / the A+ path (r0 F3).
    wire        y8_sel = (r_mode == 3'd1);
    wire        gau_sel = (r_mode == 3'd2);
    wire        he_sel = (r_mode == 3'd3);

    // INT.P4 r2: timing-only derived variant (identical ports/semantics) that adds
    // registered ready boundaries so the shared-stream output ready cannot reach
    // the front-end row-buffer path combinationally (r1 G2 worst path E1).  The
    // base img_algo_parallel_top stays read-only in fpga/csi2/src/img/.
    img_algo_parallel_top_p4 #(.MAX_WORDS(MAX_WORDS)) u_algo (
        .clk(clk), .rst_n(rst_n),
        .cfg_valid(cfg_valid), .cfg_ready(algo_cfg_ready), .cfg_width(cfg_width),
        .cfg_height(cfg_height), .cfg_phase(cfg_phase), .cfg_error(algo_cfg_error),
        .s_valid(algo_s_valid), .s_ready(algo_s_ready),
        .s_data(algo_s_data), .s_sof(algo_s_sof), .s_eol(algo_s_eol),
        .s_eof(algo_s_eof), .s_abort(algo_s_abort),
        .y8_valid(y8_valid), .y8_ready(y8_sel  ? m_ready : 1'b1), .y8_data(y8_data),
        .y8_sof(y8_sof), .y8_eol(y8_eol), .y8_eof(y8_eof), .y8_abort(y8_abort),
        .gau_valid(gau_valid), .gau_ready(gau_sel ? m_ready : 1'b1), .gau_data(gau_data),
        .gau_sof(gau_sof), .gau_eol(gau_eol), .gau_eof(gau_eof), .gau_abort(gau_abort),
        .he_valid(he_valid), .he_ready(he_sel ? m_ready : 1'b1), .he_data(he_data),
        .he_sof(he_sof), .he_eol(he_eol), .he_eof(he_eof), .he_abort(he_abort),
        .st_frames_good(st_frames_good), .st_frames_abort(st_frames_abort),
        .st_he_published(st_he_published), .st_he_rejected(st_he_rejected),
        .st_gau_abort(st_gau_abort),
        .he_lut_addr(8'd0), .he_lut_data()
    );

    // ---- input ready: the beat transfers only when both shared consumers can
    // take it in the same cycle (see the r1 handshake note above).
    assign s_ready = mon_side_ready && pk_side_ready;

    // ---- output routing ----
    assign m_mode   = r_mode;
    assign m_is_raw = raw_mode;
    // raw modes: the monitor taps the transposed capture beat, offered only when
    // the A+ entrance also accepts it (m_valid must never depend on m_ready).
    assign m_valid  = raw_mode ? (s_valid && pk_side_ready) : 
                      (r_mode==3'd1) ? y8_valid :
                      (r_mode==3'd2) ? gau_valid : he_valid;

    assign m_raw_data  = s_data;
    assign m_proc_data = (r_mode==3'd1) ? y8_data :
                         (r_mode==3'd2) ? gau_data : he_data;

    assign m_sof   = raw_mode ? s_sof   :
                     (r_mode==3'd1) ? y8_sof :
                     (r_mode==3'd2) ? gau_sof : he_sof;
    assign m_eol   = raw_mode ? s_eol   :
                     (r_mode==3'd1) ? y8_eol :
                     (r_mode==3'd2) ? gau_eol : he_eol;
    assign m_eof   = raw_mode ? s_eof   :
                     (r_mode==3'd1) ? y8_eof :
                     (r_mode==3'd2) ? gau_eof : he_eof;
    assign m_abort = raw_mode ? s_abort  :
                     (r_mode==3'd1) ? y8_abort :
                     (r_mode==3'd2) ? gau_abort : he_abort;
    // ---- good-frame publish / cancel transaction (D3) ----
    wire fg_frame_good, fg_frame_abort, fg_commit, fg_cancel, fg_published, fg_busy;
    frame_good_publish_cancel u_frame_good (
        .clk(clk), .rst_n(rst_n),
        .sof(s_valid && s_sof),
        .last_roi_sample(s_valid && s_eol),
        .suffix_done(s_valid && s_eof),
        .crc_ok(1'b1),
        .fe_ok(1'b1),
        .abort_in(s_abort),
        .resof(s_valid && s_sof && busy),
        .frame_good(fg_frame_good),
        .frame_abort(fg_frame_abort),
        .commit(fg_commit),
        .cancel(fg_cancel),
        .published(fg_published),
        .busy(fg_busy)
    );
endmodule