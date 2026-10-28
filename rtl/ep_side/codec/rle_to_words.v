// rle_to_words.v — rle_enc 的字节流打包成 32bit 字给 codec_pack
// 每 4 字节出一个满字（keep=1111），帧尾不足 4 字节时用 keep 标出有效字节并给 c_last。
module rle_to_words (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  s_data,
    input  wire        s_valid,
    output wire        s_ready,
    input  wire        s_eof,          // 帧尾（由上游字节流带下来）
    output reg  [31:0] o_data,
    output reg         o_valid,
    output reg  [3:0]  o_keep,
    output reg         o_last,
    input  wire        o_ready
);
    reg [31:0] acc;
    reg [1:0]  n;
    reg        eof_seen;

    assign s_ready = (!o_valid || o_ready) && !eof_seen ? 1'b1 : 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc <= 0; n <= 0; o_valid <= 0; o_data <= 0; o_keep <= 0; o_last <= 0; eof_seen <= 0;
        end else begin
            if (o_valid && o_ready) o_valid <= 1'b0;
            if (s_eof) eof_seen <= 1'b1;   // 帧尾可能在无数据时到达

            if (!o_valid && (n != 0) && eof_seen) begin
                // 帧尾：把剩余不足 4 字节的字吐出去
                o_data  <= acc;
                o_keep  <= (n == 1) ? 4'b0001 : (n == 2) ? 4'b0011 : 4'b0111;
                o_last  <= 1'b1;
                o_valid <= 1'b1;
                acc <= 0; n <= 0; eof_seen <= 0;
            end else if (!o_valid && (n == 0) && eof_seen) begin
                // 正好整字结尾：补一个空字只带 last
                o_data <= 0; o_keep <= 4'b0000; o_last <= 1'b1; o_valid <= 1'b1;
                eof_seen <= 0;
            end else if (s_valid && s_ready && !o_valid) begin
                acc <= {acc[23:0], s_data};
                n   <= n + 1'b1;
                if (n == 2'd3) begin
                    o_data  <= {acc[23:0], s_data};
                    o_keep  <= 4'b1111;
                    o_last  <= s_eof;
                    o_valid <= 1'b1;
                    acc <= 0; n <= 0;
                    if (s_eof) eof_seen <= 0;
                end
            end
        end
    end
endmodule

