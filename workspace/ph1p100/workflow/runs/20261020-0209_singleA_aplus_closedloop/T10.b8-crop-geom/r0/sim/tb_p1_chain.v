`timescale 1ns/1ps
// =============================================================================
// tb_camera_a1_uart_top.v -- P1 full-chain testbench (offline, no TD).
//
// Drives the real 4K RAW10 tap (w_a_pixel[39:0] style) with deterministic
// synthetic patterns, instantiates the integration top and the behavioural DDR
// model, and captures the exact byte sequence handed to the UART transmitter.
//
// MODE 0 : one 1920x1080 frame, smooth gradient pattern (compressible)
// MODE 1 : one 1920x1080 frame, xorshift32 pattern (incompressible)
// MODE 2 : small geometry fault run (bad frame / reset / overflow / recovery)
//
// The TB stops driving after ROI_Y+H lines: the crop contract validates every
// camera line up to and including the last ROI line and deliberately ignores
// trailing lines, which cannot change already captured ROI data.
//
// Plusargs: +MODE=n +OUT=<uart bytes, one decimal byte per line> +STAT=<stats>
// =============================================================================
module tb_camera_a1_uart_top #(
    parameter integer CAM_W = 3840,
    parameter integer CAM_H = 2160,
    parameter integer ROI_X = 960,
    parameter integer ROI_Y = 540,
    parameter integer W     = 1920,
    parameter integer H     = 1080,
    parameter integer UART_DIV = 1,
    parameter integer AW_GAP = 2,
    parameter integer R_GAP  = 3,
    parameter integer LINE_GAP = 40,
    parameter integer FRAME_GAP = 600,
    parameter integer MAX_CYCLES = 120000000
) ();
    localparam integer CG = CAM_W / 4;

    reg clk_cam = 1'b0;
    reg clk_a1  = 1'b0;
    reg clk_uart = 1'b0;
    reg rst_n = 1'b0;

    always #2.6665 clk_cam = ~clk_cam;                  // 187.5 MHz
    initial begin #1.7000; forever #2.6665 clk_a1 = ~clk_a1; end
    always #0.500 clk_uart = ~clk_uart;                 // sim-only fast baud clock

    reg  [39:0] tap_pix = 40'd0;
    reg         tap_v = 1'b0, tap_line = 1'b0, tap_frame = 1'b0, tap_vs = 1'b0;

    wire [31:0]  ddr_awaddr, ddr_araddr;
    wire         ddr_awvalid, ddr_awready, ddr_wvalid, ddr_wready;
    wire [255:0] ddr_wdata;
    wire         ddr_arvalid, ddr_arready, ddr_rvalid, ddr_rready;
    wire [255:0] ddr_rdata;
    wire         uart_txd;
    wire [7:0]   dbg_byte;
    wire         dbg_byte_valid;
    wire [31:0]  st_cap, st_enc, st_exp, st_exp_bytes, st_raw_pub, st_raw_drop;
    wire [31:0]  st_cmp_drop, st_geom, st_err;
    wire [31:0]  st_read_words, st_dup_words;

    camera_a1_uart_top #(
        .CAM_W (CAM_W), .CAM_H (CAM_H), .ROI_X (ROI_X), .ROI_Y (ROI_Y),
        .W (W), .H (H), .UART_DIV (UART_DIV)
    ) dut (
        .clk_cam (clk_cam), .clk_a1 (clk_a1), .clk_uart (clk_uart), .rst_n (rst_n),
        .i_a_pixel (tap_pix), .i_a_pixel_valid (tap_v),
        .i_a_in_line (tap_line), .i_a_in_frame (tap_frame), .i_a_vsync (tap_vs),
        .i_dbg_tap (6'd0), .i_dbg_delay_done (1'b0), .i_dbg_rst_out (1'b0),
        .i_dbg_sync_wait (1'b0), .i_dbg_pkt_tgl (1'b0), .i_dbg_vs_tgl (1'b0),
        .i_dbg_clk_tgl (1'b0), .i_dbg_sys (64'd0),
        .o_ddr_awaddr (ddr_awaddr), .o_ddr_awvalid (ddr_awvalid), .o_ddr_awready (ddr_awready),
        .o_ddr_wdata (ddr_wdata), .o_ddr_wvalid (ddr_wvalid), .o_ddr_wready (ddr_wready),
        .o_ddr_araddr (ddr_araddr), .o_ddr_arvalid (ddr_arvalid), .o_ddr_arready (ddr_arready),
        .i_ddr_rdata (ddr_rdata), .i_ddr_rvalid (ddr_rvalid), .o_ddr_rready (ddr_rready),
        .o_uart_txd (uart_txd),
        .o_dbg_byte (dbg_byte), .o_dbg_byte_valid (dbg_byte_valid),
        .o_st_cap_frames (st_cap), .o_st_enc_frames (st_enc), .o_st_exported (st_exp),
        .o_st_export_bytes (st_exp_bytes), .o_st_raw_pub (st_raw_pub),
        .o_st_raw_drop (st_raw_drop), .o_st_cmp_drop (st_cmp_drop),
        .o_st_geom_err (st_geom), .o_st_errors (st_err),
        .o_st_read_words (st_read_words), .o_st_dup_words (st_dup_words)
    );

    a1_ddr_model #(.WORDS(262144), .AW_GAP(AW_GAP), .R_GAP(R_GAP)) u_ddr (
        .clk (clk_a1), .rst_n (rst_n),
        .awaddr (ddr_awaddr), .awvalid (ddr_awvalid), .awready (ddr_awready),
        .wdata (ddr_wdata), .wvalid (ddr_wvalid), .wready (ddr_wready),
        .araddr (ddr_araddr), .arvalid (ddr_arvalid), .arready (ddr_arready),
        .rdata (ddr_rdata), .rvalid (ddr_rvalid), .rready (ddr_rready)
    );

    // ------------------------------------------------------------ capture
    integer fd;
    integer fs;
    integer cap_bytes = 0;
    reg [1023:0] out_path, stat_path;
    integer mode = 0;
    integer cycles = 0;
    integer trace_on = 0;
    integer trace_cnt = 0;

    always @(posedge clk_a1) begin
        if (rst_n && trace_on && dut.a1_in_valid && dut.a1_in_ready && trace_cnt < 14) begin
            $display("ACC t=%0t n=%0d sof=%0d pix=%h istate=%0d fa=%0d",
                     $time, dut.grp_sent, dut.a1_in_sof, dut.a1_in_pix,
                     dut.u_a1.istate, dut.u_a1.frame_active);
            trace_cnt = trace_cnt + 1;
        end
        if (rst_n && trace_on && (dut.u_a1.frame_commit || dut.u_a1.frame_abort) && trace_cnt < 30) begin
            $display("CMT/ABT t=%0t commit=%0d abort=%0d xlen=%0d",
                     $time, dut.u_a1.frame_commit, dut.u_a1.frame_abort, dut.u_a1.xlen_r);
            trace_cnt = trace_cnt + 1;
        end
    end

    always @(posedge clk_uart) begin
        if (rst_n && dbg_byte_valid) begin
            $fwrite(fd, "%0d\n", dbg_byte);
            cap_bytes = cap_bytes + 1;
        end
    end

    always @(posedge clk_a1) begin
        cycles = cycles + 1;
        if (cycles > MAX_CYCLES) begin
            $display("TB_TIMEOUT cycles=%0d", cycles);
            write_stats;
            $fclose(fd);
            $fclose(fs);
            $finish;
        end
    end

    // --------------------------------------------------------- patterns
    reg [31:0] lfsr;

    function [9:0] smp;
        input integer y;
        input integer x;
        begin
            smp = (x*3 + y*5 + ((x ^ y) & 7)*17) & 1023;
        end
    endfunction

    task drive_frame;
        input integer pat;
        input integer short_line;
        input integer nlines;
        integer y, g;
        reg [9:0] s0, s1, s2, s3;
        reg [31:0] st;
        begin
            @(negedge clk_cam);
            tap_frame = 1'b1;
            tap_vs    = 1'b1;
            lfsr      = 32'h1234_5678;
            for (y = 0; y < nlines; y = y + 1) begin
                @(negedge clk_cam);
                tap_line = 1'b1;
                tap_v    = 1'b0;
                for (g = 0; g < CG; g = g + 1) begin
                    if (pat == 1) begin
                        st   = lfsr;
                        st   = st ^ (st << 13);
                        st   = st ^ (st >> 17);
                        st   = st ^ (st << 5);
                        lfsr = st;
                        s0 = st[9:0]; s1 = st[19:10]; s2 = st[29:20]; s3 = st[31:22];
                    end else begin
                        s0 = smp(y, g*4 + 0);
                        s1 = smp(y, g*4 + 1);
                        s2 = smp(y, g*4 + 2);
                        s3 = smp(y, g*4 + 3);
                    end
                    tap_pix = {s3[1:0], s2[1:0], s1[1:0], s0[1:0],
                               s3[9:2], s2[9:2], s1[9:2], s0[9:2]};
                    tap_v   = 1'b1;
                    if (short_line && (y == 3) && (g == CG-1)) tap_v = 1'b0;
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

    // Waits for n NEW exports relative to the entry count: a mid-run reset
    // clears the DUT counter, so an absolute target would hang (probe r1).
    task wait_export;
        input integer n;
        integer t, target;
        begin
            target = st_exp + n;
            t = 0;
            while ((st_exp < target) && (t < 20000000)) begin
                @(negedge clk_a1);
                t = t + 1;
            end
            if (st_exp < target) $display("WAIT_EXPORT_TIMEOUT want=%0d got=%0d", target, st_exp);
        end
    endtask

    task write_stats;
        begin
            $fwrite(fs, "STAT mode=%0d cap=%0d enc=%0d exported=%0d exp_bytes=%0d",
                    mode, st_cap, st_enc, st_exp, st_exp_bytes);
            $fwrite(fs, " raw_pub=%0d raw_drop=%0d cmp_drop=%0d geom=%0d err=%0d cap_bytes=%0d cycles=%0d",
                    st_raw_pub, st_raw_drop, st_cmp_drop, st_geom, st_err, cap_bytes, cycles);
            $fwrite(fs, " read_words=%0d dup_words=%0d\n", st_read_words, st_dup_words);
        end
    endtask

    // ------------------------------------------------------------- sequence
    initial begin
        if (!$value$plusargs("MODE=%d", mode)) mode = 0;
        if ($test$plusargs("TRACE")) trace_on = 1;
        if (!$value$plusargs("OUT=%s", out_path)) out_path = "uart_bytes.dec";
        if (!$value$plusargs("STAT=%s", stat_path)) stat_path = "tb_stats.txt";
        fd = $fopen(out_path, "w");
        fs = $fopen(stat_path, "w");
        if ((fd == 0) || (fs == 0)) begin
            $display("TB_OPEN_FAIL %0s", out_path);
            $finish;
        end

        tap_pix = 40'd0; tap_v = 0; tap_line = 0; tap_frame = 0; tap_vs = 0;
        rst_n = 1'b0;
        repeat (20) @(negedge clk_a1);
        rst_n = 1'b1;
        repeat (40) @(negedge clk_a1);

        if (mode == 0) begin
            drive_frame(0, 0, ROI_Y + H);
            wait_export(1);
            repeat (2000) @(negedge clk_a1);
        end else if (mode == 1) begin
            drive_frame(1, 0, ROI_Y + H);
            wait_export(1);
            repeat (2000) @(negedge clk_a1);
        end else begin
            // phase A: good frame
            drive_frame(0, 0, ROI_Y + H);
            wait_export(1);
            repeat (2000) @(negedge clk_a1);
            // phase B: one camera line loses its last group -> bad frame
            drive_frame(0, 1, ROI_Y + H);
            repeat (800) @(negedge clk_a1);
            // phase C: reset in the middle of a good frame -> nothing published
            fork
                drive_frame(0, 0, ROI_Y + H);
                begin
                    repeat (900) @(negedge clk_a1);   // late in the 352-cycle phase frame
                    rst_n = 1'b0;
                    repeat (40) @(negedge clk_a1);
                    rst_n = 1'b1;
                end
            join
            repeat (3000) @(negedge clk_a1);
            // phase D: recovery frame (one new export after the phase C reset)
            drive_frame(0, 0, ROI_Y + H);
            wait_export(1);
            repeat (2000) @(negedge clk_a1);
            // phase E: eight quick frames with a slow exporter -> overflow/drop, no corruption
            drive_frame(0, 0, ROI_Y + H);
            drive_frame(0, 0, ROI_Y + H);
            drive_frame(0, 0, ROI_Y + H);
            drive_frame(0, 0, ROI_Y + H);
            drive_frame(0, 0, ROI_Y + H);
            drive_frame(0, 0, ROI_Y + H);
            drive_frame(0, 0, ROI_Y + H);
            drive_frame(0, 0, ROI_Y + H);
            repeat (10000) @(negedge clk_a1);   // short tail: phase-E export cannot finish
        end

        repeat (500) @(negedge clk_a1);
        write_stats;
        $fclose(fd);
        $fclose(fs);
        $display("TB_DONE mode=%0d exported=%0d bytes=%0d err=%0d", mode, st_exp, st_exp_bytes, st_err);
        $finish;
    end
endmodule
