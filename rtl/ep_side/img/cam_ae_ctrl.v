`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////
//  cam_ae_ctrl.v — 摄像头自动曝光/增益（AE/AGC）控制
//
//  数据通路：
//    cam_clk 域：只统计 win=1 的像素，逐帧累加亮度 sum / count，
//                并统计过亮（pix>=1000）与过暗（pix<=16）像素数；
//                eof 时锁存统计值，用 64 拍移位除法求帧均值，
//                均值打一拍后用 toggle 跨到 clk_tl 域。
//    clk_tl  域：2 级同步 + 边沿检测取回均值，每 N 帧做一次
//                比例调节，通过 I_ae_req / O_ae_data 写给
//                ui_cfg_imx415 的 AE 通道（传感器 0x3090 GAIN_PGC_0）。
//
//  增益标度：IMX415 GAIN_PGC 每 LSB 约 0.3 dB，0x40(64) = 19.2 dB。
//  本模块只做“增益码值比例步进”，不做 dB 换算，避免乘法/对数。
//
//  握手假设（对端 ui_cfg_imx415.v）：
//    - I_ae_req 必须是 1 拍脉冲；O_ae_cfg_done 空闲为高，
//      收到请求后拉低，写完再拉高。
//    - 本模块发出请求后保持 O_ae_data 不变，直到 I_ae_done 完成沿。
//////////////////////////////////////////////////////////////////////
module cam_ae_ctrl #(
    // 目标亮度（10bit 域，0~1023）与死区（±P_DEADBAND 内不调节）
    parameter [9:0]  P_TARGET      = 10'd400,
    parameter [9:0]  P_DEADBAND    = 10'd40,
    // 增益码安全范围；I_ae_en=0 时直接保持 P_GAIN_INIT/manual 值
    parameter [7:0]  P_GAIN_MIN    = 8'd0,
    parameter [7:0]  P_GAIN_MAX    = 8'd160,
    parameter [7:0]  P_GAIN_INIT   = 8'd64,     // 0x40 = 19.2dB，与当前 LUT 一致
    // 每 P_FRAME_DIV 帧调节一次（>=1）
    parameter [15:0] P_FRAME_DIV   = 16'd4,
    // 比例步进：step = (target-mean) >>> P_STEP_SHIFT，并限幅到 ±P_STEP_MAX
    parameter [3:0]  P_STEP_SHIFT  = 4'd4,
    parameter [7:0]  P_STEP_MAX    = 8'd12,
    // 等 I_ae_done 的超时保护（tl 时钟拍数），防止对端异常时卡死
    parameter [23:0] P_DONE_TO     = 24'hFF_FFFF
)(
    // ---------------- 像素时钟域（cam_clk） ----------------
    input  wire        clk_cam,
    input  wire        rst_cam,          // 高有效，异步复位
    input  wire        de,               // 像素有效
    input  wire [9:0]  pix,              // 10bit 亮度
    input  wire        win,              // 该像素在测光窗口内
    input  wire        sof,              // 帧首（1 拍）
    input  wire        eof,              // 帧尾（1 拍）

    // ---------------- 控制时钟域（clk_tl） ----------------
    input  wire        clk_tl,
    input  wire        rst_tl,           // 高有效，异步复位
    input  wire        I_ae_en,          // AE 使能（静态配置）
    input  wire [7:0]  I_ae_manual_gain, // AE 关闭时保持的增益码
    input  wire        I_ae_done,        // 来自 ui_cfg_imx415 的 O_ae_cfg_done

    output reg         O_ae_req,         // 1 拍请求脉冲
    output reg  [7:0]  O_ae_data,        // 增益码，写 0x3090
    output reg  [9:0]  O_frame_mean,     // 最近一帧均值（clk_tl 域）
    output reg         O_frame_stats_valid, // 均值更新脉冲（clk_tl 域，1 拍）
    output reg  [31:0] O_clip_cnt,       // 上帧过亮像素数（cam 域锁存）
    output reg  [31:0] O_dark_cnt,       // 上帧过暗像素数（cam 域锁存）
    output wire [7:0]  O_gain_code       // 当前生效增益码（调试）
);

    // ------------------------------------------------------------------
    //  cam_clk 域：逐帧累加
    //  1920x1080x1023 = 2,121,292,800 < 2^32，64bit sum / 32bit count
    //  留足余量，单帧不可能溢出；count 额外做饱和保护。
    // ------------------------------------------------------------------
    reg [63:0] S_sum;
    reg [31:0] S_cnt;
    reg [31:0] S_clip;
    reg [31:0] S_dark;

    reg [63:0] S_div_num;       // 被除数（帧亮度和，仅累加器写）
    reg [31:0] S_div_den;       // 除数（窗口像素数，仅累加器写）
    reg [63:0] S_div_sh;        // 除法移位寄存器（仅除法器写）
    reg        S_div_start;
    reg        S_div_busy;
    reg [6:0]  S_div_i;
    reg [31:0] S_div_rem;
    reg [63:0] S_div_quo;
    reg [9:0]  S_stat_mean;
    reg        S_stat_done;

    reg [9:0]  S_mean_lat;      // 跨域数据（toggle 后保持稳定）
    reg        S_mean_tog;

    wire        S_pix_win  = de & win;
    wire [63:0] S_sum_inc  = S_sum + {54'd0, pix};
    wire [31:0] S_cnt_inc  = S_cnt + 32'd1;
    wire [31:0] S_clip_inc = S_clip + 32'd1;
    wire [31:0] S_dark_inc = S_dark + 32'd1;
    wire        S_clip_pix = S_pix_win && (pix >= 10'd1000);
    wire        S_dark_pix = S_pix_win && (pix <= 10'd16);
    // eof 同拍可能还有最后一个有效像素，计入本帧
    wire [63:0] S_sum_eof  = S_pix_win ? S_sum_inc  : S_sum;
    wire [31:0] S_cnt_eof  = S_pix_win ? S_cnt_inc  : S_cnt;
    wire [31:0] S_clip_eof = S_clip_pix ? S_clip_inc : S_clip;
    wire [31:0] S_dark_eof = S_dark_pix ? S_dark_inc : S_dark;

    always @(posedge clk_cam or posedge rst_cam) begin
        if (rst_cam) begin
            S_sum        <= 64'd0;
            S_cnt        <= 32'd0;
            S_clip       <= 32'd0;
            S_dark       <= 32'd0;
            S_div_num    <= 64'd0;
            S_div_den    <= 32'd0;
            S_div_start  <= 1'b0;
            O_clip_cnt   <= 32'd0;
            O_dark_cnt   <= 32'd0;
        end else begin
            S_div_start <= 1'b0;
            if (eof) begin
                // 帧尾：锁存统计数据并启动一次除法（空行远大于 64 拍）
                if (!S_div_busy) begin
                    S_div_num   <= S_sum_eof;
                    S_div_den   <= S_cnt_eof;
                    S_div_start <= 1'b1;
                end
                O_clip_cnt <= S_clip_eof;
                O_dark_cnt <= S_dark_eof;
                S_sum      <= 64'd0;
                S_cnt      <= 32'd0;
                S_clip     <= 32'd0;
                S_dark     <= 32'd0;
            end else if (sof) begin
                // 帧首：重新开始累加（同时处理 sof 同拍的有效像素）
                S_sum  <= S_pix_win ? {54'd0, pix} : 64'd0;
                S_cnt  <= S_pix_win ? 32'd1 : 32'd0;
                S_clip <= S_clip_pix ? 32'd1 : 32'd0;
                S_dark <= S_dark_pix ? 32'd1 : 32'd0;
            end else if (S_pix_win) begin
                S_sum  <= S_sum_inc;
                S_cnt  <= (S_cnt  == 32'hFFFF_FFFF) ? S_cnt  : S_cnt_inc;
                S_clip <= (S_clip == 32'hFFFF_FFFF) ? S_clip : (S_clip_pix ? S_clip_inc : S_clip);
                S_dark <= (S_dark == 32'hFFFF_FFFF) ? S_dark : (S_dark_pix ? S_dark_inc : S_dark);
            end
        end
    end

    // ------------------------------------------------------------------
    //  64 拍恢复余数除法：mean = sum / count
    //  商不会超过 1023（pix<=1023），高位非零时饱和到 0x3FF。
    // ------------------------------------------------------------------
    // 33bit 比较值（rem<<1 | 被除数最高位）、减法结果与比较标志
    wire [32:0] S_rem_shift = {S_div_rem, S_div_sh[63]};
    wire        S_rem_ge    = (S_rem_shift >= {1'b0, S_div_den});
    wire [31:0] S_rem_sub   = S_rem_shift[31:0] - S_div_den;

    always @(posedge clk_cam or posedge rst_cam) begin
        if (rst_cam) begin
            S_div_busy  <= 1'b0;
            S_div_i     <= 7'd0;
            S_div_sh    <= 64'd0;
            S_div_rem   <= 32'd0;
            S_div_quo   <= 64'd0;
            S_stat_mean <= 10'd0;
            S_stat_done <= 1'b0;
        end else begin
            S_stat_done <= 1'b0;
            if (S_div_start) begin
                if (S_div_den == 32'd0) begin
                    // 空窗口：均值记 0，仍然产生一次统计完成脉冲
                    S_div_busy  <= 1'b0;
                    S_stat_mean <= 10'd0;
                    S_stat_done <= 1'b1;
                end else begin
                    S_div_busy <= 1'b1;
                    S_div_i    <= 7'd0;
                    S_div_sh   <= S_div_num;    // 锁存被除数后独立移位
                    S_div_rem  <= 32'd0;
                    S_div_quo  <= 64'd0;
                end
            end else if (S_div_busy) begin
                if (S_div_i == 7'd64) begin
                    S_div_busy  <= 1'b0;
                    S_stat_mean <= (S_div_quo[63:10] != 54'd0) ? 10'h3FF
                                                              : S_div_quo[9:0];
                    S_stat_done <= 1'b1;
                end else begin
                    if (S_rem_ge) begin
                        S_div_rem <= S_rem_sub;
                        S_div_quo <= {S_div_quo[62:0], 1'b1};
                    end else begin
                        S_div_rem <= S_rem_shift[31:0];
                        S_div_quo <= {S_div_quo[62:0], 1'b0};
                    end
                    S_div_sh <= {S_div_sh[62:0], 1'b0};
                    S_div_i  <= S_div_i + 1'b1;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    //  跨时钟域：数据先稳定，再翻转 toggle（2 级同步 + 边沿检测）
    // ------------------------------------------------------------------
    always @(posedge clk_cam or posedge rst_cam) begin
        if (rst_cam) begin
            S_mean_lat <= 10'd0;
            S_mean_tog <= 1'b0;
        end else if (S_stat_done) begin
            S_mean_lat <= S_stat_mean;
            S_mean_tog <= ~S_mean_tog;
        end
    end

    reg [1:0] S_tog_sync;
    reg       S_tog_last;

    always @(posedge clk_tl or posedge rst_tl) begin
        if (rst_tl) begin
            S_tog_sync         <= 2'b00;
            S_tog_last         <= 1'b0;
            O_frame_mean       <= 10'd0;
            O_frame_stats_valid<= 1'b0;
        end else begin
            S_tog_sync          <= {S_tog_sync[0], S_mean_tog};
            O_frame_stats_valid <= 1'b0;
            if (S_tog_sync[1] != S_tog_last) begin
                S_tog_last          <= S_tog_sync[1];
                O_frame_mean        <= S_mean_lat;   // toggle 后数据已稳定
                O_frame_stats_valid <= 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------
    //  clk_tl 域：比例增益控制
    //  err = target - mean；step = err >>> P_STEP_SHIFT（限幅 ±P_STEP_MAX）
    //  next = gain + step，再夹到 [P_GAIN_MIN, P_GAIN_MAX]
    // ------------------------------------------------------------------
    wire signed [12:0] S_err      = $signed({3'b000, P_TARGET}) -
                                    $signed({3'b000, O_frame_mean});
    wire signed [12:0] S_step_raw = S_err >>> P_STEP_SHIFT;
    wire signed [12:0] S_step_max = $signed({5'b00000, P_STEP_MAX});
    wire signed [12:0] S_step     = (S_step_raw >  S_step_max) ?  S_step_max :
                                    (S_step_raw < -S_step_max) ? -S_step_max :
                                                                  S_step_raw;
    wire signed [12:0] S_gain_s   = $signed({5'b00000, S_gain});
    wire signed [12:0] S_next_raw = S_gain_s + S_step;
    wire [10:0] S_absdiff = (O_frame_mean > P_TARGET) ?
                            ({1'b0, O_frame_mean} - {1'b0, P_TARGET}) :
                            ({1'b0, P_TARGET} - {1'b0, O_frame_mean});
    wire S_inband = (S_absdiff <= {1'b0, P_DEADBAND});
    wire [7:0] S_next = (S_next_raw > $signed({5'b00000, P_GAIN_MAX})) ? P_GAIN_MAX :
                        (S_next_raw < $signed({5'b00000, P_GAIN_MIN})) ? P_GAIN_MIN :
                                                                        S_next_raw[7:0];
    // 手动值同样夹在安全范围内，防止配置寄存器写入越界码值
    wire signed [8:0] S_man_s = $signed({1'b0, I_ae_manual_gain});
    wire signed [8:0] S_min_s = $signed({1'b0, P_GAIN_MIN});
    wire signed [8:0] S_max_s = $signed({1'b0, P_GAIN_MAX});
    wire [7:0] S_manual = (S_man_s > S_max_s) ? P_GAIN_MAX :
                          (S_man_s < S_min_s) ? P_GAIN_MIN :
                                                I_ae_manual_gain;
    wire [7:0] S_goal = I_ae_en ? S_next : S_manual;
    // 使能时：只有 N 帧到期（S_pending 只由真实帧统计置位）且均值在
    // 死区外，才允许调节一次；旁路时与手动值不同就写一次。
    wire S_act = I_ae_en ? (S_pending && !S_inband && (S_goal != S_gain))
                         : (S_goal != S_gain);

    reg        S_state;
    reg [7:0]  S_gain;
    reg [15:0] S_fcnt;
    reg        S_pending;
    reg        S_done_d;
    reg [23:0] S_to;

    localparam S_IDLE = 1'b0;
    localparam S_WAIT = 1'b1;

    assign O_gain_code = S_gain;

    always @(posedge clk_tl or posedge rst_tl) begin
        if (rst_tl) begin
            S_state    <= S_IDLE;
            S_gain     <= P_GAIN_INIT;
            S_fcnt     <= 16'd0;
            S_pending  <= 1'b0;
            S_done_d   <= 1'b0;
            S_to       <= 24'd0;
            O_ae_req   <= 1'b0;
            O_ae_data  <= P_GAIN_INIT;
        end else begin
            O_ae_req <= 1'b0;

            case (S_state)
            S_IDLE: begin
                // 空闲时持续跟踪 done，避免把空闲常高误当成完成沿
                S_done_d <= I_ae_done;
                S_to     <= 24'd0;
                if (S_act) begin
                    O_ae_req  <= 1'b1;              // 单拍请求
                    O_ae_data <= S_goal;            // 保持到写完
                    S_pending <= 1'b0;
                    S_state   <= S_WAIT;
                end else begin
                    S_pending <= 1'b0;
                end
            end
            S_WAIT: begin
                // 必须等到 I_ae_done 的上升沿（或超时）才允许下一次请求
                if (I_ae_done && !S_done_d) begin
                    S_gain  <= O_ae_data;
                    S_to    <= 24'd0;
                    S_state <= S_IDLE;
                end else if (S_to >= P_DONE_TO) begin
                    S_gain  <= O_ae_data;           // 对端异常也不永久卡死
                    S_to    <= 24'd0;
                    S_state <= S_IDLE;
                end else begin
                    S_done_d <= I_ae_done;
                    S_to     <= S_to + 1'b1;
                end
            end
            default: S_state <= S_IDLE;
            endcase

            // 帧计数放在状态机之后：同一拍到达的统计不会被本次清零吃掉
            if (O_frame_stats_valid) begin
                if ((S_fcnt + 16'd1) >= P_FRAME_DIV) begin
                    S_fcnt    <= 16'd0;
                    S_pending <= 1'b1;
                end else begin
                    S_fcnt <= S_fcnt + 16'd1;
                end
            end
        end
    end

endmodule
