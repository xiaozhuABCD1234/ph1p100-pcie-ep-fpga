`timescale 1ns/1ps
// =============================================================================
// tb_crop_neg.v -- T10.b8-crop-geom r0 negative controls.
//
// The crop must reject a line whose group count is not exactly CAM_W/4:
//   case A: line 0 carries 965 beats  -> geom_err+1, no out_last, no ROI frame
//   case B: line 0 carries 967 beats  -> geom_err+1, no out_last, no ROI frame
//   case C: frame ends before the last ROI row -> short+1, no out_last
// Cases A/B prove the check is strict equality (the old 960 default fails the
// same way with 966); case C proves a truncated frame cannot publish.
// =============================================================================
module tb_crop_neg #(
    parameter integer CAM_W = 3864,
    parameter integer CAM_H = 2192,
    parameter integer ROI_X = 972,
    parameter integer ROI_Y = 556,
    parameter integer W     = 1920,
    parameter integer H     = 1080
) ();
    localparam integer CG   = CAM_W / 4;
    localparam integer OG   = W / 4;
    localparam integer NGRP = OG * H;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #2.6665 clk = ~clk;

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

    function [39:0] pat;
        input integer ln;
        input integer gg;
        begin
            pat = {ln[5:0], gg[3:0], ~{ln[5:0], gg[3:0]},
                   (ln[9:0] ^ {{6{1'b0}}, gg[3:0]}),
                   (10'h2A5 ^ (ln[9:0] + gg[3:0]))};
        end
    endfunction

    integer valid_cnt = 0, last_cnt = 0, sof_cnt = 0, abort_cnt = 0;
    always @(posedge clk) if (rst_n && out_valid) begin
        valid_cnt = valid_cnt + 1;
        if (out_last) last_cnt = last_cnt + 1;
        if (out_sof)  sof_cnt  = sof_cnt + 1;
    end

    task drive_line;
        input integer y;
        input integer nbeats;
        integer g;
        begin
            @(negedge clk);
            tap_line = 1'b1; tap_v = 1'b0;
            for (g = 0; g < nbeats; g = g + 1) begin
                tap_pix = pat(y, g);
                tap_v   = 1'b1;
                @(negedge clk);
            end
            tap_v = 1'b0; tap_line = 1'b0;
            repeat (4) @(negedge clk);
        end
    endtask

    integer fails;
    integer lines, y;
    integer g_roi, g_short;

    task check_case;
        input [255:0] name;
        input integer want_geom;
        input integer want_short;
        begin
            repeat (10) @(negedge clk);
            if (st_geom != want_geom) begin
                fails = fails + 1;
                $display("TB_NEG_FAIL case=%0s geom=%0d want=%0d", name, st_geom, want_geom);
            end
            if (st_short != want_short) begin
                fails = fails + 1;
                $display("TB_NEG_FAIL case=%0s short=%0d want=%0d", name, st_short, want_short);
            end
            if (last_cnt != 0) begin
                fails = fails + 1;
                $display("TB_NEG_FAIL case=%0s out_last=%0d want=0", name, last_cnt);
            end
            if (st_roi != 0) begin
                fails = fails + 1;
                $display("TB_NEG_FAIL case=%0s roi_frames=%0d want=0", name, st_roi);
            end
            $display("TB_NEG_CASE %0s geom=%0d short=%0d last=%0d sof=%0d beats=%0d abort_seen=%0d",
                     name, st_geom, st_short, last_cnt, sof_cnt, valid_cnt, abort_cnt);
        end
    endtask

    initial begin
        fails = 0;
        rst_n = 1'b0;
        repeat (20) @(negedge clk);
        rst_n = 1'b1;
        repeat (10) @(negedge clk);

        // ---- case A: 965 beats on line 0 ----------------------------------
        rst_n = 1'b0; repeat (5) @(negedge clk); rst_n = 1'b1;
        tap_frame = 1'b1; tap_vs = 1'b1;
        drive_line(0, CG - 1);
        drive_line(1, CG);                     // new_line validates line 0
        tap_frame = 1'b0; tap_vs = 1'b0;
        check_case("A_965", 1, 0);

        // ---- case B: 967 beats on line 0 ----------------------------------
        rst_n = 1'b0; repeat (5) @(negedge clk); rst_n = 1'b1;
        valid_cnt = 0; last_cnt = 0; sof_cnt = 0; abort_cnt = 0;
        tap_frame = 1'b1; tap_vs = 1'b1;
        drive_line(0, CG + 1);
        drive_line(1, CG);
        tap_frame = 1'b0; tap_vs = 1'b0;
        check_case("B_967", 1, 0);

        // ---- case C: frame stops one ROI row early ------------------------
        rst_n = 1'b0; repeat (5) @(negedge clk); rst_n = 1'b1;
        valid_cnt = 0; last_cnt = 0; sof_cnt = 0; abort_cnt = 0;
        tap_frame = 1'b1; tap_vs = 1'b1;
        for (y = 0; y < (ROI_Y + H - 1); y = y + 1) drive_line(y, CG);
        tap_frame = 1'b0; tap_vs = 1'b0;       // short frame
        check_case("C_short", 0, 1);
        if (valid_cnt != (OG * (H - 1))) begin
            fails = fails + 1;
            $display("TB_NEG_FAIL case=C_short beats=%0d want=%0d", valid_cnt, OG * (H - 1));
        end
        if (sof_cnt != 1) begin
            fails = fails + 1;
            $display("TB_NEG_FAIL case=C_short sof=%0d want=1", sof_cnt);
        end

        if (fails == 0) $display("TB_NEG_DONE PASS");
        else            $display("TB_NEG_DONE FAIL fails=%0d", fails);
        $finish;
    end
endmodule
