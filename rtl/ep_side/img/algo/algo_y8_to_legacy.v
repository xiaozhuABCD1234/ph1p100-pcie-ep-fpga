// algo_y8_to_legacy.v — 把算法输出的「标记与数据同拍」流转换成 writer 要的
// 「标记独占拍 + 电平型帧/行」时序。
//
// 为什么需要它：img_algo_parallel_top 的 y8_/gau_/he_ 三路输出是 AXI-Stream 风格，
// sof/eol/eof 与对应的数据拍**同一拍**有效。而 cam_r10f_writer 的 cam 侧是
// 「if (sof_evt) ... else if (line_evt) ... else if (pix_valid)」的优先级链：
// 同拍有 sofs 时那个像素会被丢弃，行尾那一组同理 —— 直接接会每帧少若干组，
// 判据 gcnt 对不上，帧永远不发布。
//
// 所以这里做一次显式拆分：标记单独占一拍，数据只在自己的拍里出现。代价是每行
// 多 2~3 个周期，行周期 5700 周期（187.5MHz / 1088 行 / 30fps）里可以忽略。
//
// 8bit 灰度 → writer 的 40bit RAW10 组：每个采样放在 10bit 的高 8 位，
// writer 打包后主机侧 >>2 正好还原出原来的 8bit 值（10bit 就地无损运输）。
module algo_y8_to_legacy #(
    parameter integer FIFO_AW = 3
)(
    input  wire        clk,
    input  wire        rst_n,
    // 算法侧（AXI-Stream：valid/ready，标记与数据同拍）
    input  wire        s_valid,
    output wire        s_ready,
    input  wire [31:0] s_data,          // 4×8bit，[7:0] 是最左/第一个像素
    input  wire        s_sof,
    input  wire        s_eol,
    input  wire        s_eof,
    // writer 侧（标记独占拍）
    output reg         o_valid,
    output reg  [39:0] o_pix,
    output reg         o_vsync,
    output reg         o_frame,
    output reg         o_line
);
    localparam integer DEPTH = 1 << FIFO_AW;

    // 队列元素：{sof, eol, eof, data[31:0]}
    reg [34:0]  mem [0:DEPTH-1];
    reg [FIFO_AW:0] wp, rp;

    wire empty = (wp == rp);
    wire full  = ((wp - rp) == DEPTH);

    assign s_ready = ~full;

    reg [34:0] hold;
    reg        hold_v;
    reg        data_sent;

    wire        h_sof = hold[34];
    wire        h_eol = hold[33];
    wire        h_eof = hold[32];

    // 4×8bit → 4×RAW10（高 8 位放灰度值，低 2 位补 0）；P0 在最低 10 位
    function [39:0] pack4;
        input [31:0] d;
        begin
            pack4 = {d[31:24], 2'b00, d[23:16], 2'b00,
                     d[15:8],  2'b00, d[7:0],   2'b00};
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wp <= 0; rp <= 0;
            hold <= 35'd0; hold_v <= 1'b0; data_sent <= 1'b0;
            o_valid <= 1'b0; o_pix <= 40'd0;
            o_vsync <= 1'b0; o_frame <= 1'b0; o_line <= 1'b0;
        end else begin
            // 默认都是单拍脉冲；o_frame 是电平（要维持到 EOF）
            o_valid <= 1'b0;
            o_vsync <= 1'b0;
            o_line  <= 1'b0;

            if (s_valid && !full) begin
                mem[wp[FIFO_AW-1:0]] <= {s_sof, s_eol, s_eof, s_data};
                wp <= wp + 1'b1;
            end

            if (!hold_v) begin
                if (!empty) begin
                    // 普通数据拍：当拍就出，不占 hold —— 否则吞吐只有 1/3 拍/周期，
                    // 跟不上 ROI 的输入速率（1/2.95 拍/周期），FIFO 一满就丢拍。
                    if (!mem[rp[FIFO_AW-1:0]][34] && !mem[rp[FIFO_AW-1:0]][33] &&
                        !mem[rp[FIFO_AW-1:0]][32]) begin
                        o_valid <= 1'b1;
                        o_pix   <= pack4(mem[rp[FIFO_AW-1:0]][31:0]);
                        rp      <= rp + 1'b1;
                    end else begin
                        hold      <= mem[rp[FIFO_AW-1:0]];
                        hold_v    <= 1'b1;
                        data_sent <= 1'b0;
                        rp        <= rp + 1'b1;
                    end
                end
            end else if (h_sof) begin
                // SOF 单独占一拍，writer 在这一拍清 x/y 与帧武装
                o_vsync <= 1'b1;
                o_frame <= 1'b1;
                hold[34] <= 1'b0;
            end else if (!data_sent) begin
                o_valid  <= 1'b1;
                o_pix    <= pack4(hold[31:0]);
                data_sent <= 1'b1;
                // 注意：EOF 不能在数据拍这一拍拉低 o_frame —— writer 的优先级链是
                // 「sof > line > pixel」，同拍见 EOF 会把最后一组丢掉。放到下一拍。
            end else begin
                // 数据拍之后的收口拍：先补行尾脉冲，再把帧拉低
                if (h_eol) o_line <= 1'b1;
                if (h_eof) o_frame <= 1'b0;
                hold_v <= 1'b0;
            end
        end
    end
endmodule
