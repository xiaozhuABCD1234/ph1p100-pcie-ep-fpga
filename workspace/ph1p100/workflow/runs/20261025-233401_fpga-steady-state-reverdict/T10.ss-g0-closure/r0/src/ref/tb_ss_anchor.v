`timescale 1ns/1ps
// =============================================================================
// tb_ss_anchor.v -- derived ONLY from the frozen b11 reference TB
// (src/ref/tb_b11_full.v, sha256 e278cea5...ac699).  DUT sources are unchanged.
//
// Allowed differences (fpga-design-guide.md 3.2 whitelist):
//   1  parameter FRAMES (default 4; control run uses 2); st_exp drain / final
//      gate use FRAMES.  The inherited informational "2*129600" READ_DONE
//      wait is intentionally left byte-identical to b11 (see DIFF.md).
//   2  SS_EVT event prints (read-only taps of the top-level st_* outputs).
//   3  slot-free pacing for frames 3/4 (waits until the target RAW slot is
//      FREE via the read-only st_slot_st observation).
//   4  per-frame watchdog: no st_exp increment for 8,000,000 cycles ->
//      SS_STALL + $finish (pass=0).
//   5  MAX_CYCLES = 30,000,000.
//   6  path registers widened to [4095:0].
//   7  stats line keeps the b11 field order and appends frames=/ss_pass=.
//   8  DEC/STAT/EVT absolute paths via +plusargs (sim/caps/).
// Extra TB-only markers: SS_META, SS_PACE, SS_STATS (documented in DIFF.md).
// =============================================================================
module tb_ss_anchor #(
    parameter integer CAM_W = 3864,
    parameter integer CAM_H = 2192,
    parameter integer ROI_X = 972,
    parameter integer ROI_Y = 556,
    parameter integer W     = 1920,
    parameter integer H     = 1080,
    parameter integer UART_DIV = 1,
    parameter integer LINE_GAP = 16,
    parameter integer FRAME_GAP = 400,
    parameter integer FRAMES = 4,
    parameter integer MAX_CYCLES = 30000000
) ();
    localparam integer CG = CAM_W / 4;
    localparam integer RAW_WORDS = 129600;
    localparam integer WD_LIMIT = 8000000;

    reg clk_cam = 1'b0, clk_a1 = 1'b0, clk_ddr = 1'b0, rst_n = 1'b0;
    always #2.6665 clk_cam = ~clk_cam;
    initial begin #1.7000; forever #2.6665 clk_a1 = ~clk_a1; end
    initial begin #0.4000; forever #2.5000 clk_ddr = ~clk_ddr; end

    reg  [39:0] tap_pix = 40'd0;
    reg         tap_v = 1'b0, tap_line = 1'b0, tap_frame = 1'b0, tap_vs = 1'b0;

    wire [31:0]  ddr_awaddr, ddr_araddr;
    wire         ddr_awvalid, ddr_awready, ddr_wvalid, ddr_wready;
    wire [255:0] ddr_wdata, ddr_rdata;
    wire         ddr_arvalid, ddr_arready, ddr_rvalid, ddr_rready;
    wire         uart_txd, dbg_byte_valid;
    wire [7:0]   dbg_byte;
    wire [31:0]  st_cap, st_enc, st_exp, st_expb, st_pub, st_rdrop, st_cdrop;
    wire [31:0]  st_geom, st_err, st_read, st_dup;

    wire [26:0]  p_awaddr, p_araddr;
    wire         p_awvalid, p_awready, p_wvalid, p_wlast, p_wready;
    wire [255:0] p_wdata;
    wire [31:0]  p_wstrb;
    wire         p_arvalid, p_arready, p_rlast, p_rvalid, p_rready;
    wire [255:0] p_rdata;
    wire [31:0]  n_ar, n_aw, n_w, n_r;
    wire [191:0] dbg_bridge;

    camera_a1_uart_top #(
        .CAM_W (CAM_W), .CAM_H (CAM_H), .ROI_X (ROI_X), .ROI_Y (ROI_Y),
        .W (W), .H (H), .UART_DIV (UART_DIV), .STS_DIV (0)
    ) dut (
        .clk_cam (clk_cam), .clk_a1 (clk_a1), .clk_uart (clk_a1), .rst_n (rst_n),
        .i_a_pixel (tap_pix), .i_a_pixel_valid (tap_v),
        .i_a_in_line (tap_line), .i_a_in_frame (tap_frame), .i_a_vsync (tap_vs),
        .i_ddr_rdy (1'b1),
        .i_dbg_tap (6'd0), .i_dbg_delay_done (1'b0), .i_dbg_rst_out (1'b0),
        .i_dbg_sync_wait (1'b0), .i_dbg_pkt_tgl (1'b0), .i_dbg_vs_tgl (1'b0),
        .i_dbg_clk_tgl (1'b0), .i_dbg_sys (64'd0), .i_dbg_bridge (dbg_bridge),
        .o_ddr_awaddr (ddr_awaddr), .o_ddr_awvalid (ddr_awvalid), .o_ddr_awready (ddr_awready),
        .o_ddr_wdata (ddr_wdata), .o_ddr_wvalid (ddr_wvalid), .o_ddr_wready (ddr_wready),
        .o_ddr_araddr (ddr_araddr), .o_ddr_arvalid (ddr_arvalid), .o_ddr_arready (ddr_arready),
        .i_ddr_rdata (ddr_rdata), .i_ddr_rvalid (ddr_rvalid), .o_ddr_rready (ddr_rready),
        .o_uart_txd (uart_txd), .o_dbg_byte (dbg_byte), .o_dbg_byte_valid (dbg_byte_valid),
        .o_st_cap_frames (st_cap), .o_st_enc_frames (st_enc), .o_st_exported (st_exp),
        .o_st_export_bytes (st_expb), .o_st_raw_pub (st_pub), .o_st_raw_drop (st_rdrop),
        .o_st_cmp_drop (st_cdrop), .o_st_geom_err (st_geom), .o_st_errors (st_err),
        .o_st_read_words (st_read), .o_st_dup_words (st_dup), .o_st_raw_sts ()
    );

    p2_ddr_bridge u_bridge (
        .clk_a1 (clk_a1), .rst_n (rst_n),
        .s_awaddr (ddr_awaddr), .s_awvalid (ddr_awvalid), .s_awready (ddr_awready),
        .s_wdata (ddr_wdata), .s_wvalid (ddr_wvalid), .s_wready (ddr_wready),
        .s_araddr (ddr_araddr), .s_arvalid (ddr_arvalid), .s_arready (ddr_arready),
        .s_rdata (ddr_rdata), .s_rvalid (ddr_rvalid), .s_rready (ddr_rready),
        .clk_ddr (clk_ddr), .ddr_rdy (1'b1),
        .paxi_awaddr (p_awaddr), .paxi_awvalid (p_awvalid), .paxi_awready (p_awready),
        .paxi_wdata (p_wdata), .paxi_wstrb (p_wstrb), .paxi_wvalid (p_wvalid),
        .paxi_wlast (p_wlast), .paxi_wready (p_wready),
        .paxi_araddr (p_araddr), .paxi_arvalid (p_arvalid), .paxi_arready (p_arready),
        .paxi_rdata (p_rdata), .paxi_rlast (p_rlast), .paxi_rvalid (p_rvalid),
        .paxi_rready (p_rready), .dbg_a1 (dbg_bridge)
    );

    p2_paxi_model_b11 #(.WORDS(524288), .AR_GAP(2), .R_GAP(3)) u_ddr (
        .clk (clk_ddr), .rst_n (rst_n), .rdy (1'b1),
        .awaddr (p_awaddr), .awvalid (p_awvalid), .awready (p_awready),
        .wdata (p_wdata), .wstrb (p_wstrb), .wvalid (p_wvalid), .wlast (p_wlast),
        .wready (p_wready),
        .araddr (p_araddr), .arvalid (p_arvalid), .arready (p_arready),
        .rdata (p_rdata), .rlast (p_rlast), .rvalid (p_rvalid), .rready (p_rready),
        .n_ar_hs (n_ar), .n_aw_hs (n_aw), .n_whs (n_w), .n_r_hs (n_r)
    );

    // ------------------------------------------------------------ capture
    integer fd, fs, fe, cap_bytes = 0, cycles = 0;
    reg [4095:0] stat_path = 4096'd0;
    reg [4095:0] dec_path  = 4096'd0;
    reg [4095:0] evt_path  = 4096'd0;
    integer t_rst = 0;
    integer t_sof [0:7];
    integer t_cam_end [0:7];
    integer prev_pub = 0, prev_enc = 0, prev_exp = 0, prev_read = 0;
    integer thr_read = RAW_WORDS;
    integer last_exp_t = 0;
    integer evt_i;

    // Final gate: b11 fields plus raw/cmp drops and cap; appended to stats.
    wire ss_pass = (st_cap == FRAMES) && (st_exp == FRAMES) && (st_enc == FRAMES) &&
                   (st_read == FRAMES*RAW_WORDS) && (st_dup == 0) && (st_err == 0) &&
                   (st_pub == FRAMES) && (st_geom == 0) && (st_rdrop == 0) &&
                   (st_cdrop == 0) && (dut.wd_fires == 0);

    always @(posedge clk_a1) begin
        if (rst_n && dbg_byte_valid) begin
            $fwrite(fd, "%0d\n", dbg_byte);
            cap_bytes = cap_bytes + 1;
        end
        cycles = cycles + 1;
        if (cycles > MAX_CYCLES) begin
            $display("B11_FULL_TIMEOUT cycles=%0d exported=%0d read=%0d", cycles, st_exp, st_read);
            $display("B11_FULL_RESULT pass=0");
            $finish;
        end
        if (rst_n) begin
            // ---- SS_EVT: read-only taps of the frozen top-level counters ----
            if (st_pub !== prev_pub) begin
                prev_pub = st_pub;
                $display("SS_EVT t=%0d kind=pub frame=%0d n=%0d", cycles, st_pub, st_pub);
                if (fe != 0) $fwrite(fe, "SS_EVT t=%0d kind=pub frame=%0d n=%0d\n", cycles, st_pub, st_pub);
            end
            if (st_read !== prev_read) begin
                prev_read = st_read;
                if (st_read >= thr_read) begin
                    $display("SS_EVT t=%0d kind=read frame=%0d n=%0d", cycles, thr_read/RAW_WORDS, st_read);
                    if (fe != 0) $fwrite(fe, "SS_EVT t=%0d kind=read frame=%0d n=%0d\n", cycles, thr_read/RAW_WORDS, st_read);
                    thr_read = thr_read + RAW_WORDS;
                end
            end
            if (st_enc !== prev_enc) begin
                prev_enc = st_enc;
                $display("SS_EVT t=%0d kind=enc frame=%0d n=%0d", cycles, st_enc, st_enc);
                if (fe != 0) $fwrite(fe, "SS_EVT t=%0d kind=enc frame=%0d n=%0d\n", cycles, st_enc, st_enc);
            end
            if (st_exp !== prev_exp) begin
                prev_exp = st_exp;
                last_exp_t = cycles;
                $display("SS_EVT t=%0d kind=exp frame=%0d n=%0d", cycles, st_exp, st_exp);
                if (fe != 0) $fwrite(fe, "SS_EVT t=%0d kind=exp frame=%0d n=%0d\n", cycles, st_exp, st_exp);
            end
            // ---- per-frame watchdog (8,000,000 cycles with no export) ----
            if ((cycles - last_exp_t) > WD_LIMIT) begin
                $display("SS_STALL frame=%0d cycles=%0d read=%0d enc=%0d exported=%0d",
                         st_exp + 1, cycles, st_read, st_enc, st_exp);
                $display("B11_FULL_RESULT pass=0");
                $finish;
            end
        end
    end

    function [9:0] smp;
        input integer y;
        input integer x;
        smp = (x*3 + y*5 + ((x ^ y) & 7)*17) & 1023;
    endfunction

    // Pacing: wait until the target RAW slot is FREE (read-only slot_st tap).
    task wait_slot_free;
        input integer slot;
        begin
            while (((slot == 0) && (dut.raw_slot_st[1:0] != 2'b00)) ||
                   ((slot != 0) && (dut.raw_slot_st[3:2] != 2'b00)))
                @(negedge clk_a1);
        end
    endtask

    task drive_frame;
        input integer k;
        integer y, g;
        reg [9:0] s0, s1, s2, s3;
        begin
            @(negedge clk_cam);
            tap_frame = 1'b1; tap_vs = 1'b1;
            t_sof[k] = cycles;
            $display("SS_EVT t=%0d kind=sof frame=%0d n=%0d", cycles, k, k);
            if (fe != 0) $fwrite(fe, "SS_EVT t=%0d kind=sof frame=%0d n=%0d\n", cycles, k, k);
            for (y = 0; y < ROI_Y + H; y = y + 1) begin
                @(negedge clk_cam);
                tap_line = 1'b1; tap_v = 1'b0;
                for (g = 0; g < CG; g = g + 1) begin
                    s0 = smp(y, g*4 + 0); s1 = smp(y, g*4 + 1);
                    s2 = smp(y, g*4 + 2); s3 = smp(y, g*4 + 3);
                    tap_pix = {s3[1:0], s2[1:0], s1[1:0], s0[1:0],
                               s3[9:2], s2[9:2], s1[9:2], s0[9:2]};
                    tap_v = 1'b1;
                    @(negedge clk_cam);
                end
                tap_v = 1'b0; tap_line = 1'b0;
                repeat (LINE_GAP) @(negedge clk_cam);
            end
            t_cam_end[k] = cycles;
            $display("SS_EVT t=%0d kind=cam_end frame=%0d n=%0d", cycles, k, k);
            if (fe != 0) $fwrite(fe, "SS_EVT t=%0d kind=cam_end frame=%0d n=%0d\n", cycles, k, k);
            tap_frame = 1'b0; tap_vs = 1'b0;
            repeat (FRAME_GAP) @(negedge clk_cam);
        end
    endtask

    initial begin
        fe = 0;
        for (evt_i = 0; evt_i < 8; evt_i = evt_i + 1) begin
            t_sof[evt_i] = 0;
            t_cam_end[evt_i] = 0;
        end
        if (!$value$plusargs("STAT=%s", stat_path)) stat_path = "ss.stats";
        if (!$value$plusargs("DEC=%s", dec_path))   dec_path  = "ss.dec";
        if ($value$plusargs("EVT=%s", evt_path))    fe = $fopen(evt_path, "w");
        fd = $fopen(dec_path, "w");
        fs = $fopen(stat_path, "w");
        repeat (20) @(negedge clk_a1);
        rst_n = 1'b1;
        t_rst = cycles;
        $display("SS_META t_rst=%0d frames=%0d max_cycles=%0d uart_div=%0d",
                 t_rst, FRAMES, MAX_CYCLES, UART_DIV);
        if (fe != 0) $fwrite(fe, "SS_META t_rst=%0d frames=%0d max_cycles=%0d uart_div=%0d\n",
                             t_rst, FRAMES, MAX_CYCLES, UART_DIV);
        repeat (40) @(negedge clk_a1);
        drive_frame(1);              // frame 1 -> raw slot 0
        drive_frame(2);              // frame 2 -> raw slot 1
        if (FRAMES >= 3) begin       // frame 3: wait for slot 0 to be read+closed
            wait_slot_free(0);
            $display("SS_PACE frame=3 slot=0 t=%0d read=%0d slot_st=%0d",
                     cycles, st_read, dut.raw_slot_st[3:0]);
            if (fe != 0) $fwrite(fe, "SS_PACE frame=3 slot=0 t=%0d read=%0d slot_st=%0d\n",
                                 cycles, st_read, dut.raw_slot_st[3:0]);
            drive_frame(3);
        end
        if (FRAMES >= 4) begin       // frame 4: wait for slot 1 to be read+closed
            wait_slot_free(1);
            $display("SS_PACE frame=4 slot=1 t=%0d read=%0d slot_st=%0d",
                     cycles, st_read, dut.raw_slot_st[3:0]);
            if (fe != 0) $fwrite(fe, "SS_PACE frame=4 slot=1 t=%0d read=%0d slot_st=%0d\n",
                                 cycles, st_read, dut.raw_slot_st[3:0]);
            drive_frame(4);
        end
        // inherited b11 informational wait, intentionally left byte-identical
        while ((st_read < 2*129600) && (cycles < MAX_CYCLES)) @(negedge clk_a1);
        $display("B11_FULL_READ_DONE read=%0d enc=%0d exported=%0d cycles=%0d",
                 st_read, st_enc, st_exp, cycles);
        while ((st_exp < FRAMES) && (cycles < MAX_CYCLES)) @(negedge clk_a1);
        repeat (2000) @(negedge clk_a1);
        $fwrite(fs, "cap=%0d enc=%0d exported=%0d exp_bytes=%0d raw_pub=%0d raw_drop=%0d cmp_drop=%0d geom=%0d err=%0d read=%0d dup=%0d cap_bytes=%0d cycles=%0d wd=%0d ar=%0d r=%0d frames=%0d ss_pass=%0d\n",
                st_cap, st_enc, st_exp, st_expb, st_pub, st_rdrop, st_cdrop,
                st_geom, st_err, st_read, st_dup, cap_bytes, cycles,
                dut.wd_fires, n_ar, n_r, FRAMES, ss_pass);
        $display("SS_STATS cap=%0d enc=%0d exported=%0d read=%0d cycles=%0d frames=%0d ss_pass=%0d",
                 st_cap, st_enc, st_exp, st_read, cycles, FRAMES, ss_pass);
        $fclose(fd); $fclose(fs); if (fe != 0) $fclose(fe);
        $display("B11_FULL_DONE enc=%0d exported=%0d read=%0d dup=%0d err=%0d wd=%0d",
                 st_enc, st_exp, st_read, st_dup, st_err, dut.wd_fires);
        $display("B11_FULL_BRIDGE ar=%0d r=%0d rlast=%0d stale=%0d block=%0d",
                 dbg_bridge[63:32], dbg_bridge[127:96], dbg_bridge[159:128],
                 dbg_bridge[191:160], dbg_bridge[95:64]);
        $display("B11_FULL_RESULT pass=%0d", ss_pass ? 1 : 0);
        $finish;
    end
endmodule
