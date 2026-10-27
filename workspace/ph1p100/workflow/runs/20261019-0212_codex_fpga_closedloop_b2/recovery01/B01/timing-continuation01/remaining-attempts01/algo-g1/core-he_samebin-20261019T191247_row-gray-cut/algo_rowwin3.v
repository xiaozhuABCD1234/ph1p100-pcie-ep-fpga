// algo_rowwin3.v — shared 3-bank / 2-reader row-window front for the 4px image
// pipeline (Bayer RAW10 demosaic front end and Y8 Gaussian branch).
// T09.rk-align-algo. Verilog-2001, async reset, synthesizable.
//
// Frozen organisation (derivation in algo/change-report.md):
//   * three line-buffer banks hold 4-sample words; write bank W(r) of input row
//     r cycles 0,2,1 and both scan readers rotate identically, so every bank is
//     accessed at most once per cycle;
//   * production row y (= output row y) is assembled while input row y+1
//     streams in; the last input row triggers a fixed flush of m_words+1
//     production slots (output row H-2 last word, then all of output row H-1);
//   * vertical neighbours follow the frozen CFA-parity clamping: up of row 0 is
//     row 1 (stream), down of row H-1 is row H-2 (up reader);
//   * frame control: a good frame ends with s_eof exactly at (H-1, last word);
//     s_abort, s_sof while active, a misplaced s_eol/s_eof or an over-length
//     frame abort the frame, reset all state and emit a one-slot abort marker
//     (prod_valid with prod_abort) so downstream branches reset in order;
//   * every state step is gated by `en` (pipeline not stalled), so input stalls
//     freeze the whole schedule consistently.
//
// The caller latches prod_* and win_* at prod_valid and owns the arithmetic
// pipeline; this module owns the frame schedule and the line buffers.
// No hardware/timing claims in this package (G1 simulation; G2 small top).

module algo_rowwin3 #(
    parameter MAX_WORDS = 512,   // words per line (MAX_WIDTH/4)
    parameter DW        = 40,    // 4 x RAW10 (40) or 4 x Y8 (32)
    parameter PARITY_CLAMP = 1   // 1 = CFA-parity clamps (demosaic),
                                 // 0 = plain replicate (Y8 Gaussian)
)(
    input  wire            clk,
    input  wire            rst_n,
    input  wire [11:0]     cfg_width,    // multiple of 4, >= 8
    input  wire [11:0]     cfg_height,   // >= 2
    input  wire            cfg_ok,
    input  wire            s_valid,
    output wire            s_ready,
    input  wire [DW-1:0]   s_data,
    input  wire            s_sof,
    input  wire            s_eol,
    input  wire            s_eof,
    input  wire            s_abort,
    input  wire            en,           // 1 = pipeline advances this cycle
    output wire            prod_valid,
    output wire [11:0]     prod_y,
    output wire [11:0]     prod_j,
    output wire            prod_first,
    output wire            prod_last,
    output wire            prod_abort,
    output wire [6*(DW/4)-1:0] win_c,
    output wire [6*(DW/4)-1:0] win_u,
    output wire [6*(DW/4)-1:0] win_d,
    output wire            evt_good,
    output wire            evt_abort
);
    localparam ST_IDLE   = 2'd0;
    localparam ST_ACTIVE = 2'd1;
    localparam ST_FLUSH  = 2'd2;

    reg  [1:0]    state;
    reg  [11:0]   in_row;
    reg  [11:0]   in_w;
    reg  [1:0]    wr_bank;
    reg  [11:0]   fl_cnt;
    reg           evt_good_r;
    reg           evt_abort_r;
    reg  [DW-1:0] st_r1, st_r2;

    reg  [DW-1:0] bank0 [0:MAX_WORDS-1];
    reg  [DW-1:0] bank1 [0:MAX_WORDS-1];
    reg  [DW-1:0] bank2 [0:MAX_WORDS-1];

    wire [11:0] m_words = cfg_width[11:2];
    wire [11:0] mm1     = m_words - 12'd1;
    wire [11:0] hm1     = cfg_height - 12'd1;

    assign s_ready = rst_n && cfg_ok && en && (state != ST_FLUSH);

    wire accept      = s_valid && s_ready;
    wire at_last     = (in_w == mm1);
    wire at_pos_last = (in_row == hm1) && at_last;

    // ---- frame control events (combinational, sampled at accept) ----
    // A frame-abort marker (s_abort) must ALWAYS be forwarded downstream, even
    // when this module is idle: the front end emits no productions for a frame
    // that was aborted before its first output row, so the branch may never
    // have opened it.  abort_evt (state reset / counters) stays state-gated.
    wire marker_evt = accept && s_abort;
    wire abort_evt = accept && (state == ST_ACTIVE) &&
                     (s_abort || s_sof || (s_eol != at_last) ||
                      (at_pos_last && !s_eof) ||
                      (s_eof && !at_pos_last));
    wire eof_good  = accept && (state == ST_ACTIVE) && s_eof && at_pos_last &&
                     !s_abort && !s_sof && (s_eol == at_last);
    wire abort_restart = abort_evt && s_sof;
    wire data_beat     = accept && (state == ST_ACTIVE) && !(abort_evt && !s_sof);
    wire frame_start   = accept && (((state == ST_IDLE) && s_sof) || abort_restart);

    // ---- production schedule ----
    wire pe = accept && (state == ST_ACTIVE) && !abort_evt && !marker_evt &&
              ((in_row >= 12'd2) || ((in_row == 12'd1) && (in_w != 12'd0)));
    wire [11:0] pe_y = (in_w == 12'd0) ? (in_row - 12'd2) : (in_row - 12'd1);
    wire [11:0] pe_j = (in_w == 12'd0) ? mm1 : (in_w - 12'd1);

    wire f_cycle = (state == ST_FLUSH) && en;
    wire [11:0] f_y = (fl_cnt == 12'd0) ? (cfg_height - 12'd2) : hm1;
    wire [11:0] f_j = (fl_cnt == 12'd0) ? mm1 : (fl_cnt - 12'd1);

    assign prod_valid = marker_evt || abort_evt || pe || f_cycle;
    assign prod_y     = (marker_evt || abort_evt) ? 12'd0 : (pe ? pe_y : f_y);
    assign prod_j     = (marker_evt || abort_evt) ? 12'd0 : (pe ? pe_j : f_j);
    assign prod_first = (prod_j == 12'd0);
    assign prod_last  = (prod_j == mm1);
    assign prod_abort = marker_evt || abort_evt;

    assign evt_good  = evt_good_r;
    assign evt_abort = evt_abort_r;

    // ---- line-buffer write port ----
    wire [1:0]  wr_bank_eff = frame_start ? 2'd0 : wr_bank;
    wire [11:0] wr_addr_eff = frame_start ? 12'd0 : in_w;
    always @(posedge clk) begin
        if (data_beat || frame_start) begin
            case (wr_bank_eff)
                2'd0: bank0[wr_addr_eff] <= s_data;
                2'd1: bank1[wr_addr_eff] <= s_data;
                2'd2: bank2[wr_addr_eff] <= s_data;
            endcase
        end
    end

    // ---- stream window registers (down row) ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st_r1 <= {DW{1'b0}};
            st_r2 <= {DW{1'b0}};
        end else if (data_beat || frame_start) begin
            st_r1 <= s_data;
            st_r2 <= st_r1;
        end
    end

    // ---- scan readers ----
    wire evt_en  = en && (accept || (state == ST_FLUSH));
    wire clr_now = frame_start || abort_evt;
    wire start_c = accept && (state == ST_ACTIVE) && (in_row == 12'd0) && at_last && !abort_evt;
    wire start_u = accept && (state == ST_ACTIVE) && (in_row == 12'd1) && at_last && !abort_evt;

    wire [11:0] rdc_addr, rdu_addr;
    wire [1:0]  rdc_bank, rdu_bank;
    wire        rdc_active, rdu_active;

    algo_rowwin_reader u_rdc (
        .clk(clk), .rst_n(rst_n), .start(start_c), .clr(clr_now), .en(evt_en),
        .m_words(m_words), .rows_limit(cfg_height),
        .rd_addr(rdc_addr), .rd_bank(rdc_bank), .active(rdc_active)
    );
    algo_rowwin_reader u_rdu (
        .clk(clk), .rst_n(rst_n), .start(start_u), .clr(clr_now), .en(evt_en),
        .m_words(m_words), .rows_limit(cfg_height - 12'd1),
        .rd_addr(rdu_addr), .rd_bank(rdu_bank), .active(rdu_active)
    );

    // one RAM access per bank per cycle: centre reader wins when active on the
    // bank.  The presented address is the current event's issue and is held
    // until the next event, so the synchronous read data of an irregular event
    // (gaps/stalls) stays valid instead of being overwritten by the speculative
    // next-issue read.
    reg [11:0] cpa_a, upa_a;
    reg [1:0]  cpa_b, upa_b;
    reg [1:0]  cbq, ubq;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpa_a <= 12'd0; cpa_b <= 2'd0; upa_a <= 12'd0; upa_b <= 2'd0;
            cbq <= 2'd0; ubq <= 2'd0;
        end else begin
            if (evt_en) begin
                cpa_a <= rdc_addr; cpa_b <= rdc_bank;
                upa_a <= rdu_addr; upa_b <= rdu_bank;
            end
            cbq <= evt_en ? rdc_bank : cpa_b;
            ubq <= evt_en ? rdu_bank : upa_b;
        end
    end
    wire [11:0] cpa_al = evt_en ? rdc_addr : cpa_a;
    wire [1:0]  cpa_bl = evt_en ? rdc_bank : cpa_b;
    wire [11:0] upa_al = evt_en ? rdu_addr : upa_a;
    wire [1:0]  upa_bl = evt_en ? rdu_bank : upa_b;

    wire [11:0] ra0 = (rdc_active && (cpa_bl == 2'd0)) ? cpa_al : upa_al;
    wire [11:0] ra1 = (rdc_active && (cpa_bl == 2'd1)) ? cpa_al : upa_al;
    wire [11:0] ra2 = (rdc_active && (cpa_bl == 2'd2)) ? cpa_al : upa_al;

    reg [DW-1:0] rb0, rb1, rb2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rb0 <= {DW{1'b0}}; rb1 <= {DW{1'b0}}; rb2 <= {DW{1'b0}};
        end else begin
            rb0 <= bank0[ra0];
            rb1 <= bank1[ra1];
            rb2 <= bank2[ra2];
        end
    end
    wire [DW-1:0] rd_c = (cbq == 2'd0) ? rb0 : (cbq == 2'd1) ? rb1 : rb2;
    wire [DW-1:0] rd_u = (ubq == 2'd0) ? rb0 : (ubq == 2'd1) ? rb1 : rb2;

    // reader word pipelines: at a production slot, rd_* is word j+1, r1 word j,
    // r2 word j-1 (two events back).
    reg [DW-1:0] rdc_r1, rdc_r2, rdu_r1, rdu_r2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rdc_r1 <= {DW{1'b0}}; rdc_r2 <= {DW{1'b0}};
            rdu_r1 <= {DW{1'b0}}; rdu_r2 <= {DW{1'b0}};
        end else if (evt_en) begin
            rdc_r2 <= rdc_r1; rdc_r1 <= rd_c;
            rdu_r2 <= rdu_r1; rdu_r1 <= rd_u;
        end
    end

    // ---- window assembly: columns 4j-1 .. 4j+4 with frozen clamp rules ----
    // Lane/sample convention (project csi_rx_10bit_unpack_checked.v): the first
    // (leftmost) pixel of the 4-sample word is bits [SW-1:0].  Window layout:
    // win[6*SW-1 -: SW] = column 4j-1 (left edge), then samples 0..3, then the
    // right edge at win[SW-1:0] (column 4j+4).
    // par=1: CFA-parity clamps (demosaic: left of col 0 is col 1, right of col
    // W-1 is col W-2); par=0: plain replicate (left/right edge is the centre).
    localparam PAR = (PARITY_CLAMP != 0) ? 1'b1 : 1'b0;

    function [59:0] asm40;
        input [39:0] din, r1, r2;
        input        first, last, par;
        begin
            asm40[59:50] = first ? (par ? r1[19:10] : r1[9:0]) : r2[39:30];
            asm40[49:40] = r1[9:0];
            asm40[39:30] = r1[19:10];
            asm40[29:20] = r1[29:20];
            asm40[19:10] = r1[39:30];
            asm40[9:0]   = last  ? (par ? r1[29:20] : r1[39:30]) : din[9:0];
        end
    endfunction

    function [47:0] asm32;
        input [31:0] din, r1, r2;
        input        first, last, par;
        begin
            asm32[47:40] = first ? (par ? r1[15:8] : r1[7:0]) : r2[31:24];
            asm32[39:32] = r1[7:0];
            asm32[31:24] = r1[15:8];
            asm32[23:16] = r1[23:16];
            asm32[15:8]  = r1[31:24];
            asm32[7:0]   = last  ? (par ? r1[23:16] : r1[31:24]) : din[7:0];
        end
    endfunction

    generate
    if (DW == 40) begin : g_raw10
        assign win_c = asm40(rd_c, rdc_r1, rdc_r2, prod_first, prod_last, PAR);
        assign win_u = (prod_y == 12'd0)
                     ? (PAR ? asm40(s_data, st_r1, st_r2, prod_first, prod_last, PAR)
                            : asm40(rd_c, rdc_r1, rdc_r2, prod_first, prod_last, PAR))
                     : asm40(rd_u, rdu_r1, rdu_r2, prod_first, prod_last, PAR);
        assign win_d = (prod_y == hm1)
                     ? (PAR ? asm40(rd_u, rdu_r1, rdu_r2, prod_first, prod_last, PAR)
                            : asm40(rd_c, rdc_r1, rdc_r2, prod_first, prod_last, PAR))
                     : asm40(s_data, st_r1, st_r2, prod_first, prod_last, PAR);
    end else begin : g_y8
        assign win_c = asm32(rd_c, rdc_r1, rdc_r2, prod_first, prod_last, PAR);
        assign win_u = (prod_y == 12'd0)
                     ? (PAR ? asm32(s_data, st_r1, st_r2, prod_first, prod_last, PAR)
                            : asm32(rd_c, rdc_r1, rdc_r2, prod_first, prod_last, PAR))
                     : asm32(rd_u, rdu_r1, rdu_r2, prod_first, prod_last, PAR);
        assign win_d = (prod_y == hm1)
                     ? (PAR ? asm32(rd_u, rdu_r1, rdu_r2, prod_first, prod_last, PAR)
                            : asm32(rd_c, rdc_r1, rdc_r2, prod_first, prod_last, PAR))
                     : asm32(s_data, st_r1, st_r2, prod_first, prod_last, PAR);
    end
    endgenerate

    // ---- frame state machine ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            in_row      <= 12'd0;
            in_w        <= 12'd0;
            wr_bank     <= 2'd0;
            fl_cnt      <= 12'd0;
            evt_good_r  <= 1'b0;
            evt_abort_r <= 1'b0;
        end else begin
            evt_good_r  <= 1'b0;
            evt_abort_r <= 1'b0;
            if (accept) begin
                if (state == ST_IDLE) begin
                    if (s_sof) begin
                        state   <= ST_ACTIVE;
                        in_row  <= 12'd0;
                        wr_bank <= 2'd0;
                        if (m_words == 12'd1) begin
                            in_w <= 12'd0; in_row <= 12'd1; wr_bank <= 2'd2;
                        end else begin
                            in_w <= 12'd1;
                        end
                    end else if (marker_evt) begin
                        // frame aborted before this module opened it: count it and
                        // still forward the marker (production path above)
                        evt_abort_r <= 1'b1;
                    end
                end else if (state == ST_ACTIVE) begin
                    if (abort_evt) begin
                        evt_abort_r <= 1'b1;
                        fl_cnt      <= 12'd0;
                        if (s_sof) begin
                            state   <= ST_ACTIVE;
                            in_row  <= 12'd0;
                            wr_bank <= 2'd0;
                            if (m_words == 12'd1) begin
                                in_w <= 12'd0; in_row <= 12'd1; wr_bank <= 2'd2;
                            end else begin
                                in_w <= 12'd1;
                            end
                        end else begin
                            state   <= ST_IDLE;
                            in_row  <= 12'd0;
                            in_w    <= 12'd0;
                            wr_bank <= 2'd0;
                        end
                    end else if (eof_good) begin
                        state  <= ST_FLUSH;
                        fl_cnt <= 12'd0;
                        if (at_last) begin
                            in_w <= 12'd0; in_row <= in_row + 12'd1;
                            wr_bank <= (wr_bank == 2'd0) ? 2'd2 : (wr_bank == 2'd2) ? 2'd1 : 2'd0;
                        end else begin
                            in_w <= in_w + 12'd1;
                        end
                    end else begin
                        if (at_last) begin
                            in_w <= 12'd0; in_row <= in_row + 12'd1;
                            wr_bank <= (wr_bank == 2'd0) ? 2'd2 : (wr_bank == 2'd2) ? 2'd1 : 2'd0;
                        end else begin
                            in_w <= in_w + 12'd1;
                        end
                    end
                end
            end else if ((state == ST_FLUSH) && en) begin
                if (fl_cnt == m_words) begin
                    state      <= ST_IDLE;
                    evt_good_r <= 1'b1;
                end else begin
                    fl_cnt <= fl_cnt + 12'd1;
                end
            end
        end
    end
endmodule
