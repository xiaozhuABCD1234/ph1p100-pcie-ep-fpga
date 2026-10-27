// raw10_sample_vector_to_packed.v — INT.P1 ROOT-01 correction.
// Converts a 4x10-bit RAW10 sample vector into the packed RAW10 byte stream
// required by A+ and other packed-RAW consumers.
//
// Input s_data is interpreted as four 10-bit samples:
//   s_data[9:0]   = P0, [19:10]=P1, [29:20]=P2, [39:30]=P3.
// Output p_data is the 5-byte packed word (40 bits), byte 0 in bits [7:0]:
//   byte0 = P0[9:2], byte1 = P1[9:2], byte2 = P2[9:2], byte3 = P3[9:2],
//   byte4 = {P3[1:0], P2[1:0], P1[1:0], P0[1:0]}.
// This is a pure combinational re-pack; no pixel value is altered.

module raw10_sample_vector_to_packed #(
    parameter DW = 40
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        s_valid,
    output wire        s_ready,
    input  wire [DW-1:0] s_data,
    input  wire        s_sof,
    input  wire        s_eol,
    input  wire        s_eof,
    input  wire        s_abort,
    input  wire        m_ready,
    output wire        m_valid,
    output wire [DW-1:0] m_data,
    output wire        m_sof,
    output wire        m_eol,
    output wire        m_eof,
    output wire        m_abort
);
    // ready/valid pass-through; combinational re-pack.
    assign s_ready = m_ready;
    assign m_valid = s_valid;
    assign m_sof   = s_sof;
    assign m_eol   = s_eol;
    assign m_eof   = s_eof;
    assign m_abort = s_abort;

    wire [9:0] p0 = s_data[9:0];
    wire [9:0] p1 = s_data[19:10];
    wire [9:0] p2 = s_data[29:20];
    wire [9:0] p3 = s_data[39:30];

    assign m_data = { p3[1:0], p2[1:0], p1[1:0], p0[1:0],  // byte4
                      p3[9:2],                                   // byte3
                      p2[9:2],                                   // byte2
                      p1[9:2],                                   // byte1
                      p0[9:2] };                                 // byte0
endmodule