// =============================================================================
//  cam_preview.v — 摄像头实时预览（抽降采样 → 片内帧缓存 → 放大显示）
//  工程: f9p_ph1p100_imx415x2      器件: PH1P100SBG484 / -3
// -----------------------------------------------------------------------------
//  数据流
//    采集侧（CSI-2 字节时钟域 187.5MHz，I_pix_data 每拍 4 个 10bit 像素）
//        源 3840x2160 RAW10
//          水平: 每 DEC_CYC 拍取 1 拍，用该拍前 2 个像素求平均   --> SW 列
//          垂直: 每 DEC_LINE 个源行成一组，取组内前 2 行平均     --> SH 行
//        ==> SW x SH 灰度（8bit）写入帧缓存
//    显示侧（HDMI 像素时钟域 137.5MHz）
//        每 SCALE x SCALE 个显示像素读同一源像素（最近邻放大）-> H_ACT x V_ACT
//
//  参数约束（改分辨率必须同时满足；下面 initial 里会检查）
//    SW = 3840 / (DEC_CYC * 4)    每拍 4 像素，每 DEC_CYC 拍出 1 个采样
//    SH = 2160 / DEC_LINE
//    H_ACT % SW == 0              SCALE 必须是整数
//    当前: SW=960, SH=540, DEC_LINE=4, DEC_CYC=1, SCALE=2 → 输出 1920x1080
//
//  依赖与约束
//    · 帧缓存用 reg 数组，但写口必须是"单时钟 + 单条 if (we) mem[a] <= d"的简单形式 ——
//      这样 TD 才会把它推断成 ERAM20K 硬块（实测 u_cam_preview 占 203 块 / 上限 300，
//      LUT6 只有百余个）。写成带复位的复杂形式会被判成分布式 RAM（LUT），
//      几万字节就能把器件撑爆（曾出现 slice 65664 > 25600 的失败）。
//    · I_frame 上升沿复位列/行计数，保证每帧取到同一批源行（防垂直滚动）。
//    · 读写地址都用"行基址增量相加"，不放乘法在关键路径上。
//    · 跨时钟域只过 O_cam_alive 一个标志（2 级同步器 ASYNC_REG），像素数据靠帧缓存。
//    · 帧缓存拆成 4 个 bank（每 bank 只装 SH/4 行）：整帧 518KB 让 TD 映射成 ~191 个 ERAM 块后，
//      块间地址译码 + 读出多路选择各要 4 级 LUT 加长布线，137.5MHz（7.27ns）压不住（实测 -0.31ns）。
//      分成 4 个各约 51 块的 bank 后，每个 bank 内部选择器浅一级，读侧再加一个 4:1 选择，时序收敛。
// =============================================================================
`timescale 1ns / 1ps

module cam_preview_capture #(
    // ---- 抽降后（帧缓存）分辨率 ----
    parameter SW         = 960,          // 抽降后宽（源 3840）
    parameter SH         = 540,          // 抽降后高（源 2160）
    // ---- 显示有效区 ----
    parameter H_ACT      = 1920,
    parameter V_ACT      = 1080,
    // ---- 抽降比 ----
    parameter DEC_LINE   = 4,            // 每 DEC_LINE 个源行成一组（2160/4 = 540）
    parameter DEC_CYC    = 1,            // 每 DEC_CYC 个字节拍取 1 个采样（960/1 = 960）
    // ---- 采集活动检测 ----
    parameter ALIVE_BITS = 24            // 超过 2^ALIVE_BITS 个字节时钟无行脉冲 → 判为无数据
)(
    // ---------------- 采集侧：CSI-2 字节时钟域 ----------------
    input  wire          I_bc_clk,
    input  wire          I_bc_rst_n,
    input  wire [39:0]   I_pix_data,     // 4 个 10bit 像素（每拍）
    input  wire          I_pix_valid,    // 该拍像素有效
    input  wire          I_line,         // 行脉冲（每行一个）
    input  wire          I_frame,        // 帧内标志（上升沿同步计数器）

    // ---------------- 显示侧：像素时钟域 ----------------
    input  wire          I_pclk,
    input  wire          I_pclk_rst_n,
    input  wire          I_de,           // 显示数据有效
    input  wire          I_vs,           // 帧同步
    output wire [23:0]   O_rgb,          // 灰度输出 {Y,Y,Y}
    output wire          O_de,           // 与 O_rgb 对齐
    output wire O_gray_sof,O_gray_valid,O_gray_last,output wire[7:0] O_gray_data,
    output wire          O_cam_alive     // 采集侧有活动（已同步到像素时钟域）
);

    // -------------------------------------------------------------------------
    // 派生参数
    // -------------------------------------------------------------------------
    function integer clog2b;                     // ceil(log2(x))，x<=1 时返回 1
        input integer x;
        integer i;
        begin
            clog2b = 1;
            for (i = 2; i < x; i = i * 2) clog2b = clog2b + 1;
        end
    endfunction

    localparam NBANK  = 4;                       // 帧缓存 bank 数（见头部说明）
    localparam RPB    = SH / NBANK;              // 每个 bank 的行数
    localparam AWB    = clog2b(RPB * SW);        // bank 内地址位宽
    localparam RAM_DEPTH = (1 << AWB); // complete address space for ERAM
    localparam SCALE  = H_ACT / SW;              // 放大倍数（须整除）
    localparam LPH_W  = clog2b(DEC_LINE);        // 组内行相位计数器位宽
    localparam CYC_W  = clog2b(DEC_CYC);         // 字节拍相位计数器位宽
    localparam SWX_W  = clog2b(SCALE);           // 显示侧子像素计数器位宽
    localparam PH_WRT = (DEC_LINE >= 2) ? 1 : 0; // 组内"写出"相位：取前两行平均则写在相位 1

    initial begin
        if (SH % NBANK != 0)          $display("cam_preview: SH 必须能被 bank 数整除");
        if (SW * DEC_CYC * 4 != 3840) $display("cam_preview: SW/DEC_CYC 与源宽 3840 不匹配");
        if (SH * DEC_LINE    != 2160) $display("cam_preview: SH/DEC_LINE 与源高 2160 不匹配");
        if (H_ACT % SW       != 0)    $display("cam_preview: H_ACT 不是 SW 的整数倍");
    end

    // =========================================================================
    // 1. 采集侧（字节时钟域）
    // =========================================================================
    reg  [LPH_W-1:0] r_line_ph  = DEC_LINE[LPH_W-1:0] - 1'b1; // 组内源行相位（0..DEC_LINE-1）
    reg  [CYC_W-1:0] r_cyc_ph   = {CYC_W{1'b0}}; // 字节拍相位（0..DEC_CYC-1）
    reg  [9:0]       r_col      = 10'd0;         // 抽降后列号
    reg  [9:0]       r_rowb     = 10'd0;         // 当前 bank 内行号
    reg  [1:0]       r_bankw    = 2'd0;          // 写入 bank
    reg  [AWB-1:0]   r_wbase    = {AWB{1'b0}};   // bank 内行基址（增量维护）
    reg  [7:0]       r_line_buf [0:SW-1];        // 组内第 1 行的水平平均值
    reg              r_line_d   = 1'b0;
    reg              r_frame_d  = 1'b0;

    reg  [AWB-1:0]   r_wr_addr  = {AWB{1'b0}};
    reg  [7:0]       r_wr_data  = 8'd0;
    reg  [3:0]       r_we       = 4'b0000;       // 每个 bank 一个写使能（与地址/数据同拍寄存）

    (* ram_style = "bram" *) reg  [7:0] r_fb0 [0:RAM_DEPTH-1];               // 帧缓存 4 个 bank（推断为 ERAM20K）
    (* ram_style = "bram" *) reg  [7:0] r_fb1 [0:RAM_DEPTH-1];
    (* ram_style = "bram" *) reg  [7:0] r_fb2 [0:RAM_DEPTH-1];
    (* ram_style = "bram" *) reg  [7:0] r_fb3 [0:RAM_DEPTH-1];

    wire w_line_rise  = I_line  & ~r_line_d;
    wire w_frame_rise = I_frame & ~r_frame_d;

    // 水平平均：取该拍的前两个像素（相邻两列），10bit 求和后取高 8 位
    wire [10:0] w_hsum = {1'b0, I_pix_data[9:0]} + {1'b0, I_pix_data[19:10]};
    wire [7:0]  w_havg = w_hsum[10:3];

    wire w_sample_now = (r_cyc_ph == {CYC_W{1'b0}});
    wire w_store_ph   = (r_line_ph == {LPH_W{1'b0}});          // 组内第 1 行 → 存行缓存
    wire w_write_ph   = (r_line_ph == PH_WRT[LPH_W-1:0]);      // 组内第 2 行 → 平均后写出

    // 帧缓存写口：每个 bank 单独一块，保持"单时钟 + 单条 if"的简单形式，TD 才会映射到 ERAM
    always @(posedge I_bc_clk) if (r_we[0]) r_fb0[r_wr_addr] <= r_wr_data;
    always @(posedge I_bc_clk) if (r_we[1]) r_fb1[r_wr_addr] <= r_wr_data;
    always @(posedge I_bc_clk) if (r_we[2]) r_fb2[r_wr_addr] <= r_wr_data;
    always @(posedge I_bc_clk) if (r_we[3]) r_fb3[r_wr_addr] <= r_wr_data;

    always @(posedge I_bc_clk or negedge I_bc_rst_n) begin
        if (!I_bc_rst_n) begin
            r_line_ph  <= DEC_LINE[LPH_W-1:0] - 1'b1;
            r_cyc_ph   <= {CYC_W{1'b0}};
            r_col      <= 10'd0;
            r_rowb     <= 10'd0;
            r_bankw    <= 2'd0;
            r_wbase    <= {AWB{1'b0}};
            r_line_d   <= 1'b0;
            r_frame_d  <= 1'b0;
            r_we       <= 4'b0000;
        end else begin
            r_line_d  <= I_line;
            r_frame_d <= I_frame;
            r_we      <= 4'b0000;

            // 帧起始：列/行/bank 计数归零，保证每帧取到同一批源行
            if (w_frame_rise) begin
                // First line-start selects store phase 0, not write phase 1.
                r_line_ph <= w_line_rise ? {LPH_W{1'b0}} : DEC_LINE[LPH_W-1:0] - 1'b1;
                r_cyc_ph <= {CYC_W{1'b0}};
                r_col   <= 10'd0;
                r_rowb  <= 10'd0;
                r_bankw <= 2'd0;
                r_wbase <= {AWB{1'b0}};
            end

            // 行脉冲：推进组内相位；一组的最后一个行脉冲之后回到相位 0（下一组开始）
            if (w_line_rise && !w_frame_rise) begin
                r_line_ph <= (r_line_ph == DEC_LINE[LPH_W-1:0] - 1'b1) ? {LPH_W{1'b0}}
                                                                       : r_line_ph + 1'b1;
                r_col     <= 10'd0;
                r_cyc_ph  <= {CYC_W{1'b0}};
            end

            // 像素采样：每 DEC_CYC 个字节拍取 1 个
            if (I_pix_valid && !w_frame_rise) begin
                if (r_cyc_ph == DEC_CYC[CYC_W-1:0] - 1'b1) r_cyc_ph <= {CYC_W{1'b0}};
                else                                       r_cyc_ph <= r_cyc_ph + 1'b1;

                if (w_sample_now && (r_col < SW)) begin
                    if (w_store_ph) begin
                        r_line_buf[r_col] <= w_havg;                       // 组内第 1 行
                    end
                    if (w_write_ph) begin
                        r_wr_data <= (DEC_LINE == 1) ? w_havg              // 单行组：直接写
                                                     : (({1'b0, r_line_buf[r_col]} + {1'b0, w_havg}) >> 1);
                        r_wr_addr <= r_wbase + r_col;
                        r_we      <= (4'b0001 << r_bankw);                 // 只使能当前 bank
                    end

                    r_col <= r_col + 1'b1;
                    if (r_col == SW - 1) begin                             // 一行采完
                        if (w_write_ph) begin                              // 只有写出去了才换目标行
                            if (r_rowb == RPB - 1) begin
                                r_rowb  <= 10'd0;                          // 本 bank 满 → 下一 bank
                                r_wbase <= {AWB{1'b0}};
                                r_bankw <= r_bankw + 1'b1;                 // 2bit 自动回绕
                            end else begin
                                r_rowb  <= r_rowb + 1'b1;
                                r_wbase <= r_wbase + SW[AWB-1:0];
                            end
                        end
                    end
                end
            end
        end
    end

    // 采集活动检测（字节域）：行脉冲超时未到 → 显示侧回落测试图
    reg [ALIVE_BITS-1:0] r_alive_cnt = {ALIVE_BITS{1'b0}};
    reg                  r_alive_bc  = 1'b1;

    always @(posedge I_bc_clk or negedge I_bc_rst_n) begin
        if (!I_bc_rst_n) begin
            r_alive_cnt <= {ALIVE_BITS{1'b0}};
            r_alive_bc  <= 1'b1;
        end else if (w_line_rise) begin
            r_alive_cnt <= {ALIVE_BITS{1'b0}};
            r_alive_bc  <= 1'b1;
        end else if (&r_alive_cnt) begin
            r_alive_bc  <= 1'b0;
        end else begin
            r_alive_cnt <= r_alive_cnt + 1'b1;
        end
    end

    (* ASYNC_REG = "TRUE" *) reg [1:0] r_alive_sync = 2'b00;
    always @(posedge I_pclk) r_alive_sync <= {r_alive_sync[0], r_alive_bc};
    assign O_cam_alive = r_alive_sync[1];

    // =========================================================================
    // 2. 显示侧（像素时钟域）：SCALE 倍最近邻放大
    // =========================================================================
    reg [SWX_W-1:0] r_sx6 = {SWX_W{1'b0}};       // 水平子像素计数（0..SCALE-1）
    reg [SWX_W-1:0] r_sy6 = {SWX_W{1'b0}};       // 垂直子行计数
    reg [9:0]       r_sx    = 10'd0;             // 源列
    reg [9:0]       r_syb   = 10'd0;             // 源行（bank 内）
    reg [1:0]       r_bankr = 2'd0;              // 读 bank
    reg [AWB-1:0]   r_rsbase = {AWB{1'b0}};      // bank 内行基址（增量维护）
    (* dont_touch="true" *) reg [AWB-1:0]   r_raddr = {AWB{1'b0}};       // bank 内读地址
    reg [1:0]       r_rbank = 2'd0;              // 与读地址同拍寄存的 bank 号

    always @(posedge I_pclk or negedge I_pclk_rst_n) begin
        if (!I_pclk_rst_n) begin
            r_sx6 <= {SWX_W{1'b0}}; r_sy6 <= {SWX_W{1'b0}};
            r_sx  <= 10'd0;         r_syb <= 10'd0;   r_bankr <= 2'd0;
            r_rsbase <= {AWB{1'b0}};
        end else if (I_vs) begin
            r_sx6 <= {SWX_W{1'b0}}; r_sy6 <= {SWX_W{1'b0}};
            r_sx  <= 10'd0;         r_syb <= 10'd0;   r_bankr <= 2'd0;
            r_rsbase <= {AWB{1'b0}};
        end else if (I_de) begin
            if (r_sx6 == SCALE[SWX_W-1:0] - 1'b1) begin
                r_sx6 <= {SWX_W{1'b0}};
                if (r_sx == SW - 1) begin
                    r_sx <= 10'd0;
                    if (r_sy6 == SCALE[SWX_W-1:0] - 1'b1) begin
                        r_sy6 <= {SWX_W{1'b0}};
                        if (r_syb == RPB - 1) begin
                            r_syb    <= 10'd0;             // 本 bank 读完 → 下一 bank
                            r_rsbase <= {AWB{1'b0}};
                            r_bankr  <= r_bankr + 1'b1;    // 2bit 自动回绕
                        end else begin
                            r_syb    <= r_syb + 1'b1;
                            r_rsbase <= r_rsbase + SW[AWB-1:0];
                        end
                    end else begin
                        r_sy6 <= r_sy6 + 1'b1;
                    end
                end else begin
                    r_sx <= r_sx + 1'b1;
                end
            end else begin
                r_sx6 <= r_sx6 + 1'b1;
            end
        end
    end

    always @(posedge I_pclk) begin
        r_raddr <= r_rsbase + r_sx;
        r_rbank <= r_bankr;
    end

    // Explicit synchronous read on each RAM before the bank mux.
    // Full address-space arrays above avoid the failed non-power-of-two mapping.
    // Preserve the existing address->data latency and bank selection cycle.
    reg [7:0] r_rd0, r_rd1, r_rd2, r_rd3;
    reg [1:0] r_rd_bank = 2'd0;
    always @(posedge I_pclk) begin
        r_rd0 <= r_fb0[r_raddr];
        r_rd1 <= r_fb1[r_raddr];
        r_rd2 <= r_fb2[r_raddr];
        r_rd3 <= r_fb3[r_raddr];
        r_rd_bank <= r_rbank;
    end
    wire [7:0] r_rd_data = (r_rd_bank == 2'd0) ? r_rd0 :
                           (r_rd_bank == 2'd1) ? r_rd1 :
                           (r_rd_bank == 2'd2) ? r_rd2 : r_rd3;

    // Address register + synchronous RAM read: delay DE through both stages.
    reg [1:0] r_de_d = 2'b00;
    always @(posedge I_pclk or negedge I_pclk_rst_n) begin
        if (!I_pclk_rst_n) r_de_d <= 2'b00;
        else               r_de_d <= {r_de_d[0], I_de};
    end
    assign O_de = r_de_d[1];

    assign O_rgb = {r_rd_data, r_rd_data, r_rd_data};

// Tap the same registered word that is written into the original preview RAM.
assign O_gray_sof=w_frame_rise;
assign O_gray_valid=(|r_we)&&!w_frame_rise;
assign O_gray_data=r_wr_data;
assign O_gray_last=O_gray_valid&&r_we[3]&&(r_wr_addr==RPB*SW-1);
endmodule
