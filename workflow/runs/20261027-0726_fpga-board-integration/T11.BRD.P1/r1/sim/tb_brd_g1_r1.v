`timescale 1ns/1ps
// =============================================================================
// tb_brd_g1_r1.v -- T11.BRD.P1 r1 scaled top-level G1 simulation
//
// Modules:
//   brd_ddr_slave_model : byte-addressed 256-bit AXI4 DDR slave model
//   tb_brd_arb          : DDR read-arbiter negatives (6 checks, unchanged)
//   tb_brd_g1_top       : scaled board datapath + camera + DDR + TLP host + BAR
//
// Scenarios (+SCEN=):
//   0 full frame, host ARM *after* P4 publish            (positive, late ARM)
//   1 truncated frame (last ROI row absent)              (negative: no EOF)
//   2 wrong ACK then correct ACK                         (negative + release)
//   3 full frame, host ARM *before* the frame, doubled    (positive, early ARM)
//   4 full frame, duplicate ARM while armed/held          (negative + positive)
//
// +PREP/+PRED select the A+ transform.  bypass (0/0) makes xform == the packed
// RAW10 A+ input byte stream, so the host reference is exact.
//
// The A1U1 44B header is built HERE by the testbench host model (D6 contract);
// the DUT only stores the zlib bytes.  The header and payload are written to
// a1u1_frame.bin for the independent Python verifier.
// =============================================================================

// ---------------------------------------------------------------------------
// DDR3 AXI4 slave model (byte addressed, 256 bit, single write beat, INCR read)
// ---------------------------------------------------------------------------
module brd_ddr_slave_model #(
    parameter integer DWORDS = 8192,
    parameter integer DWORDS_LOG = 13
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [28:0]  awaddr,
    input  wire [255:0] wdata,
    input  wire [31:0]  wstrb,
    input  wire         awvalid,
    input  wire         wvalid,
    input  wire         wlast,
    output reg          awready,
    output reg          wready,
    input  wire         bready,
    output reg          bvalid,
    input  wire [3:0]   arid,
    input  wire [28:0]  araddr,
    input  wire [7:0]   arlen,
    input  wire [2:0]   arsize,
    input  wire [1:0]   arburst,
    input  wire         arvalid,
    output reg          arready,
    output reg  [3:0]   rid,
    output reg  [255:0] rdata,
    output reg  [1:0]   rresp,
    output reg          rlast,
    output reg          rvalid,
    input  wire         rready,
    output reg  [31:0]  wr_beats,
    output reg  [31:0]  rd_bursts,
    output reg  [31:0]  rd_beats
);
    reg [255:0] mem [0:DWORDS-1];

    integer i;
    initial begin
        for (i = 0; i < DWORDS; i = i + 1) mem[i] = 256'd0;
        awready = 1'b0; wready = 1'b0; bvalid = 1'b0;
        arready = 1'b0; rvalid = 1'b0; rlast = 1'b0; rdata = 256'd0; rresp = 2'b00;
        rid = 4'd0; wr_beats = 32'd0; rd_bursts = 32'd0; rd_beats = 32'd0;
    end

    reg        aw_pending;
    reg [28:0] aw_addr_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awready <= 1'b0; wready <= 1'b0; bvalid <= 1'b0;
            aw_pending <= 1'b0; aw_addr_q <= 29'd0; wr_beats <= 32'd0;
        end else begin
            awready <= 1'b0;
            wready  <= 1'b0;
            if (awvalid && !aw_pending && !bvalid) begin
                awready    <= 1'b1;
                aw_pending <= 1'b1;
                aw_addr_q  <= awaddr;
            end
            if (aw_pending && wvalid) begin
                wready <= 1'b1;
                mem[aw_addr_q[DWORDS_LOG+4:5]] <= wdata;
                aw_pending <= 1'b0;
                wr_beats   <= wr_beats + 32'd1;
            end
            if (wvalid && wready) bvalid <= 1'b1;
            else if (bvalid && bready) bvalid <= 1'b0;
        end
    end

    reg [28:0] rd_addr_q;
    reg [7:0]  rd_left;
    reg        rd_busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arready <= 1'b0; rvalid <= 1'b0; rlast <= 1'b0;
            rdata <= 256'd0; rresp <= 2'b00; rid <= 4'd0;
            rd_busy <= 1'b0; rd_addr_q <= 29'd0; rd_left <= 8'd0;
            rd_bursts <= 32'd0; rd_beats <= 32'd0;
        end else begin
            arready <= 1'b0;
            if (arvalid && !rd_busy) begin
                arready   <= 1'b1;
                rd_busy   <= 1'b1;
                rd_addr_q <= araddr;
                rd_left   <= arlen;
                rid       <= arid;
                rd_bursts <= rd_bursts + 32'd1;
            end else if (rd_busy) begin
                if (!rvalid || rready) begin
                    rvalid <= 1'b1;
                    rdata  <= mem[rd_addr_q[DWORDS_LOG+4:5]];
                    rlast  <= (rd_left == 8'd0);
                    rd_addr_q <= rd_addr_q + 29'd32;
                    rd_beats  <= rd_beats + 32'd1;
                    if (rd_left == 8'd0) rd_busy <= 1'b0;
                    else                 rd_left <= rd_left - 8'd1;
                end
            end else begin
                rvalid <= 1'b0;
                rlast  <= 1'b0;
            end
        end
    end
endmodule

// ---------------------------------------------------------------------------
// arbiter test: mid-burst switch request + orphan beat (same 6 checks as r0)
// ---------------------------------------------------------------------------
module tb_brd_arb;
    localparam integer DWORDS = 64;
    localparam integer DWORDS_LOG = 6;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg  [28:0] b_araddr = 29'd0;
    reg         b_arvalid = 1'b0;
    wire        b_arready;
    wire [255:0] b_rdata;
    wire        b_rlast, b_rvalid;
    reg         b_rready = 1'b1;

    reg  [3:0]  p_arid = 4'h2;
    reg  [28:0] p_araddr = 29'd0;
    reg  [7:0]  p_arlen = 8'd3;
    reg  [2:0]  p_arsize = 3'd5;
    reg  [1:0]  p_arburst = 2'b01;
    reg         p_arvalid = 1'b0;
    wire        p_arready;
    wire [3:0]  p_rid;
    wire [255:0] p_rdata;
    wire [1:0]  p_rresp;
    wire        p_rlast, p_rvalid;
    reg         p_rready = 1'b1;

    wire [3:0]  m_arid;
    wire [28:0] m_araddr;
    wire [7:0]  m_arlen;
    wire [2:0]  m_arsize;
    wire [1:0]  m_arburst;
    wire        m_arvalid, m_arready;
    wire [3:0]  m_rid;
    wire [255:0] m_rdata;
    wire [1:0]  m_rresp;
    wire        m_rlast, m_rvalid, m_rready;

    wire        o_owner, o_busy;
    wire [31:0] o_late, o_switch, o_bx, o_px;

    brd_ddr_rd_arb u_arb (
        .clk(clk), .rst_n(rst_n),
        .b_araddr(b_araddr), .b_arvalid(b_arvalid), .b_arready(b_arready),
        .b_rdata(b_rdata), .b_rresp(), .b_rlast(b_rlast), .b_rvalid(b_rvalid), .b_rready(b_rready),
        .p_arid(p_arid), .p_araddr(p_araddr), .p_arlen(p_arlen), .p_arsize(p_arsize),
        .p_arburst(p_arburst), .p_arvalid(p_arvalid), .p_arready(p_arready),
        .p_rid(p_rid), .p_rdata(p_rdata), .p_rresp(p_rresp), .p_rlast(p_rlast),
        .p_rvalid(p_rvalid), .p_rready(p_rready),
        .m_arid(m_arid), .m_araddr(m_araddr), .m_arlen(m_arlen), .m_arsize(m_arsize),
        .m_arburst(m_arburst), .m_arvalid(m_arvalid), .m_arready(m_arready),
        .m_rid(m_rid), .m_rdata(m_rdata), .m_rresp(m_rresp), .m_rlast(m_rlast),
        .m_rvalid(m_rvalid), .m_rready(m_rready),
        .o_owner(o_owner), .o_busy(o_busy), .o_late_cnt(o_late), .o_switch_err(o_switch),
        .o_b_xacts(o_bx), .o_p_xacts(o_px)
    );

    brd_ddr_slave_model #(.DWORDS(DWORDS), .DWORDS_LOG(DWORDS_LOG)) u_mem (
        .clk(clk), .rst_n(rst_n),
        .awaddr(29'd0), .wdata(256'd0), .wstrb(32'd0), .awvalid(1'b0), .wvalid(1'b0),
        .wlast(1'b0), .awready(), .wready(), .bready(1'b1), .bvalid(),
        .arid(m_arid), .araddr(m_araddr), .arlen(m_arlen), .arsize(m_arsize),
        .arburst(m_arburst), .arvalid(m_arvalid), .arready(m_arready),
        .rid(m_rid), .rdata(m_rdata), .rresp(m_rresp), .rlast(m_rlast),
        .rvalid(m_rvalid), .rready(m_rready),
        .wr_beats(), .rd_bursts(), .rd_beats()
    );

    integer errors = 0;
    integer b_grant_inside_burst = 0;
    integer transferred_to_b = 0;

    always @(posedge clk) begin
        if (o_busy && o_owner == 1'b1 && b_arready) b_grant_inside_burst = b_grant_inside_burst + 1;
        if (o_busy && o_owner == 1'b0 && p_arready) b_grant_inside_burst = b_grant_inside_burst + 1;
        if (b_rvalid) transferred_to_b = transferred_to_b + 1;
    end

    initial begin
        repeat (8) @(posedge clk);
        rst_n = 1;
        repeat (4) @(posedge clk);

        p_araddr  = 29'd128;
        p_arlen   = 8'd3;
        p_arvalid = 1'b1;
        @(posedge clk);
        while (!p_arready) @(posedge clk);
        p_arvalid = 1'b0;

        @(posedge clk);
        b_araddr  = 29'd64;
        b_arvalid = 1'b1;

        while (o_busy) @(posedge clk);
        @(posedge clk);
        b_arvalid = 1'b0;
        repeat (6) @(posedge clk);

        if (b_grant_inside_burst != 0) begin
            $display("FAIL arb: %0d grant(s) inside a burst", b_grant_inside_burst);
            errors = errors + 1;
        end else $display("PASS arb: no grant changed owner inside a burst");
        if (transferred_to_b != 1) begin
            $display("FAIL arb: bridge received %0d beats (expected 1)", transferred_to_b);
            errors = errors + 1;
        end else $display("PASS arb: bridge got exactly its single beat");
        if (o_bx != 32'd1) begin
            $display("FAIL arb: o_b_xacts=%0d (expected 1)", o_bx); errors = errors + 1;
        end else $display("PASS arb: one bridge transaction completed");
        if (o_switch != 32'd0) begin
            $display("FAIL arb: o_switch_err=%0d", o_switch); errors = errors + 1;
        end else $display("PASS arb: o_switch_err=0");

        force m_rvalid = 1'b1;
        force m_rdata  = 256'hDEAD_BEEF_DEAD_BEEF_DEAD_BEEF_DEAD_BEEF_DEAD_BEEF_DEAD_BEEF_DEAD_BEEF_DEAD_BEEF;
        force m_rlast  = 1'b1;
        @(posedge clk);
        @(posedge clk);
        release m_rvalid;
        release m_rdata;
        release m_rlast;
        repeat (4) @(posedge clk);

        if (o_late != 32'd1) begin
            $display("FAIL arb: orphan beat not counted (o_late_cnt=%0d)", o_late); errors = errors + 1;
        end else $display("PASS arb: orphan/late beat counted once (o_late_cnt=1)");
        if (transferred_to_b != 1) begin
            $display("FAIL arb: orphan beat leaked to the bridge"); errors = errors + 1;
        end else $display("PASS arb: orphan beat was NOT re-routed to any owner");

        if (errors == 0) $display("ARB_RESULT=PASS");
        else             $display("ARB_RESULT=FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #2000000;
        $display("ARB_RESULT=FAIL timeout");
        $finish;
    end
endmodule

// ---------------------------------------------------------------------------
// top level scaled board datapath test
// ---------------------------------------------------------------------------
module tb_brd_g1_top;
    localparam integer W       = 64;
    localparam integer H       = 48;
    localparam integer CAM_W   = 128;
    localparam integer CAM_H   = 96;
    localparam integer ROI_X   = 32;
    localparam integer ROI_Y   = 16;
    localparam integer NG      = (W * H) / 4;
    localparam integer SLOT_WORDS = 1024;
    localparam [31:0]  SLOT_BASE_WORD = 32'd2048;
    localparam integer SLOT_BASE_BYTES = 2048 * 32;   // 65536
    localparam integer DWORDS  = 16384;
    localparam integer DWORDS_LOG = 14;

    integer SCEN, PREP, PRED;
    initial begin
        if (!$value$plusargs("SCEN=%d", SCEN)) SCEN = 0;
        if (!$value$plusargs("PREP=%d", PREP)) PREP = 0;
        if (!$value$plusargs("PRED=%d", PRED)) PRED = 0;
        $display("TB_SCEN=%0d PREP=%0d PRED=%0d", SCEN, PREP, PRED);
    end

    reg cam_clk = 0, core_clk = 0, usr_clk = 0, tl_clk = 0;
    always #2.667 cam_clk  = ~cam_clk;
    always #3.333 core_clk = ~core_clk;
    always #5.000 usr_clk  = ~usr_clk;
    always #8.000 tl_clk   = ~tl_clk;

    reg [39:0] cam_pix = 40'd0;
    reg        cam_pv = 0, cam_il = 0, cam_if = 0, cam_vs = 0;

    reg  [31:0] cfg_cap_bytes = 32'h0004_0000;
    reg  [31:0] cfg_session   = 32'hA5A5_0001;
    reg  [31:0] cfg_dst_lo    = 32'h0100_0000;
    reg  [31:0] cfg_dst_hi    = 32'd0;
    reg  [31:0] cfg_db_lo     = 32'h0200_0000;
    reg  [31:0] cfg_db_hi     = 32'd0;
    reg         cfg_push_en   = 1'b1;
    reg         tx_arm = 0, tx_ack = 0, tx_cancel = 0;
    reg  [31:0] tx_ack_seq = 0, tx_ack_sess = 0;

    wire [28:0] ddr_awaddr;
    wire [255:0] ddr_wdata;
    wire [31:0] ddr_wstrb;
    wire ddr_awvalid, ddr_wvalid, ddr_wlast, ddr_bready;
    wire ddr_awready, ddr_wready;
    wire [3:0] ddr_arid;
    wire [28:0] ddr_araddr;
    wire [7:0] ddr_arlen;
    wire [2:0] ddr_arsize;
    wire [1:0] ddr_arburst;
    wire ddr_arvalid, ddr_arready, ddr_rready;
    wire [3:0] ddr_rid;
    wire [255:0] ddr_rdata;
    wire [1:0] ddr_rresp;
    wire ddr_rlast, ddr_rvalid;

    wire [31:0] push_done, push_status, push_tlp;
    wire [7:0]  push_err;
    wire [31:0] tx_status;
    wire        tx_block_cfg;
    wire [127:0] p4_st;
    wire        utx_sel = 1'b1;   // EP TX port always grants in this TB (tl_tx_wait=0)
    wire        utx_req, utx_sop, utx_eop;
    wire [255:0] utx_data;
    wire [7:0]  utx_valid;
    wire        arb_owner;
    wire [31:0] arb_late, arb_switch, desc_active, slot_busy, arm_seq_c;

    reg [3:0] rst_core_cnt = 4'd0, rst_tl_cnt = 4'd0, rst_usr_cnt = 4'd0, rst_cam_cnt = 4'd0;
    wire rst_core_n = rst_core_cnt[3];
    wire rst_tl_n   = rst_tl_cnt[3];
    wire rst_usr_n  = rst_usr_cnt[3];
    wire rst_cam_n  = rst_cam_cnt[3];

    brd_board_datapath #(
        .CAM_A_W(128), .CAM_A_H(96), .ROI_A_X(32), .ROI_A_Y(16),
        .CAM_B_W(128), .CAM_B_H(96), .ROI_B_X(32), .ROI_B_Y(16),
        .W(W), .H(H), .MAX_WORDS(64),
        .SLOT_WORDS(SLOT_WORDS),
        .SLOT_BASE_WORD(SLOT_BASE_WORD),
        .FIFO_AW(10),
        .DDR_CAP_BYTES(32'h0010_0000)
    ) u_dut (
        .cam_a_clk(cam_clk), .cam_a_rst_n(rst_cam_n),
        .cam_a_pix(40'd0), .cam_a_pix_valid(1'b0),
        .cam_a_in_line(1'b0), .cam_a_in_frame(1'b0), .cam_a_vsync(1'b0),
        .cam_b_clk(cam_clk), .cam_b_rst_n(rst_cam_n),
        .cam_b_pix(cam_pix), .cam_b_pix_valid(cam_pv),
        .cam_b_in_line(cam_il), .cam_b_in_frame(cam_if), .cam_b_vsync(cam_vs),
        .clk_core(core_clk), .rst_core_n(rst_core_n),
        .usr_clk(usr_clk), .rst_usr_n(rst_usr_n), .ddr_rdy(1'b1),
        .tl_clk(tl_clk), .tl_rst_n(rst_tl_n),
        .cfg_cap_bytes(cfg_cap_bytes), .cfg_session_id(cfg_session),
        .cfg_dst_lo(cfg_dst_lo), .cfg_dst_hi(cfg_dst_hi),
        .cfg_db_lo(cfg_db_lo), .cfg_db_hi(cfg_db_hi),
        .cfg_push_en(cfg_push_en), .cfg_a_enable(1'b0), .cfg_trigger_mode(1'b0),
        .cfg_p4_desc_owner(1'b1), .cfg_mode(3'd0), .cfg_prep(PREP != 0), .cfg_pred(PRED != 0),
        .cfg_phase(2'd0), .link_up(1'b1), .mps_code(3'd0),
        .tx_arm(tx_arm), .tx_ack(tx_ack), .tx_cancel(tx_cancel),
        .tx_cap_bytes(cfg_cap_bytes), .tx_session_id(cfg_session),
        .tx_ack_seq(tx_ack_seq), .tx_ack_session(tx_ack_sess),
        .tl_tx_wait(1'b0),
        .utx_sel(utx_sel), .utx_req(utx_req), .utx_data(utx_data),
        .utx_sop(utx_sop), .utx_eop(utx_eop), .utx_valid(utx_valid),
        .o_push_done(push_done), .o_push_status(push_status), .o_push_tlp(push_tlp),
        .o_push_err(push_err), .o_tx_status(tx_status), .o_tx_block_cfg(tx_block_cfg),
        .o_p4_st(p4_st),
        .ddr_awaddr(ddr_awaddr), .ddr_wdata(ddr_wdata), .ddr_wstrb(ddr_wstrb),
        .ddr_awvalid(ddr_awvalid), .ddr_wvalid(ddr_wvalid), .ddr_wlast(ddr_wlast),
        .ddr_awready(ddr_awready), .ddr_wready(ddr_wready), .ddr_bready(ddr_bready),
        .ddr_arid(ddr_arid), .ddr_araddr(ddr_araddr), .ddr_arlen(ddr_arlen),
        .ddr_arsize(ddr_arsize), .ddr_arburst(ddr_arburst),
        .ddr_arvalid(ddr_arvalid), .ddr_arready(ddr_arready),
        .ddr_rid(ddr_rid), .ddr_rdata(ddr_rdata), .ddr_rresp(ddr_rresp),
        .ddr_rlast(ddr_rlast), .ddr_rvalid(ddr_rvalid), .ddr_rready(ddr_rready),
        .o_arb_owner(arb_owner), .o_arb_late(arb_late), .o_arb_switch(arb_switch),
        .o_p4_desc_active(desc_active), .o_slot_busy(slot_busy),
        .o_arm_seq(arm_seq_c)
    );

    initial begin
        repeat (20) @(posedge core_clk);
        rst_core_cnt <= 4'hF;
        rst_cam_cnt  <= 4'hF;
        repeat (20) @(posedge tl_clk);
        rst_tl_cnt <= 4'hF;
        repeat (20) @(posedge usr_clk);
        rst_usr_cnt <= 4'hF;
    end

    wire [31:0] dm_wr_beats, dm_rd_bursts, dm_rd_beats;

    brd_ddr_slave_model #(.DWORDS(DWORDS), .DWORDS_LOG(DWORDS_LOG)) u_mem (
        .clk(usr_clk), .rst_n(rst_usr_n),
        .awaddr(ddr_awaddr), .wdata(ddr_wdata), .wstrb(ddr_wstrb),
        .awvalid(ddr_awvalid), .wvalid(ddr_wvalid), .wlast(ddr_wlast),
        .awready(ddr_awready), .wready(ddr_wready), .bready(ddr_bready), .bvalid(),
        .arid(ddr_arid), .araddr(ddr_araddr), .arlen(ddr_arlen), .arsize(ddr_arsize),
        .arburst(ddr_arburst), .arvalid(ddr_arvalid), .arready(ddr_arready),
        .rid(ddr_rid), .rdata(ddr_rdata), .rresp(ddr_rresp), .rlast(ddr_rlast),
        .rvalid(ddr_rvalid), .rready(ddr_rready),
        .wr_beats(dm_wr_beats), .rd_bursts(dm_rd_bursts), .rd_beats(dm_rd_beats)
    );

    // -----------------------------------------------------------------------
    // TLP host model: 4DW MWr header + 32 DW payload (5 beats), doorbell = 1 DW
    // -----------------------------------------------------------------------
    reg  [31:0] dw_all [0:63];
    integer     tlp_dw = 0;
    integer     tlp_cnt = 0;
    integer     db_cnt = 0;
    integer     be_cnt = 0;
    integer     err_tlp = 0;
    integer     mism = 0;
    reg  [31:0] db_payload = 32'd0;
    reg  [31:0] first_addr = 32'd0;
    reg  [31:0] last_addr  = 32'd0;
    integer     k, j, b;
    reg  [31:0] exp_addr;
    reg  [31:0] dw_swap;
    reg  [31:0] frame_bytes_r;
    integer     frame_bytes_i;

    function [31:0] bswap32;
        input [31:0] x;
        begin bswap32 = {x[7:0], x[15:8], x[23:16], x[31:24]}; end
    endfunction

    task process_tlp;
        begin
            if (tlp_cnt + db_cnt < 6)
                $display("TLP_CAP n=%0d tlp_dw=%0d dw0=%h dw1=%h dw2=%h dw3=%h dw4=%h",
                         tlp_cnt+db_cnt, tlp_dw, dw_all[0], dw_all[1], dw_all[2], dw_all[3], dw_all[4]);
            if (dw_all[0][9:0] == 10'd1) begin
                db_cnt = db_cnt + 1;
                db_payload = bswap32(dw_all[4]);
                if ({dw_all[2], dw_all[3]} != {cfg_db_hi, cfg_db_lo}) begin
                    $display("FAIL tlp: doorbell address %h != %h", {dw_all[2], dw_all[3]}, {cfg_db_hi, cfg_db_lo});
                    err_tlp = err_tlp + 1;
                end
            end else begin
                tlp_cnt = tlp_cnt + 1;
                exp_addr = cfg_dst_lo + (tlp_cnt - 1) * 32'd128;
                if ({dw_all[2], dw_all[3]} != {cfg_dst_hi, exp_addr}) begin
                    if (err_tlp < 4) $display("FAIL tlp: addr %h != %h", {dw_all[2], dw_all[3]}, {cfg_dst_hi, exp_addr});
                    err_tlp = err_tlp + 1;
                end
                if (tlp_cnt == 1) first_addr = dw_all[3];
                last_addr = dw_all[3];
                if (dw_all[0][9:0] != 10'd32) begin
                    if (err_tlp < 4) $display("FAIL tlp: length %0d != 32", dw_all[0][9:0]);
                    err_tlp = err_tlp + 1;
                end
                for (j = 0; j < 32; j = j + 1) begin
                    dw_swap = bswap32(dw_all[4+j]);
                    for (b = 0; b < 4; b = b + 1) begin
                        be_cnt = be_cnt + 1;
                        if (dw_swap[8*b +: 8] !==
                            u_mem.mem[(SLOT_BASE_BYTES + (tlp_cnt-1)*128 + j*4 + b) >> 5]
                                      [((SLOT_BASE_BYTES + (tlp_cnt-1)*128 + j*4 + b) % 32)*8 +: 8]) begin
                            if (mism < 4) $display("MISMATCH tlp %0d byte %0d: got %h exp %h",
                                tlp_cnt-1, j*4+b,
                                dw_swap[8*b +: 8],
                                u_mem.mem[(SLOT_BASE_BYTES + (tlp_cnt-1)*128 + j*4 + b) >> 5]
                                          [((SLOT_BASE_BYTES + (tlp_cnt-1)*128 + j*4 + b) % 32)*8 +: 8]);
                            mism = mism + 1;
                        end
                    end
                end
            end
        end
    endtask

    always @(posedge tl_clk) begin
        if (utx_sel && utx_req && (utx_valid != 8'd0)) begin
            if (utx_sop) tlp_dw = 0;
            // The pusher places the first TLP DW in the HIGHEST beat lane
            // ("first byte in the high bits", 8'hF0 header mask).  Emit only the
            // valid DW lanes, from lane 7 down to lane 0, into TLP order.
            for (k = 7; k >= 0; k = k - 1) begin
                if (utx_valid[k]) begin
                    dw_all[tlp_dw] = utx_data[k*32 +: 32];
                    tlp_dw = tlp_dw + 1;
                end
            end
            if (utx_eop) process_tlp;
        end
    end

    // -----------------------------------------------------------------------
    // A+ input byte capture (packed RAW10, 5 B per accepted 40-bit beat)
    // -----------------------------------------------------------------------
    reg  [7:0] pk_bytes [0:65535];
    integer    pk_cnt = 0;
    always @(posedge core_clk) begin
        if (rst_core_n && u_dut.u_p4.pk_accept) begin
            pk_bytes[pk_cnt*5+0] = u_dut.u_p4.pk_data[7:0];
            pk_bytes[pk_cnt*5+1] = u_dut.u_p4.pk_data[15:8];
            pk_bytes[pk_cnt*5+2] = u_dut.u_p4.pk_data[23:16];
            pk_bytes[pk_cnt*5+3] = u_dut.u_p4.pk_data[31:24];
            pk_bytes[pk_cnt*5+4] = u_dut.u_p4.pk_data[39:32];
            pk_cnt = pk_cnt + 1;
        end
    end

    // -----------------------------------------------------------------------
    // X / monotonic checks
    // -----------------------------------------------------------------------
    integer x_hits = 0;
    always @(posedge core_clk) begin
        if (rst_core_n && u_dut.u_p4.ap_valid && (^u_dut.u_p4.ap_data === 1'bx)) x_hits = x_hits + 1;
        if (rst_core_n && ddr_wvalid && (^ddr_wdata === 1'bx)) x_hits = x_hits + 1;
    end
    always @(posedge usr_clk) begin
        if (rst_usr_n && ddr_rvalid && (^ddr_rdata === 1'bx)) x_hits = x_hits + 1;
    end
    always @(posedge tl_clk) begin
        if (rst_tl_n && utx_valid != 8'd0 && (^utx_data === 1'bx)) x_hits = x_hits + 1;
    end

    // -----------------------------------------------------------------------
    // helpers
    // -----------------------------------------------------------------------
    task pulse_arm;
        begin
            @(posedge tl_clk); tx_arm <= 1'b1;
            @(posedge tl_clk); tx_arm <= 1'b0;
        end
    endtask

    task do_ack(input [31:0] seq);
        begin
            @(posedge tl_clk);
            tx_ack_seq  <= seq;
            tx_ack_sess <= cfg_session;
            tx_ack      <= 1'b1;
            @(posedge tl_clk);
            tx_ack      <= 1'b0;
        end
    endtask

    function [31:0] crc32b;
        input [31:0] c;
        input [7:0]  d;
        integer kk;
        reg [31:0] x;
        begin
            x = c ^ {24'd0, d};
            for (kk = 0; kk < 8; kk = kk + 1)
                x = x[0] ? ((x >> 1) ^ 32'hEDB88320) : (x >> 1);
            crc32b = x;
        end
    endfunction

    reg [31:0] hdr_w [0:10];
    reg [7:0]  hdr_b [0:43];
    reg [31:0] hcrc, crc_run;
    integer    hk;
    integer    fd, meta;
    integer    stream_len_i, frame_bytes_calc;
    reg [31:0] held_seq;

    task dump_and_header;
        begin
            stream_len_i    = u_dut.u_p4.st_stream_len;
            frame_bytes_r   = u_dut.m_frame_bytes;
            frame_bytes_i   = frame_bytes_r;
            held_seq        = u_dut.u_pusher.held_seq;

            // slot bytes at 0x1_0000 and the legacy base 0
            fd = $fopen("slot_dump.bin", "wb");
            for (hk = 0; hk < stream_len_i; hk = hk + 1)
                $fwrite(fd, "%c", u_mem.mem[(SLOT_BASE_BYTES+hk) >> 5][((SLOT_BASE_BYTES+hk) % 32)*8 +: 8]);
            $fclose(fd);
            fd = $fopen("slotbase0_dump.bin", "wb");
            for (hk = 0; hk < 4096; hk = hk + 1)
                $fwrite(fd, "%c", u_mem.mem[hk >> 5][(hk % 32)*8 +: 8]);
            $fclose(fd);
            // A+ input packed RAW10 bytes
            fd = $fopen("pk_bytes.bin", "wb");
            for (hk = 0; hk < pk_cnt*5; hk = hk + 1)
                $fwrite(fd, "%c", pk_bytes[hk]);
            $fclose(fd);
            // A1U1 header built by the host model (D6 contract)
            hdr_w[0]  = 32'h31553141;
            hdr_w[1]  = {8'h00, 8'd44, 6'b0, (PRED != 0), (PREP != 0), 8'h01};
            hdr_w[2]  = u_dut.m_capture_seq;
            hdr_w[3]  = {H[15:0], W[15:0]};
            hdr_w[4]  = (W * H * 10) / 8;
            hdr_w[5]  = u_dut.u_p4.st_xform_len;
            hdr_w[6]  = u_dut.u_p4.st_stream_len;
            hdr_w[7]  = u_dut.u_p4.st_raw_crc;
            hdr_w[8]  = u_dut.u_p4.st_xform_crc;
            hdr_w[9]  = u_dut.u_p4.st_stream_crc;
            crc_run = 32'hFFFFFFFF;
            for (hk = 0; hk < 40; hk = hk + 1) begin
                hdr_b[hk] = hdr_w[hk >> 2] >> ((hk % 4) * 8);
                crc_run = crc32b(crc_run, hdr_b[hk]);
            end
            hcrc = ~crc_run;
            hdr_w[10] = hcrc;
            for (hk = 40; hk < 44; hk = hk + 1) hdr_b[hk] = hdr_w[hk >> 2] >> ((hk % 4) * 8);

            // no change to the DUT, so its three status CRCs must match host CRCs
            crc_run = 32'hFFFFFFFF;
            for (hk = 0; hk < pk_cnt*5; hk = hk + 1) crc_run = crc32b(crc_run, pk_bytes[hk]);
            $display("HDR xform_crc=%h host_pk_crc=%h raw_crc=%h", u_dut.u_p4.st_xform_crc, ~crc_run, u_dut.u_p4.st_raw_crc);
            if ((PREP == 0) && (PRED == 0) && (~crc_run !== u_dut.u_p4.st_xform_crc)) begin
                $display("A1U1_HEADER=FAIL xform_crc_mismatch");
            end else begin
                $display("A1U1_HEADER=PASS frame_id=%0d W=%0d H=%0d raw=%0d xform=%0d stream=%0d hcrc=%h",
                         hdr_w[2], W, H, hdr_w[4], hdr_w[5], hdr_w[6], hcrc);
            end

            fd = $fopen("a1u1_frame.bin", "wb");
            for (hk = 0; hk < 44; hk = hk + 1) $fwrite(fd, "%c", hdr_b[hk]);
            for (hk = 0; hk < stream_len_i; hk = hk + 1)
                $fwrite(fd, "%c", u_mem.mem[(SLOT_BASE_BYTES+hk) >> 5][((SLOT_BASE_BYTES+hk) % 32)*8 +: 8]);
            $fclose(fd);

            meta = $fopen("sim_meta.txt", "w");
            $fwrite(meta, "stream_len=%0d\n", stream_len_i);
            $fwrite(meta, "frame_bytes=%0d\n", frame_bytes_i);
            $fwrite(meta, "xform_len=%0d\n", u_dut.u_p4.st_xform_len);
            $fwrite(meta, "raw_len=%0d\n", u_dut.u_p4.st_raw_len);
            $fwrite(meta, "pk_bytes=%0d\n", pk_cnt*5);
            $fwrite(meta, "tlp_cnt=%0d\n", tlp_cnt);
            $fwrite(meta, "mwr_bytes=%0d\n", be_cnt);
            $fwrite(meta, "db_cnt=%0d\n", db_cnt);
            $fwrite(meta, "db_payload=%0d\n", db_payload);
            $fwrite(meta, "held_seq=%0d\n", held_seq);
            $fwrite(meta, "exported=%0d\n", u_dut.u_p4.st_exported);
            $fwrite(meta, "mism=%0d\n", mism);
            $fwrite(meta, "err_tlp=%0d\n", err_tlp);
            $fwrite(meta, "x_hits=%0d\n", x_hits);
            $fwrite(meta, "stream_crc=%h\n", u_dut.u_p4.st_stream_crc);
            $fclose(meta);
        end
    endtask

    // -----------------------------------------------------------------------
    // stimulus
    // -----------------------------------------------------------------------
    integer line, grp, i;
    integer guard;
    integer last_line;
    integer rel_before;
    integer arm_ignored_c;

    initial begin
        repeat (200) @(posedge cam_clk);
        cam_if = 0; cam_il = 0; cam_pv = 0; cam_vs = 0;

        // early ARM (before any frame) for SCEN 3; double ARM = one request
        if (SCEN == 3) begin
            pulse_arm;
            pulse_arm;
            $display("INFO: early ARM issued before the frame (doubled)");
        end

        // one ROI frame out of the sensor raster; SCEN 1 omits the last ROI row
        last_line = (SCEN == 1) ? (ROI_Y + H - 1) : (ROI_Y + H);
        cam_vs <= 1'b1; @(posedge cam_clk); cam_vs <= 1'b0;
        @(posedge cam_clk); cam_if <= 1'b1;
        for (line = 0; line < last_line; line = line + 1) begin
            @(posedge cam_clk); cam_il <= 1'b1;
            @(posedge cam_clk); cam_il <= 1'b0;
            for (grp = 0; grp < (CAM_W/4); grp = grp + 1) begin
                cam_pv  <= 1'b1;
                cam_pix <= {4{(line*32 + grp) & 10'h3FF}};
                @(posedge cam_clk);
                cam_pv <= 1'b0;
            end
        end
        @(posedge cam_clk); cam_if <= 1'b0;

        $display("INFO: frame sent (%0d raster lines, ROI rows %0d..%0d)", last_line, ROI_Y, last_line-1);

        if (SCEN == 1) begin
            // arm after the truncated frame: must still never export
            pulse_arm;
            guard = 0;
            while ((u_dut.u_p4.st_release_count == 0) && (guard < 400000)) begin
                @(posedge tl_clk); guard = guard + 1;
            end
            repeat (500) @(posedge tl_clk);
            $display("INFO: neg1 committed=%0d published=%0d aborted=%0d exported=%0d tlp=%0d db=%0d rel=%0d guard=%0d",
                     u_dut.u_p4.st_frames_committed, u_dut.u_p4.st_store_published,
                     u_dut.u_p4.st_frames_aborted, u_dut.u_p4.st_exported, tlp_cnt, db_cnt,
                     u_dut.u_p4.st_release_count, guard);
            if (u_dut.u_p4.st_frames_committed == 0 && u_dut.u_p4.st_store_published == 0 &&
                u_dut.u_p4.st_exported == 0 && tlp_cnt == 0 && db_cnt == 0 &&
                u_dut.u_p4.st_release_count >= 1 && u_dut.u_p4.st_frames_aborted >= 1)
                $display("NEG1_RESULT=PASS");
            else
                $display("NEG1_RESULT=FAIL");
            $finish;
        end

        // late ARM: wait for the P4 publish (store_published != 0)
        if (SCEN != 3) begin
            guard = 0;
            while ((u_dut.u_p4.st_store_published == 0) && (guard < 400000)) begin
                @(posedge tl_clk); guard = guard + 1;
            end
            $display("INFO: publish seen after %0d tl cycles (published=%0d)", guard, u_dut.u_p4.st_store_published);
            pulse_arm;
        end

        // duplicate ARM while ARMED (SCEN 4)
        if (SCEN == 4) begin
            guard = 0;
            while (!(tx_status[0] || tx_status[1]) && (guard < 20000)) begin
                @(posedge tl_clk); guard = guard + 1;
            end
            pulse_arm;
            @(posedge tl_clk); tx_arm <= 1'b1;
            @(posedge tl_clk); tx_arm <= 1'b0;
        end

        // wait for the doorbell (export complete)
        guard = 0;
        while ((db_cnt == 0) && (guard < 800000)) begin
            @(posedge tl_clk); guard = guard + 1;
        end
        repeat (300) @(posedge tl_clk);

        $display("INFO: after export tlp=%0d mwr_bytes=%0d db=%0d db_payload=%0d exported=%0d held_seq=%0d frame_bytes=%0d stream_len=%0d",
                 tlp_cnt, be_cnt, db_cnt, db_payload, u_dut.u_p4.st_exported,
                 u_dut.u_pusher.held_seq, u_dut.m_frame_bytes, u_dut.u_p4.st_stream_len);

        if (SCEN == 2) begin
            rel_before = u_dut.u_p4.st_release_count;
            do_ack(u_dut.u_pusher.held_seq ^ 32'd1);
            repeat (3000) @(posedge tl_clk);
            $display("INFO: neg2 wrong ACK held=%b exported=%0d rel=%0d desc_active=%b",
                     tx_status[2], u_dut.u_p4.st_exported, u_dut.u_p4.st_release_count, desc_active);
            if (tx_status[2] !== 1'b1 || u_dut.u_p4.st_exported != 1 ||
                u_dut.u_p4.st_release_count != rel_before || desc_active !== 1'b1) begin
                $display("NEG2_RESULT=FAIL wrong ACK changed state");
                $finish;
            end
            do_ack(u_dut.u_pusher.held_seq);
            guard = 0;
            while ((u_dut.u_p4.st_release_count == rel_before) && (guard < 100000)) begin
                @(posedge tl_clk); guard = guard + 1;
            end
            if (u_dut.u_p4.st_release_count != (rel_before + 1)) begin
                $display("NEG2_RESULT=FAIL correct ACK did not release (rel=%0d before=%0d)",
                         u_dut.u_p4.st_release_count, rel_before);
            end else begin
                $display("PASS neg2: wrong ACK held, correct ACK released rel=%0d", u_dut.u_p4.st_release_count);
                $display("NEG2_RESULT=PASS");
            end
            $finish;
        end

        // ---- positive checks ----
        dump_and_header;
        arm_ignored_c = u_dut.u_export_seq.arm_ignored;
        $display("INFO: seq evt_cnt=%0d arm_ignored=%0d armed=%b", u_dut.u_export_seq.evt_cnt, arm_ignored_c, u_dut.u_export_seq.armed_q);
        $display("DBG PUSH g_st=%0d src_evt=%b claim=%b last_seq=%0d src_seq=%0d fbytes=%0d lat_fbytes=%0d push_en=%b ddr_status=%b ddr_base=%h lat_src=%b src_sel=%b lat_cam=%b cam_sel=%b pv=%b dok=%b bok=%b pu_seq=%0d",
                 u_dut.u_pusher.g_st, u_dut.u_pusher.src_evt, u_dut.u_pusher.claim,
                 u_dut.u_pusher.last_seq, u_dut.u_pusher.src_seq, u_dut.u_pusher.frame_bytes,
                 u_dut.u_pusher.lat_fbytes, u_dut.u_pusher.push_en, u_dut.u_pusher.ddr_status,
                 u_dut.u_pusher.ddr_base, u_dut.u_pusher.lat_src, u_dut.u_pusher.src_sel,
                 u_dut.u_pusher.lat_cam, u_dut.u_pusher.cam_sel_live, u_dut.u_pusher.par_valid,
                 u_dut.u_pusher.claim_desc_ok, u_dut.u_pusher.claim_base_ok, u_dut.pu_seq);
        $display("DBG AXI a_st=%0d req_level=%b req_s2=%b fifo_empty=%b arvalid=%b arready=%b rvalid=%b rready=%b arlen=%0d araddr=%h arb_busy=%b arb_owner=%b b_arvalid=%b dm_bursts=%0d dm_beats=%0d",
                 u_dut.u_pusher.a_st, u_dut.u_pusher.req_level, u_dut.u_pusher.req_s2,
                 u_dut.u_pusher.fifo_empty, u_dut.ddr_arvalid, u_dut.ddr_arready,
                 u_dut.ddr_rvalid, u_dut.ddr_rready, u_dut.ddr_arlen, u_dut.ddr_araddr,
                 u_dut.u_arb.busy, u_dut.u_arb.owner, u_dut.u_bridge.paxi_arvalid,
                 dm_rd_bursts, dm_rd_beats);
        $display("SLOT_FIRST=%02h %02h SLOT0=%02h %02h %02h %02h",
                 u_mem.mem[SLOT_BASE_BYTES >> 5][0 +: 8], u_mem.mem[SLOT_BASE_BYTES >> 5][8 +: 8],
                 u_mem.mem[0][0 +: 8], u_mem.mem[0][8 +: 8], u_mem.mem[0][16 +: 8], u_mem.mem[0][24 +: 8]);

        if (tlp_cnt == 0 || db_cnt == 0 || u_dut.u_p4.st_exported != 1 ||
            u_dut.u_p4.st_frames_committed != 1 || u_dut.u_p4.st_store_published != 1) begin
            $display("FAIL pos: no export (tlp=%0d db=%0d exported=%0d err=%h status=%h)",
                     tlp_cnt, db_cnt, u_dut.u_p4.st_exported, push_err, push_status);
            $display("POS_RESULT=FAIL");
            $finish;
        end
        if (tlp_cnt != (u_dut.m_frame_bytes / 128) || be_cnt != u_dut.m_frame_bytes) begin
            $display("FAIL pos: mwr_count/bytes %0d/%0d != frame_bytes/128=%0d bytes=%0d",
                     tlp_cnt, be_cnt, u_dut.m_frame_bytes/128, u_dut.m_frame_bytes);
            $display("POS_RESULT=FAIL");
            $finish;
        end
        if (mism != 0 || err_tlp != 0) begin
            $display("FAIL pos: mismatch=%0d tlp_header_errors=%0d", mism, err_tlp);
            $display("POS_RESULT=FAIL");
            $finish;
        end
        if (db_payload != u_dut.u_pusher.held_seq || db_cnt != 1) begin
            $display("FAIL pos: doorbell payload/count %0d/%0d != held_seq=%0d/1",
                     db_payload, db_cnt, u_dut.u_pusher.held_seq);
            $display("POS_RESULT=FAIL");
            $finish;
        end
        if (u_mem.mem[SLOT_BASE_BYTES >> 5][0 +: 8] != 8'h78 ||
            u_mem.mem[SLOT_BASE_BYTES >> 5][8 +: 8] != 8'h9C) begin
            $display("FAIL pos: slot base 0x10000 does not start with 78 9C");
            $display("POS_RESULT=FAIL");
            $finish;
        end
        for (i = 0; i < 64; i = i + 1) begin
            if (u_mem.mem[i >> 5][(i % 32)*8 +: 8] !== 8'h00) begin
                $display("FAIL pos: legacy base 0 byte %0d is %02h (must stay unused)",
                         i, u_mem.mem[i >> 5][(i % 32)*8 +: 8]);
                $display("POS_RESULT=FAIL");
                $finish;
            end
        end
        if (x_hits != 0 || arb_late != 0 || arb_switch != 0) begin
            $display("FAIL pos: x_hits=%0d late=%0d switch=%0d", x_hits, arb_late, arb_switch);
            $display("POS_RESULT=FAIL");
            $finish;
        end
        if (SCEN == 4 && arm_ignored_c < 1) begin
            $display("FAIL pos: duplicate ARM was not ignored (arm_ignored=%0d)", arm_ignored_c);
            $display("POS_RESULT=FAIL");
            $finish;
        end

        // ---- correct ACK releases the slot ----
        rel_before = u_dut.u_p4.st_release_count;
        do_ack(u_dut.u_pusher.held_seq);
        guard = 0;
        while ((u_dut.u_p4.st_release_count == rel_before) && (guard < 100000)) begin
            @(posedge tl_clk); guard = guard + 1;
        end
        if (u_dut.u_p4.st_release_count != (rel_before + 1)) begin
            $display("FAIL pos: correct ACK did not release (rel=%0d before=%0d)",
                     u_dut.u_p4.st_release_count, rel_before);
            $display("POS_RESULT=FAIL");
            $finish;
        end
        $display("PASS pos: correct ACK released the slot after %0d cycles (rel=%0d)", guard, u_dut.u_p4.st_release_count);
        $display("POS_RESULT=PASS tlps=%0d bytes=%0d db=%0d scen=%0d", tlp_cnt, be_cnt, db_payload, SCEN);
        $finish;
    end

    initial begin
        #60000000;
        $display("RESULT=FAIL timeout");
        $finish;
    end
endmodule

