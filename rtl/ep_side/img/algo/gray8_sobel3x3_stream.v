// gray8_sobel3x3_stream.v — 4px/beat streaming 3x3 Sobel edge magnitude on Y8.
//
// 与 gray8_gaussian3x3_stream 共用同一套行窗/背压/边带契约，只替换 3x3 运算：
//   Gx = (d0 + 2*d1 + d2) - (u0 + 2*u1 + u2)     垂直梯度
//   Gy = (u2 + 2*c2 + d2) - (u0 + 2*c0 + d0)     水平梯度
//   out = min(255, (|Gx| + |Gy|) >> 1)            定点、无乘法、无除法
// 每拍出 4 个像素，与输入同速；边框按行窗给出的复制像素处理（与高斯一致）。
//
// 支持配置：W % 4 == 0，8 <= W <= MAX_WORDS*4，2 <= H <= 2048。
module gray8_sobel3x3_stream #(
    parameter MAX_WORDS = 512
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        cfg_valid,
    output wire        cfg_ready,
    input  wire [11:0] cfg_width,
    input  wire [11:0] cfg_height,
    output wire        cfg_error,
    input  wire        s_valid,
    output wire        s_ready,
    input  wire [31:0] s_data,
    input  wire        s_sof,
    input  wire        s_eol,
    input  wire        s_eof,
    input  wire        s_abort,
    output wire        m_valid,
    input  wire        m_ready,
    output wire [31:0] m_data,
    output wire        m_sof,
    output wire        m_eol,
    output wire        m_eof,
    output wire        m_abort,
    output wire [15:0] st_frames_good,
    output wire [15:0] st_frames_abort
);
    localparam LW = MAX_WORDS;

    // ---------------- 配置 ----------------
    reg        cfg_lat;
    reg        cfg_err;
    reg [11:0] r_width, r_height;

    assign cfg_ready = rst_n && !cfg_lat;
    assign cfg_error = cfg_err;
    wire cfg_ok = cfg_lat && !cfg_err;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_lat  <= 1'b0;
            cfg_err  <= 1'b0;
            r_width  <= 12'd0;
            r_height <= 12'd0;
        end else if (cfg_valid && cfg_ready) begin
            cfg_lat  <= 1'b1;
            r_width  <= cfg_width;
            r_height <= cfg_height;
            cfg_err  <= !((cfg_width[1:0] == 2'd0) &&
                          (cfg_width >= 12'd8) &&
                          (cfg_width <= LW*4) &&
                          (cfg_height >= 12'd2) &&
                          (cfg_height <= 12'd2048));
        end
    end

    // ---------------- 行窗前端 ----------------
    wire        prod_valid, prod_first, prod_last, prod_abort, evt_good, evt_abort;
    wire [11:0] prod_y, prod_j;
    wire [47:0] win_c, win_u, win_d;

    wire pipe_en = !(m_valid && !m_ready);

    algo_rowwin3 #(.MAX_WORDS(MAX_WORDS), .DW(32), .PARITY_CLAMP(0)) u_row (
        .clk(clk), .rst_n(rst_n),
        .cfg_width(r_width), .cfg_height(r_height), .cfg_ok(cfg_ok),
        .s_valid(s_valid), .s_ready(s_ready), .s_data(s_data),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof), .s_abort(s_abort),
        .en(pipe_en),
        .prod_valid(prod_valid), .prod_y(prod_y), .prod_j(prod_j),
        .prod_first(prod_first), .prod_last(prod_last), .prod_abort(prod_abort),
        .win_c(win_c), .win_u(win_u), .win_d(win_d),
        .evt_good(evt_good), .evt_abort(evt_abort)
    );

    // ---------------- P 级：锁存待处理窗口 ----------------
    reg [47:0] p_wc, p_wu, p_wd;
    reg        p_valid, p_abort, p_sof, p_eol, p_eof;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p_wc <= 48'd0; p_wu <= 48'd0; p_wd <= 48'd0;
            p_valid <= 1'b0; p_abort <= 1'b0;
            p_sof <= 1'b0; p_eol <= 1'b0; p_eof <= 1'b0;
        end else if (pipe_en) begin
            p_valid <= prod_valid;
            p_abort <= prod_valid && prod_abort;
            if (prod_valid && !prod_abort) begin
                p_wc  <= win_c;
                p_wu  <= win_u;
                p_wd  <= win_d;
                p_sof <= (prod_y == 12'd0) && (prod_j == 12'd0);
                p_eol <= prod_last;
                p_eof <= prod_last && (prod_y == r_height - 12'd1);
            end else if (prod_valid && prod_abort) begin
                p_sof <= 1'b0;
                p_eol <= 1'b0;
                p_eof <= 1'b0;
            end
        end
    end

    // ---------------- M1 级：行向加权和与列向加权和 ----------------
    wire [7:0] c0 = p_wc[47:40], c1 = p_wc[39:32], c2 = p_wc[31:24];
    wire [7:0] c3 = p_wc[23:16], c4 = p_wc[15:8],  c5 = p_wc[7:0];
    wire [7:0] u0 = p_wu[47:40], u1 = p_wu[39:32], u2 = p_wu[31:24];
    wire [7:0] u3 = p_wu[23:16], u4 = p_wu[15:8],  u5 = p_wu[7:0];
    wire [7:0] d0 = p_wd[47:40], d1 = p_wd[39:32], d2 = p_wd[31:24];
    wire [7:0] d3 = p_wd[23:16], d4 = p_wd[15:8],  d5 = p_wd[7:0];

    function [10:0] hsum;          // a + 2b + c
        input [7:0] l, m, r;
        begin
            hsum = {3'b0, l} + ({3'b0, m} << 1) + {3'b0, r};
        end
    endfunction

    function [10:0] vsum;          // a + 2b + c（列向）
        input [7:0] t, m, b;
        begin
            vsum = {3'b0, t} + ({3'b0, m} << 1) + {3'b0, b};
        end
    endfunction

    // Gx 用顶/底两行的 1-2-1 行和；Gy 用列向 1-2-1 和后错两列相减
    wire [10:0] hu0 = hsum(u0,u1,u2), hu1 = hsum(u1,u2,u3);
    wire [10:0] hu2 = hsum(u2,u3,u4), hu3 = hsum(u3,u4,u5);
    wire [10:0] hd0 = hsum(d0,d1,d2), hd1 = hsum(d1,d2,d3);
    wire [10:0] hd2 = hsum(d2,d3,d4), hd3 = hsum(d3,d4,d5);
    wire [10:0] v0 = vsum(u0,c0,d0), v1 = vsum(u1,c1,d1);
    wire [10:0] v2 = vsum(u2,c2,d2), v3 = vsum(u3,c3,d3);
    wire [10:0] v4 = vsum(u4,c4,d4), v5 = vsum(u5,c5,d5);

    reg [10:0] r_hu0, r_hu1, r_hu2, r_hu3;
    reg [10:0] r_hd0, r_hd1, r_hd2, r_hd3;
    reg [10:0] r_v0, r_v1, r_v2, r_v3, r_v4, r_v5;
    reg        r_valid, r_abort, r_sof, r_eol, r_eof;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_hu0 <= 11'd0; r_hu1 <= 11'd0; r_hu2 <= 11'd0; r_hu3 <= 11'd0;
            r_hd0 <= 11'd0; r_hd1 <= 11'd0; r_hd2 <= 11'd0; r_hd3 <= 11'd0;
            r_v0 <= 11'd0; r_v1 <= 11'd0; r_v2 <= 11'd0;
            r_v3 <= 11'd0; r_v4 <= 11'd0; r_v5 <= 11'd0;
            r_valid <= 1'b0; r_abort <= 1'b0;
            r_sof <= 1'b0; r_eol <= 1'b0; r_eof <= 1'b0;
        end else if (pipe_en) begin
            r_hu0 <= hu0; r_hu1 <= hu1; r_hu2 <= hu2; r_hu3 <= hu3;
            r_hd0 <= hd0; r_hd1 <= hd1; r_hd2 <= hd2; r_hd3 <= hd3;
            r_v0 <= v0; r_v1 <= v1; r_v2 <= v2;
            r_v3 <= v3; r_v4 <= v4; r_v5 <= v5;
            r_valid <= p_valid; r_abort <= p_abort;
            r_sof <= p_sof; r_eol <= p_eol; r_eof <= p_eof;
        end
    end

    // ---------------- M2/输出级：求梯度幅值 ----------------
    function [7:0] mag;
        input [10:0] top, bot, va, vb;
        reg [11:0] gx, gy;
        reg [12:0] s;
        begin
            gx = (bot >= top) ? (bot - top) : (top - bot);
            gy = (vb  >= va ) ? (vb  - va ) : (va  - vb );
            s  = {1'b0, gx} + {1'b0, gy};
            s  = s >> 1;                       // 1-2-1 归一化后左移，保证弱边缘可见
            mag = (s > 13'd255) ? 8'd255 : s[7:0];
        end
    endfunction

    reg [31:0] o_data;
    reg        o_valid, o_abort, o_sof, o_eol, o_eof;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_data <= 32'd0;
            o_valid <= 1'b0; o_abort <= 1'b0;
            o_sof <= 1'b0; o_eol <= 1'b0; o_eof <= 1'b0;
        end else if (pipe_en) begin
            // 像素 j 的窗口是列 j/j+1/j+2：Gx 取顶底行和之差，Gy 取列和左右之差
            o_data <= { mag(r_hd3, r_hu3, r_v3, r_v5),
                        mag(r_hd2, r_hu2, r_v2, r_v4),
                        mag(r_hd1, r_hu1, r_v1, r_v3),
                        mag(r_hd0, r_hu0, r_v0, r_v2) };
            o_valid <= r_valid; o_abort <= r_abort;
            o_sof <= r_sof; o_eol <= r_eol; o_eof <= r_eof;
        end
    end

    assign m_valid = o_valid;
    assign m_data  = o_data;
    assign m_sof   = o_sof;
    assign m_eol   = o_eol;
    assign m_eof   = o_eof;
    assign m_abort = o_abort;

    // ---------------- 帧计数 ----------------
    reg [15:0] cnt_good, cnt_abort;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_good  <= 16'd0;
            cnt_abort <= 16'd0;
        end else begin
            if (evt_good)  cnt_good  <= cnt_good + 16'd1;
            if (evt_abort) cnt_abort <= cnt_abort + 16'd1;
        end
    end
    assign st_frames_good  = cnt_good;
    assign st_frames_abort = cnt_abort;
endmodule
