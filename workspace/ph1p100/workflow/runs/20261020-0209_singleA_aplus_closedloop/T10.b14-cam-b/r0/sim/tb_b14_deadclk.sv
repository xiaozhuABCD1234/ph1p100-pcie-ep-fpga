`timescale 1ns/1ps
// =============================================================================
// tb_b14_deadclk.sv -- T10.b14-cam-b S4: dead B byte clock.
//
// The A1 chain is driven by the selected camera byte clock.  If B has no byte
// clock (module/clock lane dead), clk_cam never toggles.  The contract is:
//   * status packets keep coming out of clk_a1 (241 B / VER 5 / XOR ok),
//   * cam fields hold 0 (mailbox keeps its reset value; hardware powers up 0),
//   * no A1 frame starts, nothing hangs, no half frame is emitted.
//
// clk_cam is tied to 0 on purpose (the strict "clock stopped" case).  The slow
// side of cam_diag_mailbox has an asynchronous reset, so the cam bus holds 0;
// the crop/FIFO write side never clocks, exactly like silicon with a dead clock.
// =============================================================================
module tb_b14_deadclk;
    reg clk_a1 = 1'b0;
    reg rst_n  = 1'b0;
    always #2.6665 clk_a1 = ~clk_a1;

    reg clk_cam = 1'b0;           // B byte clock: runs only through power-on reset
    // T10.b14-cam-b: hardware powers the stopped clk_cam domain up at 0.  The
    // dev-plan explicitly allows modelling that by initialising the domain: run
    // a few clk_cam edges while rst_n is still low (every clk_cam register has a
    // synchronous `if (!rst_n)` clear), then stop the clock for good.
    initial begin
        #1.3;
        repeat (8) begin #1.3333 clk_cam = ~clk_cam; end
    end
    wire clk_uart = clk_a1;

    reg  [39:0] tap_pix = 40'd0;
    reg         tap_v = 1'b0, tap_line = 1'b0, tap_frame = 1'b0, tap_vs = 1'b0;

    wire [31:0]  ddr_awaddr, ddr_araddr;
    wire         ddr_awvalid, ddr_awready, ddr_wvalid, ddr_wready;
    wire [255:0] ddr_wdata;
    wire         ddr_arvalid, ddr_arready, ddr_rvalid, ddr_rready;
    wire [255:0] ddr_rdata;
    wire         rd_abort_w, uart_txd, dbg_byte_valid;
    wire [7:0]   dbg_byte;
    wire [31:0]  st_cap, st_enc, st_exp, st_exp_bytes, st_raw_pub, st_raw_drop;
    wire [31:0]  st_cmp_drop, st_geom, st_err, st_read_words, st_dup_words;
    wire [255:0] dbg_bridge;

    camera_a1_uart_top #(
        .CAM_W (3864), .CAM_H (2192), .ROI_X (972), .ROI_Y (556),
        .W (1920), .H (1080), .UART_DIV (1), .STS_DIV (25000), .FIFO_AW (6)
    ) dut (
        .clk_cam (clk_cam), .clk_a1 (clk_a1), .clk_uart (clk_uart), .rst_n (rst_n),
        .i_a_pixel (tap_pix), .i_a_pixel_valid (tap_v),
        .i_a_in_line (tap_line), .i_a_in_frame (tap_frame), .i_a_vsync (tap_vs),
        .i_ddr_rdy (1'b1),
        .i_dbg_tap (6'd46), .i_dbg_delay_done (1'b0), .i_dbg_rst_out (1'b0),
        .i_dbg_sync_wait (1'b1), .i_dbg_pkt_tgl (1'b0), .i_dbg_vs_tgl (1'b0),
        .i_dbg_clk_tgl (1'b0), .i_dbg_sys (64'h0010_0000_0000_0000),
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

    // No DDR traffic is expected: tie the bridge read data low via a model-free
    // inactive responder.  (raw_awvalid can never rise without clk_cam data.)
    assign ddr_rdata  = 256'd0;
    assign ddr_rvalid = 1'b0;
    assign ddr_awready = 1'b1;
    assign ddr_wready  = 1'b1;
    assign ddr_arready = 1'b0;

    // --------------------------------------------------------------- capture
    reg [7:0] pkt [0:240];
    integer nbyte = 0, npkt = 0, nbad = 0, k, cycles = 0;
    reg [7:0] xacc;
    reg [31:0] f0, f1;
    always @(posedge clk_a1) begin
        cycles = cycles + 1;
        if (rst_n && dbg_byte_valid) begin
            pkt[nbyte] = dbg_byte;
            nbyte = nbyte + 1;
            if (nbyte == 241) begin
                nbyte = 0;
                npkt  = npkt + 1;
                if ((pkt[0] !== 8'hA5) || (pkt[1] !== 8'h5A) ||
                    (pkt[2] !== 8'd241) || (pkt[3] !== 8'd5)) nbad = nbad + 1;
                xacc = 8'd0;
                for (k = 0; k < 240; k = k + 1) xacc = xacc ^ pkt[k];
                if (xacc !== pkt[240]) nbad = nbad + 1;
                // cam fields #0..#14 live at packet bytes 4+8*4 .. (field 8..22)
                f0 = {pkt[4+8*4+3], pkt[4+8*4+2], pkt[4+8*4+1], pkt[4+8*4]};
                f1 = {pkt[4+21*4+3], pkt[4+21*4+2], pkt[4+21*4+1], pkt[4+21*4]};
                if (pkt[4+8*4] !== 8'd0 || pkt[4+8*4+1] !== 8'd0 ||
                    pkt[4+8*4+2] !== 8'd0 || pkt[4+8*4+3] !== 8'd0) nbad = nbad + 1;
                // field 21 (cam_sysstat): bit20 must be 1 (CAM_SEL) and the rest 0
                if (f1 !== 32'h0010_0000) nbad = nbad + 1;
            end
        end
        if (cycles > 4000000) begin
            $display("B14_DEADCLK_WATCHDOG cycles=%0d packets=%0d", cycles, npkt);
            $display("B14_DEADCLK_RESULT pass=0");
            $finish;
        end
    end

    initial begin
        repeat (20) @(posedge clk_a1);
        rst_n = 1'b1;
        // 241 B at UART_DIV=1 plus the status cadence: 3 packets need ~ 3*25000
        repeat (200000) @(posedge clk_a1);
        $display("B14_DEADCLK_DONE packets=%0d bad=%0d cap=%0d enc=%0d exp=%0d raw_pub=%0d",
                 npkt, nbad, st_cap, st_enc, st_exp, st_raw_pub);
        $display("B14_DEADCLK_RESULT pass=%0d",
                 ((npkt >= 2) && (nbad == 0) && (st_cap == 0) && (st_enc == 0) &&
                  (st_exp == 0) && (st_raw_pub == 0)) ? 1 : 0);
        $finish;
    end
endmodule
