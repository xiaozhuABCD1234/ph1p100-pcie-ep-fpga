// algo_rowwin3_p4.v — INT.P4 round3 TIMING-ONLY derived variant of
// fpga/csi2/src/img/algo_rowwin3.v (base file stays read-only; its sha256 is
// bound in INT.P4-r3-manifest.json).  Verilog-2001, async reset, synthesizable.
// SAME module ports, parameters, frame schedule and token sequence as the base;
// the only difference is +1 clock of fixed, uniform output latency.
//
// WHY THIS FILE EXISTS (INT.P4 r2 G2 failure: 112 setup endpoints, WNS -0.637 ns)
// ------------------------------------------------------------------------------
// r2 worst path (5.906 ns, cell 2.304 / net 3.602, 7 logic levels):
//   u_obuf_gau/count_reg[0] -> gray8_gaussian3x3_stream.pipe_en(fo199)
//   -> algo_rowwin3.evt_en(fo155) -> ra0(fo256) -> 320-deep LUT-RAM read mux
//   -> rb0_reg[0].d
// i.e. the row-buffer read enable/address and the deep asynchronous LUT-RAM read
// mux were evaluated in the same 5.333 ns cycle.  This variant registers the
// read address/bank selection so the LUT-RAM address pins are driven by flops,
// and realigns the production path with the SAME fixed +1 cycle:
//
//   1) ra0/ra1/ra2 are captured in ra0_r/ra1_r/ra2_r on evt_en; rb0/rb1/rb2 then
//      read bank0[ra0_r]/bank1[ra1_r]/bank2[ra2_r]  -> rb* is one cycle later.
//   2) cbq/ubq (the bank qualifiers that select rd_c/rd_u) are delayed one cycle
//      (cbq_d/ubq_d) so they stay aligned with the one-cycle-later rb*; the
//      reader pipelines rdc_r1/r2, rdu_r1/r2 inherit the same +1 automatically
//      because they sample rd_c/rd_u on evt_en.
//   3) the stream-side window inputs are delayed one cycle (s_data_d, st_r1_d,
//      st_r2_d) and the production descriptor (prod_valid/prod_y/prod_j/
//      prod_first/prod_last/prod_abort) is presented one cycle later
//      (prod_*_d), so win_*/prod_* keep their exact base-cycle relationship.
//      During a downstream stall (en=0) the delayed descriptor and all delayed
//      data freeze together and are presented on the next en=1 cycle: no token
//      is dropped, duplicated or reordered, and s_ready is bit-identical to the
//      base (en && cfg_ok && rst_n && state!=FLUSH), so the acceptance rate and
//      the backpressure semantics are unchanged.
//
// Everything below (line-buffer banks, write port, frame state machine, events,
// flush schedule, clamping functions) is a verbatim copy of the base file.
// No CDC, no asynchronous FIFO, no clock change, no timing exception, no
// attribute-only change; only the fixed +1 cycle latency at the output boundary.
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
// No board/timing closure is claimed here; the retime is evidenced by the r3
// isolated synthesis (INT.P4/td/r3_run*/) plus the token-sequence equivalence TB.

module algo_rowwin3_p4 #(
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

    // production event of the CURRENT cycle (one cycle before it is presented)
    wire        pv_now = marker_evt || abort_evt || pe || f_cycle;
    wire [11:0] py_now = (marker_evt || abort_evt) ? 12'd0 : (pe ? pe_y : f_y);
    wire [11:0] pj_now = (marker_evt || abort_evt) ? 12'd0 : (pe ? pe_j : f_j);
    wire        pf_now = (pj_now == 12'd0);
    wire        pl_now = (pj_now == mm1);
    wire        pa_now = marker_evt || abort_evt;

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

    // ---- r3 retime: registered LUT-RAM read address/bank (the only change) ----
    // ra* are captured on evt_en, so the 320-deep asynchronous LUT-RAM address
    // pins are driven by flops.  The read is held over gaps/stalls exactly like
    // the base cpa_*/upa_* hold, therefore the LUT-RAM data of an irregular
    // event cannot be overwritten by a speculative next-issue read.
    reg [11:0] ra0_r, ra1_r, ra2_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ra0_r <= 12'd0; ra1_r <= 12'd0; ra2_r <= 12'd0;
        end else if (evt_en) begin
            ra0_r <= ra0; ra1_r <= ra1; ra2_r <= ra2;
        end
    end

    reg [DW-1:0] rb0, rb1, rb2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rb0 <= {DW{1'b0}}; rb1 <= {DW{1'b0}}; rb2 <= {DW{1'b0}};
        end else if (en) begin
            // The read register follows the base's every-cycle read *while the
            // pipeline advances* (en=1 covers both events and input gaps, where
            // ra0_r holds the same address the base would use).  On a stall
            // (en=0) it freezes, so a held token keeps its exact window; the
            // base cannot stall-hold a token, so this is the only extra rule.
            rb0 <= bank0[ra0_r];
            rb1 <= bank1[ra1_r];
            rb2 <= bank2[ra2_r];
        end
    end

    // bank qualifiers travel with rb* (one more cycle than the base cbq/ubq)
    reg [1:0] cbq_d, ubq_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cbq_d <= 2'd0; ubq_d <= 2'd0;
        end else begin
            cbq_d <= cbq; ubq_d <= ubq;
        end
    end

    wire [DW-1:0] rd_c = (cbq_d == 2'd0) ? rb0 : (cbq_d == 2'd1) ? rb1 : rb2;
    wire [DW-1:0] rd_u = (ubq_d == 2'd0) ? rb0 : (ubq_d == 2'd1) ? rb1 : rb2;

    // reader word pipelines: at a production slot, rd_* is word j+1, r1 word j,
    // r2 word j-1 (two events back).  r3: they inherit the +1 read cycle because
    // they sample rd_c/rd_u on evt_en.
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

    // ---- r3 realignment: one-cycle-delayed stream inputs + event descriptor ----
    // The line-buffer data path above is now one cycle later than the base, so the
    // stream-side window inputs and the production descriptor are delayed by the
    // same fixed cycle.  en=0 freezes the whole delayed group (no pop); a held
    // descriptor is consumed on the next en=1 cycle.  s_ready, the frame state
    // machine, the flush schedule and the token order are untouched, so the only
    // observable difference is +1 cycle of fixed latency.
    reg [DW-1:0] s_data_d, st_r1_d, st_r2_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_data_d <= {DW{1'b0}}; st_r1_d <= {DW{1'b0}}; st_r2_d <= {DW{1'b0}};
        end else begin
            // st_r1/st_r2 are themselves gated registers, so an unconditional
            // one-cycle copy is exact (they hold over gaps/stalls and over the
            // flush).  s_data is a live input, so it is loaded on the same event
            // that updates st_r1/st_r2 and freezes otherwise: a held token can
            // never be corrupted by a source that changes s_data while valid=0.
            if (data_beat || frame_start) s_data_d <= s_data;
            st_r1_d <= st_r1;
            st_r2_d <= st_r2;
        end
    end

    reg        prod_valid_d, prod_first_d, prod_last_d, prod_abort_d;
    reg [11:0] prod_y_d, prod_j_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prod_valid_d <= 1'b0; prod_first_d <= 1'b0;
            prod_last_d  <= 1'b0; prod_abort_d <= 1'b0;
            prod_y_d <= 12'd0; prod_j_d <= 12'd0;
        end else if (evt_en) begin
            prod_valid_d <= pv_now;
            prod_y_d     <= py_now;
            prod_j_d     <= pj_now;
            prod_first_d <= pf_now;
            prod_last_d  <= pl_now;
            prod_abort_d <= pa_now;
        end else if (en) begin
            // the downstream advanced this cycle but no new production event exists
            prod_valid_d <= 1'b0;
        end
    end

    // r3: the presented token is the one delayed by the same fixed cycle as the
    // line-buffer read data (declared after the registers to keep every tool's
    // declaration order simple)
    assign prod_valid = prod_valid_d;
    assign prod_y     = prod_y_d;
    assign prod_j     = prod_j_d;
    assign prod_first = prod_first_d;
    assign prod_last  = prod_last_d;
    assign prod_abort = prod_abort_d;

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
        assign win_c = asm40(rd_c, rdc_r1, rdc_r2, prod_first_d, prod_last_d, PAR);
        assign win_u = (prod_y_d == 12'd0)
                     ? (PAR ? asm40(s_data_d, st_r1_d, st_r2_d, prod_first_d, prod_last_d, PAR)
                            : asm40(rd_c, rdc_r1, rdc_r2, prod_first_d, prod_last_d, PAR))
                     : asm40(rd_u, rdu_r1, rdu_r2, prod_first_d, prod_last_d, PAR);
        assign win_d = (prod_y_d == hm1)
                     ? (PAR ? asm40(rd_u, rdu_r1, rdu_r2, prod_first_d, prod_last_d, PAR)
                            : asm40(rd_c, rdc_r1, rdc_r2, prod_first_d, prod_last_d, PAR))
                     : asm40(s_data_d, st_r1_d, st_r2_d, prod_first_d, prod_last_d, PAR);
    end else begin : g_y8
        assign win_c = asm32(rd_c, rdc_r1, rdc_r2, prod_first_d, prod_last_d, PAR);
        assign win_u = (prod_y_d == 12'd0)
                     ? (PAR ? asm32(s_data_d, st_r1_d, st_r2_d, prod_first_d, prod_last_d, PAR)
                            : asm32(rd_c, rdc_r1, rdc_r2, prod_first_d, prod_last_d, PAR))
                     : asm32(rd_u, rdu_r1, rdu_r2, prod_first_d, prod_last_d, PAR);
        assign win_d = (prod_y_d == hm1)
                     ? (PAR ? asm32(rd_u, rdu_r1, rdu_r2, prod_first_d, prod_last_d, PAR)
                            : asm32(rd_c, rdc_r1, rdc_r2, prod_first_d, prod_last_d, PAR))
                     : asm32(s_data_d, st_r1_d, st_r2_d, prod_first_d, prod_last_d, PAR);
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
