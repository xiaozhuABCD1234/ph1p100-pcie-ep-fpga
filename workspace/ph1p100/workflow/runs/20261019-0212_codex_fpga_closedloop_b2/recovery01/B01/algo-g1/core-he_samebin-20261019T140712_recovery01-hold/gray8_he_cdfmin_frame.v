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
    reg [7:0]  px_pp[0:3];
    reg [7:0]  lut_r[0:3];
    reg        cnt_en_d;
    reg        s_sof_d, s_eol_d, s_eof_d;

    // ---------------- histogram write pipeline ----------------
    // The bank read data is registered a second time (hb*_r) so the 4-bank sum
    // of the merge pass starts from a register; the histogram write data,
    // address and enable are registered as well, so the ERAM clk2q never feeds
    // the same-cycle write data path.  The write for a beat then lands two
    // cycles after its read, so the RAM read misses the two most recent writes;
    // we1/we2 are their "was counted" flags and feed the same-bin bypass.
    reg [23:0] hb0_r, hb1_r, hb2_r, hb3_r;
    reg [23:0] wd0, wd1, wd2, wd3;
    reg [7:0]  wa0, wa1, wa2, wa3;
    reg        we1, we2, we_w;

    // ---------------- output stage registers ----------------
    reg [31:0] o_data;
    reg        o_valid, o_sof, o_eol, o_eof, o_abort;
    reg        mk_d;

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
    reg        fw_d;

    // ---------------- pipeline registers (bounded pipelining for Fmax) ----------------
    // merge: the bank sum is registered so the 4-bank adder and the 32-bit
    // accumulate/cdf-min chain are split into two short paths
    reg [25:0] hsum_r;
    // LUT generation: cdf read data / difference / product / denominator
    // registers split the ERAM clk2q -> subtract -> multiply -> add chain
    reg [31:0] cdf_v, cdf_d, num_r;
    reg [31:0] den32_r, den_half, den_s;

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
    // the marker must always be forwarded (even when this branch is idle and
    // never opened the aborted frame); abort_evt only gates the frame reset
    wire mk_evt    = accept && s_abort;
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
        // second stage: the merge path sums these registers, which keeps the
        // ERAM clk2q plus its net off the 4-bank adder input
        hb0_r <= hb0_rd;
        hb1_r <= hb1_rd;
        hb2_r <= hb2_rd;
        hb3_r <= hb3_rd;
    end

    // ---------------- stage A registers ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_px[0] <= 8'd0; a_px[1] <= 8'd0; a_px[2] <= 8'd0; a_px[3] <= 8'd0;
            px_p[0] <= 8'd0; px_p[1] <= 8'd0; px_p[2] <= 8'd0; px_p[3] <= 8'd0;
            px_pp[0] <= 8'd0; px_pp[1] <= 8'd0; px_pp[2] <= 8'd0; px_pp[3] <= 8'd0;
        end else if (accept) begin
            a_px[0] <= px0; a_px[1] <= px1; a_px[2] <= px2; a_px[3] <= px3;
            px_p[0] <= a_px[0]; px_p[1] <= a_px[1]; px_p[2] <= a_px[2]; px_p[3] <= a_px[3];
            px_pp[0] <= px_p[0]; px_pp[1] <= px_p[1]; px_pp[2] <= px_p[2]; px_pp[3] <= px_p[3];
        end
    end

    // ---------------- stage B: effective count + histogram write ----------------
    // The histogram update is a read-modify-write through a registered RAM.  The
    // write data is registered as well, so the RAM read for beat c misses the
    // two most recent writes (beats c-1 and c-2, whose writes are still in
    // flight).  Their increments are added explicitly by the same-bin bypass:
    //   write(c) = base (RAM through c-3) + 1 (this beat)
    //              + [bin(c-1) == bin(c)] + [bin(c-2) == bin(c)]
    // where we1/we2 say whether those beats were actually counted.
    wire [1:0] inc0 = {1'b0, (1'b0)} +
                      {1'b0, ((a_px[0] == px_pp[0]) && we2)} + 2'd1;
    wire [1:0] inc1 = {1'b0, (1'b0)} +
                      {1'b0, ((a_px[1] == px_pp[1]) && we2)} + 2'd1;
    wire [1:0] inc2 = {1'b0, (1'b0)} +
                      {1'b0, ((a_px[2] == px_pp[2]) && we2)} + 2'd1;
    wire [1:0] inc3 = {1'b0, (1'b0)} +
                      {1'b0, ((a_px[3] == px_pp[3]) && we2)} + 2'd1;
    wire [23:0] eff0 = hb0_rd + {22'd0, inc0};
    wire [23:0] eff1 = hb1_rd + {22'd0, inc1};
    wire [23:0] eff2 = hb2_rd + {22'd0, inc2};
    wire [23:0] eff3 = hb3_rd + {22'd0, inc3};
    wire        we_now = cnt_en_d && en;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_en_d <= 1'b0;
            we1 <= 1'b0; we2 <= 1'b0; we_w <= 1'b0;
            wd0 <= 24'd0; wd1 <= 24'd0; wd2 <= 24'd0; wd3 <= 24'd0;
            wa0 <= 8'd0; wa1 <= 8'd0; wa2 <= 8'd0; wa3 <= 8'd0;
        end else if (en) begin
            cnt_en_d <= cnt_en;
            we1      <= we_now;
            we2      <= we1;
            we_w     <= we_now;
            if (we_now) begin
                wd0 <= eff0; wd1 <= eff1; wd2 <= eff2; wd3 <= eff3;
                wa0 <= a_px[0]; wa1 <= a_px[1]; wa2 <= a_px[2]; wa3 <= a_px[3];
            end
        end
    end

    always @(posedge clk) begin
        if (we_w && en) begin
            hb0[wa0] <= wd0;
            hb1[wa1] <= wd1;
            hb2[wa2] <= wd2;
            hb3[wa3] <= wd3;
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

    // ---------------- output stage (data + abort marker, single driver) ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_data <= 32'd0;
            o_valid <= 1'b0; o_sof <= 1'b0; o_eol <= 1'b0; o_eof <= 1'b0;
            o_abort <= 1'b0;
            mk_d <= 1'b0;
        end else if (en) begin
            if (lut_pub) o_data <= {lut_r[3], lut_r[2], lut_r[1], lut_r[0]};
            else         o_data <= {a_px[3], a_px[2], a_px[1], a_px[0]};
            // the abort marker rides the data pipeline as a valid entry with
            // o_abort=1 (the output buffer converts it to a one-cycle port event)
            o_valid <= cnt_en_d | mk_d;
            o_abort <= mk_d;
            o_sof   <= cnt_en_d && s_sof_d;
            o_eol   <= cnt_en_d && s_eol_d;
            o_eof   <= cnt_en_d && s_eof_d;
            mk_d    <= mk_evt;
        end
    end

    assign m_valid = o_valid;
    assign m_data  = o_data;
    assign m_sof   = o_sof;
    assign m_eol   = o_eol;
    assign m_eof   = o_eof;
    assign m_abort = o_abort;

    // ---------------- merge / LUT generation datapath ----------------
    // hsum is registered (hsum_r) so the 4-bank sum and the 32-bit accumulate
    // are separate short paths; the merge then runs one address behind the
    // bank read stream (writes cdf[mrg_a-2] with cdf_acc = cdf[mrg_a-3]).
    wire [25:0] hsum = {2'b0, hb0_r} + {2'b0, hb1_r} + {2'b0, hb2_r} + {2'b0, hb3_r};
    wire [31:0] cdf_acc_n = cdf_acc + {6'b0, hsum_r};

    // cdf read for the LUT pass (issued at lut_ph == 0)
    always @(posedge clk) begin
        if (st == ST_LUTGEN && lut_ph == 4'd0) cdf_rd <= cdf_ram[lut_a[7:0]];
    end

    // ---------------- main state machine ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st         <= ST_CLEAR;   // power-up: zero all histogram banks first
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
            fw_d       <= 1'b0;
            act_bank   <= 1'b0;
            lut_pub    <= 1'b0;
            hsum_r     <= 26'd0;
            cdf_v      <= 32'd0;
            cdf_d      <= 32'd0;
            num_r      <= 32'd0;
            den32_r    <= 32'd0;
            den_half   <= 32'd0;
            den_s      <= 32'd0;
        end else begin
            cdf_we <= 1'b0;
            // every frame-abort marker counts as one rejected frame, whether or
            // not this branch had opened the frame
            if (mk_evt) cnt_rej <= cnt_rej + 16'd1;
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
                        good_d <= 1'b0;   // aborted frame: never publishes
                        st <= ST_FW;
                    end else if (eof_evt) begin
                        // latch the frame-end decision exactly once (the ST_FW
                        // takes two cycles, so a continuously refreshed flag
                        // would be cleared before the decision is taken)
                        good_d <= good_evt;
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
                    // two cycles: the last two histogram writes (registered
                    // write data) land during this state, so the merge/clear
                    // reads and writes must not start earlier
                    mrg_a   <= 12'd0;
                    cdf_acc <= 32'd0;
                    cdf_min <= 32'd0;
                    cdf_min_v <= 1'b0;
                    clr_a   <= 12'd0;
                    if (fw_d) begin
                        fw_d <= 1'b0;
                        st   <= good_d ? ST_MERGE : ST_CLEAR;
                    end else begin
                        fw_d <= 1'b1;
                    end
                end
                ST_MERGE: begin
                    // stage 1: register the bank sum (short path from the banks)
                    hsum_r <= hsum;
                    // stage 2: accumulate three addresses behind the read stream
                    // (the read is registered twice and the sum once)
                    if (mrg_a >= 12'd3) begin
                        cdf_acc   <= cdf_acc_n;
                        cdf_we    <= 1'b1;
                        cdf_waddr <= mrg_a[7:0] - 8'd3;
                        cdf_wdata <= cdf_acc_n;
                        if (!cdf_min_v && (hsum_r != 26'd0)) begin
                            cdf_min_v <= 1'b1;
                            cdf_min   <= cdf_acc_n;
                        end
                    end
                    if (mrg_a == 12'd258) begin
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
                        4'd0: begin
                            // the cdf read is issued in the always block below;
                            // derive the span and pre-shifted denominators here
                            // (registered: the 32-bit subtract and the shifts are
                            // one short path)
                            den32_r  <= npix - cdf_min;
                            den_half <= (npix - cdf_min) >> 1;
                            den_s    <= (npix - cdf_min) << 7;
                            lut_ph   <= 4'd1;
                        end
                        4'd1: begin
                            // re-register the ERAM output (short path)
                            cdf_v  <= cdf_rd;
                            lut_ph <= 4'd2;
                        end
                        4'd2: begin
                            if (den32_r == 32'd0) begin
                                // empty histogram span: identity mapping
                                q_r    <= lut_a[7:0];
                                lut_ph <= 4'd13;
                            end else begin
                                cdf_d  <= (cdf_v >= cdf_min) ? (cdf_v - cdf_min) : 32'd0;
                                lut_ph <= 4'd3;
                            end
                        end
                        4'd3: begin
                            num_r  <= cdf_d * 32'd255;
                            lut_ph <= 4'd4;
                        end
                        4'd4: begin
                            rem    <= num_r + den_half;
                            q_r    <= 8'd0;
                            i_r    <= 4'd7;
                            lut_ph <= 4'd5;
                        end
                        4'd5, 4'd6, 4'd7, 4'd8, 4'd9, 4'd10, 4'd11, 4'd12: begin
                            if (rem >= den_s) begin
                                rem <= rem - den_s;
                                q_r <= q_r | (8'd1 << i_r);
                            end
                            den_s  <= den_s >> 1;
                            i_r    <= i_r - 4'd1;
                            if (i_r == 4'd0) lut_ph <= 4'd13;
                        end
                        4'd13: begin
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
