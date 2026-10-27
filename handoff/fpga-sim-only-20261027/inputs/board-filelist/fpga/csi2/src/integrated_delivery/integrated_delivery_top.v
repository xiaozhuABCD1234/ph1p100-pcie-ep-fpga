`timescale 1ns/1ps
// =============================================================================
// integrated_delivery_top.v -- INT.P4 same-candidate integrated delivery.
//
// ONE top that chains, in a single clk/rst_n domain:
//
//   capture A / capture B  (40-bit RAW10 4-sample beats + sof/eol/eof/abort)
//        |  (frame-granular source mux, selected by the P3 capture descriptor)
//        v
//   integrated_input_processing_top (INT.P1 frozen r1)
//        |-- pk_*  packed RAW10 byte stream (5 B per 4 px)  -> A+ entrance
//        `-- m_*   selected monitor stream (Y8 in modes 1/2/3, raw in 0/4)
//        v
//   a1_frame_top (b20 r0 READ-ONLY candidate)  ->  zlib stream words
//        v
//   a1_ddr_slot_store (MODE=1, b20 r0 READ-ONLY)  ->  2-slot 256-bit DDR store
//        v  (native 256-bit port through a1_ddr_arb2, b20 r0 READ-ONLY)
//   aplus_pcie_egress_adapter (INT.P2 frozen r0)  ->  descriptor face
//        v
//   PCIe backend descriptor face (arm + descriptor regs + identity + status)
//
//   dual_channel_capture_scheduler (INT.P3 frozen r1) provides A/B identity,
//   a_enable gating, B-first / round-robin arbitration and the full-field
//   release handshake that closes the ownership loop after host ACK.
//
// Contract notes (see INT.P4-protocol.md):
//  * Single clock domain, target 187.5 MHz (5.333 ns).  No CDC, no async FIFO.
//  * Format separation: pk_*/A+ carry packed RAW10 only; m_* carries the P1
//    selected output (Y8 for modes 1..3, raw 4x10-bit for modes 0/4).  The two
//    formats are never mixed.
//  * Pipeline depth is one frame end-to-end: a capture descriptor is admitted
//    only when the store has a free slot, no slot is READY, the egress adapter
//    is idle and no drain is in progress.  Frames are therefore never lost to a
//    missed publish; deeper overlap is a documented performance gap (G4).
//  * s_ready of a non-granted channel stays low, which is the capture-window
//    backpressure model of this integration (per-channel capture staging is a
//    documented gap, not a stub).
//  * No module here is a placeholder: every module named above is the frozen
//    production/read-only implementation.
// =============================================================================
module integrated_delivery_top #(
    parameter integer W             = 1920,
    parameter integer H             = 1080,
    parameter integer MAX_WORDS     = 512,
    parameter integer SLOT_WORDS    = 81085,
    parameter [31:0]  SLOT_BASE_WORD = 32'd0,
    parameter integer SLOT_AWB      = 18,
    parameter [31:0]  ALIGN_BYTES   = 32'd4096
) (
    input  wire         clk,
    input  wire         rst_n,

    // ---------------- capture source A (camera_id = 0) ----------------
    input  wire         a_s_valid,
    output wire         a_s_ready,
    input  wire [39:0]  a_s_data,
    input  wire         a_s_sof,
    input  wire         a_s_eol,
    input  wire         a_s_eof,
    input  wire         a_s_abort,

    // ---------------- capture source B (camera_id = 1) ----------------
    input  wire         b_s_valid,
    output wire         b_s_ready,
    input  wire [39:0]  b_s_data,
    input  wire         b_s_sof,
    input  wire         b_s_eol,
    input  wire         b_s_eof,
    input  wire         b_s_abort,

    // ---------------- host configuration ----------------
    input  wire [2:0]   cfg_mode,          // P1 output mode 0..4
    input  wire [1:0]   cfg_phase,
    input  wire         cfg_aplus_prep,    // A+ Bayer plane reorder enable
    input  wire         cfg_aplus_pred,    // A+ 2-plane predictor enable

    // ---------------- PCIe/egress configuration ----------------
    input  wire         push_en,
    input  wire [31:0]  cap_bytes,
    input  wire [31:0]  session_id,
    input  wire [63:0]  dst_base,
    input  wire [63:0]  db_addr,
    input  wire [2:0]   mps_code,
    input  wire         link_up,

    // ---------------- P3 capture descriptors ----------------
    input  wire         a_desc_valid,
    output wire         a_desc_ready,
    input  wire         a_desc_camera_id,
    input  wire         a_desc_slot_id,
    input  wire [31:0]  a_desc_epoch,
    input  wire [31:0]  a_desc_session,
    input  wire [31:0]  a_desc_capture_seq,

    input  wire         b_desc_valid,
    output wire         b_desc_ready,
    input  wire         b_desc_camera_id,
    input  wire         b_desc_slot_id,
    input  wire [31:0]  b_desc_epoch,
    input  wire [31:0]  b_desc_session,
    input  wire [31:0]  b_desc_capture_seq,

    input  wire         a_enable,
    input  wire         b_priority,

    // ---------------- host ACK / cancel ----------------
    input  wire         ack_pulse,
    input  wire [31:0]  ack_seq,
    input  wire [31:0]  ack_session,
    input  wire         cancel_pulse,

    // ---------------- PCIe backend status ----------------
    input  wire         pcie_busy,
    input  wire         pcie_held,
    input  wire         pcie_done,
    input  wire         pcie_err,
    input  wire [31:0]  pcie_held_seq,
    input  wire [31:0]  pcie_held_sess,

    // ---------------- native 256-bit DDR port ----------------
    input  wire         ddr_ready,
    output wire [31:0]  ddr_awaddr,
    output wire         ddr_awvalid,
    input  wire         ddr_awready,
    output wire [255:0] ddr_wdata,
    output wire         ddr_wvalid,
    input  wire         ddr_wready,
    output wire [31:0]  ddr_araddr,
    output wire         ddr_arvalid,
    input  wire         ddr_arready,
    input  wire [255:0] ddr_rdata,
    input  wire         ddr_rvalid,
    output wire         ddr_rready,

    // ---------------- PCIe descriptor face (P2 adapter outputs) ----------------
    output wire         desc_arm,
    output wire [31:0]  desc_cap_bytes,
    output wire [31:0]  desc_session_id,
    output wire [63:0]  desc_dst_base,
    output wire [63:0]  desc_db_addr,
    output wire [31:0]  desc_frame_bytes,
    output wire [31:0]  desc_stream_len,
    output wire [31:0]  desc_slot_base_word,
    output wire         desc_src_sel,
    output wire         desc_cam_sel,
    output wire         slot_release,
    // identity that travels beside the wire descriptor
    output wire         desc_ident_valid,
    output wire         desc_camera_id,
    output wire         desc_slot_id,
    output wire [31:0]  desc_epoch,
    output wire [31:0]  desc_capture_seq,

    // ---------------- full-field release back to the capture scheduler -------
    output wire         rel_valid,
    output wire         rel_camera_id,
    output wire         rel_slot_id,
    output wire [31:0]  rel_epoch,
    output wire [31:0]  rel_session,
    output wire [31:0]  rel_capture_seq,
    output wire [2:0]   rel_status,

    // ---------------- P1 selected monitor stream (Y8 or RAW) ----------------
    input  wire         m_ready,
    output wire         mon_accept,      // true transfer of the selected stream
    output wire         m_valid,
    output wire [2:0]   m_mode,
    output wire         m_is_raw,
    output wire [39:0]  m_raw_data,
    output wire [31:0]  m_proc_data,
    output wire         m_sof,
    output wire         m_eol,
    output wire         m_eof,
    output wire         m_abort,

    // ---------------- A+ stream observation (exactly the stored beats) ------
    output wire [31:0]  ap_data,
    output wire         ap_valid,
    output wire [3:0]   ap_keep,
    output wire         ap_last,
    output wire         ap_accept,
    output wire         ap_commit,
    output wire         ap_abort,

    // ---------------- packed RAW10 accepted by the A+ entrance --------------
    output wire [39:0]  pk_data,
    output wire         pk_accept,

    // ---------------- drained slot observation (release path) --------------
    output wire [255:0] drain_data,
    output wire         drain_accept,

    // ---------------- A+ per-frame observation ----------------
    output wire [31:0]  st_raw_len,
    output wire [31:0]  st_xform_len,
    output wire [31:0]  st_stream_len,
    output wire [31:0]  st_raw_crc,
    output wire [31:0]  st_xform_crc,
    output wire [31:0]  st_stream_crc,
    output wire [31:0]  st_blocks,
    output wire [31:0]  st_stall,

    // ---------------- P1 status ----------------
    output wire [15:0]  st_p1_good,
    output wire [15:0]  st_p1_abort,

    // ---------------- store / egress / glue status ----------------
    output wire [31:0]  st_store_published,
    output wire [31:0]  st_store_dropped,
    output wire [31:0]  st_store_errors,
    output wire [31:0]  st_exported,
    output wire [31:0]  st_adapter_err,
    output wire         st_adapter_busy,
    output wire         st_adapter_held,
    output wire [31:0]  st_frames_committed,
    output wire [31:0]  st_frames_aborted,
    output wire [31:0]  st_release_count,
    output wire [31:0]  st_admit_count,
    output wire [31:0]  st_drain_words,
    output wire [31:0]  st_cfg_error,

    // ---------------- P3 scheduler status ----------------
    output wire [15:0]  st_sched_accepted,
    output wire [15:0]  st_sched_completed,
    output wire [15:0]  st_sched_failed,
    output wire [15:0]  st_sched_rejected,
    output wire         st_sched_a_busy,
    output wire         st_sched_b_busy,
    output wire         st_sched_last_cam,
    output wire [3:0]   st_glue_state
);

    // =============================================================== declarations
    // ---- P3 scheduler ----
    wire        sched_o_valid, sched_o_ready;
    wire        sched_o_camera, sched_o_slot;
    wire [31:0] sched_o_epoch, sched_o_session, sched_o_seq;
    wire        sched_rel_ready;

    // ---- glue state ----
    reg  [3:0]  gs;
    reg         active_cam;
    reg         f_slot;
    reg  [31:0] f_epoch, f_session, f_seq;
    reg         wr_started;
    reg         wr_begin;
    reg         wr_abort;
    reg         rel_status_r;
    reg         rel_pulse;
    reg         wd_en;
    reg  [15:0] wd_cnt;
    reg  [2:0]  cfg_mode_r;
    reg  [1:0]  cfg_phase_r;
    wire        cfg_dirty;

    // ---- P1 ----
    wire        p1_cfg_ready, p1_cfg_error, p1_cfg_valid;
    wire        p1_s_ready;
    wire        cap_valid;
    wire [39:0] cap_data;
    wire        cap_sof, cap_eol, cap_eof, cap_abort;
    wire        p1_pk_valid, p1_pk_sof, p1_pk_abort, p1_pk_ready, p1_pk_eof;
    wire [39:0] p1_pk_data;
    wire        p1_m_valid, p1_m_is_raw;
    wire [2:0]  p1_m_mode;
    wire [39:0] p1_m_raw;
    wire [31:0] p1_m_proc;
    wire        p1_m_sof, p1_m_eol, p1_m_eof, p1_m_abort;

    // ---- A+ core ----
    wire [31:0] ap_st_raw_len, ap_st_xform_len, ap_st_stream_len;
    wire [31:0] ap_st_raw_crc, ap_st_xform_crc, ap_st_stream_crc;
    wire [31:0] ap_st_blocks, ap_st_stall;
    wire        ap_st_busy;
    wire        ap_in_ready;
    wire [31:0] core_out_data;
    wire        core_out_valid, core_out_last, core_out_ready;
    wire [3:0]  core_out_keep;
    wire        core_commit, core_frame_abort;

    // ---- store ----
    wire        store_wr_ready;
    wire        store_begin_ready;
    wire        store_rd_open_ready;
    wire [31:0] store_rd_id, store_rd_len;
    wire [255:0] store_rd_data;
    wire        store_rd_valid;
    wire [31:0] store_published, store_dropped, store_errors;
    wire        store_free_valid;
    wire [31:0] store_slot_st;
    wire [31:0] store_awaddr, store_araddr;
    wire        store_awvalid, store_awready, store_wvalid, store_wready;
    wire [255:0] store_wdata;
    wire        store_arvalid, store_arready, store_rvalid, store_rready;
    wire [255:0] store_rdata;

    // ---- publish detect ----
    reg  [3:0]  slot_st_q;
    wire [1:0]  slot0_st, slot1_st;
    wire        pub_evt, pub_slot, store_has_ready;
    reg         pub_pulse;
    reg  [31:0] pub_id, pub_len;
    reg         pub_slot_r;

    // ---- egress adapter ----
    wire [31:0] egress_cap_bytes, egress_session, egress_frame_bytes;
    wire [31:0] egress_stream_len, egress_slot_base;
    wire [63:0] egress_dst, egress_db;
    wire        egress_src_sel, egress_cam_sel, egress_arm;
    wire [31:0] egress_exported;
    wire [7:0]  egress_err;
    wire        egress_busy, egress_held;

    // ---- drain engine ----
    reg  [1:0]  dr;
    reg         drain_req;
    reg  [31:0] dr_len, dr_words, dr_cnt;
    reg         dr_done;
    reg  [31:0] drain_words_total;
    wire        rd_open, rd_close, drain_take;
    wire        drain_busy;

    // ---- misc ----
    reg         core_abort_q;
    wire        core_abort_evt;
    reg  [31:0] committed_cnt, aborted_cnt, release_cnt, admit_cnt;
    wire        admit_ok;

    // ---- INT.P4 r1 frame integrity guard (F1) ----
    // A frame may only be stored as a COMPLETE frame.  The glue counts the
    // packed-RAW10 beats actually transferred into the A+ entrance and requires
    // exactly W*H/4 beats plus exactly one EOF marker.  The store's write-last is
    // gated by that verdict and the commit path re-checks it, so a truncated or
    // mis-fed frame can never be published/exported as a successful frame.
    localparam [31:0] EXPECT_BEATS = (W * H) / 4;
    localparam [31:0] FRAME_WD     = 32'h0400_0000;  // ~341 ms @187.5 MHz
    reg  [31:0] pk_cnt, pk_eof_cnt;
    reg         int_ok_r;
    reg  [31:0] run_wd;
    reg         glue_abort;
    wire        pk_tr = p1_pk_valid && p1_pk_ready;
    wire        store_wr_last = core_out_last && int_ok_r;
    wire        core_abort_in = p1_pk_abort || glue_abort;
    wire        commit_ok = core_commit && int_ok_r;

    localparam [3:0] GS_IDLE = 4'd0, GS_CFG = 4'd1, GS_BEGIN = 4'd2,
                     GS_RUN  = 4'd3, GS_WAIT_PUB = 4'd4, GS_WAIT_REL = 4'd5,
                     GS_DRAIN = 4'd6;
    localparam [1:0] DR_IDLE = 2'd0, DR_OPEN = 2'd1, DR_TAKE = 2'd2,
                     DR_CLOSE = 2'd3;

    // =========================================================== P3 scheduler
    dual_channel_capture_scheduler #(.CNT_WIDTH(16)) u_sched (
        .clk(clk), .rst_n(rst_n),
        .a_desc_valid(a_desc_valid), .a_desc_ready(a_desc_ready),
        .a_desc_camera_id(a_desc_camera_id), .a_desc_slot_id(a_desc_slot_id),
        .a_desc_epoch(a_desc_epoch), .a_desc_session(a_desc_session),
        .a_desc_capture_seq(a_desc_capture_seq),
        .b_desc_valid(b_desc_valid), .b_desc_ready(b_desc_ready),
        .b_desc_camera_id(b_desc_camera_id), .b_desc_slot_id(b_desc_slot_id),
        .b_desc_epoch(b_desc_epoch), .b_desc_session(b_desc_session),
        .b_desc_capture_seq(b_desc_capture_seq),
        .o_valid(sched_o_valid), .o_ready(sched_o_ready),
        .o_camera_id(sched_o_camera), .o_slot_id(sched_o_slot),
        .o_epoch(sched_o_epoch), .o_session(sched_o_session),
        .o_capture_seq(sched_o_seq),
        .rel_valid(rel_valid), .rel_ready(sched_rel_ready),
        .rel_camera_id(rel_camera_id), .rel_slot_id(rel_slot_id),
        .rel_epoch(rel_epoch), .rel_session(rel_session),
        .rel_capture_seq(rel_capture_seq), .rel_status(rel_status),
        .a_enable(a_enable), .b_priority(b_priority),
        .st_accepted(st_sched_accepted), .st_completed(st_sched_completed),
        .st_failed(st_sched_failed), .st_rejected(st_sched_rejected),
        .st_busy(), .st_a_busy(st_sched_a_busy), .st_b_busy(st_sched_b_busy),
        .st_last_camera(st_sched_last_cam)
    );

    // =========================================================== capture mux
    assign cap_valid = (gs == GS_RUN) ? (active_cam ? b_s_valid : a_s_valid) : 1'b0;
    assign cap_data  = active_cam ? b_s_data  : a_s_data;
    assign cap_sof   = active_cam ? b_s_sof   : a_s_sof;
    assign cap_eol   = active_cam ? b_s_eol   : a_s_eol;
    assign cap_eof   = active_cam ? b_s_eof   : a_s_eof;
    // Abort is only presented while the frame is running; outside GS_RUN it is
    // masked so a latched source abort can never hold the A+ core out of idle.
    assign cap_abort = (gs == GS_RUN) ? (active_cam ? b_s_abort : a_s_abort) : 1'b0;

    assign a_s_ready = (gs == GS_RUN) && !active_cam && p1_s_ready;
    assign b_s_ready = (gs == GS_RUN) &&  active_cam && p1_s_ready;

    assign cfg_dirty  = (cfg_mode != cfg_mode_r) || (cfg_phase != cfg_phase_r);
    assign p1_cfg_valid = cfg_dirty && p1_cfg_ready;

    // =========================================================== P1 instance
    integrated_input_processing_top #(
        .MAX_WORDS(MAX_WORDS), .WIDTH(W), .HEIGHT(H)
    ) u_p1 (
        .clk(clk), .rst_n(rst_n),
        .cfg_valid(p1_cfg_valid), .cfg_ready(p1_cfg_ready),
        .cfg_width(W[11:0]), .cfg_height(H[11:0]), .cfg_phase(cfg_phase),
        .cfg_mode(cfg_mode), .cfg_error(p1_cfg_error),
        .s_valid(cap_valid), .s_ready(p1_s_ready), .s_data(cap_data),
        .s_sof(cap_sof), .s_eol(cap_eol), .s_eof(cap_eof), .s_abort(cap_abort),
        .m_ready(m_ready), .m_valid(p1_m_valid), .m_mode(p1_m_mode),
        .m_is_raw(p1_m_is_raw), .m_raw_data(p1_m_raw), .m_proc_data(p1_m_proc),
        .m_sof(p1_m_sof), .m_eol(p1_m_eol), .m_eof(p1_m_eof), .m_abort(p1_m_abort),
        .pk_ready(p1_pk_ready), .pk_valid(p1_pk_valid), .pk_data(p1_pk_data),
        .pk_sof(p1_pk_sof), .pk_eol(), .pk_eof(p1_pk_eof), .pk_abort(p1_pk_abort),
        .st_frames_good(st_p1_good), .st_frames_abort(st_p1_abort)
    );

    assign m_valid     = p1_m_valid;
    assign m_mode      = p1_m_mode;
    assign m_is_raw    = p1_m_is_raw;
    assign m_raw_data  = p1_m_raw;
    assign m_proc_data = p1_m_proc;
    assign m_sof       = p1_m_sof;
    assign m_eol       = p1_m_eol;
    assign m_eof       = p1_m_eof;
    assign m_abort     = p1_m_abort;
    // In the raw modes the P1 monitor valid is already gated by m_ready, so the
    // real transfer of the selected stream is the accepted input beat.  This is
    // the accepted-beat indication used by the testbench monitor.
    assign mon_accept  = ((p1_m_mode == 3'd0) || (p1_m_mode == 3'd4))
                         ? (cap_valid && p1_s_ready)
                         : (p1_m_valid && m_ready);

    // =========================================================== A+ core
    a1_frame_top #(.W(W), .H(H)) u_aplus (
        .clk(clk), .rst_n(rst_n),
        .in_pix(p1_pk_data), .in_valid(p1_pk_valid), .in_ready(ap_in_ready),
        .in_sof(p1_pk_sof),
        .prep_en(cfg_aplus_prep), .pred_en(cfg_aplus_pred), .abort(core_abort_in),
        .out_data(core_out_data), .out_valid(core_out_valid),
        .out_ready(core_out_ready), .out_keep(core_out_keep),
        .out_last(core_out_last), .frame_commit(core_commit),
        .frame_abort(core_frame_abort),
        .st_raw_len(ap_st_raw_len), .st_xform_len(ap_st_xform_len),
        .st_stream_len(ap_st_stream_len), .st_raw_crc(ap_st_raw_crc),
        .st_xform_crc(ap_st_xform_crc), .st_stream_crc(ap_st_stream_crc),
        .st_blocks(ap_st_blocks), .st_stall_cycles(ap_st_stall),
        .st_busy(ap_st_busy), .dbg()
    );

    assign p1_pk_ready   = ap_in_ready;
    assign st_raw_len    = ap_st_raw_len;
    assign st_xform_len  = ap_st_xform_len;
    assign st_stream_len = ap_st_stream_len;
    assign st_raw_crc    = ap_st_raw_crc;
    assign st_xform_crc  = ap_st_xform_crc;
    assign st_stream_crc = ap_st_stream_crc;
    assign st_blocks     = ap_st_blocks;
    assign st_stall      = ap_st_stall;

    assign pk_data   = p1_pk_data;
    assign pk_accept = p1_pk_valid && ap_in_ready;

    assign ap_data   = core_out_data;
    assign ap_valid  = core_out_valid;
    assign ap_keep   = core_out_keep;
    assign ap_last   = core_out_last;
    assign ap_accept = core_out_valid && core_out_ready;
    assign ap_commit = core_commit;
    assign ap_abort  = core_frame_abort;

    // =========================================================== slot store
    a1_ddr_slot_store #(
        .MODE(1), .SLOT_WORDS(SLOT_WORDS), .BASE_WORD(32'd0),
        .AWB(SLOT_AWB), .EXPECT_BYTES(0), .RETRY_EN(0)
    ) u_store (
        .clk(clk), .rst_n(rst_n), .ddr_ready(ddr_ready),
        .wr_begin(wr_begin), .wr_begin_ready(store_begin_ready),
        .wr_id(f_seq), .wr_data({8'd0, core_out_data}), .wr_keep(core_out_keep),
        .wr_valid(core_out_valid), .wr_last(store_wr_last),
        .wr_ready(store_wr_ready), .wr_abort(wr_abort),
        .rd_open(rd_open), .rd_open_ready(store_rd_open_ready),
        .rd_id(store_rd_id), .rd_len_bytes(store_rd_len),
        .rd_close(rd_close), .rd_data(store_rd_data), .rd_valid(store_rd_valid),
        .rd_take(drain_take),
        .ddr_awaddr(store_awaddr), .ddr_awvalid(store_awvalid),
        .ddr_awready(store_awready),
        .ddr_wdata(store_wdata), .ddr_wvalid(store_wvalid),
        .ddr_wready(store_wready),
        .ddr_araddr(store_araddr), .ddr_arvalid(store_arvalid),
        .ddr_arready(store_arready),
        .ddr_rdata(store_rdata), .ddr_rvalid(store_rvalid),
        .ddr_rready(store_rready),
        .st_published(store_published), .st_dropped(store_dropped),
        .st_errors(store_errors), .st_last_bytes(),
        .st_read_words(), .st_dup_words(),
        .st_wr_beats(), .st_wr_words(), .st_wr_ptr(), .st_wr_state(),
        .st_rd_state(), .st_slot_st(store_slot_st),
        .st_slot_len0(), .st_slot_len1(), .st_rd_idx(), .st_rd_words(),
        .st_ar_valid(), .st_ar_hs(), .st_rv_cnt(), .st_rd_open_ok(),
        .st_rd_close_cnt(), .st_abort_cnt(),
        .st_free_valid(store_free_valid), .st_wr_active_out(),
        .rd_timeout(), .rd_retry_ready(), .st_timeout_cnt(),
        .st_retry_cnt(), .st_retry_giveup()
    );

    assign core_out_ready = store_wr_ready;
    assign st_store_published = store_published;
    assign st_store_dropped   = store_dropped;
    assign st_store_errors    = store_errors;

    // =========================================================== DDR arbiter
    a1_ddr_arb2 u_arb (
        .clk(clk), .rst_n(rst_n),
        // master 0 is the reserved non-compressed staging master; it is inactive
        // in this integration (the RAW store path is not part of INT.P4).
        .m0_awaddr(32'd0), .m0_awvalid(1'b0), .m0_awready(),
        .m0_wdata(256'd0), .m0_wvalid(1'b0), .m0_wready(),
        .m0_araddr(32'd0), .m0_arvalid(1'b0), .m0_arready(),
        .m0_rdata(), .m0_rvalid(), .m0_rready(1'b1),
        .m0_rd_abort(1'b0),
        // master 1 is the A+ compressed slot store
        .m1_awaddr(store_awaddr), .m1_awvalid(store_awvalid),
        .m1_awready(store_awready),
        .m1_wdata(store_wdata), .m1_wvalid(store_wvalid),
        .m1_wready(store_wready),
        .m1_araddr(store_araddr), .m1_arvalid(store_arvalid),
        .m1_arready(store_arready),
        .m1_rdata(store_rdata), .m1_rvalid(store_rvalid),
        .m1_rready(store_rready),
        .s_awaddr(ddr_awaddr), .s_awvalid(ddr_awvalid), .s_awready(ddr_awready),
        .s_wdata(ddr_wdata), .s_wvalid(ddr_wvalid), .s_wready(ddr_wready),
        .s_araddr(ddr_araddr), .s_arvalid(ddr_arvalid), .s_arready(ddr_arready),
        .s_rdata(ddr_rdata), .s_rvalid(ddr_rvalid), .s_rready(ddr_rready)
    );

    // =========================================================== publish detect
    assign slot0_st = store_slot_st[1:0];
    assign slot1_st = store_slot_st[3:2];
    assign store_has_ready = (slot0_st == 2'd2) || (slot1_st == 2'd2);
    assign pub_evt  = ((slot0_st == 2'd2) && (slot_st_q[1:0] != 2'd2)) ||
                      ((slot1_st == 2'd2) && (slot_st_q[3:2] != 2'd2));
    assign pub_slot = ((slot0_st == 2'd2) && (slot_st_q[1:0] != 2'd2)) ? 1'b0 : 1'b1;

    // =========================================================== drain engine
    assign rd_open     = (dr == DR_OPEN);
    assign rd_close    = (dr == DR_CLOSE);
    assign drain_take  = (dr == DR_TAKE) && store_rd_valid;
    assign drain_busy  = drain_req || (dr != DR_IDLE);
    assign drain_data   = store_rd_data;
    assign drain_accept = (dr == DR_TAKE) && store_rd_valid;
    assign st_drain_words = drain_words_total;

    // =========================================================== egress adapter
    assign desc_arm            = egress_arm;
    assign desc_cap_bytes      = egress_cap_bytes;
    assign desc_session_id     = egress_session;
    assign desc_dst_base       = egress_dst;
    assign desc_db_addr        = egress_db;
    assign desc_frame_bytes    = egress_frame_bytes;
    assign desc_stream_len     = egress_stream_len;
    assign desc_slot_base_word = egress_slot_base;
    assign desc_src_sel        = egress_src_sel;
    assign desc_cam_sel        = egress_cam_sel;
    assign st_exported         = egress_exported;
    assign st_adapter_err      = {24'd0, egress_err};
    assign st_adapter_busy     = egress_busy;
    assign st_adapter_held     = egress_held;

    assign desc_ident_valid = egress_arm;
    assign desc_camera_id   = active_cam;
    assign desc_slot_id     = f_slot;
    assign desc_epoch       = f_epoch;
    assign desc_capture_seq = f_seq;

    aplus_pcie_egress_adapter #(
        .SLOT_BYTES(SLOT_WORDS * 32),
        .ALIGN_BYTES(ALIGN_BYTES),
        .SESSION_DEFAULT(32'd1)
    ) u_egress (
        .clk(clk), .rst_n(rst_n),
        .push_en(push_en), .cap_bytes(cap_bytes), .session_id(session_id),
        .dst_base(dst_base), .db_addr(db_addr), .mps_code(mps_code),
        .link_up(link_up),
        .slot_ready(pub_pulse), .slot_id(pub_id), .slot_stream_len(pub_len),
        .slot_base_word(SLOT_BASE_WORD + (pub_slot_r ? SLOT_WORDS : 32'd0)),
        .pcie_busy(pcie_busy), .pcie_held(pcie_held), .pcie_done(pcie_done),
        .pcie_err(pcie_err), .pcie_held_seq(pcie_held_seq),
        .pcie_held_sess(pcie_held_sess),
        .ack_pulse(ack_pulse), .ack_seq(ack_seq), .ack_session(ack_session),
        .cancel_pulse(cancel_pulse),
        .arm_pulse(egress_arm), .o_cap_bytes(egress_cap_bytes),
        .o_session_id(egress_session), .o_dst_base(egress_dst),
        .o_db_addr(egress_db), .o_frame_bytes(egress_frame_bytes),
        .o_stream_len(egress_stream_len), .o_slot_base_word(egress_slot_base),
        .o_src_sel(egress_src_sel), .o_cam_sel(egress_cam_sel),
        .slot_release(slot_release),
        .st_exported(egress_exported), .st_bytes(), .st_err(egress_err),
        .st_busy(egress_busy), .st_held(egress_held)
    );

    // =========================================================== abort / counters
    assign core_abort_evt = core_frame_abort && !core_abort_q;

    assign admit_ok = (gs == GS_IDLE) && !cfg_dirty && store_free_valid &&
                      !store_has_ready && !egress_busy && !drain_busy &&
                      !ap_st_busy && !wr_started;
    assign sched_o_ready = admit_ok;

    assign st_frames_committed = committed_cnt;
    assign st_frames_aborted   = aborted_cnt;
    assign st_release_count    = release_cnt;
    assign st_admit_count      = admit_cnt;
    assign st_cfg_error        = {31'd0, p1_cfg_error};
    assign st_glue_state       = gs;

    // =========================================================== main glue FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gs            <= GS_IDLE;
            active_cam    <= 1'b0;
            f_slot        <= 1'b0;
            f_epoch       <= 32'd0;
            f_session     <= 32'd0;
            f_seq         <= 32'd0;
            wr_started    <= 1'b0;
            wr_begin      <= 1'b0;
            wr_abort      <= 1'b0;
            rel_status_r  <= 1'b0;
            rel_pulse     <= 1'b0;
            wd_en         <= 1'b0;
            wd_cnt        <= 16'd0;
            cfg_mode_r    <= 3'd0;
            cfg_phase_r   <= 2'd3;
            slot_st_q     <= 4'b0000;
            pub_pulse     <= 1'b0;
            pub_id        <= 32'd0;
            pub_len       <= 32'd0;
            pub_slot_r    <= 1'b0;
            dr            <= DR_IDLE;
            drain_req     <= 1'b0;
            dr_len        <= 32'd0;
            dr_words      <= 32'd0;
            dr_cnt        <= 32'd0;
            dr_done       <= 1'b0;
            drain_words_total <= 32'd0;
            core_abort_q  <= 1'b0;
            committed_cnt <= 32'd0;
            aborted_cnt   <= 32'd0;
            release_cnt   <= 32'd0;
            admit_cnt     <= 32'd0;
            pk_cnt        <= 32'd0;
            pk_eof_cnt    <= 32'd0;
            int_ok_r      <= 1'b0;
            run_wd        <= 32'd0;
            glue_abort    <= 1'b0;
        end else begin
            // single-cycle pulses
            wr_begin     <= 1'b0;
            wr_abort     <= 1'b0;
            pub_pulse    <= 1'b0;
            dr_done      <= 1'b0;
            rel_pulse    <= 1'b0;
            glue_abort   <= 1'b0;
            slot_st_q    <= {slot1_st, slot0_st};
            core_abort_q <= core_frame_abort;

            // ---- frame integrity accounting (r1) ----
            if (gs == GS_IDLE) begin
                pk_cnt     <= 32'd0;
                pk_eof_cnt <= 32'd0;
                int_ok_r   <= 1'b0;
                run_wd     <= 32'd0;
            end else begin
                if (pk_tr) begin
                    if (p1_pk_sof || (pk_cnt == 32'd0)) pk_cnt <= 32'd1;
                    else                             pk_cnt <= pk_cnt + 32'd1;
                    if (p1_pk_eof) pk_eof_cnt <= pk_eof_cnt + 32'd1;
                end
                // verdict latched on the transferred EOF beat: the A+ last output
                // word follows many cycles later, so store write-last and the
                // commit decision both see a stable verdict
                if (pk_tr && p1_pk_eof)
                    int_ok_r <= ((pk_cnt + 32'd1) == EXPECT_BEATS) &&
                                (pk_eof_cnt == 32'd0);
                if (gs == GS_RUN) begin
                    if (pk_tr)                     run_wd <= 32'd0;
                    else if (run_wd != FRAME_WD)   run_wd <= run_wd + 32'd1;
                end
            end

            if (p1_cfg_valid && p1_cfg_ready) begin
                cfg_mode_r  <= cfg_mode;
                cfg_phase_r <= cfg_phase;
            end

            // publish event -> P2 slot_ready (id/length/base latched here)
            if (pub_evt) begin
                pub_pulse  <= 1'b1;
                pub_id     <= store_rd_id;
                pub_len    <= store_rd_len;
                pub_slot_r <= pub_slot;
            end

            // ---- descriptor admission ----
            if ((gs == GS_IDLE) && sched_o_valid && sched_o_ready) begin
                active_cam <= sched_o_camera;
                f_slot     <= sched_o_slot;
                f_epoch    <= sched_o_epoch;
                f_session  <= sched_o_session;
                f_seq      <= sched_o_seq;
                admit_cnt  <= admit_cnt + 32'd1;
                gs         <= GS_CFG;
            end

            if (rel_valid && sched_rel_ready) begin
                release_cnt <= release_cnt + 32'd1;
            end

            // ---- frame sequence ----
            case (gs)
                GS_IDLE: ;

                GS_CFG: begin
                    if (!cfg_dirty) gs <= GS_BEGIN;
                end

                GS_BEGIN: begin
                    wr_begin <= 1'b1;
                    if (wr_begin && store_begin_ready) begin
                        wr_started <= 1'b1;
                        gs         <= GS_RUN;
                    end
                end

                GS_RUN: begin
                    if (commit_ok) begin
                        committed_cnt <= committed_cnt + 32'd1;
                        wr_started    <= 1'b0;
                        gs            <= GS_WAIT_PUB;
                    end else if (core_commit) begin
                        // The A+ core closed the frame but the transferred beat
                        // count/EOF verdict does not match W*H/4: never publish
                        // it as a good frame.  Discard the partial slot and
                        // release the capture descriptor as failed.
                        aborted_cnt  <= aborted_cnt + 32'd1;
                        wr_abort     <= 1'b1;
                        wr_started   <= 1'b0;
                        rel_status_r <= 1'b1;
                        rel_pulse    <= 1'b1;
                        gs           <= GS_IDLE;
                    end else if (core_abort_evt) begin
                        aborted_cnt  <= aborted_cnt + 32'd1;
                        wr_abort     <= 1'b1;
                        wr_started   <= 1'b0;
                        // nothing was published: free the store slot and release
                        // the capture descriptor with a failed status immediately
                        rel_status_r <= 1'b1;
                        rel_pulse    <= 1'b1;
                        gs           <= GS_IDLE;
                    end else if (run_wd == FRAME_WD) begin
                        // stalled capture / lost source EOF: abort instead of
                        // pinning the A+ core and the slot store forever
                        glue_abort <= 1'b1;
                        run_wd     <= 32'd0;
                        aborted_cnt <= aborted_cnt + 32'd1;
                        wr_abort   <= 1'b1;
                        wr_started <= 1'b0;
                        rel_status_r <= 1'b1;
                        rel_pulse    <= 1'b1;
                        gs           <= GS_IDLE;
                    end
                end

                GS_WAIT_PUB: begin
                    if (pub_pulse) gs <= GS_WAIT_REL;
                end

                GS_WAIT_REL: begin
                    if (slot_release) begin
                        // a good ACK while the adapter held the frame = completed
                        rel_status_r <= (egress_held && !cancel_pulse) ? 1'b0 : 1'b1;
                        drain_req    <= 1'b1;
                        wd_en        <= 1'b0;
                        gs           <= GS_DRAIN;
                    end else if (!wd_en) begin
                        wd_en  <= 1'b1;
                        wd_cnt <= 16'd0;
                    end else begin
                        // export/ACK watchdog: a rejected descriptor or a lost ACK
                        // must never pin a published slot forever
                        wd_cnt <= wd_cnt + 16'd1;
                        if (wd_cnt == 16'hFFFF) begin
                            wd_en        <= 1'b0;
                            rel_status_r <= 1'b1;
                            drain_req    <= 1'b1;
                            gs           <= GS_DRAIN;
                        end
                    end
                end

                GS_DRAIN: begin
                    if (dr_done) begin
                        gs <= GS_IDLE;
                    end
                end

                default: gs <= GS_IDLE;
            endcase

            // ---- drain engine (slot READY -> READING -> FREE on release) ----
            case (dr)
                DR_IDLE: begin
                    if (drain_req) dr <= DR_OPEN;
                end
                DR_OPEN: begin
                    if (store_rd_open_ready) begin
                        dr_len   <= store_rd_len;
                        dr_words <= (store_rd_len + 32'd31) >> 5;
                        dr_cnt   <= 32'd0;
                        dr       <= DR_TAKE;
                    end
                end
                DR_TAKE: begin
                    if (store_rd_valid) begin
                        drain_words_total <= drain_words_total + 32'd1;
                        dr_cnt            <= dr_cnt + 32'd1;
                        if ((dr_cnt + 32'd1) >= dr_words) dr <= DR_CLOSE;
                    end
                end
                DR_CLOSE: begin
                    dr_done   <= 1'b1;
                    drain_req <= 1'b0;
                    dr        <= DR_IDLE;
                end
                default: dr <= DR_IDLE;
            endcase
        end
    end

    // release handshake: one cycle at the end of the drain, or the immediate
    // failed release after an aborted frame
    assign rel_valid = (dr == DR_CLOSE) || rel_pulse;
    assign rel_camera_id   = active_cam;
    assign rel_slot_id     = f_slot;
    assign rel_epoch       = f_epoch;
    assign rel_session     = f_session;
    assign rel_capture_seq = f_seq;
    assign rel_status      = {2'd0, rel_status_r};

endmodule
