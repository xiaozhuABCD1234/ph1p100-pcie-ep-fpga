`timescale 1ns/1ps
// =============================================================================
// tb_r1_sof.v -- T10.b12-r1-last T7: SOF rejection variant / head-of-line drain
//
//   1. frame A (seed 200) is driven with the external DDR write port stalled.
//      Its SOF is accepted, the raw writer starts, then the FIFO is full and
//      the LAST is rejected -> the b12 sticky loss-abort is armed.
//   2. frame B (seed 201) is driven immediately: its SOF is offered while the
//      FIFO is still full -> the SOF itself is rejected (counted).
//   3. the stall is released.  The queued beats and the abort beat must drain in
//      order (no head-of-line deadlock), the writer must abort and the slot must
//      be released.
//   4. frame C (seed 300) must publish, encode, export and decode cleanly.
//
// Same small geometry/clocking as the independent R1 counterexample:
// CAM 40x8, ROI(4,2) 32x2, FIFO_AW=2 (real depth 4), camera 25 MHz,
// A1/UART 187.5 MHz, UART_DIV=4.  The only fault injection is the external
// DDR AW/W ready backpressure; nothing in the DUT is forced.
// =============================================================================
module tb_r1_sof;
    localparam W=32, H=2, CAM_W=40, CAM_H=8, ROI_X=4, ROI_Y=2, CG=10;
    localparam FIFO_AW=2, UART_DIV=4;

    reg clk_cam = 0, clk_a1 = 0, rst_n = 0;
    always #20 clk_cam = ~clk_cam;
    initial begin #1.7; forever #2.6665 clk_a1 = ~clk_a1; end
    wire clk_uart = clk_a1;

    reg [39:0] pix = 0;
    reg pv = 0, il = 0, inf = 0, vs = 0;
    wire [31:0] awaddr, araddr;
    wire awvalid, awready, wvalid, wready, arvalid, arready, rvalid, rready;
    wire [255:0] wdata, rdata;
    wire [7:0] byte_data;
    wire byte_valid, txd;
    wire [31:0] cap, enc, exp, expbytes, rawpub, rawdrop, cmpdrop, geom, err, reads, dups;

    camera_a1_uart_top #(.CAM_W(CAM_W), .CAM_H(CAM_H), .ROI_X(ROI_X), .ROI_Y(ROI_Y),
        .W(W), .H(H), .UART_DIV(UART_DIV), .FIFO_AW(FIFO_AW), .STS_DIV(0)) dut (
        .clk_cam(clk_cam), .clk_a1(clk_a1), .clk_uart(clk_uart), .rst_n(rst_n),
        .i_a_pixel(pix), .i_a_pixel_valid(pv), .i_a_in_line(il), .i_a_in_frame(inf), .i_a_vsync(vs),
        .i_ddr_rdy(1'b1), .i_dbg_tap(6'd0), .i_dbg_delay_done(1'b0), .i_dbg_rst_out(1'b0),
        .i_dbg_sync_wait(1'b0), .i_dbg_pkt_tgl(1'b0), .i_dbg_vs_tgl(1'b0), .i_dbg_clk_tgl(1'b0),
        .i_dbg_sys(64'd0), .i_dbg_bridge(192'd0),
        .o_ddr_awaddr(awaddr), .o_ddr_awvalid(awvalid), .o_ddr_awready(awready),
        .o_ddr_wdata(wdata), .o_ddr_wvalid(wvalid), .o_ddr_wready(wready),
        .o_ddr_araddr(araddr), .o_ddr_arvalid(arvalid), .o_ddr_arready(arready),
        .i_ddr_rdata(rdata), .i_ddr_rvalid(rvalid), .o_ddr_rready(rready),
        .o_uart_txd(txd), .o_dbg_byte(byte_data), .o_dbg_byte_valid(byte_valid),
        .o_st_cap_frames(cap), .o_st_enc_frames(enc), .o_st_exported(exp),
        .o_st_export_bytes(expbytes), .o_st_raw_pub(rawpub), .o_st_raw_drop(rawdrop),
        .o_st_cmp_drop(cmpdrop), .o_st_geom_err(geom), .o_st_errors(err),
        .o_st_read_words(reads), .o_st_dup_words(dups), .o_st_raw_sts());

    reg stall_write = 0;
    wire pending;
    wire [31:0] response_epoch, aw_count, w_count, ar_count, r_count, old_r_count;
    ddr_recovery_model mem (.clk(clk_a1), .dut_rst_n(rst_n), .stall_write(stall_write),
        .read_delay(32'd5), .epoch(32'd0),
        .awaddr(awaddr), .awvalid(awvalid), .awready(awready), .wdata(wdata),
        .wvalid(wvalid), .wready(wready), .araddr(araddr), .arvalid(arvalid),
        .arready(arready), .rdata(rdata), .rvalid(rvalid), .rready(rready),
        .pending(pending), .response_epoch(response_epoch), .aw_count(aw_count),
        .w_count(w_count), .ar_count(ar_count), .r_count(r_count),
        .old_r_count(old_r_count));

    integer fd, fu, ft, fs;
    integer cycles = 0, bytes_count = 0, uart_bytes = 0;
    integer sof_accept = 0, sof_reject = 0, last_reject = 0, rejects = 0, crop_aborts = 0;
    integer post_release_writer = -1, drain_cycles = -1;
    reg [2047:0] out_path, uart_path, trace_path, stat_path;

    always @(posedge clk_cam) if (rst_n) begin
        if (dut.crop_valid) begin
            if (dut.crop_sof && dut.u_cam_fifo.w_valid && dut.u_cam_fifo.w_ready)
                sof_accept = sof_accept + 1;
            if (dut.crop_sof && dut.u_cam_fifo.w_valid && !dut.u_cam_fifo.w_ready) begin
                sof_reject = sof_reject + 1;
                $fwrite(ft, "SOF_REJECTED cycle=%0d full=%0d\n", cycles, dut.u_cam_fifo.full);
            end
            if (dut.u_cam_fifo.w_valid && !dut.u_cam_fifo.w_ready) begin
                rejects = rejects + 1;
                if (dut.crop_last) begin
                    last_reject = last_reject + 1;
                    $fwrite(ft, "LAST_REJECTED cycle=%0d writer=%0d nbytes=%0d\n",
                            cycles, dut.u_raw_store.wr_active, dut.u_raw_store.nbytes);
                end
            end
        end
        if (dut.crop_abort) crop_aborts = crop_aborts + 1;
    end

    always @(posedge clk_a1) begin
        cycles = cycles + 1;
        if (cycles > 400000) begin
            $display("TB_R1_SOF_TIMEOUT cycle=%0d writer=%0d slot0=%0d slot1=%0d",
                     cycles, dut.u_raw_store.wr_active, dut.u_raw_store.slot_st[0],
                     dut.u_raw_store.slot_st[1]);
            $fwrite(fs, "STAT case=t7 exp=%0d rawpub=%0d timeout=1\n", exp, rawpub);
            $fclose(fs);
            $finish;
        end
        if (rst_n && byte_valid) begin
            $fwrite(fd, "%0d\n", byte_data);
            bytes_count = bytes_count + 1;
        end
    end

    integer ub;
    reg [7:0] serial_data;
    initial forever begin
        @(negedge txd);
        if (rst_n) begin
            repeat (2) @(negedge clk_uart);
            if (txd !== 1'b0) $display("UART_BAD_START");
            for (ub = 0; ub < 8; ub = ub + 1) begin
                repeat (UART_DIV) @(negedge clk_uart);
                serial_data[ub] = txd;
            end
            repeat (UART_DIV) @(negedge clk_uart);
            if (txd !== 1'b1) $display("UART_BAD_STOP");
            $fwrite(fu, "%0d\n", serial_data);
            uart_bytes = uart_bytes + 1;
        end
    end

    task drive_frame;
        input integer seed;
        integer y, g;
        reg [31:0] st;
        reg [9:0] q [0:3];
        begin
            $fwrite(ft, "SOURCE seed=%0d cycle=%0d stall=%0d\n", seed, cycles, stall_write);
            st = 32'h12345678 ^ seed;
            @(negedge clk_cam);
            inf = 1; vs = 1;
            for (y = 0; y < ROI_Y + H; y = y + 1) begin
                @(negedge clk_cam);
                il = 1; pv = 0;
                for (g = 0; g < CG; g = g + 1) begin
                    st = st ^ (st << 13); st = st ^ (st >> 17); st = st ^ (st << 5);
                    q[0] = st[9:0]; q[1] = st[19:10]; q[2] = st[29:20]; q[3] = st[31:22];
                    pix = {q[3][1:0], q[2][1:0], q[1][1:0], q[0][1:0],
                           q[3][9:2], q[2][9:2], q[1][9:2], q[0][9:2]};
                    pv = 1;
                    @(negedge clk_cam);
                end
                pv = 0; il = 0;
                repeat (12) @(negedge clk_cam);
            end
            inf = 0; vs = 0;
            repeat (16) @(negedge clk_cam);
            $fwrite(ft, "SOURCE_END seed=%0d cycle=%0d\n", seed, cycles);
        end
    endtask

    task settle_uart;
        begin
            repeat (100) @(negedge clk_a1);
            while (dut.u_export.uart_busy) @(negedge clk_a1);
            repeat (20) @(negedge clk_a1);
        end
    endtask

    integer t;
    initial begin
        if (!$value$plusargs("OUT=%s", out_path))   out_path = "capture.dec";
        if (!$value$plusargs("UART=%s", uart_path)) uart_path = "uart.dec";
        if (!$value$plusargs("TRACE=%s", trace_path)) trace_path = "trace.txt";
        if (!$value$plusargs("STAT=%s", stat_path)) stat_path = "stats.txt";
        fd = $fopen(out_path, "w"); fu = $fopen(uart_path, "w");
        ft = $fopen(trace_path, "w"); fs = $fopen(stat_path, "w");
        if (!fd || !fu || !ft || !fs) begin
            $display("TB_R1_SOF_OPEN_FAIL");
            $finish;
        end
        repeat (24) @(negedge clk_a1);
        rst_n = 1'b1;
        repeat (50) @(negedge clk_a1);
        $fwrite(ft, "START cycle=%0d\n", cycles);

        // 1. fault frame A with the DDR write port stalled
        stall_write = 1'b1;
        drive_frame(200);
        $fwrite(ft, "A_DONE cycle=%0d sof_accept=%0d last_reject=%0d rejects=%0d\n",
                cycles, sof_accept, last_reject, rejects);

        // 2. frame B back-to-back: its SOF must be rejected by the full FIFO
        drive_frame(201);
        $fwrite(ft, "B_DONE cycle=%0d sof_reject=%0d rejects=%0d\n", cycles, sof_reject, rejects);

        // 3. release the stall and require an ordered drain + writer release
        stall_write = 1'b0;
        t = 0;
        while ((dut.u_raw_store.wr_active || dut.abort_hold || dut.fifo_valid || dut.skid_valid)
               && (t < 40000)) begin
            @(negedge clk_a1);
            t = t + 1;
        end
        drain_cycles = t;
        post_release_writer = dut.u_raw_store.wr_active;
        $fwrite(ft, "RELEASED_DRAINED cycle=%0d t=%0d writer=%0d slot0=%0d slot1=%0d raw_abort_cnt=%0d rawdrop=%0d\n",
                cycles, t, dut.u_raw_store.wr_active, dut.u_raw_store.slot_st[0],
                dut.u_raw_store.slot_st[1], dut.raw_abort_cnt, rawdrop);

        // 4. a clean frame after the drain must publish/encode/export
        repeat (200) @(negedge clk_a1);
        drive_frame(300);
        t = 0;
        while ((exp < 1) && (t < 200000)) begin
            @(negedge clk_a1);
            t = t + 1;
        end
        settle_uart;

        $fwrite(ft, "FINAL cycle=%0d cap=%0d rawpub=%0d enc=%0d exp=%0d bytes=%0d uart=%0d writer=%0d slot0=%0d slot1=%0d raw_abort_cnt=%0d rawdrop=%0d begin_deny=%0d\n",
                cycles, cap, rawpub, enc, exp, bytes_count, uart_bytes,
                dut.u_raw_store.wr_active, dut.u_raw_store.slot_st[0],
                dut.u_raw_store.slot_st[1], dut.raw_abort_cnt, rawdrop,
                dut.raw_begin_deny);
        $fwrite(fs, "STAT case=t7 w=%0d h=%0d cap=%0d rawpub=%0d enc=%0d exp=%0d rawdrop=%0d cmpdrop=%0d geom=%0d err=%0d bytes=%0d uart_bytes=%0d sof_accept=%0d sof_reject=%0d last_reject=%0d rejects=%0d crop_aborts=%0d raw_abort_cnt=%0d begin_deny=%0d writer_final=%0d slot0=%0d slot1=%0d post_release_writer=%0d drain_cycles=%0d timeout=0 cycles=%0d\n",
            W, H, cap, rawpub, enc, exp, rawdrop, cmpdrop, geom, err,
            bytes_count, uart_bytes, sof_accept, sof_reject, last_reject, rejects,
            crop_aborts, dut.raw_abort_cnt, dut.raw_begin_deny,
            dut.u_raw_store.wr_active, dut.u_raw_store.slot_st[0],
            dut.u_raw_store.slot_st[1], post_release_writer, drain_cycles, cycles);
        $fclose(fd); $fclose(fu); $fclose(ft); $fclose(fs);
        $display("CASE_RESULT case=t7 rawpub=%0d exported=%0d writer=%0d sof_reject=%0d drain=%0d",
                 rawpub, exp, dut.u_raw_store.wr_active, sof_reject, drain_cycles);
        $finish;
    end
endmodule
