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
    parameter integer CAM_W = 3864,
    parameter integer CAM_H = 2192,
    parameter integer ROI_X = 972,
    parameter integer ROI_Y = 556,
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
    // T10.b10 B9-03: b9 used 32'd131072, which overlapped RAW1
    // (129,600..259,199) with CMP0/CMP1 (131,072..293,241).  2^18 keeps the
    // CMP pair above the whole RAW pair: 262,144..424,313.
    parameter [31:0]  CMP_BASE = 32'd262144
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

    // T10.b9 F4: real DDR readiness of the raw slot store.  P2 drives it from
    // the synchronized ddrphy_rdy; the P1 golden testbench ties it to 1'b1 so
    // the frozen byte streams are unchanged.
    input  wire        i_ddr_rdy,

    // r0-diag: camera front-end observability (T10.b7, guide section 3/4/5).
    // i_dbg_tap/delay_done/rst_out/sync_wait and the three toggles are the
    // camera core's *existing* internal state, exported by its new o_dbg_*
    // ports.  i_dbg_sys is the clk_a1-domain snapshot produced by the sys
    // mailbox in the board top: {cam_sysstat[31:0], cam_nack_cnt[31:0]}.
    input  wire [5:0]  i_dbg_tap,
    input  wire        i_dbg_delay_done,
    input  wire        i_dbg_rst_out,
    input  wire        i_dbg_sync_wait,
    input  wire        i_dbg_pkt_tgl,
    input  wire        i_dbg_vs_tgl,
    input  wire        i_dbg_clk_tgl,
    input  wire [63:0] i_dbg_sys,

    // T10.b11 r0-diag: read-path observation from p2_ddr_bridge.  Already a
    // clk_a1 snapshot (the clk_ddr counters cross through a stable-hold
    // mailbox inside the bridge), so it can be latched by the status packet.
    // [191:160]stale_r [159:128]rlast [127:96]r_cnt [95:64]ar_block
    // [63:32]ar_cnt  [31:0]br0
    input  wire [255:0] i_dbg_bridge,

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

    // T10.b13: read-timeout purge request (1 clk_a1 pulse) to the DDR bridge.
    output wire         o_rd_abort,

    // UART
    output wire        o_uart_txd,
    output wire [7:0]  o_dbg_byte,
    output wire        o_dbg_byte_valid,

    // observation
    output wire [31:0] o_st_cap_frames,    output wire [31:0] o_st_enc_frames,
    output wire [31:0] o_st_exported,
    output wire [31:0] o_st_export_bytes,
    output wire [31:0] o_st_raw_pub,
    output wire [31:0] o_st_raw_drop,
    output wire [31:0] o_st_cmp_drop,
    output wire [31:0] o_st_geom_err,
    output wire [31:0] o_st_errors,
    output wire [31:0] o_st_read_words,
    output wire [31:0] o_st_dup_words,
    // T10.b9 status packet v3: 20 x u32 raw-store/read-path fields
    // (field 23 = raw_begin_ok in bits [31:0], field 42 = raw_deny_ddr in
    //  bits [639:608]).  Observation only; the board top may leave it open.
    output wire [639:0] o_st_raw_sts
);
    localparam integer GROUPS   = (W * H) / 4;                 // 518,400
    localparam integer RAW_WORDS = (GROUPS + 3) / 4;           // 129,600
    localparam integer EXP_RAW_BYTES = (W * H * 10) / 8;       // 2,592,000
    localparam integer CMP_WORDS = 81085;                      // >= 2,594,706/32
    // T10.b10 B9-03: real DDR capacity, read from the TD DDR IP configuration
    //   td/src/vendor/ip/ddrmc_x32/{ddrmc_x32.v,.params_ddrmc_x32.txt}
    //   DDR3-1600 x32: ROW_WIDTH=14, COL_WIDTH=10, BA_WIDTH=3, CS=1
    //     -> 2^14 * 2^10 * 2^3 * 32 bit = 4 Gbit = 512 MiB = 2^24 256-bit words
    //   AXI_ADDR_WIDTH=29 (byte address) -> 2^29 B = 512 MiB, consistent;
    //   PAXI/MC_ADDR_WIDTH=27 word address, port is 26:0.
    // 2^24 words is the binding (smaller) capacity and is used here.
    localparam integer DDR_WORDS = 16777216;                   // 2^24 x 256 bit
    localparam [31:0] GROUPS32 = GROUPS;
    localparam        PREP = (PREP_EN != 0);
    localparam        PRED = (PRED_EN != 0);

`ifdef SIMULATION
    // T10.b10 B9-03 layout assertions (simulation only).  Any overlap or a
    // too-small DDR / AWB aborts the run before a single cycle is simulated.
    initial begin
        if (!((CMP_BASE >= (RAW_BASE + 2*RAW_WORDS)) &&
              ((CMP_BASE + 2*CMP_WORDS) <= DDR_WORDS))) begin
            $display("B10_LAYOUT_FAIL raw_base=%0d raw_words=%0d cmp_base=%0d cmp_words=%0d ddr_words=%0d",
                     RAW_BASE, RAW_WORDS, CMP_BASE, CMP_WORDS, DDR_WORDS);
            $fatal(1, "B10_LAYOUT_FAIL four-slot DDR layout overlaps or exceeds capacity");
        end
        if ((RAW_WORDS > (1<<18)) || (CMP_WORDS > (1<<17))) begin
            $display("B10_LAYOUT_FAIL slot words exceed AWB raw=%0d cmp=%0d",
                     RAW_WORDS, CMP_WORDS);
            $fatal(1, "B10_LAYOUT_FAIL slot does not fit AWB");
        end
        $display("B10_LAYOUT_OK raw0=%0d..%0d raw1=%0d..%0d cmp0=%0d..%0d cmp1=%0d..%0d ddr_words=%0d",
                 RAW_BASE, RAW_BASE+RAW_WORDS-1,
                 RAW_BASE+RAW_WORDS, RAW_BASE+2*RAW_WORDS-1,
                 CMP_BASE, CMP_BASE+CMP_WORDS-1,
                 CMP_BASE+CMP_WORDS, CMP_BASE+2*CMP_WORDS-1,
                 DDR_WORDS);
    end
`endif

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

    // ======================================================================
    // r0-diag: camera-side counters (all posedge clk_cam) and the two generic
    // toggle mailboxes.  Nothing here feeds the crop, the CDC FIFO, the raw
    // store or the A+ chain: it is observation only.
    // ======================================================================
    reg [31:0] cam_pix_beats;          // 0  i_a_pixel_valid beats (4 px each)
    reg [31:0] cam_line_rises;         // 1  i_a_in_line rising edges
    reg [31:0] cam_frame_rises;        // 2  i_a_in_frame rising edges
    reg [31:0] cam_frame_falls;        // 3  i_a_in_frame falling edges
    reg [31:0] cam_vsync_rises;        // 4  i_a_vsync rising edges
    reg [31:0] cam_last_frame_cycles;  // 5  clk_cam cycles of the last frame
    reg [31:0] cam_inframe_cycles;
    reg        r_line_d, r_frame_d, r_vsync_d;

    always @(posedge clk_cam) begin
        if (!rst_n) begin
            cam_pix_beats        <= 32'd0;
            cam_line_rises       <= 32'd0;
            cam_frame_rises      <= 32'd0;
            cam_frame_falls      <= 32'd0;
            cam_vsync_rises      <= 32'd0;
            cam_last_frame_cycles<= 32'd0;
            cam_inframe_cycles   <= 32'd0;
            r_line_d <= 1'b0; r_frame_d <= 1'b0; r_vsync_d <= 1'b0;
        end else begin
            r_line_d  <= i_a_in_line;
            r_frame_d <= i_a_in_frame;
            r_vsync_d <= i_a_vsync;
            if (i_a_pixel_valid) cam_pix_beats <= cam_pix_beats + 32'd1;
            if (i_a_in_line && !r_line_d) cam_line_rises <= cam_line_rises + 32'd1;
            if (i_a_vsync  && !r_vsync_d) cam_vsync_rises <= cam_vsync_rises + 32'd1;
            if (i_a_in_frame && !r_frame_d) begin
                cam_frame_rises    <= cam_frame_rises + 32'd1;
                cam_inframe_cycles <= 32'd0;
            end else if (i_a_in_frame) begin
                cam_inframe_cycles <= cam_inframe_cycles + 32'd1;
            end
            if (!i_a_in_frame && r_frame_d) begin
                cam_frame_falls       <= cam_frame_falls + 32'd1;
                cam_last_frame_cycles <= cam_inframe_cycles;
            end
        end
    end

    // Physical status word, packed in clk_cam (guide section 4 bit map).
    wire [31:0] cam_phystat = {21'd0, i_a_vsync, i_a_in_frame, i_dbg_sync_wait,
                               i_dbg_rst_out, i_dbg_delay_done, i_dbg_tap};

    // 11 clk_cam-domain words (6 counters + 4 crop counters + physstat) cross
    // to clk_a1 through the stable-hold/toggle mailbox.  The guide's "8 words"
    // omits the four crop counters, which are also clk_cam-domain registers:
    // the packet needs all of them, so the mailbox carries 11 x 32 = 352 bit.
    wire [351:0] cam_mail_in = {crop_geom, crop_short, crop_groups, crop_frames,
                                cam_phystat, cam_last_frame_cycles,
                                cam_vsync_rises, cam_frame_falls,
                                cam_frame_rises, cam_line_rises,
                                cam_pix_beats};
    wire [351:0] cam_mail_out;

    cam_diag_mailbox #(.W(352), .DIV_BITS(12)) u_dbg_cam_mail (
        .clk_slow   (clk_cam),
        .rst_slow_n (rst_n),
        .i_data     (cam_mail_in),
        .clk_fast   (clk_a1),
        .rst_fast_n (rst_n),
        .o_data     (cam_mail_out)
    );

    wire [31:0] m_pix_beats        = cam_mail_out[31:0];
    wire [31:0] m_line_rises       = cam_mail_out[63:32];
    wire [31:0] m_frame_rises      = cam_mail_out[95:64];
    wire [31:0] m_frame_falls      = cam_mail_out[127:96];
    wire [31:0] m_vsync_rises      = cam_mail_out[159:128];
    wire [31:0] m_last_frame_cycles= cam_mail_out[191:160];
    wire [31:0] m_phystat          = cam_mail_out[223:192];
    wire [31:0] m_roi_frames       = cam_mail_out[255:224];
    wire [31:0] m_groups           = cam_mail_out[287:256];
    wire [31:0] m_short            = cam_mail_out[319:288];
    wire [31:0] m_geom_err         = cam_mail_out[351:320];

    // --------------------------------------------------- clk_a1 toggle counters
    // Three independent 2FF+edge counters (never a bus).  The toggle periods
    // are >= 1.7 kHz (clk activity) / one CSI packet / one frame, i.e. >> 2
    // clk_a1 cycles, so the edge detector cannot miss a transition.
    reg [31:0] cam_clk_tgl_inc, cam_pkt_tgl_inc, cam_vs_tgl_inc;
    (* ASYNC_REG = "TRUE" *) reg [2:0] s_clk_tgl, s_pkt_tgl, s_vs_tgl;

    always @(posedge clk_a1) begin
        if (!rst_n) begin
            cam_clk_tgl_inc <= 32'd0;
            cam_pkt_tgl_inc <= 32'd0;
            cam_vs_tgl_inc  <= 32'd0;
            s_clk_tgl <= 3'b000; s_pkt_tgl <= 3'b000; s_vs_tgl <= 3'b000;
        end else begin
            s_clk_tgl <= {s_clk_tgl[1:0], i_dbg_clk_tgl};
            s_pkt_tgl <= {s_pkt_tgl[1:0], i_dbg_pkt_tgl};
            s_vs_tgl  <= {s_vs_tgl[1:0],  i_dbg_vs_tgl};
            if (s_clk_tgl[2] ^ s_clk_tgl[1]) cam_clk_tgl_inc <= cam_clk_tgl_inc + 32'd1;
            if (s_pkt_tgl[2] ^ s_pkt_tgl[1]) cam_pkt_tgl_inc <= cam_pkt_tgl_inc + 32'd1;
            if (s_vs_tgl[2]  ^ s_vs_tgl[1])  cam_vs_tgl_inc  <= cam_vs_tgl_inc  + 32'd1;
        end
    end

    // 15 x u32 cam fields, frozen packet order (field 0 in [31:0]).
    wire [479:0] cam_sts_bus = {i_dbg_sys[31:0],        // 14 cam_nack_cnt
                                i_dbg_sys[63:32],      // 13 cam_sysstat
                                m_phystat,             // 12 cam_phystat
                                m_geom_err,            // 11 crop_geom_err
                                m_short,               // 10 crop_short
                                m_groups,              //  9 crop_groups
                                m_roi_frames,          //  8 crop_roi_frames
                                m_last_frame_cycles,   //  7 cam_last_frame_cycles
                                m_frame_falls,         //  6 cam_frame_falls
                                m_frame_rises,         //  5 cam_frame_rises
                                m_line_rises,          //  4 cam_line_rises
                                m_pix_beats,           //  3 cam_pix_beats
                                cam_vs_tgl_inc,        //  2 cam_vs_tgl_inc
                                cam_pkt_tgl_inc,       //  1 cam_pkt_tgl_inc
                                cam_clk_tgl_inc};      //  0 cam_clk_tgl_inc

    // ------------------------------------------------------ CDC cam -> A1
    // T10.b9 F1: a1_raw_crop raises out_abort for exactly one clk_cam cycle
    // with out_valid = 0 in that cycle, so an abort must be *pushed as its own
    // FIFO beat*: w_valid = crop_valid | abort, and bit 42 of the beat marks it.
    // The abort request is held until the FIFO actually accepts it, so a full
    // FIFO can no longer swallow the only abort of a frame (that was the
    // permanent WRITE-state hang seen on the board).
    wire [42:0] fifo_dout;
    wire        fifo_valid;
    reg         fifo_ready;
    wire        fifo_wready;
    reg         abort_hold;
    reg  [31:0] fifo_ovf_cnt;          // camera beats offered while the FIFO was full

    wire fifo_wabort = crop_abort | abort_hold;
    wire fifo_wvalid = crop_valid | fifo_wabort;

    always @(posedge clk_cam) begin
        if (!rst_n) begin
            abort_hold  <= 1'b0;
            fifo_ovf_cnt <= 32'd0;
        end else begin
            if (fifo_wvalid && fifo_wready && fifo_wabort) abort_hold <= 1'b0;
            else if (crop_abort)                          abort_hold <= 1'b1;
            // T10.b12 R1 (a): a beat that the CDC FIFO cannot take (SOF, LAST
            // or a middle beat) is data loss for the frame that is currently
            // being written.  Incrementing fifo_ovf_cnt alone left the store's
            // writer open forever when the lost beat was the LAST (the store
            // never sees wr_last), so every later frame was denied ("orphan
            // writer").  Raise the *sticky* loss-abort request here: the abort
            // beat is offered behind the already-queued data beats and pushed
            // as soon as the FIFO has room, which frees the half-written slot
            // and makes the rest of the damaged frame discarded.  abort_hold is
            // held until the FIFO really accepts the abort beat, so a full FIFO
            // can no longer swallow it.
            else if (fifo_wvalid && !fifo_wready)          abort_hold <= 1'b1;
            // Count only real data loss: a retried abort beat is not data.
            if (crop_valid && !fifo_wready) fifo_ovf_cnt <= fifo_ovf_cnt + 32'd1;
        end
    end

    capture_async_fifo #(.WIDTH(43), .ADDR_BITS(FIFO_AW)) u_cam_fifo (
        .rst_n   (rst_n),
        .wclk    (clk_cam),
        .w_valid (fifo_wvalid),
        .w_data  ({fifo_wabort, crop_last, crop_sof, crop_pix}),
        .w_ready (fifo_wready),
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
    reg         begin_pend, raw_abort;
    wire        raw_begin_ready, raw_wr_ready;
    reg  [31:0] raw_id;
    reg         skid_valid, skid_last;
    reg  [39:0] skid_pix;
    reg         raw_active, skip_frame;
    reg         raw_rd_close_r, raw_expect_ok;
    wire        raw_pub, raw_rd_open_ready, raw_rd_close;
    reg         raw_rd_open;
    wire [31:0] raw_rd_id, raw_rd_len;
    wire [255:0] raw_rd_data;
    wire        raw_rd_valid;
    reg         raw_rd_take;
    wire [31:0] raw_st_pub, raw_st_drop, raw_st_err, raw_st_bytes;
    wire [31:0] raw_st_read, raw_st_dup;

    // T10.b9 v3: raw-store write/read observation (all clk_a1)
    wire [31:0] raw_wr_beats, raw_wr_words, raw_wr_ptr, raw_wr_state;
    wire [31:0] raw_st_rd_state, raw_slot_st, raw_slot_len0, raw_slot_len1;
    wire [31:0] raw_rd_idx, raw_rd_words;
    wire [31:0] raw_ar_valid, raw_ar_hs, raw_rv_cnt;
    wire [31:0] raw_rd_open_ok, raw_rd_close_cnt, raw_abort_cnt;
    wire        raw_free_valid, raw_wr_active_st;
    // T10.b13: raw read timeout / retry recovery
    wire        raw_rd_timeout, raw_rd_retry_ready;
    wire [31:0] raw_timeout_cnt, raw_retry_cnt, raw_retry_giveup;
    reg  [31:0] raw_begin_ok, raw_begin_deny, raw_deny_nofree, raw_deny_ddr;

    wire skid_take = skid_valid && raw_wr_ready;
    wire skid_free = !skid_valid || skid_take;
    wire begin_hs  = begin_pend && raw_begin_ready;

    // T10.b10 R1: a data beat with no active frame (its SOF was denied, lost,
    // or the frame was aborted) is consumed and discarded.  Leaving fifo_ready
    // at 0 there was a hard FIFO deadlock: the head beat could never leave, so
    // the sticky loss-abort behind it could never be pushed and the store
    // stayed a permanent orphan writer.
    // T10.b12 R1 (b): the final else is that missing consume path.  It only
    // affects an *unowned* data beat (no SOF, no owner, not skipping, not an
    // abort beat); every beat of a normal frame still takes the raw_active ->
    // skid_free path, so the frozen P1 byte streams are unchanged.
    always @(*) begin
        fifo_ready = 1'b0;
        if (fifo_valid) begin
            if (e_sof)           fifo_ready = skid_free;
            else if (skip_frame) fifo_ready = 1'b1;
            else if (e_abort)    fifo_ready = 1'b1;
            else if (raw_active) fifo_ready = skid_free;
            else                 fifo_ready = 1'b1;   // R1: stray beat, consume only
        end
    end

    always @(posedge clk_a1) begin
        if (!rst_n) begin
            begin_pend <= 1'b0; raw_abort <= 1'b0; raw_id <= 32'd0;
            skid_valid <= 1'b0; skid_last <= 1'b0; skid_pix <= 40'd0;
            raw_active <= 1'b0; skip_frame <= 1'b0;
            raw_begin_ok <= 32'd0; raw_begin_deny <= 32'd0;
            raw_deny_nofree <= 32'd0; raw_deny_ddr <= 32'd0;
        end else begin
            raw_abort <= 1'b0;
            if (begin_hs) begin
                begin_pend  <= 1'b0;
                raw_begin_ok <= raw_begin_ok + 32'd1;
            end
            // skid consumed by the store.  T10.b10 R1: raw_active is released
            // only when the LAST beat is really taken by the store (b9 cleared
            // it as soon as the LAST entered the skid, so a stalled LAST looked
            // like a finished frame and the next SOF was denied).
            if (skid_take) skid_valid <= 1'b0;

            if (fifo_valid && fifo_ready) begin
                if (e_abort) begin
                    // one abort beat = one FIFO entry, no DDR write
                    if (raw_active) begin
                        raw_abort    <= 1'b1;
                    end
                    raw_active <= 1'b0;
                    begin_pend <= 1'b0;
                    skip_frame <= 1'b1;
                    skid_valid <= 1'b0;
                end else if (e_sof) begin
                    if (!raw_active && !begin_pend && raw_begin_ready) begin
                        raw_active <= 1'b1;
                        begin_pend <= 1'b1;
                        skip_frame <= 1'b0;
                        raw_id     <= raw_id + 32'd1;
                        skid_pix   <= e_pix;
                        skid_last  <= e_last;
                        skid_valid <= 1'b1;
                    end else begin
                        // whole-frame discard: still counted, never silent
                        raw_begin_deny <= raw_begin_deny + 32'd1;
                        if (!i_ddr_rdy)  raw_deny_ddr    <= raw_deny_ddr    + 32'd1;
                        else             raw_deny_nofree <= raw_deny_nofree + 32'd1;
                        skip_frame <= 1'b1;
                        skid_valid <= 1'b0;
                    end
                end else if (!skip_frame) begin
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
        .EXPECT_BYTES (EXP_RAW_BYTES),
        // T10.b13: only the raw reader recovers from a lost DDR read response.
        .RETRY_EN (1), .TIMEOUT_N (8192), .GUARD_N (32768), .MAX_RETRY (2)
    ) u_raw_store (
        .clk (clk_a1), .rst_n (rst_n), .ddr_ready (i_ddr_rdy),
        .wr_begin (begin_pend), .wr_begin_ready (raw_begin_ready), .wr_id (raw_id),
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
        .st_read_words (raw_st_read), .st_dup_words (raw_st_dup),
        .st_wr_beats (raw_wr_beats), .st_wr_words (raw_wr_words),
        .st_wr_ptr (raw_wr_ptr), .st_wr_state (raw_wr_state),
        .st_rd_state (raw_st_rd_state), .st_slot_st (raw_slot_st),
        .st_slot_len0 (raw_slot_len0), .st_slot_len1 (raw_slot_len1),
        .st_rd_idx (raw_rd_idx), .st_rd_words (raw_rd_words),
        .st_ar_valid (raw_ar_valid), .st_ar_hs (raw_ar_hs),
        .st_rv_cnt (raw_rv_cnt), .st_rd_open_ok (raw_rd_open_ok),
        .st_rd_close_cnt (raw_rd_close_cnt), .st_abort_cnt (raw_abort_cnt),
        .st_free_valid (raw_free_valid), .st_wr_active_out (raw_wr_active_st),
        .rd_timeout (raw_rd_timeout), .rd_retry_ready (raw_rd_retry_ready),
        .st_timeout_cnt (raw_timeout_cnt), .st_retry_cnt (raw_retry_cnt),
        .st_retry_giveup (raw_retry_giveup)
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
    wire [31:0] a1_dbg;                 // T10.b11 observation only

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
        .st_blocks (a1_blocks), .st_stall_cycles (a1_stall), .st_busy (a1_busy),
        .dbg (a1_dbg)
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

    // T10.b13b: pending cmp_abort after a read timeout.  The A+ core may still
    // hold (or later present) one packed output word in a1_frame_top's skid
    // register after the frame-level abort; with the compressed slot already
    // released (wr_active=0) that word could never be consumed, so a1_out_valid
    // stayed high and F_IDLE never restarted (1080p drop-R deadlock).
    // The orphan word is now consumed by the core handshake and *not* written
    // to the store (wr_valid is gated), then the slot is aborted.  A 16-cycle
    // tail covers the deflate core's output drain.  Nothing is ever committed.
    reg         cmp_abort_pend;
    reg  [4:0]  orphan_drain_cnt;
    wire        orphan_drain = cmp_abort_pend || (orphan_drain_cnt != 5'd0);

    assign a1_out_ready = cmp_wr_ready || orphan_drain;

    a1_ddr_slot_store #(
        .MODE (1), .SLOT_WORDS (CMP_WORDS), .BASE_WORD (CMP_BASE), .AWB (17),
        .RETRY_EN (0)      // T10.b13: the compressed slot keeps the b12 behaviour
    ) u_cmp_store (
        .clk (clk_a1), .rst_n (rst_n), .ddr_ready (1'b1),
        .wr_begin (cmp_begin), .wr_begin_ready (cmp_begin_ready), .wr_id (cmp_id),
        .wr_data ({8'd0, a1_out_data}), .wr_keep (a1_out_keep),
        .wr_valid (a1_out_valid && !orphan_drain), .wr_last (a1_out_last), .wr_ready (cmp_wr_ready),
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
    // T10.b11: bounded F_WAIT watchdog (2^24 clk_a1 = 89.5 ms @ 187.5 MHz).
    localparam [31:0] WD_LIMIT = 32'd16777216;
    reg [31:0] wd_fires;            // sim/log observation only
    reg [31:0] rd_wait_cycles;      // #50, declared early (used in the feeder)
    reg [31:0] fwait_cycles;        // #51 source, declared early (feeder watchdog)
    reg [1:0]  fstate;
    reg [255:0] wbuf;
    reg [1:0]  gidx;
    reg        first;
    reg [31:0] grp_sent;

    wire a1_can_start = (fstate == F_IDLE) && !a1_busy && !a1_out_valid &&
                        raw_rd_open_ready && cmp_begin_ready;

    assign raw_rd_close = raw_rd_close_r;

    // T10.b13: the raw store timeout is the single purge request; it goes to the
    // bridge (o_rd_abort) and to the arbiter (m0_rd_abort) in the same cycle.
    assign o_rd_abort = raw_rd_timeout;

    always @(posedge clk_a1) begin
        if (!rst_n) begin
            fstate <= F_IDLE; wbuf <= 256'd0; gidx <= 2'd0; first <= 1'b0;
            grp_sent <= 32'd0;
            wd_fires <= 32'd0;
            a1_in_pix <= 40'd0; a1_in_valid <= 1'b0; a1_in_sof <= 1'b0;
            a1_abort <= 1'b0;
            raw_rd_open <= 1'b0; raw_rd_take <= 1'b0;
            cmp_begin <= 1'b0; cmp_abort <= 1'b0; cmp_id <= 32'd0;
            raw_rd_close_r <= 1'b0;
            cmp_abort_pend <= 1'b0;
            orphan_drain_cnt <= 5'd0;
        end else begin
            cmp_begin <= 1'b0;
            cmp_abort <= 1'b0;
            a1_abort  <= 1'b0;
            raw_rd_open <= 1'b0; raw_rd_take <= 1'b0;
            raw_rd_close_r <= 1'b0;

            if (raw_rd_timeout) begin
                // Highest priority: kill the A+ half frame, stop feeding, and go
                // back to F_IDLE.  The raw slot stays READING (no rd_close) so
                // the store can retry the SAME frame after its guard window.
                a1_abort       <= 1'b1;
                a1_in_valid    <= 1'b0;
                a1_in_sof      <= 1'b0;
                grp_sent       <= 32'd0;
                cmp_abort_pend <= 1'b1;
                fstate         <= F_IDLE;
            end else begin
            if (cmp_abort_pend && !a1_out_valid) begin
                cmp_abort      <= 1'b1;   // release the orphan compressed slot
                cmp_abort_pend <= 1'b0;
                orphan_drain_cnt <= 5'd16;
            end else if (orphan_drain_cnt != 5'd0) begin
                orphan_drain_cnt <= orphan_drain_cnt - 5'd1;
            end
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
                    end else if (fwait_cycles >= WD_LIMIT) begin
                        // T10.b11 W2: bounded liveness guard.  A raw read that
                        // has been started but delivers no next DDR word for
                        // WD_LIMIT clk_a1 cycles (~89 ms @ 187.5 MHz, >1000x
                        // the normal read latency) is a dead DDR read response.
                        // Abort the frame cleanly instead of hanging forever:
                        // kill the A+ frame, cancel the compressed slot, ask the
                        // raw store to release its slot, and park in F_IDLE.
                        // A good frame never reaches this branch, so the frozen
                        // P1 byte streams are unaffected.
                        a1_abort       <= 1'b1;
                        cmp_abort      <= 1'b1;
                        raw_rd_close_r <= 1'b1;
                        wd_fires       <= wd_fires + 32'd1;
                        fstate         <= F_IDLE;
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
            end   // T10.b13: !raw_rd_timeout
        end
    end

    // ======================================================================
    // T10.b9 v3: 20 x u32 raw-store / read-path fields (frozen order, field 23
    // in bits [31:0]).  Every source is a clk_a1 register or a clk_a1 wire, so
    // the packet snapshot in a1_uart_export latches all 43 fields on ONE edge.
    // ======================================================================
    wire [31:0] raw_rd_state32 = {
        4'd0,                // [31:28]
        raw_st_rd_state[27], // [27] T10.b13 rd_state[2] (R_GUARD/R_ABORT)
        5'd0,                // [26:22]
        cmp_abort,           // [21]
        cmp_begin,           // [20]
        a1_out_last,         // [19]
        a1_in_ready,         // [18]
        a1_in_valid,         // [17]
        fstate,              // [16:15]
        cmp_begin_ready,     // [14]
        a1_out_valid,        // [13]
        a1_busy,             // [12]
        raw_active,          // [11]
        fifo_ready,          // [10]
        fifo_valid,          // [ 9]
        skid_valid,          // [ 8]
        skip_frame,          // [ 7]
        raw_rd_open_ready,   // [ 6]
        raw_rd_open,         // [ 5]
        raw_st_rd_state[4:0] // [ 4]=rd_valid [3]=rd_sel [2]=rd_armed [1:0]=rd_state
    };

    wire [639:0] raw_sts_bus = {
        raw_deny_ddr,      // 42
        raw_deny_nofree,   // 41
        raw_abort_cnt,     // 40
        raw_rd_close_cnt,  // 39
        raw_rd_open_ok,    // 38
        raw_rv_cnt,        // 37
        raw_ar_hs,         // 36
        raw_ar_valid,      // 35
        raw_rd_words,      // 34
        raw_rd_idx,        // 33
        raw_slot_len1,     // 32
        raw_slot_len0,     // 31
        raw_slot_st,       // 30
        raw_rd_state32,    // 29
        raw_wr_state,      // 28
        raw_wr_ptr,        // 27
        raw_wr_words,      // 26
        raw_wr_beats,      // 25
        raw_begin_deny,    // 24
        raw_begin_ok};     // 23

    assign o_st_raw_sts = raw_sts_bus;

    // ======================================================================
    // T10.b11-aplus-read v4: twelve clk_a1 observation words (#44..#55).
    // Every source is a clk_a1 register or wire; the two new counters are
    // saturating consecutive-cycle counters that reset on the recovery event.
    // Pure observation: no output of this block feeds the data path.
    // ======================================================================
    wire [31:0] exp_dbg;         // #54 exporter state tap
    wire [31:0] raw_stale_guard = i_dbg_bridge[223:192];   // T10.b13 #59

    always @(posedge clk_a1) begin
        if (!rst_n) begin
            rd_wait_cycles <= 32'd0;
            fwait_cycles   <= 32'd0;
        end else begin
            if (raw_st_rd_state[2] && !raw_rvalid) begin
                if (rd_wait_cycles != 32'hFFFF_FFFF)
                    rd_wait_cycles <= rd_wait_cycles + 32'd1;
            end else begin
                rd_wait_cycles <= 32'd0;
            end
            if ((fstate == F_WAIT) && !raw_rd_valid) begin
                if (fwait_cycles != 32'hFFFF_FFFF)
                    fwait_cycles <= fwait_cycles + 32'd1;
            end else begin
                fwait_cycles <= 32'd0;
            end
        end
    end

    wire [511:0] sts_ext_bus = {
        raw_stale_guard,                                         // 59 stale_guard_cnt
        raw_retry_giveup,                                        // 58
        raw_retry_cnt,                                           // 57
        raw_timeout_cnt,                                         // 56
        fwait_cycles,                                            // 55
        exp_dbg,                                                 // 54
        {28'd0, a1_dbg[15], a1_dbg[14], a1_dbg[17], a1_dbg[16]}, // 53 src0
        {18'd0, a1_dbg[13:0]},                                   // 52 frame0
        {21'd0, a1_dbg[21], a1_dbg[20], a1_dbg[19], a1_dbg[18],  // 51 core0
                a1_dbg[17], a1_dbg[9], a1_dbg[26:22]},
        rd_wait_cycles,                                          // 50
        i_dbg_bridge[191:160],                                   // 49 stale_r_cnt
        i_dbg_bridge[159:128],                                   // 48 rlast_cnt
        i_dbg_bridge[127:96],                                    // 47 r_cnt
        i_dbg_bridge[95:64],                                     // 46 ar_block_cnt
        i_dbg_bridge[63:32],                                     // 45 ar_cnt
        i_dbg_bridge[31:0]                                       // 44 br0
    };

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
        .sts_read_words (raw_st_read),
        // r0-diag: 15 x u32 camera front-end fields (frozen packet order)
        .sts_cam        (cam_sts_bus),
        // T10.b9 v3: 20 x u32 raw-store fields (frozen packet order)
        .sts_raw        (raw_sts_bus),
        // T10.b11 v4: 12 x u32 read-path / A+ observability fields (#44..#55)
        .sts_ext        (sts_ext_bus),
        .dbg_st         (exp_dbg)
    );

    // --------------------------------------------------------------- DDR mux
    a1_ddr_arb2 u_arb (
        .clk (clk_a1), .rst_n (rst_n),
        .m0_rd_abort (raw_rd_timeout),
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
