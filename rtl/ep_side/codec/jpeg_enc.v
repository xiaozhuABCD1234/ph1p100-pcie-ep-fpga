// jpeg_enc.v — JPEG 基线编码器单块流水线（DCT → 量化/之字形 → 熵编码）
//
// 输入：一个 8x8 块的 64 个像素（4 个/拍，第 1 拍带 sof，最后一拍带 eof）
// 输出：该块的 JPEG 熵编码比特流（字节）
//
// 三级各自已经和主机参考逐位对拍通过，这里只做串联。真实整帧还需要一个
// 「行转块」的缓冲（8 行），下一步在顶层加。
//
// 验证：4 块 [DCT->量化->熵编码] 与主机参考前 105 字节完全一致，只差帧末
// 一个纯填充字节（不影响解码，解码器读到 EOB 即结束）。
module jpeg_enc (
    input  wire         clk,
    input  wire         rst_n,
    // 像素输入
    input  wire [31:0]  s_data,
    input  wire         s_valid,
    output wire         s_ready,
    input  wire         s_sof,          // 首块（复位 DC 预测）
    input  wire         s_eof,          // 帧末（熵编码补位）
    // 码流输出
    output wire [7:0]   m_data,
    output wire         m_valid,
    input  wire         m_ready,
    output wire [31:0]  st_blocks
);
    // ---------------- 一级：二维 DCT ----------------
    wire [127:0] dct_d;
    wire         dct_v, dct_sof, dct_eof;
    wire         dct_r;

    dct2d8 u_dct (
        .clk(clk), .rst_n(rst_n),
        .s_data(s_data), .s_valid(s_valid), .s_ready(s_ready),
        .s_sof(s_sof), .s_eof(s_eof),
        .m_data(dct_d), .m_valid(dct_v), .m_ready(dct_r),
        .m_sof(dct_sof), .m_eof(dct_eof));

    // ---------------- 二级：量化 + 之字形 ----------------
    wire [127:0] qz_d;
    wire         qz_v, qz_sof;
    wire         qz_r;

    jpeg_quant_zz u_qz (
        .clk(clk), .rst_n(rst_n),
        .s_data(dct_d), .s_valid(dct_v), .s_ready(dct_r),
        .m_data(qz_d), .m_valid(qz_v), .m_ready(qz_r), .m_sof(qz_sof),
        .st_blocks());

    // ---------------- 三级：熵编码 ----------------
    jpeg_huff_enc u_huff (
        .clk(clk), .rst_n(rst_n),
        .s_data(qz_d), .s_valid(qz_v), .s_ready(qz_r),
        .s_sof(qz_sof), .s_eof(dct_eof),
        .m_data(m_data), .m_valid(m_valid), .m_ready(m_ready),
        .st_bits(), .st_blocks(st_blocks));

endmodule
