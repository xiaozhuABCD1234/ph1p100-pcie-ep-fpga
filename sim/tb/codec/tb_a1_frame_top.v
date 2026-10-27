// =============================================================================
// tb_a1_frame_top.v -- P3 frame-level TB for a1_frame_top
//
// Parameterised by W/H; one generated wrapper module per case selects the
// geometry.  Reads a raw packed-RAW10 binary frame, drives 40-bit groups with
// valid/ready, collects the committed zlib bytes as hex, and records counters.
//
// Plusargs:
//   +MODE=0 clean | 1 abort+clean | 2 reset+clean | 3 proto-sof+clean |
//         4 out-stall + abort + clean | 5 clean with random output ready
//   +IN= +OUT=            phase 1 frame / output hex
//   +IN2= +OUT2=          phase 2 frame / output hex
//   +PREP=0|1 +PRED=0|1   phase 1 config   (+PREP2/+PRED2 phase 2)
//   +ABORT_AT=<group> +RST_AT=<group> +PROTO_AT=<group>
//   +STAT=<txt> +TIMEOUT=<cycles>
//
// No board, no download, no production path.
// =============================================================================
`timescale 1ns / 1ps

module tb_a1_frame_top #(
    parameter integer W = 1920,
    parameter integer H = 1080
) ();

    localparam integer STRIDE = (W * 5) / 4;
    localparam integer NVALS  = STRIDE * H;
    localparam integer NGRP   = NVALS / 5;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg         rst_n = 1'b0;
    reg  [39:0] in_pix = 40'd0;
    reg         in_valid = 1'b0;
    wire        in_ready;
    reg         in_sof = 1'b0;
    reg         prep_en = 1'b0;
    reg         pred_en = 1'b0;
    reg         abort = 1'b0;

    wire [31:0] out_data;
    wire        out_valid;
    reg         out_ready = 1'b1;
    wire [3:0]  out_keep;
    wire        out_last;
    wire        frame_commit;
    wire        frame_abort;

    wire [31:0] st_raw_len, st_xform_len, st_stream_len;
    wire [31:0] st_raw_crc, st_xform_crc, st_stream_crc;
    wire [31:0] st_blocks, st_stall_cycles;
    wire        st_busy;

    a1_frame_top #(.W(W), .H(H)) dut (
        .clk(clk), .rst_n(rst_n),
        .in_pix(in_pix), .in_valid(in_valid), .in_ready(in_ready), .in_sof(in_sof),
        .prep_en(prep_en), .pred_en(pred_en), .abort(abort),
        .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready),
        .out_keep(out_keep), .out_last(out_last),
        .frame_commit(frame_commit), .frame_abort(frame_abort),
        .st_raw_len(st_raw_len), .st_xform_len(st_xform_len),
        .st_stream_len(st_stream_len), .st_raw_crc(st_raw_crc),
        .st_xform_crc(st_xform_crc), .st_stream_crc(st_stream_crc),
        .st_blocks(st_blocks), .st_stall_cycles(st_stall_cycles),
        .st_busy(st_busy)
    );

    reg [7:0] rawmem [0:NVALS-1];

    integer cyc = 0;
    always @(posedge clk) begin
        cyc <= cyc + 1;
        if ((cyc % 200000) == 0)
            $display("DBG_ST t=%0t ist=%0d cool=%b busy=%b fa=%b sv=%b ir=%b ds=%0d dblk=%0d bb=%b iv=%b iso=%b",
                     $time, dut.istate, dut.cooldown, dut.core_busy, dut.frame_active,
                     dut.svalid, in_ready, dut.dstate, dut.dblk, dut.bank_busy, in_valid, in_sof);
    end

    // ------------------------------------------------------- capture / counters
    integer ofd = 0;
    reg     capture = 0;
    integer commit_cnt = 0, last_cnt = 0, outbytes = 0;
    reg     abort_seen = 0;
    integer stab_err = 0, xerr = 0;
    integer commit_cyc = 0, first_cyc = 0;
    reg     phase_started = 0;
    reg [31:0] prev_data = 32'd0;
    reg [3:0]  prev_keep = 4'd0;
    reg        prev_valid = 1'b0;
    integer k;

    // debug (TB only)
    reg fab_d = 1'b0;
    reg fab_seen_d = 1'b0;
    always @(posedge clk) begin
        if (frame_abort && !fab_d)
            $display("DBG_ABORT t=%0t istate=%0d dstate=%0d raw=%0d xlen=%0d blk=%0d grp=%0d dblk=%0d rds=%0d bank=%b iv=%b isof=%b ab=%b",
                     $time, dut.istate, dut.dstate, dut.raw_len_r, dut.xlen_r,
                     dut.blk_idx, dut.grp_in_row, dut.dblk, dut.rd_s,
                     dut.bank_busy, in_valid, in_sof, abort);
        fab_d <= frame_abort;
        if (frame_commit) $display("DBG_COMMIT t=%0t", $time);
    end

    // control / stats (declared before the tasks that use them)
    integer mode = 0, pa = 0, pr = 0, pa2 = 0, pr2 = 0;
    integer abort_at = 0, rst_at = 0, proto_at = 0;
    integer timeout_max = 9000000;
    integer errs = 0;
    integer statf = 0;
    reg [1023:0] in1, out1, in2, out2, statp;
    integer stall_ok;
    integer last_any = 0;
    integer multi_nframes = 2;
    integer tmo2 = 0;

    always @(posedge clk) begin
        if (out_valid && out_ready && capture) begin
            for (k = 0; k < 4; k = k + 1)
                if (out_keep[k]) $fwrite(ofd, "%02x", out_data[8*k +: 8]);
            outbytes = outbytes + 1;
            if (out_last) last_cnt = last_cnt + 1;
        end
        if (frame_commit) begin
            commit_cnt = commit_cnt + 1;
            commit_cyc = cyc;
        end
        if (out_valid && out_ready && out_last) last_any = last_any + 1;
        if (frame_abort && !fab_seen_d) abort_seen = 1;
        fab_seen_d <= frame_abort;
        if (out_valid && ((^out_data) === 1'bx)) xerr = xerr + 1;
        if (out_valid && !out_ready) begin
            if (prev_valid && ((out_data !== prev_data) || (out_keep !== prev_keep)))
                stab_err = stab_err + 1;
            prev_data  = out_data;
            prev_keep  = out_keep;
            prev_valid = 1'b1;
        end else begin
            prev_valid = 1'b0;
        end
    end

    // ------------------------------------------------------------- out_ready
    integer bp_mode = 0;
    reg     rel = 1'b0;
    always @(negedge clk) begin
        case (bp_mode)
            0: out_ready <= 1'b1;
            1: out_ready <= (($random & 3) != 0);
            3: out_ready <= !(out_valid && out_last);
            default: out_ready <= rel;
        endcase
    end

    // --------------------------------------------------------------- driving
    task drive_group;
        input [39:0] p;
        input        sof;
        begin
            @(negedge clk);
            in_pix   <= p;
            in_sof   <= sof;
            in_valid <= 1'b1;
            #1;
            // in_ready is stable between clock edges; only sample it at a
            // negedge, then the very next posedge is the handshake edge.
            while (!in_ready) begin
                @(negedge clk);
                #1;
            end
            @(posedge clk);
            if (!phase_started) begin
                first_cyc = cyc;
                phase_started = 1'b1;
            end
            @(negedge clk);
            in_valid <= 1'b0;
            in_sof   <= 1'b0;
        end
    endtask

    // --------------------------------------------------------------- one phase
    task run_phase;
        input integer pno;
        input [1023:0] inpath;
        input [1023:0] outpath;
        input integer prep, pred;
        input integer abort_at, rst_at, proto_at;
        input integer wait_done;
        integer fd, nr, g, tmo;
        reg [39:0] g40;
        begin
            commit_cnt = 0; last_cnt = 0; outbytes = 0;
            abort_seen = 1'b0; stab_err = 0; xerr = 0;
            commit_cyc = 0; first_cyc = cyc; phase_started = 1'b0;
            prev_valid = 1'b0;

            fd = $fopen(inpath, "rb");
            if (fd == 0) begin
                $display("ERR_OPEN_IN %0s", inpath);
                errs = errs + 1;
            end else begin
                nr = $fread(rawmem, fd);
                $fclose(fd);
                if (nr != NVALS) begin
                    $display("ERR_RAW_LEN got=%0d want=%0d", nr, NVALS);
                    errs = errs + 1;
                end
            end

            ofd = $fopen(outpath, "w");
            if (ofd == 0) begin $display("ERR_OPEN_OUT %0s", outpath); errs = errs + 1; end
            capture = 1'b1;
            prep_en = (prep != 0);
            pred_en = (pred != 0);

            g = 0;
            while (g < NGRP) begin
                if ((abort_at > 0) && (g == abort_at)) begin
                    @(negedge clk); abort <= 1'b1;
                    repeat (3) @(negedge clk);
                    abort <= 1'b0;
                    g = NGRP;
                end else if ((rst_at > 0) && (g == rst_at)) begin
                    @(negedge clk); rst_n <= 1'b0;
                    repeat (4) @(negedge clk);
                    rst_n <= 1'b1;
                    g = NGRP;
                end else if ((proto_at > 0) && (g == proto_at)) begin
                    g40 = {rawmem[g*5+4], rawmem[g*5+3], rawmem[g*5+2],
                           rawmem[g*5+1], rawmem[g*5]};
                    @(negedge clk);
                    in_pix <= g40; in_sof <= 1'b1; in_valid <= 1'b1;
                    repeat (4) @(negedge clk);
                    in_valid <= 1'b0; in_sof <= 1'b0;
                    g = NGRP;
                end else begin
                    g40 = {rawmem[g*5+4], rawmem[g*5+3], rawmem[g*5+2],
                           rawmem[g*5+1], rawmem[g*5]};
                    drive_group(g40, (g == 0));
                    g = g + 1;
                end
            end

            in_valid <= 1'b0;
            in_sof   <= 1'b0;

            if (wait_done != 0) begin
                tmo = 0;
                while ((commit_cnt == 0) && !abort_seen && (tmo < timeout_max)) begin
                    @(posedge clk);
                    tmo = tmo + 1;
                end
                if (commit_cnt == 0 && !abort_seen) begin
                    $display("ERR_TIMEOUT phase %0d", pno);
                    errs = errs + 1;
                end
            end else begin
                repeat (30) @(posedge clk);
            end
            repeat (4) @(posedge clk);
            capture = 1'b0;
            @(negedge clk);
            if (ofd != 0) $fclose(ofd);
            ofd = 0;

            $fdisplay(statf, "p%0d_commit %0d", pno, commit_cnt);
            $fdisplay(statf, "p%0d_last %0d", pno, last_cnt);
            $fdisplay(statf, "p%0d_abort %0d", pno, abort_seen);
            $fdisplay(statf, "p%0d_outbytes %0d", pno, outbytes);
            $fdisplay(statf, "p%0d_stab_err %0d", pno, stab_err);
            $fdisplay(statf, "p%0d_xerr %0d", pno, xerr);
            $fdisplay(statf, "p%0d_cycles %0d", pno,
                      (commit_cyc > first_cyc) ? (commit_cyc - first_cyc) : 0);
            $fdisplay(statf, "p%0d_raw_len %0d", pno, st_raw_len);
            $fdisplay(statf, "p%0d_xform_len %0d", pno, st_xform_len);
            $fdisplay(statf, "p%0d_stream_len %0d", pno, st_stream_len);
            $fdisplay(statf, "p%0d_raw_crc %08x", pno, st_raw_crc);
            $fdisplay(statf, "p%0d_xform_crc %08x", pno, st_xform_crc);
            $fdisplay(statf, "p%0d_stream_crc %08x", pno, st_stream_crc);
            $fdisplay(statf, "p%0d_blocks %0d", pno, st_blocks);
            $fdisplay(statf, "p%0d_stall %0d", pno, st_stall_cycles);
            $fdisplay(statf, "p%0d_w %0d", pno, W);
            $fdisplay(statf, "p%0d_h %0d", pno, H);
            $fdisplay(statf, "p%0d_prep %0d", pno, prep);
            $fdisplay(statf, "p%0d_pred %0d", pno, pred);
        end
    endtask


    // ---------------------------------------------------------- extra drivers
    task drive_all;
        input [1023:0] inpath;
        input integer prep, pred;
        integer fd, nr, g;
        reg [39:0] g40;
        begin
            fd = $fopen(inpath, "rb");
            if (fd == 0) begin $display("ERR_OPEN_IN"); errs = errs + 1; end
            else begin
                nr = $fread(rawmem, fd);
                $fclose(fd);
                if (nr != NVALS) begin $display("ERR_RAW_LEN"); errs = errs + 1; end
            end
            prep_en = (prep != 0);
            pred_en = (pred != 0);
            for (g = 0; g < NGRP; g = g + 1) begin
                g40 = {rawmem[g*5+4], rawmem[g*5+3], rawmem[g*5+2],
                       rawmem[g*5+1], rawmem[g*5]};
                drive_group(g40, (g == 0));
            end
            in_valid <= 1'b0;
            in_sof   <= 1'b0;
        end
    endtask

    task drive_first;
        input [1023:0] inpath;
        integer fd, nr;
        reg [39:0] g40;
        begin
            fd = $fopen(inpath, "rb");
            if (fd == 0) errs = errs + 1;
            else begin
                nr = $fread(rawmem, fd);
                $fclose(fd);
                if (nr != NVALS) errs = errs + 1;
            end
            g40 = {rawmem[4], rawmem[3], rawmem[2], rawmem[1], rawmem[0]};
            drive_group(g40, 1'b1);
        end
    endtask

    task run_multi;
        input integer nframes;
        input [1023:0] inpath;
        input [1023:0] outpath;
        input integer prep, pred;
        integer fd, nr, g, f, tmo, c0, c1;
        reg [39:0] g40;
        begin
            commit_cnt = 0; last_cnt = 0; abort_seen = 0; stab_err = 0; xerr = 0;
            fd = $fopen(inpath, "rb");
            nr = $fread(rawmem, fd);
            $fclose(fd);
            if (nr != NVALS) errs = errs + 1;
            ofd = $fopen(outpath, "w");
            capture = 1'b1;
            prep_en = (prep != 0); pred_en = (pred != 0);
            c0 = 0; c1 = 0;
            for (f = 0; f < nframes; f = f + 1) begin
                commit_cnt = 0; last_cnt = 0; abort_seen = 0; phase_started = 1'b0;
                for (g = 0; g < NGRP; g = g + 1) begin
                    g40 = {rawmem[g*5+4], rawmem[g*5+3], rawmem[g*5+2],
                           rawmem[g*5+1], rawmem[g*5]};
                    drive_group(g40, (g == 0));
                end
                in_valid <= 1'b0; in_sof <= 1'b0;
                tmo = 0;
                while ((commit_cnt == 0) && !abort_seen && (tmo < timeout_max)) begin
                    @(posedge clk); tmo = tmo + 1;
                end
                if (f == 0) c0 = first_cyc;
                c1 = commit_cyc;
                $fdisplay(statf, "m%0d_commit %0d", f+1, commit_cnt);
                $fdisplay(statf, "m%0d_last %0d", f+1, last_cnt);
                $fdisplay(statf, "m%0d_stream_len %0d", f+1, st_stream_len);
                $fdisplay(statf, "m%0d_blocks %0d", f+1, st_blocks);
                $fdisplay(statf, "m%0d_cycles %0d", f+1,
                          (commit_cyc > first_cyc) ? (commit_cyc - first_cyc) : 0);
                repeat (4) @(posedge clk);
            end
            capture = 1'b0;
            @(negedge clk);
            if (ofd != 0) $fclose(ofd);
            ofd = 0;
            $fdisplay(statf, "multi_n %0d", nframes);
            $fdisplay(statf, "multi_total_cycles %0d", (c1 > c0) ? (c1 - c0) : 0);
            $fdisplay(statf, "multi_bytes %0d", nframes * NVALS);
        end
    endtask

    // ------------------------------------------------------------------ control
    initial begin
        in1 = 0; out1 = 0; in2 = 0; out2 = 0;
        $value$plusargs("MODE=%d", mode);
        if (!$value$plusargs("IN=%s", in1))       begin $display("no +IN"); errs = errs + 1; end
        if (!$value$plusargs("OUT=%s", out1))     begin $display("no +OUT"); errs = errs + 1; end
        if (!$value$plusargs("STAT=%s", statp))   begin $display("no +STAT"); errs = errs + 1; end
        $value$plusargs("IN2=%s", in2);
        $value$plusargs("OUT2=%s", out2);
        $value$plusargs("PREP=%d", pa);
        $value$plusargs("PRED=%d", pr);
        $value$plusargs("PREP2=%d", pa2);
        $value$plusargs("PRED2=%d", pr2);
        $value$plusargs("ABORT_AT=%d", abort_at);
        $value$plusargs("RST_AT=%d", rst_at);
        $value$plusargs("PROTO_AT=%d", proto_at);
        $value$plusargs("BP=%d", bp_mode);
        $value$plusargs("TIMEOUT=%d", timeout_max);
        $value$plusargs("NFRAMES=%d", multi_nframes);

        statf = $fopen(statp, "w");
        if (statf == 0) begin $display("no stat file"); $finish; end
        $fdisplay(statf, "mode %0d", mode);
        $fdisplay(statf, "w %0d", W);
        $fdisplay(statf, "h %0d", H);

        repeat (6) @(posedge clk);
        rst_n <= 1'b1;
        repeat (6) @(posedge clk);

        case (mode)
            0: begin
                run_phase(1, in1, out1, pa, pr, 0, 0, 0, 1);
            end
            1: begin
                bp_mode = 0;
                run_phase(1, in1, out1, pa, pr, abort_at, 0, 0, 0);
                $fdisplay(statf, "p1_abort_lvl %0d", frame_abort);
                repeat (10) @(posedge clk);
                run_phase(2, in2, out2, pa2, pr2, 0, 0, 0, 1);
            end
            2: begin
                bp_mode = 0;
                run_phase(1, in1, out1, pa, pr, 0, rst_at, 0, 0);
                $fdisplay(statf, "p1_abort_lvl %0d", frame_abort);
                repeat (10) @(posedge clk);
                run_phase(2, in2, out2, pa2, pr2, 0, 0, 0, 1);
            end
            3: begin
                bp_mode = 0;
                run_phase(1, in1, out1, pa, pr, 0, 0, proto_at, 0);
                $fdisplay(statf, "p1_abort_lvl %0d", frame_abort);
                repeat (10) @(posedge clk);
                run_phase(2, in2, out2, pa2, pr2, 0, 0, 0, 1);
            end
            4: begin
                bp_mode = 2;
                rel = 1'b0;
                run_phase(1, in1, out1, pa, pr, abort_at, 0, 0, 0);
                // the pending output word must still be presented and stable
                stall_ok = out_valid;
                repeat (25) @(posedge clk);
                if (!out_valid) stall_ok = 0;
                $fdisplay(statf, "p1_pending_after_abort %0d", stall_ok);
                rel = 1'b1;
                repeat (200) @(posedge clk);
                $fdisplay(statf, "p1_commit_after_release %0d", commit_cnt);
                $fdisplay(statf, "p1_last_after_release %0d", last_cnt);
                bp_mode = 0;
                repeat (10) @(posedge clk);
                run_phase(2, in2, out2, pa2, pr2, 0, 0, 0, 1);
            end
            6: begin
                bp_mode = 0;
                run_multi(multi_nframes, in1, out1, pa, pr);
            end
            7: begin
                bp_mode = 0;
                run_phase(1, in1, out1, pa, pr, 0, 0, 0, 1);
                commit_cnt = 0; last_cnt = 0; last_any = 0; abort_seen = 0;
                bp_mode = 3;
                drive_all(in1, pa, pr);
                tmo2 = 0;
                while (!(out_valid && out_last) && (tmo2 < 2000000)) begin
                    @(posedge clk); tmo2 = tmo2 + 1;
                end
                $fdisplay(statf, "p2_pending_last %0d", (out_valid && out_last));
                @(negedge clk); abort <= 1'b1;
                repeat (3) @(negedge clk);
                abort <= 1'b0;
                repeat (5) @(posedge clk);
                $fdisplay(statf, "p2_last_after_abort %0d", out_last);
                $fdisplay(statf, "p2_valid_after_abort %0d", out_valid);
                $fdisplay(statf, "p2_abort_lvl %0d", frame_abort);
                $fdisplay(statf, "p2_commit_after_abort %0d", commit_cnt);
                bp_mode = 0;
                repeat (50) @(posedge clk);
                $fdisplay(statf, "p2_last_after_release %0d", last_any);
                $fdisplay(statf, "p2_commit_after_release %0d", commit_cnt);
                $fdisplay(statf, "p2_valid_after_release %0d", out_valid);
                run_phase(3, in2, out2, pa2, pr2, 0, 0, 0, 1);
            end
            8: begin
                bp_mode = 0;
                commit_cnt = 0; abort_seen = 0;
                prep_en = (pa != 0); pred_en = (pr != 0);
                drive_first(in1);
                repeat (20) @(posedge clk);
                $fdisplay(statf, "p1_abort_lvl %0d", frame_abort);
                $fdisplay(statf, "p1_commit %0d", commit_cnt);
                $fdisplay(statf, "p1_busy %0d", st_busy);
                rst_n <= 1'b0; repeat (4) @(posedge clk); rst_n <= 1'b1;
                repeat (6) @(posedge clk);
                $fdisplay(statf, "after_rst_abort %0d", frame_abort);
                commit_cnt = 0; abort_seen = 0;
                drive_first(in1);
                repeat (20) @(posedge clk);
                $fdisplay(statf, "p2_abort_lvl %0d", frame_abort);
                $fdisplay(statf, "p2_commit %0d", commit_cnt);
            end
            9: begin
                bp_mode = 0;
                commit_cnt = 0; abort_seen = 0;
                prep_en = (pa != 0); pred_en = (pr != 0);
                drive_first(in1);
                repeat (20) @(posedge clk);
                $fdisplay(statf, "p1_abort_lvl %0d", frame_abort);
                $fdisplay(statf, "p1_commit %0d", commit_cnt);
                rst_n <= 1'b0; repeat (4) @(posedge clk); rst_n <= 1'b1;
                repeat (6) @(posedge clk);
                run_phase(2, in2, out2, pa2, pr2, 0, 0, 0, 1);
            end
            default: begin
                bp_mode = 1;
                run_phase(1, in1, out1, pa, pr, 0, 0, 0, 1);
                bp_mode = 0;
            end
        endcase

        $fdisplay(statf, "errs %0d", errs);
        $fclose(statf);
        $finish;
    end

    initial begin
        #2000000000;
        $display("GLOBAL_TIMEOUT");
        $finish;
    end

endmodule

