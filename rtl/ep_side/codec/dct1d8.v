// dct1d8.v — 8 点 1D DCT（JPEG 前向），8 拍串行输出
//
// 系数 M[u][x] = 0.5*C(u)*cos((2x+1)u*pi/16)，Q12 定点（C(0)=1/sqrt2），
// 存在 64x12 的系数 ROM 里，按 u 逐个取。
//
// 为什么串行：64 个乘法全展开要 142 个 DSP、组合路径 11 ns 收敛不了。
// 改成每拍算一个 u（8 个乘法 + 3 级平衡加法树），8 拍出完 8 个系数。
// 一个 8x8 块两遍变换 = 8 行 x 8 拍 + 8 列 x 8 拍 = 128 拍，
// 1080p 一帧约 4.2M 拍（100MHz 下 42 ms），压缩不需要实时，够用。
module dct1d8 #(
    parameter integer IW = 9
)(
    input  wire                clk,
    input  wire                rst_n,
    input  wire [8*IW-1:0]     x,      // 8 个 IW 位有符号，8 拍内保持稳定
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

    // 系数 ROM：crom[u*8 + i]
    reg signed [11:0] crom [0:63];
    initial begin crom[0]=12'sd1448; crom[1]=12'sd1448; crom[2]=12'sd1448; crom[3]=12'sd1448;
                  crom[4]=12'sd1448; crom[5]=12'sd1448; crom[6]=12'sd1448; crom[7]=12'sd1448; end
    initial begin crom[8]=12'sd2009; crom[9]=12'sd1703; crom[10]=12'sd1138; crom[11]=12'sd400;
                  crom[12]=-12'sd400; crom[13]=-12'sd1138; crom[14]=-12'sd1703; crom[15]=-12'sd2009; end
    initial begin crom[16]=12'sd1892; crom[17]=12'sd784; crom[18]=-12'sd784; crom[19]=-12'sd1892;
                  crom[20]=-12'sd1892; crom[21]=-12'sd784; crom[22]=12'sd784; crom[23]=12'sd1892; end
    initial begin crom[24]=12'sd1703; crom[25]=-12'sd400; crom[26]=-12'sd2009; crom[27]=-12'sd1138;
                  crom[28]=12'sd1138; crom[29]=12'sd2009; crom[30]=12'sd400; crom[31]=-12'sd1703; end
    initial begin crom[32]=12'sd1448; crom[33]=-12'sd1448; crom[34]=-12'sd1448; crom[35]=12'sd1448;
                  crom[36]=12'sd1448; crom[37]=-12'sd1448; crom[38]=-12'sd1448; crom[39]=12'sd1448; end
    initial begin crom[40]=12'sd1138; crom[41]=-12'sd2009; crom[42]=12'sd400; crom[43]=12'sd1703;
                  crom[44]=-12'sd1703; crom[45]=-12'sd400; crom[46]=12'sd2009; crom[47]=-12'sd1138; end
    initial begin crom[48]=12'sd784; crom[49]=-12'sd1892; crom[50]=12'sd1892; crom[51]=-12'sd784;
                  crom[52]=-12'sd784; crom[53]=12'sd1892; crom[54]=-12'sd1892; crom[55]=12'sd784; end
    initial begin crom[56]=12'sd400; crom[57]=-12'sd1138; crom[58]=12'sd1703; crom[59]=-12'sd2009;
                  crom[60]=12'sd2009; crom[61]=-12'sd1703; crom[62]=12'sd1138; crom[63]=-12'sd400; end

    reg [2:0] ucnt;
    reg       busy;

    wire signed [11:0] cu0 = crom[ucnt*8 + 0];
    wire signed [11:0] cu1 = crom[ucnt*8 + 1];
    wire signed [11:0] cu2 = crom[ucnt*8 + 2];
    wire signed [11:0] cu3 = crom[ucnt*8 + 3];
    wire signed [11:0] cu4 = crom[ucnt*8 + 4];
    wire signed [11:0] cu5 = crom[ucnt*8 + 5];
    wire signed [11:0] cu6 = crom[ucnt*8 + 6];
    wire signed [11:0] cu7 = crom[ucnt*8 + 7];

    wire signed [IW+11:0] pp0 = cu0 * x0;
    wire signed [IW+11:0] pp1 = cu1 * x1;
    wire signed [IW+11:0] pp2 = cu2 * x2;
    wire signed [IW+11:0] pp3 = cu3 * x3;
    wire signed [IW+11:0] pp4 = cu4 * x4;
    wire signed [IW+11:0] pp5 = cu5 * x5;
    wire signed [IW+11:0] pp6 = cu6 * x6;
    wire signed [IW+11:0] pp7 = cu7 * x7;

    // 3 级平衡加法树（每拍只有一个 u 的 8 个乘积，路径很短）
    wire signed [IW+12:0] a0 = pp0 + pp1;
    wire signed [IW+12:0] a1 = pp2 + pp3;
    wire signed [IW+12:0] a2 = pp4 + pp5;
    wire signed [IW+12:0] a3 = pp6 + pp7;
    wire signed [IW+13:0] b0 = a0 + a1;
    wire signed [IW+13:0] b1 = a2 + a3;
    wire signed [IW+14:0] ss = b0 + b1;
    wire signed [15:0]    yv = ss >>> FRAC;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ucnt <= 3'd0; busy <= 1'b0; done <= 1'b0; y <= 128'd0;
        end else begin
            done <= 1'b0;
            if (start) begin
                ucnt <= 3'd0;
                busy <= 1'b1;
            end else if (busy) begin
                y[ucnt*16 +: 16] <= yv;
                if (ucnt == 3'd7) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end else ucnt <= ucnt + 3'd1;
            end
        end
    end
endmodule
