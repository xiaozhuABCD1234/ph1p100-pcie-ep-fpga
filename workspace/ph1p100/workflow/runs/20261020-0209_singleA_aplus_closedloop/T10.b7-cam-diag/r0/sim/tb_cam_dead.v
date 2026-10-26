`timescale 1ns/1ps
// =============================================================================
// tb_cam_dead.v -- "camera byte clock is dead" branch (T10.b7 guide section 9.2)
//
// 1. Full camera_a1_uart_top with clk_cam HELD AT 0 for the whole run: the
//    clk_cam -> clk_a1 mailbox never toggles, so every camera field must be 0,
//    yet the 97-byte status packet must still be emitted at the STS_DIV tick
//    and the A1 chain must not hang (the exporter is the only producer here).
// 2. A standalone cam_diag_mailbox: after the slow clock stops, the fast-side
//    snapshot must keep the last published value (no timeouts, no X).
//
// Plusargs: +OUT=<bytes> +NPKT=<packets>
// =============================================================================
module tb_cam_dead;
    reg clk_a1 = 1'b0;
    reg clk_cam = 1'b0;
    reg rst_n  = 1'b0;
    always #2.6665 clk_a1 = ~clk_a1;
    always #4.4900 clk_cam = ~clk_cam;    // 111.375 MHz byte clock, alive

    // ---------------------------------------------------------------- DUT 1
    wire [39:0] tap_pix = 40'd0;
    wire [31:0] ddr_awaddr, ddr_araddr;
    wire        ddr_awvalid, ddr_awready, ddr_wvalid, ddr_wready;
    wire [255:0] ddr_wdata;
    wire        ddr_arvalid, ddr_arready, ddr_rvalid, ddr_rready;
    wire [255:0] ddr_rdata;
    wire        uart_txd;
    wire [7:0]  dbg_byte;
    wire        dbg_byte_valid;
    wire [31:0] st_cap, st_enc, st_exp, st_exp_bytes, st_raw_pub, st_raw_drop;
    wire [31:0] st_cmp_drop, st_geom, st_err, st_read_words, st_dup_words;

    camera_a1_uart_top #(
        .CAM_W (32), .CAM_H (4), .ROI_X (0), .ROI_Y (0), .W (8), .H (2),
        .UART_DIV (1), .HB_DIV (0), .STS_DIV (4096)
    ) dut (
        .clk_cam (clk_cam),              // byte clock alive, no CSI activity
        .clk_a1 (clk_a1), .clk_uart (clk_a1), .rst_n (rst_n),
        .i_a_pixel (tap_pix), .i_a_pixel_valid (1'b0),
        .i_a_in_line (1'b0), .i_a_in_frame (1'b0), .i_a_vsync (1'b0),
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

    a1_ddr_model #(.WORDS(262144), .AW_GAP(2), .R_GAP(3)) u_ddr (
        .clk (clk_a1), .rst_n (rst_n),
        .awaddr (ddr_awaddr), .awvalid (ddr_awvalid), .awready (ddr_awready),
        .wdata (ddr_wdata), .wvalid (ddr_wvalid), .wready (ddr_wready),
        .araddr (ddr_araddr), .arvalid (ddr_arvalid), .arready (ddr_arready),
        .rdata (ddr_rdata), .rvalid (ddr_rvalid), .rready (ddr_rready)
    );

    // ---------------------------------------------------------------- DUT 2
    reg         mb_slow_clk = 1'b0;
    reg  [15:0] mb_data = 16'h1111;
    wire [15:0] mb_out;

    cam_diag_mailbox #(.W(16), .DIV_BITS(2)) u_mb (
        .clk_slow (mb_slow_clk), .rst_slow_n (rst_n), .i_data (mb_data),
        .clk_fast (clk_a1), .rst_fast_n (rst_n), .o_data (mb_out)
    );

    integer fd;
    integer cap_bytes = 0;
    integer npkt = 0;
    integer npkt_want = 3;
    integer i;
    integer j;
    reg [1023:0] out_path;
    reg [15:0] mb_after_stop;

    always @(posedge clk_a1) begin
        if (rst_n && dbg_byte_valid) begin
            $fwrite(fd, "%0d\n", dbg_byte);
            cap_bytes = cap_bytes + 1;
            if ((cap_bytes % 97) == 0) npkt = npkt + 1;
        end
    end

    // slow clock: 20 slow edges after reset, then stop forever
    initial begin
        wait (rst_n);
        repeat (4) @(negedge clk_a1);
        for (j = 0; j < 20; j = j + 1) begin
            #10 mb_slow_clk = 1'b1; #10 mb_slow_clk = 1'b0;
            if (j == 8) mb_data = 16'h2222;
        end
        mb_after_stop = mb_out;
        mb_data = 16'h3333;                 // must NOT appear on the fast side
        $display("MB_STOPPED snap=%04h", mb_after_stop);
    end

    initial begin
        if (!$value$plusargs("OUT=%s", out_path)) out_path = "status_dead_bytes.txt";
        if (!$value$plusargs("NPKT=%d", npkt_want)) npkt_want = 3;
        fd = $fopen(out_path, "w");
        if (fd == 0) begin
            $display("TB_OPEN_FAIL %0s", out_path);
            $finish;
        end

        repeat (10) @(negedge clk_a1);
        rst_n = 1'b1;
        for (i = 0; i < npkt_want * 4096 * 3 + 2000; i = i + 1) @(negedge clk_a1);

        $display("TB_DEADCAM bytes=%0d packets=%0d cap=%0d enc=%0d exp=%0d err=%0d",
                 cap_bytes, npkt, st_cap, st_enc, st_exp, st_err);
        $display("MB_FINAL snap=%04h data_in=%04h", mb_out, mb_data);
        if (mb_out !== mb_after_stop) $display("MB_BAD_HOLD got=%04h want=%04h", mb_out, mb_after_stop);
        if (npkt < npkt_want)         $display("TB_DEADCAM_BAD_PACKETS want=%0d got=%0d", npkt_want, npkt);
        if (cap_bytes != npkt * 97)   $display("TB_DEADCAM_BAD_LEN bytes=%0d packets=%0d", cap_bytes, npkt);
        $fclose(fd);
        $finish;
    end
endmodule
