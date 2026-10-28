// rle_enc.v — 水平差分 + 零游程编码（无损）
//
// 与 tools/rle_codec.py 对齐（TB 回放对拍 + 主机解码校验）：
//   d[n] = (y[n] - y[n-1]) & 0xFF，帧首 y[-1] = 128
//   d == 0 的游程：0x00, N（N = 1..255，表示 N 个零）
//   d != 0 的字面量：直接输出该字节
//
// 为什么先做这个而不是完整 LZ77：完整 LZ77 的硬件状态机写了两版都没能跟参考实现
// 收敛（见 docs/CODEC.md「现状」），而这条链在真实去噪帧上就有 31% 压缩率。
// 先把它做对做实，再在同一数据通路上加长匹配单元。
module rle_enc (
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
    output reg  [31:0] st_out_bytes
);
    localparam S_IDLE = 2'd0, S_FL0 = 2'd1, S_FL1 = 2'd2, S_PL = 2'd3;

    reg [1:0]  st;
    reg [7:0]  prev_y;
    reg        have_prev;
    reg [7:0]  run;
    reg [7:0]  pend;          // 冲刷后要补发的字面量
    reg [1:0]  after;         // 冲完之后的动作：0 无、1 补字面量、2 新游程=1

    reg [7:0]  ofifo [0:15];
    reg [3:0]  owp, orp;
    wire [3:0] oused = owp - orp;
    wire       room = (oused < 12);

    assign in_ready = (st == S_IDLE) && room;

    wire [7:0] d = have_prev ? (in_data - prev_y) : (in_data - 8'd128);
    wire       push = room;                       // 输出 FIFO 有地方

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_y <= 0; have_prev <= 0; run <= 0; pend <= 0; after <= 0;
            owp <= 0; orp <= 0; out_valid <= 0; out_data <= 0; st <= S_IDLE;
            st_in_bytes <= 0; st_out_bytes <= 0;
        end else begin
            if (in_sof) have_prev <= 1'b0;

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
            S_IDLE: if (in_valid && in_ready) begin
                st_in_bytes <= st_in_bytes + 32'd1;
                prev_y <= in_data;
                have_prev <= 1'b1;
                if (d == 8'd0) begin
                    if (run == 8'd255) begin
                        after <= 2'd2;            // 冲完再从 1 起算
                        st <= S_FL0;
                    end else run <= run + 1'b1;
                end else begin
                    if (run != 8'd0) begin
                        pend  <= d;
                        after <= 2'd1;            // 冲完补发这个字面量
                        st <= S_FL0;
                    end else if (push) begin
                        ofifo[owp[3:0]] <= d;
                        owp <= owp + 1'b1;
                    end
                end
            end
            S_FL0: if (push) begin
                ofifo[owp[3:0]] <= 8'h00;
                owp <= owp + 1'b1;
                st <= S_FL1;
            end
            S_FL1: if (push) begin
                ofifo[owp[3:0]] <= run;
                owp <= owp + 1'b1;
                run <= 8'd0;
                if (after == 2'd1) st <= S_PL;
                else if (after == 2'd2) begin run <= 8'd1; after <= 2'd0; st <= S_IDLE; end
                else st <= S_IDLE;
            end
            S_PL: if (push) begin
                ofifo[owp[3:0]] <= pend;
                owp <= owp + 1'b1;
                after <= 2'd0;
                st <= S_IDLE;
            end
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule
