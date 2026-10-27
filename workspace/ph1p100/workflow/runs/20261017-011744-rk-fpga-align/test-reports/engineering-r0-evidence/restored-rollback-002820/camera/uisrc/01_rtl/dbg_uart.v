// =============================================================================
//  dbg_uart.v — 通过 UART 打印状态，用来替代"数灯"
//
//  每 0.5s 打五行（每行 = 4 字符标签 + '=' + 8 位十六进制 + CRLF）：
//    STAT=XXXXXXXX  状态位（见下）
//    CNA =XXXXXXXX  A 口最近 0.5s：{帧类事件[31:16], CSI-2 包数[15:0]}
//    CNB =XXXXXXXX  B 口同上
//    CKA =XXXXXXXX  A 口字节时钟活动（0.5s 内慢翻转跳变次数；0 = 字节时钟没起来）
//    CKB =XXXXXXXX  B 口同上
//  每 1s 再加一行：HB  =XXXXXXXX   秒计数（验证串口通道本身）
//
//  字节时钟换算：CKA 的 N 次跳变 → 字节时钟 ≈ N × 2 × 2^15 / 0.5s = N × 131072 Hz
//                （N≈850 即 111MHz，正常值）
//
//  STAT 状态字位定义（bit0 最低）：
//    [3:0]   alA     A 口 4 个 lane 字节对齐有效（实时电平）
//    [7:4]   alB     B 口同上
//    [8]     cfgA    A 口 I2C 配置流程跑完
//    [9]     errA    A 口 I2C 出现过 NACK（顶层已锁存，错过一次就一直是 1）
//    [10]    cfgB    B 口 I2C 配置流程跑完
//    [11]    errB    B 口 I2C 出现过 NACK（锁存）
//    [17:12] tapA    当前生效 delay tap
//    [23:18] tapB    当前生效 delay tap
//    [24]    pktA    累计收到过 CSI-2 包
//    [25]    vsA     累计收到过帧类事件
//    [26]    pktB    B 口同上
//    [27]    vsB     B 口同上
//    [31:28] 0
// =============================================================================
`timescale 1ns / 1ps

module dbg_uart #(
    parameter CLK_DIV = 16'd434              // 50MHz / 434 ≈ 115200
)(
    input  wire        I_clk,
    input  wire        I_rst_n,

    // ---- 端口 A ----
    input  wire [3:0]  I_a_lane_valid,
    input  wire [5:0]  I_a_tap,
    input  wire        I_a_cfg_done,
    input  wire        I_a_bus_err,
    input  wire        I_a_pkt_tgl,
    input  wire        I_a_vs_tgl,
    input  wire        I_a_clk_tgl,
    input  wire [31:0] I_a_nack_cnt,
    input  wire [31:0] I_b_nack_cnt,
    input  wire [3:0]  I_a_lane_sticky,
    input  wire [3:0]  I_b_lane_sticky,
    // ---- 端口 B ----
    input  wire [3:0]  I_b_lane_valid,
    input  wire [5:0]  I_b_tap,
    input  wire        I_b_cfg_done,
    input  wire        I_b_bus_err,
    input  wire        I_b_pkt_tgl,
    input  wire        I_b_vs_tgl,
    input  wire        I_b_clk_tgl,

    output wire        O_txd
);

    // ---------------- 跨时钟域同步 ----------------
    reg [1:0] r_a_pkt_s, r_a_vs_s, r_a_clk_s;
    reg [1:0] r_b_pkt_s, r_b_vs_s, r_b_clk_s;
    reg [3:0] r_a_al, r_b_al;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_a_pkt_s <= 2'd0; r_a_vs_s <= 2'd0; r_a_clk_s <= 2'd0;
            r_b_pkt_s <= 2'd0; r_b_vs_s <= 2'd0; r_b_clk_s <= 2'd0;
            r_a_al <= 4'd0;    r_b_al <= 4'd0;
        end else begin
            r_a_pkt_s <= {r_a_pkt_s[0], I_a_pkt_tgl};
            r_a_vs_s  <= {r_a_vs_s[0],  I_a_vs_tgl };
            r_a_clk_s <= {r_a_clk_s[0], I_a_clk_tgl};
            r_b_pkt_s <= {r_b_pkt_s[0], I_b_pkt_tgl};
            r_b_vs_s  <= {r_b_vs_s[0],  I_b_vs_tgl };
            r_b_clk_s <= {r_b_clk_s[0], I_b_clk_tgl};
            r_a_al    <= I_a_lane_valid;
            r_b_al    <= I_b_lane_valid;
        end
    end

    // ---------------- 窗口内边沿计数 ----------------
    reg [15:0] r_a_pkt_c, r_a_fra_c, r_a_clk_c;
    reg [15:0] r_b_pkt_c, r_b_fra_c, r_b_clk_c;
    reg        r_a_pkt_l, r_a_vs_l, r_a_clk_l;
    reg        r_b_pkt_l, r_b_vs_l, r_b_clk_l;
    reg        r_a_pkt_seen, r_a_vs_seen, r_b_pkt_seen, r_b_vs_seen;

    wire w_a_pkt_ev = r_a_pkt_s[1] ^ r_a_pkt_l;
    wire w_a_vs_ev  = r_a_vs_s[1]  ^ r_a_vs_l;
    wire w_a_clk_ev = r_a_clk_s[1] ^ r_a_clk_l;
    wire w_b_pkt_ev = r_b_pkt_s[1] ^ r_b_pkt_l;
    wire w_b_vs_ev  = r_b_vs_s[1]  ^ r_b_vs_l;
    wire w_b_clk_ev = r_b_clk_s[1] ^ r_b_clk_l;

    // ---------------- 0.5s 定时 ----------------
    reg [24:0] r_cnt  = 25'd0;
    reg        r_tick = 1'b0;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_cnt  <= 25'd0;
            r_tick <= 1'b0;
        end else begin
            r_tick <= 1'b0;
            if (r_cnt == 25'd24_999_999) begin
                r_cnt  <= 25'd0;
                r_tick <= 1'b1;
            end else begin
                r_cnt <= r_cnt + 1'b1;
            end
        end
    end

    // ---------------- 打印用锁存值 ----------------
    reg [31:0] r_stat_w = 32'd0, r_cna_w = 32'd0, r_cnb_w = 32'd0;
    reg [31:0] r_cka_w  = 32'd0, r_ckb_w = 32'd0, r_sec   = 32'd0;
    reg [31:0] r_era_w  = 32'd0, r_erb_w = 32'd0;
    reg [31:0] r_lna_w  = 32'd0, r_lnb_w = 32'd0;
    reg        r_hb_flag = 1'b0;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_a_pkt_c <= 16'd0; r_a_fra_c <= 16'd0; r_a_clk_c <= 16'd0;
            r_b_pkt_c <= 16'd0; r_b_fra_c <= 16'd0; r_b_clk_c <= 16'd0;
            r_a_pkt_l <= 1'b0;  r_a_vs_l  <= 1'b0;  r_a_clk_l <= 1'b0;
            r_b_pkt_l <= 1'b0;  r_b_vs_l  <= 1'b0;  r_b_clk_l <= 1'b0;
            r_a_pkt_seen <= 1'b0; r_a_vs_seen <= 1'b0;
            r_b_pkt_seen <= 1'b0; r_b_vs_seen <= 1'b0;
            r_stat_w <= 32'd0; r_cna_w <= 32'd0; r_cnb_w <= 32'd0;
            r_cka_w <= 32'd0; r_ckb_w <= 32'd0; r_sec <= 32'd0; r_hb_flag <= 1'b0;
        end else begin
            if (w_a_pkt_ev) begin r_a_pkt_c <= r_a_pkt_c + 1'b1; r_a_pkt_seen <= 1'b1; end
            if (w_a_vs_ev ) begin r_a_fra_c <= r_a_fra_c + 1'b1; r_a_vs_seen  <= 1'b1; end
            if (w_a_clk_ev) r_a_clk_c <= r_a_clk_c + 1'b1;
            if (w_b_pkt_ev) begin r_b_pkt_c <= r_b_pkt_c + 1'b1; r_b_pkt_seen <= 1'b1; end
            if (w_b_vs_ev ) begin r_b_fra_c <= r_b_fra_c + 1'b1; r_b_vs_seen  <= 1'b1; end
            if (w_b_clk_ev) r_b_clk_c <= r_b_clk_c + 1'b1;

            r_a_pkt_l <= r_a_pkt_s[1]; r_a_vs_l <= r_a_vs_s[1]; r_a_clk_l <= r_a_clk_s[1];
            r_b_pkt_l <= r_b_pkt_s[1]; r_b_vs_l <= r_b_vs_s[1]; r_b_clk_l <= r_b_clk_s[1];

            if (r_tick) begin
                r_stat_w <= {4'd0,
                             r_b_vs_seen, r_b_pkt_seen, r_a_vs_seen, r_a_pkt_seen,
                             I_b_tap, I_a_tap,
                             I_b_bus_err, I_b_cfg_done, I_a_bus_err, I_a_cfg_done,
                             r_b_al, r_a_al};
                r_cna_w <= {r_a_fra_c, r_a_pkt_c};
                r_cnb_w <= {r_b_fra_c, r_b_pkt_c};
                r_cka_w <= {16'd0, r_a_clk_c};
                r_ckb_w <= {16'd0, r_b_clk_c};
                r_era_w <= I_a_nack_cnt;
                r_lna_w <= {28'd0, I_a_lane_sticky};
                r_lnb_w <= {28'd0, I_b_lane_sticky};
                r_erb_w <= I_b_nack_cnt;
                r_a_pkt_c <= 16'd0; r_a_fra_c <= 16'd0; r_a_clk_c <= 16'd0;
                r_b_pkt_c <= 16'd0; r_b_fra_c <= 16'd0; r_b_clk_c <= 16'd0;
                r_hb_flag <= ~r_hb_flag;
                if (r_hb_flag) r_sec <= r_sec + 1'b1;
            end
        end
    end

    // ---------------- 发送状态机 ----------------
    localparam [3:0] L_STAT = 4'd0, L_CNA = 4'd1, L_CNB = 4'd2, L_CKA = 4'd3, L_CKB = 4'd4,
                     L_ERA = 4'd5, L_ERB = 4'd6, L_LNA = 4'd7, L_LNB = 4'd8,
                     L_HB = 4'd9, L_IDLE = 4'd15;
    // 行序：STAT CNA CNB CKA CKB ERA ERB LNA LNB (HB)

    reg [3:0]  r_line = L_IDLE;
    reg [3:0]  r_idx  = 4'd0;
    reg [2:0]  r_nib  = 3'd0;
    reg [31:0] r_word = 32'd0;
    reg [7:0]  r_tx_data = 8'd0;
    reg        r_tx_valid = 1'b0;
    wire       w_tx_busy;
    reg        r_pend = 1'b0;

    wire [3:0] w_nib = r_word[(31 - r_nib*4) -: 4];
    wire [7:0] w_hex = (w_nib < 4'd10) ? (8'h30 + {4'd0, w_nib}) :
                                        (8'h41 + ({4'd0, w_nib} - 4'd10));

    reg [7:0] w_tag;
    always @* begin
        case (r_line)
            L_STAT: w_tag = (r_idx == 4'd0) ? "S" : (r_idx == 4'd1) ? "T" : (r_idx == 4'd2) ? "A" : "T";
            L_CNA : w_tag = (r_idx == 4'd0) ? "C" : (r_idx == 4'd1) ? "N" : (r_idx == 4'd2) ? "A" : " ";
            L_CNB : w_tag = (r_idx == 4'd0) ? "C" : (r_idx == 4'd1) ? "N" : (r_idx == 4'd2) ? "B" : " ";
            L_CKA : w_tag = (r_idx == 4'd0) ? "C" : (r_idx == 4'd1) ? "K" : (r_idx == 4'd2) ? "A" : " ";
            L_CKB : w_tag = (r_idx == 4'd0) ? "C" : (r_idx == 4'd1) ? "K" : (r_idx == 4'd2) ? "B" : " ";
            L_ERA : w_tag = (r_idx == 4'd0) ? "E" : (r_idx == 4'd1) ? "R" : (r_idx == 4'd2) ? "A" : " ";
            L_ERB : w_tag = (r_idx == 4'd0) ? "E" : (r_idx == 4'd1) ? "R" : (r_idx == 4'd2) ? "B" : " ";
            L_LNA : w_tag = (r_idx == 4'd0) ? "L" : (r_idx == 4'd1) ? "N" : (r_idx == 4'd2) ? "A" : " ";
            L_LNB : w_tag = (r_idx == 4'd0) ? "L" : (r_idx == 4'd1) ? "N" : (r_idx == 4'd2) ? "B" : " ";
            default: w_tag = (r_idx == 4'd0) ? "H" : (r_idx == 4'd1) ? "B" : " ";
        endcase
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_line <= L_IDLE; r_idx <= 4'd0; r_nib <= 3'd0;
            r_tx_valid <= 1'b0; r_pend <= 1'b0;
        end else begin
            r_tx_valid <= 1'b0;

            if (r_line == L_IDLE) begin
                if (r_tick) r_pend <= 1'b1;
                else if (r_pend) begin
                    r_line <= L_STAT; r_idx <= 4'd0; r_nib <= 3'd0; r_word <= r_stat_w;
                end
            end else if (!w_tx_busy && !r_tx_valid) begin
                if (r_idx <= 4'd3)       r_tx_data <= w_tag;
                else if (r_idx == 4'd4)  r_tx_data <= "=";
                else if (r_idx <= 4'd12) r_tx_data <= w_hex;
                else if (r_idx == 4'd13) r_tx_data <= 8'h0D;
                else                     r_tx_data <= 8'h0A;
                r_tx_valid <= 1'b1;

                if (r_idx == 4'd14) begin
                    r_idx <= 4'd0;
                    r_nib <= 3'd0;
                    case (r_line)
                        L_STAT: begin r_line <= L_CNA; r_word <= r_cna_w; end
                        L_CNA : begin r_line <= L_CNB; r_word <= r_cnb_w; end
                        L_CNB : begin r_line <= L_CKA; r_word <= r_cka_w; end
                        L_CKA : begin r_line <= L_CKB; r_word <= r_ckb_w; end
                        L_CKB : begin r_line <= L_ERA; r_word <= r_era_w; end
                        L_ERA : begin r_line <= L_ERB; r_word <= r_erb_w; end
                        L_ERB : begin r_line <= L_LNA; r_word <= r_lna_w; end
                        L_LNA : begin r_line <= L_LNB; r_word <= r_lnb_w; end
                        L_LNB : begin
                                    if (r_hb_flag) begin r_line <= L_HB; r_word <= r_sec; end
                                    else begin r_line <= L_IDLE; r_pend <= 1'b0; end
                                end
                        default: begin r_line <= L_IDLE; r_pend <= 1'b0; end
                    endcase
                end else begin
                    r_idx <= r_idx + 1'b1;
                    if (r_idx >= 4'd5 && r_nib != 3'd7) r_nib <= r_nib + 1'b1;
                end
            end
        end
    end

    uart_tx #(.CLK_DIV(CLK_DIV)) u_tx (
        .I_clk   (I_clk    ),
        .I_rst_n (I_rst_n  ),
        .I_data  (r_tx_data),
        .I_valid (r_tx_valid),
        .O_txd   (O_txd    ),
        .O_busy  (w_tx_busy)
    );

endmodule
