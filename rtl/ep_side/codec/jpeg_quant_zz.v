// jpeg_quant_zz.v — JPEG 量化 + 之字形扫描
//
// 收 64 个 DCT 系数（8 个/拍，自然顺序），量化后按之字形顺序输出（8 个/拍）。
// 量化用定点乘法：z = sign(c) * ((|c| * R + 2^(S-1)) >>> S)，R = round(2^S / q)。
// 这里的表是质量因子 q=50 的标准亮度表；换表即可做「动态码率」加分项。
//
// 三张表（量化值 64x8、倒数 64x17、之字形 64x6）都用变量下标读，综合成分布式 ROM。
module jpeg_quant_zz (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [127:0] s_data,     // 8 个 16bit 有符号系数/拍
    input  wire         s_valid,
    output wire         s_ready,
    input  wire         s_eof,      // 与最后 8 个系数同拍：本块是整帧最后一块
    output reg  [127:0] m_data,     // 8 个量化后的之字形系数/拍
    output reg          m_valid,
    input  wire         m_ready,
    output reg          m_sof,
    output reg          m_eof,      // 与 m_data 同拍：本块是整帧最后一块
    output reg  [31:0]  st_blocks   // 已处理块数（观测用）
);
    localparam integer S = 16;

    // 量化表（q=50 标准亮度表）
    reg [7:0] qtab [0:63];
    // 倒数表 R = round(2^S / q)
    reg [16:0] rtab [0:63];
    // 之字形表：ZZ[k] = 之字形第 k 个位置的自然下标
    reg [5:0] ztab [0:63];
    initial begin qtab[ 0]= 16; qtab[ 1]= 11; qtab[ 2]= 10; qtab[ 3]= 16;
                  qtab[ 4]= 24; qtab[ 5]= 40; qtab[ 6]= 51; qtab[ 7]= 61; end
    initial begin qtab[ 8]= 12; qtab[ 9]= 12; qtab[10]= 14; qtab[11]= 19;
                  qtab[12]= 26; qtab[13]= 58; qtab[14]= 60; qtab[15]= 55; end
    initial begin qtab[16]= 14; qtab[17]= 13; qtab[18]= 16; qtab[19]= 24;
                  qtab[20]= 40; qtab[21]= 57; qtab[22]= 69; qtab[23]= 56; end
    initial begin qtab[24]= 14; qtab[25]= 17; qtab[26]= 22; qtab[27]= 29;
                  qtab[28]= 51; qtab[29]= 87; qtab[30]= 80; qtab[31]= 62; end
    initial begin qtab[32]= 18; qtab[33]= 22; qtab[34]= 37; qtab[35]= 56;
                  qtab[36]= 68; qtab[37]=109; qtab[38]=103; qtab[39]= 77; end
    initial begin qtab[40]= 24; qtab[41]= 35; qtab[42]= 55; qtab[43]= 64;
                  qtab[44]= 81; qtab[45]=104; qtab[46]=113; qtab[47]= 92; end
    initial begin qtab[48]= 49; qtab[49]= 64; qtab[50]= 78; qtab[51]= 87;
                  qtab[52]=103; qtab[53]=121; qtab[54]=120; qtab[55]=101; end
    initial begin qtab[56]= 72; qtab[57]= 92; qtab[58]= 95; qtab[59]= 98;
                  qtab[60]=112; qtab[61]=100; qtab[62]=103; qtab[63]= 99; end
    initial begin rtab[ 0]=  4096; rtab[ 1]=  5958; rtab[ 2]=  6554; rtab[ 3]=  4096;
                  rtab[ 4]=  2731; rtab[ 5]=  1638; rtab[ 6]=  1285; rtab[ 7]=  1074; end
    initial begin rtab[ 8]=  5461; rtab[ 9]=  5461; rtab[10]=  4681; rtab[11]=  3449;
                  rtab[12]=  2521; rtab[13]=  1130; rtab[14]=  1092; rtab[15]=  1192; end
    initial begin rtab[16]=  4681; rtab[17]=  5041; rtab[18]=  4096; rtab[19]=  2731;
                  rtab[20]=  1638; rtab[21]=  1150; rtab[22]=   950; rtab[23]=  1170; end
    initial begin rtab[24]=  4681; rtab[25]=  3855; rtab[26]=  2979; rtab[27]=  2260;
                  rtab[28]=  1285; rtab[29]=   753; rtab[30]=   819; rtab[31]=  1057; end
    initial begin rtab[32]=  3641; rtab[33]=  2979; rtab[34]=  1771; rtab[35]=  1170;
                  rtab[36]=   964; rtab[37]=   601; rtab[38]=   636; rtab[39]=   851; end
    initial begin rtab[40]=  2731; rtab[41]=  1872; rtab[42]=  1192; rtab[43]=  1024;
                  rtab[44]=   809; rtab[45]=   630; rtab[46]=   580; rtab[47]=   712; end
    initial begin rtab[48]=  1337; rtab[49]=  1024; rtab[50]=   840; rtab[51]=   753;
                  rtab[52]=   636; rtab[53]=   542; rtab[54]=   546; rtab[55]=   649; end
    initial begin rtab[56]=   910; rtab[57]=   712; rtab[58]=   690; rtab[59]=   669;
                  rtab[60]=   585; rtab[61]=   655; rtab[62]=   636; rtab[63]=   662; end
    initial begin ztab[ 0]= 0; ztab[ 1]= 1; ztab[ 2]= 8; ztab[ 3]=16;
                  ztab[ 4]= 9; ztab[ 5]= 2; ztab[ 6]= 3; ztab[ 7]=10; end
    initial begin ztab[ 8]=17; ztab[ 9]=24; ztab[10]=32; ztab[11]=25;
                  ztab[12]=18; ztab[13]=11; ztab[14]= 4; ztab[15]= 5; end
    initial begin ztab[16]=12; ztab[17]=19; ztab[18]=26; ztab[19]=33;
                  ztab[20]=40; ztab[21]=48; ztab[22]=41; ztab[23]=34; end
    initial begin ztab[24]=27; ztab[25]=20; ztab[26]=13; ztab[27]= 6;
                  ztab[28]= 7; ztab[29]=14; ztab[30]=21; ztab[31]=28; end
    initial begin ztab[32]=35; ztab[33]=42; ztab[34]=49; ztab[35]=56;
                  ztab[36]=57; ztab[37]=50; ztab[38]=43; ztab[39]=36; end
    initial begin ztab[40]=29; ztab[41]=22; ztab[42]=15; ztab[43]=23;
                  ztab[44]=30; ztab[45]=37; ztab[46]=44; ztab[47]=51; end
    initial begin ztab[48]=58; ztab[49]=59; ztab[50]=52; ztab[51]=45;
                  ztab[52]=38; ztab[53]=31; ztab[54]=39; ztab[55]=46; end
    initial begin ztab[56]=53; ztab[57]=60; ztab[58]=61; ztab[59]=54;
                  ztab[60]=47; ztab[61]=55; ztab[62]=62; ztab[63]=63; end

    reg [15:0] cbuf [0:63];      // 量化后的系数，自然顺序
    reg [2:0]  wn, on;
    reg        ready_out;
    reg        eof_in_lat;       // 本块是否帧末块（收数时锁存，出数时随最后一拍给出）

    // ready_out=0 时才收数据。wn 到 7 的那一拍仍要能收（是第 8 个系数），
    // 所以不能用 wn != 7 判断。
    assign s_ready = !ready_out;

    // 定点量化：z = sign(c) * ((|c| * R + 2^(S-1)) >>> S)
    function signed [15:0] qz;
        input signed [15:0] c;
        input        [16:0] r;
        reg   signed [32:0] mag;
        begin
            mag = (c[15] ? -c : c) * $signed({1'b0, r});
            mag = (mag + (1 << (S-1))) >>> S;
            qz  = c[15] ? -mag[15:0] : mag[15:0];
        end
    endfunction

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wn <= 0; on <= 0; m_valid <= 0; m_data <= 0; m_sof <= 0; m_eof <= 0;
            ready_out <= 0; st_blocks <= 0; eof_in_lat <= 1'b0;
            for (i = 0; i < 64; i = i + 1) cbuf[i] <= 0;
        end else begin
            if (m_valid && m_ready) m_valid <= 1'b0;

            // 收 8 拍系数并量化
            if (s_valid && s_ready) begin
                for (i = 0; i < 8; i = i + 1)
                    cbuf[wn*8 + i] <= qz(s_data[i*16 +: 16], rtab[wn*8 + i]);
                if (wn == 3'd7) begin
                    wn <= 0; ready_out <= 1'b1; on <= 0;
                    // 帧末标记跟着系数一起进流水线，出数时再随最后一拍还给下游
                    eof_in_lat <= s_eof;
                end
                else wn <= wn + 3'd1;
            end

            // 之字形输出 8 拍
            if (ready_out && (!m_valid || m_ready)) begin
                for (i = 0; i < 8; i = i + 1)
                    m_data[i*16 +: 16] <= cbuf[ztab[on*8 + i]];
                m_valid <= 1'b1;
                m_sof   <= (on == 3'd0);
                m_eof   <= eof_in_lat && (on == 3'd7);
                if (on == 3'd7) begin
                    ready_out <= 1'b0;
                    st_blocks <= st_blocks + 32'd1;
                end else on <= on + 3'd1;
            end
        end
    end
endmodule
