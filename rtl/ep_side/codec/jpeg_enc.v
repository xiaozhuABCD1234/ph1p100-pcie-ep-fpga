// jpeg_enc.v — JPEG 基线编码器单块流水线（DCT → 量化/之字形 → 熵编码）
//
// 输入：一个 8x8 块的 64 个像素（4 个/拍，第 1 拍带 sof，最后一拍带 eof）
// 输出：该块的 JPEG 熵编码比特流（字节）
//
// DCT 输出到量化器之间插了一级寄存器切片：DCT 的 8:1 输出选择 + 量化乘法
// 串在一拍里，是 100 MHz 下最紧的一条路径（板上 WNS -0.32 ns）。切片后
// 吞吐不变（每拍仍可过一组），只多一拍延迟。
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
    output wire [31:0]  st_blocks,
    output wire         m_done
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

    // ---------------- 一级半：DCT → 量化的寄存器切片 ----------------
    reg  [127:0] sl_d;
    reg          sl_v, sl_sof, sl_eof;
    wire         qz_s_ready;   // 量化器还能收
    wire         qz_m_ready;   // 熵编码器能收量化结果
    wire         sl_ready = !sl_v || qz_s_ready;

    assign dct_r = sl_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sl_v <= 1'b0; sl_d <= 128'd0; sl_sof <= 1'b0; sl_eof <= 1'b0;
        end else if (sl_ready) begin
            sl_v <= dct_v;
            if (dct_v) begin
                sl_d   <= dct_d;
                sl_sof <= dct_sof;
                sl_eof <= dct_eof;
            end
        end
    end

    // ---------------- 二级：量化 + 之字形 ----------------
    wire [127:0] qz_d;
    wire         qz_v, qz_sof, qz_eof;

    jpeg_quant_zz u_qz (
        .clk(clk), .rst_n(rst_n),
        .s_data(sl_d), .s_valid(sl_v), .s_ready(qz_s_ready), .s_eof(sl_eof),
        .m_data(qz_d), .m_valid(qz_v), .m_ready(qz_m_ready), .m_sof(qz_sof), .m_eof(qz_eof),
        .st_blocks());

    // ---------------- 三级：熵编码 ----------------
    jpeg_huff_enc u_huff (
        .clk(clk), .rst_n(rst_n),
        .s_data(qz_d), .s_valid(qz_v), .s_ready(qz_m_ready),
        .s_sof(qz_sof), .s_eof(qz_eof),
        .m_data(m_data), .m_valid(m_valid), .m_ready(m_ready),
        .st_bits(), .st_blocks(st_blocks), .m_done(m_done));

endmodule