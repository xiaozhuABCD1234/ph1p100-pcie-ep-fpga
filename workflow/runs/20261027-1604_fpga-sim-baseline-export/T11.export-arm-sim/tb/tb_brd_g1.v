`timescale 1ns/1ps
// =============================================================================
// tb_brd_g1.v -- T11.export-arm-sim G1 simulation (derived from the r0
// T11.BRD.P1 tb_brd_g1.v; the historical tb_brd_arb unit test is NOT carried
// over -- see result-r0.md "derived-testbench" note).
//
// Harness: brd_board_datapath (DUT, unchanged) + camera stimulus + DDR AXI
// slave model + TLP host model + BAR register model.
//   tb_brd_g1_top  : scaled board datapath, +SCEN=0 (3 frames) / 1 (no EOF)
//                    / 2 (wrong ACK) / 3 (3 frames with host+DDR backpressure)
//   tb_brd_neg_base: same harness, SLOT_BASE_WORD=2049 -> non-4KiB-aligned base
//                    must be rejected (no MWr / no doorbell)
//   tb_brd_neg_cap : same harness, DDR_CAP_BYTES too small for base+frame_bytes
//                    must be rejected (no MWr / no doorbell)
//
// Geometry is scaled (ROI 64x48, camera 128x96) but the RTL path is the same
// brd_board_datapath that the board top instantiates: a1_raw_crop -> 43b pack ->
// capture_async_fifo -> integrated_delivery_top (P4) -> p2_ddr_bridge ->
// brd_ddr_rd_arb <-> ddr_frame_pusher -> TLP.
// =============================================================================

// ---------------------------------------------------------------------------
// DDR3 AXI4 slave model (byte addressed, 256 bit, single write beat, INCR read)
// `stall` stretches both channels so the DUT sees a slow DDR (backpressure).
// ---------------------------------------------------------------------------
module brd_ddr_slave_model #(
    parameter integer DWORDS = 8192,
    parameter integer DWORDS_LOG = 13
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         stall,
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
            if (awvalid && !aw_pending && !bvalid && !stall) begin
                awready    <= 1'b1;
                aw_pending <= 1'b1;
                aw_addr_q  <= awaddr;
            end
            if (aw_pending && wvalid && !stall) begin
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
            if (arvalid && !rd_busy && !stall) begin
                arready   <= 1'b1;
                rd_busy   <= 1'b1;
                rd_addr_q <= araddr;
                rd_left   <= arlen;
                rid       <= arid;
                rd_bursts <= rd_bursts + 32'd1;
            end else if (rd_busy) begin
                if (!stall && (!rvalid || rready)) begin
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
// shared scaled-board harness
// ---------------------------------------------------------------------------
module brd_g1_harness #(
    parameter integer BASEW = 2048,
    parameter integer CAPB  = 1048576,
    parameter integer IS_NEG = 0,
    parameter integer NEGID  = 0
) ();
    localparam integer W       = 64;
    localparam integer H       = 48;
    localparam integer CAM_W   = 128;
    localparam integer CAM_H   = 96;
    localparam integer ROI_X   = 32;
    localparam integer ROI_Y   = 16;
    localparam integer SLOT_WORDS = 1024;
    localparam [31:0]  SLOT_BASE_WORD = BASEW;
    localparam integer DWORDS  = 16384;
    localparam integer DWORDS_LOG = 14;

    integer SCEN;
    integer NF;
    initial begin
        if (!$value$plusargs("SCEN=%d", SCEN)) SCEN = 0;
        if (!$value$plusargs("NF=%d", NF)) begin
            if (SCEN == 0 || SCEN == 3) NF = 3; else NF = 1;
        end
        $display("TB_SCEN=%0d NF=%0d BASEW=%0d CAPB=%0d IS_NEG=%0d", SCEN, NF, BASEW, CAPB, IS_NEG);
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
    reg         tl_wait = 0;
    reg         ddr_stall = 0;

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
        .DDR_CAP_BYTES(CAPB)
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

        .tl_tx_wait(tl_wait),
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

    // ---- DDR slave model ----
    wire [31:0] dm_wr_beats, dm_rd_bursts, dm_rd_beats;

    brd_ddr_slave_model #(.DWORDS(DWORDS), .DWORDS_LOG(DWORDS_LOG)) u_mem (
        .clk(usr_clk), .rst_n(rst_usr_n), .stall(ddr_stall),
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
    // TLP host model: 4DW MWr header + 32 DW payload, doorbell = 1 DW
    // -----------------------------------------------------------------------
    reg  [31:0] dw_all [0:63];
    integer     beat_idx = 0;
    integer     tlp_f, db_f, cmp_bytes, mism_bytes, err_hdr;
    reg  [31:0] db_val;
    reg  [31:0] ex_bytes, slot_bytes, seq_f, slotw;
    integer     j, b, baddr;
    reg  [31:0] exp_addr;
    reg  [7:0]  got_b, exp_b;

    initial begin
        tlp_f = 0; db_f = 0; cmp_bytes = 0; mism_bytes = 0; err_hdr = 0;
        db_val = 32'd0; ex_bytes = 32'd0; slot_bytes = 32'd0; seq_f = 32'd0; slotw = 32'd0;
    end

    integer     beat_in_tlp = 0;
    integer     base_tlp = 0;
    integer     n = 0;

    // ---- address probe: where do the store writes land, where does the pusher read? ----
    integer awdbg = 0, ardbg = 0;
    always @(posedge usr_clk) begin
        if (u_dut.ddr_awvalid && u_dut.ddr_awready) begin
            if (awdbg < 8) $display("AWDBG t=%0t addr=%h data0=%h strb=%h", $time, u_dut.ddr_awaddr, u_dut.ddr_wdata[7:0], u_dut.ddr_wstrb);
            awdbg <= awdbg + 1;
        end
        if (u_dut.ddr_arvalid && u_dut.ddr_arready) begin
            if (ardbg < 4) $display("ARDBG t=%0t addr=%h len=%0d", $time, u_dut.ddr_araddr, u_dut.ddr_arlen);
            ardbg <= ardbg + 1;
        end
    end

    // ---- independent baseline: capture the compressed stream where the DUT writes it ----
    // expbuf holds the bytes as produced by the compression core (store write side), so
    // the TLP payload comparison no longer uses the same DDR memory the pusher reads.
    integer cap_f = 0, cap_total = 0, cur_cap = 0, cap_sel = 0, sb = 0;
    integer cap_end [0:7];
    integer cb0 = 0, elen = 0;
    integer cap_base [0:7];
    integer cap_len  [0:7];
    reg [7:0] expbuf [0:16383];
    always @(posedge core_clk) begin
        // frame boundaries are taken at pub_pulse (one publish per finished frame);
        // wr_begin/core_commit keyed windows missed or shifted frame 2, so the publish
        // event marks the exact end of each frame stream.
        if (u_dut.u_p4.pub_pulse) begin
            cap_end[cap_f] = cap_total;
            cap_f          = cap_f + 1;
        end
        if (u_dut.u_p4.core_out_valid) begin
            for (sb = 0; sb < 4; sb = sb + 1) begin
                if (u_dut.u_p4.core_out_keep[sb]) begin
                    expbuf[cap_total] = u_dut.u_p4.core_out_data[8*sb +: 8];
                    cap_total = cap_total + 1;
                end
            end
        end
    end

    task process_tlp;
        begin
            // pusher beat packing (ddr_frame_pusher.v L566-570):
            //   k==0: utx_data = {hdr_dw0, hdr_dw1, hdr_dw2, hdr_dw3, 128'd0} -> header DWs
            //         sit in the HIGH half, i.e. dw_all[7]=hdr_dw0 .. dw_all[4]=hdr_dw3
            //   k>=1: payload beat (low DW first) -> payload starts at dw_all[8]
            //   doorbell: {db_dw0..3, bswap32(db_val), 96'd0} -> db_val at dw_all[3]
            if (beat_in_tlp == 1) begin
                db_f   = db_f + 1;
                db_val = {dw_all[3][7:0], dw_all[3][15:8], dw_all[3][23:16], dw_all[3][31:24]};
                if ({dw_all[5], dw_all[4]} != {cfg_db_hi, cfg_db_lo}) begin
                    $display("FAIL tlp: doorbell address %h != %h", {dw_all[5], dw_all[4]}, {cfg_db_hi, cfg_db_lo});
                    err_hdr = err_hdr + 1;
                end
            end else begin
                tlp_f = tlp_f + 1;
                n = tlp_f - base_tlp;   // per-frame TLP index: every frame restarts at cfg_dst_lo
                if (dw_all[7][9:0] != 10'd32) begin
                    if (err_hdr < 4) $display("FAIL tlp: length %0d != 32", dw_all[7][9:0]);
                    err_hdr = err_hdr + 1;
                end
                exp_addr = cfg_dst_lo + n * 32'd128 - 32'd128;
                if ({dw_all[5], dw_all[4]} != {cfg_dst_hi, exp_addr}) begin
                    if (err_hdr < 4) $display("FAIL tlp: addr %h != %h (frame idx %0d)", {dw_all[5], dw_all[4]}, {cfg_dst_hi, exp_addr}, n);
                    err_hdr = err_hdr + 1;
                end
                // payload vs DDR slot, only the first ex_bytes bytes (exact payload)
                for (j = 0; j < 32; j = j + 1) begin
                    for (b = 0; b < 4; b = b + 1) begin
                        if (((n-1)*128 + j*4 + b) < ex_bytes) begin
                            got_b = dw_all[8+j][8*b +: 8];
                            baddr = slot_bytes + (n-1)*128 + j*4 + b;
                            exp_b = expbuf[cb0 + (n-1)*128 + j*4 + b];
                            cmp_bytes = cmp_bytes + 1;
                            if (got_b !== exp_b) begin
                                if (mism_bytes < 4) $display("MISMATCH tlp %0d byte %0d: got %h exp %h",
                                    tlp_f-1, j*4+b, got_b, exp_b);
                                mism_bytes = mism_bytes + 1;
                            end
                        end
                    end
                end
            end
        end
    endtask

    integer     x_cnt = 0;
    always @(posedge tl_clk) begin
        if (utx_valid != 8'h00) begin
            if ((^utx_data) === 1'bx) x_cnt = x_cnt + 1;
        end
        if ((^u_dut.u_p4.st_frames_committed) === 1'bx) x_cnt = x_cnt + 1;
    end

    integer REQ;
    initial begin
        if (!$value$plusargs("REQ=%d", REQ)) begin
            if (SCEN == 0 || SCEN == 3) REQ = NF - 1; else REQ = 0;
        end
        $display("TB_REQ=%0d", REQ);
    end
    function integer pos_verdict;
        input integer ok;
        input integer fail;
        input integer req;
        begin
            pos_verdict = ((fail == 0) && (req > 0) && (ok == req)) ? 1 : 0;
        end
    endfunction

    integer     rawcnt = 0;
    reg         ack_rel_seen = 0;
    integer     xack_cnt = 0;
    always @(posedge core_clk) if (u_dut.x_ack) xack_cnt <= xack_cnt + 1;
    always @(posedge core_clk) if (u_dut.u_p4.slot_release) ack_rel_seen <= 1'b1;
    always @(posedge tl_clk) begin
        if (utx_sel && utx_req && (utx_valid != 8'h00)) begin
            if (utx_sop) begin
                beat_idx = 0; beat_in_tlp = 0;
                if (rawcnt < 2) begin
                    rawcnt = rawcnt + 1;
                    $display("RAW_SOP t=%0t MSB..LSB = %h %h %h %h %h %h %h %h",
                             $time, utx_data[255:224], utx_data[223:192], utx_data[191:160],
                             utx_data[159:128], utx_data[127:96], utx_data[95:64],
                             utx_data[63:32], utx_data[31:0]);
                end
            end
            beat_in_tlp = beat_in_tlp + 1;
            dw_all[beat_idx*8 + 0] = utx_data[31:0];
            dw_all[beat_idx*8 + 1] = utx_data[63:32];
            dw_all[beat_idx*8 + 2] = utx_data[95:64];
            dw_all[beat_idx*8 + 3] = utx_data[127:96];
            dw_all[beat_idx*8 + 4] = utx_data[159:128];
            dw_all[beat_idx*8 + 5] = utx_data[191:160];
            dw_all[beat_idx*8 + 6] = utx_data[223:192];
            dw_all[beat_idx*8 + 7] = utx_data[255:224];
            beat_idx = beat_idx + 1;
            if (utx_eop) process_tlp;
        end
    end

    // -----------------------------------------------------------------------
    // read-only observation monitors
    // -----------------------------------------------------------------------
    integer desc_hs_cnt = 0;
    always @(posedge core_clk) if (u_dut.b_desc_hs) desc_hs_cnt = desc_hs_cnt + 1;

    always @(posedge tl_clk) if (u_dut.u_desc.o_arm)
        $display("DESC_VALID t=%0t seq=%0d base_w=%0d fbytes=%0d slen=%0d cap=%h sess=%h ident=%b",
                 $time, u_dut.u_desc.o_capture_seq, u_dut.u_desc.o_slot_base_word,
                 u_dut.u_desc.o_frame_bytes, u_dut.u_desc.o_stream_len,
                 u_dut.u_desc.o_cap_bytes, u_dut.u_desc.o_session_id, u_dut.u_desc.o_ident_valid);

    reg [3:0] g_st_q = 4'hF;
    always @(posedge tl_clk) if (u_dut.u_pusher.g_st != g_st_q) begin
        g_st_q <= u_dut.u_pusher.g_st;
        $display("PUSH_G t=%0t g_st=%0d ddr_seq=%0d ddr_base=%0d fbytes=%0d claim=%b cb=%b cd=%b",
                 $time, u_dut.u_pusher.g_st, u_dut.u_pusher.ddr_seq, u_dut.u_pusher.ddr_base,
                 u_dut.u_pusher.frame_bytes, u_dut.u_pusher.claim,
                 u_dut.u_pusher.claim_base_ok, u_dut.u_pusher.claim_desc_ok);
    end

    // ---- D3 three-way probe: AR issued? R returned? consumer advanced? ----
    integer ar_hs = 0, ddr_r_hs = 0, pu_r_hs = 0, txdbg = 0;
    always @(posedge usr_clk) begin
        if (u_dut.u_pusher.m_axi_arvalid && u_dut.u_pusher.m_axi_arready) ar_hs     <= ar_hs + 1;
        if (u_dut.ddr_rvalid && u_dut.ddr_rready)                         ddr_r_hs <= ddr_r_hs + 1;
        if (u_dut.u_pusher.m_axi_rvalid && u_dut.u_pusher.m_axi_rready)   pu_r_hs  <= pu_r_hs + 1;
        if (u_dut.u_pusher.g_st == 3'd2) begin
            txdbg <= txdbg + 1;
            if ((txdbg % 400) == 0)
                $display("TXDBG t=%0t ar_hs=%0d ddrR_hs=%0d puR_hs=%0d owner=%b busy=%b p_arvalid=%b p_arready=%b m_arvalid=%b m_arready=%b m_rvalid=%b m_rready=%b mem_rd_busy=%b mem_rd_left=%0d p_st=%0d b_arvalid=%b",
                         $time, ar_hs, ddr_r_hs, pu_r_hs,
                         u_dut.u_arb.o_owner, u_dut.u_arb.o_busy,
                         u_dut.u_pusher.m_axi_arvalid, u_dut.u_pusher.m_axi_arready,
                         u_dut.u_arb.m_arvalid, u_dut.u_arb.m_arready,
                         u_dut.u_arb.m_rvalid, u_dut.u_arb.m_rready,
                         u_mem.rd_busy, u_mem.rd_left, u_dut.u_pusher.p_st,
                         u_dut.u_arb.b_arvalid);
        end
    end

    // -----------------------------------------------------------------------
    // backpressure generator (SCEN==3 only): host tl_tx_wait + slow DDR windows
    // -----------------------------------------------------------------------
    integer bp_cnt = 0;
    reg     bp_en = 0;
    always @(posedge tl_clk) begin
        if (bp_en) begin
            bp_cnt <= bp_cnt + 1;
            tl_wait  <= ((bp_cnt % 400) >= 120) && ((bp_cnt % 400) < 260);
            ddr_stall<= (((bp_cnt / 8) % 400) >= 100) && (((bp_cnt / 8) % 400) < 200);
        end else begin
            tl_wait   <= 1'b0;
            ddr_stall <= 1'b0;
        end
    end

    // -----------------------------------------------------------------------
    // stimulus
    // -----------------------------------------------------------------------
    integer line, grp, f, guard;
    integer tlp_prev, db_prev, rel_prev;
    integer frame_ok, frame_fail;
    reg [31:0] seq_prev;
    reg        drop_last;

    task cam_frame;
        input [9:0] seed;
        begin
            cam_vs <= 1'b1; @(posedge cam_clk); cam_vs <= 1'b0;
            @(posedge cam_clk); cam_if <= 1'b1;
            for (line = 0; line < (ROI_Y + H); line = line + 1) begin
                @(posedge cam_clk); cam_il <= 1'b1;
                @(posedge cam_clk); cam_il <= 1'b0;
                for (grp = 0; grp < (CAM_W/4); grp = grp + 1) begin
                    if (!(drop_last && (line == (ROI_Y + H - 1)) && (grp == (CAM_W/4 - 1)))) begin
                        cam_pv  <= 1'b1;
                        cam_pix <= {4{((line*32 + grp + seed) & 10'h3FF)}};
                    end
                    @(posedge cam_clk);
                    cam_pv <= 1'b0;
                end
            end
            @(posedge cam_clk); cam_if <= 1'b0;
        end
    endtask

    task pulse_arm;
        begin
            @(posedge tl_clk); tx_arm <= 1'b1;
            @(posedge tl_clk); tx_arm <= 1'b0;
        end
    endtask

    task pulse_ack;
        input [31:0] aseq;
        begin
            @(posedge tl_clk); tx_ack_seq <= aseq; tx_ack_sess <= cfg_session; tx_ack <= 1'b1;
            @(posedge tl_clk); tx_ack <= 1'b0;
        end
    endtask

    initial begin
        drop_last = 1'b0;
        seq_prev = 32'd0;
        frame_ok = 0; frame_fail = 0;
        rel_prev = 0;
        wait (rst_core_n === 1'b1 && rst_tl_n === 1'b1 && rst_usr_n === 1'b1 && rst_cam_n === 1'b1);
        repeat (200) @(posedge cam_clk);
        cam_if = 0; cam_il = 0; cam_pv = 0; cam_vs = 0;

        // ---- SCEN 1: frame without EOF must never arm/export ----
        if (SCEN == 1) begin
            drop_last = 1'b1;
            cam_frame(10'd1);
            repeat (60000) @(posedge tl_clk);
            if (arm_seq_c != 32'd0) begin
                $display("FAIL neg1: frame without EOF was armed (arm_seq=%0d)", arm_seq_c);
                $display("NEG1_RESULT=FAIL"); $finish;
            end
            if (push_done != 32'd0 || tlp_f != 0 || db_f != 0) begin
                $display("FAIL neg1: partial frame exported (done=%0d tlp=%0d db=%0d)", push_done, tlp_f, db_f);
                $display("NEG1_RESULT=FAIL"); $finish;
            end
            $display("PASS neg1: no EOF -> not armed, nothing exported (tlp=0 db=0)");
            $display("NEG1_RESULT=PASS");
            $finish;
        end

        // ---- SCEN 0 / 2 / 3 (and the IS_NEG wrappers) ----
        // pusher contract (ddr_frame_pusher): ARM latches the descriptor and sets
        // last_seq := current seq, i.e. "only frames published AFTER arm are
        // claimed"; arm_reject fires while frame_bytes==0.  A real host therefore
        // arms once the first descriptor is visible (that first frame is consumed
        // by the arm) and re-arms after every ACK, while frame_bytes still holds
        // the previous frame.  Frames 1.. are the exported ones.
        if (SCEN == 3) bp_en = 1'b1;
        for (f = 0; f < NF; f = f + 1) begin
            tlp_prev = tlp_f;
            base_tlp = tlp_f;
            cap_sel  = f;
            cb0      = (f == 0) ? 0 : cap_end[f-1];
            elen     = cap_end[f] - cb0;
            db_prev  = db_f;
            cam_frame(f * 10'd37);

            // wait for the P2 descriptor of this frame (capture_seq advances)
            guard = 0;
            while ((u_dut.u_desc.o_capture_seq == seq_prev) && (guard < 400000)) begin
                @(posedge tl_clk); guard = guard + 1;
            end
            if (u_dut.u_desc.o_capture_seq == seq_prev) begin
                $display("FAIL frame %0d: descriptor never delivered (guard=%0d)", f, guard);
                $display("ADMIT gs=%0d free_v=%b has_rdy=%b eg_busy=%b dr_busy=%b ap_busy=%b wr_started=%b cfg_dirty=%b admit_ok=%b slot_st=%h b_act=%b",
                         u_dut.u_p4.gs, u_dut.u_p4.store_free_valid, u_dut.u_p4.store_has_ready, u_dut.u_p4.egress_busy,
                         u_dut.u_p4.drain_busy, u_dut.u_p4.ap_st_busy, u_dut.u_p4.wr_started, u_dut.u_p4.cfg_dirty,
                         u_dut.u_p4.admit_ok, u_dut.u_p4.store_slot_st, u_dut.b_desc_active);
                $display("POS_RESULT=FAIL desc_timeout frame=%0d", f);
                $finish;
            end
            seq_f     = u_dut.u_desc.o_capture_seq;
            seq_prev  = seq_f;
            ex_bytes  = u_dut.u_desc.o_stream_len;
            slotw     = u_dut.u_desc.o_slot_base_word;
            slot_bytes= slotw * 32;
            $display("INFO frame=%0d seq=%0d slot_word=%0d base_bytes=%0d exact_bytes=%0d",
                     f, seq_f, slotw, slot_bytes, ex_bytes);

            if (f == 0) begin
                // arming frame: the ARM consumes this descriptor, no MWr expected
                pulse_arm;
                repeat (2000) @(posedge tl_clk);
                if (db_f != db_prev) begin
                    $display("FAIL frame 0: the arming frame must not be exported (db=%0d)", db_f - db_prev);
                    $display("POS_RESULT=FAIL arming_frame_exported");
                    $finish;
                end
                // the integration watchdog drains and releases the slot
                guard = 0;
                while ((u_dut.u_p4.st_release_count == rel_prev) && (guard < 400000)) begin
                    @(posedge tl_clk); guard = guard + 1;
                end
                if (u_dut.u_p4.st_release_count == rel_prev) begin
                    $display("FAIL frame 0: arming frame slot never released (guard=%0d)", guard);
                    $display("DBG arm gs=%0d dr=%0d wd_en=%b wd_cnt=%0d rel_valid=%b rel_cam=%b active_cam=%b b_act=%b a_act=%b slot_rel=%b eg=%0d pub_pulse=%b",
                             u_dut.u_p4.gs, u_dut.u_p4.dr, u_dut.u_p4.wd_en, u_dut.u_p4.wd_cnt,
                             u_dut.u_p4.rel_valid, u_dut.u_p4.rel_camera_id, u_dut.u_p4.active_cam,
                             u_dut.b_desc_active, u_dut.a_desc_active, u_dut.u_p4.slot_release,
                             u_dut.u_p4.u_egress.state, u_dut.u_p4.pub_pulse);
                    $display("POS_RESULT=FAIL arming_slot_pinned");
                    $finish;
                end
                rel_prev = u_dut.u_p4.st_release_count;
                $display("INFO frame=0 arming frame consumed, slot freed after %0d tl cycles (rel_count=%0d)", guard, rel_prev);
            end else begin
                // wait for the doorbell of this frame
                guard = 0;
                while ((db_f == db_prev) && (guard < 400000)) begin
                    @(posedge tl_clk); guard = guard + 1;
                end
                if (db_f == db_prev) begin
                    $display("FAIL frame %0d: no export (tlp=%0d db=%0d done=%0d status=%h err=%h active=%b cb=%b)",
                             f, tlp_f - tlp_prev, db_f - db_prev, push_done, push_status, push_err,
                             desc_active, u_dut.u_pusher.claim_base_ok);
                    $display("PAYLOAD_COMPARE frame=%0d seq=%0d exact_bytes=%0d compared=%0d mismatch=%0d tlps=%0d doorbell=%0d NOT_EXECUTED=1",
                             f, seq_f, ex_bytes, cmp_bytes, mism_bytes, tlp_f - tlp_prev, db_f - db_prev);
                    if (IS_NEG != 0) begin
                        $display("PASS neg: illegal descriptor rejected (no MWr, no doorbell)");
                        $display("NEG_RESULT=PASS frame=%0d", f);
                        $display("POS_RESULT=NEG_PASS id=%0d", NEGID);
                        #2000;
                        $finish;
                    end
                    $display("POS_RESULT=FAIL no_export frame=%0d", f);
                    $finish;
                end
                repeat (40) @(posedge tl_clk);

                $display("PAYLOAD_COMPARE frame=%0d seq=%0d slot_word=%0d exact_bytes=%0d compared=%0d mismatch=%0d tlps=%0d doorbell=%0d db_val=%0d hdr_err=%0d",
                         f, seq_f, slotw, ex_bytes, cmp_bytes, mism_bytes, tlp_f - tlp_prev, db_f - db_prev, db_val, err_hdr);
                if ((cmp_bytes == ex_bytes) && (ex_bytes > 0) && (mism_bytes == 0) &&
                    ((tlp_f - tlp_prev) > 0) && ((db_f - db_prev) == 1) && (err_hdr == 0)) begin
                    frame_ok = frame_ok + 1;
                    $display("FRAME_RESULT frame=%0d PASS", f);
                end else begin
                    frame_fail = frame_fail + 1;
                    $display("FRAME_RESULT frame=%0d FAIL (compared=%0d exact=%0d mismatch=%0d tlps=%0d db=%0d hdr=%0d)",
                             f, cmp_bytes, ex_bytes, mism_bytes, tlp_f - tlp_prev, db_f - db_prev, err_hdr);
                end
                $display("E9 baseline_source=store_write_side frame=%0d exp_len=%0d exact_bytes=%0d extra=%0d",
                         f, elen, ex_bytes, (elen - ex_bytes));
                $display("MEMDBG mem[2048]=%h mem[2049]=%h mem[8192]=%h mem[8193]=%h", u_mem.mem[2048], u_mem.mem[2049], u_mem.mem[8192], u_mem.mem[8193]);
                cmp_bytes = 0; mism_bytes = 0; err_hdr = 0;

                // ---- ACK / release ----
                // convention (brd_cdc_mailboxes.v L362-363 + board shell L489-499):
                //   pcie_held_seq  = tl_arm_seq  = descriptor capture_seq latched at ARM
                //   pcie_held_sess = tl_arm_sess = m_session_id latched at ARM
                ack_rel_seen = 0;
                $display("ACK_SEND frame=%0d seq=%0d db_val=%0d sess=%h | held_seq=%0d held_sess=%h tl_arm_seq=%0d tl_arm_sess=%h m_sess=%h eg_state=%0d wd_cnt=%0d",
                         f, seq_f, db_val, cfg_session,
                         u_dut.u_p4.u_egress.held_seq_r, u_dut.u_p4.u_egress.held_sess_r,
                         u_dut.tl_arm_seq, u_dut.tl_arm_sess, u_dut.m_session_id,
                         u_dut.u_p4.u_egress.state, u_dut.u_p4.wd_cnt);
                if (((SCEN == 0) || (SCEN == 2)) && (f == 1)) begin
                    pulse_ack(db_val ^ 32'h1);
                    repeat (8000) @(posedge tl_clk);
                    if (u_dut.u_p4.st_release_count != rel_prev) begin
                        $display("FAIL neg2: wrong ACK released the slot");
                        $display("NEG2_RESULT=FAIL"); $finish;
                    end
                    $display("PASS neg2: wrong ACK did not release (desc_active=1)");
                    $display("NEG2_RESULT=PASS");
                end
                pulse_ack(seq_f);
                if (db_val != seq_f) pulse_ack(db_val);
                repeat (60) @(posedge core_clk);
                $display("ACK_PROBE frame=%0d xack_cnt=%0d ack_start=%b ack_free=%b ack_valid=%b x_ack=%b eg_state=%0d wd_cnt=%0d slot_rel=%b",
                         f, xack_cnt, u_dut.u_ack.start, u_dut.u_ack.free, u_dut.u_ack.valid,
                         u_dut.x_ack, u_dut.u_p4.u_egress.state, u_dut.u_p4.wd_cnt, u_dut.u_p4.slot_release);
                guard = 0;
                while ((u_dut.u_p4.st_release_count == rel_prev) && (guard < 200000)) begin
                    @(posedge tl_clk); guard = guard + 1;
                end
                if (u_dut.u_p4.st_release_count == rel_prev) begin
                    $display("FAIL frame %0d: correct ACK (seq=%0d) did not release the slot (%0d cycles)",
                             f, db_val, guard);
                    $display("POS_RESULT=FAIL no_release frame=%0d", f);
                    $finish;
                end
                rel_prev = u_dut.u_p4.st_release_count;
                $display("INFO frame=%0d ACK(seq=%0d) released the slot after %0d tl cycles (rel_count=%0d)", f, db_val, guard, rel_prev);
                repeat (200) @(posedge tl_clk);
                // re-arm for the next frame while frame_bytes still holds this one
                if (f != (NF - 1)) begin
                    pulse_arm;
                    $display("INFO frame=%0d re-armed for frame %0d", f, f + 1);
                end
            end
        end
        bp_en = 1'b0;
        begin : stream_chk
            integer d, k2;
            d = 0;
            for (k2 = 0; (k2 < cap_end[1]) && (k2 < (cap_end[2] - cap_end[1])); k2 = k2 + 1)
                if (expbuf[k2] !== expbuf[cap_end[1]+k2]) d = d + 1;
            $display("STREAM_DIFF frame1(%0d) vs frame2(%0d) bytes_differ=%0d", cap_end[1], (cap_end[2]-cap_end[1]), d);
            if (d == 0) begin
                $display("FAIL stream: the two frames carry identical compression streams");
                $display("POS_RESULT=FAIL stream_identical");
                $finish;
            end
        end

        $display("INFO summary frames_ok=%0d frames_fail=%0d req=%0d x_cnt=%0d ddr_wr_beats=%0d ddr_rd_beats=%0d",
                 frame_ok, frame_fail, REQ, x_cnt, dm_wr_beats, dm_rd_beats);
        // E8: POS_RESULT may only be PASS when the target frame count is reached and
        // every frame passed (previously it reported PASS for "1 of 2").
        if (pos_verdict(frame_ok, frame_fail, REQ) && (x_cnt == 0))
            $display("POS_RESULT=PASS frames=%0d req=%0d x_cnt=%0d", frame_ok, REQ, x_cnt);
        else
            $display("POS_RESULT=FAIL frames_ok=%0d fail=%0d req=%0d x_cnt=%0d", frame_ok, frame_fail, REQ, x_cnt);
        // E8 negative control: the same gate must reject a run that is one frame short
        $display("E8_NEGCTL gate(ok=%0d,req=%0d)=%0d gate(ok=%0d,req=%0d)=%0d expect 1_then_0",
                 frame_ok, REQ, pos_verdict(frame_ok, frame_fail, REQ),
                 frame_ok, REQ + 1, pos_verdict(frame_ok, frame_fail, REQ + 1));
        $finish;
    end

    // ---- global watchdog ----
    initial begin
        #400000000;
        $display("RESULT=FAIL timeout");
        $finish;
    end
endmodule

// ---------------------------------------------------------------------------
// thin wrappers (one compile, one vsim run per scenario)
// ---------------------------------------------------------------------------
module tb_brd_g1_top;
    brd_g1_harness #(.BASEW(2048), .CAPB(1048576), .IS_NEG(0)) u_h();
endmodule

module tb_brd_neg_base;
    // SLOT_BASE_WORD=2049 -> ddr_base=0x1_0020, ddr_base[11:0]!=0 -> must be rejected
    brd_g1_harness #(.BASEW(2049), .CAPB(1048576), .IS_NEG(1)) u_h();
endmodule

module tb_brd_neg_cap;
    // cap too small: base 0x10000 + frame 0x1000 > 0x10800 -> must be rejected
    brd_g1_harness #(.BASEW(2048), .CAPB(32'h0001_0800), .IS_NEG(1)) u_h();
endmodule

// ---------------------------------------------------------------------------
// merged illegal-condition negatives (one vsim run): non-4KiB base + short cap
// ---------------------------------------------------------------------------
module tb_brd_neg_both;
    brd_g1_harness #(.BASEW(2049), .CAPB(1048576), .IS_NEG(1), .NEGID(1)) u_neg_base();
    brd_g1_harness #(.BASEW(2048), .CAPB(32'h0001_0800), .IS_NEG(1), .NEGID(2)) u_neg_cap();
endmodule
