`timescale 1ns/1ps
// =============================================================================
// camera_a1_uart_top.v -- P1 offline integration top for the single-A board chain
//
//   A raw tap (w_a_pixel[39:0], 4K RAW10)
//     -> a1_raw_crop (1920x1080, 2x2 aligned, default centre ROI)
//     -> CDC fifo (camera byte clock -> A1 clock)
//     -> raw DDR slot store (2 slots, 4 groups per 256-bit word)
//     -> readback feeder -> a1_frame_top (W=1920,H=1080, A+ core bf6af390)
//     -> compressed DDR slot store (2 slots, variable length)
//     -> a1_uart_export (44-byte header + zlib stream + CRC) -> UART TX
//
// Clock domains: clk_cam (camera byte clock), clk_a1 (A+ 187.5 MHz + DDR user
// clock), clk_uart (UART baud clock).  Two CDC fifos only.
// Frame ownership: a frame is published only after the complete stream was
// written; a published (READY/READING) frame is never overwritten; a bad or
// aborted frame never publishes; reset frees every slot.
// No TD/bitgen/download is implied by this file (P1 is offline only).
//
// r1-diag (2026-10-24, diagnostic candidate only): the eight o_st_* counters
// are also routed into a1_uart_export's idle status packet (A5 5A + 8 x u32 LE
// + XOR, one packet per STS_DIV clk cycles while the exporter is idle).  The
// frame header/payload/CRC and DDR layout are untouched; STS_DIV = 0 restores
// the exact r4 behaviour.
// =============================================================================
module camera_a1_uart_top #(
    parameter integer CAM_W = 3840,
    parameter integer CAM_H = 2160,
    parameter integer ROI_X = 960,
    parameter integer ROI_Y = 540,
    parameter integer W     = 1920,
    parameter integer H     = 1080,
    parameter integer UART_DIV = 434,
    parameter integer HB_DIV   = 0,
    // r1-diag: diagnostic status packet period in clk_a1 cycles.  At the P2
    // 187.5 MHz clock the default is exactly 1.000 s.  0 disables the packet
    // and leaves the frame wire format bit-for-bit identical to r4/P1.
    parameter integer STS_DIV  = 187500000,
    parameter integer PREP_EN = 1,
    parameter integer PRED_EN = 1,
    parameter integer FIFO_AW = 9,
    parameter [31:0]  RAW_BASE = 32'd0,
    parameter [31:0]  CMP_BASE = 32'd131072
) (
    input  wire        clk_cam,
    input  wire        clk_a1,
    input  wire        clk_uart,
    input  wire        rst_n,

    // raw tap from f9p_camera_display_core (observation only)
    input  wire [39:0] i_a_pixel,
    input  wire        i_a_pixel_valid,
    input  wire        i_a_in_line,
    input  wire        i_a_in_frame,
    input  wire        i_a_vsync,

    // native 256-bit DDR port (P2 maps to PH1P PAXI)
    output wire [31:0]  o_ddr_awaddr,
    output wire         o_ddr_awvalid,
    input  wire         o_ddr_awready,
    output wire [255:0] o_ddr_wdata,
    output wire         o_ddr_wvalid,
    input  wire         o_ddr_wready,
    output wire [31:0]  o_ddr_araddr,
    output wire         o_ddr_arvalid,
    input  wire         o_ddr_arready,
    input  wire [255:0] i_ddr_rdata,
    input  wire         i_ddr_rvalid,
    output wire         o_ddr_rready,

    // UART
    output wire        o_uart_txd,
    output wire [7:0]  o_dbg_byte,
    output wire        o_dbg_byte_valid,

    // observation
    output wire [31:0] o_st_cap_frames,
    output wire [31:0] o_st_enc_frames,
    output wire [31:0] o_st_exported,
    output wire [31:0] o_st_export_bytes,
    output wire [31:0] o_st_raw_pub,
    output wire [31:0] o_st_raw_drop,
    output wire [31:0] o_st_cmp_drop,
    output wire [31:0] o_st_geom_err,
    output wire [31:0] o_st_errors,
    output wire [31:0] o_st_read_words,
    output wire [31:0] o_st_dup_words
);
    localparam integer GROUPS   = (W * H) / 4;                 // 518,400
    localparam integer RAW_WORDS = (GROUPS + 3) / 4;           // 129,600
    localparam integer EXP_RAW_BYTES = (W * H * 10) / 8;       // 2,592,000
    localparam integer CMP_WORDS = 81085;                      // >= 2,594,706/32
    localparam [31:0] GROUPS32 = GROUPS;
    localparam        PREP = (PREP_EN != 0);
    localparam        PRED = (PRED_EN != 0);

    // ------------------------------------------------------------ crop (cam)
    wire [39:0] crop_pix;
    wire        crop_valid, crop_sof, crop_last, crop_abort;
    wire [31:0] crop_frames, crop_groups, crop_geom, crop_short;

    a1_raw_crop #(
        .CAM_W (CAM_W), .CAM_H (CAM_H),
        .ROI_X (ROI_X), .ROI_Y (ROI_Y),
        .W (W), .H (H)
    ) u_crop (
        .clk (clk_cam), .rst_n (rst_n),
        .pix (i_a_pixel), .pix_valid (i_a_pixel_valid),
        .in_line (i_a_in_line), .in_frame (i_a_in_frame), .vsync (i_a_vsync),
        .out_pix (crop_pix), .out_valid (crop_valid),
        .out_sof (crop_sof), .out_last (crop_last), .out_abort (crop_abort),
        .st_roi_frames (crop_frames), .st_groups (crop_groups),
        .st_geom_err (crop_geom), .st_short (crop_short)
    );

    // ------------------------------------------------------ CDC cam -> A1
    wire [42:0] fifo_dout;
    wire        fifo_valid;
    reg         fifo_ready;

    capture_async_fifo #(.WIDTH(43), .ADDR_BITS(FIFO_AW)) u_cam_fifo (
        .rst_n   (rst_n),
        .wclk    (clk_cam),
        .w_valid (crop_valid),
        .w_data  ({crop_abort, crop_last, crop_sof, crop_pix}),
        .w_ready (),
        .rclk    (clk_a1),
        .r_valid (fifo_valid),
        .r_data  (fifo_dout),
        .r_ready (fifo_ready)
    );

    wire [39:0] e_pix   = fifo_dout[39:0];
    wire        e_sof   = fifo_dout[40];
    wire        e_last  = fifo_dout[41];
    wire        e_abort = fifo_dout[42];

    // ------------------------------------------------- raw store write path
    reg         raw_begin, raw_abort;
    wire        raw_begin_ready, raw_wr_ready;
    reg  [31:0] raw_id;
    reg         skid_valid, skid_last;
    reg  [39:0] skid_pix;
    reg         raw_active, raw_drop;
    reg         raw_rd_close_r, raw_expect_ok;
    wire        raw_pub, raw_rd_open_ready, raw_rd_close;
    reg         raw_rd_open;
    wire [31:0] raw_rd_id, raw_rd_len;
    wire [255:0] raw_rd_data;
    wire        raw_rd_valid;
    reg         raw_rd_take;
    wire [31:0] raw_st_pub, raw_st_drop, raw_st_err, raw_st_bytes;
    wire [31:0] raw_st_read, raw_st_dup;

    wire skid_take = skid_valid && raw_wr_ready;
    wire skid_free = !skid_valid || skid_take;

    always @(*) begin
        fifo_ready = 1'b0;
        if (fifo_valid) begin
            if (e_abort)       fifo_ready = 1'b1;
            else if (e_sof)    fifo_ready = skid_free && !raw_active && raw_begin_ready;
            else if (raw_drop) fifo_ready = 1'b1;
            else if (raw_active) fifo_ready = skid_free;
        end
    end

    always @(posedge clk_a1) begin
        if (!rst_n) begin
            raw_begin <= 1'b0; raw_abort <= 1'b0; raw_id <= 32'd0;
            skid_valid <= 1'b0; skid_last <= 1'b0; skid_pix <= 40'd0;
            raw_active <= 1'b0; raw_drop <= 1'b0;
        end else begin
            raw_begin   <= 1'b0;
            raw_abort   <= 1'b0;
            // skid consumed by the store
            if (skid_take) skid_valid <= 1'b0;

            if (fifo_valid && fifo_ready) begin
                if (e_abort) begin
                    if (raw_active) raw_abort <= 1'b1;
                    raw_active <= 1'b0;
                    raw_drop   <= 1'b1;
                    skid_valid <= 1'b0;
                end else if (e_sof) begin
                    raw_begin  <= 1'b1;
                    raw_id     <= raw_id + 32'd1;
                    raw_active <= 1'b1;
                    raw_drop   <= 1'b0;
                    skid_pix   <= e_pix;
                    skid_last  <= e_last;
                    skid_valid <= 1'b1;
                end else if (!raw_drop) begin
                    skid_pix   <= e_pix;
                    skid_last  <= e_last;
                    skid_valid <= 1'b1;
                    if (e_last) raw_active <= 1'b0;
                end
            end
        end
    end

    wire [31:0]  raw_awaddr, raw_araddr;
    wire         raw_awvalid, raw_awready, raw_wvalid, raw_wready;
    wire         raw_arvalid, raw_arready, raw_rvalid, raw_rready;
    wire [255:0] raw_wdata, raw_rdata;
    wire [31:0]  cmp_awaddr, cmp_araddr;
    wire         cmp_awvalid, cmp_awready, cmp_wvalid, cmp_wready;
    wire         cmp_arvalid, cmp_arready, cmp_rvalid, cmp_rready;
    wire [255:0] cmp_wdata, cmp_rdata;

    a1_ddr_slot_store #(
        .MODE (0), .SLOT_WORDS (RAW_WORDS), .BASE_WORD (RAW_BASE), .AWB (18),
        .EXPECT_BYTES (EXP_RAW_BYTES)
    ) u_raw_store (
        .clk (clk_a1), .rst_n (rst_n), .ddr_ready (1'b1),
        .wr_begin (raw_begin), .wr_begin_ready (raw_begin_ready), .wr_id (raw_id),
        .wr_data (skid_pix), .wr_keep (4'hF),
        .wr_valid (skid_valid), .wr_last (skid_last), .wr_ready (raw_wr_ready),
        .wr_abort (raw_abort),
        .rd_open (raw_rd_open), .rd_open_ready (raw_rd_open_ready),
        .rd_id (raw_rd_id), .rd_len_bytes (raw_rd_len), .rd_close (raw_rd_close),
        .rd_data (raw_rd_data), .rd_valid (raw_rd_valid), .rd_take (raw_rd_take),
        .ddr_awaddr (raw_awaddr), .ddr_awvalid (raw_awvalid), .ddr_awready (raw_awready),
        .ddr_wdata (raw_wdata), .ddr_wvalid (raw_wvalid), .ddr_wready (raw_wready),
        .ddr_araddr (raw_araddr), .ddr_arvalid (raw_arvalid), .ddr_arready (raw_arready),
        .ddr_rdata (raw_rdata), .ddr_rvalid (raw_rvalid), .ddr_rready (raw_rready),
        .st_published (raw_st_pub), .st_dropped (raw_st_drop),
        .st_errors (raw_st_err), .st_last_bytes (raw_st_bytes),
        .st_read_words (raw_st_read), .st_dup_words (raw_st_dup)
    );

    // --------------------------------------------------------- A+ frame top
    reg  [39:0] a1_in_pix;
    reg         a1_in_valid, a1_in_sof;
    wire        a1_in_ready;
    reg         a1_abort;
    wire [31:0] a1_out_data;
    wire        a1_out_valid, a1_out_ready, a1_out_last;
    wire [3:0]  a1_out_keep;
    wire        a1_commit, a1_fabort;
    wire [31:0] a1_raw_len, a1_xlen, a1_slen, a1_raw_crc, a1_xcrc, a1_scrc;
    wire [31:0] a1_blocks, a1_stall;
    wire        a1_busy;

    a1_frame_top #(.W(W), .H(H)) u_a1 (
        .clk (clk_a1), .rst_n (rst_n),
        .in_pix (a1_in_pix), .in_valid (a1_in_valid), .in_ready (a1_in_ready),
        .in_sof (a1_in_sof),
        .prep_en (PREP), .pred_en (PRED), .abort (a1_abort),
        .out_data (a1_out_data), .out_valid (a1_out_valid), .out_ready (a1_out_ready),
        .out_keep (a1_out_keep), .out_last (a1_out_last),
        .frame_commit (a1_commit), .frame_abort (a1_fabort),
        .st_raw_len (a1_raw_len), .st_xform_len (a1_xlen), .st_stream_len (a1_slen),
        .st_raw_crc (a1_raw_crc), .st_xform_crc (a1_xcrc), .st_stream_crc (a1_scrc),
        .st_blocks (a1_blocks), .st_stall_cycles (a1_stall), .st_busy (a1_busy)
    );

    // --------------------------------------------------- compressed store
    reg         cmp_begin, cmp_abort;
    wire        cmp_begin_ready, cmp_wr_ready;
    reg  [31:0] cmp_id;
    wire        cmp_open_ready, cmp_close;
    wire        cmp_open;
    wire [31:0] cmp_rd_id, cmp_rd_len;
    wire [255:0] cmp_rd_data;
    wire        cmp_rd_valid;
    wire        cmp_rd_take;
    wire [31:0] cmp_st_pub, cmp_st_drop, cmp_st_err, cmp_st_bytes;

    assign a1_out_ready = cmp_wr_ready;

    a1_ddr_slot_store #(
        .MODE (1), .SLOT_WORDS (CMP_WORDS), .BASE_WORD (CMP_BASE), .AWB (17)
    ) u_cmp_store (
        .clk (clk_a1), .rst_n (rst_n), .ddr_ready (1'b1),
        .wr_begin (cmp_begin), .wr_begin_ready (cmp_begin_ready), .wr_id (cmp_id),
        .wr_data ({8'd0, a1_out_data}), .wr_keep (a1_out_keep),
        .wr_valid (a1_out_valid), .wr_last (a1_out_last), .wr_ready (cmp_wr_ready),
        .wr_abort (cmp_abort),
        .rd_open (cmp_open), .rd_open_ready (cmp_open_ready),
        .rd_id (cmp_rd_id), .rd_len_bytes (cmp_rd_len), .rd_close (cmp_close),
        .rd_data (cmp_rd_data), .rd_valid (cmp_rd_valid), .rd_take (cmp_rd_take),
        .ddr_awaddr (cmp_awaddr), .ddr_awvalid (cmp_awvalid), .ddr_awready (cmp_awready),
        .ddr_wdata (cmp_wdata), .ddr_wvalid (cmp_wvalid), .ddr_wready (cmp_wready),
        .ddr_araddr (cmp_araddr), .ddr_arvalid (cmp_arvalid), .ddr_arready (cmp_arready),
        .ddr_rdata (cmp_rdata), .ddr_rvalid (cmp_rvalid), .ddr_rready (cmp_rready),
        .st_published (cmp_st_pub), .st_dropped (cmp_st_drop),
        .st_errors (cmp_st_err), .st_last_bytes (cmp_st_bytes)
    );

    // ---------------------------------------------------- feeder / sequencer
    localparam [1:0] F_IDLE = 2'd0, F_WAIT = 2'd1, F_FEED = 2'd2, F_END = 2'd3;
    reg [1:0]  fstate;
    reg [255:0] wbuf;
    reg [1:0]  gidx;
    reg        first;
    reg [31:0] grp_sent;

    wire a1_can_start = (fstate == F_IDLE) && !a1_busy && !a1_out_valid &&
                        raw_rd_open_ready && cmp_begin_ready;

    assign raw_rd_close = raw_rd_close_r;

    always @(posedge clk_a1) begin
        if (!rst_n) begin
            fstate <= F_IDLE; wbuf <= 256'd0; gidx <= 2'd0; first <= 1'b0;
            grp_sent <= 32'd0;
            a1_in_pix <= 40'd0; a1_in_valid <= 1'b0; a1_in_sof <= 1'b0;
            a1_abort <= 1'b0;
            raw_rd_open <= 1'b0; raw_rd_take <= 1'b0;
            cmp_begin <= 1'b0; cmp_abort <= 1'b0; cmp_id <= 32'd0;
            raw_rd_close_r <= 1'b0;
        end else begin
            cmp_begin <= 1'b0;
            cmp_abort <= 1'b0;
            a1_abort  <= 1'b0;
            raw_rd_open <= 1'b0; raw_rd_take <= 1'b0;
            raw_rd_close_r <= 1'b0;

            case (fstate)
                F_IDLE: begin
                    a1_in_valid <= 1'b0;
                    a1_in_sof   <= 1'b0;
                    if (a1_can_start) begin
                        raw_rd_open <= 1'b1;
                        cmp_begin   <= 1'b1;
                        cmp_id      <= cmp_id + 32'd1;
                        grp_sent    <= 32'd0;
                        raw_expect_ok <= (raw_rd_len == EXP_RAW_BYTES[31:0]);
                        fstate      <= F_WAIT;
                    end
                end
                F_WAIT: begin
                    a1_in_valid <= 1'b0;
                    if (raw_rd_valid) begin
                        wbuf  <= raw_rd_data;
                        gidx  <= 2'd0;
                        first <= (grp_sent == 32'd0);   // in_sof only on the frame's first group
                        raw_rd_take <= 1'b1;            // take-and-latch: consume the word here so it
                                                        // can never be presented again
                        fstate <= F_FEED;
                    end
                end
                F_FEED: begin
                    if (!a1_in_valid) begin
                        a1_in_pix   <= (gidx == 2'd0) ? wbuf[39:0] :
                                       (gidx == 2'd1) ? wbuf[79:40] :
                                       (gidx == 2'd2) ? wbuf[119:80] : wbuf[159:120];
                        a1_in_valid <= 1'b1;
                        a1_in_sof   <= first;
                    end else if (a1_in_ready) begin
                        a1_in_valid <= 1'b0;
                        a1_in_sof   <= 1'b0;
                        first       <= 1'b0;
                        grp_sent    <= grp_sent + 32'd1;
                        if (gidx == 2'd3) begin
                            gidx <= 2'd0;
                            if ((grp_sent + 32'd1) >= GROUPS32) begin
                                fstate <= F_END;
                            end else begin
                                fstate      <= F_WAIT;   // take already done at latch time
                            end
                        end else begin
                            gidx <= gidx + 2'd1;
                        end
                    end
                end
                F_END: begin
                    a1_in_valid <= 1'b0;
                    a1_in_sof   <= 1'b0;
                    if (a1_commit) begin
                        raw_rd_close_r <= 1'b1;
                        fstate <= F_IDLE;
                    end else if (a1_fabort) begin
                        cmp_abort      <= 1'b1;
                        raw_rd_close_r <= 1'b1;
                        fstate <= F_IDLE;
                    end
                end
                default: fstate <= F_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------- exporter
    reg         desc_push;
    reg  [31:0] d_raw_len, d_xlen, d_slen, d_raw_crc, d_xcrc, d_scrc, d_fid;
    wire [31:0] exp_exported, exp_bytes, exp_err;
    // r1-diag: total error count, exactly the value reported as o_st_errors and
    // mirrored into the UART status packet (field 6).
    wire [31:0] st_errors_all = raw_st_err + cmp_st_err + exp_err;

    always @(posedge clk_a1) begin
        if (!rst_n) begin
            desc_push <= 1'b0;
            d_raw_len <= 32'd0; d_xlen <= 32'd0; d_slen <= 32'd0;
            d_raw_crc <= 32'd0; d_xcrc <= 32'd0; d_scrc <= 32'd0; d_fid <= 32'd0;
        end else begin
            desc_push <= 1'b0;
            if (a1_commit) begin
                desc_push <= 1'b1;
                d_raw_len <= a1_raw_len; d_xlen <= a1_xlen; d_slen <= a1_slen;
                d_raw_crc <= a1_raw_crc; d_xcrc <= a1_xcrc; d_scrc <= a1_scrc;
                d_fid     <= cmp_id;   // store latched the incremented id at wr_begin
            end
        end
    end

    a1_uart_export #(.W(W), .H(H), .UART_DIV(UART_DIV), .HB_DIV(HB_DIV),
                     .STS_DIV(STS_DIV)) u_export (
        .clk (clk_a1), .rst_n (rst_n),
        .desc_push (desc_push),
        .d_frame_id (d_fid), .d_raw_len (d_raw_len), .d_xform_len (d_xlen),
        .d_stream_len (d_slen), .d_raw_crc (d_raw_crc), .d_xform_crc (d_xcrc),
        .d_stream_crc (d_scrc),
        .d_profile ({PRED_EN[0], PREP_EN[0]}),
        .cmp_open (cmp_open), .cmp_open_ready (cmp_open_ready),
        .cmp_len (cmp_rd_len), .cmp_id (cmp_rd_id), .cmp_close (cmp_close),
        .rd_data (cmp_rd_data), .rd_valid (cmp_rd_valid), .rd_take (cmp_rd_take),
        .dbg_byte (o_dbg_byte), .dbg_byte_valid (o_dbg_byte_valid),
        .uart_clk (clk_uart), .uart_txd (o_uart_txd),
        .st_exported (exp_exported), .st_bytes (exp_bytes), .st_err (exp_err),
        .st_busy (),
        // r1-diag: frozen status-packet snapshot, same expressions as o_st_*
        .sts_cap_frames (crop_frames),
        .sts_raw_pub    (raw_st_pub),
        .sts_enc_frames (cmp_st_pub),
        .sts_exported   (exp_exported),
        .sts_raw_drop   (raw_st_drop),
        .sts_cmp_drop   (cmp_st_drop),
        .sts_errors     (st_errors_all),
        .sts_read_words (raw_st_read)
    );

    // --------------------------------------------------------------- DDR mux
    a1_ddr_arb2 u_arb (
        .clk (clk_a1), .rst_n (rst_n),
        .m0_awaddr (raw_awaddr), .m0_awvalid (raw_awvalid), .m0_awready (raw_awready),
        .m0_wdata (raw_wdata), .m0_wvalid (raw_wvalid), .m0_wready (raw_wready),
        .m0_araddr (raw_araddr), .m0_arvalid (raw_arvalid), .m0_arready (raw_arready),
        .m0_rdata (raw_rdata), .m0_rvalid (raw_rvalid), .m0_rready (raw_rready),
        .m1_awaddr (cmp_awaddr), .m1_awvalid (cmp_awvalid), .m1_awready (cmp_awready),
        .m1_wdata (cmp_wdata), .m1_wvalid (cmp_wvalid), .m1_wready (cmp_wready),
        .m1_araddr (cmp_araddr), .m1_arvalid (cmp_arvalid), .m1_arready (cmp_arready),
        .m1_rdata (cmp_rdata), .m1_rvalid (cmp_rvalid), .m1_rready (cmp_rready),
        .s_awaddr (o_ddr_awaddr), .s_awvalid (o_ddr_awvalid), .s_awready (o_ddr_awready),
        .s_wdata (o_ddr_wdata), .s_wvalid (o_ddr_wvalid), .s_wready (o_ddr_wready),
        .s_araddr (o_ddr_araddr), .s_arvalid (o_ddr_arvalid), .s_arready (o_ddr_arready),
        .s_rdata (i_ddr_rdata), .s_rvalid (i_ddr_rvalid), .s_rready (o_ddr_rready)
    );

    // ---------------------------------------------------------------- stats
    assign o_st_cap_frames   = crop_frames;
    assign o_st_enc_frames   = cmp_st_pub;
    assign o_st_exported     = exp_exported;
    assign o_st_export_bytes = exp_bytes;
    assign o_st_raw_pub      = raw_st_pub;
    assign o_st_raw_drop     = raw_st_drop;
    assign o_st_cmp_drop     = cmp_st_drop;
    assign o_st_geom_err     = crop_geom + crop_short;
    assign o_st_errors       = st_errors_all;
    assign o_st_read_words   = raw_st_read;
    assign o_st_dup_words    = raw_st_dup;
endmodule
