// =============================================================================
// a1_eng_top.v - T10.a1-eng-freeze build-only wrapper (NOT a candidate RTL file)
// Purpose: a1_frame_top exposes 7 x 32-bit test-only status buses; as a chip-level
// top TD counts them as package IOs and rejects the build (max 286 IOs). This
// wrapper keeps the full DUT and folds all status buses into one 32-bit debug XOR,
// so the counters are not optimized away but the pin count stays legal.
// No functional logic is added or removed. Single clock: clk.
// =============================================================================
module a1_eng_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [39:0] in_pix,
    input  wire        in_valid,
    output wire        in_ready,
    input  wire        in_sof,
    input  wire        prep_en,
    input  wire        pred_en,
    input  wire        abort,
    output wire [31:0] out_data,
    output wire        out_valid,
    input  wire        out_ready,
    output wire [3:0]  out_keep,
    output wire        out_last,
    output wire        frame_commit,
    output wire        frame_abort,
    output wire [31:0] st_dbg
);

    wire [31:0] st_raw_len;
    wire [31:0] st_xform_len;
    wire [31:0] st_stream_len;
    wire [31:0] st_raw_crc;
    wire [31:0] st_xform_crc;
    wire [31:0] st_stream_crc;
    wire [31:0] st_blocks;
    wire [31:0] st_stall_cycles;
    wire        st_busy;

    assign st_dbg = st_raw_len ^ st_xform_len ^ st_stream_len ^ st_raw_crc ^
                    st_xform_crc ^ st_stream_crc ^ st_blocks ^ st_stall_cycles ^
                    {31'b0, st_busy};

    a1_frame_top #(
        .W (1920),
        .H (1080)
    ) u_dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .in_pix         (in_pix),
        .in_valid       (in_valid),
        .in_ready       (in_ready),
        .in_sof         (in_sof),
        .prep_en        (prep_en),
        .pred_en        (pred_en),
        .abort          (abort),
        .out_data       (out_data),
        .out_valid      (out_valid),
        .out_ready      (out_ready),
        .out_keep       (out_keep),
        .out_last       (out_last),
        .frame_commit   (frame_commit),
        .frame_abort    (frame_abort),
        .st_raw_len     (st_raw_len),
        .st_xform_len   (st_xform_len),
        .st_stream_len  (st_stream_len),
        .st_raw_crc     (st_raw_crc),
        .st_xform_crc   (st_xform_crc),
        .st_stream_crc  (st_stream_crc),
        .st_blocks      (st_blocks),
        .st_stall_cycles(st_stall_cycles),
        .st_busy        (st_busy)
    );

endmodule
