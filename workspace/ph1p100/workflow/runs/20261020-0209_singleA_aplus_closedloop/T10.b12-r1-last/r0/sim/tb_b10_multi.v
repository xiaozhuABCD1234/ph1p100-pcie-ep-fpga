`timescale 1ns/1ps
// =============================================================================
// tb_b10_multi.v -- T10.b10 three consecutive compressed frames through the
// real chain (crop -> CDC -> raw store -> A+ core -> cmp store -> exporter).
// The captured UART byte stream is parsed by check_multi.py: every frame's
// 44-byte header, stream_len, stream CRC and zlib decode are checked, and the
// stream must consist of exactly frame, (status packet)?, frame, ... with no
// insertion inside a frame.
// =============================================================================
module tb_b10_multi #(
    parameter integer CAM_W = 128,
    parameter integer CAM_H = 16,
    parameter integer ROI_X = 0,
    parameter integer ROI_Y = 0,
    parameter integer W     = 64,
    parameter integer H     = 8,
    parameter integer UART_DIV = 1,
    parameter integer STA_DIV  = 3000,
    parameter integer LINE_GAP = 4,
    parameter integer FRAME_GAP = 200,
    parameter integer MAX_CYCLES = 4000000
) ();
    localparam integer CG = CAM_W / 4;

    reg clk_cam = 0, clk_a1 = 0, clk_uart = 0, rst_n = 0;
    always #2.6665 clk_cam = ~clk_cam;
    initial begin #1.7000; forever #2.6665 clk_a1 = ~clk_a1; end
    always #0.500 clk_uart = ~clk_uart;

    reg  [39:0] tap_pix = 0;
    reg         tap_v = 0, tap_line = 0, tap_frame = 0, tap_vs = 0;

    wire [31:0]  ddr_awaddr, ddr_araddr;
    wire         ddr_awvalid, ddr_awready, ddr_wvalid, ddr_wready;
    wire [255:0] ddr_wdata, ddr_rdata;
    wire         ddr_arvalid, ddr_arready, ddr_rvalid, ddr_rready;
    wire         uart_txd, dbg_valid;
    wire [7:0]   dbg_byte;
    wire [31:0]  st_cap, st_enc, st_exp, st_expb, st_pub, st_rdrop, st_cdrop;
    wire [31:0]  st_geom, st_err, st_read, st_dup;

    camera_a1_uart_top #(
        .CAM_W (CAM_W), .CAM_H (CAM_H), .ROI_X (ROI_X), .ROI_Y (ROI_Y),
        .W (W), .H (H), .UART_DIV (UART_DIV), .STS_DIV (STA_DIV)
    ) dut (
        .clk_cam (clk_cam), .clk_a1 (clk_a1), .clk_uart (clk_uart), .rst_n (rst_n),
        .i_a_pixel (tap_pix), .i_a_pixel_valid (tap_v),
        .i_a_in_line (tap_line), .i_a_in_frame (tap_frame), .i_a_vsync (tap_vs),
        .i_ddr_rdy (1'b1),
        .i_dbg_tap (6'd0), .i_dbg_delay_done (1'b0), .i_dbg_rst_out (1'b0),
        .i_dbg_sync_wait (1'b0), .i_dbg_pkt_tgl (1'b0), .i_dbg_vs_tgl (1'b0),
        .i_dbg_clk_tgl (1'b0), .i_dbg_sys (64'd0),
        .o_ddr_awaddr (ddr_awaddr), .o_ddr_awvalid (ddr_awvalid), .o_ddr_awready (ddr_awready),
        .o_ddr_wdata (ddr_wdata), .o_ddr_wvalid (ddr_wvalid), .o_ddr_wready (ddr_wready),
        .o_ddr_araddr (ddr_araddr), .o_ddr_arvalid (ddr_arvalid), .o_ddr_arready (ddr_arready),
        .i_ddr_rdata (ddr_rdata), .i_ddr_rvalid (ddr_rvalid), .o_ddr_rready (ddr_rready),
        .o_uart_txd (uart_txd), .o_dbg_byte (dbg_byte), .o_dbg_byte_valid (dbg_valid),
        .o_st_cap_frames (st_cap), .o_st_enc_frames (st_enc), .o_st_exported (st_exp),
        .o_st_export_bytes (st_expb), .o_st_raw_pub (st_pub), .o_st_raw_drop (st_rdrop),
        .o_st_cmp_drop (st_cdrop), .o_st_geom_err (st_geom), .o_st_errors (st_err),
        .o_st_read_words (st_read), .o_st_dup_words (st_dup), .o_st_raw_sts ()
    );

    a1_ddr_model #(.WORDS(262144), .AW_GAP(2), .R_GAP(2)) u_ddr (
        .clk (clk_a1), .rst_n (rst_n),
        .awaddr (ddr_awaddr), .awvalid (ddr_awvalid), .awready (ddr_awready),
        .wdata (ddr_wdata), .wvalid (ddr_wvalid), .wready (ddr_wready),
        .araddr (ddr_araddr), .arvalid (ddr_arvalid), .arready (ddr_arready),
        .rdata (ddr_rdata), .rvalid (ddr_rvalid), .rready (ddr_rready)
    );

    integer fd, fs, cap_bytes = 0, cycles = 0, nframes = 0;
    reg [1023:0] out_path, stat_path;

    always @(posedge clk_uart) begin
        if (rst_n && dbg_valid) begin
            $fwrite(fd, "%0d\n", dbg_byte);
            cap_bytes = cap_bytes + 1;
        end
    end

    always @(posedge clk_a1) begin
        cycles = cycles + 1;
        if (cycles > MAX_CYCLES) begin
            $display("B10_MULTI_TIMEOUT cycles=%0d exported=%0d", cycles, st_exp);
            $fwrite(fs, "TIMEOUT cap=%0d enc=%0d exported=%0d bytes=%0d\n", st_cap, st_enc, st_exp, cap_bytes);
            $fclose(fd); $fclose(fs);
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
            tap_frame = 1; tap_vs = 1;
            for (y = 0; y < H; y = y + 1) begin
                @(negedge clk_cam);
                tap_line = 1; tap_v = 0;
                for (g = 0; g < CG; g = g + 1) begin
                    s0 = smp(y, g*4 + 0); s1 = smp(y, g*4 + 1);
                    s2 = smp(y, g*4 + 2); s3 = smp(y, g*4 + 3);
                    tap_pix = {s3[1:0], s2[1:0], s1[1:0], s0[1:0],
                               s3[9:2], s2[9:2], s1[9:2], s0[9:2]};
                    tap_v = 1'b1;
                    @(negedge clk_cam);
                end
                tap_v = 0; tap_line = 0;
                repeat (LINE_GAP) @(negedge clk_cam);
            end
            tap_frame = 0; tap_vs = 0;
            repeat (FRAME_GAP) @(negedge clk_cam);
        end
    endtask

    task wait_export(input integer n);
        integer t, target;
        begin
            target = st_exp + n; t = 0;
            while ((st_exp < target) && (t < 2000000)) begin
                @(negedge clk_a1); t = t + 1;
            end
            if (st_exp < target) $display("B10_MULTI_WAIT_TIMEOUT want=%0d got=%0d", target, st_exp);
        end
    endtask

    initial begin
        if (!$value$plusargs("OUT=%s", out_path)) out_path = "multi.dec";
        if (!$value$plusargs("STAT=%s", stat_path)) stat_path = "multi.stats";
        fd = $fopen(out_path, "w");
        fs = $fopen(stat_path, "w");
        repeat (20) @(negedge clk_a1);
        rst_n = 1;
        repeat (40) @(negedge clk_a1);
        nframes = 0;
        repeat (3) begin
            drive_frame;
            wait_export(1);
            nframes = nframes + 1;
            repeat (2000) @(negedge clk_a1);
        end
        repeat (3000) @(negedge clk_a1);
        $fwrite(fs, "cap=%0d enc=%0d exported=%0d exp_bytes=%0d raw_pub=%0d raw_drop=%0d cmp_drop=%0d geom=%0d err=%0d read=%0d dup=%0d cap_bytes=%0d cycles=%0d\n",
                st_cap, st_enc, st_exp, st_expb, st_pub, st_rdrop, st_cdrop,
                st_geom, st_err, st_read, st_dup, cap_bytes, cycles);
        $fclose(fd); $fclose(fs);
        $display("B10_MULTI_DONE frames=%0d exported=%0d bytes=%0d err=%0d", nframes, st_exp, cap_bytes, st_err);
        $finish;
    end
endmodule
