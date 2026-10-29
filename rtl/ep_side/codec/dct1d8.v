// dct1d8.v — 8 点 1D DCT（JPEG 前向），全展开常数乘法
//
// 系数 M[u][x] = 0.5*C(u)*cos((2x+1)u*pi/16)，Q12 定点（C(0)=1/sqrt2）。
// 二维 DCT 用本模块做两次：第一遍 IW=9 吃像素，第二遍 IW=12 吃中间结果。
// 输出 8 个 16bit 有符号系数。64 个常数乘加全展开，1 拍出结果。
//
// 常数表来源：tools/gen_dct_coef.py（公式见文件头），不要手改。
module dct1d8 #(
    parameter integer IW = 9
)(
    input  wire                clk,
    input  wire                rst_n,
    input  wire [8*IW-1:0]     x,      // {x7..x0}，每个 IW 位有符号
    input  wire                start,
    output reg  [127:0]        y,      // {y7..y0}，每个 16bit 有符号
    output reg                 done
);
    localparam integer FRAC = 12;

    wire signed [IW-1:0] x0 = x[0*IW +: IW];
    wire signed [IW-1:0] x1 = x[1*IW +: IW];
    wire signed [IW-1:0] x2 = x[2*IW +: IW];
    wire signed [IW-1:0] x3 = x[3*IW +: IW];
    wire signed [IW-1:0] x4 = x[4*IW +: IW];
    wire signed [IW-1:0] x5 = x[5*IW +: IW];
    wire signed [IW-1:0] x6 = x[6*IW +: IW];
    wire signed [IW-1:0] x7 = x[7*IW +: IW];

    // 常数（Q12，12bit 有符号）
    wire signed [11:0] c0_0 = 12'sd1448;
    wire signed [11:0] c0_1 = 12'sd1448;
    wire signed [11:0] c0_2 = 12'sd1448;
    wire signed [11:0] c0_3 = 12'sd1448;
    wire signed [11:0] c0_4 = 12'sd1448;
    wire signed [11:0] c0_5 = 12'sd1448;
    wire signed [11:0] c0_6 = 12'sd1448;
    wire signed [11:0] c0_7 = 12'sd1448;
    wire signed [11:0] c1_0 = 12'sd2009;
    wire signed [11:0] c1_1 = 12'sd1703;
    wire signed [11:0] c1_2 = 12'sd1138;
    wire signed [11:0] c1_3 = 12'sd400;
    wire signed [11:0] c1_4 = -12'sd400;
    wire signed [11:0] c1_5 = -12'sd1138;
    wire signed [11:0] c1_6 = -12'sd1703;
    wire signed [11:0] c1_7 = -12'sd2009;
    wire signed [11:0] c2_0 = 12'sd1892;
    wire signed [11:0] c2_1 = 12'sd784;
    wire signed [11:0] c2_2 = -12'sd784;
    wire signed [11:0] c2_3 = -12'sd1892;
    wire signed [11:0] c2_4 = -12'sd1892;
    wire signed [11:0] c2_5 = -12'sd784;
    wire signed [11:0] c2_6 = 12'sd784;
    wire signed [11:0] c2_7 = 12'sd1892;
    wire signed [11:0] c3_0 = 12'sd1703;
    wire signed [11:0] c3_1 = -12'sd400;
    wire signed [11:0] c3_2 = -12'sd2009;
    wire signed [11:0] c3_3 = -12'sd1138;
    wire signed [11:0] c3_4 = 12'sd1138;
    wire signed [11:0] c3_5 = 12'sd2009;
    wire signed [11:0] c3_6 = 12'sd400;
    wire signed [11:0] c3_7 = -12'sd1703;
    wire signed [11:0] c4_0 = 12'sd1448;
    wire signed [11:0] c4_1 = -12'sd1448;
    wire signed [11:0] c4_2 = -12'sd1448;
    wire signed [11:0] c4_3 = 12'sd1448;
    wire signed [11:0] c4_4 = 12'sd1448;
    wire signed [11:0] c4_5 = -12'sd1448;
    wire signed [11:0] c4_6 = -12'sd1448;
    wire signed [11:0] c4_7 = 12'sd1448;
    wire signed [11:0] c5_0 = 12'sd1138;
    wire signed [11:0] c5_1 = -12'sd2009;
    wire signed [11:0] c5_2 = 12'sd400;
    wire signed [11:0] c5_3 = 12'sd1703;
    wire signed [11:0] c5_4 = -12'sd1703;
    wire signed [11:0] c5_5 = -12'sd400;
    wire signed [11:0] c5_6 = 12'sd2009;
    wire signed [11:0] c5_7 = -12'sd1138;
    wire signed [11:0] c6_0 = 12'sd784;
    wire signed [11:0] c6_1 = -12'sd1892;
    wire signed [11:0] c6_2 = 12'sd1892;
    wire signed [11:0] c6_3 = -12'sd784;
    wire signed [11:0] c6_4 = -12'sd784;
    wire signed [11:0] c6_5 = 12'sd1892;
    wire signed [11:0] c6_6 = -12'sd1892;
    wire signed [11:0] c6_7 = 12'sd784;
    wire signed [11:0] c7_0 = 12'sd400;
    wire signed [11:0] c7_1 = -12'sd1138;
    wire signed [11:0] c7_2 = 12'sd1703;
    wire signed [11:0] c7_3 = -12'sd2009;
    wire signed [11:0] c7_4 = 12'sd2009;
    wire signed [11:0] c7_5 = -12'sd1703;
    wire signed [11:0] c7_6 = 12'sd1138;
    wire signed [11:0] c7_7 = -12'sd400;

    // 每个 u 一路：8 个常数乘相加，右移 FRAC
    wire signed [IW+16:0] s0 = c0_0 * x0 + c0_1 * x1 + c0_2 * x2 + c0_3 * x3 + c0_4 * x4 + c0_5 * x5 + c0_6 * x6 + c0_7 * x7;
    wire signed [15:0]    y0 = s0 >>> FRAC;

    wire signed [IW+16:0] s1 = c1_0 * x0 + c1_1 * x1 + c1_2 * x2 + c1_3 * x3 + c1_4 * x4 + c1_5 * x5 + c1_6 * x6 + c1_7 * x7;
    wire signed [15:0]    y1 = s1 >>> FRAC;

    wire signed [IW+16:0] s2 = c2_0 * x0 + c2_1 * x1 + c2_2 * x2 + c2_3 * x3 + c2_4 * x4 + c2_5 * x5 + c2_6 * x6 + c2_7 * x7;
    wire signed [15:0]    y2 = s2 >>> FRAC;

    wire signed [IW+16:0] s3 = c3_0 * x0 + c3_1 * x1 + c3_2 * x2 + c3_3 * x3 + c3_4 * x4 + c3_5 * x5 + c3_6 * x6 + c3_7 * x7;
    wire signed [15:0]    y3 = s3 >>> FRAC;

    wire signed [IW+16:0] s4 = c4_0 * x0 + c4_1 * x1 + c4_2 * x2 + c4_3 * x3 + c4_4 * x4 + c4_5 * x5 + c4_6 * x6 + c4_7 * x7;
    wire signed [15:0]    y4 = s4 >>> FRAC;

    wire signed [IW+16:0] s5 = c5_0 * x0 + c5_1 * x1 + c5_2 * x2 + c5_3 * x3 + c5_4 * x4 + c5_5 * x5 + c5_6 * x6 + c5_7 * x7;
    wire signed [15:0]    y5 = s5 >>> FRAC;

    wire signed [IW+16:0] s6 = c6_0 * x0 + c6_1 * x1 + c6_2 * x2 + c6_3 * x3 + c6_4 * x4 + c6_5 * x5 + c6_6 * x6 + c6_7 * x7;
    wire signed [15:0]    y6 = s6 >>> FRAC;

    wire signed [IW+16:0] s7 = c7_0 * x0 + c7_1 * x1 + c7_2 * x2 + c7_3 * x3 + c7_4 * x4 + c7_5 * x5 + c7_6 * x6 + c7_7 * x7;
    wire signed [15:0]    y7 = s7 >>> FRAC;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y <= 128'd0; done <= 1'b0;
        end else begin
            done <= start;
            if (start) y <= {y7, y6, y5, y4, y3, y2, y1, y0};
        end
    end
endmodule
