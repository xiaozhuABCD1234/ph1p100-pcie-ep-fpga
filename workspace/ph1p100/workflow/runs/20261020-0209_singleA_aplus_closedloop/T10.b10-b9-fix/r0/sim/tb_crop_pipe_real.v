`timescale 1ns/1ps
// =============================================================================
// tb_crop_pipe_real.v -- T10.b8-crop-geom r0
//
// Real CSI-2 byte stream (FS / RAW10 long packets + packet CRC / FE) through the
// pipeline that the P2 candidate actually builds:
//   csi_rx_packet_integrity  (packet framing + CRC16 + keep)
//   csi_rx_10bit_unpack_checked (5 B -> 4 px)
//   a1_raw_crop
// (01_build.tcl adds csi_rx_10bit_unpack_checked.v / the integrity handler; the
//  vendor csi_rx_10bit_unpack.v is NOT in the build - see result-r0 finding F1.)
//
// Small real-proportion geometry: CAM_W=64 (16 beats/line), CAM_H=36,
// ROI_X=16, ROI_Y=8, W=32, H=16 -> 16 ROI rows x 8 groups = 128 groups
// (OG*H; the design-guide "8x8" shorthand contradicts the frozen H=16, the
//  frozen parameter table wins and every one of the 128 groups is checked).
//
// Proves:
//   * one 1-cycle O_in_line pulse per long packet
//   * 5 B -> 4 px RAW10 unpack with real framing/CRC, not an ideal driver
//   * exactly 16 accepted beats per 64-px line (not 15, not 17)
//   * last payload word -> last beat = 2 cycles (unpack register stages)
//   * every ROI group byte-identical to the contract pattern
//   * crc_errors/header_errors/timeouts/bad_frames = 0, good_frames = 1
// =============================================================================
module tb_crop_pipe_real #(
    parameter integer CAM_W = 64,
    parameter integer CAM_H = 36,
    parameter integer ROI_X = 16,
    parameter integer ROI_Y = 8,
    parameter integer W     = 32,
    parameter integer H     = 16,
    parameter integer GAP   = 6
) ();
    localparam integer CG   = CAM_W / 4;      // 16 beats per line
    localparam integer OG   = W / 4;          // 8 groups per ROI row
    localparam integer GX   = ROI_X / 4;      // 4
    localparam integer NGRP = OG * H;         // 128
    localparam integer WC   = CG * 5;         // 80 payload bytes per line
    localparam integer NW   = WC / 4;         // 20 payload words

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #2.6665 clk = ~clk;

    reg  [31:0] src_data = 32'd0;
    reg         src_valid = 1'b0;
    reg         enable = 1'b1;

    wire [31:0] pl_data;
    wire [3:0]  pl_keep;
    wire        pl_valid, pl_done, pl_sync, pl_vs, pl_in_frame, pl_in_line;
    wire [31:0] crc_errors, header_errors, packet_timeouts, frame_timeouts;
    wire [31:0] good_frames, bad_frames;
    wire [15:0] last_wc, last_lines;
    wire        frame_good, frame_abort;

    csi_rx_packet_integrity #(.VC_ID(0), .IMAGE_DT(6'h2b), .IMAGE_WC(0)) u_pkt (
        .I_clock (clk), .I_reset_n (rst_n), .I_enable (enable),
        .I_data (src_data), .I_data_valid (src_valid),
        .O_packet_done (pl_done), .O_sync_wait (pl_sync),
        .O_payload_out (pl_data), .O_payload_valid (pl_valid), .O_payload_keep (pl_keep),
        .O_vsync_out (pl_vs), .O_in_frame (pl_in_frame), .O_in_line (pl_in_line),
        .O_frame_end (), .O_frame_good (frame_good), .O_frame_abort (frame_abort),
        .O_crc_errors (crc_errors), .O_header_errors (header_errors),
        .O_packet_timeouts (packet_timeouts), .O_frame_timeouts (frame_timeouts),
        .O_good_frames (good_frames), .O_bad_frames (bad_frames),
        .O_last_wc (last_wc), .O_last_lines (last_lines)
    );

    wire [39:0] up_pix;
    wire        up_valid;

    csi_rx_10bit_unpack_checked u_unp (
        .I_clock (clk), .I_reset_n (rst_n), .I_enable (enable),
        .I_line_in (pl_in_line), .I_data_in (pl_data), .I_keep (pl_keep),
        .I_din_valid (pl_valid),
        .O_data_out (up_pix), .O_dout_valid (up_valid)
    );

    wire [39:0] out_pix;
    wire        out_valid, out_sof, out_last, out_abort;
    wire [31:0] st_roi, st_groups, st_geom, st_short;

    a1_raw_crop #(
        .CAM_W (CAM_W), .CAM_H (CAM_H), .ROI_X (ROI_X), .ROI_Y (ROI_Y),
        .W (W), .H (H)
    ) dut (
        .clk (clk), .rst_n (rst_n),
        .pix (up_pix), .pix_valid (up_valid),
        .in_line (pl_in_line), .in_frame (pl_in_frame), .vsync (pl_vs),
        .out_pix (out_pix), .out_valid (out_valid), .out_sof (out_sof),
        .out_last (out_last), .out_abort (out_abort),
        .st_roi_frames (st_roi), .st_groups (st_groups),
        .st_geom_err (st_geom), .st_short (st_short)
    );

    reg  [31:0] crc_errors_dummy_unused;

    function [9:0] pval;
        input integer ln;
        input integer gg;
        input integer k;
        begin
            pval = (ln * 37 + gg * 11 + k * 5) & 10'h3FF;
        end
    endfunction

    function [39:0] pack4;
        input [9:0] p0, p1, p2, p3;
        begin
            pack4 = {p3[1:0], p2[1:0], p1[1:0], p0[1:0],
                     p3[9:2], p2[9:2], p1[9:2], p0[9:2]};
        end
    endfunction

    // Tap beat layout produced by csi_rx_10bit_unpack_checked: 4 x 10-bit
    // samples, p3 in [39:30] .. p0 in [9:0].  The crop must pass this 40-bit
    // beat through unchanged (media layout is owned by the frozen tap/consumers,
    // see result-r0 finding F2).
    function [39:0] tap4;
        input [9:0] p0, p1, p2, p3;
        begin
            tap4 = {p3, p2, p1, p0};
        end
    endfunction

    function [15:0] crc_byte;
        input [15:0] c;
        input [7:0]  b;
        reg [15:0] v;
        integer k;
        begin
            v = c ^ {8'd0, b};
            for (k = 0; k < 8; k = k + 1) v = (v >> 1) ^ (v[0] ? 16'h8408 : 16'h0000);
            crc_byte = v;
        end
    endfunction

    reg [7:0] pay [0:127];

    integer cyc = 0;
    integer lastword_t = 0;

    task fill_line;
        input integer y;
        integer g;
        reg [39:0] p;
        begin
            for (g = 0; g < CG; g = g + 1) begin
                p = pack4(pval(y, g, 0), pval(y, g, 1), pval(y, g, 2), pval(y, g, 3));
                pay[5*g + 0] = p[7:0];
                pay[5*g + 1] = p[15:8];
                pay[5*g + 2] = p[23:16];
                pay[5*g + 3] = p[31:24];
                pay[5*g + 4] = p[39:32];
            end
        end
    endtask

    reg [15:0] hdr_wc;
    reg [5:0]  hdr_dt;
    wire [7:0] hdr_ecc;
    csi_rx_hdr_ecc u_ecc (.data ({hdr_wc, 2'b00, hdr_dt}), .ecc (hdr_ecc));

    task send_hdr;
        input [5:0]  dt;
        input [15:0] wc;
        begin
            @(negedge clk); hdr_wc = wc; hdr_dt = dt;
            @(negedge clk);
            src_data  = {hdr_ecc, wc, 2'b00, dt};
            src_valid = 1'b1;
            @(negedge clk); src_valid = 1'b0;
        end
    endtask

    integer wi;
    task send_payload;
        begin
            @(negedge clk);
            src_valid = 1'b1;
            for (wi = 0; wi < NW; wi = wi + 1) begin
                src_data = {pay[4*wi + 3], pay[4*wi + 2], pay[4*wi + 1], pay[4*wi]};
                if (wi == (NW - 1)) lastword_t = cyc + 1;   // cycle that consumes it
                @(negedge clk);
            end
            src_valid = 1'b0;
        end
    endtask

    // packet CRC word: I_data[7:0] = crc low (offset WC), I_data[15:8] = crc high
    task send_crc;
        reg [15:0] c;
        integer k;
        begin
            c = 16'hFFFF;
            for (k = 0; k < WC; k = k + 1) c = crc_byte(c, pay[k]);
            @(negedge clk);
            src_data  = {16'h0000, c[15:8], c[7:0]};
            src_valid = 1'b1;
            @(negedge clk);
            src_valid = 1'b0;
        end
    endtask

    // ---- monitors ----------------------------------------------------------
    integer exp_idx = 0;
    integer ub_line = 0, ub_prev_line = -1, line_err = 0;
    integer line_pulses = 0, wide_pulse = 0;
    integer pl_line_d = 0;
    integer li_t = 0, li_to_beat = -1, found_first = 0;
    integer lastbeat_t = -1, lastword_to_beat = -1;
    integer data_err = 0, order_err = 0, sof_cnt = 0, last_cnt = 0, abort_cnt = 0;
    integer el, eg;
    reg [39:0] exp_pix;

    always @(posedge clk) begin
        cyc = cyc + 1;
        if (rst_n) begin
            if (out_abort) abort_cnt = abort_cnt + 1;
            if (pl_in_line) begin
                if (pl_line_d) wide_pulse = wide_pulse + 1;
                line_pulses = line_pulses + 1;
                if (line_pulses > 1) begin
                    ub_prev_line = ub_line;
                    if (ub_prev_line != CG) begin
                        line_err = line_err + 1;
                        if (line_err <= 3)
                            $display("LINE_MISMATCH line=%0d beats=%0d want=%0d",
                                     line_pulses - 2, ub_prev_line, CG);
                    end
                    if (lastbeat_t >= 0) lastword_to_beat = lastbeat_t - lastword_t;
                end
                ub_line = 0;
                li_t = cyc;
                found_first = 0;
            end
            pl_line_d = pl_in_line;
            if (up_valid) begin
                ub_line = ub_line + 1;
                if (!found_first) begin
                    found_first = 1;
                    li_to_beat = cyc - li_t;
                end
                lastbeat_t = cyc;
            end
            if (out_valid) begin
                el = ROI_Y + (exp_idx / OG);
                eg = GX + (exp_idx % OG);
                exp_pix = tap4(pval(el, eg, 0), pval(el, eg, 1),
                               pval(el, eg, 2), pval(el, eg, 3));
                if (out_pix !== exp_pix) begin
                    data_err = data_err + 1;
                    if (data_err <= 3)
                        $display("DATA_MISMATCH idx=%0d line=%0d grp=%0d got=%h want=%h",
                                 exp_idx, el, eg, out_pix, exp_pix);
                end
                if (out_sof !== (exp_idx == 0))           order_err = order_err + 1;
                if (out_last !== (exp_idx == (NGRP - 1))) order_err = order_err + 1;
                if (out_sof)  sof_cnt  = sof_cnt + 1;
                if (out_last) last_cnt = last_cnt + 1;
                exp_idx = exp_idx + 1;
            end
        end
    end

    integer y;
    integer fails;
    initial begin
        rst_n = 1'b0;
        repeat (20) @(negedge clk);
        rst_n = 1'b1;
        repeat (10) @(negedge clk);
        fails = 0;

        send_hdr(6'h00, 16'd0);                     // FS
        repeat (GAP) @(negedge clk);
        for (y = 0; y < CAM_H; y = y + 1) begin
            fill_line(y);
            send_hdr(6'h2B, WC);                    // RAW10 long packet, 80 B
            send_payload();
            send_crc();
            repeat (GAP) @(negedge clk);
        end
        send_hdr(6'h01, 16'd0);                     // FE
        repeat (60) @(negedge clk);

        if (ub_line != CG) line_err = line_err + 1;
        if (line_pulses != CAM_H) begin
            fails = fails + 1;
            $display("TB_PIPE_FAIL line_pulses=%0d want=%0d", line_pulses, CAM_H);
        end
        if (wide_pulse != 0) begin
            fails = fails + 1;
            $display("TB_PIPE_FAIL in_line wider than 1 cycle: %0d", wide_pulse);
        end
        if (line_err != 0) begin
            fails = fails + 1;
            $display("TB_PIPE_FAIL per-line beat count wrong (want %0d)", CG);
        end
        if (li_to_beat < 2 || li_to_beat > 6) begin
            fails = fails + 1;
            $display("TB_PIPE_FAIL line_in->first beat = %0d", li_to_beat);
        end
        if (lastword_to_beat < 2 || lastword_to_beat > 3) begin
            fails = fails + 1;
            $display("TB_PIPE_FAIL last payload word->last beat = %0d", lastword_to_beat);
        end
        if (exp_idx != NGRP) begin
            fails = fails + 1;
            $display("TB_PIPE_FAIL beats=%0d want=%0d", exp_idx, NGRP);
        end
        if (data_err != 0)  begin fails = fails + 1; $display("TB_PIPE_FAIL data_err=%0d", data_err); end
        if (order_err != 0) begin fails = fails + 1; $display("TB_PIPE_FAIL order_err=%0d", order_err); end
        if (sof_cnt != 1 || last_cnt != 1) begin
            fails = fails + 1; $display("TB_PIPE_FAIL sof=%0d last=%0d", sof_cnt, last_cnt);
        end
        if (abort_cnt != 0) begin fails = fails + 1; $display("TB_PIPE_FAIL abort=%0d", abort_cnt); end
        if (st_roi != 1)   begin fails = fails + 1; $display("TB_PIPE_FAIL st_roi=%0d", st_roi); end
        if (st_groups != NGRP) begin fails = fails + 1; $display("TB_PIPE_FAIL st_groups=%0d", st_groups); end
        if (st_geom != 0)  begin fails = fails + 1; $display("TB_PIPE_FAIL st_geom=%0d", st_geom); end
        if (st_short != 0) begin fails = fails + 1; $display("TB_PIPE_FAIL st_short=%0d", st_short); end
        if (crc_errors != 0 || header_errors != 0 || packet_timeouts != 0 ||
            frame_timeouts != 0 || bad_frames != 0) begin
            fails = fails + 1;
            $display("TB_PIPE_FAIL pkt crc=%0d hdr=%0d pto=%0d fto=%0d bad=%0d",
                     crc_errors, header_errors, packet_timeouts, frame_timeouts, bad_frames);
        end
        if (good_frames != 1) begin
            fails = fails + 1; $display("TB_PIPE_FAIL good_frames=%0d", good_frames);
        end

        $display("TB_PIPE_INFO beats=%0d per_line=%0d line_pulses=%0d li_to_beat=%0d lastword_to_beat=%0d data_err=%0d",
                 exp_idx, CG, line_pulses, li_to_beat, lastword_to_beat, data_err);
        $display("TB_PIPE_INFO pkt crc=%0d hdr=%0d pto=%0d fto=%0d good=%0d bad=%0d last_wc=%0d last_lines=%0d",
                 crc_errors, header_errors, packet_timeouts, frame_timeouts,
                 good_frames, bad_frames, last_wc, last_lines);
        if (fails == 0) $display("TB_PIPE_DONE PASS beats=%0d st_groups=%0d", exp_idx, st_groups);
        else            $display("TB_PIPE_DONE FAIL fails=%0d", fails);
        $finish;
    end
endmodule
