// corrected copy for verification only; production file unchanged
// fix: declare raw_mode before use in u_algo instance
module integrated_input_processing_top #(
    parameter MAX_WORDS = 512,
    parameter WIDTH     = 1920,
    parameter HEIGHT    = 1080
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        cfg_valid,
    output wire        cfg_ready,
    input  wire [11:0] cfg_width,
    input  wire [11:0] cfg_height,
    input  wire [1:0]  cfg_phase,
    input  wire [2:0]  cfg_mode,
    output wire        cfg_error,
    input  wire        s_valid,
    output wire        s_ready,
    input  wire [39:0] s_data,
    input  wire        s_sof,
    input  wire        s_eol,
    input  wire        s_eof,
    input  wire        s_abort,
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
    input  wire        pk_ready,
    output wire        pk_valid,
    output wire [39:0] pk_data,
    output wire        pk_sof,
    output wire        pk_eol,
    output wire        pk_eof,
    output wire        pk_abort,
    output wire [15:0] st_frames_good,
    output wire [15:0] st_frames_abort
);
    reg        cfg_err;
    reg [11:0] r_width, r_height;
    reg [1:0]  r_phase;
    reg [2:0]  r_mode;
    reg        busy;

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
                cfg_err <= 1'b1;
            end
        end
    end
    assign cfg_error = cfg_err || algo_cfg_error;

    wire raw_mode = (r_mode==3'd0) || (r_mode==3'd4);

    wire        pk_valid_i;
    wire [39:0] pk_data_i;
    wire        pk_sof_i, pk_eol_i, pk_eof_i, pk_abort_i;
    raw10_sample_vector_to_packed u_pack (
        .clk(clk), .rst_n(rst_n),
        .s_valid(s_valid), .s_ready(), .s_data(s_data),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof), .s_abort(s_abort),
        .m_ready(pk_ready),
        .m_valid(pk_valid_i), .m_data(pk_data_i),
        .m_sof(pk_sof_i), .m_eol(pk_eol_i), .m_eof(pk_eof_i), .m_abort(pk_abort_i)
    );
    assign pk_valid = pk_valid_i;
    assign pk_data  = pk_data_i;
    assign pk_sof   = pk_sof_i;
    assign pk_eol   = pk_eol_i;
    assign pk_eof   = pk_eof_i;
    assign pk_abort = pk_abort_i;

    wire        y8_valid, gau_valid, he_valid;
    wire [31:0] y8_data, gau_data, he_data;
    wire        y8_sof, y8_eol, y8_eof, y8_abort;
    wire        gau_sof, gau_eol, gau_eof, gau_abort;
    wire        he_sof, he_eol, he_eof, he_abort;
    wire        algo_s_ready;

    img_algo_parallel_top #(.MAX_WORDS(MAX_WORDS)) u_algo (
        .clk(clk), .rst_n(rst_n),
        .cfg_valid(cfg_valid), .cfg_ready(algo_cfg_ready), .cfg_width(cfg_width),
        .cfg_height(cfg_height), .cfg_phase(cfg_phase), .cfg_error(algo_cfg_error),
        .s_valid(s_valid && !raw_mode), .s_ready(algo_s_ready),
        .s_data(s_data), .s_sof(s_sof), .s_eol(s_eol),
        .s_eof(s_eof), .s_abort(s_abort),
        .y8_valid(y8_valid), .y8_ready(m_ready), .y8_data(y8_data),
        .y8_sof(y8_sof), .y8_eol(y8_eol), .y8_eof(y8_eof), .y8_abort(y8_abort),
        .gau_valid(gau_valid), .gau_ready(m_ready), .gau_data(gau_data),
        .gau_sof(gau_sof), .gau_eol(gau_eol), .gau_eof(gau_eof), .gau_abort(gau_abort),
        .he_valid(he_valid), .he_ready(m_ready), .he_data(he_data),
        .he_sof(he_sof), .he_eol(he_eol), .he_eof(he_eof), .he_abort(he_abort),
        .st_frames_good(st_frames_good), .st_frames_abort(st_frames_abort),
        .he_lut_addr(8'd0), .he_lut_data()
    );

    assign s_ready = raw_mode ? (m_ready && pk_ready) : (algo_s_ready && pk_ready);

    assign m_mode   = r_mode;
    assign m_is_raw = raw_mode;
    assign m_valid  = raw_mode ? (s_valid && m_ready) :
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
endmodule