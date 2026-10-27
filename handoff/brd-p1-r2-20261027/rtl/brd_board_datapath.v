`timescale 1ns/1ps
// =============================================================================
// brd_board_datapath.v -- T11.BRD.P1 board datapath (guide 3, 4, 6)
//
//   cam_B byte clk : a1_raw_crop -> 43b pack -> capture_async_fifo -\
//   cam_A byte clk : a1_raw_crop -> 43b pack -> capture_async_fifo -+-> clk_core
//                                                                    |
//   clk_core : integrated_delivery_top (P4 r2, read-only instance)    |
//              |  a_s_* / b_s_*                                        |
//              |  ddr_* single-beat 256b PAXI                          |
//              v                                                       |
//   clk_core : p2_ddr_bridge (b18 read-only) --> brd_paxi_remap --> DDR AXI4 write
//   usr_clk  : brd_ddr_rd_arb  <-- pusher 4KB burst  <-- ddr_frame_pusher (tl)
//                            \<-- bridge single-beat read <-- P4 slot drain
//
//   CDC (guide 4.1):
//     C1  cam A byte clk -> clk_core : brd_cam_fe capture_async_fifo (43b)
//     C2  cam B byte clk -> clk_core : brd_cam_fe capture_async_fifo (43b)
//     C3  clk_core -> usr_clk        : p2_ddr_bridge WF/AF/RF Gray FIFOs
//     C3b clk_core <- usr_clk        : ddr_rdy single bit, 2FF
//     C4  clk_core -> tl_clk_user    : brd_desc_xing
//     C5  tl_clk_user -> clk_core    : brd_ack_xing
//     C6  tl_clk_user -> clk_core    : brd_pcie_track (forward)
//     C6b clk_core -> tl_clk_user    : brd_pcie_track (P4 status snapshot)
//     C7  tl_clk_user -> clk_core    : brd_cfg_xing
//     C8  tl_clk_user -> clk_core    : mps_code[2:0] single-bit x3 2FF
//     C9  tl_clk_user -> clk_core    : link_up       single-bit   2FF
//
// DDR addressing (one documented convention, guide 9 "documented limitation"):
//   the board DDR AXI4 port is byte addressed (the same convention the board
//   proven cam_r10f_writer / ddr_frame_pusher pair uses, BEAT_BYTES=32,
//   BURST_STEP=4096).  P4 emits a 256-bit WORD index; p2_ddr_bridge converts it
//   to word*8.  brd_paxi_remap therefore multiplies the bridge address by 4 so
//   one P4 word lands on 32 consecutive bytes and the pusher, which reads
//   byte addresses, sees the same bytes.  Verified only by the G1 simulation
//   in this round; hardware confirmation belongs to T11.BRD.P2.
//
// r1 fixes (round1):
//   F2: the P4 r2 slot store is instantiated with BASE_WORD=0 inside the
//       read-only integrated_delivery_top, while its egress descriptor reports
//       SLOT_BASE_WORD.  The board therefore adds SLOT_BASE_WORD (word units)
//       to BOTH the P4 write and read word addresses before the bridge, so the
//       store, the drain read, the descriptor and the pusher all use byte
//       base 0x1_0000 (word 2048).  P4 sources are unchanged.
//   F1: brd_export_seq latches the host ARM and presents it to the pusher only
//       after a published descriptor exists, then emits exactly one source
//       event on a board-owned sequence.  Repeats are ignored/counted.
//   held_seq: the P4 egress adapter compares the host ACK sequence against the
//       pusher's HELD identity, so the tracker is fed the pusher done count
//       (= held_seq, the doorbell value) instead of the capture sequence.
//   C8/C9: mps_code and link_up enter clk_core only through 2FF synchronisers.
// =============================================================================
module brd_board_datapath #(
    parameter integer CAM_A_W  = 3840,
    parameter integer CAM_A_H  = 2160,
    parameter integer ROI_A_X  = 960,
    parameter integer ROI_A_Y  = 540,
    parameter integer CAM_B_W  = 3864,
    parameter integer CAM_B_H  = 2192,
    parameter integer ROI_B_X  = 972,
    parameter integer ROI_B_Y  = 556,
    parameter integer W        = 1920,
    parameter integer H        = 1080,
    parameter integer MAX_WORDS = 512,
    parameter integer SLOT_WORDS = 81920,           // 640 KiB per slot, 4 KiB aligned stride
    parameter [31:0]  SLOT_BASE_WORD = 32'd2048,    // byte 0x0001_0000
    parameter integer FIFO_AW  = 10,
    parameter [31:0]  DDR_CAP_BYTES = 32'h1000_0000
) (
    // ---------------- camera front ends ----------------
    input  wire         cam_a_clk,
    input  wire         cam_a_rst_n,
    input  wire [39:0]  cam_a_pix,
    input  wire         cam_a_pix_valid,
    input  wire         cam_a_in_line,
    input  wire         cam_a_in_frame,
    input  wire         cam_a_vsync,

    input  wire         cam_b_clk,
    input  wire         cam_b_rst_n,
    input  wire [39:0]  cam_b_pix,
    input  wire         cam_b_pix_valid,
    input  wire         cam_b_in_line,
    input  wire         cam_b_in_frame,
    input  wire         cam_b_vsync,

    // ---------------- clk_core ----------------
    input  wire         clk_core,
    input  wire         rst_core_n,

    // ---------------- DDR user clock ----------------
    input  wire         usr_clk,
    input  wire         rst_usr_n,
    input  wire         ddr_rdy,

    // ---------------- tl_clk_user (BAR) ----------------
    input  wire         tl_clk,
    input  wire         tl_rst_n,
    input  wire [31:0]  cfg_cap_bytes,
    input  wire [31:0]  cfg_session_id,
    input  wire [31:0]  cfg_dst_lo,
    input  wire [31:0]  cfg_dst_hi,
    input  wire [31:0]  cfg_db_lo,
    input  wire [31:0]  cfg_db_hi,
    input  wire         cfg_push_en,
    input  wire         cfg_a_enable,
    input  wire         cfg_trigger_mode,
    input  wire         cfg_p4_desc_owner,
    input  wire [2:0]   cfg_mode,
    input  wire         cfg_prep,
    input  wire         cfg_pred,
    input  wire [1:0]   cfg_phase,
    input  wire         link_up,
    input  wire [2:0]   mps_code,

    input  wire         tx_arm,
    input  wire         tx_ack,
    input  wire         tx_cancel,
    input  wire [31:0]  tx_cap_bytes,
    input  wire [31:0]  tx_session_id,
    input  wire [31:0]  tx_ack_seq,
    input  wire [31:0]  tx_ack_session,

    // TL transmit port to the PCIe EP engine (tl domain)
    input  wire         tl_tx_wait,
    output wire         utx_sel,
    output wire         utx_req,
    output wire [255:0] utx_data,
    output wire         utx_sop,
    output wire         utx_eop,
    output wire [7:0]   utx_valid,

    output wire [31:0]  o_push_done,
    output wire [31:0]  o_push_status,
    output wire [31:0]  o_push_tlp,
    output wire [7:0]   o_push_err,
    output wire [31:0]  o_tx_status,
    output wire         o_tx_block_cfg,
    output wire [127:0] o_p4_st,

    // ---------------- DDR3 AXI4 (byte address, 256 bit) ----------------
    output wire [28:0]  ddr_awaddr,
    output wire [255:0] ddr_wdata,
    output wire [31:0]  ddr_wstrb,
    output wire         ddr_awvalid,
    output wire         ddr_wvalid,
    output wire         ddr_wlast,
    input  wire         ddr_awready,
    input  wire         ddr_wready,
    output wire         ddr_bready,

    output wire [3:0]   ddr_arid,
    output wire [28:0]  ddr_araddr,
    output wire [7:0]   ddr_arlen,
    output wire [2:0]   ddr_arsize,
    output wire [1:0]   ddr_arburst,
    output wire         ddr_arvalid,
    input  wire         ddr_arready,
    input  wire [3:0]   ddr_rid,
    input  wire [255:0] ddr_rdata,
    input  wire [1:0]   ddr_rresp,
    input  wire         ddr_rlast,
    input  wire         ddr_rvalid,
    output wire         ddr_rready,

    // ---------------- observation ----------------
    output wire         o_arb_owner,
    output wire [31:0]  o_arb_late,
    output wire [31:0]  o_arb_switch,
    output wire [31:0]  o_p4_desc_active,
    output wire [31:0]  o_slot_busy,
    output wire [31:0]  o_arm_seq
);

    // =========================================================================
    // C7 config shadow
    // =========================================================================
    wire [31:0] c_cap_bytes, c_session_id;
    wire [63:0] c_dst_base, c_db_addr;
    wire        c_push_en, c_a_enable, c_trigger_mode, c_p4_owner;
    wire [2:0]  c_mode;
    wire        c_prep, c_pred;
    wire [1:0]  c_phase;

    brd_cfg_xing u_cfg (
        .tl_clk(tl_clk), .tl_rst_n(tl_rst_n),
        .i_cap_bytes(cfg_cap_bytes), .i_session_id(cfg_session_id),
        .i_dst_lo(cfg_dst_lo), .i_dst_hi(cfg_dst_hi),
        .i_db_lo(cfg_db_lo),   .i_db_hi(cfg_db_hi),
        .i_push_en(cfg_push_en), .i_a_enable(cfg_a_enable),
        .i_trigger_mode(cfg_trigger_mode), .i_p4_desc_owner(cfg_p4_desc_owner),
        .i_cfg_mode(cfg_mode), .i_prep(cfg_prep), .i_pred(cfg_pred), .i_phase(cfg_phase),
        .clk_core(clk_core), .rst_core_n(rst_core_n),
        .o_cap_bytes(c_cap_bytes), .o_session_id(c_session_id),
        .o_dst_base(c_dst_base), .o_db_addr(c_db_addr),
        .o_push_en(c_push_en), .o_a_enable(c_a_enable),
        .o_trigger_mode(c_trigger_mode), .o_p4_desc_owner(c_p4_owner),
        .o_cfg_mode(c_mode), .o_prep(c_prep), .o_pred(c_pred), .o_phase(c_phase)
    );

    // =========================================================================
    // C1 / C2 camera front ends
    // =========================================================================
    wire [39:0] a_pix, b_pix;
    wire        a_valid, a_sof, a_eol, a_eof, a_abort;
    wire        b_valid, b_sof, b_eol, b_eof, b_abort;
    wire        a_ready, b_ready;

    brd_cam_fe #(
        .CAM_W(CAM_A_W), .CAM_H(CAM_A_H), .ROI_X(ROI_A_X), .ROI_Y(ROI_A_Y),
        .W(W), .H(H), .FIFO_AW(FIFO_AW)
    ) u_fe_a (
        .cam_clk(cam_a_clk), .cam_rst_n(cam_a_rst_n),
        .cam_pix(cam_a_pix), .cam_pix_valid(cam_a_pix_valid),
        .cam_in_line(cam_a_in_line), .cam_in_frame(cam_a_in_frame), .cam_vsync(cam_a_vsync),
        .st_frames(), .st_groups(), .st_abort(), .st_ovf(),
        .core_clk(clk_core), .core_rst_n(rst_core_n),
        .o_pix(a_pix), .o_valid(a_valid), .o_sof(a_sof), .o_eol(a_eol),
        .o_eof(a_eof), .o_abort(a_abort), .o_ready(a_ready)
    );

    brd_cam_fe #(
        .CAM_W(CAM_B_W), .CAM_H(CAM_B_H), .ROI_X(ROI_B_X), .ROI_Y(ROI_B_Y),
        .W(W), .H(H), .FIFO_AW(FIFO_AW)
    ) u_fe_b (
        .cam_clk(cam_b_clk), .cam_rst_n(cam_b_rst_n),
        .cam_pix(cam_b_pix), .cam_pix_valid(cam_b_pix_valid),
        .cam_in_line(cam_b_in_line), .cam_in_frame(cam_b_in_frame), .cam_vsync(cam_b_vsync),
        .st_frames(), .st_groups(), .st_abort(), .st_ovf(),
        .core_clk(clk_core), .core_rst_n(rst_core_n),
        .o_pix(b_pix), .o_valid(b_valid), .o_sof(b_sof), .o_eol(b_eol),
        .o_eof(b_eof), .o_abort(b_abort), .o_ready(b_ready)
    );

    // =========================================================================
    // descriptors (guide 3.3): one standing offer per camera while idle
    // =========================================================================
    reg         a_desc_active, b_desc_active;
    reg  [31:0] a_epoch, a_seq, b_epoch, b_seq;

    wire a_desc_valid_w = c_p4_owner & c_a_enable & ~a_desc_active;
    wire b_desc_valid_w = c_p4_owner &              ~b_desc_active;
    wire a_desc_hs, b_desc_hs;
    wire desc_ident_valid, desc_camera_id, desc_slot_id;
    wire [31:0] desc_epoch, desc_capture_seq;
    wire        rel_valid, rel_camera_id, rel_slot_id;
    wire [31:0] rel_epoch, rel_session, rel_capture_seq;
    wire [2:0]  rel_status;
    wire        slot_release;

    wire a_desc_ready, b_desc_ready;

    always @(posedge clk_core or negedge rst_core_n) begin
        if (!rst_core_n) begin
            a_desc_active <= 1'b0; b_desc_active <= 1'b0;
            a_epoch <= 32'd0; a_seq <= 32'd0;
            b_epoch <= 32'd0; b_seq <= 32'd0;
        end else begin
            if (a_desc_hs) begin
                a_desc_active <= 1'b1;
                a_seq         <= a_seq + 32'd1;
                a_epoch       <= a_epoch + 32'd1;
            end
            if (rel_valid) begin
                // rel_camera_id: 0 = A, 1 = B (scheduler identity).  r0 cleared the
                // wrong camera's active flag, so the B descriptor stayed active
                // forever after a good ACK (r1 fix).
                if (rel_camera_id) b_desc_active <= 1'b0;
                else               a_desc_active <= 1'b0;
            end
            if (b_desc_hs) begin
                b_desc_active <= 1'b1;
                b_seq         <= b_seq + 32'd1;
                b_epoch       <= b_epoch + 32'd1;
            end
        end
    end

    assign a_desc_hs = a_desc_valid_w & a_desc_ready;
    assign b_desc_hs = b_desc_valid_w & b_desc_ready;

    // =========================================================================
    // C5 host ACK / CANCEL (tl -> core)
    // =========================================================================
    wire        x_ack, x_cancel;
    wire [31:0] x_ack_seq, x_ack_session;

    brd_ack_xing u_ack (
        .tl_clk(tl_clk), .tl_rst_n(tl_rst_n),
        .ack_pulse(tx_ack), .cancel_pulse(tx_cancel),
        .ack_seq(tx_ack_seq), .ack_session(tx_ack_session),
        .clk_core(clk_core), .rst_core_n(rst_core_n),
        .o_ack(x_ack), .o_cancel(x_cancel),
        .o_ack_seq(x_ack_seq), .o_ack_session(x_ack_session)
    );

    // =========================================================================
    // C6 pusher status (tl -> core) and C6b P4 status snapshot (core -> tl)
    // =========================================================================
    wire        p_done_p, p_held, p_err, p_busy;
    wire [31:0] p_held_seq, p_held_sess, p_tx_done, p_tx_status, p_tx_tlp;
    wire [7:0]  p_tx_err;
    wire        p_link_up, p_block_cfg;
    wire        p_held_w, p_busy_w;
    wire [31:0] p4_st0, p4_st1, p4_st2, p4_st3;

    brd_pcie_track u_track (
        .tl_clk(tl_clk), .tl_rst_n(tl_rst_n),
        .i_done(o_push_done), .i_status(o_push_status), .i_err(o_push_err),
        .i_tlp_cnt(o_push_tlp), .i_held(p_held_w), .i_busy(p_busy_w),
        .i_block_cfg(o_tx_block_cfg), .i_link_up(link_up),
        .i_arm_seq(o_push_done), .i_arm_sess(tx_session_id),
        .clk_core(clk_core), .rst_core_n(rst_core_n),
        .o_pcie_done(p_done_p), .o_pcie_held(p_held), .o_pcie_err(p_err),
        .o_pcie_busy(p_busy), .o_pcie_held_seq(p_held_seq), .o_pcie_held_sess(p_held_sess),
        .o_tx_done(p_tx_done), .o_tx_status(p_tx_status), .o_tx_err(p_tx_err),
        .o_tx_tlp(p_tx_tlp), .o_link_up(p_link_up), .o_block_cfg(p_block_cfg),
        .i_p4_st0(p4_st0), .i_p4_st1(p4_st1), .i_p4_st2(p4_st2), .i_p4_st3(p4_st3),
        .o_p4_st(o_p4_st)
    );

    // =========================================================================
    // P4 r2 core (read-only instance, guide 1)
    // =========================================================================
    wire [31:0] p4_st_raw_len, p4_st_xform_len, p4_st_stream_len;
    wire [31:0] p4_st_raw_crc, p4_st_xform_crc, p4_st_stream_crc;
    wire [31:0] p4_st_blocks, p4_st_stall;
    wire [15:0] p4_st_good, p4_st_abort16;
    wire [31:0] p4_st_store_pub, p4_st_store_drop, p4_st_store_err;
    wire [31:0] p4_st_exported, p4_st_adapter_err;
    wire        p4_st_adapter_busy, p4_st_adapter_held;
    wire [31:0] p4_st_committed, p4_st_frames_aborted, p4_st_release, p4_st_admit;
    wire [31:0] p4_st_drain_words, p4_st_cfg_error;
    wire [15:0] p4_st_sched_acc, p4_st_sched_comp, p4_st_sched_fail, p4_st_sched_rej;
    wire        p4_sched_a_busy, p4_sched_b_busy, p4_sched_last_cam;
    wire [3:0]  p4_glue_state;

    wire        desc_arm;
    wire [31:0] desc_cap_bytes, desc_session_id, desc_frame_bytes, desc_stream_len, desc_slot_base_word;
    wire [63:0] desc_dst_base, desc_db_addr;
    wire        desc_src_sel, desc_cam_sel;

    wire [31:0] p4_ddr_awaddr, p4_ddr_araddr;
    wire        p4_ddr_awvalid, p4_ddr_wvalid, p4_ddr_arvalid, p4_ddr_rready;
    wire [255:0] p4_ddr_wdata;
    wire        p4_ddr_awready, p4_ddr_wready, p4_ddr_arready, p4_ddr_rvalid;
    wire [255:0] p4_ddr_rdata;

    // =========================================================================
    // C8 / C9: BAR-domain quasi-static inputs into clk_core
    //   mps_code is a 3-bit negotiated code, link_up is a level; both are
    //   quasi-static, so the frozen structure is one 2FF per bit (no bundle
    //   sampling).  The raw tl-domain copies stay in the tl domain for the
    //   pusher/register face.  There is no other direct mps_code/link_up path
    //   into clk_core logic.
    // =========================================================================
    wire [2:0] c_mps_code;
    wire       c_link_up;

    (* async_reg = "true" *) reg [2:0] mps_s1, mps_s2;
    (* async_reg = "true" *) reg [1:0] lnk_s1, lnk_s2;

    always @(posedge clk_core or negedge rst_core_n) begin
        if (!rst_core_n) begin
            mps_s1 <= 3'd0; mps_s2 <= 3'd0;
            lnk_s1 <= 2'd0; lnk_s2 <= 2'd0;
        end else begin
            mps_s1 <= mps_code; mps_s2 <= mps_s1;
            lnk_s1 <= {1'b0, link_up}; lnk_s2 <= lnk_s1;
        end
    end
    assign c_mps_code = mps_s2;
    assign c_link_up  = lnk_s2[0];

    wire ddr_rdy_c;
    brd_2ff_sync u_sync_rdy (.clk(clk_core), .rst_n(rst_core_n), .d(ddr_rdy), .q(ddr_rdy_c));

    integrated_delivery_top #(
        .W(W), .H(H), .MAX_WORDS(MAX_WORDS),
        .SLOT_WORDS(SLOT_WORDS),
        .SLOT_BASE_WORD(SLOT_BASE_WORD),
        .SLOT_AWB(18),
        .ALIGN_BYTES(32'd4096)
    ) u_p4 (
        .clk(clk_core), .rst_n(rst_core_n),

        .a_s_valid(a_valid), .a_s_ready(a_ready), .a_s_data(a_pix),
        .a_s_sof(a_sof), .a_s_eol(a_eol), .a_s_eof(a_eof), .a_s_abort(a_abort),

        .b_s_valid(b_valid), .b_s_ready(b_ready), .b_s_data(b_pix),
        .b_s_sof(b_sof), .b_s_eol(b_eol), .b_s_eof(b_eof), .b_s_abort(b_abort),

        .cfg_mode(c_mode), .cfg_phase(c_phase),
        .cfg_aplus_prep(c_prep), .cfg_aplus_pred(c_pred),
        .push_en(c_push_en), .cap_bytes(c_cap_bytes), .session_id(c_session_id),
        .dst_base(c_dst_base), .db_addr(c_db_addr), .mps_code(c_mps_code),
        .link_up(c_link_up),

        .a_desc_valid(a_desc_valid_w), .a_desc_ready(a_desc_ready),
        .a_desc_camera_id(1'b0), .a_desc_slot_id(1'b0),
        .a_desc_epoch(a_epoch), .a_desc_session(c_session_id), .a_desc_capture_seq(a_seq),

        .b_desc_valid(b_desc_valid_w), .b_desc_ready(b_desc_ready),
        .b_desc_camera_id(1'b1), .b_desc_slot_id(1'b0),
        .b_desc_epoch(b_epoch), .b_desc_session(c_session_id), .b_desc_capture_seq(b_seq),

        .a_enable(c_a_enable), .b_priority(1'b1),
        .ack_pulse(x_ack), .ack_seq(x_ack_seq), .ack_session(x_ack_session),
        .cancel_pulse(x_cancel),
        .pcie_busy(p_busy), .pcie_held(p_held), .pcie_done(p_done_p), .pcie_err(p_err),
        .pcie_held_seq(p_held_seq), .pcie_held_sess(p_held_sess),
        .ddr_ready(ddr_rdy_c),

        .ddr_awaddr(p4_ddr_awaddr), .ddr_awvalid(p4_ddr_awvalid), .ddr_awready(p4_ddr_awready),
        .ddr_wdata(p4_ddr_wdata), .ddr_wvalid(p4_ddr_wvalid), .ddr_wready(p4_ddr_wready),
        .ddr_araddr(p4_ddr_araddr), .ddr_arvalid(p4_ddr_arvalid), .ddr_arready(p4_ddr_arready),
        .ddr_rdata(p4_ddr_rdata), .ddr_rvalid(p4_ddr_rvalid), .ddr_rready(p4_ddr_rready),

        .desc_arm(desc_arm), .desc_cap_bytes(desc_cap_bytes), .desc_session_id(desc_session_id),
        .desc_dst_base(desc_dst_base), .desc_db_addr(desc_db_addr),
        .desc_frame_bytes(desc_frame_bytes), .desc_stream_len(desc_stream_len),
        .desc_slot_base_word(desc_slot_base_word),
        .desc_src_sel(desc_src_sel), .desc_cam_sel(desc_cam_sel),
        .slot_release(slot_release),
        .desc_ident_valid(desc_ident_valid), .desc_camera_id(desc_camera_id),
        .desc_slot_id(desc_slot_id), .desc_epoch(desc_epoch),
        .desc_capture_seq(desc_capture_seq),
        .rel_valid(rel_valid), .rel_camera_id(rel_camera_id), .rel_slot_id(rel_slot_id),
        .rel_epoch(rel_epoch), .rel_session(rel_session),
        .rel_capture_seq(rel_capture_seq), .rel_status(rel_status),
        .m_ready(1'b1),

        .mon_accept(), .m_valid(), .m_mode(), .m_is_raw(), .m_raw_data(), .m_proc_data(),
        .m_sof(), .m_eol(), .m_eof(), .m_abort(),
        .ap_data(), .ap_valid(), .ap_keep(), .ap_last(), .ap_accept(),
        .ap_commit(), .ap_abort(), .pk_data(), .pk_accept(),
        .drain_data(), .drain_accept(),

        .st_raw_len(p4_st_raw_len), .st_xform_len(p4_st_xform_len),
        .st_stream_len(p4_st_stream_len),
        .st_raw_crc(p4_st_raw_crc), .st_xform_crc(p4_st_xform_crc),
        .st_stream_crc(p4_st_stream_crc),
        .st_blocks(p4_st_blocks), .st_stall(p4_st_stall),
        .st_p1_good(p4_st_good), .st_p1_abort(p4_st_abort16),
        .st_store_published(p4_st_store_pub), .st_store_dropped(p4_st_store_drop),
        .st_store_errors(p4_st_store_err),
        .st_exported(p4_st_exported), .st_adapter_err(p4_st_adapter_err),
        .st_adapter_busy(p4_st_adapter_busy), .st_adapter_held(p4_st_adapter_held),
        .st_frames_committed(p4_st_committed), .st_frames_aborted(p4_st_frames_aborted),
        .st_release_count(p4_st_release), .st_admit_count(p4_st_admit),
        .st_drain_words(p4_st_drain_words), .st_cfg_error(p4_st_cfg_error),
        .st_sched_accepted(p4_st_sched_acc), .st_sched_completed(p4_st_sched_comp),
        .st_sched_failed(p4_st_sched_fail), .st_sched_rejected(p4_st_sched_rej),
        .st_sched_a_busy(p4_sched_a_busy), .st_sched_b_busy(p4_sched_b_busy),
        .st_sched_last_cam(p4_sched_last_cam), .st_glue_state(p4_glue_state)
    );

    // =========================================================================
    // C3 DDR write bridge (b18 p2_ddr_bridge, read-only) + byte-address remap
    // =========================================================================
    // F2 (r1): the P4 store itself is instantiated with BASE_WORD=0 inside the
    // read-only integrated_delivery_top; its descriptor reports SLOT_BASE_WORD.
    // Add SLOT_BASE_WORD (word units) to BOTH the write and the drain read so
    // the store, the drain, the descriptor and the pusher agree on byte base
    // SLOT_BASE_WORD*32 = 0x1_0000.
    wire [31:0] p4_ddr_awaddr_off = p4_ddr_awaddr + SLOT_BASE_WORD;
    wire [31:0] p4_ddr_araddr_off = p4_ddr_araddr + SLOT_BASE_WORD;

    wire [26:0] br_awaddr, br_araddr;
    wire        br_awvalid, br_awready, br_wvalid, br_wready, br_wlast;
    wire [255:0] br_wdata;
    wire [31:0] br_wstrb;
    wire        br_arvalid, br_arready, br_rvalid, br_rlast, br_rready;
    wire [255:0] br_rdata;
    wire [511:0] br_dbg;

    p2_ddr_bridge #(.ALLOW_CONCURRENT(0)) u_bridge (
        .clk_a1(clk_core), .rst_n(rst_core_n),
        .s_awaddr(p4_ddr_awaddr_off), .s_awvalid(p4_ddr_awvalid), .s_awready(p4_ddr_awready),
        .s_wdata(p4_ddr_wdata),   .s_wvalid(p4_ddr_wvalid),   .s_wready(p4_ddr_wready),
        .s_araddr(p4_ddr_araddr_off), .s_arvalid(p4_ddr_arvalid), .s_arready(p4_ddr_arready),
        .s_rdata(p4_ddr_rdata),   .s_rvalid(p4_ddr_rvalid),   .s_rready(p4_ddr_rready),
        .rd_abort(1'b0),
        .clk_ddr(usr_clk), .ddr_rdy(ddr_rdy),
        .paxi_awaddr(br_awaddr), .paxi_awvalid(br_awvalid), .paxi_awready(br_awready),
        .paxi_wdata(br_wdata), .paxi_wstrb(br_wstrb), .paxi_wvalid(br_wvalid),
        .paxi_wlast(br_wlast), .paxi_wready(br_wready),
        .paxi_araddr(br_araddr), .paxi_arvalid(br_arvalid), .paxi_arready(br_arready),
        .paxi_rdata(br_rdata), .paxi_rlast(br_rlast), .paxi_rvalid(br_rvalid),
        .paxi_rready(br_rready),
        .dbg_a1(br_dbg)
    );

    // 27 bit bridge address (256-bit-word*8) -> 29 bit byte address (word*32)
    wire [28:0] br_araddr_b = {br_araddr, 2'b00};

    assign ddr_awaddr  = {br_awaddr, 2'b00};
    assign ddr_awvalid = br_awvalid;
    assign br_awready  = ddr_awready;
    assign ddr_wdata   = br_wdata;
    assign ddr_wstrb   = br_wstrb;
    assign ddr_wvalid  = br_wvalid;
    assign ddr_wlast   = br_wlast;
    assign br_wready   = ddr_wready;
    assign ddr_bready  = 1'b1;

    // =========================================================================
    // C4 descriptor mailbox (core -> tl)
    // =========================================================================
    wire        m_arm;
    wire [31:0] m_cap_bytes, m_session_id, m_frame_bytes, m_stream_len, m_slot_base_word;
    wire [63:0] m_dst_base, m_db_addr;
    wire        m_src_sel, m_cam_sel, m_ident_valid, m_camera_id, m_slot_id;
    wire [31:0] m_epoch, m_capture_seq;

    brd_desc_xing u_desc (
        .clk_core(clk_core), .rst_core_n(rst_core_n),
        .desc_arm(desc_arm),
        .desc_cap_bytes(desc_cap_bytes), .desc_session_id(desc_session_id),
        .desc_dst_base(desc_dst_base), .desc_db_addr(desc_db_addr),
        .desc_frame_bytes(desc_frame_bytes), .desc_stream_len(desc_stream_len),
        .desc_slot_base_word(desc_slot_base_word),
        .desc_src_sel(desc_src_sel), .desc_cam_sel(desc_cam_sel),
        .desc_ident_valid(desc_ident_valid), .desc_camera_id(desc_camera_id),
        .desc_slot_id(desc_slot_id), .desc_epoch(desc_epoch),
        .desc_capture_seq(desc_capture_seq),
        .tl_clk(tl_clk), .tl_rst_n(tl_rst_n),
        .o_arm(m_arm),
        .o_cap_bytes(m_cap_bytes), .o_session_id(m_session_id),
        .o_dst_base(m_dst_base), .o_db_addr(m_db_addr),
        .o_frame_bytes(m_frame_bytes), .o_stream_len(m_stream_len),
        .o_slot_base_word(m_slot_base_word),
        .o_src_sel(m_src_sel), .o_cam_sel(m_cam_sel),
        .o_ident_valid(m_ident_valid), .o_camera_id(m_camera_id),
        .o_slot_id(m_slot_id), .o_epoch(m_epoch), .o_capture_seq(m_capture_seq)
    );

    // byte address of the armed slot (word index * 32)
    wire [31:0] m_slot_base_bytes = {m_slot_base_word[26:0], 5'b0};
    // frame ready flag for the pusher (guide 3.3: source keeps the frame until ACK)
    wire        m_frame_ready = (m_frame_bytes != 32'd0);
    wire [31:0] m_ddr_status  = {30'd0, 2'b01};

    // =========================================================================
    // F1 export sequencer (tl domain): latch host ARM, align it to a published
    // descriptor and emit exactly one pusher source event per ARM.
    // =========================================================================
    wire        pu_arm;
    wire [31:0] pu_seq;
    wire        seq_armed, seq_frame_pend;
    wire [31:0] seq_evt_cnt, seq_arm_ignored;

    brd_export_seq u_export_seq (
        .clk(tl_clk), .rst_n(tl_rst_n),
        .host_arm(tx_arm), .host_ack(tx_ack), .host_cancel(tx_cancel),
        .desc_evt(m_arm), .frame_bytes(m_frame_bytes), .tx_status(o_tx_status),
        .pu_arm(pu_arm), .pu_seq(pu_seq),
        .armed_q(seq_armed), .frame_pend_q(seq_frame_pend),
        .evt_cnt(seq_evt_cnt), .arm_ignored(seq_arm_ignored)
    );

    // =========================================================================
    // pusher (reference read-only) + DDR read arbiter
    // =========================================================================
    wire [3:0]  pu_arid;
    wire [28:0] pu_araddr;
    wire [7:0]  pu_arlen;
    wire [2:0]  pu_arsize;
    wire [1:0]  pu_arburst;
    wire        pu_arvalid, pu_arready;
    wire [3:0]  pu_rid;
    wire [255:0] pu_rdata;
    wire [1:0]  pu_rresp;
    wire        pu_rlast, pu_rvalid, pu_rready;

    wire [31:0] pu_fb_addr;
    wire        pu_fb_req;
    wire        pu_src_act, pu_fb_hold, pu_src_lock;
    wire        pu_rel0, pu_rel1, pu_rel2, pu_rel3;

    // pusher base parameters are BYTE addresses (ddr_base is the slot byte base)
    localparam [31:0] PUSH_BASE0 = SLOT_BASE_WORD * 32;
    localparam [31:0] PUSH_BASE1 = (SLOT_BASE_WORD + SLOT_WORDS) * 32;

    ddr_frame_pusher #(
        .W(W), .H(H), .PAY_DW(32), .MAX_FRAME_BYTES(3840*2160),
        .FIFO_AW(7), .BURST_BEATS(128), .WAIT_LIMIT(16'hFFFF),
        .BASE0(PUSH_BASE0),
        .BASE1(PUSH_BASE1),
        .BASE0B(PUSH_BASE0),
        .BASE1B(PUSH_BASE1)
    ) u_pusher (
        .clk_fb(tl_clk), .rst_fb(~tl_rst_n),
        .push_en(cfg_push_en),
        .src_sel(1'b0),
        .fb_frame_cnt(32'd0),
        .fb_rd_addr(pu_fb_addr), .fb_rd_data(32'd0),
        .fb_req(pu_fb_req), .fb_grant(1'b1),
        .src_act(pu_src_act), .fb_hold(pu_fb_hold),
        .dst_lo(cfg_dst_lo), .dst_hi(cfg_dst_hi),
        .db_lo(cfg_db_lo),   .db_hi(cfg_db_hi),
        .st_done(o_push_done), .st_status(o_push_status),
        .st_err(o_push_err), .st_tlp_cnt(o_push_tlp),

        .arm_pulse(pu_arm), .ack_pulse(tx_ack), .cancel_pulse(tx_cancel),
        .cap_bytes(tx_cap_bytes), .session_id(tx_session_id),
        .ack_seq_w(tx_ack_seq), .ack_session_w(tx_ack_session),
        .cfg_reject(1'b0),
        .link_up(link_up), .mps_code(mps_code),
        .ddr_cap_bytes(DDR_CAP_BYTES),
        .cam_sel_live(m_cam_sel),
        .tx_status(o_tx_status), .tx_block_cfg(o_tx_block_cfg),
        .rel_tgl0(pu_rel0), .rel_tgl1(pu_rel1), .rel_tgl2(pu_rel2), .rel_tgl3(pu_rel3),
        .tx_src_lock(pu_src_lock),

        .frame_bytes(m_frame_bytes),
        .ddr_seq(pu_seq),
        .ddr_base(m_slot_base_bytes),
        .ddr_status(m_ddr_status),

        .utx_sel(utx_sel), .tl_tx_wait(tl_tx_wait),
        .utx_req(utx_req), .utx_data(utx_data), .utx_sop(utx_sop),
        .utx_eop(utx_eop), .utx_valid(utx_valid),

        .clk_ddr(usr_clk), .rst_ddr(~rst_usr_n),

        .m_axi_arid(pu_arid), .m_axi_araddr(pu_araddr), .m_axi_arlen(pu_arlen),
        .m_axi_arsize(pu_arsize), .m_axi_arburst(pu_arburst),
        .m_axi_arvalid(pu_arvalid), .m_axi_arready(pu_arready),
        .m_axi_rid(pu_rid), .m_axi_rdata(pu_rdata), .m_axi_rresp(pu_rresp),
        .m_axi_rlast(pu_rlast), .m_axi_rvalid(pu_rvalid), .m_axi_rready(pu_rready)
    );

    // pusher HELD/BUSY for P4: derived from tx_status, see INT.P4-protocol 0x114
    assign p_held_w = o_tx_status[2];   // pusher 0xC4 bit2 = G_HELD
    assign p_busy_w = o_tx_status[1];   // pusher 0xC4 bit1 = tx_active

    brd_ddr_rd_arb u_arb (
        .clk(usr_clk), .rst_n(rst_usr_n),
        .b_araddr(br_araddr_b), .b_arvalid(br_arvalid), .b_arready(br_arready),
        .b_rdata(br_rdata), .b_rresp(), .b_rlast(br_rlast),
        .b_rvalid(br_rvalid), .b_rready(br_rready),
        .p_arid(pu_arid), .p_araddr(pu_araddr), .p_arlen(pu_arlen),
        .p_arsize(pu_arsize), .p_arburst(pu_arburst),
        .p_arvalid(pu_arvalid), .p_arready(pu_arready),
        .p_rid(pu_rid), .p_rdata(pu_rdata), .p_rresp(pu_rresp),
        .p_rlast(pu_rlast), .p_rvalid(pu_rvalid), .p_rready(pu_rready),
        .m_arid(ddr_arid), .m_araddr(ddr_araddr), .m_arlen(ddr_arlen),
        .m_arsize(ddr_arsize), .m_arburst(ddr_arburst),
        .m_arvalid(ddr_arvalid), .m_arready(ddr_arready),
        .m_rid(ddr_rid), .m_rdata(ddr_rdata), .m_rresp(ddr_rresp),
        .m_rlast(ddr_rlast), .m_rvalid(ddr_rvalid), .m_rready(ddr_rready),
        .o_owner(o_arb_owner), .o_busy(), .o_late_cnt(o_arb_late),
        .o_switch_err(o_arb_switch), .o_b_xacts(), .o_p_xacts()
    );

    // =========================================================================
    // P4 status words for BAR 0x130..0x13C
    // =========================================================================
    assign p4_st0 = {p4_st_committed[15:0], p4_st_release[7:0],
                     4'd0, b_desc_active, p_held_w, p_busy_w, cfg_push_en, cfg_a_enable};
    assign p4_st1 = {p4_st_raw_len[15:0], p4_st_stream_len[15:0]};
    assign p4_st2 = {p4_st_blocks[15:0], p4_st_stall[15:0]};
    assign p4_st3 = {p4_st_exported[15:0], p4_st_release[15:0]};

    assign o_p4_desc_active = b_desc_active;
    assign o_slot_busy      = p4_st_adapter_busy;
    assign o_arm_seq        = m_capture_seq;

endmodule

// ---------------------------------------------------------------------------
// single-bit 2FF level synchroniser (C3b)
// ---------------------------------------------------------------------------
module brd_2ff_sync (
    input  wire clk,
    input  wire rst_n,
    input  wire d,
    output wire q
);
    (* async_reg = "true" *) reg [1:0] s;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) s <= 2'b00;
        else        s <= {s[0], d};
    end
    assign q = s[1];
endmodule

