`timescale 1ns/1ps
// tb_frame_probe.v -- bounded probe of a1_frame_top + a1_deflate_core:
// scaled 64x48 frame, bypass prep/pred, capture the exact stream words/keep.
module tb_frame_probe;
    localparam integer W = 64;
    localparam integer H = 48;
    localparam integer NG = (W * H) / 4;   // 768 groups

    reg clk = 0, rst_n = 0;
    always #3.333 clk = ~clk;

    reg         PREP = 0, PRED = 0;
    initial begin if (!$value$plusargs("PREP=%d", PREP)) PREP = 0; if (!$value$plusargs("PRED=%d", PRED)) PRED = 0; $display("FPRB prep=%0d pred=%0d", PREP, PRED); end
    reg  [39:0] in_pix = 0;
    reg         in_valid = 0, in_sof = 0;
    wire        in_ready;
    wire [31:0] out_data;
    wire        out_valid;
    wire [3:0]  out_keep;
    wire        out_last;
    wire        out_ready = 1'b1;
    wire        frame_commit, frame_abort;
    wire [31:0] st_raw_len, st_xform_len, st_stream_len;
    wire [31:0] st_raw_crc, st_xform_crc, st_stream_crc;
    wire [31:0] st_blocks, st_stall;
    wire        st_busy;
    wire [31:0] dbg;

    a1_frame_top #(.W(W), .H(H)) u_f (
        .clk(clk), .rst_n(rst_n),
        .in_pix(in_pix), .in_valid(in_valid), .in_ready(in_ready), .in_sof(in_sof),
        .prep_en(PREP), .pred_en(PRED), .abort(1'b0),
        .out_data(out_data), .out_valid(out_valid), .out_ready(out_ready),
        .out_keep(out_keep), .out_last(out_last),
        .frame_commit(frame_commit), .frame_abort(frame_abort),
        .st_raw_len(st_raw_len), .st_xform_len(st_xform_len), .st_stream_len(st_stream_len),
        .st_raw_crc(st_raw_crc), .st_xform_crc(st_xform_crc), .st_stream_crc(st_stream_crc),
        .st_blocks(st_blocks), .st_stall_cycles(st_stall), .st_busy(st_busy), .dbg(dbg)
    );

    reg  [7:0] outp [0:65535];
    integer    ocnt = 0;
    integer    last_seen = 0;
    integer    i, b;
    integer    fd;

    always @(posedge clk) begin
        if (rst_n && out_valid) begin
            for (b = 0; b < 4; b = b + 1)
                if (out_keep[b]) begin
                    outp[ocnt] = out_data[8*b +: 8];
                    ocnt = ocnt + 1;
                end
            if (out_last) last_seen = 1;
        end
    end

    integer g;
    initial begin
        repeat (8) @(posedge clk);
        rst_n = 1;
        repeat (4) @(posedge clk);

        g = 0;
        @(negedge clk);
        in_valid = 1'b1;
        in_sof   = 1'b1;
        in_pix   = {4{10'h0A5}};   // 4 identical samples: any data
        while (g < NG) begin
            @(posedge clk);
            if (in_ready) begin
                g = g + 1;
                @(negedge clk);
                in_sof = 1'b0;
                if (g < NG) in_pix = {4{(10'h0A5 + g[9:0])}};
                else        in_valid = 1'b0;
            end
        end

        i = 0;
        while (!last_seen && (i < 2000000)) begin
            @(posedge clk); i = i + 1;
        end
        repeat (100) @(posedge clk);

        $display("FPRB words=%0d bytes=%0d raw=%0d xform=%0d stream=%0d blocks=%0d commit=%b abort=%b",
                 ocnt/4, ocnt, st_raw_len, st_xform_len, st_stream_len, st_blocks,
                 frame_commit, frame_abort);
        $display("FPRB tail8=%02h %02h %02h %02h %02h %02h %02h %02h",
                 outp[ocnt-8], outp[ocnt-7], outp[ocnt-6], outp[ocnt-5],
                 outp[ocnt-4], outp[ocnt-3], outp[ocnt-2], outp[ocnt-1]);
        fd = $fopen("frame_probe_stream.bin", "wb");
        for (i = 0; i < ocnt; i = i + 1) $fwrite(fd, "%c", outp[i]);
        $fclose(fd);
        $display("FPRB wrote frame_probe_stream.bin");
        $display("FPRB_DONE");
        $finish;
    end

    initial begin
        #5000000;
        $display("FPRB_DONE timeout ocnt=%0d", ocnt);
        $finish;
    end
endmodule

