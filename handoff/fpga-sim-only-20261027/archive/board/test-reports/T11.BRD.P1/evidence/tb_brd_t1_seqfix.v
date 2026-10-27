`timescale 1ns/1ps
// =============================================================================
// tb_brd_t1.v -- TESTER copy of T11.BRD.P1 sim/tb_brd_g1.v (SHA256 B8FBDBF5...)
//   Independent additions by the integrated tester (round 0):
//     * dump_slot  : dumps the DDR slot bytes + P4 status + egress adapter state
//                    so a THIRD-PARTY (python zlib) decoder can verify the frame
//     * X monitor  : counts X/Z on the TLP and DDR buses after reset release
//     * SCEN=1     : additionally requires committed==0 and published==0
//     * arb #3     : both owners requesting simultaneously must both be served
//   No production RTL was modified. Only this test copy differs.
// =============================================================================
//
// Two test modules in one file (one compile, two vsim runs):
//   tb_brd_g1_top : scaled board datapath + camera model + DDR AXI slave model
//                   + TLP host model + BAR register model.
//                   +SCEN=0 full frame A1U1 export (positive)
//                   +SCEN=1 frame without EOF      (must be rejected)
//                   +SCEN=2 wrong ACK              (must not release)
//   tb_brd_arb    : adversarial DDR read arbiter test (mid-burst switch request
//                   + orphan/迟到 beat counting)
//
// Geometry is scaled (ROI 64x48, camera 128x96) but the RTL path is the same
// brd_board_datapath that the board top instantiates: a1_raw_crop -> 43b pack ->
// capture_async_fifo -> integrated_delivery_top (P4 r2) -> p2_ddr_bridge ->
// brd_ddr_rd_arb <-> ddr_frame_pusher -> TLP.
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
    // write
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
    // read
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
    // observation
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

    // ---- write channel: latch the address, then take one 256 bit beat ----
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

    // ---- read channel ----
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
                    if (rd_left == 8'd0) begin
                        rd_busy <= 1'b0;
                    end else begin
                        rd_left <= rd_left - 8'd1;
                    end
                end
            end else begin
                rvalid <= 1'b0;
                rlast  <= 1'b0;
            end
        end
    end
endmodule

// ---------------------------------------------------------------------------
// arbiter test: mid-burst switch request + orphan beat
// ---------------------------------------------------------------------------
module tb_brd_t1_arb;
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
    integer guard2 = 0;
    integer bx_before = 0;

    // monitor: b_arready while the pusher burst is in flight is a violation
    always @(posedge clk) begin
        if (o_busy && o_owner == 1'b1 && b_arready) b_grant_inside_burst = b_grant_inside_burst + 1;
        if (o_busy && o_owner == 1'b0 && p_arready) b_grant_inside_burst = b_grant_inside_burst + 1;
        if (b_rvalid) transferred_to_b = transferred_to_b + 1;
    end

    initial begin
        repeat (8) @(posedge clk);
        rst_n = 1;
        repeat (4) @(posedge clk);

        // ---- 1. pusher burst of 4 beats; bridge asks during the burst ----
        p_araddr  = 29'd128;
        p_arlen   = 8'd3;
        p_arvalid = 1'b1;
        @(posedge clk);
        while (!p_arready) @(posedge clk);
        p_arvalid = 1'b0;

        // ask for the bridge while two beats are still outstanding
        @(posedge clk);
        b_araddr  = 29'd64;
        b_arvalid = 1'b1;

        // wait for the burst to finish
        while (o_busy) @(posedge clk);
        // bridge must be granted now (round robin went to the bridge)
        @(posedge clk);
        b_arvalid = 1'b0;
        repeat (6) @(posedge clk);

        if (b_grant_inside_burst != 0) begin
            $display("FAIL arb: %0d grant(s) inside a burst", b_grant_inside_burst);
            errors = errors + 1;
        end else begin
            $display("PASS arb: no grant changed owner inside a burst");
        end
        if (transferred_to_b != 1) begin
            $display("FAIL arb: bridge received %0d beats (expected 1)", transferred_to_b);
            errors = errors + 1;
        end else begin
            $display("PASS arb: bridge got exactly its single beat");
        end
        if (o_bx != 32'd1) begin
            $display("FAIL arb: o_b_xacts=%0d (expected 1)", o_bx); errors = errors + 1;
        end else $display("PASS arb: one bridge transaction completed");
        if (o_switch != 32'd0) begin
            $display("FAIL arb: o_switch_err=%0d", o_switch); errors = errors + 1;
        end else $display("PASS arb: o_switch_err=0");

        // ---- 2. orphan (迟到) beat: inject one extra R beat with no AR ----
        //     the model only answers ARs, so drive the DDR side by hand
        //     (m_* are wires from the model; use force on the arbiter input)
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
        end else begin
            $display("PASS arb: orphan/迟到 beat counted once (o_late_cnt=1)");
        end
        if (transferred_to_b != 1) begin
            $display("FAIL arb: orphan beat leaked to the bridge"); errors = errors + 1;
        end else begin
            $display("PASS arb: orphan beat was NOT re-routed to any owner");
        end

        // ---- 3. T1: fairness -- both owners request at the same time ----
        //     neither may starve: both transactions must complete back to back.
        bx_before = o_bx;
        b_araddr  = 29'd96;  b_arvalid = 1'b1;
        p_araddr  = 29'd256; p_arlen = 8'd1; p_arvalid = 1'b1;
        guard2 = 0;
        while (((o_bx != bx_before + 1) || (o_px < 1)) && (guard2 < 200)) begin
            @(posedge clk); guard2 = guard2 + 1;
        end
        b_arvalid = 1'b0; p_arvalid = 1'b0;
        repeat (4) @(posedge clk);
        if ((o_bx != bx_before + 1) || (o_px < 1)) begin
            $display("FAIL arb: starvation with simultaneous requests (b=%0d p=%0d, %0d cycles)",
                      o_bx, o_px, guard2);
            errors = errors + 1;
        end else begin
            $display("PASS arb: simultaneous requests both served (b=%0d p=%0d, %0d cycles)",
                      o_bx, o_px, guard2);
        end

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
module tb_brd_t1_top;
    localparam integer W       = 64;
    localparam integer H       = 48;
    localparam integer CAM_W   = 128;
    localparam integer CAM_H   = 96;
    localparam integer ROI_X   = 32;
    localparam integer ROI_Y   = 16;
    localparam integer NG      = (W * H) / 4;         // 768 groups per frame
    localparam integer SLOT_WORDS = 1024;
    localparam [31:0]  SLOT_BASE_WORD = 32'd2048;
    localparam integer SLOT_BASE_BYTES = 2048 * 32;   // 65536
    localparam integer DWORDS  = 16384;               // 512 KiB of DDR model
    localparam integer DWORDS_LOG = 14;
    localparam integer DUMP_BYTES = 8192;              // T1: slot bytes dumped for the python decoder

    integer SCEN;
    initial begin
        if (!$value$plusargs("SCEN=%d", SCEN)) SCEN = 0;
        $display("TB_SCEN=%0d", SCEN);
    end

    // T1 seqfix: emulate the minimum RTL fix (first capture_seq must differ from
    // the pusher's reset/ARM last_seq=0) by forcing the scheduler's first seq to 1.
    integer SEQ1;
    initial begin
        if (!$value$plusargs("SEQ1=%d", SEQ1)) SEQ1 = 1;
        $display("TB_SEQ1=%0d", SEQ1);
    end

    // ---- clocks ----
    reg cam_clk = 0, core_clk = 0, usr_clk = 0, tl_clk = 0;
    always #2.667 cam_clk  = ~cam_clk;   // 187.5 MHz
    always #3.333 core_clk = ~core_clk;  // 150.0 MHz
    always #5.000 usr_clk  = ~usr_clk;   // 100.0 MHz
    always #8.000 tl_clk   = ~tl_clk;    //  62.5 MHz

    // ---- camera model ----
    reg [39:0] cam_pix = 40'd0;
    reg        cam_pv = 0, cam_il = 0, cam_if = 0, cam_vs = 0;

    // ---- BAR register model ----
    reg  [31:0] cfg_cap_bytes = 32'h0004_0000;
    reg  [31:0] cfg_session   = 32'hA5A5_0001;
    reg  [31:0] cfg_dst_lo    = 32'h0100_0000;
    reg  [31:0] cfg_dst_hi    = 32'd0;
    reg  [31:0] cfg_db_lo     = 32'h0200_0000;
    reg  [31:0] cfg_db_hi     = 32'd0;
    reg         cfg_push_en   = 1'b1;
    reg         tx_arm = 0, tx_ack = 0, tx_cancel = 0;
    reg  [31:0] tx_ack_seq = 0, tx_ack_sess = 0;

    // ---- DUT ----
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
    wire        utx_sel, utx_req, utx_sop, utx_eop;
    wire [255:0] utx_data;
    wire [7:0]  utx_valid;
    wire        arb_owner;
    wire [31:0] arb_late, arb_switch, desc_active, slot_busy, arm_seq_c;

    // reset for the three synchronous domains (the board top does async assert /
    // sync release; the TB only has to release them in order).  Declared before
    // the DUT because Verilog needs the declaration to precede the use.
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
        .cfg_p4_desc_owner(1'b1), .cfg_mode(3'd0), .cfg_prep(1'b1), .cfg_pred(1'b1),
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

    // reset release sequence
    initial begin
        repeat (20) @(posedge core_clk);
        rst_core_cnt <= 4'hF;
        rst_cam_cnt  <= 4'hF;
        repeat (20) @(posedge tl_clk);
        rst_tl_cnt <= 4'hF;
        repeat (20) @(posedge usr_clk);
        rst_usr_cnt <= 4'hF;
    end

    // ---- DDR slave model ----
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
    integer     beat_idx = 0;
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

    task process_tlp;
        begin
            // DW0[9:0] = length in DW; DW2/DW3 = 64 bit address (low/high)
            if (dw_all[0][9:0] == 10'd1) begin
                // doorbell
                db_cnt = db_cnt + 1;
                db_payload = dw_all[4];
                if ({dw_all[3], dw_all[2]} != {cfg_db_hi, cfg_db_lo}) begin
                    $display("FAIL tlp: doorbell address %h != %h", {dw_all[3], dw_all[2]}, {cfg_db_hi, cfg_db_lo});
                    err_tlp = err_tlp + 1;
                end
            end else begin
                tlp_cnt = tlp_cnt + 1;
                exp_addr = cfg_dst_lo + tlp_cnt * 32'd128 - 32'd128;
                if ({dw_all[3], dw_all[2]} != {cfg_dst_hi, exp_addr}) begin
                    if (err_tlp < 4) $display("FAIL tlp: addr %h != %h", {dw_all[3], dw_all[2]}, {cfg_dst_hi, exp_addr});
                    err_tlp = err_tlp + 1;
                end
                if (tlp_cnt == 1) first_addr = dw_all[2];
                last_addr = dw_all[2];
                if (dw_all[0][9:0] != 10'd32) begin
                    if (err_tlp < 4) $display("FAIL tlp: length %0d != 32", dw_all[0][9:0]);
                    err_tlp = err_tlp + 1;
                end
                // payload DW 4..35 must equal the DDR slot bytes for this 128B block
                for (j = 0; j < 32; j = j + 1) begin
                    for (b = 0; b < 4; b = b + 1) begin
                        be_cnt = be_cnt + 1;
                        if (dw_all[4+j][8*b +: 8] !==
                            u_mem.mem[(SLOT_BASE_BYTES + (tlp_cnt-1)*128 + j*4 + b) >> 5]
                                      [((SLOT_BASE_BYTES + (tlp_cnt-1)*128 + j*4 + b) % 32)*8 +: 8]) begin
                            if (mism < 4) $display("MISMATCH tlp %0d byte %0d: got %h exp %h",
                                tlp_cnt-1, j*4+b,
                                dw_all[4+j][8*b +: 8],
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
        if (utx_sel && utx_req) begin
            if (utx_sop) beat_idx = 0;
            for (k = 0; k < 8; k = k + 1) dw_all[beat_idx*8 + k] = utx_data[k*32 +: 32];
            beat_idx = beat_idx + 1;
            if (utx_eop) process_tlp;
        end
    end

    // -----------------------------------------------------------------------
    // T1 independent evidence: P4 status + egress state + DDR slot raw bytes
    // (decoded later by python zlib, not by the developer's scripts)
    // -----------------------------------------------------------------------
    integer dfd, di;
    reg [1023:0] dump_dir, dump_path;

    task dump_slot;
        begin
            if (!$value$plusargs("SAMPLE_DIR=%s", dump_dir)) dump_dir = ".";
            $sformat(dump_path, "%0s/t1_slot_scen%0d.bin", dump_dir, SCEN);
            dfd = $fopen(dump_path, "wb");
            if (dfd == 0) begin
                $display("T1_DUMP_OPEN_FAIL %0s", dump_path);
            end else begin
                for (di = 0; di < DUMP_BYTES; di = di + 1) begin
                    $fwrite(dfd, "%c", u_mem.mem[(SLOT_BASE_BYTES + di) >> 5]
                              [((SLOT_BASE_BYTES + di) % 32)*8 +: 8]);
                end
                $fclose(dfd);
                $display("T1_DUMP_WRITTEN %0s bytes=%0d", dump_path, DUMP_BYTES);
            end
            $display("T1_P4 raw_len=%0d xform_len=%0d stream_len=%0d committed=%0d published=%0d exported=%0d drain=%0d",
                     u_dut.u_p4.st_raw_len, u_dut.u_p4.st_xform_len, u_dut.u_p4.st_stream_len,
                     u_dut.u_p4.st_frames_committed, u_dut.u_p4.st_store_published,
                     u_dut.u_p4.st_exported, u_dut.u_p4.st_drain_words);
            $display("T1_P4 crc raw=%h xform=%h stream=%h p1_good=%0d p1_abort=%0d cfg_err=%0d",
                     u_dut.u_p4.st_raw_crc, u_dut.u_p4.st_xform_crc, u_dut.u_p4.st_stream_crc,
                     u_dut.u_p4.st_p1_good, u_dut.u_p4.st_p1_abort, u_dut.u_p4.st_cfg_error);
            $display("T1_EG state=%0d desc_ok=%b err=%0d held_len=%0d exported=%0d busy=%b held=%b",
                     u_dut.u_p4.u_egress.state, u_dut.u_p4.u_egress.desc_ok,
                     u_dut.u_p4.u_egress.st_err, u_dut.u_p4.u_egress.held_stream_len,
                     u_dut.u_p4.u_egress.st_exported, u_dut.u_p4.u_egress.st_busy,
                     u_dut.u_p4.u_egress.st_held);
            $display("T1_EGIN push_en=%b cap=%h sess=%h mps=%0d link=%b dst=%h db=%h",
                     u_dut.u_p4.push_en, u_dut.u_p4.cap_bytes, u_dut.u_p4.session_id,
                     u_dut.u_p4.mps_code, u_dut.u_p4.link_up, u_dut.u_p4.dst_base,
                     u_dut.u_p4.db_addr);
            $display("T1_EGIN2 pub_len=%0d pub_id=%0d slot_base_word=%0d SLOT_BYTES=%0d",
                     u_dut.u_p4.pub_len, u_dut.u_p4.pub_id,
                     SLOT_BASE_WORD, 1024*32);
            $display("T1_HS pub=%0d egress_arm=%0d desc_o_arm=%0d", pub_cnt, egress_arm_cnt, darm_cnt);
            $display("T1_DESC m_frame_bytes=%0d m_capture_seq=%0d m_slot_base_bytes=%0d m_session=%h",
                     u_dut.m_frame_bytes, u_dut.m_capture_seq, u_dut.m_slot_base_bytes,
                     u_dut.m_session_id);
            $display("T1_PUSH state=%0d err=%h done=%0d tlp=%0d status=%h push_err=%h block_cfg=%b",
                     u_dut.u_pusher.p_st, u_dut.u_pusher.st_err, push_done, push_tlp,
                     push_status, push_err, tx_block_cfg);
        end
    endtask

    // X/Z monitor on the egress buses after all resets are released
    integer x_hits = 0;
    always @(posedge tl_clk) begin
        if (rst_tl_n && rst_core_n && rst_usr_n && rst_cam_n) begin
            if (utx_valid && (^{utx_data, utx_sop, utx_eop, utx_req} === 1'bx)) x_hits = x_hits + 1;
            if (ddr_awvalid && (^{ddr_awaddr, ddr_wdata, ddr_wstrb} === 1'bx)) x_hits = x_hits + 1;
            if (ddr_wvalid && (^{ddr_wdata, ddr_wstrb, ddr_wlast} === 1'bx)) x_hits = x_hits + 1;
            if (ddr_arvalid && (^ddr_araddr === 1'bx)) x_hits = x_hits + 1;
            if (ddr_rvalid && (^{ddr_rdata, ddr_rlast} === 1'bx)) x_hits = x_hits + 1;
        end
    end

    // T1 probes: handshake counters for the descriptor mailbox and the egress arm
    integer darm_cnt = 0, egress_arm_cnt = 0, pub_cnt = 0;
    always @(posedge core_clk) begin
        if (u_dut.u_p4.u_egress.arm_pulse) egress_arm_cnt = egress_arm_cnt + 1;
        if (u_dut.u_p4.pub_pulse)          pub_cnt = pub_cnt + 1;
    end
    always @(posedge tl_clk) if (u_dut.u_desc.o_arm) darm_cnt = darm_cnt + 1;

    // -----------------------------------------------------------------------
    // stimulus
    // -----------------------------------------------------------------------
    integer line, grp, i;
    integer tlp_at_arm = 0;
    integer desc_hs_cnt = 0;

    always @(posedge core_clk) if (u_dut.b_desc_hs) desc_hs_cnt = desc_hs_cnt + 1;
    integer rel_before;
    integer guard;

    initial begin
        wait (rst_core_n && rst_tl_n && rst_usr_n && rst_cam_n);
        if (SEQ1) force u_dut.b_seq = 32'd1;
        repeat (50) @(posedge tl_clk);
        tx_arm <= 1'b1;
        @(posedge tl_clk);
        tx_arm <= 1'b0;
        repeat (20) @(posedge tl_clk);
        cam_if = 0; cam_il = 0; cam_pv = 0; cam_vs = 0;

        // ---- one 64x48 ROI frame out of a 128x96 sensor raster ----
        cam_vs <= 1'b1; @(posedge cam_clk); cam_vs <= 1'b0;
        @(posedge cam_clk); cam_if <= 1'b1;
        for (line = 0; line < (ROI_Y + H); line = line + 1) begin
            @(posedge cam_clk); cam_il <= 1'b1;
            @(posedge cam_clk); cam_il <= 1'b0;
            for (grp = 0; grp < (CAM_W/4); grp = grp + 1) begin
                if (!((SCEN == 1) && (line == (ROI_Y + H - 1)) && (grp == (CAM_W/4 - 1)))) begin
                    cam_pv  <= 1'b1;
                    cam_pix <= {4{(line*32 + grp) & 10'h3FF}};
                end
                @(posedge cam_clk);
                cam_pv <= 1'b0;
            end
        end
        @(posedge cam_clk); cam_if <= 1'b0;

        // ---- wait for the datapath to publish a frame ----
        guard = 0;
        while ((u_dut.u_p4.st_store_published == 32'd0) && (guard < 400000)) begin
            @(posedge tl_clk); guard = guard + 1;
        end
        $display("INFO: published=%0d after %0d tl cycles (SCEN=%0d)", u_dut.u_p4.st_store_published, guard, SCEN);
        $display("DBG fe_b frames=%0d groups=%0d abort=%0d ovf=%0d fifo_valid=%b row=%0d",
                 u_dut.u_fe_b.frame_cnt, u_dut.u_fe_b.c_groups, u_dut.u_fe_b.abort_cnt,
                 u_dut.u_fe_b.fifo_ovf_cnt, u_dut.u_fe_b.fifo_valid, u_dut.u_fe_b.row_cnt);
        $display("DBG p4 acc=%0d comp=%0d fail=%0d rej=%0d admit=%0d committed=%0d exported=%0d pub=%0d p1g=%0d p1a=%0d cfgerr=%0d",
                 u_dut.u_p4.st_sched_accepted, u_dut.u_p4.st_sched_completed, u_dut.u_p4.st_sched_failed,
                 u_dut.u_p4.st_sched_rejected, u_dut.u_p4.st_admit_count, u_dut.u_p4.st_frames_committed,
                 u_dut.u_p4.st_exported, u_dut.u_p4.st_store_published, u_dut.u_p4.st_p1_good,
                 u_dut.u_p4.st_p1_abort, u_dut.u_p4.st_cfg_error);
        $display("DBG desc active=%b hs=%0d arm=%b marshal=%0d", u_dut.b_desc_active, desc_hs_cnt,
                 u_dut.desc_arm, u_dut.u_p4.st_drain_words);
        dump_slot;

        if (SCEN == 1) begin
            // a frame without EOF must never arm and must never export
            repeat (4000) @(posedge tl_clk);
            if (arm_seq_c != 32'd0) begin
                $display("FAIL neg1: frame without EOF was armed (arm_seq=%0d)", arm_seq_c); $finish;
            end
            if (push_done != 32'd0 || tlp_cnt != 0) begin
                $display("FAIL neg1: partial frame exported (done=%0d tlp=%0d)", push_done, tlp_cnt); $finish;
            end
            // T1: the real discriminator -- no EOF must also mean no commit/publish
            if (u_dut.u_p4.st_frames_committed != 32'd0 || u_dut.u_p4.st_store_published != 32'd0) begin
                $display("FAIL neg1: incomplete frame was committed/published (committed=%0d published=%0d)",
                          u_dut.u_p4.st_frames_committed, u_dut.u_p4.st_store_published);
                $display("NEG1_RESULT=FAIL"); $finish;
            end
            $display("PASS neg1: no EOF -> not armed, not committed, not published, nothing exported");
            $display("NEG1_RESULT=PASS");
            $finish;
        end

        // ---- host ARM was issued before the frame (T1 seqfix) ----
        // wait for the doorbell (export complete)
        guard = 0;
        while ((db_cnt == 0) && (guard < 400000)) begin
            @(posedge tl_clk); guard = guard + 1;
        end
        repeat (200) @(posedge tl_clk);

        // ---- positive checks ----
        if (SCEN == 0) begin
            $display("T1_X HITS=%0d", x_hits);
            if (x_hits != 0) begin
                $display("FAIL pos: X/Z seen on the TLP/DDR buses (%0d samples)", x_hits);
                $display("POS_RESULT=FAIL"); $finish;
            end
            if (tlp_cnt == 0 || db_cnt == 0) begin
                $display("FAIL pos: no export (tlp=%0d db=%0d done=%0d status=%h err=%h)",
                          tlp_cnt, db_cnt, push_done, push_status, push_err);
                $display("POS_RESULT=FAIL");
                $finish;
            end
            if (mism != 0) begin
                $display("FAIL pos: %0d payload bytes differ from the DDR slot", mism);
                $display("POS_RESULT=FAIL");
                $finish;
            end
            if (err_tlp != 0) begin
                $display("FAIL pos: %0d TLP header errors", err_tlp);
                $display("POS_RESULT=FAIL");
                $finish;
            end
            if (db_payload != 32'd1) begin
                $display("FAIL pos: doorbell payload %h != 1", db_payload);
                $display("POS_RESULT=FAIL");
                $finish;
            end
            $display("INFO: exported %0d MWr TLPs, %0d payload bytes, doorbell=%h first=%h last=%h",
                      tlp_cnt, be_cnt, db_payload, first_addr, last_addr);
            $display("POS_RESULT=PASS tlps=%0d bytes=%0d", tlp_cnt, be_cnt);

            // ---- the frame must still be held until the host ACKs ----
            rel_before = p4_st[15:8];
            repeat (2000) @(posedge tl_clk);
            if (p4_st[15:8] !== rel_before[7:0] + 0 && desc_active != 1'b1) begin
                $display("WARN: release counter moved before ACK (st=%h active=%b)", p4_st, desc_active);
            end
            $display("INFO: before ACK desc_active=%b rel_cnt=%0d held=%b", desc_active, p4_st[15:8], tx_status[1]);

            // ---- correct ACK releases the slot ----
            @(posedge tl_clk);
            tx_ack_seq  <= u_dut.u_pusher.held_seq;
            tx_ack_sess <= cfg_session;
            tx_ack      <= 1'b1;
            @(posedge tl_clk);
            tx_ack      <= 1'b0;
            guard = 0;
            while ((desc_active == 1'b1) && (guard < 100000)) begin
                @(posedge tl_clk); guard = guard + 1;
            end
            if (desc_active == 1'b1) begin
                $display("FAIL pos: correct ACK did not release the slot (%0d cycles)", guard);
                $display("POS_RESULT=FAIL");
            end else begin
                $display("PASS pos: correct ACK released the slot after %0d cycles", guard);
                $display("POS_RESULT=PASS_ACK");
            end
            $finish;
        end

        // ---- SCEN 2: wrong ACK must not release ----
        if (SCEN == 2) begin
            rel_before = p4_st[15:8];
            @(posedge tl_clk);
            tx_ack_seq  <= u_dut.u_pusher.held_seq ^ 32'h1;   // wrong sequence
            tx_ack_sess <= cfg_session;
            tx_ack      <= 1'b1;
            @(posedge tl_clk);
            tx_ack      <= 1'b0;
            repeat (8000) @(posedge tl_clk);
            if (desc_active !== 1'b1) begin
                $display("FAIL neg2: wrong ACK released the slot"); $display("NEG2_RESULT=FAIL"); $finish;
            end
            if (p4_st[15:8] !== rel_before[7:0]) begin
                $display("FAIL neg2: release counter advanced %0d -> %0d", rel_before, p4_st[15:8]);
                $display("NEG2_RESULT=FAIL"); $finish;
            end
            $display("PASS neg2: wrong ACK did not release the slot (desc_active=1, rel_cnt=%0d)", p4_st[15:8]);

            // correct ACK then releases
            @(posedge tl_clk);
            tx_ack_seq  <= u_dut.u_pusher.held_seq;
            tx_ack_sess <= cfg_session;
            tx_ack      <= 1'b1;
            @(posedge tl_clk);
            tx_ack      <= 1'b0;
            guard = 0;
            while ((desc_active == 1'b1) && (guard < 100000)) begin
                @(posedge tl_clk); guard = guard + 1;
            end
            if (desc_active !== 1'b0) begin
                $display("FAIL neg2: correct ACK after the wrong one did not release");
                $display("NEG2_RESULT=FAIL");
            end else begin
                $display("PASS neg2: matching ACK still releases after a rejected one");
                $display("NEG2_RESULT=PASS");
            end
            $finish;
        end
    end

    // ---- global watchdog ----
    initial begin
        #40000000;
        $display("RESULT=FAIL timeout");
        $finish;
    end
endmodule
