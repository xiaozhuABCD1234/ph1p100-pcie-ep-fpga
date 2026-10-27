// =============================================================================
// tb_adapter_directed.v -- T10.ah-honly r1 directed adapter test (TB only)
//
// Instantiates the REAL a1_frame_top (r0 frozen H candidate, W=8/H=8) and
// replaces only its internal core output nets with a TB byte source
// (force/release on the core->frame_top nets).  The adapter, sdata/skeep/slast,
// slen, stream_crc and the 32-bit word packing are the real DUT logic.
//
// Directed cases: even/odd stream length, scnt=3+keep=1 (pending byte across
// the 32-bit word boundary), output backpressure with a held pending byte, and
// a 1-byte last transfer (out_last) at every scnt position 0..3.
// The expected words/keep/last are a direct little-endian 4-byte assembly of
// the source byte list (independent of the adapter implementation); the
// expected stream CRC is the standard reflected CRC32 (zlib) over the bytes.
// =============================================================================
`timescale 1ns / 1ps

module tb_adapter_directed;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;
    reg out_ready = 1'b1;

    // forced core->frame_top source
    reg        src_valid = 1'b0;
    reg [15:0] src_data  = 16'd0;
    reg        src_keep  = 1'b0;
    reg        src_last  = 1'b0;

    wire [31:0] out_data;
    wire        out_valid;
    wire [3:0]  out_keep;
    wire        out_last;
    wire        frame_commit, frame_abort;
    wire [31:0] st_stream_len, st_stream_crc;

    a1_frame_top #(.W(8), .H(8)) dut (
        .clk(clk), .rst_n(rst_n),
        .in_pix(40'd0), .in_valid(1'b0), .in_ready(), .in_sof(1'b0),
        .prep_en(1'b0), .pred_en(1'b0), .abort(1'b0),
        .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready),
        .out_keep(out_keep), .out_last(out_last),
        .frame_commit(frame_commit), .frame_abort(frame_abort),
        .st_raw_len(), .st_xform_len(), .st_stream_len(st_stream_len),
        .st_raw_crc(), .st_xform_crc(), .st_stream_crc(st_stream_crc),
        .st_blocks(), .st_stall_cycles(), .st_busy(), .dbg()
    );

    initial begin
        force dut.core_out_valid = src_valid;
        force dut.core_out_data  = src_data;
        force dut.core_out_keep  = src_keep;
        force dut.core_out_last  = src_last;
    end

    // ---------------------------------------------------------------- model
    reg [7:0] cbytes [0:63];
    integer   cgrp   [0:31];
    integer   cur_n = 0;
    integer   cap_idx = 0;
    integer   errs = 0;
    integer   cases = 0;
    integer   bp_mode = 0;
    integer   lfsr = 32'h1;
    integer   wait_cyc = 0;

    always @(negedge clk) begin
        lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
        case (bp_mode)
            0: out_ready <= 1'b1;
            1: out_ready <= lfsr[3];          // ~50 %, multi-cycle lows
            default: out_ready <= 1'b1;
        endcase
    end

    function [31:0] exp_word(input integer idx);
        integer j;
        reg [31:0] w;
        begin
            w = 32'd0;
            for (j = 0; j < 4; j = j + 1)
                if ((4*idx + j) < cur_n) w[8*j +: 8] = cbytes[4*idx + j];
            exp_word = w;
        end
    endfunction

    function [3:0] exp_keep(input integer idx);
        integer rem;
        begin
            rem = cur_n - 4*idx;
            if (rem >= 4) exp_keep = 4'hF;
            else          exp_keep = (4'd1 << rem) - 4'd1;
        end
    endfunction

    function exp_last(input integer idx);
        begin
            exp_last = (idx == ((cur_n + 3) / 4) - 1);
        end
    endfunction

    function [31:0] crc_std;
        integer i, k;
        reg [31:0] x;
        begin
            x = 32'hFFFFFFFF;
            for (i = 0; i < cur_n; i = i + 1) begin
                x = x ^ {24'd0, cbytes[i]};
                for (k = 0; k < 8; k = k + 1)
                    x = x[0] ? ((x >> 1) ^ 32'hEDB88320) : (x >> 1);
            end
            crc_std = ~x;
        end
    endfunction

    // captured output words are checked against the independent model.
    // Only bytes marked valid by out_keep are part of the external stream; the
    // frozen frame_top leaves unused sdata bytes at their previous value.
    integer bi;
    always @(posedge clk) begin
        if (rst_n && out_valid && out_ready) begin
            for (bi = 0; bi < 4; bi = bi + 1) begin
                if (out_keep[bi] && (out_data[8*bi +: 8] !== exp_word(cap_idx)[8*bi +: 8])) begin
                    $display("ADAPTER_FAIL case=%0d word=%0d byte=%0d data=%02x exp=%02x",
                             cases, cap_idx, bi, out_data[8*bi +: 8],
                             exp_word(cap_idx)[8*bi +: 8]);
                    errs = errs + 1;
                end
            end
            if (out_keep !== exp_keep(cap_idx)) begin
                $display("ADAPTER_FAIL case=%0d word=%0d keep=%x exp=%x",
                         cases, cap_idx, out_keep, exp_keep(cap_idx));
                errs = errs + 1;
            end
            if (out_last !== exp_last(cap_idx)) begin
                $display("ADAPTER_FAIL case=%0d word=%0d last=%b exp=%b",
                         cases, cap_idx, out_last, exp_last(cap_idx));
                errs = errs + 1;
            end
            cap_idx = cap_idx + 1;
        end
    end

    task run_case(input integer n, input integer ng, input integer bp);
        integer i, gsz, rem;
        begin
            cases = cases + 1;
            // data pattern is case-dependent but deterministic
            for (i = 0; i < n; i = i + 1)
                cbytes[i] = (i * 8'd37 + cases * 8'd11 + 8'h03) & 8'hFF;
            cur_n = n;
            cap_idx = 0;
            bp_mode = bp;
            rst_n = 1'b0;
            src_valid = 1'b0; src_data = 16'd0; src_keep = 1'b0; src_last = 1'b0;
            out_ready = 1'b1;
            repeat (6) @(posedge clk);
            rst_n = 1'b1;
            repeat (4) @(posedge clk);
            rem = n;
            for (i = 0; i < ng; i = i + 1) begin
                gsz = cgrp[i];
                @(negedge clk);
                src_data[7:0] = cbytes[n - rem];
                src_keep = (gsz == 2);
                if (gsz == 2) src_data[15:8] = cbytes[n - rem + 1];
                src_last = (gsz == rem);
                src_valid = 1'b1;
                while (!dut.core_out_ready) @(negedge clk);
                @(posedge clk);              // accepted here
                src_valid <= 1'b0;           // NBA: the DUT sees valid=1 at this edge
                rem = rem - gsz;
            end
            wait_cyc = 0;
            while ((cap_idx < ((n + 3) / 4)) && (wait_cyc < 3000)) begin
                @(posedge clk);
                wait_cyc = wait_cyc + 1;
            end
            repeat (3) @(posedge clk);
            if (cap_idx != ((n + 3) / 4)) begin
                $display("ADAPTER_FAIL case=%0d words=%0d exp=%0d",
                         cases, cap_idx, (n + 3) / 4);
                errs = errs + 1;
            end
            if (st_stream_len !== n) begin
                $display("ADAPTER_FAIL case=%0d slen=%0d exp=%0d", cases, st_stream_len, n);
                errs = errs + 1;
            end
            if (st_stream_crc !== crc_std) begin
                $display("ADAPTER_FAIL case=%0d crc=%08x exp=%08x cases=%0d",
                         cases, st_stream_crc, crc_std, cases);
                errs = errs + 1;
            end
            $display("ADAPTER_CASE case=%0d n=%0d groups=%0d bp=%0d words=%0d slen=%0d crc=%08x",
                     cases, n, ng, bp, cap_idx, st_stream_len, st_stream_crc);
        end
    endtask

    initial begin
        // n, #groups, backpressure mode
        cgrp[0]=2; cgrp[1]=2; cgrp[2]=2; cgrp[3]=1; cgrp[4]=1;
        run_case(8, 5, 0);          // even, last 1 B at scnt=3
        cgrp[0]=1; cgrp[1]=2; cgrp[2]=2; cgrp[3]=1; cgrp[4]=1; cgrp[5]=1;
        run_case(8, 6, 0);          // even, scnt=3+keep=1 pending, last 1 B
        cgrp[0]=2; cgrp[1]=2; cgrp[2]=1;
        run_case(5, 3, 0);          // odd, last 1 B at scnt=0
        cgrp[0]=2; cgrp[1]=1;
        run_case(3, 2, 0);          // odd, last 1 B at scnt=2, keep=3
        cgrp[0]=1;
        run_case(1, 1, 0);          // 1 B, keep=1
        cgrp[0]=1; cgrp[1]=1;
        run_case(2, 2, 0);          // last 1 B at scnt=1, keep=3
        cgrp[0]=1; cgrp[1]=2; cgrp[2]=1;
        run_case(4, 3, 0);          // full last word at scnt=3
        cgrp[0]=1; cgrp[1]=2; cgrp[2]=2; cgrp[3]=1; cgrp[4]=1;
        run_case(7, 5, 0);          // pending + keep=7
        cgrp[0]=1; cgrp[1]=2; cgrp[2]=2; cgrp[3]=2; cgrp[4]=1;
        run_case(8, 5, 1);          // pending held under backpressure
        cgrp[0]=1; cgrp[1]=2; cgrp[2]=1; cgrp[3]=2; cgrp[4]=2; cgrp[5]=1;
        cgrp[6]=1; cgrp[7]=1; cgrp[8]=1; cgrp[9]=1;
        run_case(13, 10, 1);        // multi-word + backpressure, keep=1
        cgrp[0]=2; cgrp[1]=2; cgrp[2]=1; cgrp[3]=1;
        run_case(6, 4, 0);          // 2 words, keep=3
        cgrp[0]=1; cgrp[1]=1; cgrp[2]=1; cgrp[3]=1; cgrp[4]=1;
        cgrp[5]=1; cgrp[6]=1; cgrp[7]=1; cgrp[8]=1;
        run_case(9, 9, 0);          // all 1-byte transfers
        repeat (5) @(posedge clk);
        release dut.core_out_valid;
        release dut.core_out_data;
        release dut.core_out_keep;
        release dut.core_out_last;
        if (errs == 0) $display("ADAPTER_PASS cases=%0d errors=0", cases);
        else           $display("ADAPTER_FAIL cases=%0d errors=%0d", cases, errs);
        $display("ADAPTER_RESULT pass=%0d", (errs == 0));
        $finish;
    end

    initial begin
        #500000;
        $display("ADAPTER_GLOBAL_TIMEOUT");
        $finish;
    end

endmodule
