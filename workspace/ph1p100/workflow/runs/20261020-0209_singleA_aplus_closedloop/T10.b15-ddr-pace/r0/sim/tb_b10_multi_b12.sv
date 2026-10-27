`timescale 1ns/1ps
// Frozen b10 candidate, small-geometry consecutive-frame verification only.
// Camera line/frame timing is adapted from frozen tb_p1_chain.v.
// UART and A1 share the same net; all source patterns differ; no mid-run reset.
// Status boundary arbitration and complete UART bytes are observed passively.
module tb_b10_multi_strict #(
    parameter integer CAM_W = 72,
    parameter integer CAM_H = 10,
    parameter integer ROI_X = 4,
    parameter integer ROI_Y = 2,
    parameter integer W     = 64,
    parameter integer H     = 8,
    parameter integer UART_DIV = 4,
    parameter integer AW_GAP = 2,
    parameter integer R_GAP  = 3,
    parameter integer LINE_GAP = 40,
    parameter integer FRAME_GAP = 600,
    parameter integer MAX_CYCLES = 500000,
    parameter integer NFRAMES = 3, STA_DIV = 10000, FIFO_AW = 6
) ();
    localparam integer CG = CAM_W / 4;

    reg clk_cam = 1'b0;
    reg clk_a1  = 1'b0;
    wire clk_uart = clk_a1; // Same physical clock net, as required by frozen exporter.
    reg rst_n = 1'b0;

    always #2.6665 clk_cam = ~clk_cam;                  // 187.5 MHz
    initial begin #1.7000; forever #2.6665 clk_a1 = ~clk_a1; end


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
        .W (W), .H (H), .UART_DIV (UART_DIV), .STS_DIV(STA_DIV), .FIFO_AW(FIFO_AW)
    ) dut (
        .clk_cam (clk_cam), .clk_a1 (clk_a1), .clk_uart (clk_uart), .rst_n (rst_n),
        .i_a_pixel (tap_pix), .i_a_pixel_valid (tap_v),
        .i_a_in_line (tap_line), .i_a_in_frame (tap_frame), .i_a_vsync (tap_vs),
        .i_ddr_rdy (1'b1),
        .i_dbg_tap (6'd0), .i_dbg_delay_done (1'b0), .i_dbg_rst_out (1'b0),
        .i_dbg_sync_wait (1'b0), .i_dbg_pkt_tgl (1'b0), .i_dbg_vs_tgl (1'b0),
        .i_dbg_clk_tgl (1'b0), .i_dbg_sys (64'd0),
        // T10.b12: the frozen b10 TB predates the v4 observation port.  It is a
        // pure clk_a1 snapshot input; connecting it to 0 only removes 4-state
        // 'z' from v4 fields #44..#49.  No stimulus and no acceptance rule changes.
        .i_dbg_bridge (256'd0),
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
        .o_st_read_words (st_read_words), .o_st_dup_words (st_dup_words),
        .o_st_raw_sts ()
    );

    // T10.b10: the frozen four-slot layout needs >= 424,314 256-bit words; the b9
    // test model only held 2^18 and silently dropped every CMP write above it.
    a1_ddr_model #(.WORDS(524288), .AW_GAP(AW_GAP), .R_GAP(R_GAP)) u_ddr (
        .clk (clk_a1), .rst_n (rst_n),
        .awaddr (ddr_awaddr), .awvalid (ddr_awvalid), .awready (ddr_awready),
        .wdata (ddr_wdata), .wvalid (ddr_wvalid), .wready (ddr_wready),
        .araddr (ddr_araddr), .arvalid (ddr_arvalid), .arready (ddr_arready),
        .rdata (ddr_rdata), .rvalid (ddr_rvalid), .rready (ddr_rready)
    );


    // All observation is passive; no force/release and no DUT assignments.
    integer fd, fw, ft, fs, cycles=0, cap_bytes=0, wire_bytes=0;
    integer source_frames=0, source_groups=0, crop_beats=0, crop_sofs=0, crop_lasts=0;
    integer fifo_reject=0, raw_beats=0, cmp_words=0, raw_writes=0, cmp_writes=0;
    integer ticks_in_frame=0, boundary_due_queued=0, status_grants=0, max_dq=0;
    integer fidx, seed, target, waits=0;
    reg [2047:0] out_path, wire_path, trace_path, stat_path;
    reg [7:0] serial_byte;
    integer bitno;
    reg [31:0] prev_cap=0,prev_pub=0,prev_enc=0,prev_exp=0;
    task write_stats;
      begin
        $fwrite(fs,"nframes=%0d w=%0d h=%0d cam_w=%0d cam_h=%0d roi_x=%0d roi_y=%0d uart_div=%0d sts_div=%0d fifo_aw=%0d line_gap=%0d frame_gap=%0d cycles=%0d cap=%0d raw_pub=%0d enc=%0d exported=%0d exp_bytes=%0d raw_drop=%0d cmp_drop=%0d geom=%0d err=%0d read_words=%0d dup_words=%0d cap_bytes=%0d wire_bytes=%0d source_frames=%0d source_groups=%0d crop_beats=%0d crop_sofs=%0d crop_lasts=%0d fifo_reject=%0d raw_beats=%0d cmp_words=%0d raw_writes=%0d cmp_writes=%0d ticks_in_frame=%0d boundary_due_queued=%0d status_grants=%0d max_dq=%0d assert_fails=%0d third_wait=%0d\n",
         NFRAMES,W,H,CAM_W,CAM_H,ROI_X,ROI_Y,UART_DIV,STA_DIV,FIFO_AW,LINE_GAP,FRAME_GAP,cycles,st_cap,st_raw_pub,st_enc,st_exp,st_exp_bytes,st_raw_drop,st_cmp_drop,st_geom,st_err,st_read_words,st_dup_words,cap_bytes,wire_bytes,source_frames,source_groups,crop_beats,crop_sofs,crop_lasts,fifo_reject,raw_beats,cmp_words,raw_writes,cmp_writes,ticks_in_frame,boundary_due_queued,status_grants,max_dq,dut.u_export.b10_assert_fails,waits);
      end
    endtask
    always @(posedge clk_cam) if(rst_n) begin
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
        if(dut.u_export.sts_tick && dut.u_export.estate!=0) begin
          ticks_in_frame=ticks_in_frame+1;
          $fwrite(ft,"MID_FRAME_TICK cycles=%0d fid=%0d estate=%0d dq=%0d sent=%0d slen=%0d\n",cycles,dut.u_export.w_frame_id,dut.u_export.estate,dut.u_export.dq_cnt,dut.u_export.sent,dut.u_export.w_stream_len);
        end
        if(dut.u_export.frame_boundary && dut.u_export.status_due && dut.u_export.dq_cnt>0) begin
          boundary_due_queued=boundary_due_queued+1;
          $fwrite(ft,"QUEUED_STATUS_BOUNDARY cycles=%0d dq=%0d exported=%0d want=%0d tick=%0d\n",cycles,dut.u_export.dq_cnt,st_exp,dut.u_export.sts_want,dut.u_export.sts_tick);
        end
        if(dut.u_export.grant_status) begin
          status_grants=status_grants+1;
          $fwrite(ft,"STATUS_GRANT cycles=%0d offset=%0d exported=%0d estate=%0d dq=%0d\n",cycles,cap_bytes,st_exp,dut.u_export.estate,dut.u_export.dq_cnt);
        end
        if(st_cap!=prev_cap||st_raw_pub!=prev_pub||st_enc!=prev_enc||st_exp!=prev_exp) begin
          $fwrite(ft,"COUNTERS cycles=%0d cap=%0d pub=%0d enc=%0d exp=%0d raw_slots=%0d,%0d cmp_slots=%0d,%0d\n",cycles,st_cap,st_raw_pub,st_enc,st_exp,dut.u_raw_store.slot_st[0],dut.u_raw_store.slot_st[1],dut.u_cmp_store.slot_st[0],dut.u_cmp_store.slot_st[1]);
          prev_cap=st_cap;prev_pub=st_raw_pub;prev_enc=st_enc;prev_exp=st_exp;
        end
      end
      if(cycles>MAX_CYCLES) begin
        write_stats; $fclose(fd);$fclose(fw);$fclose(ft);$fclose(fs);
        $fatal(1,"MULTI_WATCHDOG cap=%0d pub=%0d enc=%0d exp=%0d",st_cap,st_raw_pub,st_enc,st_exp);
      end
    end
    // Decode the physical UART 8N1 wire at bit centres; compare to debug capture in Python.
    initial forever begin
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

    function [9:0] smp;
        input integer y;
        input integer x;
        begin
            smp = (x*3 + y*5 + ((x ^ y) & 7)*17) & 1023;
        end
    endfunction

    task drive_frame;
        input integer seed;
        input integer short_line;
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
                    if (1) begin
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
        // Finite two-slot store: the third input waits only for a FREE RAW slot.
        if(fidx==2) while(!dut.raw_begin_ready) begin @(negedge clk_a1);waits=waits+1;end
        seed=111*(fidx+1);
        $fwrite(ft,"SOURCE_START source=%0d seed=%0d cycles=%0d exported=%0d\n",fidx+1,seed,cycles,st_exp);
        drive_frame(seed,0,ROI_Y+H);
        source_frames=source_frames+1;
        $fwrite(ft,"SOURCE_END source=%0d seed=%0d cycles=%0d crop_beats=%0d cap=%0d pub=%0d exp=%0d\n",fidx+1,seed,cycles,crop_beats,st_cap,st_raw_pub,st_exp);
      end
      while(st_exp<NFRAMES) @(negedge clk_a1);
      // Export counter advances before final stop bit; drain all current bytes/status.
      @(negedge clk_a1);
      while(!(dut.u_export.estate==0 && dut.u_export.sstate==0 && dut.u_export.tx_ready && !dut.u_export.tx_valid_r)) @(negedge clk_a1);
      write_stats;$fclose(fd);$fclose(fw);$fclose(ft);$fclose(fs);
      $display("MULTI_DONE frames=%0d cap=%0d pub=%0d enc=%0d exported=%0d bytes=%0d queued_boundary=%0d mid_tick=%0d",NFRAMES,st_cap,st_raw_pub,st_enc,st_exp,cap_bytes,boundary_due_queued,ticks_in_frame);
      $finish;
    end
endmodule

