// dct2d8.v — 8x8 二维 DCT（JPEG 前向）= 行 DCT → 转置 → 列 DCT
//
// 收 64 个像素（行优先，4 个/拍）后：先对每行做 dct1d8（IW=9，吃像素），
// 再对每列做一次（IW=12，吃 16bit 中间结果）。输出 64 个系数，8 个/拍。
//
// 一次变换约 40 拍；1080p 一帧 32,640 块 ≈ 1.3M 拍，100 MHz 下 13 ms/帧。
module dct2d8 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [31:0]  s_data,          // 4 像素/拍
    input  wire         s_valid,
    output wire         s_ready,
    input  wire         s_sof,           // 块边界对齐信号
    input  wire         s_eof,
    output reg  [127:0] m_data,          // 8 个系数/拍（16bit 有符号）
    output reg          m_valid,
    input  wire         m_ready,
    output reg          m_sof,
    output reg          m_eof
);
    localparam S_IDLE  = 4'd0, S_FILL  = 4'd1, S_ROWP = 4'd2, S_COLP  = 4'd3,
               S_WAIT  = 4'd4, S_WAIT2 = 4'd5, S_OUT  = 4'd6;
    reg [3:0]  st;
    reg [7:0]  blk [0:63];
    reg [15:0] tmp [0:63];      // 行 DCT 结果（按 y 分行）
    reg [15:0] out [0:63];      // 列 DCT 结果（按 v 分行）
    reg [5:0]  wn;
    reg [2:0]  idx, on;
    reg [71:0] dx;              // 第一遍：8 x 9bit
    reg [95:0] dx2;             // 第二遍：8 x 12bit
    reg        dstart, dstart2;
    reg        eof_lat;   // 本块是否帧末块（像素阶段的 eof 要带到输出）
    wire [127:0] dy, dy2;
    wire       ddone, ddone2;

    // S_IDLE 也要 ready：SOF 和第一组像素是同一拍到的，不能丢
    assign s_ready = ((st == S_FILL) || (st == S_IDLE)) && (m_ready || !m_valid);

    dct1d8 #(.IW(9)) u_dct_row (
        .clk(clk), .rst_n(rst_n), .x(dx), .start(dstart), .y(dy), .done(ddone));

    dct1d8 #(.IW(12)) u_dct_col (
        .clk(clk), .rst_n(rst_n), .x(dx2), .start(dstart2), .y(dy2), .done(ddone2));

    // 取第 r 行第 c 列像素并减 128（9bit 有符号；8bit 无符号的 0-128 会绕成 +128）
    function [8:0] pw;
        input [2:0] r;
        input [2:0] c;
        reg [8:0] v;
        begin
            v = {1'b0, blk[r*8 + c]};
            pw = v - 9'sd128;
        end
    endfunction

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; wn <= 0; idx <= 0; on <= 0; eof_lat <= 0;
            dx <= 0; dx2 <= 0; dstart <= 0; dstart2 <= 0;
            m_valid <= 0; m_data <= 0; m_sof <= 0; m_eof <= 0;
            for (k = 0; k < 64; k = k + 1) begin blk[k] <= 0; tmp[k] <= 0; out[k] <= 0; end
        end else begin
            dstart <= 1'b0; dstart2 <= 1'b0;
            if (m_valid && m_ready) m_valid <= 1'b0;

            case (st)
            S_IDLE: if (s_valid && s_sof && s_ready) begin
                blk[0] <= s_data[7:0];
                blk[1] <= s_data[15:8];
                blk[2] <= s_data[23:16];
                blk[3] <= s_data[31:24];
                wn <= 6'd4;
                st <= S_FILL;
            end

            S_FILL: if (s_valid && s_ready) begin
                blk[wn]        <= s_data[7:0];
                blk[wn + 6'd1] <= s_data[15:8];
                blk[wn + 6'd2] <= s_data[23:16];
                blk[wn + 6'd3] <= s_data[31:24];
                if (wn >= 6'd60) begin
                    eof_lat <= s_eof;
                    wn <= 0; idx <= 0; st <= S_ROWP;
                end
                else wn <= wn + 6'd4;
            end

            S_ROWP: begin
                dx <= { pw(idx,3'd7), pw(idx,3'd6), pw(idx,3'd5), pw(idx,3'd4),
                        pw(idx,3'd3), pw(idx,3'd2), pw(idx,3'd1), pw(idx,3'd0) };
                dstart <= 1'b1;
                st <= S_WAIT;
            end

            S_WAIT: if (ddone) begin
                for (k = 0; k < 8; k = k + 1) tmp[idx*8 + k] <= dy[k*16 +: 16];
                if (idx == 3'd7) begin idx <= 0; st <= S_COLP; end
                else begin idx <= idx + 3'd1; st <= S_ROWP; end
            end

            S_COLP: begin
                // tmp 是 16bit，但 dx2 只有 8x12bit。行 DCT 结果在 ±500 内，
                // 取低 12 位是安全的（直接拼 16bit 会被截掉高两路，列 pass 就全错）。
                dx2 <= { tmp[7*8+idx][11:0], tmp[6*8+idx][11:0], tmp[5*8+idx][11:0], tmp[4*8+idx][11:0],
                         tmp[3*8+idx][11:0], tmp[2*8+idx][11:0], tmp[1*8+idx][11:0], tmp[0*8+idx][11:0] };
                dstart2 <= 1'b1;
                st <= S_WAIT2;
            end

            S_WAIT2: if (ddone2) begin
                for (k = 0; k < 8; k = k + 1) out[k*8 + idx] <= dy2[k*16 +: 16];
                if (idx == 3'd7) begin on <= 0; st <= S_OUT; end
                else begin idx <= idx + 3'd1; st <= S_COLP; end
            end

            S_OUT: if (!m_valid || m_ready) begin
                m_data  <= { out[on*8+7], out[on*8+6], out[on*8+5], out[on*8+4],
                             out[on*8+3], out[on*8+2], out[on*8+1], out[on*8+0] };
                m_valid <= 1'b1;
                m_sof   <= (on == 3'd0);
                m_eof   <= (on == 3'd7) && eof_lat;
                if (on == 3'd7) begin
                    // 块是连续的：直接回去收下一块的 64 个像素，不用等 SOF
                    st <= S_FILL; wn <= 0;
                end
                else on <= on + 3'd1;
            end
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule
