// =============================================================================
// integrated_delivery_synth_wrap.v -- INT.P4 ISOLATED-SYNTHESIS HARNESS ONLY.
//
// Why this file exists
// --------------------
// integrated_delivery_top is an integration candidate, not a board shell: it
// exposes capture A/B, the full native 256-bit DDR port, the descriptor/PCIe
// status face, the monitor stream and every observation bus.  That is 2813 IO
// pins, so TD MapIO rejects it (SYN-8228, device max 286) before any timing or
// resource report exists.  This wrapper keeps the frozen DUT bit-for-bit
// unchanged and moves every off-chip interface to an on-chip model so the real
// internal logic can be synthesised, timed and counted:
//
//   * capture A/B      <- on-chip RAW10 frame generators (LFSR payload)
//   * DDR 256-bit port -> on-chip 32 x 256-bit behavioural DDR slave: writes are
//                         captured, one read is outstanding, rdata is returned,
//                         so the store write/read, arbiter and egress data paths
//                         stay live, are counted and are timed
//   * descriptors      <- on-chip A/B descriptor sequencers (self-sustaining)
//   * PCIe backend     <- on-chip busy/done/held + matched ACK model
//   * monitor m_ready  <- periodic backpressure
//   * ~2800 status pins-> 32-bit XOR-reduced observation port + frame counter
//
// COVERAGE BOUNDARY (recorded as the G2 gap, do not over-read this harness)
// -----------------------------------------------------------------------
//   * STA covers internal register-to-register paths of the DUT plus this small
//     harness; it is NOT a board-level sign-off.
//   * Off-chip IO is unconstrained (no package pinout is assigned); the 42 IO in
//     the area report are harness pins only.
//   * No ADC/pin/timing-exception is fabricated: one create_clock (5.333ns,
//     clk) in integrated_core.sdc, no false_path, no multicycle, no clock group.
//   * This file is NOT a board top and must never be presented as one.
//   * Every DUT DDR slave input (ddr_awready/ddr_wready/ddr_arready/ddr_rvalid/
//     ddr_rdata) is driven by the behavioural DDR model below (INT.P4 r2), so
//     u_egress / u_arb / u_store logic is no longer trimmed by constant
//     propagation.
// The DUT source is not modified: only its own logic is being measured, plus
// this small harness (32x256 RAM + counters).  bitgen/CWC/download/Flash are
// not run.
// =============================================================================
`timescale 1ns/1ps

module integrated_delivery_synth_wrap #(
    parameter integer W          = 1920,
    parameter integer H          = 1080,
    parameter integer SLOT_WORDS = 81085
) (
    input  wire        clk,
    input  wire        rst_n,
    output wire [31:0] obs,        // XOR-reduced DUT observation
    output wire [7:0]  frame_cnt   // committed-frame counter (low bits)
);

    localparam integer BEATS = (W / 4) * H;   // packed RAW10 beats per frame

    // ---- harness-driven DUT inputs and harness-consumed DUT outputs ----
    // (declared before first use: implicit 1-bit nets would truncate the 40-bit
    // capture beat and the 256-bit DDR data)
    wire        a_s_valid, a_s_sof, a_s_eol, a_s_eof, a_s_abort;
    wire [39:0] a_s_data;
    wire        b_s_valid, b_s_sof, b_s_eol, b_s_eof, b_s_abort;
    wire [39:0] b_s_data;
    wire        a_s_ready, b_s_ready;
    wire        a_desc_ready, b_desc_ready;
    wire        rel_valid, rel_camera_id, rel_slot_id;
    wire [31:0] rel_epoch, rel_session, rel_capture_seq;
    wire [2:0]  rel_status;
    wire        desc_arm;
    wire [31:0] desc_session_id;
    wire        ddr_awready, ddr_wready, ddr_arready, ddr_rvalid;
    wire [255:0] ddr_rdata;
    wire [31:0] ddr_awaddr, ddr_araddr;
    wire        ddr_awvalid, ddr_wvalid, ddr_arvalid, ddr_rready;
    wire [255:0] ddr_wdata;

    // ------------------------------------------------------------- global time
    reg [31:0] cyc;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cyc <= 32'd0;
        else        cyc <= cyc + 32'd1;
    end

    // ------------------------------------------------------- config / control
    // Mode is swept (1..4) from a free-running divider so no algorithm branch is
    // constant-propagated away; prep toggles with the same divider (pred stays 0
    // because pred without prep is an A+ geometry abort by contract).
    wire [1:0] mode_sel = cyc[15:14];
    wire [2:0] cfg_mode = {1'b0, mode_sel} + 3'd1;
    wire       cfg_prep = cyc[13];
    wire       cfg_pred = 1'b0;

    // ------------------------------------------------------ capture generators
    // INT.P4 r2: the beat presented to the DUT comes from an output register,
    // not combinationally from the generator state machine (a real capture
    // source presents registered beats).  With the r2-1 RTL the synthesis worst
    // path started at gb_reg[1] and ran through the capture/admit and the P1
    // accept logic into the row-buffer read address; a registered source keeps
    // the harness out of that path without changing the stimulus content.
    reg  [1:0]  ga, gb;
    reg  [31:0] ia, ib, gapa, gapb;
    reg  [15:0] ca, cb;              // column within the row (no modulo arithmetic)
    reg  [15:0] lfsr_a, lfsr_b;

    wire [39:0] a_data = {lfsr_a, lfsr_b, 8'h5A};
    wire [39:0] b_data = {lfsr_b, lfsr_a, 8'hA5};

    reg         capv_a, capsof_a, capeol_a, capeof_a;
    reg  [39:0] capd_a;
    reg         capv_b, capsof_b, capeol_b, capeof_b;
    reg  [39:0] capd_b;

    wire a_take = capv_a && a_s_ready;
    wire b_take = capv_b && b_s_ready;
    wire a_last_col = (ca == ((W/4) - 1));
    wire b_last_col = (cb == ((W/4) - 1));
    wire a_form = (ga == 2'd1) && !capv_a;
    wire b_form = (gb == 2'd1) && !capv_b;

    assign a_s_valid = capv_a;
    assign a_s_data  = capd_a;
    assign a_s_sof   = capsof_a;
    assign a_s_eol   = capeol_a;
    assign a_s_eof   = capeof_a;
    assign a_s_abort = 1'b0;

    assign b_s_valid = capv_b;
    assign b_s_data  = capd_b;
    assign b_s_sof   = capsof_b;
    assign b_s_eol   = capeol_b;
    assign b_s_eof   = capeof_b;
    assign b_s_abort = 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ga <= 2'd0; gb <= 2'd0;
            ia <= 32'd0; ib <= 32'd0;
            ca <= 16'd0; cb <= 16'd0;
            gapa <= 32'd7; gapb <= 32'd21;
            lfsr_a <= 16'hACE1; lfsr_b <= 16'h1357;
            capv_a <= 1'b0; capsof_a <= 1'b0; capeol_a <= 1'b0;
            capeof_a <= 1'b0; capd_a <= 40'd0;
            capv_b <= 1'b0; capsof_b <= 1'b0; capeol_b <= 1'b0;
            capeof_b <= 1'b0; capd_b <= 40'd0;
        end else begin
            lfsr_a <= {lfsr_a[14:0], lfsr_a[15] ^ lfsr_a[13] ^ lfsr_a[12] ^ lfsr_a[10]};
            lfsr_b <= {lfsr_b[14:0], lfsr_b[15] ^ lfsr_b[14] ^ lfsr_b[11] ^ lfsr_b[9]};
            if (a_take) capv_a <= 1'b0;
            if (b_take) capv_b <= 1'b0;
            // channel A beat formation
            if (a_form) begin
                capv_a   <= 1'b1;
                capd_a   <= a_data;
                capsof_a <= (ia == 32'd0);
                capeol_a <= a_last_col;
                capeof_a <= (ia == (BEATS - 1));
                if (ia == (BEATS - 1)) begin ga <= 2'd2; gapa <= 32'd31; end
                else                   ia <= ia + 32'd1;
                if (a_last_col) ca <= 16'd0; else ca <= ca + 16'd1;
            end
            // channel B beat formation
            if (b_form) begin
                capv_b   <= 1'b1;
                capd_b   <= b_data;
                capsof_b <= (ib == 32'd0);
                capeol_b <= b_last_col;
                capeof_b <= (ib == (BEATS - 1));
                if (ib == (BEATS - 1)) begin gb <= 2'd2; gapb <= 32'd17; end
                else                   ib <= ib + 32'd1;
                if (b_last_col) cb <= 16'd0; else cb <= cb + 16'd1;
            end
            // idle / tail gaps
            case (ga)
                2'd0: if (gapa == 32'd0) begin ga <= 2'd1; ia <= 32'd0; ca <= 16'd0; end
                      else gapa <= gapa - 32'd1;
                2'd1: ;   // beat formation above
                default: if (gapa == 32'd0) ga <= 2'd0; else gapa <= gapa - 32'd1;
            endcase
            case (gb)
                2'd0: if (gapb == 32'd0) begin gb <= 2'd1; ib <= 32'd0; cb <= 16'd0; end
                      else gapb <= gapb - 32'd1;
                2'd1: ;   // beat formation above
                default: if (gapb == 32'd0) gb <= 2'd0; else gapb <= gapb - 32'd1;
            endcase
        end
    end

    // ------------------------------------------------- capture descriptor flow
    reg        a_pend, b_pend;
    reg [31:0] seq_a, seq_b, epoch_a, epoch_b;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_pend <= 1'b1; b_pend <= 1'b1;
            seq_a <= 32'd1; seq_b <= 32'd1;
            epoch_a <= 32'd1; epoch_b <= 32'd1;
        end else begin
            if (a_pend && a_desc_ready) begin
                a_pend  <= 1'b0;
                seq_a   <= seq_a + 32'd1;
                epoch_a <= epoch_a + 32'd1;
            end else if (rel_valid && (rel_camera_id == 1'b0)) begin
                a_pend  <= 1'b1;
            end
            if (b_pend && b_desc_ready) begin
                b_pend  <= 1'b0;
                seq_b   <= seq_b + 32'd1;
                epoch_b <= epoch_b + 32'd1;
            end else if (rel_valid && (rel_camera_id == 1'b1)) begin
                b_pend  <= 1'b1;
            end
        end
    end

    // ------------------------------------------------------------ DDR model
    // INT.P4 r2: the DUT's DDR *slave* inputs are now fully driven here.  In r1
    // ddr_awready/ddr_wready/ddr_arready/ddr_rvalid/ddr_rdata were declared but
    // never assigned (HDL-5314 "does not have a driver"), so the store write
    // handshake, the arbiter and the egress read path were constant-propagated
    // away and could not be counted or timed.  This is a behavioural single-
    // outstanding DDR slave: writes are accepted immediately, one read is
    // outstanding, rdata comes from the small on-chip array.
    reg [255:0] ddr_mem [0:31];
    reg         rd_v;
    reg [255:0] rd_d;
    wire        wr_hs  = ddr_awvalid && ddr_awready && ddr_wvalid && ddr_wready;
    wire        ar_hs  = ddr_arvalid && ddr_arready;
    wire        rd_hs  = ddr_rvalid && ddr_rready;

    assign ddr_awready = rst_n;
    assign ddr_wready  = rst_n;
    assign ddr_arready = rst_n && !rd_v;
    assign ddr_rvalid  = rd_v;
    assign ddr_rdata   = rd_d;

    always @(posedge clk) begin
        if (wr_hs) ddr_mem[ddr_awaddr[4:0]] <= ddr_wdata;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_v <= 1'b0;
            rd_d <= 256'd0;
        end else if (ar_hs) begin
            rd_d <= ddr_mem[ddr_araddr[4:0]];
            rd_v <= 1'b1;
        end else if (rd_hs) begin
            rd_v <= 1'b0;
        end
    end

    // ------------------------------------------------------- PCIe backend model
    localparam [1:0] P_IDLE = 2'd0, P_BUSY = 2'd1, P_ACK = 2'd2;
    reg  [1:0]  ps;
    reg  [7:0]  pcnt;
    reg         pcie_busy, pcie_done, pcie_held, pcie_err;
    reg  [31:0] pcie_held_seq, pcie_held_sess, seq_gen;
    reg         ack_pulse;
    reg  [31:0] ack_seq, ack_session;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ps <= P_IDLE; pcnt <= 8'd0;
            pcie_busy <= 1'b0; pcie_done <= 1'b0; pcie_held <= 1'b0;
            pcie_err <= 1'b0;
            pcie_held_seq <= 32'd0; pcie_held_sess <= 32'd0;
            seq_gen <= 32'd1;
            ack_pulse <= 1'b0; ack_seq <= 32'd0; ack_session <= 32'd0;
        end else begin
            pcie_done  <= 1'b0;
            ack_pulse  <= 1'b0;
            case (ps)
                P_IDLE: begin
                    pcie_busy <= 1'b0;
                    if (desc_arm) begin
                        pcie_busy <= 1'b1;
                        pcnt      <= 8'd12;
                        ps        <= P_BUSY;
                    end
                end
                P_BUSY: begin
                    if (pcnt == 8'd0) begin
                        pcie_done      <= 1'b1;
                        pcie_held      <= 1'b1;
                        pcie_held_seq  <= seq_gen;
                        pcie_held_sess <= desc_session_id;
                        seq_gen        <= seq_gen + 32'd1;
                        pcnt           <= 8'd24;
                        ps             <= P_ACK;
                    end else begin
                        pcnt <= pcnt - 8'd1;
                    end
                end
                P_ACK: begin
                    pcie_busy <= 1'b0;
                    if (pcnt == 8'd0) begin
                        ack_pulse   <= 1'b1;
                        ack_seq     <= pcie_held_seq;
                        ack_session <= pcie_held_sess;
                        pcie_held   <= 1'b0;
                        ps          <= P_IDLE;
                    end else begin
                        pcnt <= pcnt - 8'd1;
                    end
                end
                default: ps <= P_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------ monitor sink
    // Periodic monitor backpressure (4 of 8 cycles ready) so the P1 shared-stream
    // handshake and the selected-output routing stay live and timed.
    wire m_ready = ~cyc[2];

    // ---------------------------------------------------------------- DUT wires
    wire        slot_release;
    wire [31:0] desc_cap_bytes, desc_frame_bytes, desc_stream_len;
    wire [31:0] desc_slot_base_word;
    wire [63:0] desc_dst_base, desc_db_addr;
    wire        desc_src_sel, desc_cam_sel;
    wire        desc_ident_valid, desc_camera_id, desc_slot_id;
    wire [31:0] desc_epoch, desc_capture_seq;
    wire        mon_accept, m_valid, m_is_raw;
    wire [2:0]  m_mode;
    wire [39:0] m_raw_data;
    wire [31:0] m_proc_data;
    wire        m_sof, m_eol, m_eof, m_abort;
    wire [31:0] ap_data;
    wire        ap_valid, ap_last, ap_accept, ap_commit, ap_abort;
    wire [3:0]  ap_keep;
    wire [39:0] pk_data;
    wire        pk_accept;
    wire [255:0] drain_data;
    wire        drain_accept;
    wire [31:0] st_raw_len, st_xform_len, st_stream_len;
    wire [31:0] st_raw_crc, st_xform_crc, st_stream_crc, st_blocks, st_stall;
    wire [15:0] st_p1_good, st_p1_abort;
    wire [31:0] st_store_published, st_store_dropped, st_store_errors;
    wire [31:0] st_exported, st_adapter_err;
    wire        st_adapter_busy, st_adapter_held;
    wire [31:0] st_frames_committed, st_frames_aborted;
    wire [31:0] st_release_count, st_admit_count, st_drain_words, st_cfg_error;
    wire [15:0] st_sched_accepted, st_sched_completed, st_sched_failed, st_sched_rejected;
    wire        st_sched_a_busy, st_sched_b_busy, st_sched_last_cam;
    wire [3:0]  st_glue_state;

    // ----------------------------------------------------------------- the DUT
    integrated_delivery_top #(
        .W(W), .H(H), .SLOT_WORDS(SLOT_WORDS)
    ) u_dut (
        .clk(clk), .rst_n(rst_n),
        .a_s_valid(a_s_valid), .a_s_ready(a_s_ready), .a_s_data(a_s_data),
        .a_s_sof(a_s_sof), .a_s_eol(a_s_eol), .a_s_eof(a_s_eof),
        .a_s_abort(a_s_abort),
        .b_s_valid(b_s_valid), .b_s_ready(b_s_ready), .b_s_data(b_s_data),
        .b_s_sof(b_s_sof), .b_s_eol(b_s_eol), .b_s_eof(b_s_eof),
        .b_s_abort(b_s_abort),
        .cfg_mode(cfg_mode), .cfg_phase(2'd3),
        .cfg_aplus_prep(cfg_prep), .cfg_aplus_pred(cfg_pred),
        .push_en(1'b1), .cap_bytes(32'h00FF_FFFF), .session_id(32'h0000_1234),
        .dst_base(64'h0000_0000_1000_0000), .db_addr(64'h0000_0000_2000_0000),
        .mps_code(3'd1), .link_up(1'b1),
        .a_desc_valid(a_pend), .a_desc_ready(a_desc_ready),
        .a_desc_camera_id(1'b0), .a_desc_slot_id(cyc[0]),
        .a_desc_epoch(epoch_a), .a_desc_session(32'h0000_1234),
        .a_desc_capture_seq(seq_a),
        .b_desc_valid(b_pend), .b_desc_ready(b_desc_ready),
        .b_desc_camera_id(1'b1), .b_desc_slot_id(cyc[1]),
        .b_desc_epoch(epoch_b), .b_desc_session(32'h0000_1234),
        .b_desc_capture_seq(seq_b),
        .a_enable(1'b1), .b_priority(cyc[12]),
        .ack_pulse(ack_pulse), .ack_seq(ack_seq), .ack_session(ack_session),
        .cancel_pulse(1'b0),
        .pcie_busy(pcie_busy), .pcie_held(pcie_held), .pcie_done(pcie_done),
        .pcie_err(pcie_err), .pcie_held_seq(pcie_held_seq),
        .pcie_held_sess(pcie_held_sess),
        .ddr_ready(1'b1),
        .ddr_awaddr(ddr_awaddr), .ddr_awvalid(ddr_awvalid), .ddr_awready(ddr_awready),
        .ddr_wdata(ddr_wdata), .ddr_wvalid(ddr_wvalid), .ddr_wready(ddr_wready),
        .ddr_araddr(ddr_araddr), .ddr_arvalid(ddr_arvalid), .ddr_arready(ddr_arready),
        .ddr_rdata(ddr_rdata), .ddr_rvalid(ddr_rvalid), .ddr_rready(ddr_rready),
        .desc_arm(desc_arm), .desc_cap_bytes(desc_cap_bytes),
        .desc_session_id(desc_session_id), .desc_dst_base(desc_dst_base),
        .desc_db_addr(desc_db_addr), .desc_frame_bytes(desc_frame_bytes),
        .desc_stream_len(desc_stream_len),
        .desc_slot_base_word(desc_slot_base_word), .desc_src_sel(desc_src_sel),
        .desc_cam_sel(desc_cam_sel), .slot_release(slot_release),
        .desc_ident_valid(desc_ident_valid), .desc_camera_id(desc_camera_id),
        .desc_slot_id(desc_slot_id), .desc_epoch(desc_epoch),
        .desc_capture_seq(desc_capture_seq),
        .rel_valid(rel_valid), .rel_camera_id(rel_camera_id),
        .rel_slot_id(rel_slot_id), .rel_epoch(rel_epoch),
        .rel_session(rel_session), .rel_capture_seq(rel_capture_seq),
        .rel_status(rel_status),
        .m_ready(m_ready), .mon_accept(mon_accept), .m_valid(m_valid),
        .m_mode(m_mode), .m_is_raw(m_is_raw), .m_raw_data(m_raw_data),
        .m_proc_data(m_proc_data), .m_sof(m_sof), .m_eol(m_eol),
        .m_eof(m_eof), .m_abort(m_abort),
        .ap_data(ap_data), .ap_valid(ap_valid), .ap_keep(ap_keep),
        .ap_last(ap_last), .ap_accept(ap_accept), .ap_commit(ap_commit),
        .ap_abort(ap_abort),
        .pk_data(pk_data), .pk_accept(pk_accept),
        .drain_data(drain_data), .drain_accept(drain_accept),
        .st_raw_len(st_raw_len), .st_xform_len(st_xform_len),
        .st_stream_len(st_stream_len), .st_raw_crc(st_raw_crc),
        .st_xform_crc(st_xform_crc), .st_stream_crc(st_stream_crc),
        .st_blocks(st_blocks), .st_stall(st_stall),
        .st_p1_good(st_p1_good), .st_p1_abort(st_p1_abort),
        .st_store_published(st_store_published), .st_store_dropped(st_store_dropped),
        .st_store_errors(st_store_errors), .st_exported(st_exported),
        .st_adapter_err(st_adapter_err), .st_adapter_busy(st_adapter_busy),
        .st_adapter_held(st_adapter_held),
        .st_frames_committed(st_frames_committed),
        .st_frames_aborted(st_frames_aborted),
        .st_release_count(st_release_count), .st_admit_count(st_admit_count),
        .st_drain_words(st_drain_words), .st_cfg_error(st_cfg_error),
        .st_sched_accepted(st_sched_accepted),
        .st_sched_completed(st_sched_completed),
        .st_sched_failed(st_sched_failed), .st_sched_rejected(st_sched_rejected),
        .st_sched_a_busy(st_sched_a_busy), .st_sched_b_busy(st_sched_b_busy),
        .st_sched_last_cam(st_sched_last_cam), .st_glue_state(st_glue_state)
    );

    // ------------------------------------------------------- observation reduce
    // Registered so the reduction is a normal reg-to-reg path with the full clock
    // budget (and so the harness adds no combinational pad path of its own).
    reg  [31:0] obs_r;
    reg  [7:0]  fcnt_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            obs_r  <= 32'd0;
            fcnt_r <= 8'd0;
        end else begin
            obs_r  <= st_raw_len ^ st_xform_len ^ st_stream_len ^
                      st_raw_crc ^ st_xform_crc ^ st_stream_crc ^
                      st_blocks ^ st_stall ^
                      st_store_published ^ st_store_dropped ^ st_store_errors ^
                      st_exported ^ st_adapter_err ^ st_frames_committed ^
                      st_frames_aborted ^ st_release_count ^ st_admit_count ^
                      st_drain_words ^ st_cfg_error ^
                      {16'd0, st_sched_accepted} ^ {16'd0, st_sched_completed} ^
                      {16'd0, st_sched_failed} ^ {16'd0, st_sched_rejected} ^
                      {16'd0, st_p1_good} ^ {16'd0, st_p1_abort} ^
                      {28'd0, st_glue_state} ^
                      {29'd0, st_sched_a_busy, st_sched_b_busy, st_sched_last_cam} ^
                      {31'd0, st_adapter_busy, st_adapter_held} ^
                      {31'd0, desc_arm, desc_src_sel, desc_cam_sel, desc_ident_valid} ^
                      {31'd0, rel_valid, rel_status} ^
                      desc_cap_bytes ^ desc_session_id ^ desc_frame_bytes ^
                      desc_stream_len ^ desc_slot_base_word ^
                      desc_dst_base[31:0] ^ desc_dst_base[63:32] ^
                      desc_db_addr[31:0] ^ desc_db_addr[63:32] ^
                      {31'd0, desc_camera_id, desc_slot_id} ^ desc_epoch ^
                      desc_capture_seq ^ rel_epoch ^ rel_session ^ rel_capture_seq ^
                      {31'd0, rel_camera_id, rel_slot_id} ^
                      m_proc_data ^ {24'd0, m_mode} ^
                      {7'd0, ap_keep, ap_last, ap_accept, ap_commit, ap_abort} ^
                      ap_data ^ pk_data[39:8] ^
                      {24'd0, m_valid, m_is_raw, m_sof, m_eol, m_eof, m_abort, mon_accept} ^
                      drain_data[31:0] ^ drain_data[63:32] ^ drain_data[95:64] ^
                      drain_data[127:96] ^ drain_data[159:128] ^ drain_data[191:160] ^
                      drain_data[223:192] ^ drain_data[255:224];
            fcnt_r <= st_frames_committed[7:0];
        end
    end

    assign obs       = obs_r;
    assign frame_cnt = fcnt_r;

endmodule
