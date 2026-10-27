`timescale 1ns/1ps
// =============================================================================
// a1_raw_crop.v -- A-only 2x2-aligned ROI crop of the IMX415 4K RAW10 tap.
//
// Input : w_a_pixel[39:0] (4 packed RAW10 pixels per beat, b0..b4 layout of
//         a1_frame_top), w_a_pixel_valid, w_a_in_line, w_a_in_frame.
// Output: the ROI groups in raster order, one group per accepted beat, with
//         out_sof on the first group of the ROI and out_last on the last one.
//
// Contract (frozen in T10.b1 P1):
//  - ROI_X must be a multiple of 4 (group aligned) and ROI_X/ROI_Y must be even
//    (2x2 Bayer phase preserved).  Default ROI = centre of the full valid array.
//  - Every camera line that ends at or before the last ROI line must contain
//    exactly CAM_W/4 valid groups; otherwise the frame is aborted and no
//    out_last is issued (no half frame).
//  - A frame that ends (in_frame falls) before the ROI is complete is aborted.
//  - Lines after the last ROI line cannot change already captured ROI data and
//    are not validated.
//
// T10.b8-crop-geom r0 (measured, see geometry-derivation.md):
//  - Real IMX415 tap = 3864 x 2192 valid array, 966 beats per line (4 px/beat),
//    2192 lines per frame; the 3840x2160 active window sits at (12,16).
//  - Old defaults (3840/2160/960/540) made CG=960, so the very first new_line
//    already saw 966 groups -> one st_geom_err per frame and active=0, which
//    zeroed crop_groups/raw_pub/enc/exported on the board (T10.b7 evidence).
//  - New defaults: CAM_W=3864, CAM_H=2192, ROI_X=972, ROI_Y=556, W/H=1920/1080.
//    Ports, output timing, sof/last and the four counter meanings are unchanged.
// Observation only: the display/preview path is untouched.
// =============================================================================
module a1_raw_crop #(
    parameter integer CAM_W = 3864,
    parameter integer CAM_H = 2192,
    parameter integer ROI_X = 972,
    parameter integer ROI_Y = 556,
    parameter integer W     = 1920,
    parameter integer H     = 1080
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [39:0] pix,
    input  wire        pix_valid,
    input  wire        in_line,
    input  wire        in_frame,
    input  wire        vsync,
    output reg  [39:0] out_pix,
    output reg         out_valid,
    output reg         out_sof,
    output reg         out_last,
    output reg         out_abort,
    output reg  [31:0] st_roi_frames,
    output reg  [31:0] st_groups,
    output reg  [31:0] st_geom_err,
    output reg  [31:0] st_short
);
    localparam integer CG   = CAM_W / 4;   // groups per camera line
    localparam integer OG   = W / 4;       // groups per ROI line
    localparam integer GX   = ROI_X / 4;   // first ROI group in a camera line
    localparam integer NGRP = OG * H;      // groups per ROI frame

    reg        line_d, frame_d;
    reg [15:0] line_idx, grp_idx;
    // out_cnt must hold W*H/4 (518,400 at 1920x1080) -> 20 bits, not 16.
    reg [19:0] out_cnt;
    reg        active, done;

    wire frame_rise = in_frame & ~frame_d;
    wire frame_fall = ~in_frame & frame_d;
    wire line_rise  = in_line  & ~line_d;
    wire new_line   = line_rise & ~frame_rise;

    wire [15:0] eff_line = frame_rise ? 16'd0 : (new_line ? (line_idx + 16'd1) : line_idx);
    wire [15:0] eff_grp  = (frame_rise | new_line) ? 16'd0 : grp_idx;

    wire in_roi_row = (eff_line >= ROI_Y) && (eff_line < (ROI_Y + H));
    wire in_roi_col = (eff_grp  >= GX)    && (eff_grp  < (GX + OG));
    wire take       = pix_valid && in_frame && active && !done;

    // lines that must carry a complete group count before the ROI is closed
    wire need_check = (line_idx <= (ROI_Y + H - 1));

    // ---- parameter contract -------------------------------------------------
    // Fail-closed: an illegal geometry must not elaborate, in simulation or in
    // TD, so a wrong ROI can never reach a bitstream candidate.
    generate
        if (((CAM_W % 4) != 0) || ((ROI_X % 4) != 0) || ((ROI_Y % 2) != 0) ||
            ((W % 4) != 0) || ((H % 2) != 0) ||
            ((ROI_X + W) > CAM_W) || ((ROI_Y + H) > CAM_H) ||
            (CAM_W > 65532) || (CAM_H > 65532) || (NGRP >= (1 << 20))) begin : g_geometry_bad
            a1_raw_crop_illegal_geometry_must_not_elaborate u_illegal ();
        end
    endgenerate

`ifdef SIMULATION
    // Simulation-only value report (kept out of TD by the SIMULATION macro).
    initial begin
        if ((((CAM_W % 4) != 0) || ((ROI_X % 4) != 0) || ((ROI_Y % 2) != 0) ||
             ((W % 4) != 0) || ((H % 2) != 0) ||
             ((ROI_X + W) > CAM_W) || ((ROI_Y + H) > CAM_H) ||
             (CAM_W > 65532) || (CAM_H > 65532) || (NGRP >= (1 << 20)))) begin
            $display("CROP_GEOM_ASSERT_FAIL CAM_W=%0d CAM_H=%0d ROI_X=%0d ROI_Y=%0d W=%0d H=%0d",
                     CAM_W, CAM_H, ROI_X, ROI_Y, W, H);
            $finish;
        end
        $display("CROP_GEOM_OK CAM_W=%0d CAM_H=%0d ROI_X=%0d ROI_Y=%0d W=%0d H=%0d CG=%0d OG=%0d GX=%0d NGRP=%0d",
                 CAM_W, CAM_H, ROI_X, ROI_Y, W, H, CG, OG, GX, NGRP);
    end
`endif

    always @(posedge clk) begin
        if (!rst_n) begin
            line_d <= 1'b0; frame_d <= 1'b0;
            line_idx <= 16'd0; grp_idx <= 16'd0; out_cnt <= 16'd0;
            active <= 1'b0; done <= 1'b0;
            out_pix <= 40'd0; out_valid <= 1'b0; out_sof <= 1'b0;
            out_last <= 1'b0; out_abort <= 1'b0;
            st_roi_frames <= 32'd0; st_groups <= 32'd0;
            st_geom_err <= 32'd0; st_short <= 32'd0;
        end else begin
            line_d    <= in_line;
            frame_d   <= in_frame;
            out_valid <= 1'b0;
            out_sof   <= 1'b0;
            out_last  <= 1'b0;
            out_abort <= 1'b0;

            if (frame_rise) begin
                line_idx <= 16'hFFFF;   // first line_rise is line 0
                grp_idx  <= 16'd0;
                out_cnt  <= 20'd0;
                active   <= 1'b1;
                done     <= 1'b0;
            end else if (new_line) begin
                if (active && !done && need_check && (grp_idx != CG[15:0])) begin
                    active       <= 1'b0;
                    out_abort    <= 1'b1;
                    st_geom_err  <= st_geom_err + 32'd1;
                end
                line_idx <= line_idx + 16'd1;
                grp_idx  <= 16'd0;
            end

            if (frame_fall && active && !done) begin
                active    <= 1'b0;
                out_abort <= 1'b1;
                st_short  <= st_short + 32'd1;
            end

            if (take) begin
                if (in_roi_row && in_roi_col) begin
                    out_pix    <= pix;
                    out_valid  <= 1'b1;
                    st_groups  <= st_groups + 32'd1;
                    if (out_cnt == 20'd0) out_sof <= 1'b1;
                    out_cnt <= out_cnt + 20'd1;
                    if (out_cnt == (NGRP - 1)) begin
                        out_last      <= 1'b1;
                        done          <= 1'b1;
                        st_roi_frames <= st_roi_frames + 32'd1;
                    end
                end
                grp_idx <= eff_grp + 16'd1;
            end
        end
    end
endmodule
