// =============================================================================
// a1_frame_top.v -- T10 A+ v1 frame-level codec top (test-only, P3)
//
// Raw packed RAW10 (40 bit = 4 px) in -> declared RGGB phase-0 2x2 Bayer
// plane reorder (+ optional per-plane modulo-1024 prediction) -> one
// transform-domain block per 2-row pair -> a1_deflate_core -> zlib bytes out.
//
// - 2-row pair buffer is ping-ponged (2 banks) so block assembly and encoder
//   feed overlap; sustained input rate is 5 cycles per 40-bit group
//   (= 1 byte/cycle), the encoder core remains the bottleneck (~2.15 c/B).
// - In bypass mode (prep_en=0) samples are written in raster order and
//   repacked, so xform bytes are byte-identical to raw bytes.
// - Abort / bad geometry / non-zero pred without prep never commit.
// - A 32-bit output word is held stable while out_valid && !out_ready.
//
// Field order of in_pix: [7:0]=b0, [15:8]=b1, [23:16]=b2, [31:24]=b3,
// [39:32]=b4 (b0..b3 = px[9:2], b4 = four 2-bit LSBs, b4[1:0]=P0).
//
// No dynamic Huffman, no cross-block references, no production integration.
// =============================================================================
`timescale 1ns / 1ps

module a1_frame_top #(
    parameter integer W = 1920,
    parameter integer H = 1080
) (
    input  wire        clk,
    input  wire        rst_n,

    // packed RAW10 input, one 4-pixel group per beat
    input  wire [39:0] in_pix,
    input  wire        in_valid,
    output wire        in_ready,
    input  wire        in_sof,

    // sampled at in_sof; abort terminates the running frame immediately
    input  wire        prep_en,
    input  wire        pred_en,
    input  wire        abort,

    // zlib stream, 32-bit words, low byte first
    output wire [31:0] out_data,
    output wire        out_valid,
    input  wire        out_ready,
    output wire [3:0]  out_keep,
    output wire        out_last,
    output wire        frame_commit,
    output wire        frame_abort,

    // observation (test/integration only, no production enum)
    output wire [31:0] st_raw_len,
    output wire [31:0] st_xform_len,
    output wire [31:0] st_stream_len,
    output wire [31:0] st_raw_crc,
    output wire [31:0] st_xform_crc,
    output wire [31:0] st_stream_crc,
    output wire [31:0] st_blocks,
    output wire [31:0] st_stall_cycles,
    output wire        st_busy,
    // T10.b11-aplus-read: pure observation bus (no logic change).  Layout:
    //  [1:0]dstate [4:2]istate [5]frame_active [6]wr_bank [7]rd_bank
    //  [8]cooldown [9]core_in_ready [11:10]eidx [12]first_byte
    //  [13]bank_busy0 [14]bank_busy1 [15]src_ready(=bank_busy[rd_bank])
    //  [16]din_valid(=core in_valid) [17]core_out_valid [18]core_out_ready
    //  [19]core_busy [20]core_done [25:21]core FSM state [26]in_ready
    output wire [31:0] dbg
);

    // ---------------------------------------------------------------- geometry
    localparam integer STRIDE  = (W * 5) / 4;   // bytes per row
    localparam integer HALFW   = W / 2;         // samples per plane
    localparam integer NSAMP   = 2 * W;         // samples per 2-row block
    localparam integer MEMD    = 2 * NSAMP;     // two banks
    localparam integer NBLK    = (H + 1) / 2;   // 2-row blocks
    localparam integer TAIL    = H % 2;         // 1 = odd H, last block is 1 row
    localparam integer MAXBLK  = 4800;          // a1_deflate_core block limit
    localparam integer GEOOK   = (W >= 4) && ((W % 4) == 0) && (H >= 2) &&
                                 ((2 * STRIDE) <= MAXBLK);

    // ------------------------------------------------------------------ states
    localparam [2:0] I_IDLE  = 3'd0;
    localparam [2:0] I_EXP   = 3'd1;
    localparam [2:0] I_DONE  = 3'd2;
    localparam [2:0] I_ABORT = 3'd3;
    localparam [2:0] I_DEAD  = 3'd4;

    localparam [1:0] D_IDLE = 2'd0;
    localparam [1:0] D_GATH = 2'd1;
    localparam [1:0] D_EMIT = 2'd2;
    localparam [1:0] D_FIN  = 2'd3;

    // ------------------------------------------------------------------- regs
    reg [2:0]  istate;
    reg [2:0]  byte_k;
    reg [39:0] pix_r;

    reg        wr_bank, rd_bank;
    reg [1:0]  bank_busy;
    reg [15:0] bank_ns0, bank_ns1;
    reg [15:0] row_in_blk, grp_in_row;
    reg [15:0] blk_idx;

    reg [31:0] raw_len_r, xlen_r, slen_r;
    reg [31:0] raw_crc_r, xf_crc_r, str_crc_r;
    reg [31:0] blocks_r, stall_r;

    reg        frame_active, frame_abort_r, killed, cooldown, first_byte;
    reg        prep_r, pred_r;
    reg        core_flush;
    // T10.b20-a-timing: registered abort for the drain side only.  The frame
    // abort itself (frame_abort/killed/frame_active/istate and the input-side
    // counters) stays combinational/immediate; the drain teardown
    // (dstate/bank_busy/dblk) consumes abort_d one cycle later so that no
    // drain-side cone -- in particular the ERAM read-address next state -- is
    // launched from the raw abort input.  The aborted frame is discarded, so
    // the extra cycle only lengthens its teardown.
    reg        abort_d;

    reg [1:0]  dstate;
    reg        drain_bank;
    reg [15:0] n_samp, rd_s, pj, dblk;
    reg [1:0]  gcnt;
    reg [39:0] pack40, eb;
    reg [2:0]  eidx;
    reg [9:0]  prev_s;
    reg [9:0]  dq_r;
    reg [15:0] rd_issue;
    // r0-c: registered smem read address.  The old read expression
    //   smem[(rd_issue < n_samp) ? (rd_issue + (rd_bank ? NSAMP : 0)) : 0]
    // is evaluated one cycle earlier at the rd_issue assignment sites, so the
    // memory is addressed from a register and dq_r keeps the same value and
    // the same latency (no protocol/frame change).
    reg [15:0] rd_addr;
    reg        rd_en, primed;

    reg [31:0] sdata;
    reg [3:0]  skeep;
    reg        svalid, slast;
    reg [1:0]  scnt;

    // combinational temporaries
    reg [9:0]  samp_t, d_t;
    reg [15:0] x_t, waddr_t;
    reg [1:0]  plane_t;
    reg [7:0]  b_t;

    // r0-c: smem read-address helper (same expression the old combinational
    // index used, now evaluated one cycle before the read).
    function [15:0] raddr_of;
        input [15:0] idx;
        input [15:0] ns;
        input        bank;
        begin
            raddr_of = (idx < ns) ? (idx + (bank ? NSAMP : 0)) : 16'd0;
        end
    endfunction

    reg [9:0] smem [0:MEMD-1];
    // Registered smem write port: separates the byte_k/Bayer address/data
    // chain from the ERAM write enable.  One write per input byte, no bubble.
    reg        smem_we_r;
    reg [15:0] smem_waddr_r;
    reg [9:0]  smem_wdata_r;

    // ------------------------------------------------------------- core wires
    // ------------------------------------------------------------- core wires
    wire        core_in_ready;
    wire [7:0]  core_in_data;
    wire        core_in_sop, core_in_blk_end, core_in_stream_end;
    wire        core_out_valid, core_out_last;
    wire [7:0]  core_out_data;
    wire        core_out_ready;
    wire        core_done, core_busy;
    wire [4:0]  core_state;                 // T10.b11 observation only
    wire [31:0] core_stat_blocks, core_stat_fixed, core_stat_stored;
    wire [31:0] core_stat_literals, core_stat_matches, core_stat_cand_aborts;
    wire [31:0] core_stat_stall, core_stat_max_match, core_stat_max_dist;

    wire proto_abort = frame_active && in_valid && in_sof;
    wire core_abort  = abort || proto_abort || core_flush;

    assign core_in_data       = (eb >> (eidx * 8)) & 8'hFF;
    assign core_in_sop        = (dstate == D_EMIT) && first_byte && (eidx == 3'd0);
    assign core_in_blk_end    = (dstate == D_EMIT) && (eidx == 3'd4) &&
                                (rd_s == n_samp);
    assign core_in_stream_end = core_in_blk_end && (dblk == (NBLK - 1));
    assign core_out_ready     = !svalid;


    assign out_valid    = svalid;
    assign out_data     = sdata;
    assign out_keep     = skeep;
    assign out_last     = svalid && slast && !killed;
    assign frame_commit = svalid && out_ready && slast && !killed;
    assign frame_abort  = frame_abort_r;

    assign st_raw_len      = raw_len_r;
    assign st_xform_len    = xlen_r;
    assign st_stream_len   = slen_r;
    assign st_raw_crc      = ~raw_crc_r;
    assign st_xform_crc    = ~xf_crc_r;
    assign st_stream_crc   = ~str_crc_r;
    assign st_blocks       = blocks_r;
    assign st_stall_cycles = stall_r;
    assign st_busy         = frame_active;

    // T10.b11-aplus-read: observation bus (see port comment).  Pure reads.
    // Actual bit map (the plan's [11:10]eidx field was 1 bit short because eidx
    // counts 0..4, so the pack is shifted by one from [10] up; parser matches):
    //  [1:0]dstate [4:2]istate [5]frame_active [6]wr_bank [7]rd_bank
    //  [8]cooldown [9]core_in_ready [12:10]eidx [13]first_byte [14]bank_busy0
    //  [15]bank_busy1 [16]src_ready [17]din_valid [18]core_out_valid
    //  [19]core_out_ready [20]core_busy [21]core_done [26:22]core_state
    //  [27]in_ready [31:28]=0
    assign dbg = {4'd0, in_ready, core_state, core_done, core_busy,
                  core_out_ready, core_out_valid,
                  (dstate == D_EMIT),          // [17] din_valid
                  bank_busy[rd_bank],          // [16] src_ready
                  bank_busy[1], bank_busy[0],  // [15:14]
                  first_byte, eidx,            // [13], [12:10]
                  core_in_ready,               // [9]
                  cooldown, rd_bank, wr_bank,  // [8], [7], [6]
                  frame_active, istate, dstate}; // [5], [4:2], [1:0]

    // Input ready: one group at a time.  A new frame is only started on in_sof
    // with no pending output word; a running frame is gated by the write bank.
    assign in_ready = (istate == I_IDLE) && !abort &&
                      (frame_active ? (!in_sof && !bank_busy[wr_bank])
                                    : (in_sof && !cooldown && !svalid));

    // --------------------------------------------------------------- functions
    function [31:0] crc32b;
        input [31:0] c;
        input [7:0]  d;
        integer k;
        reg [31:0] x;
        begin
            x = c ^ {24'd0, d};
            for (k = 0; k < 8; k = k + 1)
                x = x[0] ? ((x >> 1) ^ 32'hEDB88320) : (x >> 1);
            crc32b = x;
        end
    endfunction

    // ------------------------------------------------------------------- core
    a1_deflate_core u_core (
        .clk            (clk),
        .rst_n          (rst_n),
        .abort          (core_abort),
        .in_valid       (dstate == D_EMIT),
        .in_ready       (core_in_ready),
        .in_data        (core_in_data),
        .in_sop         (core_in_sop),
        .in_blk_end     (core_in_blk_end),
        .in_stream_end  (core_in_stream_end),
        .out_valid      (core_out_valid),
        .out_ready      (core_out_ready),
        .out_data       (core_out_data),
        .out_last       (core_out_last),
        .done           (core_done),
        .busy           (core_busy),
        .stat_blocks      (core_stat_blocks),
        .stat_fixed       (core_stat_fixed),
        .stat_stored      (core_stat_stored),
        .stat_literals    (core_stat_literals),
        .stat_matches     (core_stat_matches),
        .stat_cand_aborts (core_stat_cand_aborts),
        .stat_stall       (core_stat_stall),
        .stat_max_match   (core_stat_max_match),
        .stat_max_dist    (core_stat_max_dist),
        .dbg_state        (core_state)
    );

    always @(posedge clk) begin
        if (smem_we_r)
            smem[smem_waddr_r] <= smem_wdata_r;
    end

    // ---------------------------------------------------------------- sequential
    always @(posedge clk) begin
        if (!rst_n) begin
            istate        <= I_IDLE;
            byte_k        <= 3'd0;
            pix_r         <= 40'd0;
            wr_bank       <= 1'b0;
            rd_bank       <= 1'b0;
            bank_busy     <= 2'b00;
            bank_ns0      <= 16'd0;
            bank_ns1      <= 16'd0;
            row_in_blk    <= 16'd0;
            grp_in_row    <= 16'd0;
            blk_idx       <= 16'd0;
            raw_len_r     <= 32'd0;
            xlen_r        <= 32'd0;
            slen_r        <= 32'd0;
            raw_crc_r     <= 32'hFFFFFFFF;
            xf_crc_r      <= 32'hFFFFFFFF;
            str_crc_r     <= 32'hFFFFFFFF;
            blocks_r      <= 32'd0;
            stall_r       <= 32'd0;
            frame_active  <= 1'b0;
            frame_abort_r <= 1'b0;
            killed        <= 1'b0;
            cooldown      <= 1'b0;
            first_byte    <= 1'b0;
            prep_r        <= 1'b0;
            pred_r        <= 1'b0;
            core_flush    <= 1'b0;
            abort_d       <= 1'b0;
            dstate        <= D_IDLE;
            drain_bank    <= 1'b0;
            n_samp        <= 16'd0;
            rd_s          <= 16'd0;
            pj            <= 16'd0;
            dblk          <= 16'd0;
            gcnt          <= 2'd0;
            pack40        <= 40'd0;
            eb            <= 40'd0;
            eidx          <= 3'd0;
            prev_s        <= 10'd0;
            rd_issue      <= 16'd0;
            rd_en         <= 1'b0;
            primed        <= 1'b0;
            sdata         <= 32'd0;
            skeep         <= 4'd0;
            svalid        <= 1'b0;
            slast         <= 1'b0;
            scnt          <= 2'd0;
            smem_we_r     <= 1'b0;
        end else begin
            core_flush <= 1'b0;   // one-cycle core cleanup pulse after commit
            smem_we_r  <= 1'b0;
            if (rd_en)
                dq_r <= smem[rd_addr];
            // T10.b20-a-timing: register the frame-level abort for the drain
            // side.  Same condition as the immediate abort branch below, so
            // abort_d is asserted in the cycle after the abort is taken.
            abort_d <= frame_active && (abort || proto_abort) &&
                       !(svalid && out_ready && slast && !killed);
            // ------------------------------------------------ frame-level abort
            if (frame_active && (abort || proto_abort) &&
                !(svalid && out_ready && slast && !killed)) begin
                frame_abort_r <= 1'b1;
                killed        <= 1'b1;
                frame_active  <= 1'b0;
                istate        <= I_ABORT;
                blk_idx       <= 16'd0;
                row_in_blk    <= 16'd0;
                grp_in_row    <= 16'd0;
                scnt          <= 2'd0;   // drop bytes not yet presented as a word
                first_byte    <= 1'b0;   // no sop into the already-aborted core
                // dstate/dblk/bank_busy are torn down by abort_d one cycle
                // later (drain side); the aborted frame's data is discarded.
                // svalid (already published, not yet consumed) is left intact
            end else begin

                if (cooldown && !core_busy) cooldown <= 1'b0;

                if (frame_active && in_valid && !in_ready)
                    stall_r <= stall_r + 32'd1;

                // ---------------------------------------------------- input path
                if (istate == I_IDLE) begin
                    if (in_valid && in_ready) begin
                        if (!frame_active) begin
                            if (!GEOOK || (pred_en && !prep_en)) begin
                                frame_abort_r <= 1'b1;
                                killed        <= 1'b1;
                                istate        <= I_DEAD;
                            end else begin
                                frame_active  <= 1'b1;
                                frame_abort_r <= 1'b0;
                                killed        <= 1'b0;
                                prep_r        <= prep_en;
                                pred_r        <= pred_en;
                                raw_crc_r     <= 32'hFFFFFFFF;
                                xf_crc_r      <= 32'hFFFFFFFF;
                                str_crc_r     <= 32'hFFFFFFFF;
                                raw_len_r     <= 32'd0;
                                xlen_r        <= 32'd0;
                                slen_r        <= 32'd0;
                                blocks_r      <= 32'd0;
                                stall_r       <= 32'd0;
                                blk_idx       <= 16'd0;
                                row_in_blk    <= 16'd0;
                                grp_in_row    <= 16'd0;
                                wr_bank       <= 1'b0;
                                rd_bank       <= 1'b0;
                                dblk          <= 16'd0;
                                bank_busy     <= 2'b00;
                                first_byte    <= 1'b1;
                                dstate        <= D_IDLE;
                                scnt          <= 2'd0;
                                svalid        <= 1'b0;
                                slast         <= 1'b0;
                                skeep         <= 4'd0;
                                pix_r         <= in_pix;
                                byte_k        <= 3'd0;
                                istate        <= I_EXP;
                            end
                        end else begin
                            pix_r  <= in_pix;
                            byte_k <= 3'd0;
                            istate <= I_EXP;
                        end
                    end
                end else if (istate == I_EXP) begin
                    b_t = (pix_r >> (byte_k * 8)) & 8'hFF;
                    raw_crc_r <= crc32b(raw_crc_r, b_t);
                    raw_len_r <= raw_len_r + 32'd1;
                    if (byte_k != 3'd4) begin
                        x_t     = (grp_in_row << 2) + byte_k;
                        samp_t  = {b_t, 2'b00} | ((pix_r >> (32 + 2 * byte_k)) & 2'b11);
                        if (prep_r) begin
                            plane_t  = {row_in_blk[0], x_t[0]};
                            waddr_t  = (wr_bank ? NSAMP : 0) + plane_t * HALFW +
                                       (x_t >> 1);
                        end else begin
                            waddr_t  = (wr_bank ? NSAMP : 0) + row_in_blk * W + x_t;
                        end
                        smem_we_r    <= 1'b1;
                        smem_waddr_r <= waddr_t;
                        smem_wdata_r <= samp_t;
                    end
                    if (byte_k == 3'd4) begin
                        byte_k <= 3'd0;
                        istate <= I_IDLE;
                        if (grp_in_row == ((W / 4) - 1)) begin
                            grp_in_row <= 16'd0;
                            if ((row_in_blk + 1) >=
                                (((TAIL != 0) && (blk_idx == (NBLK - 1))) ? 1 : 2)) begin
                                // block complete -> publish to the drain side
                                if (wr_bank) bank_ns1 <=
                                    ((TAIL != 0 && blk_idx == (NBLK - 1)) ? W : (2 * W));
                                else bank_ns0 <=
                                    ((TAIL != 0 && blk_idx == (NBLK - 1)) ? W : (2 * W));
                                bank_busy[wr_bank] <= 1'b1;
                                row_in_blk <= 16'd0;
                                if (blk_idx == (NBLK - 1)) begin
                                    istate <= I_DONE;
                                end else begin
                                    blk_idx <= blk_idx + 16'd1;
                                    wr_bank <= ~wr_bank;
                                end
                            end else begin
                                row_in_blk <= row_in_blk + 16'd1;
                            end
                        end else begin
                            grp_in_row <= grp_in_row + 16'd1;
                        end
                    end else begin
                        byte_k <= byte_k + 3'd1;
                    end
                end else if (istate == I_ABORT) begin
                    if (!abort) istate <= I_IDLE;
                end

                // ---------------------------------------------------- drain path
                // T10.b20-a-timing: the drain teardown of an aborted frame is
                // driven by abort_d (registered), never by the raw abort input.
                // During the abort cycle itself the whole normal block is
                // skipped, so no drain/input step is taken; one cycle later the
                // drain FSM is parked in D_IDLE with no bank busy.
                if (abort_d) begin
                    dstate    <= D_IDLE;
                    dblk      <= 16'd0;
                    bank_busy <= 2'b00;
                end else case (dstate)
                    D_IDLE: begin
                        if (bank_busy[rd_bank]) begin
                            drain_bank <= rd_bank;
                            n_samp     <= rd_bank ? bank_ns1 : bank_ns0;
                            rd_s       <= 16'd0;
                            pj         <= 16'd0;
                            gcnt       <= 2'd0;
                            prev_s     <= 10'd0;
                            pack40     <= 40'd0;
                            rd_issue   <= 16'd0;
                            rd_en      <= 1'b1;
                            primed     <= 1'b0;
                            dstate     <= D_GATH;
                        end
                    end
                    D_GATH: begin
                        if (!primed) begin
                            primed   <= 1'b1;      // one prefetch cycle per block
                            rd_issue <= rd_s + 16'd1;
                            rd_en    <= 1'b1;
                        end else begin
                            d_t = (prep_r && pred_r) ?
                                  ((pj == 0) ? dq_r : ((dq_r - prev_s) & 10'h3FF)) : dq_r;
                            prev_s <= dq_r;
                            pack40 <= {pack40[29:0], d_t};
                            if (gcnt == 2'd3) begin
                                eb    <= {d_t[1:0], pack40[1:0], pack40[11:10],
                                          pack40[21:20], d_t[9:2], pack40[9:2],
                                          pack40[19:12], pack40[29:22]};
                                eidx  <= 3'd0;
                                dstate <= D_EMIT;
                            end
                            rd_s     <= rd_s + 16'd1;
                            if (gcnt != 2'd3) begin
                                rd_issue <= rd_s + 16'd2;   // 2-stage read pipeline
                            end
                            rd_en    <= 1'b1;
                            gcnt     <= gcnt + 2'd1;
                            pj       <= (pj == (HALFW - 1)) ? 16'd0 : (pj + 16'd1);
                        end
                    end
                    D_EMIT: begin
                        if (core_in_ready) begin
                            xf_crc_r   <= crc32b(xf_crc_r, core_in_data);
                            xlen_r     <= xlen_r + 32'd1;
                            first_byte <= 1'b0;
                            if (eidx == 3'd4) begin
                                if (rd_s == n_samp) begin
                                    blocks_r <= blocks_r + 32'd1;
                                    bank_busy[drain_bank] <= 1'b0;
                                    rd_bank <= ~rd_bank;
                                    dblk    <= dblk + 16'd1;
                                    if (dblk == (NBLK - 1)) dstate <= D_FIN;
                                    else begin
                                        gcnt   <= 2'd0;
                                        dstate <= D_IDLE;   // re-pick bank + n_samp
                                    end
                                end else begin
                                    gcnt     <= 2'd0;
                                    primed   <= 1'b1;
                                    rd_issue <= rd_s + 16'd1; // 2nd sample of next group
                                    dstate   <= D_GATH;
                                end
                            end else begin
                                eidx <= eidx + 3'd1;
                            end
                        end
                    end
                    default: ; // D_FIN
                endcase

                // ------------------------------------------------- output packing
                if (core_out_valid && core_out_ready) begin
                    case (scnt)
                        2'd0: sdata[7:0]   <= core_out_data;
                        2'd1: sdata[15:8]  <= core_out_data;
                        2'd2: sdata[23:16] <= core_out_data;
                        default: sdata[31:24] <= core_out_data;
                    endcase
                    str_crc_r <= crc32b(str_crc_r, core_out_data);
                    slen_r    <= slen_r + 32'd1;
                    if ((scnt == 2'd3) || core_out_last) begin
                        svalid <= 1'b1;
                        slast  <= core_out_last;
                        case (scnt)
                            2'd0: skeep <= 4'h1;
                            2'd1: skeep <= 4'h3;
                            2'd2: skeep <= 4'h7;
                            default: skeep <= 4'hF;
                        endcase
                        scnt   <= 2'd0;
                    end else begin
                        scnt <= scnt + 2'd1;
                    end
                end

                if (svalid && out_ready) begin
                    svalid <= 1'b0;
                    if (slast) slast <= 1'b0;
                    if (slast && !killed && frame_active) begin
                        // complete frame published and consumed
                        core_flush   <= 1'b1;   // P2 core leaves enc_busy set after the
                                                // last block; one abort cycle clears it
                        frame_active <= 1'b0;
                        cooldown     <= 1'b1;
                        istate       <= I_IDLE;
                        dstate       <= D_IDLE;
                        dblk         <= 16'd0;
                        blk_idx      <= 16'd0;
                        bank_busy    <= 2'b00;
                    end
                end

            end
        end
    end

    // P2 r3: memory read-address register without a reset-enable.  The ERAM
    // contents need no reset; D_IDLE seeds rd_addr before rd_en is asserted.
    always @(posedge clk) begin
        if (dstate == D_IDLE) begin
            if (bank_busy[rd_bank])
                rd_addr <= raddr_of(16'd0, rd_bank ? bank_ns1 : bank_ns0, rd_bank);
        end else if (dstate == D_GATH) begin
            if (!primed)
                rd_addr <= raddr_of(rd_s + 16'd1, n_samp, rd_bank);
            else if (gcnt != 2'd3)
                rd_addr <= raddr_of(rd_s + 16'd2, n_samp, rd_bank);
        end else if (dstate == D_EMIT) begin
            if (core_in_ready && (eidx == 3'd4) && (rd_s != n_samp))
                rd_addr <= raddr_of(rd_s + 16'd1, n_samp, rd_bank);
        end
    end

endmodule
