`timescale 1ns/1ps
// =============================================================================
// tb_crop_geom_real.v -- T10.b8-crop-geom r0
//
// Full real geometry: 3864 x 2192 valid array, 966 beats/line, 2192 lines/frame,
// ROI 972,556 1920x1080.  Two frames with different deterministic patterns.
//
// Checks (all must hold):
//   * 518,400 out_valid beats per frame, 480 per ROI row, raster order
//   * out_sof exactly on the first ROI beat, out_last exactly on the last
//   * every output beat equals the contract pattern (independent of the RTL)
//   * st_roi_frames=2, st_groups=1,036,800, st_geom_err=0, st_short=0,
//     out_abort never asserted
//   * caps/roi_real.bin = 5 B little endian per beat (for the Python reference)
//
// Plusargs: +OUT=<binary> +STAT=<text>
// =============================================================================
module tb_crop_geom_real #(
    parameter integer CAM_W = 3864,
    parameter integer CAM_H = 2192,
    parameter integer ROI_X = 972,
    parameter integer ROI_Y = 556,
    parameter integer W     = 1920,
    parameter integer H     = 1080,
    parameter integer FRAMES    = 2,
    parameter integer LINE_GAP  = 4,
    parameter integer FRAME_GAP = 40
) ();
    localparam integer CG   = CAM_W / 4;
    localparam integer OG   = W / 4;
    localparam integer GX   = ROI_X / 4;
    localparam integer NGRP = OG * H;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #2.6665 clk = ~clk;                   // 187.5 MHz camera byte clock

    reg  [39:0] tap_pix = 40'd0;
    reg         tap_v = 1'b0, tap_line = 1'b0, tap_frame = 1'b0, tap_vs = 1'b0;

    wire [39:0] out_pix;
    wire        out_valid, out_sof, out_last, out_abort;
    wire [31:0] st_roi, st_groups, st_geom, st_short;

    a1_raw_crop #(
        .CAM_W (CAM_W), .CAM_H (CAM_H), .ROI_X (ROI_X), .ROI_Y (ROI_Y),
        .W (W), .H (H)
    ) dut (
        .clk (clk), .rst_n (rst_n),
        .pix (tap_pix), .pix_valid (tap_v),
        .in_line (tap_line), .in_frame (tap_frame), .vsync (tap_vs),
        .out_pix (out_pix), .out_valid (out_valid), .out_sof (out_sof),
        .out_last (out_last), .out_abort (out_abort),
        .st_roi_frames (st_roi), .st_groups (st_groups),
        .st_geom_err (st_geom), .st_short (st_short)
    );

    integer fd, fs;
    reg [1023:0] out_path, stat_path;

    // ---- contract pattern (documented in result-r0 / make_ref_geom.py) ------
    function [9:0] pxv;
        input integer fr;
        input integer ln;
        input integer gg;
        input integer k;
        reg [9:0] b;
        begin
            case (k)
                0: b = {ln[5:0], gg[3:0]};
                1: b = ~{ln[5:0], gg[3:0]};
                2: b = ln[9:0] ^ {{6{1'b0}}, gg[3:0]};
                default: b = 10'h2A5 ^ (ln[9:0] + gg[3:0]);
            endcase
            pxv = (b + ((fr == 1) ? 10'h155 : 10'h000)) & 10'h3FF;
        end
    endfunction

    function [39:0] pack4;
        input [9:0] p0, p1, p2, p3;
        begin
            pack4 = {p3[1:0], p2[1:0], p1[1:0], p0[1:0],
                     p3[9:2], p2[9:2], p1[9:2], p0[9:2]};
        end
    endfunction

    // ---- monitors ----------------------------------------------------------
    integer frame = 0;
    integer exp_idx = 0;          // accepted beats in the current frame
    integer beats_f = 0, sof_f = 0, last_f = 0, row_beats = 0;
    integer tot_beats = 0, tot_sof = 0, tot_last = 0;
    integer data_err = 0, order_err = 0, row_err = 0, abort_cnt = 0;
    integer first_beat_line = -1, first_beat_grp = -1;
    integer last_beat_line = -1, last_beat_grp = -1;
    integer el, eg;
    reg [39:0] exp_pix;

    always @(posedge clk) begin
        if (rst_n && out_abort) abort_cnt = abort_cnt + 1;
        if (rst_n && out_valid) begin
            el = ROI_Y + (exp_idx / OG);
            eg = GX + (exp_idx % OG);
            exp_pix = pack4(pxv(frame, el, eg, 0), pxv(frame, el, eg, 1),
                            pxv(frame, el, eg, 2), pxv(frame, el, eg, 3));
            if (out_pix !== exp_pix) data_err = data_err + 1;
            if ((exp_idx % OG) == 0) begin
                if (exp_idx != 0 && row_beats != OG) row_err = row_err + 1;
                row_beats = 0;
            end
            if (out_sof !== (exp_idx == 0))           order_err = order_err + 1;
            if (out_last !== (exp_idx == (NGRP - 1))) order_err = order_err + 1;
            if (first_beat_line < 0) begin
                first_beat_line = el; first_beat_grp = eg;
            end
            last_beat_line = el; last_beat_grp = eg;
            beats_f = beats_f + 1;
            row_beats = row_beats + 1;
            if (out_sof)  sof_f  = sof_f + 1;
            if (out_last) last_f = last_f + 1;
            $fwrite(fd, "%c%c%c%c%c", exp_pix[7:0], exp_pix[15:8], exp_pix[23:16],
                    exp_pix[31:24], exp_pix[39:32]);
            exp_idx = exp_idx + 1;
        end
    end

    task drive_frame;
        input integer fr;
        integer y, g;
        begin
            @(negedge clk);
            tap_frame = 1'b1;
            tap_vs    = 1'b1;
            for (y = 0; y < CAM_H; y = y + 1) begin
                @(negedge clk);
                tap_line = 1'b1;
                tap_v    = 1'b0;
                for (g = 0; g < CG; g = g + 1) begin
                    tap_pix = pack4(pxv(fr, y, g, 0), pxv(fr, y, g, 1),
                                    pxv(fr, y, g, 2), pxv(fr, y, g, 3));
                    tap_v   = 1'b1;
                    @(negedge clk);
                end
                tap_v    = 1'b0;
                tap_line = 1'b0;
                repeat (LINE_GAP) @(negedge clk);
            end
            tap_frame = 1'b0;
            tap_vs    = 1'b0;
            repeat (FRAME_GAP) @(negedge clk);
        end
    endtask

    integer f;
    integer fails;
    initial begin
        if (!$value$plusargs("OUT=%s", out_path))  out_path  = "roi_real.bin";
        if (!$value$plusargs("STAT=%s", stat_path)) stat_path = "roi_real.stats";
        fd = $fopen(out_path, "wb");
        fs = $fopen(stat_path, "w");
        if ((fd == 0) || (fs == 0)) begin
            $display("TB_GEOM_OPEN_FAIL %0s %0s", out_path, stat_path);
            $finish;
        end
        rst_n = 1'b0;
        repeat (20) @(negedge clk);
        rst_n = 1'b1;
        repeat (10) @(negedge clk);

        fails = 0;
        for (f = 0; f < FRAMES; f = f + 1) begin
            frame = f;
            beats_f = 0; sof_f = 0; last_f = 0; row_beats = 0;
            exp_idx = 0; first_beat_line = -1;
            drive_frame(f);
            repeat (10) @(negedge clk);
            if (beats_f != NGRP)   begin fails = fails + 1; $display("TB_GEOM_FAIL frame=%0d beats=%0d want=%0d", f, beats_f, NGRP); end
            if (sof_f != 1)        begin fails = fails + 1; $display("TB_GEOM_FAIL frame=%0d sof=%0d", f, sof_f); end
            if (last_f != 1)       begin fails = fails + 1; $display("TB_GEOM_FAIL frame=%0d last=%0d", f, last_f); end
            if (first_beat_line != ROI_Y || first_beat_grp != GX)
                begin fails = fails + 1; $display("TB_GEOM_FAIL frame=%0d first=%0d,%0d", f, first_beat_line, first_beat_grp); end
            tot_beats = tot_beats + beats_f;
            tot_sof   = tot_sof + sof_f;
            tot_last  = tot_last + last_f;
        end

        $fclose(fd);
        if (st_roi !== FRAMES)        begin fails = fails + 1; $display("TB_GEOM_FAIL st_roi=%0d", st_roi); end
        if (st_groups !== (NGRP * FRAMES)) begin fails = fails + 1; $display("TB_GEOM_FAIL st_groups=%0d", st_groups); end
        if (st_geom !== 0)            begin fails = fails + 1; $display("TB_GEOM_FAIL st_geom=%0d", st_geom); end
        if (st_short !== 0)           begin fails = fails + 1; $display("TB_GEOM_FAIL st_short=%0d", st_short); end
        if (abort_cnt != 0)           begin fails = fails + 1; $display("TB_GEOM_FAIL abort=%0d", abort_cnt); end
        if (data_err != 0)            begin fails = fails + 1; $display("TB_GEOM_FAIL data_err=%0d", data_err); end
        if (order_err != 0)           begin fails = fails + 1; $display("TB_GEOM_FAIL order_err=%0d", order_err); end
        if (row_err != 0)             begin fails = fails + 1; $display("TB_GEOM_FAIL row_err=%0d", row_err); end

        $fwrite(fs, "CROP_GEOM_REAL cam_w=%0d cam_h=%0d roi_x=%0d roi_y=%0d w=%0d h=%0d frames=%0d\n",
                CAM_W, CAM_H, ROI_X, ROI_Y, W, H, FRAMES);
        $fwrite(fs, "beats=%0d sof=%0d last=%0d st_roi=%0d st_groups=%0d geom=%0d short=%0d abort=%0d\n",
                tot_beats, tot_sof, tot_last, st_roi, st_groups, st_geom, st_short, abort_cnt);
        $fwrite(fs, "data_err=%0d order_err=%0d row_err=%0d per_row=%0d ngroups=%0d first=%0d,%0d last=%0d,%0d\n",
                data_err, order_err, row_err, OG, NGRP, first_beat_line, first_beat_grp,
                last_beat_line, last_beat_grp);
        $fclose(fs);
        if (fails == 0) $display("TB_GEOM_DONE PASS beats=%0d st_groups=%0d", tot_beats, st_groups);
        else            $display("TB_GEOM_DONE FAIL fails=%0d", fails);
        $finish;
    end
endmodule
