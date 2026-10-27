// bayer_raw10_demosaic4_p4.v — INT.P4 round2 TIMING-ONLY derived variant.
// Verilog-2001, async reset, synthesizable.  NO functional change.
//
// Base (read-only this round): fpga/csi2/src/img/bayer_raw10_demosaic4.v
//   sha256 recorded in INT.P4-r2-manifest.json (source_variant_bases).
//
// WHY THIS FILE EXISTS (INT.P4 r1 G2 failure E1)
// ----------------------------------------------
// The r1 synthesis worst path was
//   u_p1/u_algo/u_obuf_gau/count_reg[0] -> u_p1/u_algo/u_front/u_row/rb0_reg[0].d
//   6.818ns (cell 2.619 / net 4.199, max fanout 320, 8 logic levels)
// i.e. the P1 all-or-nothing output-ready fanout reached the front-end row-buffer
// read address through  pipe_en = !(m_valid && !m_ready)  and  s_ready/en.
// Shortening only the ready fanout upstream leaves ~4.6ns of that chain *inside*
// this module (pipe_en -> enabling net -> evt_en -> ra0 -> DRAM read -> bank mux
// -> rb0.d), so a top-level-only boundary cannot meet 5.333ns.  This variant
// therefore decouples the module's own pipeline from the downstream ready.
//
// THE ONLY CHANGE (diff vs the base file)
// ---------------------------------------
//   * `pipe_en` was  !(m_valid && !m_ready)  — the downstream ready reached the
//     P/Q/T pipeline enables and the row-window `en` combinationally.  It is now
//     driven by the "not full" flag of a 2-beat elastic output stage whose ready
//     comes from its own count register (registered ready).
//   * The module outputs are the head of that 2-beat stage instead of the T
//     stage registers.  Data order, sof/eol/eof/abort sidebands, frame schedule,
//     clamping, truncation, counters and cfg behaviour are bit-identical; only
//     the observable output latency changes, and the port contract (valid/ready
//     with a beat held while m_ready is low) is unchanged.
//   * Everything else (configuration block, algo_rowwin3 instance, P/Q/T
//     pipelines, counters) is a verbatim copy of the base file.
//
// Supported configuration and frozen semantics: unchanged (see the base file).
// No CDC, no asynchronous FIFO, no clock change, no timing exception.
//
// The elastic stage is also used by img_algo_parallel_top_p4.v (beat slice
// between the four gray streams and the three output ports).
//
// INT.P4 ROUND 3 (r3) — one additional, purely timing-derived change layer:
//   * u_row is now algo_rowwin3_p4 (derived from the read-only img/algo_rowwin3.v):
//     the 320-deep LUT-RAM read address/bank selection is registered and the
//     production path is realigned with the SAME fixed +1 cycle, so the r2 worst
//     path (pipe_en -> evt_en -> ra0 -> LUT-RAM read mux -> rb0.d) is split into
//     two shorter paths.  s_ready, the acceptance rate, the frame schedule and
//     the token order are unchanged; only +1 fixed cycle of latency is added.
//   * the 2-beat elastic output stage (r2) is unchanged.

module bayer_raw10_demosaic4_p4 #(
    parameter MAX_WORDS = 512
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
    output wire        m_valid,
    input  wire        m_ready,
    output wire [31:0] m_r,
    output wire [31:0] m_g,
    output wire [31:0] m_b,
    output wire        m_sof,
    output wire        m_eol,
    output wire        m_eof,
    output wire        m_abort,
    output wire [15:0] st_frames_good,
    output wire [15:0] st_frames_abort
);
    localparam LW = MAX_WORDS;

    // ---------------- configuration (identical to base) ----------------
    reg        cfg_lat;
    reg        cfg_err;
    reg [11:0] r_width, r_height;
    reg [1:0]  r_phase;

    assign cfg_ready = rst_n && !cfg_lat;
    assign cfg_error = cfg_err;

    wire cfg_ok = cfg_lat && !cfg_err;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_lat  <= 1'b0;
            cfg_err  <= 1'b0;
            r_width  <= 12'd0;
            r_height <= 12'd0;
            r_phase  <= 2'd0;
        end else if (cfg_valid && cfg_ready) begin
            cfg_lat  <= 1'b1;
            r_width  <= cfg_width;
            r_height <= cfg_height;
            r_phase  <= cfg_phase;
            cfg_err  <= !((cfg_width[1:0] == 2'd0) &&
                          (cfg_width >= 12'd8) &&
                          (cfg_width <= LW*4) &&
                          (cfg_height >= 12'd2) &&
                          (cfg_height <= 12'd2048));
        end
    end

    // ---------------- output elastic stage (the ONLY change) ----------------
    // 2 beats, count-based (registered) ready.  pipe_en therefore depends only on
    // this stage's count register, never on m_ready.
    wire        of_s_ready;
    wire        of_m_valid;
    wire [99:0] of_m_data;

    wire pipe_en = of_s_ready;

    // ---------------- row-window front (identical to base) ----------------
    wire        prod_valid, prod_first, prod_last, prod_abort, evt_good, evt_abort;
    wire [11:0] prod_y, prod_j;
    wire [59:0] win_c, win_u, win_d;

    // r3: derived row-window front (registered LUT-RAM read address, +1 fixed cycle)
    algo_rowwin3_p4 #(.MAX_WORDS(MAX_WORDS), .DW(40), .PARITY_CLAMP(1)) u_row (
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

    // ---------------- pipeline stage P (identical to base) ----------------
    reg [59:0] p_wc, p_wu, p_wd;
    reg        p_valid, p_abort, p_sof, p_eol, p_eof, p_ypar;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p_wc <= 60'd0; p_wu <= 60'd0; p_wd <= 60'd0;
            p_valid <= 1'b0; p_abort <= 1'b0;
            p_sof <= 1'b0; p_eol <= 1'b0; p_eof <= 1'b0; p_ypar <= 1'b0;
        end else if (pipe_en) begin
            p_valid <= prod_valid;
            p_abort <= prod_valid && prod_abort;
            if (prod_valid && !prod_abort) begin
                p_wc   <= win_c;
                p_wu   <= win_u;
                p_wd   <= win_d;
                p_sof  <= (prod_y == 12'd0) && (prod_j == 12'd0);
                p_eol  <= prod_last;
                p_eof  <= prod_last && (prod_y == r_height - 12'd1);
                p_ypar <= prod_y[0];
            end else if (prod_valid && prod_abort) begin
                p_sof  <= 1'b0;
                p_eol  <= 1'b0;
                p_eof  <= 1'b0;
            end
        end
    end

    // ---------------- pipeline stage M (identical to base) ----------------
    function [1:0] cfa_code;
        input        xpar;
        input        ypar;
        input [1:0]  phase;
        reg [1:0] tl, tr, bl, br;
        begin
            case (phase)
                2'd0: begin tl = 2'd0; tr = 2'd1; bl = 2'd1; br = 2'd2; end // RGGB
                2'd1: begin tl = 2'd2; tr = 2'd1; bl = 2'd1; br = 2'd0; end // BGGR
                2'd2: begin tl = 2'd1; tr = 2'd0; bl = 2'd2; br = 2'd1; end // GRBG
                default: begin tl = 2'd1; tr = 2'd2; bl = 2'd0; br = 2'd1; end // GBRG
            endcase
            cfa_code = ypar ? (xpar ? br : bl) : (xpar ? tr : tl);
        end
    endfunction

    function [29:0] dmx_lane;
        input [9:0] own, hl, hr, vu, vd, dul, dur, ddl, ddr;
        input [1:0] own_code, h_code;
        reg [10:0] a2h, a2v;
        reg [11:0] a4o, a4d;
        begin
            a2h = (hl + hr + 11'd1) >> 1;
            a2v = (vu + vd + 11'd1) >> 1;
            a4o = (hl + hr + vu + vd + 12'd2) >> 2;
            a4d = (dul + dur + ddl + ddr + 12'd2) >> 2;
            if (own_code == 2'd1) begin
                if (h_code == 2'd0) dmx_lane = {a2h[9:0], own, a2v[9:0]};
                else                dmx_lane = {a2v[9:0], own, a2h[9:0]};
            end else if (own_code == 2'd0) begin
                dmx_lane = {own, a4o[9:0], a4d[9:0]};
            end else begin
                dmx_lane = {a4d[9:0], a4o[9:0], own};
            end
        end
    endfunction

    wire [9:0] c0 = p_wc[59:50], c1 = p_wc[49:40], c2 = p_wc[39:30];
    wire [9:0] c3 = p_wc[29:20], c4 = p_wc[19:10], c5 = p_wc[9:0];
    wire [9:0] u0 = p_wu[59:50], u1 = p_wu[49:40], u2 = p_wu[39:30];
    wire [9:0] u3 = p_wu[29:20], u4 = p_wu[19:10], u5 = p_wu[9:0];
    wire [9:0] d0 = p_wd[59:50], d1 = p_wd[49:40], d2 = p_wd[39:30];
    wire [9:0] d3 = p_wd[29:20], d4 = p_wd[19:10], d5 = p_wd[9:0];

    wire [1:0] code0 = cfa_code(1'b0, p_ypar, r_phase);
    wire [1:0] code1 = cfa_code(1'b1, p_ypar, r_phase);
    wire [1:0] code0h = cfa_code(1'b1, p_ypar, r_phase);
    wire [1:0] code1h = cfa_code(1'b0, p_ypar, r_phase);

    wire [29:0] m0 = dmx_lane(c1, c0, c2, u1, d1, u0, u2, d0, d2, code0, code0h);
    wire [29:0] m1 = dmx_lane(c2, c1, c3, u2, d2, u1, u3, d1, d3, code1, code1h);
    wire [29:0] m2 = dmx_lane(c3, c2, c4, u3, d3, u2, u4, d2, d4, code0, code0h);
    wire [29:0] m3 = dmx_lane(c4, c3, c5, u4, d4, u3, u5, d3, d5, code1, code1h);

    reg [29:0] q0, q1, q2, q3;
    reg        q_valid, q_abort, q_sof, q_eol, q_eof;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q0 <= 30'd0; q1 <= 30'd0; q2 <= 30'd0; q3 <= 30'd0;
            q_valid <= 1'b0; q_abort <= 1'b0;
            q_sof <= 1'b0; q_eol <= 1'b0; q_eof <= 1'b0;
        end else if (pipe_en) begin
            q0 <= m0; q1 <= m1; q2 <= m2; q3 <= m3;
            q_valid <= p_valid; q_abort <= p_abort;
            q_sof <= p_sof; q_eol <= p_eol; q_eof <= p_eof;
        end
    end

    // ---------------- pipeline stage T (identical to base) ----------------
    reg [23:0] t0, t1, t2, t3;
    reg        t_valid, t_abort, t_sof, t_eol, t_eof;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            t0 <= 24'd0; t1 <= 24'd0; t2 <= 24'd0; t3 <= 24'd0;
            t_valid <= 1'b0; t_abort <= 1'b0;
            t_sof <= 1'b0; t_eol <= 1'b0; t_eof <= 1'b0;
        end else if (pipe_en) begin
            t0 <= {q0[29:22], q0[19:12], q0[9:2]};
            t1 <= {q1[29:22], q1[19:12], q1[9:2]};
            t2 <= {q2[29:22], q2[19:12], q2[9:2]};
            t3 <= {q3[29:22], q3[19:12], q3[9:2]};
            t_valid <= q_valid; t_abort <= q_abort;
            t_sof <= q_sof; t_eol <= q_eol; t_eof <= q_eof;
        end
    end

    // ---------------- outputs: 2-beat elastic stage (changed) ----------------
    wire [99:0] of_in = {t_abort, t_eof, t_eol, t_sof,
                         {t3[23:16], t2[23:16], t1[23:16], t0[23:16]},
                         {t3[15:8],  t2[15:8],  t1[15:8],  t0[15:8]},
                         {t3[7:0],   t2[7:0],   t1[7:0],   t0[7:0]}};

    int_p4_elastic_beats #(.DW(100)) u_ofifo (
        .clk(clk), .rst_n(rst_n),
        .s_valid(t_valid), .s_ready(of_s_ready), .s_data(of_in),
        .m_valid(of_m_valid), .m_ready(m_ready), .m_data(of_m_data)
    );

    assign m_valid = of_m_valid;
    assign m_abort = of_m_data[99];
    assign m_eof   = of_m_data[98];
    assign m_eol   = of_m_data[97];
    assign m_sof   = of_m_data[96];
    assign m_r     = of_m_data[95:64];
    assign m_g     = of_m_data[63:32];
    assign m_b     = of_m_data[31:0];

    // ---------------- frame counters (identical to base) ----------------
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

// =============================================================================
// int_p4_elastic_beats — 2-beat elastic register slice with a *registered* ready.
//
// The ready presented to the producer is a function of this stage's own count
// register (cnt != DEPTH), never of the consumer's ready, so a downstream
// backpressure network cannot reach the producer's pipeline enables
// combinationally.  Order is preserved, each beat is transferred exactly once,
// and the full 1 beat/clock throughput is kept (2 storage entries).
//
// Frozen latency note: adds 0..2 cycles of visible latency; the port contract
// (hold the beat while m_ready is low) is standard valid/ready.
// =============================================================================
module int_p4_elastic_beats #(
    parameter DW    = 32,
    parameter DEPTH = 2
)(
    input  wire          clk,
    input  wire          rst_n,
    input  wire          s_valid,
    output wire          s_ready,
    input  wire [DW-1:0] s_data,
    output wire          m_valid,
    input  wire          m_ready,
    output wire [DW-1:0] m_data
);
    localparam AW = 1;  // DEPTH=2 -> 1-bit pointers, 2-bit count

    reg [DW-1:0] mem [0:DEPTH-1];
    reg [AW-1:0] wr_ptr, rd_ptr;
    reg [AW:0]   cnt;

    wire full  = (cnt == DEPTH[AW:0]);
    wire empty = (cnt == {(AW+1){1'b0}});
    wire push  = s_valid && !full;
    wire pop   = !empty && m_ready;

    assign s_ready = !full;
    assign m_valid = !empty;
    assign m_data  = mem[rd_ptr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {AW{1'b0}};
            rd_ptr <= {AW{1'b0}};
            cnt    <= {(AW+1){1'b0}};
        end else begin
            if (push) begin
                mem[wr_ptr] <= s_data;
                wr_ptr      <= wr_ptr + 1'b1;
            end
            if (pop) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
            case ({push, pop})
                2'b10:   cnt <= cnt + 1'b1;
                2'b01:   cnt <= cnt - 1'b1;
                default: cnt <= cnt;
            endcase
        end
    end
endmodule
