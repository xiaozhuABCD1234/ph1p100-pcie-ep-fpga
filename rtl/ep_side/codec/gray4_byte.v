// gray4_byte.v — 32bit 四像素拍 → 8bit 字节流（给 rle_enc 用）
// 32bit 里 [7:0] 是第一个像素，按顺序吐出 4 个字节；sof/eof 标记跟着帧走。
module gray4_byte (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] s_data,
    input  wire        s_valid,
    output wire        s_ready,
    input  wire        s_sof,
    input  wire        s_eof,
    output reg  [7:0]  o_data,
    output reg         o_valid,
    input  wire        o_ready,
    output reg         o_sof,
    output reg         o_eof
);
    reg [1:0]  bi;
    reg [31:0] word;
    reg        busy;

    assign s_ready = !busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bi <= 0; word <= 0; busy <= 0; o_valid <= 0; o_data <= 0; o_sof <= 0; o_eof <= 0;
        end else begin
            if (o_valid && o_ready) o_valid <= 1'b0;
            if (!busy && s_valid && s_ready) begin
                word <= s_data;
                busy <= 1'b1;
                bi   <= 2'd0;
                o_sof <= s_sof;
                o_eof <= s_eof;      // 帧尾标记放到最后一个字节上
            end else if (busy && !o_valid) begin
                o_data  <= (word >> (bi * 8)) & 8'hFF;
                o_valid <= 1'b1;
                if (bi == 2'd3) begin busy <= 1'b0; o_sof <= 1'b0; end
                else bi <= bi + 1'b1;
            end
        end
    end
endmodule

