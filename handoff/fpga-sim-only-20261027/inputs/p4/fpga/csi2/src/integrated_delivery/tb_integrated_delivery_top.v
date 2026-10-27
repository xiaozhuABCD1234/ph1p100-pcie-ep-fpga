`timescale 1ns/1ps
// =============================================================================
// tb_integrated_delivery_top.v -- INT.P4 integrated testbench (reduced geometry)
//
// Real DUT: integrated_delivery_top (P1 + b20 A+ core + slot store + arbiter +
// P2 egress adapter + P3 dual-channel scheduler).  TB-side models only:
//   * native 256-bit DDR (256-word array, programmable latency + write stalls)
//   * capture frame sources for channel A/B (RAW10 4-sample beats)
//   * PCIe backend / host ACK model (busy, done, held seq/sess, ACK, bad ACK)
//
// Covered: backpressure (DDR write stalls, m_ready gaps), abort, A disabled with
// B priority, identity + full-field release, descriptor/length/last/complete/
// release, RAW bypass vs Y8 separation, A1U1 sample emission + decode material.
// =============================================================================
module tb_integrated_delivery_top;

    localparam integer W = 64;
    localparam integer H = 48;
    localparam integer SLOT_WORDS = 1024;
    localparam integer BEATS = (W/4)*H;

    localparam [31:0] EXP_SESSION = 32'h0000_1234;
    localparam [63:0] EXP_DST     = 64'h0000_0000_1000_0000;
    localparam [63:0] EXP_DB      = 64'h0000_0000_2000_0000;

    // ---------------------------------------------------------------- clock/reset
    reg clk;
    reg rst_n;
    initial clk = 1'b0;
    always #2.6665 clk = ~clk;

    // ---------------------------------------------------------------- DUT ports
    reg         a_s_valid, a_s_sof, a_s_eol, a_s_eof, a_s_abort;
    wire        a_s_ready;
    reg  [39:0] a_s_data;
    reg         b_s_valid, b_s_sof, b_s_eol, b_s_eof, b_s_abort;
    wire        b_s_ready;
    reg  [39:0] b_s_data;

    reg  [2:0]  cfg_mode;
    reg  [1:0]  cfg_phase;
    reg         cfg_prep, cfg_pred;

    reg         push_en, link_up;
    reg  [31:0] cap_bytes, session_id;
    reg  [63:0] dst_base, db_addr;
    reg  [2:0]  mps_code;

    reg         a_desc_valid, a_desc_camera_id, a_desc_slot_id;
    reg  [31:0] a_desc_epoch, a_desc_session, a_desc_capture_seq;
    wire        a_desc_ready;
    reg         b_desc_valid, b_desc_camera_id, b_desc_slot_id;
    reg  [31:0] b_desc_epoch, b_desc_session, b_desc_capture_seq;
    wire        b_desc_ready;
    reg         a_enable, b_priority;

    reg         ack_pulse;
    reg  [31:0] ack_seq, ack_session;
    reg         cancel_pulse;

    reg         pcie_busy, pcie_held, pcie_done, pcie_err;
    reg  [31:0] pcie_held_seq, pcie_held_sess;

    reg         ddr_ready;
    wire [31:0]  ddr_awaddr;
    wire         ddr_awvalid;
    wire         ddr_awready;
    wire [255:0] ddr_wdata;
    wire         ddr_wvalid;
    wire         ddr_wready;
    wire [31:0]  ddr_araddr;
    wire         ddr_arvalid;
    wire         ddr_arready;
    wire [255:0] ddr_rdata;
    wire         ddr_rvalid;
    wire         ddr_rready;

    wire        desc_arm;
    wire [31:0] desc_cap_bytes, desc_session_id, desc_frame_bytes, desc_stream_len;
    wire [31:0] desc_slot_base_word;
    wire [63:0] desc_dst_base, desc_db_addr;
    wire        desc_src_sel, desc_cam_sel, slot_release;
    wire        desc_ident_valid, desc_camera_id, desc_slot_id;
    wire [31:0] desc_epoch, desc_capture_seq;

    wire        rel_valid, rel_camera_id, rel_slot_id;
    wire [31:0] rel_epoch, rel_session, rel_capture_seq;
    wire [2:0]  rel_status;

    reg         m_ready;
    wire        mon_accept;
    wire        m_valid;
    wire [2:0]  m_mode;
    wire        m_is_raw;
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
    wire [31:0] st_raw_crc, st_xform_crc, st_stream_crc;
    wire [31:0] st_blocks, st_stall;
    wire [15:0] st_p1_good, st_p1_abort;
    wire [31:0] st_store_published, st_store_dropped, st_store_errors;
    wire [31:0] st_exported, st_adapter_err;
    wire        st_adapter_busy, st_adapter_held;
    wire [31:0] st_frames_committed, st_frames_aborted;
    wire [31:0] st_release_count, st_admit_count, st_drain_words, st_cfg_error;
    wire [15:0] st_sched_accepted, st_sched_completed, st_sched_failed, st_sched_rejected;
    wire        st_sched_a_busy, st_sched_b_busy, st_sched_last_cam;
    wire [3:0]  st_glue_state;

    integrated_delivery_top #(
        .W(W), .H(H), .MAX_WORDS(512), .SLOT_WORDS(SLOT_WORDS),
        .SLOT_BASE_WORD(32'd0), .SLOT_AWB(18), .ALIGN_BYTES(32'd4096)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .a_s_valid(a_s_valid), .a_s_ready(a_s_ready), .a_s_data(a_s_data),
        .a_s_sof(a_s_sof), .a_s_eol(a_s_eol), .a_s_eof(a_s_eof),
        .a_s_abort(a_s_abort),
        .b_s_valid(b_s_valid), .b_s_ready(b_s_ready), .b_s_data(b_s_data),
        .b_s_sof(b_s_sof), .b_s_eol(b_s_eol), .b_s_eof(b_s_eof),
        .b_s_abort(b_s_abort),
        .cfg_mode(cfg_mode), .cfg_phase(cfg_phase),
        .cfg_aplus_prep(cfg_prep), .cfg_aplus_pred(cfg_pred),
        .push_en(push_en), .cap_bytes(cap_bytes), .session_id(session_id),
        .dst_base(dst_base), .db_addr(db_addr), .mps_code(mps_code),
        .link_up(link_up),
        .a_desc_valid(a_desc_valid), .a_desc_ready(a_desc_ready),
        .a_desc_camera_id(a_desc_camera_id), .a_desc_slot_id(a_desc_slot_id),
        .a_desc_epoch(a_desc_epoch), .a_desc_session(a_desc_session),
        .a_desc_capture_seq(a_desc_capture_seq),
        .b_desc_valid(b_desc_valid), .b_desc_ready(b_desc_ready),
        .b_desc_camera_id(b_desc_camera_id), .b_desc_slot_id(b_desc_slot_id),
        .b_desc_epoch(b_desc_epoch), .b_desc_session(b_desc_session),
        .b_desc_capture_seq(b_desc_capture_seq),
        .a_enable(a_enable), .b_priority(b_priority),
        .ack_pulse(ack_pulse), .ack_seq(ack_seq), .ack_session(ack_session),
        .cancel_pulse(cancel_pulse),
        .pcie_busy(pcie_busy), .pcie_held(pcie_held), .pcie_done(pcie_done),
        .pcie_err(pcie_err), .pcie_held_seq(pcie_held_seq),
        .pcie_held_sess(pcie_held_sess),
        .ddr_ready(ddr_ready),
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
        .m_ready(m_ready), .mon_accept(mon_accept), .m_valid(m_valid), .m_mode(m_mode),
        .m_is_raw(m_is_raw), .m_raw_data(m_raw_data), .m_proc_data(m_proc_data),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof), .m_abort(m_abort),
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
        .st_sched_last_cam(st_sched_last_cam),
        .st_glue_state(st_glue_state)
    );

    // ============================================================ DDR model
    localparam integer DDR_DEPTH = 4096;   // 256-bit words
    reg [255:0] ddr_mem [0:DDR_DEPTH-1];
    reg         ddr_stall_en;
    integer     ddr_lat;
    reg [2:0]   ddr_stall_cnt;
    integer     ddr_cyc;
    wire        ddr_wr_hs = ddr_awvalid && ddr_awready && ddr_wvalid && ddr_wready;

    reg         ddr_stall_w;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ddr_stall_cnt <= 3'd0;
            ddr_stall_w   <= 1'b0;
            ddr_cyc       <= 0;
        end else begin
            ddr_cyc <= ddr_cyc + 1;
            if (!ddr_stall_en) begin
                ddr_stall_w <= 1'b0;
            end else if (ddr_stall_cnt != 3'd0) begin
                ddr_stall_cnt <= ddr_stall_cnt - 3'd1;
                ddr_stall_w   <= 1'b1;
            end else if ((ddr_cyc % 23) == 0) begin
                ddr_stall_cnt <= 3'd4;
                ddr_stall_w   <= 1'b1;
            end else begin
                ddr_stall_w   <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (ddr_wr_hs) ddr_mem[ddr_awaddr[11:0]] <= ddr_wdata;
    end

    assign ddr_arready = 1'b1;
    assign ddr_awready = ddr_ready && !ddr_stall_w;
    assign ddr_wready  = ddr_ready && !ddr_stall_w;

    reg         r_busy, r_valid;
    reg [31:0]  r_addr;
    integer     r_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_busy  <= 1'b0;
            r_valid <= 1'b0;
            r_addr  <= 32'd0;
            r_cnt   <= 0;
        end else if (!r_busy) begin
            r_valid <= 1'b0;
            if (ddr_arvalid && ddr_arready) begin
                r_busy <= 1'b1;
                r_addr <= ddr_araddr;
                r_cnt  <= ddr_lat;
            end
        end else begin
            if (r_cnt > 0) begin
                r_cnt <= r_cnt - 1;
            end else begin
                r_valid <= 1'b1;
                if (r_valid && ddr_rready) begin
                    r_valid <= 1'b0;
                    r_busy  <= 1'b0;
                end
            end
        end
    end

    assign ddr_rvalid = r_valid;
    assign ddr_rdata  = ddr_mem[r_addr[11:0]];

    // ============================================================ capture sources
    function [39:0] mk_vec;
        input [31:0] seed;
        input integer y;
        input integer gx;
        integer i;
        reg [9:0] p;
        begin
            mk_vec = 40'd0;
            for (i = 0; i < 4; i = i + 1) begin
                p = (seed + y*97 + (gx*4+i)*13 + (gx*y)*7) & 10'h3FF;
                mk_vec[10*i +: 10] = p;
            end
        end
    endfunction

    function integer keep_count;
        input [3:0] k;
        begin
            keep_count = {31'd0, k[0]} + {31'd0, k[1]} +
                         {31'd0, k[2]} + {31'd0, k[3]};
        end
    endfunction

    // ============================================================ observation
    reg [7:0]   payload  [0:32767];
    reg [7:0]   rawbytes [0:32767];
    reg [255:0] drainmem  [0:2047];
    integer     payload_n, raw_n, drain_n;
    integer     m_beats, m_sof_seen, m_eol_seen, m_eof_seen;
    reg         mon_active;
    reg         mon_is_raw_exp;
    reg [31:0]  mon_seed;
    reg [31:0]  mon_seq;
    integer     mon_err;
    integer     mon_zero;   // processed-mode beats whose selected data is all zero

    // sticky capture of the full-field release handshake (one-cycle pulse)
    reg         rel_seen;
    reg         rel_cam_l, rel_slot_l;
    reg  [31:0] rel_epoch_l, rel_session_l, rel_seq_l;
    reg  [2:0]  rel_status_l;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rel_seen <= 1'b0; rel_cam_l <= 1'b0; rel_slot_l <= 1'b0;
            rel_epoch_l <= 32'd0; rel_session_l <= 32'd0; rel_seq_l <= 32'd0;
            rel_status_l <= 3'd0;
        end else if (rel_valid) begin
            rel_seen     <= 1'b1;
            rel_cam_l    <= rel_camera_id;
            rel_slot_l   <= rel_slot_id;
            rel_epoch_l  <= rel_epoch;
            rel_session_l<= rel_session;
            rel_seq_l    <= rel_capture_seq;
            rel_status_l <= rel_status;
        end
    end

    integer errors;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            payload_n <= 0;
            raw_n     <= 0;
            drain_n   <= 0;
            m_beats   <= 0;
            m_sof_seen <= 0;
            m_eol_seen <= 0;
            m_eof_seen <= 0;
            mon_err   <= 0;
            mon_zero  <= 0;
        end else begin
            // A+ stored beats -> payload bytes (exact stored stream)
            if (ap_accept) begin
                if (ap_keep[0]) payload[payload_n]   <= ap_data[7:0];
                if (ap_keep[1]) payload[payload_n+1] <= ap_data[15:8];
                if (ap_keep[2]) payload[payload_n+2] <= ap_data[23:16];
                if (ap_keep[3]) payload[payload_n+3] <= ap_data[31:24];
                payload_n <= payload_n + keep_count(ap_keep);
            end
            // packed RAW10 accepted by the A+ entrance
            if (pk_accept) begin
                rawbytes[raw_n]   <= pk_data[7:0];
                rawbytes[raw_n+1] <= pk_data[15:8];
                rawbytes[raw_n+2] <= pk_data[23:16];
                rawbytes[raw_n+3] <= pk_data[31:24];
                rawbytes[raw_n+4] <= pk_data[39:32];
                raw_n <= raw_n + 5;
            end
            // released slot drain words
            if (drain_accept) begin
                drainmem[drain_n] <= drain_data;
                drain_n <= drain_n + 1;
            end
            // monitor stream (P1 selected output)
            if (mon_accept) begin
                m_beats <= m_beats + 1;
                if (m_sof) m_sof_seen <= m_sof_seen + 1;
                if (m_eol) m_eol_seen <= m_eol_seen + 1;
                if (m_eof) m_eof_seen <= m_eof_seen + 1;
                if (mon_active && (m_is_raw !== mon_is_raw_exp)) begin
                    mon_err <= mon_err + 1;
                    if (mon_err < 3) $display("MON_FAIL is_raw=%0d exp=%0d beat=%0d",
                                              m_is_raw, mon_is_raw_exp, m_beats);
                end
                if (mon_active && mon_is_raw_exp) begin
                    if (m_raw_data !== mk_vec(mon_seed,
                             (m_beats/(W/4)), (m_beats % (W/4)))) begin
                        mon_err <= mon_err + 1;
                        if (mon_err < 3) $display("MON_FAIL raw mismatch beat=%0d got=%010x exp=%010x",
                            m_beats, m_raw_data, mk_vec(mon_seed,(m_beats/(W/4)),(m_beats%(W/4))));
                    end
                end
                if (mon_active && !mon_is_raw_exp && (m_proc_data == 32'd0))
                    mon_zero <= mon_zero + 1;
            end
        end
    end

    // ============================================================ debug counters
    integer dbg_mv, dbg_cv, dbg_sr, dbg_pk;
    integer dbg_fv, dbg_g0, dbg_yr, dbg_yv, dbg_gs, dbg_hs, dbg_yf;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbg_mv <= 0; dbg_cv <= 0; dbg_sr <= 0; dbg_pk <= 0;
            dbg_fv <= 0; dbg_g0 <= 0; dbg_yr <= 0; dbg_yv <= 0;
            dbg_gs <= 0; dbg_hs <= 0; dbg_yf <= 0;
        end else begin
            if (m_valid) dbg_mv <= dbg_mv + 1;
            if (dut.cap_valid) dbg_cv <= dbg_cv + 1;
            if (dut.cap_valid && dut.p1_s_ready) dbg_sr <= dbg_sr + 1;
            if (dut.p1_pk_valid && dut.p1_pk_ready) dbg_pk <= dbg_pk + 1;
            if (dut.u_p1.u_algo.f_valid) dbg_fv <= dbg_fv + 1;
            if (dut.u_p1.u_algo.g0_valid) dbg_g0 <= dbg_g0 + 1;
            if (dut.u_p1.u_algo.y8_stream_ready) dbg_yr <= dbg_yr + 1;
            if (dut.u_p1.u_algo.y8_valid) dbg_yv <= dbg_yv + 1;
            if (dut.u_p1.u_algo.gau_s_ready) dbg_gs <= dbg_gs + 1;
            if (dut.u_p1.u_algo.he_s_ready) dbg_hs <= dbg_hs + 1;
            if (dut.u_p1.u_algo.y8_fifo_ready) dbg_yf <= dbg_yf + 1;

        end
    end

    // ============================================================ PCIe backend
    localparam integer PS_IDLE = 0, PS_BUSY = 1, PS_END = 2, PS_ACK = 3;
    integer     ps;
    integer     ps_cnt;
    reg [31:0]  seq_gen;
    reg [31:0]  held_seq_r, held_sess_r;
    reg         ack_bad_en;
    integer     ack_bad_cnt;
    integer     ack_delay;
    integer     busy_cycles;

    // descriptor snapshot taken at arm
    reg [31:0]  arm_frame_bytes, arm_stream_len, arm_session;
    reg [63:0]  arm_dst, arm_db;
    reg         arm_src_sel, arm_cam, arm_slot;
    reg [31:0]  arm_seq, arm_epoch, arm_base_word;
    reg         arm_ident_valid;
    integer     arm_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ps             <= PS_IDLE;
            ps_cnt         <= 0;
            seq_gen        <= 32'h100;
            held_seq_r     <= 32'd0;
            held_sess_r    <= 32'd0;
            pcie_busy      <= 1'b0;
            pcie_done      <= 1'b0;
            pcie_held      <= 1'b0;
            pcie_err       <= 1'b0;
            pcie_held_seq  <= 32'd0;
            pcie_held_sess <= 32'd0;
            ack_pulse      <= 1'b0;
            ack_seq        <= 32'd0;
            ack_session    <= 32'd0;
            arm_count      <= 0;
            arm_frame_bytes<= 32'd0;
            arm_stream_len <= 32'd0;
            arm_session    <= 32'd0;
            arm_dst        <= 64'd0;
            arm_db         <= 64'd0;
            arm_src_sel    <= 1'b0;
            arm_cam        <= 1'b0;
            arm_slot       <= 1'b0;
            arm_seq        <= 32'd0;
            arm_epoch      <= 32'd0;
            arm_base_word  <= 32'd0;
            arm_ident_valid<= 1'b0;
        end else begin
            pcie_done <= 1'b0;
            ack_pulse <= 1'b0;

            if (desc_arm) begin
                arm_frame_bytes <= desc_frame_bytes;
                arm_stream_len  <= desc_stream_len;
                arm_session     <= desc_session_id;
                arm_dst         <= desc_dst_base;
                arm_db          <= desc_db_addr;
                arm_src_sel     <= desc_src_sel;
                arm_cam         <= desc_camera_id;
                arm_slot        <= desc_slot_id;
                arm_seq         <= desc_capture_seq;
                arm_epoch       <= desc_epoch;
                arm_base_word   <= desc_slot_base_word;
                arm_ident_valid <= desc_ident_valid;
                arm_count       <= arm_count + 1;
            end

            case (ps)
                PS_IDLE: begin
                    if (desc_arm) begin
                        pcie_busy <= 1'b1;
                        ps_cnt    <= busy_cycles;
                        ps        <= PS_BUSY;
                    end
                end
                PS_BUSY: begin
                    if (ps_cnt > 0) ps_cnt <= ps_cnt - 1;
                    else begin
                        pcie_busy      <= 1'b0;
                        pcie_done      <= 1'b1;
                        pcie_held      <= 1'b1;
                        held_seq_r     <= seq_gen;
                        held_sess_r    <= desc_session_id;
                        pcie_held_seq  <= seq_gen;
                        pcie_held_sess <= desc_session_id;
                        seq_gen        <= seq_gen + 32'd1;
                        ps_cnt         <= 0;
                        ps             <= PS_END;
                    end
                end
                PS_END: begin
                    pcie_done <= 1'b0;
                    ps_cnt    <= 0;
                    ps        <= PS_ACK;
                end
                PS_ACK: begin
                    if (ps_cnt < ack_delay) begin
                        ps_cnt <= ps_cnt + 1;
                    end else if (ack_bad_en && (ack_bad_cnt == 0)) begin
                        // wrong identity first: adapter must keep ownership
                        ack_pulse   <= 1'b1;
                        ack_seq     <= held_seq_r + 32'd9;
                        ack_session <= held_sess_r;
                        ack_bad_cnt <= ack_bad_cnt + 1;
                        ps_cnt      <= 0;
                    end else begin
                        ack_pulse   <= 1'b1;
                        ack_seq     <= held_seq_r;
                        ack_session <= held_sess_r;
                        pcie_held   <= 1'b0;
                        ps          <= PS_IDLE;
                    end
                end
                default: ps <= PS_IDLE;
            endcase
        end
    end

    // ============================================================ helpers
    integer errors_total;
    integer mode_arg, sample_en, extra_en;
    task chk;
        input [8*40-1:0] name;
        input integer    cond;
        begin
            if (cond) begin
                $display("  ok   : %0s", name);
            end else begin
                errors_total = errors_total + 1;
                $display("  FAIL : %0s", name);
            end
        end
    endtask

    // drive one capture frame on the selected channel.
    // abort_beat: 0-based beat index that carries a one-cycle abort marker (-1 = none)
    // eof_beat  : 0-based beat index that carries the EOF marker (normally BEATS-1)
    task drive_frame;
        input integer ch;
        input [31:0]  seed;
        input integer abort_beat;
        input integer eof_beat;
        integer y, gx, beat;
        reg [39:0] v;
        begin
            beat = 0;
            $display("DRIVE start ch=%0d", ch);
            for (y = 0; y < H; y = y + 1) begin
                for (gx = 0; gx < (W/4); gx = gx + 1) begin
                    v = mk_vec(seed, y, gx);
                    if ((beat % 128) == 0) $display("DRIVE ch=%0d beat=%0d y=%0d", ch, beat, y);
                    if (beat == abort_beat) begin
                        // The frame abort is a level marker, not a data beat: the
                        // A+ core blocks in_ready while abort is high, so the beat
                        // must not wait for a handshake.  Assert for one cycle.
                        @(negedge clk);
                        if (ch == 0) begin
                            a_s_valid = 1'b1; a_s_data = v; a_s_sof = 1'b0;
                            a_s_eol = 1'b0; a_s_eof = 1'b0; a_s_abort = 1'b1;
                        end else begin
                            b_s_valid = 1'b1; b_s_data = v; b_s_sof = 1'b0;
                            b_s_eol = 1'b0; b_s_eof = 1'b0; b_s_abort = 1'b1;
                        end
                        @(posedge clk);
                        @(negedge clk);
                        if (ch == 0) begin a_s_valid = 1'b0; a_s_abort = 1'b0; end
                        else         begin b_s_valid = 1'b0; b_s_abort = 1'b0; end
                        y = H; gx = W/4; // break both loops
                    end else begin
                        @(negedge clk);
                        if (ch == 0) begin
                            a_s_valid = 1'b1; a_s_data = v;
                            a_s_sof   = (beat == 0);
                            a_s_eol   = (gx == (W/4-1));
                            a_s_eof   = (beat == eof_beat);
                            a_s_abort = 1'b0;
                        end else begin
                            b_s_valid = 1'b1; b_s_data = v;
                            b_s_sof   = (beat == 0);
                            b_s_eol   = (gx == (W/4-1));
                            b_s_eof   = (beat == eof_beat);
                            b_s_abort = 1'b0;
                        end
                        // ready is sampled mid-cycle (stable between edges); the
                        // following posedge performs the transfer.  Sampling it at
                        // the posedge would race with the DUT's next-state update.
                        #1;
                        if (ch == 0) while (!a_s_ready) begin @(negedge clk); #1; end
                        else         while (!b_s_ready) begin @(negedge clk); #1; end
                        @(posedge clk);
                        beat = beat + 1;
                    end
                end
            end
            $display("DRIVE done ch=%0d beat=%0d", ch, beat);
            @(negedge clk);
            if (ch == 0) begin a_s_valid = 1'b0; a_s_abort = 1'b0; a_s_sof = 1'b0; a_s_eol = 1'b0; a_s_eof = 1'b0; end
            else         begin b_s_valid = 1'b0; b_s_abort = 1'b0; b_s_sof = 1'b0; b_s_eol = 1'b0; b_s_eof = 1'b0; end
        end
    endtask

    task present_desc;
        input integer cam;
        input         slot;
        input [31:0]  epoch;
        input [31:0]  sess;
        input [31:0]  seq;
        begin
            @(negedge clk);
            if (cam == 0) begin
                a_desc_valid      = 1'b1;
                a_desc_camera_id  = 1'b0;
                a_desc_slot_id    = slot;
                a_desc_epoch      = epoch;
                a_desc_session    = sess;
                a_desc_capture_seq= seq;
            end else begin
                b_desc_valid      = 1'b1;
                b_desc_camera_id  = 1'b1;
                b_desc_slot_id    = slot;
                b_desc_epoch      = epoch;
                b_desc_session    = sess;
                b_desc_capture_seq= seq;
            end
        end
    endtask

    task wait_grant;
        input integer cam;
        begin
            // ready is sampled mid-cycle; the posedge performs the handshake.
            // Checking only at the next negedge could miss an accept that
            // happened on the very first posedge after the descriptor was driven.
            #1;
            if (cam == 0) begin
                while (!a_desc_ready) begin @(negedge clk); #1; end
                @(posedge clk);
                @(negedge clk);
                a_desc_valid = 1'b0;
            end else begin
                while (!b_desc_ready) begin @(negedge clk); #1; end
                @(posedge clk);
                @(negedge clk);
                b_desc_valid = 1'b0;
            end
        end
    endtask

    // crc32 helpers (same polynomial/convention as the RTL and the Python tool)
    function [31:0] crc32_byte;
        input [31:0] c;
        input [7:0]  d;
        integer k;
        reg [31:0] x;
        begin
            x = c ^ d;
            for (k = 0; k < 8; k = k + 1)
                x = x[0] ? ((x >> 1) ^ 32'hEDB88320) : (x >> 1);
            crc32_byte = x;
        end
    endfunction

    reg [7:0]   hdr [0:43];
    reg [31:0]  hcrc;
    reg [1023:0] sample_dir;
    reg [1023:0] fpath;
    integer     fd, i;
    integer     exp_beats;

    task build_and_write_sample;
        begin
            // 44-byte A1U1 header
            hdr[0]  = 8'h41; hdr[1] = 8'h31; hdr[2] = 8'h55; hdr[3] = 8'h31; // 'A1U1'
            hdr[4]  = 8'h01;                       // version
            hdr[5]  = {6'd0, cfg_pred, cfg_prep};  // flags = {pred, prep}
            hdr[6]  = 8'd44; hdr[7] = 8'd0;        // header_len LE = 44
            hdr[8]  = mon_seq[7:0];   hdr[9]  = mon_seq[15:8];
            hdr[10] = mon_seq[23:16]; hdr[11] = mon_seq[31:24];
            hdr[12] = W[7:0]; hdr[13] = W[15:8];
            hdr[14] = H[7:0]; hdr[15] = H[15:8];
            hdr[16] = st_raw_len[7:0];   hdr[17] = st_raw_len[15:8];
            hdr[18] = st_raw_len[23:16]; hdr[19] = st_raw_len[31:24];
            hdr[20] = st_xform_len[7:0];   hdr[21] = st_xform_len[15:8];
            hdr[22] = st_xform_len[23:16]; hdr[23] = st_xform_len[31:24];
            hdr[24] = st_stream_len[7:0];   hdr[25] = st_stream_len[15:8];
            hdr[26] = st_stream_len[23:16]; hdr[27] = st_stream_len[31:24];
            hdr[28] = st_raw_crc[7:0];   hdr[29] = st_raw_crc[15:8];
            hdr[30] = st_raw_crc[23:16]; hdr[31] = st_raw_crc[31:24];
            hdr[32] = st_xform_crc[7:0];   hdr[33] = st_xform_crc[15:8];
            hdr[34] = st_xform_crc[23:16]; hdr[35] = st_xform_crc[31:24];
            hdr[36] = st_stream_crc[7:0];   hdr[37] = st_stream_crc[15:8];
            hdr[38] = st_stream_crc[23:16]; hdr[39] = st_stream_crc[31:24];
            hcrc = 32'hFFFFFFFF;
            for (i = 0; i < 40; i = i + 1) hcrc = crc32_byte(hcrc, hdr[i]);
            hcrc = ~hcrc;
            hdr[40] = hcrc[7:0];   hdr[41] = hcrc[15:8];
            hdr[42] = hcrc[23:16]; hdr[43] = hcrc[31:24];

            if (!$value$plusargs("SAMPLE_DIR=%s", sample_dir)) sample_dir = ".";
            $sformat(fpath, "%0s/integrated_sample.a1u1", sample_dir);
            fd = $fopen(fpath, "wb");
            if (fd == 0) begin
                $display("SAMPLE_OPEN_FAIL %0s", fpath);
                errors_total = errors_total + 1;
            end else begin
                for (i = 0; i < 44; i = i + 1) $fwrite(fd, "%c", hdr[i]);
                for (i = 0; i < payload_n; i = i + 1) $fwrite(fd, "%c", payload[i]);
                $fclose(fd);
                $display("SAMPLE_WRITTEN %0s payload=%0d", fpath, payload_n);
            end

            $sformat(fpath, "%0s/integrated_sample.raw", sample_dir);
            fd = $fopen(fpath, "wb");
            if (fd == 0) begin
                $display("RAW_OPEN_FAIL %0s", fpath);
                errors_total = errors_total + 1;
            end else begin
                for (i = 0; i < raw_n; i = i + 1) $fwrite(fd, "%c", rawbytes[i]);
                $fclose(fd);
                $display("RAW_WRITTEN %0s bytes=%0d", fpath, raw_n);
            end

            $sformat(fpath, "%0s/integrated_sample.json", sample_dir);
            fd = $fopen(fpath, "w");
            if (fd == 0) begin
                $display("JSON_OPEN_FAIL %0s", fpath);
                errors_total = errors_total + 1;
            end else begin
                $fwrite(fd, "{\n");
                $fwrite(fd, "  \"task\": \"INT.P4\",\n");
                $fwrite(fd, "  \"source\": \"integrated_delivery_top RTL simulation (a1_frame_top + slot store + egress adapter)\",\n");
                $fwrite(fd, "  \"format\": \"A1U1\",\n");
                $fwrite(fd, "  \"width\": %0d,\n  \"height\": %0d,\n", W, H);
                $fwrite(fd, "  \"prep\": %0d,\n  \"pred\": %0d,\n", cfg_prep, cfg_pred);
                $fwrite(fd, "  \"raw_len\": %0d,\n", st_raw_len);
                $fwrite(fd, "  \"xform_len\": %0d,\n", st_xform_len);
                $fwrite(fd, "  \"stream_len\": %0d,\n", st_stream_len);
                $fwrite(fd, "  \"raw_crc\": %0d,\n", st_raw_crc);
                $fwrite(fd, "  \"xform_crc\": %0d,\n", st_xform_crc);
                $fwrite(fd, "  \"stream_crc\": %0d,\n", st_stream_crc);
                $fwrite(fd, "  \"header_crc\": %0d,\n", hcrc);
                $fwrite(fd, "  \"payload_bytes\": %0d,\n", payload_n);
                $fwrite(fd, "  \"pk_bytes\": %0d,\n", raw_n);
                $fwrite(fd, "  \"frame_bytes\": %0d,\n", arm_frame_bytes);
                $fwrite(fd, "  \"transport_aligned\": 4096,\n");
                $fwrite(fd, "  \"session_id\": %0d,\n", arm_session);
                $fwrite(fd, "  \"dst_base\": \"0x%016x\",\n", arm_dst);
                $fwrite(fd, "  \"db_addr\": \"0x%016x\",\n", arm_db);
                $fwrite(fd, "  \"src_sel\": %0d,\n", arm_src_sel);
                $fwrite(fd, "  \"camera_id\": %0d,\n", arm_cam);
                $fwrite(fd, "  \"slot_id\": %0d,\n", arm_slot);
                $fwrite(fd, "  \"capture_seq\": %0d,\n", arm_seq);
                $fwrite(fd, "  \"epoch\": %0d,\n", arm_epoch);
                $fwrite(fd, "  \"slot_base_word\": %0d,\n", arm_base_word);
                $fwrite(fd, "  \"drain_words\": %0d,\n", drain_n);
                $fwrite(fd, "  \"rtl_blocks\": %0d,\n", st_blocks);
                $fwrite(fd, "  \"note\": \"RTL simulation bytes; not a real PCIe transfer and not a board capture\"\n");
                $fwrite(fd, "}\n");
                $fclose(fd);
                $display("JSON_WRITTEN %0s", fpath);
            end
        end
    endtask

    // compare drained slot bytes with the stored payload
    task check_drain_prefix;
        input integer nbytes;
        integer k;
        reg [7:0] b;
        begin
            for (k = 0; k < nbytes; k = k + 1) begin
                b = drainmem[k/32] >> (8*(k%32));
                if (b !== payload[k]) begin
                    if (k < 8) $display("DRAIN_MISMATCH k=%0d got=%02x exp=%02x", k, b, payload[k]);
                    errors_total = errors_total + 1;
                end
            end
        end
    endtask

    task dut_reset;
        begin
            rst_n        = 1'b0;
            m_ready      = 1'b1;
            ddr_stall_en = 1'b0;
            ack_bad_en   = 1'b0;
            ack_bad_cnt  = 0;
            ack_delay    = 12;
            repeat (8) @(posedge clk);
            rst_n = 1'b1;
            repeat (24) @(posedge clk);
        end
    endtask

    // ============================================================ stimulus
    integer rel_timeout;

    localparam integer GOLDEN_RAW    = (W*H*10)/8;   // 3840 for 64x48
    localparam integer GOLDEN_STREAM = 3965;         // deterministic zlib stream for this input

    // per-scenario bookkeeping: every scenario is entered after dut_reset, so the
    // DUT counters restart from 0 and only TB-side accumulators must be cleared.
    task scn_begin;
        begin
            payload_n  = 0; raw_n = 0; drain_n = 0;
            m_beats    = 0; m_sof_seen = 0; m_eol_seen = 0; m_eof_seen = 0;
            mon_err    = 0; mon_zero = 0;
            arm_count  = 0; rel_seen = 1'b0;
        end
    endtask

    task wait_commit;
        input integer limit;
        begin
            rel_timeout = 0;
            while ((st_frames_committed == 0) && (rel_timeout < limit)) begin
                @(posedge clk);
                rel_timeout = rel_timeout + 1;
            end
        end
    endtask

    task wait_release;
        input integer limit;
        begin
            rel_timeout = 0;
            while (!rel_seen && (rel_timeout < limit)) begin
                @(posedge clk);
                rel_timeout = rel_timeout + 1;
            end
        end
    endtask

    initial begin
        errors_total = 0;
        // reset / idle values
        rst_n      = 1'b0;
        a_s_valid  = 1'b0; a_s_data = 40'd0; a_s_sof = 0; a_s_eol = 0; a_s_eof = 0; a_s_abort = 0;
        b_s_valid  = 1'b0; b_s_data = 40'd0; b_s_sof = 0; b_s_eol = 0; b_s_eof = 0; b_s_abort = 0;
        if (!$value$plusargs("MODE=%d", mode_arg)) mode_arg = 1;
        if (!$value$plusargs("SAMPLE=%d", sample_en)) sample_en = 0;
        if (!$value$plusargs("EXTRA=%d", extra_en)) extra_en = 0;
        cfg_mode   = mode_arg[2:0]; cfg_phase = 2'd3; cfg_prep = 1'b0; cfg_pred = 1'b0;
        push_en    = 1'b1; link_up = 1'b1;
        cap_bytes  = 32'd4_000_000; session_id = EXP_SESSION;
        dst_base   = EXP_DST; db_addr = EXP_DB; mps_code = 3'd1;
        a_desc_valid = 0; a_desc_camera_id = 0; a_desc_slot_id = 0;
        a_desc_epoch = 0; a_desc_session = 0; a_desc_capture_seq = 0;
        b_desc_valid = 0; b_desc_camera_id = 1; b_desc_slot_id = 0;
        b_desc_epoch = 0; b_desc_session = 0; b_desc_capture_seq = 0;
        a_enable   = 1'b1; b_priority = 1'b0;
        ack_pulse  = 1'b0; ack_seq = 0; ack_session = 0; cancel_pulse = 1'b0;
        pcie_err   = 1'b0;
        ddr_ready  = 1'b1; ddr_stall_en = 1'b0; ddr_lat = 3;
        m_ready    = 1'b1;
        mon_active = 1'b0; mon_is_raw_exp = 1'b0; mon_seed = 0; mon_seq = 0;
        ack_bad_en = 1'b0; ack_bad_cnt = 0; ack_delay = 12; busy_cycles = 20;
        arm_count  = 0;
        mon_err    = 0; mon_zero = 0;
        rel_seen   = 1'b0;

        repeat (12) @(posedge clk);
        rst_n = 1'b1;
        repeat (20) @(posedge clk);
        ddr_lat = 3;

        // ============================== T1: B single frame (default scenario)
        scn_begin;
        $display("=== T1: B channel, mode=%0d, prep=0/pred=0, A+ sample ===", cfg_mode);
        cfg_prep = 1'b0; cfg_pred = 1'b0;
        mon_active = 1'b1;
        mon_is_raw_exp = (cfg_mode == 3'd0) || (cfg_mode == 3'd4);
        mon_seed = 32'hB000;
        mon_seq = 32'd7;
        exp_beats = BEATS;
        present_desc(1, 1'b1, 32'd11, EXP_SESSION, 32'd7);
        wait_grant(1);
        drive_frame(1, 32'hB000, -1, BEATS-1);

        wait_commit(200000);
        chk("T1 ap_commit observed", st_frames_committed == 1);
        repeat (4) @(posedge clk);
        chk("T1 pk_bytes == raw_len", raw_n == st_raw_len);
        chk("T1 payload_bytes == stream_len", payload_n == st_stream_len);
        chk("T1 raw_len == W*H*10/8", st_raw_len == GOLDEN_RAW);
        chk("T1 stream_len == golden", st_stream_len == GOLDEN_STREAM);
        chk("T1 xform_len == raw_len (prep=0)", st_xform_len == st_raw_len);

        wait_release(200000);
        chk("T1 release observed", rel_seen);
        chk("T1 release camera = B", rel_cam_l == 1'b1);
        chk("T1 release slot/epoch/session/seq",
            (rel_slot_l == 1'b1) && (rel_epoch_l == 32'd11) &&
            (rel_session_l == EXP_SESSION) && (rel_seq_l == 32'd7));
        chk("T1 release status = completed", rel_status_l == 3'd0);
        repeat (6) @(posedge clk);

        chk("T1 descriptor arm count == 1", arm_count == 1);
        chk("T1 frame_bytes 4096 aligned", arm_frame_bytes == 32'd4096);
        chk("T1 desc stream_len == payload bytes", arm_stream_len == payload_n);
        chk("T1 desc session", arm_session == EXP_SESSION);
        chk("T1 desc dst/db", (arm_dst == EXP_DST) && (arm_db == EXP_DB));
        chk("T1 desc src_sel=0 (DDR)", arm_src_sel == 1'b0);
        chk("T1 desc identity (cam/slot/seq/epoch)",
            arm_ident_valid && (arm_cam == 1'b1) && (arm_slot == 1'b1) &&
            (arm_seq == 32'd7) && (arm_epoch == 32'd11));
        $display("  info : T1 m_beats=%0d sof=%0d eol=%0d eof=%0d mons=%0d m_mode=%0d mv=%0d cv=%0d sr=%0d pk=%0d cfg_err=%0d",
                 m_beats, m_sof_seen, m_eol_seen, m_eof_seen, mon_err, m_mode,
                 dbg_mv, dbg_cv, dbg_sr, dbg_pk, st_cfg_error);
        $display("  info : ALGO fv=%0d g0=%0d yr=%0d yv=%0d gs=%0d hs=%0d yf=%0d",
                 dbg_fv, dbg_g0, dbg_yr, dbg_yv, dbg_gs, dbg_hs, dbg_yf);
        chk("T1 monitor routed to configured mode", m_mode == cfg_mode);
        if (mon_is_raw_exp) begin
            // raw bypass (MODE=0/4): the selected monitor stream is bit-exact RAW
            chk("T1 raw bypass monitor beats", m_beats == exp_beats);
            chk("T1 raw bypass eol count", m_eol_seen == H);
            chk("T1 raw bypass eof count", m_eof_seen == 1);
            chk("T1 raw bypass sof count", m_sof_seen == 1);
        end else begin
            // processed mode (Y8/gaussian/HE): full beat stream, correct frame
            // markers and non-degenerate data.  Pixel-exact Y8 content needs the
            // algorithm model and is a documented coverage gap.
            chk("T1 Y8 monitor beats", m_beats == exp_beats);
            chk("T1 Y8 monitor markers",
                (m_sof_seen == 1) && (m_eol_seen == H) && (m_eof_seen == 1));
            chk("T1 Y8 monitor data non-zero", mon_zero < exp_beats);
        end
        chk("T1 monitor raw/y8 separation", mon_err == 0);
        chk("T1 drain words == ceil(stream/32)",
            drain_n == ((payload_n + 31) / 32));
        check_drain_prefix(payload_n);
        chk("T1 store published", st_store_published == 1);
        chk("T1 exported", st_exported == 1);
        chk("T1 scheduler completed", st_sched_completed == 1);
        if (sample_en) build_and_write_sample;
        else $display("  info : sample emission disabled (SAMPLE=0)");

        if (!extra_en) begin
            repeat (20) @(posedge clk);
            $display("=== SUMMARY ===");
            $display("  admits=%0d commits=%0d aborts=%0d releases=%0d published=%0d exported=%0d",
                     st_admit_count, st_frames_committed, st_frames_aborted,
                     st_release_count, st_store_published, st_exported);
            $display("  sched accepted=%0d completed=%0d failed=%0d rejected=%0d",
                     st_sched_accepted, st_sched_completed, st_sched_failed,
                     st_sched_rejected);
            $display("  cfg_error=%0d store_errors=%0d adapter_err=%0d",
                     st_cfg_error, st_store_errors, st_adapter_err);
            if (errors_total == 0)
                $display("TB_INTEGRATED_DELIVERY_TOP PASS");
            else
                $display("TB_INTEGRATED_DELIVERY_TOP FAIL errors=%0d", errors_total);
            $finish;
        end

        // ============================== T2: A frame under monitor + A+ backpressure
        // F1/F3 scenario: monitor gaps (m_ready low) AND DDR write stalls (which
        // propagate pk_ready low through the A+ core).  The capture must not
        // deadlock, the frame must complete bit-exactly and be committed once.
        dut_reset; scn_begin;
        $display("=== T2: A channel, mode=%0d, monitor gaps + DDR stalls (backpressure) ===", cfg_mode);
        ddr_stall_en = 1'b1; ddr_lat = 5;
        mon_active = 1'b1;
        mon_is_raw_exp = (cfg_mode == 3'd0) || (cfg_mode == 3'd4);
        // same source data as T1 so the compressed stream must be byte-length
        // identical (3965) to the golden sample even under backpressure
        mon_seed = 32'hB000;
        mon_seq = 32'd8;
        present_desc(0, 1'b0, 32'd12, EXP_SESSION, 32'd8);
        wait_grant(0);
        fork
            drive_frame(0, 32'hB000, -1, BEATS-1);
            begin
                repeat (60) @(posedge clk); m_ready = 1'b0;
                repeat (40) @(posedge clk); m_ready = 1'b1;
                repeat (40) @(posedge clk); m_ready = 1'b0;
                repeat (10) @(posedge clk); m_ready = 1'b1;
                repeat (30) @(posedge clk); m_ready = 1'b0;
                repeat (30) @(posedge clk); m_ready = 1'b1;
            end
        join
        wait_commit(400000);
        repeat (4) @(posedge clk);
        chk("T2 commit (no deadlock)", st_frames_committed == 1);
        chk("T2 raw_len == W*H*10/8", st_raw_len == GOLDEN_RAW);
        chk("T2 pk_bytes == raw_len", raw_n == st_raw_len);
        chk("T2 payload == stream_len", payload_n == st_stream_len);
        chk("T2 stream_len == golden (content preserved)", st_stream_len == GOLDEN_STREAM);
        chk("T2 pk beats == 768 (no duplication/loss)", raw_n == GOLDEN_RAW);
        if (mon_is_raw_exp) begin
            chk("T2 raw monitor bit-exact under backpressure", mon_err == 0);
            chk("T2 raw monitor beat count", m_beats == BEATS);
        end else begin
            chk("T2 Y8 monitor beat count under backpressure", m_beats == BEATS);
            chk("T2 Y8 monitor markers",
                (m_sof_seen == 1) && (m_eol_seen == H) && (m_eof_seen == 1));
            chk("T2 Y8 monitor data non-zero", mon_zero < BEATS);
        end
        wait_release(400000);
        chk("T2 release A completed", rel_seen && (rel_status_l == 3'd0) &&
                                      (rel_cam_l == 1'b0) && (rel_seq_l == 32'd8));
        repeat (6) @(posedge clk);
        chk("T2 descriptor armed once", arm_count == 1);
        chk("T2 descriptor identity A", (arm_cam == 1'b0) && (arm_seq == 32'd8));
        chk("T2 no store/adapter errors",
            (st_store_errors == 0) && (st_adapter_err == 0));
        chk("T2 drain words == ceil(stream/32)", drain_n == ((payload_n + 31) / 32));
        check_drain_prefix(payload_n);
        ddr_stall_en = 1'b0; ddr_lat = 3;

        // ============================== T3: abort mid-frame
        dut_reset; scn_begin;
        $display("=== T3: B frame aborted mid-stream ===");
        cfg_prep = 1'b0; cfg_pred = 1'b0;
        mon_active = 1'b0;
        present_desc(1, 1'b0, 32'd13, EXP_SESSION, 32'd9);
        wait_grant(1);
        drive_frame(1, 32'hB100, 120, BEATS-1);
        wait_release(50000);
        chk("T3 failed release after abort", rel_seen && (rel_status_l == 3'd1));
        chk("T3 release identity B/seq9",
            (rel_cam_l == 1'b1) && (rel_seq_l == 32'd9));
        repeat (8) @(posedge clk);
        chk("T3 no descriptor armed for aborted frame", arm_count == 0);
        chk("T3 store dropped the aborted write", st_store_dropped == 1);
        chk("T3 scheduler failed count", st_sched_failed == 1);
        chk("T3 no commit", st_frames_committed == 0);

        // ============================== T4: A disabled + B priority, then A
        dut_reset; scn_begin;
        $display("=== T4: A disabled + B priority, then A enabled ===");
        a_enable = 1'b0; b_priority = 1'b1;
        present_desc(0, 1'b1, 32'd14, EXP_SESSION, 32'd10);
        present_desc(1, 1'b0, 32'd15, EXP_SESSION, 32'd11);
        rel_timeout = 0;
        #1;
        while (!b_desc_ready && (rel_timeout < 20000)) begin
            @(negedge clk);
            #1;
            rel_timeout = rel_timeout + 1;
        end
        chk("T4 B granted while A disabled", b_desc_ready);
        if (!b_desc_ready) $display("T4DBG b_can=%b out_stall=%b a_can=%b a_en=%b b_busy=%b o_valid=%b o_ready=%b",
            dut.u_sched.b_can, dut.u_sched.out_stall, dut.u_sched.a_can, a_enable,
            dut.u_sched.b_busy, dut.u_sched.o_valid, dut.sched_o_ready);
        chk("T4 A not granted while disabled", a_desc_ready == 1'b0);
        @(posedge clk);
        @(negedge clk);
        b_desc_valid = 1'b0;
        repeat (50) @(negedge clk);
        chk("T4 A still not granted (gated)", a_desc_ready == 1'b0);
        mon_active = 1'b0;
        drive_frame(1, 32'hB200, -1, BEATS-1);
        wait_release(200000);
        chk("T4 B release completed", rel_seen && (rel_status_l == 3'd0) &&
                                      (rel_cam_l == 1'b1));
        repeat (10) @(posedge clk);
        chk("T4 A descriptor still pending", a_desc_valid == 1'b1);
        a_enable = 1'b1;
        #1;
        rel_timeout = 0;
        while (!a_desc_ready && (rel_timeout < 20000)) begin
            @(negedge clk);
            #1;
            rel_timeout = rel_timeout + 1;
        end
        chk("T4 A granted after enable", a_desc_ready);
        @(posedge clk);
        @(negedge clk);
        a_desc_valid = 1'b0;
        scn_begin;
        drive_frame(0, 32'hA300, -1, BEATS-1);
        wait_release(200000);
        chk("T4 A release completed", rel_seen && (rel_status_l == 3'd0) &&
                                      (rel_cam_l == 1'b0) && (rel_seq_l == 32'd10));
        chk("T4 both channels completed", st_sched_completed == 2);

        // ============================== T5: wrong ACK then correct ACK
        dut_reset; scn_begin;
        $display("=== T5: wrong ACK is rejected, correct ACK releases ===");
        ack_bad_en  = 1'b1;
        ack_bad_cnt = 0;
        ack_delay   = 40;
        mon_active = 1'b0;
        present_desc(1, 1'b1, 32'd16, EXP_SESSION, 32'd12);
        wait_grant(1);
        drive_frame(1, 32'hB400, -1, BEATS-1);
        wait_commit(200000);
        rel_timeout = 0;
        while ((ack_bad_cnt == 0) && (rel_timeout < 50000)) begin
            @(posedge clk);
            rel_timeout = rel_timeout + 1;
        end
        chk("T5 bad ACK issued", ack_bad_cnt != 0);
        repeat (10) @(posedge clk);
        chk("T5 bad ACK does not release", rel_seen == 1'b0);
        chk("T5 adapter error counted", st_adapter_err >= 1);
        ack_bad_en = 1'b0;
        wait_release(200000);
        chk("T5 good ACK releases", rel_seen && (rel_status_l == 3'd0));

        // ============================== T6: truncated frame must not be committed
        // F1 second half: a source that signals EOF early (truncated/corrupt
        // frame) must never be published, armed or exported as a good frame.
        dut_reset; scn_begin;
        $display("=== T6: truncated frame (early EOF) must not be committed/exported ===");
        mon_active = 1'b0;
        present_desc(1, 1'b0, 32'd17, EXP_SESSION, 32'd13);
        wait_grant(1);
        drive_frame(1, 32'hB600, -1, 700);   // EOF on beat 700 of 768
        wait_release(300000);
        chk("T6 incomplete frame released as failed", rel_seen && (rel_status_l == 3'd1));
        repeat (8) @(posedge clk);
        chk("T6 no descriptor armed", arm_count == 0);
        chk("T6 not published", st_store_published == 0);
        chk("T6 not exported", st_exported == 0);
        chk("T6 store dropped the partial write", st_store_dropped == 1);
        chk("T6 frames_aborted == 1", st_frames_aborted == 1);
        chk("T6 no commit", st_frames_committed == 0);

        repeat (20) @(posedge clk);

        // ---------------- summary ----------------
        $display("=== SUMMARY ===");
        $display("  admits=%0d commits=%0d aborts=%0d releases=%0d published=%0d exported=%0d",
                 st_admit_count, st_frames_committed, st_frames_aborted,
                 st_release_count, st_store_published, st_exported);
        $display("  sched accepted=%0d completed=%0d failed=%0d rejected=%0d",
                 st_sched_accepted, st_sched_completed, st_sched_failed,
                 st_sched_rejected);
        $display("  cfg_error=%0d store_errors=%0d adapter_err=%0d",
                 st_cfg_error, st_store_errors, st_adapter_err);
        if (errors_total == 0)
            $display("TB_INTEGRATED_DELIVERY_TOP PASS");
        else
            $display("TB_INTEGRATED_DELIVERY_TOP FAIL errors=%0d", errors_total);
        $finish;
    end

    // global watchdog
    initial begin
        #2_000_000; // 2 ms wall-clock guard
        $display("TB_INTEGRATED_DELIVERY_TOP TIMEOUT state=%0d", st_glue_state);
        $display("ADMIT free=%b hasrdy=%b egr=%b drain=%b apbusy=%b wrst=%b dirty=%b ovld=%b",
                 dut.store_free_valid, dut.store_has_ready, dut.egress_busy,
                 dut.drain_busy, dut.ap_st_busy, dut.wr_started, dut.cfg_dirty,
                 dut.sched_o_valid);
        $display("       gs=%0d dr=%0d drainreq=%b slot_st=%b a_rdy=%b b_rdy=%b a_en=%b",
                 dut.gs, dut.dr, dut.drain_req, dut.store_slot_st,
                 a_desc_ready, b_desc_ready, a_enable);
        $display("       storepub=%0d export=%0d release=%0d schedacc=%0d adm=%0d",
                 st_store_published, st_exported, st_release_count,
                 st_sched_accepted, st_admit_count);
        $display("       AP ist=%0d dst=%0d act=%b bank=%b cbusy=%b cirdy=%b svld=%b slast=%b",
                 dut.u_aplus.istate, dut.u_aplus.dstate, dut.u_aplus.frame_active,
                 dut.u_aplus.bank_busy, dut.u_aplus.core_busy,
                 dut.u_aplus.core_in_ready, dut.u_aplus.svalid, dut.u_aplus.slast);
        $display("       ST act=%b wcnt=%0d nby=%0d wrrdy=%b coutv=%b coutrdy=%b",
                 dut.u_store.wr_active, dut.u_store.wcnt, dut.u_store.nbytes,
                 dut.store_wr_ready, dut.core_out_valid, dut.core_out_ready);
        $display("       DDR awv=%b awr=%b wv=%b wr=%b arv=%b arr=%b rv=%b stall=%b",
                 ddr_awvalid, ddr_awready, ddr_wvalid, ddr_wready,
                 ddr_arvalid, ddr_arready, ddr_rvalid, ddr_stall_w);
        $display("       FRAME raw=%0d strm=%0d commits=%0d aborts=%0d blk=%0d grp=%0d row=%0d dblk=%0d cdone=%b",
                 st_raw_len, st_stream_len, st_frames_committed, st_frames_aborted,
                 dut.u_aplus.blk_idx, dut.u_aplus.grp_in_row, dut.u_aplus.row_in_blk,
                 dut.u_aplus.dblk, dut.u_aplus.core_done);
        $display("       TB p1_rdy=%b pk_rdy=%b capv=%b a_rdy=%b b_rdy=%b",
                 dut.p1_s_ready, dut.p1_pk_ready, dut.cap_valid, a_s_ready, b_s_ready);
        $display("TB_INTEGRATED_DELIVERY_TOP FAIL errors=%0d", errors_total + 1);
        $finish;
    end

endmodule
