// gray8_he_cdfmin_frame.v — previous-frame CDF-min histogram equalisation (HE)
// on the Y8 4px stream.  T09.rk-align-algo. Verilog-2001, async reset.
//
// Frozen semantics (must match parallel/algorithms/image_algorithms_ref.py):
//   * frame n is mapped with the LUT published by the last complete valid frame.
//     The first frame after reset uses the identity LUT; a bad frame (abort, or
//     eof whose beat/row counts do not match cfg) never publishes and keeps the
//     previous LUT.
//   * the histogram is taken on the *input* Y8 samples (pre-LUT) with four
//     independent banks, lane i -> bank i, so four same-bin pixels in one beat
//     are all counted (no drop, no per-beat dedup).
//   * frame end merges the banks, builds LUT[v] = clamp(round((cdf[v]-cdf_min)
//     *255/den),0,255) with den = npix-cdf_min and half-up rounding, and
//     publishes atomically between frames (ping-pong LUT banks).  den == 0
//     (constant frame) publishes the identity LUT.
//   * 24-bit histogram counters (safe for 2048x2048 = 4.19M pixels/frame).
//   * output: same 4px handshake/sidebands as the input, registered latency,
//     stall holds data; the abort marker propagates as a one-cycle m_abort
//     after the beats accepted before the abort have drained.
//
// Frame-end work (merge + 256-entry divide + bank clear) stalls the input for a
// bounded number of cycles (<= ~3.3k, see algo/change-report.md).
// No hardware/timing claims in this package (G1 simulation; G2 small top).

module gray8_he_cdfmin_frame (
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
    output wire [15:0] st_published,
    output wire [15:0] st_rejected,
    input  wire [7:0]  lut_rd_addr,
    output wire [7:0]  lut_rd_data
);
    localparam ST_IDLE   = 3'd0;
    localparam ST_ACTIVE = 3'd1;
    localparam ST_FW     = 3'd2;
    localparam ST_MERGE  = 3'd3;
    localparam ST_LUTGEN = 3'd4;
    localparam ST_PUB    = 3'd5;
    localparam ST_CLEAR  = 3'd6;

    // ---------------- configuration ----------------
    reg        cfg_lat, cfg_err;
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
                          (cfg_width <= 12'd2048) &&
                          (cfg_height >= 12'd2) &&
                          (cfg_height <= 12'd2048));
        end
    end

    wire [11:0] m_words     = r_width[11:2];
    wire [23:0] total_beats = r_height * m_words;

    // ---------------- state / frame counters ----------------
    reg [2:0]  st;
    reg [23:0] beats;
    reg [11:0] rows;
    reg [15:0] cnt_pub, cnt_rej;
    reg        good_d;

    // ---------------- histogram banks (lane i -> bank i) ----------------
    reg [23:0] hb0 [0:255];
    reg [23:0] hb1 [0:255];
    reg [23:0] hb2 [0:255];
    reg [23:0] hb3 [0:255];
    reg [31:0] cdf_ram [0:255];

    // ---------------- LUT banks: 2 banks x 4 lanes ----------------
    reg [7:0] lut_a0 [0:255];
    reg [7:0] lut_a1 [0:255];
    reg [7:0] lut_a2 [0:255];
    reg [7:0] lut_a3 [0:255];
    reg [7:0] lut_b0 [0:255];
    reg [7:0] lut_b1 [0:255];
    reg [7:0] lut_b2 [0:255];
    reg [7:0] lut_b3 [0:255];
    reg       act_bank;
    reg       lut_pub;

    // ---------------- input pipeline registers ----------------
    reg [7:0]  a_px [0:3];
    reg [7:0]  px_p [0:3];
    reg [23:0] e_p  [0:3];
    reg [23:0] rd_r [0:3];
    reg [7:0]  lut_r[0:3];
    reg        cnt_en_d;
    reg        we_r;
    reg        s_sof_d, s_eol_d, s_eof_d;

    // ---------------- output stage registers ----------------
    reg [31:0] o_data;
    reg        o_valid, o_sof, o_eol, o_eof, o_abort;
    reg        ab_pend, ab_st1;

    // ---------------- merge / LUT registers ----------------
    reg [11:0] mrg_a;
    reg [31:0] cdf_acc, cdf_min, npix;
    reg        cdf_min_v;
    reg        cdf_we;
    reg [7:0]  cdf_waddr;
    reg [31:0] cdf_wdata;
    reg [31:0] cdf_rd;
    reg [11:0] lut_a;
    reg [3:0]  lut_ph;
    reg [31:0] rem;
    reg [7:0]  q_r;
    reg [3:0]  i_r;
    reg [11:0] clr_a;

    wire accept   = s_valid && s_ready;
    wire out_free = !(m_valid && !m_ready);
    wire en       = out_free;
    wire in_frame = (st == ST_ACTIVE) || ((st == ST_IDLE) && s_sof);
    wire cnt_en   = accept && in_frame;

    assign s_ready = rst_n && cfg_ok && (st == ST_IDLE || st == ST_ACTIVE) && en;

    wire [7:0] px0 = s_data[7:0];
    wire [7:0] px1 = s_data[15:8];
    wire [7:0] px2 = s_data[23:16];
    wire [7:0] px3 = s_data[31:24];

    // ---------------- frame events ----------------
    wire [23:0] beats_c = beats + 24'd1;
    wire [11:0] rows_c  = rows + 12'd1;
    wire abort_evt = s_abort && (st == ST_ACTIVE);
    wire eof_evt   = accept && (st == ST_ACTIVE) && s_eof;
    wire sof_evt   = accept && (st == ST_IDLE) && s_sof;
    wire good_evt  = eof_evt && s_eol && (beats_c == total_beats) && (rows_c == r_height);

    // ---------------- histogram read port (shared with merge pass) ----------------
    wire       compute = (st == ST_MERGE);
    wire [7:0] hra0 = compute ? mrg_a[7:0] : (accept ? px0 : a_px[0]);
    wire [7:0] hra1 = compute ? mrg_a[7:0] : (accept ? px1 : a_px[1]);
    wire [7:0] hra2 = compute ? mrg_a[7:0] : (accept ? px2 : a_px[2]);
    wire [7:0] hra3 = compute ? mrg_a[7:0] : (accept ? px3 : a_px[3]);

    reg [23:0] hb0_rd, hb1_rd, hb2_rd, hb3_rd;
    always @(posedge clk) begin
        hb0_rd <= hb0[hra0];
        hb1_rd <= hb1[hra1];
        hb2_rd <= hb2[hra2];
        hb3_rd <= hb3[hra3];
    end

    // ---------------- stage A registers ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_px[0] <= 8'd0; a_px[1] <= 8'd0; a_px[2] <= 8'd0; a_px[3] <= 8'd0;
            px_p[0] <= 8'd0; px_p[1] <= 8'd0; px_p[2] <= 8'd0; px_p[3] <= 8'd0;
        end else if (accept) begin
            a_px[0] <= px0; a_px[1] <= px1; a_px[2] <= px2; a_px[3] <= px3;
            px_p[0] <= a_px[0]; px_p[1] <= a_px[1]; px_p[2] <= a_px[2]; px_p[3] <= a_px[3];
        end
    end

    // ---------------- stage B: effective count + histogram write ----------------
    wire [23:0] eff0 = ((a_px[0] == px_p[0]) && we_r) ? (e_p[0] + 24'd1) : rd_r[0];
    wire [23:0] eff1 = ((a_px[1] == px_p[1]) && we_r) ? (e_p[1] + 24'd1) : rd_r[1];
    wire [23:0] eff2 = ((a_px[2] == px_p[2]) && we_r) ? (e_p[2] + 24'd1) : rd_r[2];
    wire [23:0] eff3 = ((a_px[3] == px_p[3]) && we_r) ? (e_p[3] + 24'd1) : rd_r[3];
    wire        we_now = cnt_en_d && en;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_en_d <= 1'b0;
            we_r     <= 1'b0;
            e_p[0] <= 24'd0; e_p[1] <= 24'd0; e_p[2] <= 24'd0; e_p[3] <= 24'd0;
        end else if (en) begin
            cnt_en_d <= cnt_en;
            we_r     <= we_now;
            if (we_now) begin
                e_p[0] <= eff0; e_p[1] <= eff1; e_p[2] <= eff2; e_p[3] <= eff3;
            end
        end
    end

    always @(posedge clk) begin
        if (we_now) begin
            hb0[a_px[0]] <= eff0 + 24'd1;
            hb1[a_px[1]] <= eff1 + 24'd1;
            hb2[a_px[2]] <= eff2 + 24'd1;
            hb3[a_px[3]] <= eff3 + 24'd1;
        end else if (st == ST_CLEAR) begin
            hb0[clr_a[7:0]] <= 24'd0;
            hb1[clr_a[7:0]] <= 24'd0;
            hb2[clr_a[7:0]] <= 24'd0;
            hb3[clr_a[7:0]] <= 24'd0;
        end
    end

    // ---------------- LUT read (active bank) ----------------
    wire [7:0] lra0 = accept ? px0 : a_px[0];
    wire [7:0] lra1 = accept ? px1 : a_px[1];
    wire [7:0] lra2 = accept ? px2 : a_px[2];
    wire [7:0] lra3 = accept ? px3 : a_px[3];

    always @(posedge clk) begin
        if (act_bank) begin
            lut_r[0] <= lut_b0[lra0];
            lut_r[1] <= lut_b1[lra1];
            lut_r[2] <= lut_b2[lra2];
            lut_r[3] <= lut_b3[lra3];
        end else begin
            lut_r[0] <= lut_a0[lra0];
            lut_r[1] <= lut_a1[lra1];
            lut_r[2] <= lut_a2[lra2];
            lut_r[3] <= lut_a3[lra3];
        end
    end

    // delayed input sidebands for the output stage
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_sof_d <= 1'b0; s_eol_d <= 1'b0; s_eof_d <= 1'b0;
        end else if (en) begin
            s_sof_d <= s_sof;
            s_eol_d <= s_eol;
            s_eof_d <= s_eof;
        end
    end

    // ---------------- output stage ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_data <= 32'd0;
            o_valid <= 1'b0; o_sof <= 1'b0; o_eol <= 1'b0; o_eof <= 1'b0;
            o_abort <= 1'b0;
        end else if (en) begin
            if (lut_pub) o_data <= {lut_r[3], lut_r[2], lut_r[1], lut_r[0]};
            else         o_data <= {a_px[3], a_px[2], a_px[1], a_px[0]};
            // an abort marker is a valid entry with o_abort=1 (output buffer
            // converts it to a one-cycle control event at the port)
            o_valid <= cnt_en_d | ab_st1;
            o_abort <= ab_st1;
            o_sof   <= cnt_en_d && s_sof_d;
            o_eol   <= cnt_en_d && s_eol_d;
            o_eof   <= cnt_en_d && s_eof_d;
            ab_st1  <= ab_pend;
            ab_pend <= 1'b0;
        end
    end

    // abort marker: waits behind beats already accepted, then one valid entry
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ab_pend <= 1'b0;
        else if (abort_evt) ab_pend <= 1'b1;
        else if (en && ab_pend) ab_pend <= 1'b0;
    end

    assign m_valid = o_valid;
    assign m_data  = o_data;
    assign m_sof   = o_sof;
    assign m_eol   = o_eol;
    assign m_eof   = o_eof;
    assign m_abort = o_abort;

    // ---------------- merge / LUT generation datapath ----------------
    wire [25:0] hsum = {2'b0, hb0_rd} + {2'b0, hb1_rd} + {2'b0, hb2_rd} + {2'b0, hb3_rd};
    wire [31:0] cdf_acc_n = cdf_acc + {6'b0, hsum};

    wire [31:0] den32 = npix - cdf_min;
    wire [31:0] num32 = (cdf_rd >= cdf_min) ? ((cdf_rd - cdf_min) * 32'd255) : 32'd0;

    // cdf read for the LUT pass (issued at lut_ph == 0)
    always @(posedge clk) begin
        if (st == ST_LUTGEN && lut_ph == 4'd0) cdf_rd <= cdf_ram[lut_a[7:0]];
    end

    // ---------------- main state machine ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st         <= ST_IDLE;
            beats      <= 24'd0;
            rows       <= 12'd0;
            cnt_pub    <= 16'd0;
            cnt_rej    <= 16'd0;
            good_d     <= 1'b0;
            mrg_a      <= 12'd0;
            cdf_acc    <= 32'd0;
            cdf_min    <= 32'd0;
            cdf_min_v  <= 1'b0;
            cdf_we     <= 1'b0;
            cdf_waddr  <= 8'd0;
            cdf_wdata  <= 32'd0;
            npix       <= 32'd0;
            lut_a      <= 12'd0;
            lut_ph     <= 4'd0;
            rem        <= 32'd0;
            q_r        <= 8'd0;
            i_r        <= 4'd0;
            clr_a      <= 12'd0;
            act_bank   <= 1'b0;
            lut_pub    <= 1'b0;
        end else begin
            cdf_we <= 1'b0;
            if (en) good_d <= good_evt;
            case (st)
                ST_IDLE: begin
                    if (sof_evt) begin
                        st    <= ST_ACTIVE;
                        beats <= 24'd1;
                        rows  <= 12'd0;
                    end
                end
                ST_ACTIVE: begin
                    if (abort_evt) begin
                        cnt_rej <= cnt_rej + 16'd1;
                        st      <= ST_FW;
                    end else if (eof_evt) begin
                        if (good_evt) begin
                            beats <= beats_c;
                            rows  <= rows_c;
                        end else begin
                            cnt_rej <= cnt_rej + 16'd1;
                        end
                        st <= ST_FW;
                    end else if (accept) begin
                        beats <= beats_c;
                        if (s_eol) rows <= rows_c;
                    end
                end
                ST_FW: begin
                    st      <= good_d ? ST_MERGE : ST_CLEAR;
                    mrg_a   <= 12'd0;
                    cdf_acc <= 32'd0;
                    cdf_min <= 32'd0;
                    cdf_min_v <= 1'b0;
                    clr_a   <= 12'd0;
                end
                ST_MERGE: begin
                    if (mrg_a >= 12'd1) begin
                        cdf_acc   <= cdf_acc_n;
                        cdf_we    <= 1'b1;
                        cdf_waddr <= mrg_a[7:0] - 8'd1;
                        cdf_wdata <= cdf_acc_n;
                        if (!cdf_min_v && (hsum != 26'd0)) begin
                            cdf_min_v <= 1'b1;
                            cdf_min   <= cdf_acc_n;
                        end
                    end
                    if (mrg_a == 12'd256) begin
                        npix   <= cdf_acc_n;
                        st     <= ST_LUTGEN;
                        lut_a  <= 12'd0;
                        lut_ph <= 4'd0;
                    end else begin
                        mrg_a <= mrg_a + 12'd1;
                    end
                end
                ST_LUTGEN: begin
                    case (lut_ph)
                        4'd0: lut_ph <= 4'd1;
                        4'd1: begin
                            if (den32 == 32'd0) begin
                                q_r    <= lut_a[7:0];
                                lut_ph <= 4'd10;
                            end else begin
                                rem    <= num32 + (den32 >> 1);
                                q_r    <= 8'd0;
                                i_r    <= 4'd7;
                                lut_ph <= 4'd2;
                            end
                        end
                        4'd2, 4'd3, 4'd4, 4'd5, 4'd6, 4'd7, 4'd8, 4'd9: begin
                            if (rem >= (den32 << i_r)) begin
                                rem <= rem - (den32 << i_r);
                                q_r <= q_r | (8'd1 << i_r);
                            end
                            i_r <= i_r - 4'd1;
                            if (i_r == 4'd0) lut_ph <= 4'd10;
                        end
                        4'd10: begin
                            if (act_bank) begin
                                lut_a0[lut_a[7:0]] <= q_r;
                                lut_a1[lut_a[7:0]] <= q_r;
                                lut_a2[lut_a[7:0]] <= q_r;
                                lut_a3[lut_a[7:0]] <= q_r;
                            end else begin
                                lut_b0[lut_a[7:0]] <= q_r;
                                lut_b1[lut_a[7:0]] <= q_r;
                                lut_b2[lut_a[7:0]] <= q_r;
                                lut_b3[lut_a[7:0]] <= q_r;
                            end
                            if (lut_a == 12'd255) begin
                                st <= ST_PUB;
                            end else begin
                                lut_a  <= lut_a + 12'd1;
                                lut_ph <= 4'd0;
                            end
                        end
                        default: lut_ph <= 4'd0;
                    endcase
                end
                ST_PUB: begin
                    act_bank <= ~act_bank;
                    lut_pub  <= 1'b1;
                    cnt_pub  <= cnt_pub + 16'd1;
                    clr_a    <= 12'd0;
                    st       <= ST_CLEAR;
                end
                ST_CLEAR: begin
                    if (clr_a == 12'd255) st <= ST_IDLE;
                    else                  clr_a <= clr_a + 12'd1;
                end
                default: st <= ST_IDLE;
            endcase
        end
    end

    // cdf write port
    always @(posedge clk) begin
        if (cdf_we) cdf_ram[cdf_waddr] <= cdf_wdata;
    end

    // ---------------- status / monitor ----------------
    assign st_published = cnt_pub;
    assign st_rejected  = cnt_rej;

    reg [7:0] lut_mon;
    always @(posedge clk) begin
        // LUT contents are identical across lanes; monitor lane 1 of the active bank
        if (act_bank) lut_mon <= lut_b1[lut_rd_addr];
        else          lut_mon <= lut_a1[lut_rd_addr];
    end
    assign lut_rd_data = lut_mon;
endmodule
