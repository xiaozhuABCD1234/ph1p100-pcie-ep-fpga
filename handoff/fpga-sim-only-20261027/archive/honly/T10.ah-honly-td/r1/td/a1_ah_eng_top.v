// =============================================================================
// a1_ah_eng_top.v - T10.ah-honly-td (Line B) build-only TD wrapper.
//
// NOT a candidate RTL file.  It is not part of the frozen H-only r1 candidate
// (a1_deflate_core.v / a1_frame_top.v) and must never be listed as a candidate
// in any manifest.  It exists only so that TD can build a block-level top.
//
// Why: a1_frame_top exposes eight 32-bit test-only status buses, st_busy and the
// H-only observation bus dbg[31:0].  A chip-level top would count every port as a
// package IO (device limit 286) and TD would reject the build.  This wrapper
// instantiates the frozen DUT unchanged (W=1920, H=1080) and folds every
// observation bus into one 32-bit XOR so the counters survive optimisation while
// the pin count stays legal.  The dispatch text mentioned "7 status buses"; the
// frozen a1_frame_top actually has 8 x 32-bit status buses + st_busy + dbg[31:0],
// and ALL of them are connected here, so no DUT output is left undriven.
//
// No functional logic added or removed.  No clock, reset, geometry or output
// semantics change.  Single clock domain: clk (187.5 MHz = 5.333 ns).
// =============================================================================
module a1_ah_eng_top (
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

    // folded observation: 8 x 32-bit status ^ st_busy ^ dbg[31:0]
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
    wire [31:0] dut_dbg;

    // Every observation output is consumed here: XOR keeps the counters alive
    // (no dead-code removal) and leaves exactly one 32-bit debug port.
    assign st_dbg = st_raw_len     ^ st_xform_len   ^ st_stream_len   ^
                    st_raw_crc     ^ st_xform_crc   ^ st_stream_crc   ^
                    st_blocks      ^ st_stall_cycles^ {31'b0, st_busy} ^
                    dut_dbg;

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
        .st_busy        (st_busy),
        .dbg            (dut_dbg)
    );

endmodule