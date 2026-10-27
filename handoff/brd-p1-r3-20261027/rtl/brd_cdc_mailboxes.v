`timescale 1ns/1ps
// =============================================================================
// brd_cdc_mailboxes.v -- T11.BRD.P1 clock-domain crossing primitives (guide 4.1)
//
// C4  brd_desc_xing  : clk_core    -> tl_clk_user  descriptor mailbox
// C5  brd_ack_xing   : tl_clk_user -> clk_core     host ACK / CANCEL
// C6  brd_pcie_track : tl_clk_user -> clk_core     pusher status (done/err/held)
// C6b brd_pcie_track : clk_core    -> tl_clk_user  P4 status snapshot (0x130..13C)
// C7  brd_cfg_xing   : tl_clk_user -> clk_core     BAR static config shadow
//
// Every channel uses the same frozen structure:
//   * the multi-bit payload is held STABLE from before the request toggle until
//     the destination has acknowledged it (4-phase handshake),
//   * the request crosses as ONE toggle bit through two flip-flops,
//   * the destination samples the whole stable bundle on the synchronised edge,
//   * the acknowledge crosses back as one toggle bit through two flip-flops.
// No multi-bit bus is ever sampled while it can change, and no runtime clock
// mux is created.  This is the only allowed crossing style in guide 4.1.
// =============================================================================

// ---------------------------------------------------------------------------
// Generic 4-phase stable-payload crossing.
//   wstart : one-cycle strobe in the source domain; ignored while !wfree.
//   wfree  : 1 when the destination has consumed the previous transfer.
//   rvalid : one-cycle strobe in the destination domain with rdata already
//            registered (rdata is valid from that edge on).
// ---------------------------------------------------------------------------
module brd_xing_bits #(
    parameter integer W = 32
) (
    input  wire          wclk,
    input  wire          wrst_n,
    input  wire [W-1:0]  wdata,
    input  wire          wstart,
    output wire          wfree,

    input  wire          rclk,
    input  wire          rrst_n,
    output reg  [W-1:0]  rdata,
    output reg           rvalid
);
    // ---- source side ----
    reg          wreq;
    reg  [W-1:0] whold;
    (* async_reg = "true" *) reg [1:0] wack_s;
    // declare the back-channel toggle up front: it is used by the source
    // always block below (Verilog needs the declaration to precede the use)
    reg          rack;

    assign wfree = (wack_s[1] == wreq);

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wreq   <= 1'b0;
            whold  <= {W{1'b0}};
            wack_s <= 2'b00;
        end else begin
            wack_s <= {wack_s[0], rack};
            if (wstart && wfree) begin
                wreq  <= ~wreq;
                whold <= wdata;
            end
        end
    end

    // ---- destination side ----
    (* async_reg = "true" *) reg [1:0] rreq_s;
    reg          rseen;

    wire rnew = (rreq_s[1] ^ rseen);

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rreq_s  <= 2'b00;
            rseen   <= 1'b0;
            rack    <= 1'b0;
            rdata   <= {W{1'b0}};
            rvalid  <= 1'b0;
        end else begin
            rreq_s <= {rreq_s[0], wreq};
            rvalid <= 1'b0;
            if (rnew) begin
                // whold has been stable since before the synchronised toggle
                rdata  <= whold;
                rseen  <= rreq_s[1];
                rack   <= rreq_s[1];
                rvalid <= 1'b1;
            end
        end
    end
endmodule

// ---------------------------------------------------------------------------
// C4: P4 descriptor -> pusher (clk_core -> tl_clk_user)
// ---------------------------------------------------------------------------
module brd_desc_xing (
    input  wire         clk_core,
    input  wire         rst_core_n,
    input  wire         desc_arm,          // pulse from aplus_pcie_egress_adapter
    input  wire [31:0]  desc_cap_bytes,
    input  wire [31:0]  desc_session_id,
    input  wire [63:0]  desc_dst_base,
    input  wire [63:0]  desc_db_addr,
    input  wire [31:0]  desc_frame_bytes,
    input  wire [31:0]  desc_stream_len,
    input  wire [31:0]  desc_slot_base_word,
    input  wire         desc_src_sel,
    input  wire         desc_cam_sel,
    input  wire         desc_ident_valid,
    input  wire         desc_camera_id,
    input  wire         desc_slot_id,
    input  wire [31:0]  desc_epoch,
    input  wire [31:0]  desc_capture_seq,

    input  wire         tl_clk,
    input  wire         tl_rst_n,
    output reg          o_arm,             // one tl cycle strobe
    output reg  [31:0]  o_cap_bytes,
    output reg  [31:0]  o_session_id,
    output reg  [63:0]  o_dst_base,
    output reg  [63:0]  o_db_addr,
    output reg  [31:0]  o_frame_bytes,
    output reg  [31:0]  o_stream_len,
    output reg  [31:0]  o_slot_base_word,
    output reg          o_src_sel,
    output reg          o_cam_sel,
    output reg          o_ident_valid,
    output reg          o_camera_id,
    output reg          o_slot_id,
    output reg  [31:0]  o_epoch,
    output reg  [31:0]  o_capture_seq
);
    localparam integer W = 358;

    reg  [W-1:0] hold;
    reg          arm_d;
    reg          start;
    wire         free;
    wire [W-1:0] in_bus;
    wire [W-1:0] out_bus;
    wire         valid;

    assign in_bus = {desc_arm,
                     desc_cap_bytes, desc_session_id, desc_dst_base, desc_db_addr,
                     desc_frame_bytes, desc_stream_len, desc_slot_base_word,
                     desc_src_sel, desc_cam_sel,
                     desc_ident_valid, desc_camera_id, desc_slot_id,
                     desc_epoch, desc_capture_seq};

    wire arm_rise = desc_arm & ~arm_d;

    always @(posedge clk_core or negedge rst_core_n) begin
        if (!rst_core_n) begin
            arm_d <= 1'b0;
            start <= 1'b0;
            hold  <= {W{1'b0}};
        end else begin
            arm_d <= desc_arm;
            start <= 1'b0;
            if (arm_rise && free) begin
                hold  <= in_bus;
                start <= 1'b1;
            end
        end
    end

    brd_xing_bits #(.W(W)) u_x (
        .wclk(clk_core), .wrst_n(rst_core_n), .wdata(hold), .wstart(start), .wfree(free),
        .rclk(tl_clk),   .rrst_n(tl_rst_n),   .rdata(out_bus), .rvalid(valid)
    );

    always @(posedge tl_clk or negedge tl_rst_n) begin
        if (!tl_rst_n) begin
            o_arm <= 1'b0;
            o_cap_bytes <= 32'd0; o_session_id <= 32'd0;
            o_dst_base <= 64'd0;  o_db_addr <= 64'd0;
            o_frame_bytes <= 32'd0; o_stream_len <= 32'd0;
            o_slot_base_word <= 32'd0;
            o_src_sel <= 1'b0; o_cam_sel <= 1'b0;
            o_ident_valid <= 1'b0; o_camera_id <= 1'b0; o_slot_id <= 1'b0;
            o_epoch <= 32'd0; o_capture_seq <= 32'd0;
        end else begin
            o_arm <= valid;
            if (valid) begin
                o_capture_seq    <= out_bus[31:0];
                o_epoch          <= out_bus[63:32];
                o_slot_id        <= out_bus[64];
                o_camera_id      <= out_bus[65];
                o_ident_valid    <= out_bus[66];
                o_cam_sel        <= out_bus[67];
                o_src_sel        <= out_bus[68];
                o_slot_base_word <= out_bus[100:69];
                o_stream_len     <= out_bus[132:101];
                o_frame_bytes    <= out_bus[164:133];
                o_db_addr        <= out_bus[228:165];
                o_dst_base       <= out_bus[292:229];
                o_session_id     <= out_bus[324:293];
                o_cap_bytes      <= out_bus[356:325];
                // out_bus[357] = arm request bit (unused downstream)
            end
        end
    end
endmodule

// ---------------------------------------------------------------------------
// C5: host ACK / CANCEL (tl_clk_user -> clk_core)
// ---------------------------------------------------------------------------
module brd_ack_xing (
    input  wire         tl_clk,
    input  wire         tl_rst_n,
    input  wire         ack_pulse,
    input  wire         cancel_pulse,
    input  wire [31:0]  ack_seq,
    input  wire [31:0]  ack_session,

    input  wire         clk_core,
    input  wire         rst_core_n,
    output reg          o_ack,
    output reg          o_cancel,
    output reg  [31:0]  o_ack_seq,
    output reg  [31:0]  o_ack_session
);
    localparam integer W = 65;

    reg          start;
    wire         free;
    wire [W-1:0] in_bus;
    wire [W-1:0] out_bus;
    wire         valid;

    assign in_bus = {cancel_pulse, ack_seq, ack_session};

    always @(posedge tl_clk or negedge tl_rst_n) begin
        if (!tl_rst_n)      start <= 1'b0;
        else                start <= (ack_pulse | cancel_pulse) & free;
    end

    brd_xing_bits #(.W(W)) u_x (
        .wclk(tl_clk), .wrst_n(tl_rst_n), .wdata(in_bus), .wstart(start), .wfree(free),
        .rclk(clk_core), .rrst_n(rst_core_n), .rdata(out_bus), .rvalid(valid)
    );

    always @(posedge clk_core or negedge rst_core_n) begin
        if (!rst_core_n) begin
            o_ack <= 1'b0; o_cancel <= 1'b0;
            o_ack_seq <= 32'd0; o_ack_session <= 32'd0;
        end else begin
            o_ack    <= 1'b0;
            o_cancel <= 1'b0;
            if (valid) begin
                // r3 (T11 r0d ACK-slice fix): in_bus = {cancel, ack_seq, ack_session},
                // so the LSB half carries ack_session and bits [63:32] carry ack_seq.
                // The r2 read side had the halves swapped; the egress then compared
                // ack_seq(=session) against held_seq and rejected every ACK.
                o_ack_seq     <= out_bus[63:32];
                o_ack_session <= out_bus[31:0];
                o_cancel      <= out_bus[64];
                o_ack         <= ~out_bus[64];
            end
        end
    end
endmodule

// ---------------------------------------------------------------------------
// C6: pusher status tl_clk_user -> clk_core, plus C6b P4 status snapshot back
// ---------------------------------------------------------------------------
module brd_pcie_track (
    // pusher / tracker side (tl_clk_user)
    input  wire         tl_clk,
    input  wire         tl_rst_n,
    input  wire [31:0]  i_done,
    input  wire [31:0]  i_status,
    input  wire [7:0]   i_err,
    input  wire [31:0]  i_tlp_cnt,
    input  wire         i_held,
    input  wire         i_busy,
    input  wire         i_block_cfg,
    input  wire         i_link_up,
    input  wire [31:0]  i_arm_seq,
    input  wire [31:0]  i_arm_sess,

    // P4 side (clk_core)
    input  wire         clk_core,
    input  wire         rst_core_n,
    output reg          o_pcie_done,
    output reg          o_pcie_held,
    output reg          o_pcie_err,
    output reg          o_pcie_busy,
    output reg  [31:0]  o_pcie_held_seq,
    output reg  [31:0]  o_pcie_held_sess,
    output reg  [31:0]  o_tx_done,
    output reg  [31:0]  o_tx_status,
    output reg  [7:0]   o_tx_err,
    output reg  [31:0]  o_tx_tlp,
    output reg          o_link_up,
    output reg          o_block_cfg,

    // C6b: P4 status snapshot clk_core -> tl_clk_user (BAR 0x130..0x13C)
    input  wire [31:0]  i_p4_st0,
    input  wire [31:0]  i_p4_st1,
    input  wire [31:0]  i_p4_st2,
    input  wire [31:0]  i_p4_st3,
    output reg  [127:0] o_p4_st
);
    localparam integer W1 = 108;   // tl -> core
    localparam integer W2 = 128;   // core -> tl

    // ---------------- C6 forward ----------------
    reg  [W1-1:0] f_hold, f_prev;
    reg           f_start;
    wire          f_free;
    wire [W1-1:0] f_out;
    wire          f_valid;

    wire [W1-1:0] f_bus = {i_block_cfg, i_busy, i_held, i_tlp_cnt, i_err, i_status, i_done};

    wire f_go = (f_bus != f_prev) & f_free;

    always @(posedge tl_clk or negedge tl_rst_n) begin
        if (!tl_rst_n) begin
            f_hold <= {W1{1'b0}};
            f_prev <= {W1{1'b0}};
            f_start <= 1'b0;
        end else begin
            f_start <= f_go;
            f_hold  <= f_go ? f_bus : f_hold;
            f_prev  <= f_go ? f_bus : f_prev;
        end
    end

    brd_xing_bits #(.W(W1)) u_fwd (
        .wclk(tl_clk), .wrst_n(tl_rst_n), .wdata(f_hold), .wstart(f_start), .wfree(f_free),
        .rclk(clk_core), .rrst_n(rst_core_n), .rdata(f_out), .rvalid(f_valid)
    );

    reg [31:0] r_done_d;
    reg [7:0]  r_err_d;

    always @(posedge clk_core or negedge rst_core_n) begin
        if (!rst_core_n) begin
            o_pcie_done <= 1'b0;
            o_pcie_held <= 1'b0;
            o_pcie_err  <= 1'b0;
            o_pcie_busy <= 1'b0;
            o_pcie_held_seq  <= 32'd0;
            o_pcie_held_sess <= 32'd0;
            o_tx_done <= 32'd0; o_tx_status <= 32'd0;
            o_tx_err <= 8'd0;   o_tx_tlp <= 32'd0;
            o_link_up <= 1'b0;  o_block_cfg <= 1'b0;
            r_done_d <= 32'd0;
            r_err_d  <= 8'd0;
        end else begin
            o_pcie_done <= f_valid && (f_out[31:0] != r_done_d);
            if (f_valid) begin
                o_tx_done   <= f_out[31:0];
                o_tx_status <= f_out[63:32];
                o_tx_err    <= f_out[71:64];
                o_tx_tlp    <= f_out[103:72];
                o_pcie_held <= f_out[104];
                o_pcie_busy <= f_out[105];
                o_block_cfg <= f_out[106];
                r_done_d    <= f_out[31:0];
                r_err_d     <= f_out[71:64];
            end
            // r1: a NEW pusher error is a one-cycle pulse, not a sticky level.
            // A rejected ACK or a single refused ARM must not abort a later
            // frame in the P4 egress adapter.
            o_pcie_err <= f_valid && (f_out[71:64] != r_err_d) && (f_out[71:64] != 8'd0);
            // identity of the frame the pusher currently owns (set at arm time in
            // tl domain, but stable for the whole frame, so a plain sample of the
            // already-synchronised copy is enough)
            o_pcie_held_seq  <= i_arm_seq;
            o_pcie_held_sess <= i_arm_sess;
            o_link_up        <= i_link_up;
        end
    end

    // ---------------- C6b status snapshot back ----------------
    reg  [W2-1:0] b_hold, b_prev;
    reg           b_start;
    wire          b_free;
    wire [W2-1:0] b_out;
    wire          b_valid;

    wire [W2-1:0] b_bus = {i_p4_st3, i_p4_st2, i_p4_st1, i_p4_st0};

    wire b_go = (b_bus != b_prev) & b_free;

    always @(posedge clk_core or negedge rst_core_n) begin
        if (!rst_core_n) begin
            b_hold  <= {W2{1'b0}};
            b_prev  <= {W2{1'b0}};
            b_start <= 1'b0;
        end else begin
            b_start <= b_go;
            b_hold  <= b_go ? b_bus : b_hold;
            b_prev  <= b_go ? b_bus : b_prev;
        end
    end

    brd_xing_bits #(.W(W2)) u_back (
        .wclk(clk_core), .wrst_n(rst_core_n), .wdata(b_hold), .wstart(b_start), .wfree(b_free),
        .rclk(tl_clk), .rrst_n(tl_rst_n), .rdata(b_out), .rvalid(b_valid)
    );

    always @(posedge tl_clk or negedge tl_rst_n) begin
        if (!tl_rst_n) o_p4_st <= 128'd0;
        else if (b_valid) o_p4_st <= b_out;
    end
endmodule

// ---------------------------------------------------------------------------
// C7: BAR static configuration shadow (tl_clk_user -> clk_core)
// ---------------------------------------------------------------------------
module brd_cfg_xing (
    input  wire         tl_clk,
    input  wire         tl_rst_n,
    input  wire [31:0]  i_cap_bytes,
    input  wire [31:0]  i_session_id,
    input  wire [31:0]  i_dst_lo,
    input  wire [31:0]  i_dst_hi,
    input  wire [31:0]  i_db_lo,
    input  wire [31:0]  i_db_hi,
    input  wire         i_push_en,
    input  wire         i_a_enable,
    input  wire         i_trigger_mode,
    input  wire         i_p4_desc_owner,
    input  wire [2:0]   i_cfg_mode,
    input  wire         i_prep,
    input  wire         i_pred,
    input  wire [1:0]   i_phase,

    input  wire         clk_core,
    input  wire         rst_core_n,
    output reg  [31:0]  o_cap_bytes,
    output reg  [31:0]  o_session_id,
    output reg  [63:0]  o_dst_base,
    output reg  [63:0]  o_db_addr,
    output reg          o_push_en,
    output reg          o_a_enable,
    output reg          o_trigger_mode,
    output reg          o_p4_desc_owner,
    output reg  [2:0]   o_cfg_mode,
    output reg          o_prep,
    output reg          o_pred,
    output reg  [1:0]   o_phase
);
    localparam integer W = 203;

    reg  [W-1:0] hold, prev;
    reg          start;
    wire         free;
    wire [W-1:0] in_bus;
    wire [W-1:0] out_bus;
    wire         valid;

    assign in_bus = {i_cap_bytes, i_session_id, i_dst_lo, i_dst_hi, i_db_lo, i_db_hi,
                     i_push_en, i_a_enable, i_trigger_mode, i_p4_desc_owner,
                     i_cfg_mode, i_prep, i_pred, i_phase};

    wire c_go = (in_bus != prev) & free;

    always @(posedge tl_clk or negedge tl_rst_n) begin
        if (!tl_rst_n) begin
            hold  <= {W{1'b0}};
            prev  <= {W{1'b0}};
            start <= 1'b0;
        end else begin
            start <= c_go;
            hold  <= c_go ? in_bus : hold;
            prev  <= c_go ? in_bus : prev;
        end
    end

    brd_xing_bits #(.W(W)) u_x (
        .wclk(tl_clk), .wrst_n(tl_rst_n), .wdata(hold), .wstart(start), .wfree(free),
        .rclk(clk_core), .rrst_n(rst_core_n), .rdata(out_bus), .rvalid(valid)
    );

    always @(posedge clk_core or negedge rst_core_n) begin
        if (!rst_core_n) begin
            o_cap_bytes <= 32'd0; o_session_id <= 32'd0;
            o_dst_base <= 64'd0;  o_db_addr <= 64'd0;
            o_push_en <= 1'b0;    o_a_enable <= 1'b0;
            o_trigger_mode <= 1'b0; o_p4_desc_owner <= 1'b1;
            o_cfg_mode <= 3'd0;   o_prep <= 1'b1; o_pred <= 1'b1; o_phase <= 2'd0;
        end else if (valid) begin
            o_phase          <= out_bus[1:0];
            o_pred           <= out_bus[2];
            o_prep           <= out_bus[3];
            o_cfg_mode       <= out_bus[6:4];
            o_p4_desc_owner  <= out_bus[7];
            o_trigger_mode   <= out_bus[8];
            o_a_enable       <= out_bus[9];
            o_push_en        <= out_bus[10];
            o_db_addr        <= out_bus[74:11];
            o_dst_base       <= out_bus[138:75];
            o_session_id     <= out_bus[170:139];
            o_cap_bytes      <= out_bus[202:171];
        end
    end
endmodule
