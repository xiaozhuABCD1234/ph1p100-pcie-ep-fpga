`timescale 1ns/1ps
// =============================================================================
// tb_b13_chain.sv -- T10.b13 full chain with the real board read path:
//   camera_a1_uart_top (real A+ core, real stores)
//     -> a1_ddr_arb2 (inside the top)
//     -> p2_ddr_bridge (187.5 MHz <-> 200 MHz PAXI)
//     -> p2_paxi_model_b13 (drop / late R injection)
// UART output is captured both from the debug byte port and from the physical
// 8N1 wire; check_b13.py decodes frames + v5 status packets.
//
// Generics: NFRAMES, STA_DIV, DROP_ADDR, DROP_OCC, DROP_FIRST_N, LATE_ADDR,
//           LATE_OCC, LATE_DELAY, W, H, CAM_W, ROI_X, ROI_Y, UART_DIV
// =============================================================================
module tb_b17_chain #(
    parameter integer CAM_W = 72,
    parameter integer CAM_H = 10,
    parameter integer ROI_X = 4,
    parameter integer ROI_Y = 2,
    parameter integer W     = 64,
    parameter integer H     = 8,
    parameter integer UART_DIV = 4,
    parameter integer LINE_GAP = 40,
    parameter integer FRAME_GAP = 600,
    parameter integer MAX_CYCLES = 2000000,
    parameter integer NFRAMES = 1,
    parameter integer STA_DIV = 10000,
    parameter integer FIFO_AW = 6,
    parameter integer DROP_ADDR = -1,
    parameter integer DROP_OCC = 0,
    parameter integer DROP_FIRST_N = 0,
    parameter integer LATE_ADDR = -1,
    parameter integer LATE_OCC = 0,
    parameter integer LATE_DELAY = 0,
    parameter integer AR_STALL_OCC = 0,
    parameter integer AR_STALL_N = 0,
    parameter integer RV_GAP_OCC = 0,
    parameter integer RV_GAP_N = 0
) ();
    localparam integer CG = CAM_W / 4;

    reg clk_cam = 1'b0;
    reg clk_a1  = 1'b0;
    reg clk_ddr = 1'b0;
    wire clk_uart = clk_a1;
    reg rst_n = 1'b0;

    always #2.6665 clk_cam = ~clk_cam;
    initial begin #1.7000; forever #2.6665 clk_a1 = ~clk_a1; end
    initial begin #0.4000; forever #2.5000 clk_ddr = ~clk_ddr; end

    reg  [39:0] tap_pix = 40'd0;
    reg         tap_v = 1'b0, tap_line = 1'b0, tap_frame = 1'b0, tap_vs = 1'b0;

    wire [31:0]  ddr_awaddr, ddr_araddr;
    wire         ddr_awvalid, ddr_awready, ddr_wvalid, ddr_wready;
    wire [255:0] ddr_wdata;
    wire         ddr_arvalid, ddr_arready, ddr_rvalid, ddr_rready;
    wire [255:0] ddr_rdata;
    wire         rd_abort_w;
    wire         uart_txd;
    wire [7:0]   dbg_byte;
    wire         dbg_byte_valid;
    wire [31:0]  st_cap, st_enc, st_exp, st_exp_bytes, st_raw_pub, st_raw_drop;
    wire [31:0]  st_cmp_drop, st_geom, st_err, st_read_words, st_dup_words;
    wire [511:0] dbg_bridge;

    camera_a1_uart_top #(
        .CAM_W (CAM_W), .CAM_H (CAM_H), .ROI_X (ROI_X), .ROI_Y (ROI_Y),
        .W (W), .H (H), .UART_DIV (UART_DIV), .STS_DIV(STA_DIV), .FIFO_AW(FIFO_AW)
    ) dut (
        .clk_cam (clk_cam), .clk_a1 (clk_a1), .clk_uart (clk_uart), .rst_n (rst_n),
        .i_a_pixel (tap_pix), .i_a_pixel_valid (tap_v),
        .i_a_in_line (tap_line), .i_a_in_frame (tap_frame), .i_a_vsync (tap_vs),
        .i_ddr_rdy (1'b1),
        .i_dbg_tap (6'd0), .i_dbg_delay_done (1'b0), .i_dbg_rst_out (1'b0),
        .i_dbg_sync_wait (1'b0), .i_dbg_pkt_tgl (1'b0), .i_dbg_vs_tgl (1'b0),
        .i_dbg_clk_tgl (1'b0), .i_dbg_sys (64'd0),
        .i_dbg_bridge (dbg_bridge),
        .o_ddr_awaddr (ddr_awaddr), .o_ddr_awvalid (ddr_awvalid), .o_ddr_awready (ddr_awready),
        .o_ddr_wdata (ddr_wdata), .o_ddr_wvalid (ddr_wvalid), .o_ddr_wready (ddr_wready),
        .o_ddr_araddr (ddr_araddr), .o_ddr_arvalid (ddr_arvalid), .o_ddr_arready (ddr_arready),
        .i_ddr_rdata (ddr_rdata), .i_ddr_rvalid (ddr_rvalid), .o_ddr_rready (ddr_rready),
        .o_rd_abort (rd_abort_w),
        .o_uart_txd (uart_txd),
        .o_dbg_byte (dbg_byte), .o_dbg_byte_valid (dbg_byte_valid),
        .o_st_cap_frames (st_cap), .o_st_enc_frames (st_enc), .o_st_exported (st_exp),
        .o_st_export_bytes (st_exp_bytes), .o_st_raw_pub (st_raw_pub),
        .o_st_raw_drop (st_raw_drop), .o_st_cmp_drop (st_cmp_drop),
        .o_st_geom_err (st_geom), .o_st_errors (st_err),
        .o_st_read_words (st_read_words), .o_st_dup_words (st_dup_words),
        .o_st_raw_sts ()
    );

    // -------------------------------------------------- board read/write path
    wire [31:0]  s_awaddr, s_araddr;
    wire         s_awvalid, s_awready, s_wvalid, s_wready;
    wire [255:0] s_wdata;
    wire         s_arvalid, s_arready, s_rvalid, s_rready;
    wire [255:0] s_rdata;

    wire [26:0]  p_awaddr, p_araddr;
    wire         p_awvalid, p_awready, p_wvalid, p_wlast, p_wready;
    wire [255:0] p_wdata;
    wire [31:0]  p_wstrb;
    wire         p_arvalid, p_arready, p_rlast, p_rvalid, p_rready;
    wire [255:0] p_rdata;
    wire [31:0]  n_ar, n_aw, n_w, n_r;
    wire [31:0]  n_bad_low3, n_oob, n_mask, n_same_req, n_same_hs, n_write_commit;

    p2_ddr_bridge u_bridge (
        .clk_a1 (clk_a1), .rst_n (rst_n),
        .s_awaddr (ddr_awaddr), .s_awvalid (ddr_awvalid), .s_awready (ddr_awready),
        .s_wdata (ddr_wdata), .s_wvalid (ddr_wvalid), .s_wready (ddr_wready),
        .s_araddr (ddr_araddr), .s_arvalid (ddr_arvalid), .s_arready (ddr_arready),
        .s_rdata (s_rdata), .s_rvalid (s_rvalid), .s_rready (ddr_rready),
        .rd_abort (rd_abort_w),
        .clk_ddr (clk_ddr), .ddr_rdy (1'b1),
        .paxi_awaddr (p_awaddr), .paxi_awvalid (p_awvalid), .paxi_awready (p_awready),
        .paxi_wdata (p_wdata), .paxi_wstrb (p_wstrb), .paxi_wvalid (p_wvalid),
        .paxi_wlast (p_wlast), .paxi_wready (p_wready),
        .paxi_araddr (p_araddr), .paxi_arvalid (p_arvalid), .paxi_arready (p_arready),
        .paxi_rdata (p_rdata), .paxi_rlast (p_rlast), .paxi_rvalid (p_rvalid),
        .paxi_rready (p_rready),
        .dbg_a1 (dbg_bridge)
    );
    assign ddr_rdata = s_rdata;
    assign ddr_rvalid = s_rvalid;

    p2_paxi_model_b17 #(.WORDS(524288), .AR_GAP(3), .R_GAP(3),
                        .DROP_ADDR(DROP_ADDR), .DROP_OCC(DROP_OCC),
                        .DROP_FIRST_N(DROP_FIRST_N),
                        .LATE_ADDR(LATE_ADDR), .LATE_OCC(LATE_OCC),
                        .LATE_DELAY(LATE_DELAY),
                        .AR_STALL_OCC(AR_STALL_OCC), .AR_STALL_N(AR_STALL_N),
                        .RV_GAP_OCC(RV_GAP_OCC), .RV_GAP_N(RV_GAP_N)) u_ddr (
        .clk (clk_ddr), .rst_n (rst_n), .rdy (1'b1),
        .awaddr (p_awaddr), .awvalid (p_awvalid), .awready (p_awready),
        .wdata (p_wdata), .wstrb (p_wstrb), .wvalid (p_wvalid), .wlast (p_wlast),
        .wready (p_wready),
        .araddr (p_araddr), .arvalid (p_arvalid), .arready (p_arready),
        .rdata (p_rdata), .rlast (p_rlast), .rvalid (p_rvalid), .rready (p_rready),
        .n_ar_hs (n_ar), .n_aw_hs (n_aw), .n_whs (n_w), .n_r_hs (n_r),
        .n_bad_low3 (n_bad_low3), .n_oob (n_oob), .n_mask_nonzero (n_mask),
        .n_same_req (n_same_req), .n_same_hs (n_same_hs),
        .n_write_commit (n_write_commit)
    );

    // ------------------------------------------- T10.b15 read-path monitors
    // Every counter below is observation only: it never drives the DUT.
    integer b15_ar_busy_hs=0, b15_short_burst=0, b15_rready_low=0, b15_rf_ovf=0;
    integer b15_max_rf_level=0, b15_max_os=0, b15_stale_r=0, b15_purge_close=0;
    integer b15_ar=0, b15_r=0, b15_rlast=0, b15_bursts=0;
    reg [26:0] b15_last_ar_addr=27'd0;
    reg        b15_prev_busy=1'b0;
    reg        b15_rlast_seen=1'b0;
    always @(posedge clk_ddr) begin
      if (rst_n) begin
        if (p_rready !== 1'b1) b15_rready_low = b15_rready_low + 1;
        if (p_arvalid && p_arready) begin
          b15_ar = b15_ar + 1;
          b15_last_ar_addr = p_araddr;
          // R2 gate: no AR may be presented while a burst is owned.
          if (u_bridge.ar_busy) b15_ar_busy_hs = b15_ar_busy_hs + 1;
        end
        if (p_rvalid && p_rready && p_rlast) b15_rlast_seen = 1'b1;
        if (p_rvalid && p_rready) begin
          b15_r = b15_r + 1;
          if (p_rlast) b15_rlast = b15_rlast + 1;
          if (!u_bridge.ar_busy) b15_stale_r = b15_stale_r + 1;
        end
        if (u_bridge.rf_push && !u_bridge.rf_wready) b15_rf_ovf = b15_rf_ovf + 1;
        if (u_bridge.rf_level > b15_max_rf_level) b15_max_rf_level = u_bridge.rf_level;
        if (u_bridge.ar_busy && !b15_prev_busy) begin
          b15_bursts = b15_bursts + 1;
          b15_rlast_seen = 1'b0;
          if (b15_max_os < 1) b15_max_os = 1;
        end
        if (!u_bridge.ar_busy && b15_prev_busy) begin
          // A burst that did not end on rlast must have been closed by the
          // b13 purge/guard force-clear (the only other legal closure).
          if (!b15_rlast_seen) begin
            if (u_bridge.rd_hold || u_bridge.purge_evt) b15_purge_close = b15_purge_close + 1;
            else b15_short_burst = b15_short_burst + 1;
          end
        end
        b15_prev_busy = u_bridge.ar_busy;
      end
    end

    // ------------------------------------------- T10.b17 native-contract monitors
    // Observation only.  These directly watch the PAXI pins, independent of the
    // model's own counters, so a model bug cannot hide a boundary violation.
    integer b17_ar_low3_bad=0, b17_aw_low3_bad=0, b17_mask_bad=0;
    integer b17_same_req=0, b17_same_hs=0, b17_aw_hs=0, b17_w_hs=0, b17_ar_hs=0;
    reg [26:0] b17_last_ar_addr=27'd0;
    always @(posedge clk_ddr) begin
      if (rst_n) begin
        if ((p_awvalid && p_arvalid) || (p_wvalid && p_arvalid)) b17_same_req = b17_same_req + 1;
        if ((p_awvalid && p_awready && p_arvalid && p_arready) ||
            (p_wvalid  && p_wready  && p_arvalid && p_arready)) b17_same_hs = b17_same_hs + 1;
        if (p_awvalid && p_awready) begin
          b17_aw_hs = b17_aw_hs + 1;
          if (p_awaddr[2:0] !== 3'b000) b17_aw_low3_bad = b17_aw_low3_bad + 1;
        end
        if (p_wvalid && p_wready) begin
          b17_w_hs = b17_w_hs + 1;
          if (p_wstrb !== 32'h0000_0000) b17_mask_bad = b17_mask_bad + 1;
        end
        if (p_arvalid && p_arready) begin
          b17_ar_hs = b17_ar_hs + 1;
          b17_last_ar_addr = p_araddr;
          if (p_araddr[2:0] !== 3'b000) b17_ar_low3_bad = b17_ar_low3_bad + 1;
        end
      end
    end

    // ------------------------------------------------------------- observation
    integer fd, fw, ft, fs, cycles=0, cap_bytes=0, wire_bytes=0;
    integer source_frames=0, source_groups=0, crop_beats=0, crop_sofs=0, crop_lasts=0;
    integer fifo_reject=0, raw_beats=0, cmp_words=0, raw_writes=0, cmp_writes=0;
    integer ticks_in_frame=0, status_grants=0, max_dq=0;
    integer fidx, seed, waits=0;
    integer timeouts=0, retries=0, giveups=0;
    integer guard_ar=0, guard_open=0, drain_words=0;
    reg [2047:0] out_path, wire_path, trace_path, stat_path;
    reg [7:0] serial_byte;
    integer bitno;
    reg [31:0] prev_cap=0,prev_pub=0,prev_enc=0,prev_exp=0;
    reg [31:0] prev_cmp_pub=0;
    reg        prev_fabort=0;
    reg [31:0] PREV_STALE=0;
    integer b15_line_rises=0, b15_frame_rises=0;
    reg b15_prev_line=1'b0, b15_prev_frame=1'b0;

    task write_stats;
      begin
        $fwrite(fs,"nframes=%0d w=%0d h=%0d cam_w=%0d cam_h=%0d roi_x=%0d roi_y=%0d uart_div=%0d sts_div=%0d fifo_aw=%0d line_gap=%0d frame_gap=%0d cycles=%0d cap=%0d raw_pub=%0d enc=%0d exported=%0d exp_bytes=%0d raw_drop=%0d cmp_drop=%0d geom=%0d err=%0d read_words=%0d dup_words=%0d cap_bytes=%0d wire_bytes=%0d source_frames=%0d source_groups=%0d crop_beats=%0d crop_sofs=%0d crop_lasts=%0d fifo_reject=%0d raw_beats=%0d cmp_words=%0d raw_writes=%0d cmp_writes=%0d ticks_in_frame=%0d status_grants=%0d max_dq=%0d timeouts=%0d retries=%0d giveups=%0d timeout_cnt=%0d retry_cnt=%0d giveup_cnt=%0d stale_guard_cnt=%0d purge_cnt=%0d guard_ar=%0d guard_open=%0d dq_end=%0d drain_words=%0d\n",
         NFRAMES,W,H,CAM_W,CAM_H,ROI_X,ROI_Y,UART_DIV,STA_DIV,FIFO_AW,LINE_GAP,FRAME_GAP,cycles,st_cap,st_raw_pub,st_enc,st_exp,st_exp_bytes,st_raw_drop,st_cmp_drop,st_geom,st_err,st_read_words,st_dup_words,cap_bytes,wire_bytes,source_frames,source_groups,crop_beats,crop_sofs,crop_lasts,fifo_reject,raw_beats,cmp_words,raw_writes,cmp_writes,ticks_in_frame,status_grants,max_dq,timeouts,retries,giveups,dut.raw_timeout_cnt,dut.raw_retry_cnt,dut.raw_retry_giveup,dut.raw_stale_guard,u_bridge.purge_cnt,guard_ar,guard_open,dut.u_export.dq_cnt,drain_words);
        // T10.b15 line 2: read-path monitors (additive keys only).
        $fwrite(fs,"b15_max_os=%0d b15_ar_busy_hs=%0d b15_short_burst=%0d b15_rready_low=%0d b15_rf_ovf=%0d b15_max_rf_level=%0d b15_stale_r=%0d b15_ar=%0d b15_r=%0d b15_rlast=%0d b15_last_ar_addr=%0d b15_purge_close=%0d b15_bursts=%0d b15_ar_minus_rlast=%0d b15_ar_minus_r=%0d b15_pix_beats=%0d b15_line_rises=%0d b15_frame_rises=%0d b15_crop_groups=%0d b15_raw_len=%0d\n",
          b15_max_os,b15_ar_busy_hs,b15_short_burst,b15_rready_low,b15_rf_ovf,
          b15_max_rf_level,b15_stale_r,b15_ar,b15_r,b15_rlast,b15_last_ar_addr,
          b15_purge_close,b15_bursts,b15_ar-b15_rlast,b15_ar-b15_r,
          crop_beats,b15_line_rises,b15_frame_rises,source_groups,dut.a1_raw_len);
        // T10.b17 line 3: native-contract + model counters.
        $fwrite(fs,"b17_ar_low3_bad=%0d b17_aw_low3_bad=%0d b17_mask_bad=%0d b17_same_req=%0d b17_same_hs=%0d b17_aw_hs=%0d b17_w_hs=%0d b17_ar_hs=%0d b17_last_ar_addr=%0d b17_last_ar_low3=%0d b17_model_bad_low3=%0d b17_model_oob=%0d b17_model_mask=%0d b17_model_sreq=%0d b17_model_shs=%0d b17_model_commit=%0d b17_model_ar=%0d b17_model_r=%0d\n",
          b17_ar_low3_bad,b17_aw_low3_bad,b17_mask_bad,b17_same_req,b17_same_hs,
          b17_aw_hs,b17_w_hs,b17_ar_hs,b17_last_ar_addr,b17_last_ar_addr[2:0],
          n_bad_low3,n_oob,n_mask,n_same_req,n_same_hs,n_write_commit,n_ar,n_r);
      end
    endtask
    always @(posedge clk_cam) if(rst_n) begin
      if(dut.i_a_in_line  && !b15_prev_line)  b15_line_rises=b15_line_rises+1;
      if(dut.i_a_in_frame && !b15_prev_frame) b15_frame_rises=b15_frame_rises+1;
      b15_prev_line=dut.i_a_in_line; b15_prev_frame=dut.i_a_in_frame;
      if(tap_v && tap_frame) source_groups=source_groups+1;
      if(dut.crop_valid) crop_beats=crop_beats+1;
      if(dut.crop_sof) crop_sofs=crop_sofs+1;
      if(dut.crop_last) crop_lasts=crop_lasts+1;
      if(dut.fifo_wvalid&&!dut.fifo_wready) fifo_reject=fifo_reject+1;
    end
    always @(posedge clk_a1) begin
      cycles=cycles+1;
      if(rst_n) begin
        if(dbg_byte_valid) begin $fwrite(fd,"%0d\n",dbg_byte);cap_bytes=cap_bytes+1;end
        if(dut.skid_valid&&dut.raw_wr_ready) raw_beats=raw_beats+1;
        if(dut.a1_out_valid&&dut.a1_out_ready) cmp_words=cmp_words+1;
        if(dut.raw_awvalid&&dut.raw_awready&&dut.raw_wvalid&&dut.raw_wready) raw_writes=raw_writes+1;
        if(dut.cmp_awvalid&&dut.cmp_awready&&dut.cmp_wvalid&&dut.cmp_wready) cmp_writes=cmp_writes+1;
        if(dut.u_export.dq_cnt>max_dq) max_dq=dut.u_export.dq_cnt;
        if(dut.raw_rd_timeout) begin
          timeouts=timeouts+1;
          $fwrite(ft,"RD_TIMEOUT cycles=%0d rd_idx=%0d rd_words=%0d rd_sel=%0d slot=%h timeout_cnt=%0d\n",
                  cycles,dut.raw_rd_idx,dut.raw_rd_words,dut.u_raw_store.rd_sel,
                  dut.raw_slot_st,dut.raw_timeout_cnt+1);
        end
        if(dut.raw_retry_cnt!=retries) begin
          retries=dut.raw_retry_cnt;
          $fwrite(ft,"RD_RETRY cycles=%0d cnt=%0d slot=%h\n",cycles,retries,dut.raw_slot_st);
        end
        if(dut.raw_retry_giveup!=giveups) begin
          giveups=dut.raw_retry_giveup;
          $fwrite(ft,"RD_GIVEUP cycles=%0d cnt=%0d slot=%h\n",cycles,giveups,dut.raw_slot_st);
        end
        if(dut.raw_stale_guard!=0 && dut.raw_stale_guard!=PREV_STALE) begin
          PREV_STALE=dut.raw_stale_guard;
          $fwrite(ft,"RD_STALE_GUARD cycles=%0d cnt=%0d\n",cycles,PREV_STALE);
        end
        if(dut.u_export.sts_tick && dut.u_export.estate!=0) ticks_in_frame=ticks_in_frame+1;
        if(dut.u_export.grant_status) status_grants=status_grants+1;
        if(st_cap!=prev_cap||st_raw_pub!=prev_pub||st_enc!=prev_enc||st_exp!=prev_exp) begin
          $fwrite(ft,"COUNTERS cycles=%0d cap=%0d pub=%0d enc=%0d exp=%0d raw_slots=%0d,%0d cmp_slots=%0d,%0d\n",cycles,st_cap,st_raw_pub,st_enc,st_exp,dut.u_raw_store.slot_st[0],dut.u_raw_store.slot_st[1],dut.u_cmp_store.slot_st[0],dut.u_cmp_store.slot_st[1]);
          prev_cap=st_cap;prev_pub=st_raw_pub;prev_enc=st_enc;prev_exp=st_exp;
        end
        if(dut.raw_rd_retry_ready===1'b1) guard_open=guard_open+1;
        // T10.b13b: an R taken while the read FSM is not in R_RW is a discarded
        // leftover from the aborted attempt (drain mode).  It must never change
        // rd_idx/rd_valid; count it as evidence.
        if(dut.raw_rready && dut.raw_rvalid && (dut.u_raw_store.rd_state != 3'd2))
          drain_words=drain_words+1;
        if(dut.raw_rready && dut.raw_rvalid)
          $fwrite(ft,"EV_RWORD cycles=%0d st=%0d idx=%0d data=%h_%h\n",cycles,dut.u_raw_store.rd_state,dut.raw_rd_idx,dut.raw_rdata[255:192],dut.raw_rdata[191:0]);
        // No AR may be presented to the bridge while the store holds its guard.
        if((dut.u_raw_store.rd_state == 3'd5) && dut.raw_arvalid) guard_ar=guard_ar+1;
        // T10.b13b event trace (diagnostic only, keeps every PASS criterion as is)
        if(dut.raw_rd_open)   $fwrite(ft,"EV_RDOPEN cycles=%0d ready=%0d idx=%0d retry=%0d\n",cycles,dut.raw_rd_open_ready,dut.raw_rd_idx,dut.raw_retry_cnt);
        if(dut.raw_rd_close)  $fwrite(ft,"EV_RDCLOSE cycles=%0d idx=%0d ok=%0d\n",cycles,dut.raw_rd_idx,dut.raw_expect_ok);
        if(dut.a1_commit)     $fwrite(ft,"EV_COMMIT cycles=%0d id=%0d slen=%0d rawlen=%0d grp=%0d\n",cycles,dut.cmp_id,dut.a1_slen,dut.a1_raw_len,dut.grp_sent);
        if(dut.a1_fabort !== prev_fabort) begin
          prev_fabort=dut.a1_fabort;
          $fwrite(ft,"EV_FABORT cycles=%0d level=%0d\n",cycles,dut.a1_fabort);
        end
        if(dut.cmp_begin)     $fwrite(ft,"EV_CMPBEGIN cycles=%0d id=%0d ready=%0d\n",cycles,dut.cmp_id,dut.cmp_begin_ready);
        if(dut.cmp_abort)     $fwrite(ft,"EV_CMPABORT cycles=%0d\n",cycles);
        if(dut.desc_push)     $fwrite(ft,"EV_DESCPUSH cycles=%0d id=%0d slen=%0d\n",cycles,dut.d_fid,dut.d_slen);
        if(dut.cmp_st_pub!==prev_cmp_pub) begin
          prev_cmp_pub=dut.cmp_st_pub;
          $fwrite(ft,"EV_CMPPUB cycles=%0d pub=%0d bytes=%0d slot=%0d,%0d len=%0d,%0d\n",cycles,dut.cmp_st_pub,dut.cmp_st_bytes,dut.u_cmp_store.slot_st[0],dut.u_cmp_store.slot_st[1],dut.u_cmp_store.slot_len[0],dut.u_cmp_store.slot_len[1]);
        end
      end
      if(cycles>MAX_CYCLES) begin
        write_stats; $fclose(fd);$fclose(fw);$fclose(ft);$fclose(fs);
        $fatal(1,"B13_WATCHDOG cap=%0d pub=%0d enc=%0d exp=%0d timeout=%0d retry=%0d giveup=%0d",
               st_cap,st_raw_pub,st_enc,st_exp,dut.raw_timeout_cnt,dut.raw_retry_cnt,dut.raw_retry_giveup);
      end
    end
    // Physical UART 8N1 decode at bit centres (no resync; strict 241-B packets).
    always begin
      @(negedge uart_txd);
      if(rst_n) begin
        repeat(UART_DIV+UART_DIV/2) @(posedge clk_a1); #0.01;
        for(bitno=0;bitno<8;bitno=bitno+1) begin
          serial_byte[bitno]=uart_txd;
          repeat(UART_DIV) @(posedge clk_a1); #0.01;
        end
        if(uart_txd!==1'b1) $fatal(1,"UART_STOP_BIT");
        $fwrite(fw,"%0d\n",serial_byte);wire_bytes=wire_bytes+1;
      end
    end
    reg [31:0] lfsr;

    task drive_frame;
        input integer seed;
        input integer nlines;
        integer y, g;
        reg [9:0] s0, s1, s2, s3;
        reg [31:0] st;
        begin
            @(negedge clk_cam);
            tap_frame = 1'b1;
            tap_vs    = 1'b1;
            lfsr      = 32'h1234_5678 ^ seed;
            for (y = 0; y < nlines; y = y + 1) begin
                @(negedge clk_cam);
                tap_line = 1'b1;
                tap_v    = 1'b0;
                for (g = 0; g < CG; g = g + 1) begin
                    st   = lfsr;
                    st   = st ^ (st << 13);
                    st   = st ^ (st >> 17);
                    st   = st ^ (st << 5);
                    lfsr = st;
                    s0 = st[9:0]; s1 = st[19:10]; s2 = st[29:20]; s3 = st[31:22];
                    tap_pix = {s3[1:0], s2[1:0], s1[1:0], s0[1:0],
                               s3[9:2], s2[9:2], s1[9:2], s0[9:2]};
                    tap_v   = 1'b1;
                    @(negedge clk_cam);
                end
                tap_v    = 1'b0;
                tap_line = 1'b0;
                repeat (LINE_GAP) @(negedge clk_cam);
            end
            tap_frame = 1'b0;
            tap_vs    = 1'b0;
            repeat (FRAME_GAP) @(negedge clk_cam);
        end
    endtask

    initial begin
      if(!$value$plusargs("OUT=%s",out_path)) out_path="capture.dec";
      if(!$value$plusargs("WIRE=%s",wire_path)) wire_path="wire.dec";
      if(!$value$plusargs("TRACE=%s",trace_path)) trace_path="trace.txt";
      if(!$value$plusargs("STAT=%s",stat_path)) stat_path="stats.txt";
      fd=$fopen(out_path,"w");fw=$fopen(wire_path,"w");ft=$fopen(trace_path,"w");fs=$fopen(stat_path,"w");
      if(!fd||!fw||!ft||!fs) $fatal(1,"OPEN_FAIL");
      repeat(20) @(negedge clk_a1);rst_n=1;
      repeat(40) @(negedge clk_a1);
      for(fidx=0;fidx<NFRAMES;fidx=fidx+1) begin
        // finite two-slot stores: wait for a FREE RAW slot before the 3rd input
        while(!dut.raw_begin_ready) begin @(negedge clk_a1);waits=waits+1;end
        seed=111*(fidx+1);
        $fwrite(ft,"SOURCE_START source=%0d seed=%0d cycles=%0d exported=%0d\n",fidx+1,seed,cycles,st_exp);
        drive_frame(seed,CAM_H);   // T10.b15: drive the whole sensor height
        source_frames=source_frames+1;
        $fwrite(ft,"SOURCE_END source=%0d seed=%0d cycles=%0d crop_beats=%0d cap=%0d pub=%0d exp=%0d\n",fidx+1,seed,cycles,crop_beats,st_cap,st_raw_pub,st_exp);
      end
      // wait for the expected export count (timeout/retry cases may export less)
      begin : wait_exp
        integer guard_cyc;
        guard_cyc = 0;
        while ((st_exp < NFRAMES) && (guard_cyc < MAX_CYCLES/4)) begin
          @(negedge clk_a1);
          // stop early if every frame has been resolved but fewer exported
          if ((dut.raw_retry_giveup > 0) && (st_exp + dut.raw_retry_giveup >= NFRAMES) &&
              (dut.u_export.estate==0) && (dut.u_export.dq_cnt==0)) guard_cyc = guard_cyc + 1;
          else guard_cyc = 0;
          if (guard_cyc > 20000) disable wait_exp;
        end
      end
      // wait for at least one complete v5 status packet on the wire
      begin : wait_status
        integer wc;
        wc = 0;
        while ((status_grants < 1) && (wc < 200000)) begin @(negedge clk_a1); wc = wc + 1; end
      end
      @(negedge clk_a1);
      while(!(dut.u_export.estate==0 && dut.u_export.sstate==0 && dut.u_export.tx_ready && !dut.u_export.tx_valid_r)) @(negedge clk_a1);
      write_stats;$fclose(fd);$fclose(fw);$fclose(ft);$fclose(fs);
      $display("B13_CHAIN_DONE frames=%0d cap=%0d pub=%0d enc=%0d exported=%0d bytes=%0d timeout=%0d retry=%0d giveup=%0d stale=%0d",
               NFRAMES,st_cap,st_raw_pub,st_enc,st_exp,cap_bytes,
               dut.raw_timeout_cnt,dut.raw_retry_cnt,dut.raw_retry_giveup,dut.raw_stale_guard);
      $display("B15_CHAIN_DONE max_os=%0d ar_busy_hs=%0d short_burst=%0d rready_low=%0d rf_ovf=%0d max_rf_level=%0d stale_r=%0d ar=%0d r=%0d rlast=%0d last_ar_addr=%0d purge_close=%0d bursts=%0d pix=%0d lines=%0d frames=%0d groups=%0d rawlen=%0d",
               b15_max_os,b15_ar_busy_hs,b15_short_burst,b15_rready_low,b15_rf_ovf,
               b15_max_rf_level,b15_stale_r,b15_ar,b15_r,b15_rlast,b15_last_ar_addr,
               b15_purge_close,b15_bursts,crop_beats,b15_line_rises,b15_frame_rises,
               source_groups,dut.a1_raw_len);
      $display("B17_CHAIN_DONE low3_bad=%0d/%0d mask_bad=%0d same_req=%0d same_hs=%0d model_bad=%0d oob=%0d mask=%0d commit=%0d ar=%0d r=%0d last_ar=%0d",
               b17_aw_low3_bad,b17_ar_low3_bad,b17_mask_bad,b17_same_req,b17_same_hs,
               n_bad_low3,n_oob,n_mask,n_write_commit,n_ar,n_r,b17_last_ar_addr);
      $finish;
    end
endmodule
