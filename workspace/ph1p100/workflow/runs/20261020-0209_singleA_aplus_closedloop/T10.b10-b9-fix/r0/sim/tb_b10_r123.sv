`timescale 1ns/1ps
// =============================================================================
// tb_b10_r123.sv -- T10.b10 minimal R1/R2/R3 cases (dev-plan section 2.5).
//
//   +CASE=r1 : raw write path, FIFO overflow with a stalled store.  A frame
//              whose beats (including LAST) are dropped by the full CDC FIFO
//              must not leave an orphan writer: the slot is aborted, the bad
//              frame is not published and the next good frame publishes/reads.
//   +CASE=r2 : p2_ddr_bridge, one store word only.  External paxi_awvalid and
//              paxi_wvalid must each handshake exactly once, with address/data
//              stable while valid under independent AW/W back-pressure.
//   +CASE=r3 : p2_ddr_bridge, AR accepted but R not returned, business reset,
//              then the stale R is released before a new AR: the stale data
//              must never be delivered to the A1 side; the new R must be.
// =============================================================================
module b10_stall_ddr #(
    parameter integer WORDS = 262144
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         stall,
    input  wire [31:0]  awaddr,
    input  wire         awvalid,
    output wire         awready,
    input  wire [255:0] wdata,
    input  wire         wvalid,
    output wire         wready,
    input  wire [31:0]  araddr,
    input  wire         arvalid,
    output wire         arready,
    output reg  [255:0] rdata,
    output reg          rvalid,
    input  wire         rready
);
    reg [255:0] mem [0:WORDS-1];
    reg         rpend;
    reg [3:0]   rwait;
    reg [31:0]  raddr_r;

    assign awready = rst_n && !stall;
    assign wready  = rst_n && !stall;
    assign arready = rst_n && !rpend && !rvalid;

    always @(posedge clk) begin
        if (rst_n && awvalid && awready && wvalid && wready)
            mem[awaddr[23:0]] <= wdata;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            rpend <= 1'b0; rwait <= 4'd0; rvalid <= 1'b0; rdata <= 256'd0;
        end else begin
            if (rvalid && rready) rvalid <= 1'b0;
            if (arvalid && arready) begin
                raddr_r <= araddr; rpend <= 1'b1; rwait <= 4'd1;
            end else if (rpend) begin
                if (rwait == 4'd0) begin
                    rpend <= 1'b0; rdata <= mem[raddr_r[23:0]]; rvalid <= 1'b1;
                end else rwait <= rwait - 4'd1;
            end
        end
    end
endmodule

module tb_b10_r123;
    reg  [8*4-1:0] case_name = "r1";

    // ------------------------------------------------------------------ clocks
    reg clk_a1 = 0, clk_cam = 0, clk_ddr = 0, rst_n = 0;
    always #5    clk_a1  = ~clk_a1;
    always #3.5  clk_ddr = ~clk_ddr;
    real cam_half = 2.6;
    always #(cam_half) clk_cam = ~clk_cam;

    // ====================================================== R1: camera raw path
    reg  [39:0] tap_pix = 0;
    reg         tap_v = 0, tap_line = 0, tap_frame = 0, tap_vs = 0;
    reg         ddr_stall = 0;
    reg         ddr_rdy   = 1;
    wire [31:0]  r_awaddr, r_araddr;
    wire         r_awvalid, r_awready, r_wvalid, r_wready;
    wire [255:0] r_wdata;
    wire         r_arvalid, r_arready, r_rvalid, r_rready;
    wire [255:0] r_rdata;
    wire         uart_txd, dbg_valid;
    wire [7:0]   dbg_byte;
    wire [31:0]  st_cap, st_enc, st_exp, st_expb, st_raw_pub, st_raw_drop;
    wire [31:0]  st_cmp_drop, st_geom, st_err, st_read, st_dup;

    camera_a1_uart_top #(
        .CAM_W (32), .CAM_H (8), .ROI_X (4), .ROI_Y (2),
        .W (8), .H (4), .UART_DIV (1), .STS_DIV (0), .FIFO_AW (2)
    ) u_top (
        .clk_cam (clk_cam), .clk_a1 (clk_a1), .clk_uart (clk_a1), .rst_n (rst_n),
        .i_a_pixel (tap_pix), .i_a_pixel_valid (tap_v),
        .i_a_in_line (tap_line), .i_a_in_frame (tap_frame), .i_a_vsync (tap_vs),
        .i_ddr_rdy (ddr_rdy),
        .i_dbg_tap (6'd0), .i_dbg_delay_done (1'b0), .i_dbg_rst_out (1'b0),
        .i_dbg_sync_wait (1'b0), .i_dbg_pkt_tgl (1'b0), .i_dbg_vs_tgl (1'b0),
        .i_dbg_clk_tgl (1'b0), .i_dbg_sys (64'd0),
        .o_ddr_awaddr (r_awaddr), .o_ddr_awvalid (r_awvalid), .o_ddr_awready (r_awready),
        .o_ddr_wdata (r_wdata), .o_ddr_wvalid (r_wvalid), .o_ddr_wready (r_wready),
        .o_ddr_araddr (r_araddr), .o_ddr_arvalid (r_arvalid), .o_ddr_arready (r_arready),
        .i_ddr_rdata (r_rdata), .i_ddr_rvalid (r_rvalid), .o_ddr_rready (r_rready),
        .o_uart_txd (uart_txd), .o_dbg_byte (dbg_byte), .o_dbg_byte_valid (dbg_valid),
        .o_st_cap_frames (st_cap), .o_st_enc_frames (st_enc), .o_st_exported (st_exp),
        .o_st_export_bytes (st_expb), .o_st_raw_pub (st_raw_pub),
        .o_st_raw_drop (st_raw_drop), .o_st_cmp_drop (st_cmp_drop),
        .o_st_geom_err (st_geom), .o_st_errors (st_err),
        .o_st_read_words (st_read), .o_st_dup_words (st_dup),
        .o_st_raw_sts ()
    );

    b10_stall_ddr #(.WORDS(262144)) u_ddr_r1 (
        .clk (clk_a1), .rst_n (rst_n), .stall (ddr_stall),
        .awaddr (r_awaddr), .awvalid (r_awvalid), .awready (r_awready),
        .wdata (r_wdata), .wvalid (r_wvalid), .wready (r_wready),
        .araddr (r_araddr), .arvalid (r_arvalid), .arready (r_arready),
        .rdata (r_rdata), .rvalid (r_rvalid), .rready (r_rready)
    );

    localparam integer CG = 8;   // CAM_W/4
    function [9:0] smp;
        input integer y;
        input integer x;
        smp = (x*3 + y*5 + ((x ^ y) & 7)*17) & 1023;
    endfunction

    task r1_frame;
        integer y, g;
        reg [9:0] s0, s1, s2, s3;
        begin
            @(negedge clk_cam);
            tap_frame = 1'b1; tap_vs = 1'b1;
            for (y = 0; y < 8; y = y + 1) begin
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
                repeat (4) @(negedge clk_cam);
            end
            tap_frame = 1'b0; tap_vs = 1'b0;
            repeat (20) @(negedge clk_cam);
        end
    endtask

    integer t;
    integer dbg_cycles = 0, crop_v_cnt = 0;
    always @(posedge clk_a1) begin
        if (rst_n) begin
            dbg_cycles = dbg_cycles + 1;
            if (u_top.crop_valid) crop_v_cnt = crop_v_cnt + 1;
            if ((case_name == "r1") && (dbg_cycles % 4000 == 0) && (dbg_cycles < 80000))
                $display("R1DBG t=%0d crop_v=%0d fifo_v=%0d skid=%0d active=%0d pub=%0d drop=%0d abort=%0d ovf=%0d",
                         dbg_cycles, crop_v_cnt, u_top.fifo_valid, u_top.skid_valid,
                         u_top.raw_active, st_raw_pub, st_raw_drop,
                         u_top.u_raw_store.st_abort_cnt, u_top.fifo_ovf_cnt);
        end
    end
    task wait_pub(input integer n);
        begin
            t = 0;
            while ((st_raw_pub < n) && (t < 400000)) begin
                @(negedge clk_a1); t = t + 1;
            end
        end
    endtask

    // ================================================= R2/R3: bridge instances
    reg         b_rst_n = 0;
    reg  [31:0] b_awaddr = 0, b_araddr = 0;
    reg         b_awvalid = 0, b_wvalid = 0, b_arvalid = 0, b_rready = 0;
    reg  [255:0] b_wdata = 0, b_wkeep = 0;
    wire        b_awready, b_wready, b_arready, b_rvalid;
    wire [255:0] b_rdata;
    reg  [26:0]  p_awaddr, p_araddr;
    wire         p_awvalid, p_wvalid, p_arvalid, p_rready;
    wire [255:0] p_wdata;
    wire [31:0]  p_wstrb;
    wire         p_wlast;
    reg         p_awready = 0, p_wready = 0, p_arready = 0;
    reg  [255:0] p_rdata = 0;
    reg         p_rvalid = 0;

    p2_ddr_bridge u_bridge (
        .clk_a1 (clk_a1), .rst_n (b_rst_n),
        .s_awaddr (b_awaddr), .s_awvalid (b_awvalid), .s_awready (b_awready),
        .s_wdata (b_wdata), .s_wvalid (b_wvalid), .s_wready (b_wready),
        .s_araddr (b_araddr), .s_arvalid (b_arvalid), .s_arready (b_arready),
        .s_rdata (b_rdata), .s_rvalid (b_rvalid), .s_rready (b_rready),
        .clk_ddr (clk_ddr), .ddr_rdy (1'b1),
        .paxi_awaddr (p_awaddr), .paxi_awvalid (p_awvalid), .paxi_awready (p_awready),
        .paxi_wdata (p_wdata), .paxi_wstrb (p_wstrb), .paxi_wvalid (p_wvalid),
        .paxi_wlast (p_wlast), .paxi_wready (p_wready),
        .paxi_araddr (p_araddr), .paxi_arvalid (p_arvalid), .paxi_arready (p_arready),
        .paxi_rdata (p_rdata), .paxi_rlast (1'b1), .paxi_rvalid (p_rvalid),
        .paxi_rready (p_rready)
    );

    integer aw_hs = 0, w_hs = 0, ar_hs = 0, r_hs = 0;
    integer aw_stable_err = 0, w_stable_err = 0;
    integer stale_seen = 0, new_seen = 0;
    reg [26:0] aw_addr_q, w_addr_q;
    reg [255:0] w_data_q;
    reg aw_was_valid = 0, w_was_valid = 0;

    always @(posedge clk_ddr) begin
        if (p_awvalid && p_awready) aw_hs = aw_hs + 1;
        if (p_wvalid && p_wready)   w_hs  = w_hs  + 1;
        if (p_arvalid && p_arready) ar_hs = ar_hs + 1;
        if (p_rvalid && p_rready)   r_hs  = r_hs  + 1;
        // address/data must not move while valid and not yet accepted
        if (p_awvalid && aw_was_valid && !p_awready && (p_awaddr !== aw_addr_q)) aw_stable_err = aw_stable_err + 1;
        if (p_wvalid  && w_was_valid  && !p_wready  && (p_wdata  !== w_data_q))  w_stable_err  = w_stable_err  + 1;
        aw_addr_q = p_awaddr; w_addr_q = p_awaddr; w_data_q = p_wdata;
        aw_was_valid = p_awvalid; w_was_valid = p_wvalid;
    end

    always @(posedge clk_a1) begin
        if (b_rvalid) begin
            if (b_rdata[31:0] === 32'hDEAD_BEEF) stale_seen = stale_seen + 1;
            if (b_rdata[31:0] === 32'hCAFE_BABE) new_seen = new_seen + 1;
        end
    end

    // --------------------------------------------------------------- sequence
    integer pass;
    initial begin
        if (!$value$plusargs("CASE=%s", case_name)) case_name = "r1";
        repeat (5) @(negedge clk_a1);
        rst_n = 1; b_rst_n = 1;
        repeat (5) @(negedge clk_a1);
        if (case_name == "r1") begin
            // Phase 1: camera clock much faster than clk_a1, so the 4-entry CDC
            // FIFO overflows while the store is stalled -> beats (including a
            // LAST) are lost.  b9 only counted this and left the writer open.
            cam_half = 2.0;
            r1_frame;
            r1_frame;
            repeat (4000) @(negedge clk_a1);
            // Phase 2: slow camera again, a good frame must publish and be read
            cam_half = 2.6;
            repeat (500) @(negedge clk_a1);
            r1_frame;
            wait_pub(1);
            repeat (3000) @(negedge clk_a1);
            pass = (st_raw_pub >= 1) && (st_exp >= 1) && (t < 400000) &&
                   (u_top.u_raw_store.st_abort_cnt >= 1);
            $display("B10_R1_DONE raw_pub=%0d exported=%0d enc=%0d raw_drop=%0d abort=%0d ovf=%0d read=%0d err=%0d geom=%0d waits=%0d",
                     st_raw_pub, st_exp, st_enc, st_raw_drop, u_top.u_raw_store.st_abort_cnt,
                     u_top.fifo_ovf_cnt, st_read, st_err, st_geom, t);
            $display("B10_R1_RESULT pass=%0d", pass);
        end else if (case_name == "r2") begin
            // word 1: both valid for exactly one cycle (the bridge accepts on
            // the same edge), AW and W then back-pressured independently
            b_awaddr = 32'h40; b_wdata = 256'h1111_2222_3333_4444;
            b_awvalid = 1; b_wvalid = 1;
            @(negedge clk_a1);
            b_awvalid = 0; b_wvalid = 0;
            repeat (10) @(negedge clk_ddr);
            p_awready = 1; repeat (2) @(negedge clk_ddr); p_awready = 0;   // AW first
            repeat (10) @(negedge clk_ddr);
            p_wready = 1;  repeat (2) @(negedge clk_ddr); p_wready = 0;    // then W
            repeat (60) @(negedge clk_ddr);
            $display("B10_R2_W1 aw_hs=%0d w_hs=%0d aw_stable_err=%0d w_stable_err=%0d",
                     aw_hs, w_hs, aw_stable_err, w_stable_err);
            // word 2: must still be exactly one AW/W
            b_awaddr = 32'h80; b_wdata = 256'h5555_6666_7777_8888;
            b_awvalid = 1; b_wvalid = 1;
            @(negedge clk_a1);
            b_awvalid = 0; b_wvalid = 0;
            repeat (10) @(negedge clk_ddr);
            p_awready = 1; p_wready = 1;
            repeat (4) @(negedge clk_ddr);
            p_awready = 0; p_wready = 0;
            repeat (60) @(negedge clk_ddr);
            pass = (aw_hs == 2) && (w_hs == 2) && (aw_stable_err == 0) && (w_stable_err == 0);
            $display("B10_R2_DONE aw_hs=%0d w_hs=%0d aw_stable_err=%0d w_stable_err=%0d",
                     aw_hs, w_hs, aw_stable_err, w_stable_err);
            $display("B10_R2_RESULT pass=%0d", pass);
        end else begin
            // R3: AR accepted, no R, business reset, stale R released, new AR
            p_arready = 1;
            b_araddr = 32'h100; b_arvalid = 1;
            @(negedge clk_a1);
            b_arvalid = 0;
            t = 0;
            while ((ar_hs == 0) && (t < 200)) begin @(negedge clk_ddr); t = t + 1; end
            p_arready = 0;
            repeat (10) @(negedge clk_ddr);
            $display("B10_R3_AR1 ar_hs=%0d", ar_hs);
            // business reset while the old AR is outstanding
            b_rst_n = 0; rst_n = 0;
            repeat (10) @(negedge clk_a1);
            b_rst_n = 1; rst_n = 1;
            repeat (10) @(negedge clk_ddr);
            // the old response arrives with no AR outstanding
            p_rdata = {224'd0, 32'hDEAD_BEEF}; p_rvalid = 1;
            @(negedge clk_ddr);
            while (!p_rready) @(negedge clk_ddr);
            p_rvalid = 0;
            repeat (20) @(negedge clk_ddr);
            // new AR + new response
            p_arready = 1;
            b_araddr = 32'h200; b_arvalid = 1;
            @(negedge clk_a1);
            b_arvalid = 0;
            t = 0;
            while ((ar_hs < 2) && (t < 200)) begin @(negedge clk_ddr); t = t + 1; end
            p_arready = 0;
            repeat (10) @(negedge clk_ddr);
            p_rdata = {224'd0, 32'hCAFE_BABE}; p_rvalid = 1;
            @(negedge clk_ddr);
            while (!p_rready) @(negedge clk_ddr);
            p_rvalid = 0;
            repeat (10) @(negedge clk_ddr);
            b_rready = 1;
            repeat (20) @(negedge clk_a1);
            b_rready = 0;
            pass = (ar_hs >= 1) && (stale_seen == 0) && (new_seen >= 1);
            $display("B10_R3_DONE ar_hs=%0d stale_seen=%0d new_seen=%0d",
                     ar_hs, stale_seen, new_seen);
            $display("B10_R3_RESULT pass=%0d", pass);
        end
        $finish;
    end

    initial begin
        #20000000;
        $display("B10_R123_TIMEOUT case=%0s raw_pub=%0d", case_name, st_raw_pub);
        $display("B10_R123_RESULT pass=0");
        $finish;
    end
endmodule
