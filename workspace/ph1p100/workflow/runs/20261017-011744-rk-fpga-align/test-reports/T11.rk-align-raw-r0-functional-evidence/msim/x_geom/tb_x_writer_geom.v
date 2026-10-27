///////////////////////////////////////////////////////////////////////////////
//  tb_x_writer_geom.v — functional-tester adversarial probe (NOT part of the
//  developer's frozen G1 set; written by the functional tester).
//
//  Purpose: exercise cam_r10f_writer at a geometry OUTSIDE the frozen samples
//  (W=4, H=2, X0=Y0=0) where packed payload = 10 bytes is NOT a multiple of 4,
//  so a published frame's CRC path must use the 2-byte partial-word variant.
//  Additionally (ownership / seq-gap semantics with prot_en=1):
//    f1 good  -> published (ordinal 1, block0, protected)
//    f2 bad   -> written to block1, NOT published
//    f3 good  -> its turn is block0 which is protected -> whole frame skipped
//                (block0 content must stay byte-identical to f1)
//    release  -> toggle rel_tgl0/rel_tgl1 (pusher ACK equivalent)
//    f4 good  -> published (ordinal 4 -> capture_seq=4, block1)
//  The TB only drives the DUT and dumps DDR content; judgment is done by the
//  tester's own Python oracle (r10f_geom_check.py), not by this TB.
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
module tb_x_writer_geom;

    reg clk_cam = 0, clk_fb = 0, clk_ddr = 0;
    always #3  clk_cam = ~clk_cam;
    always #8  clk_fb  = ~clk_fb;
    always #5  clk_ddr = ~clk_ddr;

    reg rst_cam_n = 0;
    reg wr_rst    = 1;

    localparam integer W = 4, H = 2, GPQ = W/4;
    localparam integer DMA = 4096;
    localparam [31:0] BASE0 = 32'h0010_0000, BASE1 = 32'h0010_2000;
    localparam [31:0] SES   = 32'hABCD_0001;

    reg  a_vsync=0, a_in_frame=0, a_in_line=0, a_valid=0, a_good=0;
    reg  [39:0] a_pix=0;
    reg  a_prot=1, a_rel0=0, a_rel1=0;
    wire [31:0] a_seq, a_base, a_status, a_len;
    wire        a_awvalid, a_awready, a_wvalid, a_wready, a_bvalid, a_bready, a_wlast;
    wire [28:0] a_awaddr; wire [7:0] a_awlen; wire [2:0] a_awsize; wire [1:0] a_awburst;
    wire [255:0] a_wdata; wire [31:0] a_wstrb; wire [1:0] a_bresp;

    cam_r10f_writer #(
        .W(W), .H(H), .X0(16'd0), .Y0(16'd0), .SKIP_ROWS(16'd0),
        .BASE0(BASE0), .BASE1(BASE1), .FIFO_AW(10), .BURST_BEATS(128),
        .CAMERA_ID(8'd0), .SRC_BAYER_PHASE(2'd1), .MODE_ID(32'd7), .TMO_LIMIT(21'd4095)
    ) u_wr (
        .cam_clk(clk_cam), .cam_rst_n(rst_cam_n),
        .cam_vsync(a_vsync), .cam_in_frame(a_in_frame), .cam_in_line(a_in_line),
        .cam_pix(a_pix), .cam_pix_valid(a_valid),
        .cam_frame_good(a_good), .cam_frame_abort(1'b0),
        .prot_en(a_prot), .rel_tgl0(a_rel0), .rel_tgl1(a_rel1),
        .clk_fb(clk_fb), .rst_fb(wr_rst), .session_id(SES),
        .wr_frame_seq(a_seq), .wr_base(a_base), .wr_status(a_status), .wr_len(a_len),
        .dbg_lines_per_frame(), .dbg_max_grp_per_line(), .dbg_anomaly(), .dbg_drop(),
        .clk_ddr(clk_ddr), .rst_ddr(wr_rst), .ddr_cal_done(1'b1), .arm(1'b1),
        .axi_busy(),
        .m_axi_awaddr(a_awaddr), .m_axi_awlen(a_awlen), .m_axi_awsize(a_awsize),
        .m_axi_awburst(a_awburst), .m_axi_awvalid(a_awvalid), .m_axi_awready(a_awready),
        .m_axi_wdata(a_wdata), .m_axi_wstrb(a_wstrb), .m_axi_wlast(a_wlast),
        .m_axi_wvalid(a_wvalid), .m_axi_wready(a_wready),
        .m_axi_bresp(a_bresp), .m_axi_bvalid(a_bvalid), .m_axi_bready(a_bready)
    );

    // simple AXI write slave: BASE0/BASE1 windows (512 beats = 16KB total)
    reg [255:0] mem [0:511];
    reg [28:0]  awaddr_q = 0; reg [7:0] awlen_q = 0;
    reg         bpend = 0;   reg [7:0] bcnt = 0;
    integer     bib = 0, beats = 0, i;
    assign a_awready = wr_rst ? 1'b0 : 1'b1;
    assign a_wready  = wr_rst ? 1'b0 : 1'b1;
    assign a_bresp   = 2'b00;
    assign a_bvalid  = bpend && (bcnt == 8'd0);
    assign a_bready  = 1'b1;

    always @(posedge clk_ddr) begin
        if (a_awvalid && a_awready) begin
            awaddr_q <= a_awaddr; awlen_q <= a_awlen; bib = 0;
            bcnt <= a_awlen + 8'd1; bpend <= 1'b1;
        end
        if (a_wvalid && a_wready) begin
            beats = beats + 1;
            for (i = 0; i < 32; i = i + 1)
                if (a_wstrb[i])
                    mem[((awaddr_q - BASE0[28:0])>>5) + bib[6:0]][i*8 +: 8] <= a_wdata[i*8 +: 8];
            bib = bib + 1;
            if (bcnt != 8'd0) bcnt <= bcnt - 8'd1;
        end
        if (a_bvalid && a_bready) bpend <= 1'b0;
    end

    function [7:0] mem_byte;
        input integer b;
        begin
            mem_byte = mem[b/32][(b%32)*8 +: 8];
        end
    endfunction

    integer k, fd, t, seq1, base1, beats_after_skip;

    // frame drive: 2 lines x 1 group; p(x,y) = (x*7 + y*13 + 5) & 0x3FF
    task a_frame;
        input integer good;
        integer yy, gg;
        begin
            @(negedge clk_cam); a_vsync = 1;
            @(negedge clk_cam); a_vsync = 0; a_in_frame = 1;
            for (yy = 0; yy < H; yy = yy + 1) begin
                @(negedge clk_cam); a_in_line = 1;
                @(negedge clk_cam); a_in_line = 0;
                for (gg = 0; gg < GPQ; gg = gg + 1) begin
                    @(negedge clk_cam);
                    // NOTE: assign field-by-field; a 4x32-bit concat would truncate to 40 bits.
                    a_pix[9:0]   = (0*7 + yy*13 + 5) & 10'h3FF;  // P0
                    a_pix[19:10] = (1*7 + yy*13 + 5) & 10'h3FF;  // P1
                    a_pix[29:20] = (2*7 + yy*13 + 5) & 10'h3FF;  // P2
                    a_pix[39:30] = (3*7 + yy*13 + 5) & 10'h3FF;  // P3
                    a_valid = 1;
                    @(negedge clk_cam); a_valid = 0;
                end
            end
            @(negedge clk_cam); if (good) a_good = 1;
            @(negedge clk_cam); a_in_frame = 0;
            @(negedge clk_cam); a_good = 0;
        end
    endtask

    task a_wait_idle;
        input integer limit;
        begin
            t = 0;
            while ((u_wr.s_state != 3'd0) && (t < limit)) begin @(posedge clk_fb); t = t + 1; end
            repeat (100) @(posedge clk_fb);
        end
    endtask

    task dump_frame;
        input integer off;
        input [8*64-1:0] fname;
        begin
            fd = $fopen(fname, "wb");
            for (k = 0; k < DMA; k = k + 1) $fwrite(fd, "%c", mem_byte(off + k));
            $fclose(fd);
        end
    endtask

    initial begin
        rst_cam_n = 0; wr_rst = 1; a_prot = 1;
        #100; rst_cam_n = 1; #400; wr_rst = 0; #200;
        repeat (20) @(negedge clk_cam);
        // f1 good -> published (ordinal 1, block0, protected)
        a_frame(1);
        a_wait_idle(400000);
        $display("  XGEO f1 seq=%0d base=%06h len=%0d beats=%0d status=%08h",
                 a_seq, a_base[23:0], a_len, beats, a_status);
        seq1 = a_seq; base1 = a_base;
        dump_frame(0, "x_geom_frame.bin");
        // f2 bad (no good) -> consumes ordinal 2 and the block1 turn; must NOT publish
        a_frame(0);
        a_wait_idle(400000);
        $display("  XGEO f2(bad) seq=%0d (expect unchanged %0d)", a_seq, seq1);
        if (a_seq != seq1) $display("  XGEO_ERR bad frame published");
        // f3 good -> its turn is block0 (protected) -> whole frame skipped, no write
        beats_after_skip = beats;
        a_frame(1);
        a_wait_idle(400000);
        $display("  XGEO f3(skip) seq=%0d beats=%0d (expect seq %0d, beats %0d)",
                 a_seq, beats, seq1, beats_after_skip);
        if (a_seq != seq1) $display("  XGEO_ERR locked-block frame published");
        if (beats != beats_after_skip) $display("  XGEO_ERR locked-block frame wrote DDR");
        dump_frame(0, "x_geom_after_skip.bin");   // block0 must be unchanged (= f1)
        // release both blocks (pusher ACK equivalent: toggle)
        @(negedge clk_ddr); a_rel0 = ~a_rel0; a_rel1 = ~a_rel1;
        repeat (60) @(posedge clk_ddr);
        // f4 good -> ordinal 4 -> block1 -> published, header capture_seq = 4 (gap 1 -> 4)
        a_frame(1);
        a_wait_idle(400000);
        $display("  XGEO f4 seq=%0d base=%06h (expect %0d / %06h)",
                 a_seq, a_base[23:0], seq1 + 1, BASE1[23:0]);
        dump_frame(8192, "x_geom_frame4.bin");
        if (a_seq == seq1 + 1 && a_base == BASE1 && a_len == DMA && seq1 == 1 && base1 == BASE0)
            $display("TB_DONE");
        else $display("TB_BAD_STATE");
        $finish;
    end

    initial begin
        #200_000_000;
        $display("TB_WATCHDOG");
        $finish;
    end
endmodule
