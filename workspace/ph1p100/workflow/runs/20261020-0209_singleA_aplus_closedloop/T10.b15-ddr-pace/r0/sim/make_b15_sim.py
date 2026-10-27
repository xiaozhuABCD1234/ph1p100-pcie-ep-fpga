#!/usr/bin/env python3
"""make_b15_sim.py -- derive the T10.b15 testbench and PAXI model from the
frozen b13 copies placed in this directory.

Only the *test* side changes (the DUT is the real b15 changed-src RTL):
  * p2_paxi_model_b15.v = p2_paxi_model_b13.v + two ordinal-based injection
    knobs (so the injection always lands inside the read phase):
        AR_STALL_OCC / AR_STALL_N : hold arready low for N clk_ddr cycles after
                                    the AR_STALL_OCC-th AR handshake   (S7c)
        RV_GAP_OCC   / RV_GAP_N   : stretch the R of the RV_GAP_OCC-th AR by N
                                    extra cycles                       (S7d)
    The R channel contract is unchanged: rvalid is held until rready.
  * tb_b15_chain.sv = tb_b13_chain.sv + the b15 read-path monitors
        b15_ar_busy_hs  AR handshakes while ar_busy          (must be 0)
        b15_max_os      max simultaneously outstanding ARs   (must be 1)
        b15_short_burst ar_busy closed without rlast/purge   (must be 0)
        b15_rready_low  clk_ddr cycles with paxi_rready != 1  (must be 0)
        b15_rf_ovf      paxi beats the RF could not take      (must be 0)
        b15_max_rf_level maximum rf_level observed (<= 16)
        b15_stale_r     orphan beats (absorbed, never queued)
        b15_ar/r/rlast  PAXI handshake counters
        b15_last_ar_addr last AR address issued
        b15_purge_close bursts closed by the b13 purge/guard force-clear
    Everything else (frame capture, UART wire decode, stats line 1) is byte
    identical to the b13 TB so the checker and the P1 goldens stay comparable.
"""
import pathlib

HERE = pathlib.Path(__file__).resolve().parent


def patch(src, dst, reps):
    t = (HERE / src).read_text(encoding="utf-8")
    for old, new in reps:
        if t.count(old) != 1:
            raise SystemExit("anchor %r found %d times in %s" % (old[:60], t.count(old), src))
        t = t.replace(old, new)
    (HERE / dst).write_text(t, encoding="utf-8")
    print("wrote %s (%d bytes)" % (dst, len(t)))


MODEL_REPS = [
    ("module p2_paxi_model_b13 #(", "module p2_paxi_model_b15 #("),
    ("""    parameter integer LATE_DELAY = 0
) (""",
     """    parameter integer LATE_DELAY = 0,
    // ---------------- T10.b15 channel-timing injection (ordinal based, so it
    // always lands inside the read phase and never depends on absolute time) --
    parameter integer AR_STALL_OCC = 0,  // hold arready low for AR_STALL_N cycles
    parameter integer AR_STALL_N   = 0,  //   after the AR_STALL_OCC-th AR
    parameter integer RV_GAP_OCC   = 0,  // stretch the R of the RV_GAP_OCC-th AR
    parameter integer RV_GAP_N     = 0
) ("""),
    ("""    wire aw_stall = (AR_GAP > 1) && ((tick % AR_GAP) == 0);""",
     """    // T10.b15 S7c: a long arready stall after a chosen AR handshake.
    integer    ar_occ = 0;
    reg [15:0] stall_cnt = 16'd0;
    always @(posedge clk) begin
        if (!rst_n) begin
            ar_occ    <= 0;
            stall_cnt <= 16'd0;
        end else begin
            if (stall_cnt != 16'd0) stall_cnt <= stall_cnt - 16'd1;
            if (arvalid && arready && (AR_STALL_OCC > 0) && (ar_occ + 1 == AR_STALL_OCC))
                stall_cnt <= AR_STALL_N[15:0];
            if (arvalid && arready) ar_occ <= ar_occ + 1;
        end
    end

    wire aw_stall = (AR_GAP > 1) && ((tick % AR_GAP) == 0);"""),
    ("""    assign arready = rst_n && !ar_stall;""",
     """    assign arready = rst_n && !ar_stall && (stall_cnt == 16'd0);"""),
    ("""    reg         late_hold = 1'b0;""",
     """    reg         late_hold = 1'b0;
    reg         rvgap_this = 1'b0;   // T10.b15 S7d"""),
    ("""        if (ar_hs) begin
            drop_this <= 1'b0;
            late_this <= 1'b0;""",
     """        if (ar_hs) begin
            drop_this <= 1'b0;
            late_this <= 1'b0;
            rvgap_this <= (RV_GAP_N > 0) && (RV_GAP_OCC > 0) &&
                          (ar_occ + 1 == RV_GAP_OCC);"""),
    ("""            end else if (start_rd) begin
                raddr_r <= pq[pq_r[2:0]];
                pq_r    <= pq_r + 4'd1;
                rwait   <= R_GAP[7:0];
                rpend   <= 1'b1;""",
     """            end else if (start_rd) begin
                raddr_r <= pq[pq_r[2:0]];
                pq_r    <= pq_r + 4'd1;
                // T10.b15 S7d: a wider rvalid gap on the selected AR.
                rwait   <= R_GAP[7:0] + (rvgap_this ? RV_GAP_N[7:0] : 8'd0);
                rpend   <= 1'b1;"""),
]

TB_REPS = [
    ("module tb_b13_chain #(", "module tb_b15_chain #("),
    ("""    parameter integer LATE_DELAY = 0
) ();""",
     """    parameter integer LATE_DELAY = 0,
    parameter integer AR_STALL_OCC = 0,
    parameter integer AR_STALL_N = 0,
    parameter integer RV_GAP_OCC = 0,
    parameter integer RV_GAP_N = 0
) ();"""),
    ("""    p2_paxi_model_b13 #(.WORDS(524288), .AR_GAP(3), .R_GAP(3),
                        .DROP_ADDR(DROP_ADDR), .DROP_OCC(DROP_OCC),
                        .DROP_FIRST_N(DROP_FIRST_N),
                        .LATE_ADDR(LATE_ADDR), .LATE_OCC(LATE_OCC),
                        .LATE_DELAY(LATE_DELAY)) u_ddr (""",
     """    p2_paxi_model_b15 #(.WORDS(524288), .AR_GAP(3), .R_GAP(3),
                        .DROP_ADDR(DROP_ADDR), .DROP_OCC(DROP_OCC),
                        .DROP_FIRST_N(DROP_FIRST_N),
                        .LATE_ADDR(LATE_ADDR), .LATE_OCC(LATE_OCC),
                        .LATE_DELAY(LATE_DELAY),
                        .AR_STALL_OCC(AR_STALL_OCC), .AR_STALL_N(AR_STALL_N),
                        .RV_GAP_OCC(RV_GAP_OCC), .RV_GAP_N(RV_GAP_N)) u_ddr ("""),
    ("""    // ------------------------------------------------------------- observation
    integer fd, fw, ft, fs, cycles=0, cap_bytes=0, wire_bytes=0;""",
     """    // ------------------------------------------- T10.b15 read-path monitors
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

    // ------------------------------------------------------------- observation
    integer fd, fw, ft, fs, cycles=0, cap_bytes=0, wire_bytes=0;"""),
    ("""    reg [31:0] PREV_STALE=0;""",
     """    reg [31:0] PREV_STALE=0;
    integer b15_line_rises=0, b15_frame_rises=0;
    reg b15_prev_line=1'b0, b15_prev_frame=1'b0;"""),
    ("""    always @(posedge clk_cam) if(rst_n) begin
      if(tap_v && tap_frame) source_groups=source_groups+1;""",
     """    always @(posedge clk_cam) if(rst_n) begin
      if(dut.i_a_in_line  && !b15_prev_line)  b15_line_rises=b15_line_rises+1;
      if(dut.i_a_in_frame && !b15_prev_frame) b15_frame_rises=b15_frame_rises+1;
      b15_prev_line=dut.i_a_in_line; b15_prev_frame=dut.i_a_in_frame;
      if(tap_v && tap_frame) source_groups=source_groups+1;"""),
    ("""         NFRAMES,W,H,CAM_W,CAM_H,ROI_X,ROI_Y,UART_DIV,STA_DIV,FIFO_AW,LINE_GAP,FRAME_GAP,cycles,st_cap,st_raw_pub,st_enc,st_exp,st_exp_bytes,st_raw_drop,st_cmp_drop,st_geom,st_err,st_read_words,st_dup_words,cap_bytes,wire_bytes,source_frames,source_groups,crop_beats,crop_sofs,crop_lasts,fifo_reject,raw_beats,cmp_words,raw_writes,cmp_writes,ticks_in_frame,status_grants,max_dq,timeouts,retries,giveups,dut.raw_timeout_cnt,dut.raw_retry_cnt,dut.raw_retry_giveup,dut.raw_stale_guard,u_bridge.purge_cnt,guard_ar,guard_open,dut.u_export.dq_cnt,drain_words);
      end
    endtask""",
     """         NFRAMES,W,H,CAM_W,CAM_H,ROI_X,ROI_Y,UART_DIV,STA_DIV,FIFO_AW,LINE_GAP,FRAME_GAP,cycles,st_cap,st_raw_pub,st_enc,st_exp,st_exp_bytes,st_raw_drop,st_cmp_drop,st_geom,st_err,st_read_words,st_dup_words,cap_bytes,wire_bytes,source_frames,source_groups,crop_beats,crop_sofs,crop_lasts,fifo_reject,raw_beats,cmp_words,raw_writes,cmp_writes,ticks_in_frame,status_grants,max_dq,timeouts,retries,giveups,dut.raw_timeout_cnt,dut.raw_retry_cnt,dut.raw_retry_giveup,dut.raw_stale_guard,u_bridge.purge_cnt,guard_ar,guard_open,dut.u_export.dq_cnt,drain_words);
        // T10.b15 line 2: read-path monitors (additive keys only).
        $fwrite(fs,"b15_max_os=%0d b15_ar_busy_hs=%0d b15_short_burst=%0d b15_rready_low=%0d b15_rf_ovf=%0d b15_max_rf_level=%0d b15_stale_r=%0d b15_ar=%0d b15_r=%0d b15_rlast=%0d b15_last_ar_addr=%0d b15_purge_close=%0d b15_bursts=%0d b15_ar_minus_rlast=%0d b15_ar_minus_r=%0d b15_pix_beats=%0d b15_line_rises=%0d b15_frame_rises=%0d b15_crop_groups=%0d b15_raw_len=%0d\\n",
          b15_max_os,b15_ar_busy_hs,b15_short_burst,b15_rready_low,b15_rf_ovf,
          b15_max_rf_level,b15_stale_r,b15_ar,b15_r,b15_rlast,b15_last_ar_addr,
          b15_purge_close,b15_bursts,b15_ar-b15_rlast,b15_ar-b15_r,
          crop_beats,b15_line_rises,b15_frame_rises,source_groups,dut.a1_raw_len);
      end
    endtask"""),
    ("""      $display("B13_CHAIN_DONE frames=%0d cap=%0d pub=%0d enc=%0d exported=%0d bytes=%0d timeout=%0d retry=%0d giveup=%0d stale=%0d",
               NFRAMES,st_cap,st_raw_pub,st_enc,st_exp,cap_bytes,
               dut.raw_timeout_cnt,dut.raw_retry_cnt,dut.raw_retry_giveup,dut.raw_stale_guard);""",
     """      $display("B13_CHAIN_DONE frames=%0d cap=%0d pub=%0d enc=%0d exported=%0d bytes=%0d timeout=%0d retry=%0d giveup=%0d stale=%0d",
               NFRAMES,st_cap,st_raw_pub,st_enc,st_exp,cap_bytes,
               dut.raw_timeout_cnt,dut.raw_retry_cnt,dut.raw_retry_giveup,dut.raw_stale_guard);
      $display("B15_CHAIN_DONE max_os=%0d ar_busy_hs=%0d short_burst=%0d rready_low=%0d rf_ovf=%0d max_rf_level=%0d stale_r=%0d ar=%0d r=%0d rlast=%0d last_ar_addr=%0d purge_close=%0d bursts=%0d pix=%0d lines=%0d frames=%0d groups=%0d rawlen=%0d",
               b15_max_os,b15_ar_busy_hs,b15_short_burst,b15_rready_low,b15_rf_ovf,
               b15_max_rf_level,b15_stale_r,b15_ar,b15_r,b15_rlast,b15_last_ar_addr,
               b15_purge_close,b15_bursts,crop_beats,b15_line_rises,b15_frame_rises,
               source_groups,dut.a1_raw_len);"""),
    ("""        drive_frame(seed,ROI_Y+H);""",
     """        drive_frame(seed,CAM_H);   // T10.b15: drive the whole sensor height"""),
]


if __name__ == "__main__":
    patch("p2_paxi_model_b13.v", "p2_paxi_model_b15.v", MODEL_REPS)
    patch("tb_b13_chain.sv", "tb_b15_chain.sv", TB_REPS)
