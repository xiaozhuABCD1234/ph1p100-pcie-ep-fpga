// dct1d8.v — 8 点 1D DCT（JPEG 前向），全展开常数乘法，两级流水
//
// 系数 M[u][x] = 0.5*C(u)*cos((2x+1)u*pi/16)，Q12 定点（C(0)=1/sqrt2）。
// 二维 DCT 用本模块做两次：第一遍 IW=9 吃像素，第二遍 IW=12 吃中间结果。
//
// 两级流水：第 1 拍寄存 64 个乘积（落在 DSP 内部），第 2 拍做加法树 + 右移。
// 一级组合做完时实测 11.9 ns（预算 10 ns）收敛不了，必须拆。
module dct1d8 #(
    parameter integer IW = 9
)(
    input  wire                clk,
    input  wire                rst_n,
    input  wire [8*IW-1:0]     x,
    input  wire                start,
    output reg  [127:0]        y,
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

    // ---- 第 1 级：乘积（综合到 DSP，自带输出寄存器）----
    wire signed [IW+11:0] p0_0 = c0_0 * x0;
    wire signed [IW+11:0] p0_1 = c0_1 * x1;
    wire signed [IW+11:0] p0_2 = c0_2 * x2;
    wire signed [IW+11:0] p0_3 = c0_3 * x3;
    wire signed [IW+11:0] p0_4 = c0_4 * x4;
    wire signed [IW+11:0] p0_5 = c0_5 * x5;
    wire signed [IW+11:0] p0_6 = c0_6 * x6;
    wire signed [IW+11:0] p0_7 = c0_7 * x7;
    wire signed [IW+11:0] p1_0 = c1_0 * x0;
    wire signed [IW+11:0] p1_1 = c1_1 * x1;
    wire signed [IW+11:0] p1_2 = c1_2 * x2;
    wire signed [IW+11:0] p1_3 = c1_3 * x3;
    wire signed [IW+11:0] p1_4 = c1_4 * x4;
    wire signed [IW+11:0] p1_5 = c1_5 * x5;
    wire signed [IW+11:0] p1_6 = c1_6 * x6;
    wire signed [IW+11:0] p1_7 = c1_7 * x7;
    wire signed [IW+11:0] p2_0 = c2_0 * x0;
    wire signed [IW+11:0] p2_1 = c2_1 * x1;
    wire signed [IW+11:0] p2_2 = c2_2 * x2;
    wire signed [IW+11:0] p2_3 = c2_3 * x3;
    wire signed [IW+11:0] p2_4 = c2_4 * x4;
    wire signed [IW+11:0] p2_5 = c2_5 * x5;
    wire signed [IW+11:0] p2_6 = c2_6 * x6;
    wire signed [IW+11:0] p2_7 = c2_7 * x7;
    wire signed [IW+11:0] p3_0 = c3_0 * x0;
    wire signed [IW+11:0] p3_1 = c3_1 * x1;
    wire signed [IW+11:0] p3_2 = c3_2 * x2;
    wire signed [IW+11:0] p3_3 = c3_3 * x3;
    wire signed [IW+11:0] p3_4 = c3_4 * x4;
    wire signed [IW+11:0] p3_5 = c3_5 * x5;
    wire signed [IW+11:0] p3_6 = c3_6 * x6;
    wire signed [IW+11:0] p3_7 = c3_7 * x7;
    wire signed [IW+11:0] p4_0 = c4_0 * x0;
    wire signed [IW+11:0] p4_1 = c4_1 * x1;
    wire signed [IW+11:0] p4_2 = c4_2 * x2;
    wire signed [IW+11:0] p4_3 = c4_3 * x3;
    wire signed [IW+11:0] p4_4 = c4_4 * x4;
    wire signed [IW+11:0] p4_5 = c4_5 * x5;
    wire signed [IW+11:0] p4_6 = c4_6 * x6;
    wire signed [IW+11:0] p4_7 = c4_7 * x7;
    wire signed [IW+11:0] p5_0 = c5_0 * x0;
    wire signed [IW+11:0] p5_1 = c5_1 * x1;
    wire signed [IW+11:0] p5_2 = c5_2 * x2;
    wire signed [IW+11:0] p5_3 = c5_3 * x3;
    wire signed [IW+11:0] p5_4 = c5_4 * x4;
    wire signed [IW+11:0] p5_5 = c5_5 * x5;
    wire signed [IW+11:0] p5_6 = c5_6 * x6;
    wire signed [IW+11:0] p5_7 = c5_7 * x7;
    wire signed [IW+11:0] p6_0 = c6_0 * x0;
    wire signed [IW+11:0] p6_1 = c6_1 * x1;
    wire signed [IW+11:0] p6_2 = c6_2 * x2;
    wire signed [IW+11:0] p6_3 = c6_3 * x3;
    wire signed [IW+11:0] p6_4 = c6_4 * x4;
    wire signed [IW+11:0] p6_5 = c6_5 * x5;
    wire signed [IW+11:0] p6_6 = c6_6 * x6;
    wire signed [IW+11:0] p6_7 = c6_7 * x7;
    wire signed [IW+11:0] p7_0 = c7_0 * x0;
    wire signed [IW+11:0] p7_1 = c7_1 * x1;
    wire signed [IW+11:0] p7_2 = c7_2 * x2;
    wire signed [IW+11:0] p7_3 = c7_3 * x3;
    wire signed [IW+11:0] p7_4 = c7_4 * x4;
    wire signed [IW+11:0] p7_5 = c7_5 * x5;
    wire signed [IW+11:0] p7_6 = c7_6 * x6;
    wire signed [IW+11:0] p7_7 = c7_7 * x7;

    reg signed [IW+11:0] p0r [0:7];
    reg signed [IW+11:0] p1r [0:7];
    reg signed [IW+11:0] p2r [0:7];
    reg signed [IW+11:0] p3r [0:7];
    reg signed [IW+11:0] p4r [0:7];
    reg signed [IW+11:0] p5r [0:7];
    reg signed [IW+11:0] p6r [0:7];
    reg signed [IW+11:0] p7r [0:7];

    // ---- 第 2 级：加法树 + 右移 ----
    wire signed [IW+12:0] a00 = p0r[0] + p0r[1];
    wire signed [IW+12:0] a01 = p0r[2] + p0r[3];
    wire signed [IW+12:0] a02 = p0r[4] + p0r[5];
    wire signed [IW+12:0] a03 = p0r[6] + p0r[7];
    wire signed [IW+13:0] b00 = a00 + a01;
    wire signed [IW+13:0] b01 = a02 + a03;
    wire signed [IW+14:0] s0  = b00 + b01;   // 平衡树：3 级而不是 7 级
    wire signed [15:0] y0 = s0 >>> FRAC;
    wire signed [IW+12:0] a10 = p1r[0] + p1r[1];
    wire signed [IW+12:0] a11 = p1r[2] + p1r[3];
    wire signed [IW+12:0] a12 = p1r[4] + p1r[5];
    wire signed [IW+12:0] a13 = p1r[6] + p1r[7];
    wire signed [IW+13:0] b10 = a10 + a11;
    wire signed [IW+13:0] b11 = a12 + a13;
    wire signed [IW+14:0] s1  = b10 + b11;   // 平衡树：3 级而不是 7 级
    wire signed [15:0] y1 = s1 >>> FRAC;
    wire signed [IW+12:0] a20 = p2r[0] + p2r[1];
    wire signed [IW+12:0] a21 = p2r[2] + p2r[3];
    wire signed [IW+12:0] a22 = p2r[4] + p2r[5];
    wire signed [IW+12:0] a23 = p2r[6] + p2r[7];
    wire signed [IW+13:0] b20 = a20 + a21;
    wire signed [IW+13:0] b21 = a22 + a23;
    wire signed [IW+14:0] s2  = b20 + b21;   // 平衡树：3 级而不是 7 级
    wire signed [15:0] y2 = s2 >>> FRAC;
    wire signed [IW+12:0] a30 = p3r[0] + p3r[1];
    wire signed [IW+12:0] a31 = p3r[2] + p3r[3];
    wire signed [IW+12:0] a32 = p3r[4] + p3r[5];
    wire signed [IW+12:0] a33 = p3r[6] + p3r[7];
    wire signed [IW+13:0] b30 = a30 + a31;
    wire signed [IW+13:0] b31 = a32 + a33;
    wire signed [IW+14:0] s3  = b30 + b31;   // 平衡树：3 级而不是 7 级
    wire signed [15:0] y3 = s3 >>> FRAC;
    wire signed [IW+12:0] a40 = p4r[0] + p4r[1];
    wire signed [IW+12:0] a41 = p4r[2] + p4r[3];
    wire signed [IW+12:0] a42 = p4r[4] + p4r[5];
    wire signed [IW+12:0] a43 = p4r[6] + p4r[7];
    wire signed [IW+13:0] b40 = a40 + a41;
    wire signed [IW+13:0] b41 = a42 + a43;
    wire signed [IW+14:0] s4  = b40 + b41;   // 平衡树：3 级而不是 7 级
    wire signed [15:0] y4 = s4 >>> FRAC;
    wire signed [IW+12:0] a50 = p5r[0] + p5r[1];
    wire signed [IW+12:0] a51 = p5r[2] + p5r[3];
    wire signed [IW+12:0] a52 = p5r[4] + p5r[5];
    wire signed [IW+12:0] a53 = p5r[6] + p5r[7];
    wire signed [IW+13:0] b50 = a50 + a51;
    wire signed [IW+13:0] b51 = a52 + a53;
    wire signed [IW+14:0] s5  = b50 + b51;   // 平衡树：3 级而不是 7 级
    wire signed [15:0] y5 = s5 >>> FRAC;
    wire signed [IW+12:0] a60 = p6r[0] + p6r[1];
    wire signed [IW+12:0] a61 = p6r[2] + p6r[3];
    wire signed [IW+12:0] a62 = p6r[4] + p6r[5];
    wire signed [IW+12:0] a63 = p6r[6] + p6r[7];
    wire signed [IW+13:0] b60 = a60 + a61;
    wire signed [IW+13:0] b61 = a62 + a63;
    wire signed [IW+14:0] s6  = b60 + b61;   // 平衡树：3 级而不是 7 级
    wire signed [15:0] y6 = s6 >>> FRAC;
    wire signed [IW+12:0] a70 = p7r[0] + p7r[1];
    wire signed [IW+12:0] a71 = p7r[2] + p7r[3];
    wire signed [IW+12:0] a72 = p7r[4] + p7r[5];
    wire signed [IW+12:0] a73 = p7r[6] + p7r[7];
    wire signed [IW+13:0] b70 = a70 + a71;
    wire signed [IW+13:0] b71 = a72 + a73;
    wire signed [IW+14:0] s7  = b70 + b71;   // 平衡树：3 级而不是 7 级
    wire signed [15:0] y7 = s7 >>> FRAC;

    integer k;
    reg d1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < 8; k = k + 1) begin
                p0r[k] <= 0; p1r[k] <= 0; p2r[k] <= 0; p3r[k] <= 0;
                p4r[k] <= 0; p5r[k] <= 0; p6r[k] <= 0; p7r[k] <= 0;
            end
            y <= 128'd0; done <= 1'b0; d1 <= 1'b0;
        end else begin
            d1 <= start;
            done <= d1;
            if (start) begin
                p0r[0]<=p0_0; p0r[1]<=p0_1; p0r[2]<=p0_2; p0r[3]<=p0_3;
                p0r[4]<=p0_4; p0r[5]<=p0_5; p0r[6]<=p0_6; p0r[7]<=p0_7;
                p1r[0]<=p1_0; p1r[1]<=p1_1; p1r[2]<=p1_2; p1r[3]<=p1_3;
                p1r[4]<=p1_4; p1r[5]<=p1_5; p1r[6]<=p1_6; p1r[7]<=p1_7;
                p2r[0]<=p2_0; p2r[1]<=p2_1; p2r[2]<=p2_2; p2r[3]<=p2_3;
                p2r[4]<=p2_4; p2r[5]<=p2_5; p2r[6]<=p2_6; p2r[7]<=p2_7;
                p3r[0]<=p3_0; p3r[1]<=p3_1; p3r[2]<=p3_2; p3r[3]<=p3_3;
                p3r[4]<=p3_4; p3r[5]<=p3_5; p3r[6]<=p3_6; p3r[7]<=p3_7;
                p4r[0]<=p4_0; p4r[1]<=p4_1; p4r[2]<=p4_2; p4r[3]<=p4_3;
                p4r[4]<=p4_4; p4r[5]<=p4_5; p4r[6]<=p4_6; p4r[7]<=p4_7;
                p5r[0]<=p5_0; p5r[1]<=p5_1; p5r[2]<=p5_2; p5r[3]<=p5_3;
                p5r[4]<=p5_4; p5r[5]<=p5_5; p5r[6]<=p5_6; p5r[7]<=p5_7;
                p6r[0]<=p6_0; p6r[1]<=p6_1; p6r[2]<=p6_2; p6r[3]<=p6_3;
                p6r[4]<=p6_4; p6r[5]<=p6_5; p6r[6]<=p6_6; p6r[7]<=p6_7;
                p7r[0]<=p7_0; p7r[1]<=p7_1; p7r[2]<=p7_2; p7r[3]<=p7_3;
                p7r[4]<=p7_4; p7r[5]<=p7_5; p7r[6]<=p7_6; p7r[7]<=p7_7;
            end
            if (d1) y <= {y7, y6, y5, y4, y3, y2, y1, y0};
        end
    end
endmodule
