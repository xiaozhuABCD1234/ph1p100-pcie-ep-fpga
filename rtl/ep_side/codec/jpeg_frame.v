// jpeg_frame.v — 完整 JPEG 灰度编码器（行扫描像素 → JPEG 熵编码码流）
//
//   line2block（8 行缓冲）→ dct2d8 → jpeg_quant_zz → jpeg_huff_enc
//
// 输入是相机灰度帧的行扫描流（4 像素/拍），输出是整帧的 JPEG 熵编码比特流。
// 码流前可加 SOI/DQT/SOF0/DHT/SOS 头就是标准 JPEG 文件，这部分留给主机或用
// 上面的固定头模板拼（头是常量，不必占用 FPGA 逻辑）。
module jpeg_frame #(
    parameter integer W = 1920
)(
    input  wire         clk,
    input  wire         rst_n,
    // 像素输入
    input  wire [31:0]  s_data,
    input  wire         s_valid,
    output wire         s_ready,
    input  wire         s_eol,
    input  wire         s_eof,
    // 码流输出
    output wire [7:0]   m_data,
    output wire         m_valid,
    input  wire         m_ready,
    output wire [31:0]  st_blocks
);
    // ---------------- 行转块 ----------------
    wire [31:0] bx_d;
    wire        bx_v, bx_sof, bx_eof;
    wire        bx_r;

    line2block #(.W(W)) u_l2b (
        .clk(clk), .rst_n(rst_n),
        .s_data(s_data), .s_valid(s_valid), .s_ready(s_ready),
        .s_eol(s_eol), .s_eof(s_eof),
        .m_data(bx_d), .m_valid(bx_v), .m_ready(bx_r),
        .m_sof(bx_sof), .m_eof(bx_eof));

    // ---------------- 块级 JPEG 编码 ----------------
    jpeg_enc u_enc (
        .clk(clk), .rst_n(rst_n),
        .s_data(bx_d), .s_valid(bx_v), .s_ready(bx_r),
        .s_sof(bx_sof), .s_eof(bx_eof),
        .m_data(m_data), .m_valid(m_valid), .m_ready(m_ready),
        .st_blocks(st_blocks));

endmodule
