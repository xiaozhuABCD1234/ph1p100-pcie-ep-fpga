`timescale 1ns/1ps
// =============================================================================
// tb_b11_full.v -- T10.b11 integration: real 1920x1080 chain, TWO frames, with
// the real p2_ddr_bridge CDC (187.5 MHz <-> 200 MHz) and the PAXI DDR model.
//
// crop -> CDC -> raw store -> feeder -> REAL a1_frame_top + a1_deflate_core
//      -> cmp store -> exporter (UART bytes captured) -> arb2 -> bridge -> PAXI.
//
// Gate: read_words = 2 x 129600, enc_frames = 2, exported = 2, dup = 0,
//       geom = 0, err = 0, raw_pub = 2, feeder watchdog never fires.
// =============================================================================
module tb_b11_full #(
    parameter integer CAM_W = 3864,
    parameter integer CAM_H = 2192,
    parameter integer ROI_X = 972,
    parameter integer ROI_Y = 556,
    parameter integer W     = 1920,
    parameter integer H     = 1080,
    parameter integer UART_DIV = 1,
    parameter integer LINE_GAP = 16,
    parameter integer FRAME_GAP = 400,
    parameter integer MAX_CYCLES = 60000000
) ();
    localparam integer CG = CAM_W / 4;

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
    integer fd, fs, cap_bytes = 0, cycles = 0;
    reg [1023:0] stat_path;
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
    end

    function [9:0] smp;
        input integer y;
        input integer x;
        smp = (x*3 + y*5 + ((x ^ y) & 7)*17) & 1023;
    endfunction

    task drive_frame;
        integer y, g;
        reg [9:0] s0, s1, s2, s3;
        begin
            @(negedge clk_cam);
            tap_frame = 1'b1; tap_vs = 1'b1;
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
            tap_frame = 1'b0; tap_vs = 1'b0;
            repeat (FRAME_GAP) @(negedge clk_cam);
        end
    endtask

    initial begin
        if (!$value$plusargs("STAT=%s", stat_path)) stat_path = "full.stats";
        fd = $fopen("full.dec", "w");
        fs = $fopen(stat_path, "w");
        repeat (20) @(negedge clk_a1);
        rst_n = 1'b1;
        repeat (40) @(negedge clk_a1);
        drive_frame;              // frame 1 -> raw slot 0
        drive_frame;              // frame 2 -> raw slot 1
        // drain: wait (bounded) until both raw frames were read AND exported
        while ((st_read < 2*129600) && (cycles < MAX_CYCLES)) @(negedge clk_a1);
        $display("B11_FULL_READ_DONE read=%0d enc=%0d exported=%0d cycles=%0d",
                 st_read, st_enc, st_exp, cycles);
        while ((st_exp < 2) && (cycles < MAX_CYCLES)) @(negedge clk_a1);
        repeat (2000) @(negedge clk_a1);
        $fwrite(fs, "cap=%0d enc=%0d exported=%0d exp_bytes=%0d raw_pub=%0d raw_drop=%0d cmp_drop=%0d geom=%0d err=%0d read=%0d dup=%0d cap_bytes=%0d cycles=%0d wd=%0d ar=%0d r=%0d\n",
                st_cap, st_enc, st_exp, st_expb, st_pub, st_rdrop, st_cdrop,
                st_geom, st_err, st_read, st_dup, cap_bytes, cycles,
                dut.wd_fires, n_ar, n_r);
        $fclose(fd); $fclose(fs);
        $display("B11_FULL_DONE enc=%0d exported=%0d read=%0d dup=%0d err=%0d wd=%0d",
                 st_enc, st_exp, st_read, st_dup, st_err, dut.wd_fires);
        $display("B11_FULL_BRIDGE ar=%0d r=%0d rlast=%0d stale=%0d block=%0d",
                 dbg_bridge[63:32], dbg_bridge[127:96], dbg_bridge[159:128],
                 dbg_bridge[191:160], dbg_bridge[95:64]);
        $display("B11_FULL_RESULT pass=%0d",
                 ((st_exp == 2) && (st_enc == 2) && (st_read == 2*129600) &&
                  (st_dup == 0) && (st_err == 0) && (st_pub == 2) &&
                  (dut.wd_fires == 0) && (st_geom == 0)) ? 1 : 0);
        $finish;
    end
endmodule
