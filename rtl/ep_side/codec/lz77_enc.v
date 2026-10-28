// lz77_enc.v — 流式 LZ77 编码器（差分 + 双字节哈希 + 前瞻窗口匹配）
//
// WIP: 回放对拍尚未通过（4096 字节输入：本模块 3870 / 参考实现 2733 字节）。未接顶层，勿上板。
// 与 tools/lz77_codec.py 严格对齐（TB 用真实帧回放逐字节对拍）：
//   d[n] = (y[n] - y[n-1]) & 0xFF，帧首 y[-1]=128
//   字面量段 0LLLLLLL（长度 = 值+1，1..128）+ 数据
//   匹配     1LLLLDDD（长度 = L+3，3..18；距离高 3 位）+ 1 字节距离低 8 位
//
// 结构：32 字节前瞻移位寄存器（够 18 字节匹配 + 2 字节 key）→ 决策 → 输出 FIFO
//      窗口 2048×8 存差分值；哈希 2048×11（key = {d0[2:0], d1}）；
//      字面量缓冲 128×8。
// 吞吐：字面量 1 拍/字节，匹配最多 (18 次窗口读 + 消费) ≈ 2 拍/字节。
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
    input  wire        in_eof,          // 帧尾：允许把剩余不足 19 字节的也编码完
    output reg  [7:0]  out_data,
    output reg         out_valid,
    input  wire        out_ready,
    output reg  [31:0] st_in_bytes,
    output reg  [31:0] st_out_bytes,
    output reg  [31:0] st_matches
);
    localparam integer HAW = 11;
    localparam integer LAW = 7;
    localparam integer LALEN = 32;     // 前瞻深度

    // ---------------- 前瞻移位寄存器 ----------------
    reg [7:0] la [0:LALEN-1];
    reg [5:0] lacnt;                   // 已填字节数
    reg [7:0] la_prev;                 // 相对于 la[0] 的「再前一个」字节（算差分用）

    assign in_ready = (lacnt < LALEN - 4);

    // la 内第 k 字节的差分值
    function [7:0] delt;
        input integer k;
        begin
            delt = (k == 0) ? (la[0] - la_prev) : (la[k] - la[k-1]);
        end
    endfunction

    // ---------------- 窗口 / 哈希 / 字面量 ----------------
    reg [7:0]     win [0:WIN-1];
    reg [HAW-1:0] tab [0:2047];
    reg [7:0]     lit [0:LITBUF-1];
    reg [LAW:0]   litcnt;
    reg [HAW-1:0] wptr;

    reg [7:0]     ofifo [0:15];
    reg [3:0]     owp, orp;
    wire [3:0]    oused = owp - orp;

    // ---------------- 状态机 ----------------
    localparam S_IDLE = 3'd0,   // 决策
               S_CMP  = 3'd1,   // 逐字节比较
               S_CON1 = 3'd2,   // 消费 1 字节（字面量）
               S_CONS = 3'd3,   // 消费 N 字节（匹配）
               S_EMIT = 3'd4;   // 发 token

    reg [2:0]  st;
    reg [HAW-1:0] cand;
    reg [4:0]  mlen;
    reg [4:0]  ck;
    reg [7:0]  cmpb;
    reg [4:0]  cons_n;
    reg [7:0]  litq;        // 待写窗口的差分值
    reg [1:0]  eph;         // 发送子相位
    reg [7:0]  ehdr;
    reg [7:0]  edist;
    reg [7:0]  ebyte;
    reg [7:0]  eidx;

    wire [7:0] d0 = delt(0);
    wire [7:0] d1 = delt(1);
    wire [HAW-1:0] key = {d0[2:0], d1};

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lacnt <= 0; la_prev <= 0; wptr <= 0; litcnt <= 0;
            owp <= 0; orp <= 0; out_valid <= 0; out_data <= 0;
            st <= S_IDLE; cand <= 0; mlen <= 0; ck <= 0; cmpb <= 0;
            cons_n <= 0; litq <= 0; eph <= 0; ehdr <= 0; edist <= 0; ebyte <= 0; eidx <= 0;
            st_in_bytes <= 0; st_out_bytes <= 0; st_matches <= 0;
            for (i = 0; i < 2048; i = i + 1) tab[i] <= {HAW{1'b1}};
            for (i = 0; i < LALEN; i = i + 1) la[i] <= 0;
        end else begin
            // ---- 输入进前瞻 ----
            if (in_valid && in_ready) begin
                la[lacnt[4:0]] <= in_data;
                lacnt <= lacnt + 1'b1;
                st_in_bytes <= st_in_bytes + 32'd1;
            end
            // ---- 输出 FIFO ----
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
            S_IDLE: if (lacnt >= MAXLEN + 2 || (lacnt >= 2 && in_eof)) begin
                if (tab[key] != {HAW{1'b1}} && (wptr - tab[key]) != 0 &&
                    (wptr - tab[key]) <= WIN-1 && lacnt >= 3) begin
                    cand <= tab[key];
                    mlen <= 5'd2;
                    ck   <= 5'd2;
                    cmpb <= win[(tab[key] + 5'd2) & (WIN-1)];
                    st   <= S_CMP;
                end else begin
                    st <= S_CON1;
                end
            end
            S_CMP: begin
                if (ck < MAXLEN && ck < lacnt && cmpb == delt(ck)) begin
                    mlen <= mlen + 1'b1;
                    ck   <= ck + 1'b1;
                    cmpb <= win[(cand + ck + 1'b1) & (WIN-1)];
                end else begin
                    st <= (mlen >= 3) ? S_CONS : S_CON1;
                end
            end
            S_CON1: begin
                // 消费 1 字节：写窗口 + 更新哈希 + 进字面量缓冲
                win[wptr] <= d0;
                tab[key]  <= wptr;
                wptr      <= wptr + 1'b1;
                la_prev   <= la[0];
                if (litcnt < LITBUF) begin
                    lit[litcnt[LAW-1:0]] <= d0;
                    litcnt <= litcnt + 1'b1;
                    mlen <= 0;
                    st <= S_IDLE;
                end else begin
                    eph <= 0; st <= S_EMIT;      // 段满，先发字面量段
                end
                for (i = 0; i < LALEN-1; i = i + 1) la[i] <= la[i+1];
                lacnt <= lacnt - 1'b1;
            end
            S_CONS: begin
                // 先发完字面量段（若有），再发匹配 token，然后消费 mlen 字节
                cons_n <= mlen;
                st <= S_EMIT;
            end
            S_EMIT: begin
                if (oused < 8) begin
                    case (eph)
                    2'd0: begin
                        if (litcnt != 0) begin
                            ofifo[owp[3:0]] <= litcnt[7:0] - 8'd1;
                            owp <= owp + 1'b1;
                            eidx <= 0;
                            eph <= 2'd1;
                        end else eph <= 2'd2;
                    end
                    2'd1: begin
                        if (eidx < litcnt) begin
                            ofifo[owp[3:0]] <= lit[eidx[LAW-1:0]];
                            owp <= owp + 1'b1;
                            eidx <= eidx + 1'b1;
                        end else begin
                            litcnt <= 0;
                            eph <= 2'd2;
                        end
                    end
                    2'd2: begin
                        if (cons_n >= 3) begin
                            ofifo[owp[3:0]] <= 8'h80 | (((cons_n - 5'd3) & 5'h0F) << 3) |
                                               ((edist >> 8) & 8'h07);
                            owp <= owp + 1'b1;
                            eph <= 2'd3;
                        end else begin
                            eph <= 3'd0;
                            mlen <= 0;
                            st <= S_IDLE;
                        end
                    end
                    2'd3: begin
                        ofifo[owp[3:0]] <= edist & 8'hFF;
                        owp <= owp + 1'b1;
                        eidx <= 0;
                        eph <= 2'd4;
                    end
                    default: begin
                        // 消费 cons_n 个字节：写窗口 + 更新哈希
                        if (eidx < cons_n) begin
                            win[wptr] <= delt(eidx[4:0]);
                            wptr <= wptr + 1'b1;
                            la_prev <= la[0];
                            for (i = 0; i < LALEN-1; i = i + 1) la[i] <= la[i+1];
                            lacnt <= lacnt - 1'b1;
                            eidx <= eidx + 1'b1;
                        end else begin
                            st_matches <= st_matches + 32'd1;
                            mlen <= 0;
                            eph <= 0;
                            st <= S_IDLE;
                        end
                    end
                    endcase
                    // 计算距离（token 发送时用）
                    edist <= (wptr - cand);
                end
            end
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule
