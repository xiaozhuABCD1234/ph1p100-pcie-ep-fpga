// lz77_enc.v — 流式 LZ77 编码器（差分 + 双字节哈希 + 前瞻匹配）
//
// 与 tools/lz77_codec.py 的参考实现**逐字节对齐**（tb_enc.v 用真实帧回放对拍）。
//
// 参考算法（每个位置 i）：
//   key  = (d[i], d[i+1])；cand = tab[key]；dist = i - cand
//   dist 合法 ⇒ 从 l=2 起比较 d[i+l] 与 win[cand+l]，最长 18；≥3 就发匹配并消费 l 字节
//   否则 d[i] 进字面量段，tab[key] = i
//   每消费一个字节都要更新该位置的 tab（参考实现如此，漏了会少匹配、压缩率变差）
//
// 结构：32 字节前瞻移位寄存器 → 决策/比较 → 消费 → token
//      窗口 2048×8、哈希 2048×11、字面量缓冲 128×8、输出 FIFO 16×8。
module lz77_enc #(
    parameter integer WIN    = 2048,
    parameter integer MAXLEN = 18,
    parameter integer LITBUF = 128
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  in_data,
    input  wire        in_valid,
    output wire        in_ready,
    input  wire        in_sof,
    input  wire        in_eof,
    output reg  [7:0]  out_data,
    output reg         out_valid,
    input  wire        out_ready,
    output reg  [31:0] st_in_bytes,
    output reg  [31:0] st_out_bytes,
    output reg  [31:0] st_matches
);
    localparam integer HAW = 11;
    localparam integer LAW = 7;
    localparam integer LALEN = 32;

    reg [7:0] la [0:LALEN-1];
    reg [5:0] lacnt;
    reg [7:0] la_prev;
    assign in_ready = (lacnt < LALEN - 4);

    // 变量下标直接写在这里（塞进 function 里 iverilog 会算出 X）
    wire [7:0] d0 = la[0] - la_prev;
    wire [7:0] d1 = la[1] - la[0];
    wire [7:0] dcmp = (ck == 0) ? d0 : (la[ck] - la[ck-1]);

    reg [7:0]     win  [0:WIN-1];
    reg [HAW-1:0] tab  [0:2047];
    reg [7:0]     lit  [0:LITBUF-1];
    reg [LAW:0]   litcnt;
    reg [HAW-1:0] wptr;
    reg           frame_open;

    reg [7:0]     ofifo [0:15];
    reg [3:0]     owp, orp;
    wire [3:0]    oused = owp - orp;

    wire [HAW-1:0] key0 = {d0[2:0], d1};

    localparam S_LOOK = 3'd0, S_CMP = 3'd1, S_CON = 3'd2, S_TOK = 3'd3;
    reg [2:0] st;
    reg [HAW-1:0] cand;
    reg [4:0]  mlen;
    reg [4:0]  ck;
    reg [7:0]  cmpb;
    reg [4:0]  cons_n;
    reg        cons_lit;
    reg [4:0]  mdist;
    reg [1:0]  tph;
    reg [7:0]  eidx;

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lacnt <= 0; la_prev <= 0; wptr <= 0; litcnt <= 0; frame_open <= 0;
            owp <= 0; orp <= 0; out_valid <= 0; out_data <= 0;
            st <= S_LOOK; cand <= 0; mlen <= 0; ck <= 0; cmpb <= 0;
            cons_n <= 0; cons_lit <= 0; mdist <= 0; tph <= 0; eidx <= 0;
            st_in_bytes <= 0; st_out_bytes <= 0; st_matches <= 0;
            for (i = 0; i < 2048; i = i + 1) tab[i] <= {HAW{1'b1}};
            for (i = 0; i < LALEN; i = i + 1) la[i] <= 0;
        end else begin
            if (in_valid && in_ready) begin
                la[lacnt[4:0]] <= in_data;
                lacnt <= lacnt + 1'b1;
                st_in_bytes <= st_in_bytes + 32'd1;
            end
            if (in_sof) frame_open <= 1'b1;

            if (out_valid && out_ready) begin
                out_valid <= 1'b0;
                st_out_bytes <= st_out_bytes + 32'd1;
            end
            if (!out_valid && (owp != orp)) begin
                out_data <= ofifo[orp[3:0]];
                out_valid <= 1'b1;
                orp <= orp + 1'b1;
            end

            case (st)
            S_LOOK: if (lacnt >= 2) begin
                if (tab[key0] != {HAW{1'b1}} && (wptr - tab[key0]) != 0 &&
                    (wptr - tab[key0]) <= WIN-1) begin
                    cand <= tab[key0];
                    mlen <= 5'd0;
                    ck   <= 5'd0;
                    cmpb <= win[tab[key0] & (WIN-1)];
                    st   <= S_CMP;
                end else begin
                    cons_n   <= 5'd1;
                    cons_lit <= 1'b1;
                    st       <= S_CON;
                end
            end
            S_CMP: begin
                if (ck < MAXLEN && ck < lacnt && cmpb == dcmp) begin
                    mlen <= mlen + 1'b1;
                    ck   <= ck + 1'b1;
                    cmpb <= win[(cand + ck + 1'b1) & (WIN-1)];
                end else if (mlen >= 3) begin
                    mdist  <= wptr - cand;
                    cons_n <= mlen;
                    cons_lit <= 1'b0;
                    st     <= S_TOK;
                end else begin
                    cons_n   <= 5'd1;
                    cons_lit <= 1'b1;
                    st       <= S_CON;
                end
            end
            S_CON: begin
                win[wptr] <= d0;
                if (lacnt >= 2) tab[key0] <= wptr;
                wptr <= wptr + 1'b1;
                la_prev <= la[0];
                for (i = 0; i < LALEN-1; i = i + 1) la[i] <= la[i+1];
                lacnt <= (lacnt == 0) ? 6'd0 : lacnt - 1'b1;
                if (cons_lit && litcnt < LITBUF) begin
                    lit[litcnt[LAW-1:0]] <= d0;
                    litcnt <= litcnt + 1'b1;
                end
                cons_n <= cons_n - 1'b1;
                if (cons_n == 1) st <= S_LOOK;
            end
            S_TOK: begin
                if (oused < 8) begin
                    case (tph)
                    2'd0: if (litcnt != 0) begin
                              ofifo[owp[3:0]] <= litcnt[7:0] - 8'd1;
                              owp <= owp + 1'b1;
                              eidx <= 0;
                              tph <= 2'd1;
                          end else tph <= 2'd2;
                    2'd1: if (eidx < litcnt) begin
                              ofifo[owp[3:0]] <= lit[eidx[LAW-1:0]];
                              owp <= owp + 1'b1;
                              eidx <= eidx + 1'b1;
                          end else begin
                              litcnt <= 0;
                              tph <= 2'd2;
                          end
                    2'd2: begin
                              ofifo[owp[3:0]] <= 8'h80 | (((cons_n - 5'd3) & 5'h0F) << 3) |
                                                 ((mdist >> 8) & 8'h07);
                              owp <= owp + 1'b1;
                              tph <= 2'd3;
                          end
                    default: begin
                              ofifo[owp[3:0]] <= mdist & 8'hFF;
                              owp <= owp + 1'b1;
                              tph <= 2'd0;
                              st  <= S_CON;
                          end
                    endcase
                end
            end
            default: st <= S_LOOK;
            endcase
        end
    end
endmodule
