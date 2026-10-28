// codec_pack.v — 把 a1_frame_top 的 zlib 字节流拼成「定长灰度帧」给 writer。
//
// 为什么这么绕：主机侧已经有一条验证过的取帧通路（R10F → DDR → PCIe → frame_grab），
// 它要的是「W×H 的 8bit 采样帧」。压缩流长度是变的，所以这里把压缩字节直接塞进
// 采样位（每字节一个 8bit 采样），再补零到固定 W*H/4 组，帧长永远是定值。
// 主机拿 st_stream_len（BAR0）截出前 N 字节就是真正的 zlib 流。
//
// 标记：第 0 个字带 sof，每 480 个字一个 eol（凑成 1088 行），最后一个字 eof。
// 输出给 algo_y8_to_legacy 再把标记拆成独立拍并转成 40bit 组。
module codec_pack #(
    parameter integer W    = 1920,
    parameter integer H    = 1088,
    parameter integer GPQ  = 480,          // 每行组数 = W/4
    parameter integer TOTW = (W/4)*H       // 每帧组数（= 字）
)(
    input  wire        clk,
    input  wire        rst_n,
    // 来自 a1_frame_top
    input  wire [31:0] c_data,
    input  wire        c_valid,
    input  wire [3:0]  c_keep,
    input  wire        c_last,        // 流结束
    input  wire        c_commit,
    input  wire        c_abort,       // 编码器判帧坏：丢弃半帧、立刻回到空闲
    output wire        c_ready,       // 补零期间拉低：不让下一帧的流插进来
    // 给 algo_y8_to_legacy
    output reg  [31:0] s_data,
    output reg         s_valid,
    input  wire        s_ready,
    output reg         s_sof,
    output reg         s_eol,
    output reg         s_eof,
    // 观测
    output reg  [31:0] st_stream_len,
    output reg  [31:0] st_words,
    output reg         st_done
);
    // 补零阶段（pending_frame=1 且 stream 已结束）不接受新数据，否则下一帧的
    // c_valid 会和补零交错，帧结构被破坏（板测第一次就是这样卡住的）。
    // 只在「流已结束、正在补零」时反压；streaming 期间必须放行，否则第一个字就卡死。
    assign c_ready = ~(pending_frame && !streaming);

    reg [31:0] widx;          // 本帧已发字数
    reg [15:0] col;           // 本行已发字数（0..GPQ-1）—— 用计数器代替 widx%GPQ，
                              // 取模会综合出除法器，板测那一版 SWNS 直接 -0.149ns
    reg [31:0] blen;          // 本帧压缩字节数
    reg        streaming;     // 1 = 还在收编码器输出
    reg        pending_frame; // 1 = 本帧还没发完（要补零 + eof）

    // keep 的 popcount
    function [2:0] pc4;
        input [3:0] k;
        begin
            pc4 = {2'b00, k[0]} + {2'b00, k[1]} + {2'b00, k[2]} + {2'b00, k[3]};
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_data <= 0; s_valid <= 0; s_sof <= 0; s_eol <= 0; s_eof <= 0;
            widx <= 0; col <= 0; blen <= 0; streaming <= 1'b0; pending_frame <= 1'b0;
            st_stream_len <= 0; st_words <= 0; st_done <= 1'b0;
        end else begin
            st_done <= 1'b0;

            // 编码器 abort 时不会给 c_last。这里必须丢弃半帧并回到空闲，
            // 否则 pending_frame 永远为 1（补零等不到结尾），writer 就停在半帧不动。
            if (c_abort) begin
                widx <= 32'd0; col <= 16'd0; blen <= 32'd0;
                streaming <= 1'b0; pending_frame <= 1'b0;
                s_valid <= 1'b0; s_sof <= 1'b0; s_eol <= 1'b0; s_eof <= 1'b0;
            end else

            // 编码器输出 → 组流（反压时同拍保持，algo_y8_to_legacy 有 FIFO 兜底）
            if (!s_valid || s_ready) begin
                // 补零优先：此时编码器已被 c_ready 反压住（c_valid 可能一直举着），
                // 如果这里还要等 !c_valid 才能补零，就会死锁在这一帧。
                if (pending_frame && !streaming) begin
                    s_valid <= 1'b1;
                    s_data  <= 32'd0;
                    s_sof   <= 1'b0;
                    s_eol   <= (col == GPQ - 1);
                    s_eof   <= (widx == TOTW - 1);
                    widx    <= widx + 32'd1;
                    col     <= (col == GPQ - 1) ? 16'd0 : (col + 16'd1);
                    if (widx == TOTW - 1) begin
                        pending_frame <= 1'b0;
                        widx  <= 0;
                        col   <= 16'd0;
                        blen  <= 0;
                        st_words <= TOTW;
                        st_done  <= 1'b1;
                    end
                end else if (c_valid) begin
                    s_valid <= 1'b1;
                    s_data  <= c_data;
                    s_sof   <= (widx == 32'd0);
                    s_eol   <= (col == GPQ - 1);
                    s_eof   <= 1'b0;
                    widx    <= widx + 32'd1;
                    col     <= (col == GPQ - 1) ? 16'd0 : (col + 16'd1);
                    blen    <= blen + pc4(c_keep);
                    streaming <= 1'b1;
                    pending_frame <= 1'b1;
                    if (c_last) begin
                        streaming <= 1'b0;
                        st_stream_len <= blen + pc4(c_keep);
                    end
                end else begin
                    s_valid <= 1'b0;
                    s_eof   <= 1'b0;
                end
            end
        end
    end
endmodule
