`timescale 1ns/1ps
// =============================================================================
// brd_cam_fe.v -- one CSI camera front end for T11.BRD.P1
//
//   camera byte clock (187.5 MHz)                     clk_core (150 MHz)
//   ------------------------------                    -----------------
//   a1_raw_crop (b18 read-only) --> 43 bit pack --> capture_async_fifo --> unpack
//
// The 43 bit beat and the abort_hold pattern are copied verbatim from
// T10.b18-b17-b/r0/changed-src/camera_a1_uart_top.v (L304-L361, board proven):
//   beat = {abort, last, sof, pix[39:0]}
//   w_valid = crop_valid | (crop_abort | abort_hold)
//   an abort is pushed as its OWN beat and is held until the FIFO takes it, so
//   a full FIFO can never swallow the only abort of a frame.
//
// Read side: sof is the first beat of the frame, eol is the last beat of a line
// (crop out_last), eof is the last beat of row H-1 and therefore occurs exactly
// once per complete frame.  An abort beat resets the row counter so the next
// frame starts clean.
// =============================================================================
module brd_cam_fe #(
    parameter integer CAM_W  = 3864,
    parameter integer CAM_H  = 2192,
    parameter integer ROI_X  = 972,
    parameter integer ROI_Y  = 556,
    parameter integer W      = 1920,
    parameter integer H      = 1080,
    parameter integer FIFO_AW = 10
) (
    // ---- camera byte-clock domain ----
    input  wire         cam_clk,
    input  wire         cam_rst_n,
    input  wire [39:0]  cam_pix,
    input  wire         cam_pix_valid,
    input  wire         cam_in_line,
    input  wire         cam_in_frame,
    input  wire         cam_vsync,
    output wire [31:0]  st_frames,
    output wire [31:0]  st_groups,
    output wire [31:0]  st_abort,
    output wire [31:0]  st_ovf,

    // ---- core domain ----
    input  wire         core_clk,
    input  wire         core_rst_n,
    output wire [39:0]  o_pix,
    output wire         o_valid,
    output wire         o_sof,
    output wire         o_eol,
    output wire         o_eof,
    output wire         o_abort,
    input  wire         o_ready
);

    // ------------------------------------------------------------------
    // camera-domain crop
    // ------------------------------------------------------------------
    wire [39:0] crop_pix;
    wire        crop_valid, crop_sof, crop_last, crop_abort;
    wire [31:0] c_roi_frames, c_groups, c_geom_err, c_short;

    a1_raw_crop #(
        .CAM_W (CAM_W), .CAM_H (CAM_H),
        .ROI_X (ROI_X), .ROI_Y (ROI_Y),
        .W     (W),     .H     (H)
    ) u_crop (
        .clk        (cam_clk),
        .rst_n      (cam_rst_n),
        .pix        (cam_pix),
        .pix_valid  (cam_pix_valid),
        .in_line    (cam_in_line),
        .in_frame   (cam_in_frame),
        .vsync      (cam_vsync),
        .out_pix    (crop_pix),
        .out_valid  (crop_valid),
        .out_sof    (crop_sof),
        .out_last   (crop_last),
        .out_abort  (crop_abort),
        .st_roi_frames (c_roi_frames),
        .st_groups  (c_groups),
        .st_geom_err(c_geom_err),
        .st_short   (c_short)
    );

    // ------------------------------------------------------------------
    // 43 bit pack + abort hold (b18 verbatim pattern)
    // ------------------------------------------------------------------
    wire [42:0] fifo_dout;
    wire        fifo_valid;
    wire        fifo_wready;
    reg         abort_hold;
    reg  [31:0] fifo_ovf_cnt;
    reg  [31:0] abort_cnt;
    reg  [31:0] frame_cnt;

    wire fifo_wabort = crop_abort | abort_hold;
    wire fifo_wvalid = crop_valid | fifo_wabort;

    always @(posedge cam_clk) begin
        if (!cam_rst_n) begin
            abort_hold   <= 1'b0;
            fifo_ovf_cnt <= 32'd0;
            abort_cnt    <= 32'd0;
            frame_cnt    <= 32'd0;
        end else begin
            if (fifo_wvalid && fifo_wready && fifo_wabort) begin
                abort_hold <= 1'b0;
                abort_cnt  <= abort_cnt + 32'd1;
            end else if (crop_abort) begin
                abort_hold <= 1'b1;
            end else if (fifo_wvalid && !fifo_wready) begin
                abort_hold <= 1'b1;
            end
            if (crop_valid && !fifo_wready) fifo_ovf_cnt <= fifo_ovf_cnt + 32'd1;
            if (crop_sof)                   frame_cnt    <= frame_cnt + 32'd1;
        end
    end

    capture_async_fifo #(.WIDTH(43), .ADDR_BITS(FIFO_AW)) u_cam_fifo (
        .rst_n   (cam_rst_n),
        .wclk    (cam_clk),
        .w_valid (fifo_wvalid),
        .w_data  ({fifo_wabort, crop_last, crop_sof, crop_pix}),
        .w_ready (fifo_wready),
        .rclk    (core_clk),
        .r_valid (fifo_valid),
        .r_data  (fifo_dout),
        .r_ready (o_ready)
    );

    assign st_frames = frame_cnt;
    assign st_groups = c_groups;
    assign st_abort  = abort_cnt;
    assign st_ovf    = fifo_ovf_cnt;

    // ------------------------------------------------------------------
    // read-side unpack (core domain)
    // ------------------------------------------------------------------
    wire [39:0] e_pix   = fifo_dout[39:0];
    wire        e_sof   = fifo_dout[40];
    wire        e_last  = fifo_dout[41];
    wire        e_abort = fifo_dout[42];

    assign o_pix   = e_pix;
    assign o_valid = fifo_valid;
    assign o_sof   = fifo_valid & e_sof & ~e_abort;
    assign o_abort = fifo_valid & e_abort;

    // a1_raw_crop's out_last marks the LAST GROUP OF THE WHOLE ROI, not a line
    // end, so eol/eof must be rebuilt from the group/row counters.  eof is the
    // last group of row H-1 and therefore occurs exactly once per complete frame.
    reg [15:0] row_cnt;
    reg [15:0] grp_cnt;

    wire beat_hs = fifo_valid & o_ready;

    assign o_eol = fifo_valid & ~e_abort & (grp_cnt == ((W/4) - 1));
    assign o_eof = o_eol & (row_cnt == (H[15:0] - 16'd1));

    always @(posedge core_clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            row_cnt <= 16'd0;
            grp_cnt <= 16'd0;
        end else if (beat_hs) begin
            if (o_abort) begin
                row_cnt <= 16'd0;
                grp_cnt <= 16'd0;
            end else if (o_eol) begin
                grp_cnt <= 16'd0;
                row_cnt <= o_eof ? 16'd0 : (row_cnt + 16'd1);
            end else begin
                grp_cnt <= grp_cnt + 16'd1;
            end
        end
    end

endmodule
