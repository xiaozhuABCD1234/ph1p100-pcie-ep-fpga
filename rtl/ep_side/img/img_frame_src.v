///////////////////////////////////////////////////////////////
//  img_frame_src.v — PCIe EP 图像通路：测试图源 + 帧缓存
//
//  设计约定（抄自 f9p_ph1p100_imx415x2 的踩坑记录）：
//   1) 帧缓存必须写成"简单写口" —— 单条 `if (wr_en) mem[a] <= d;`、
//      不带复位、不写多分支，TD 才会推断成 ERAM20K 硬块；
//      一旦带复位/多分支就落成分布式 RAM（LUT），几万字节直接撑爆器件。
//   2) 320x240 灰度 = 76,800 B = 19,200 字，约 30 块 ERAM20K。
//      再往上（640x480 = 120 块）要先按参考工程做法把帧缓存拆 bank，
//      否则块间的读多路选择会成为关键路径。
//
//  数据布局（主机侧看到的就是一坨 8bit 灰度）：
//    - 1 字节 1 像素，4 像素/32bit 字，小端（x 小的在低字节）
//    - 字 0 = 帧号 frame_cnt[31:0]（小端），便于主机校验帧同步
//    - 其余像素 pix = x[7:0] + y[7:0] + frame_cnt[7:0] + PIX_ADD
//      （主机可以按公式算任意位置的期望值，用于校验搬运正确性）
///////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module img_frame_src #(
    parameter       W          = 320,      // 宽（必须是 4 的倍数）
    parameter       H          = 240,      // 高
    parameter       IDLE_CYCLE = 1000000,  // 帧间空闲周期（125MHz 下 1e6 ≈ 8ms）
    parameter [7:0] PIX_ADD    = 8'h00     // 像素公式附加常量（调试用）
)(
    input  wire        clk,
    input  wire        rst,

    input  wire        enable,        // 1 = 连续出帧
    input  wire        trigger,       // 单帧触发（1 拍脉冲）

    input  wire [31:0] rd_addr,       // 帧缓存读字节地址（来自寄存器块）
    output wire [31:0] rd_data,       // 读数据（1 拍延迟）,
    output wire [31:0] dbg_rd_idx,    // 调试：内部字索引（低 17 位有效）

    output reg  [31:0] frame_cnt,     // 已完成帧数
    output wire [15:0] width,
    output wire [15:0] height,
    output reg  [31:0] data_len,      // 每帧字节数
    output reg         ready,         // 至少出过一帧
    output reg         busy           // 正在写帧缓存（此间主机读会撕裂）
);

    localparam WORDS = (W * H) / 4;

    function integer clogb2;
        input integer v;
        integer i;
        begin
            clogb2 = 0;
            for (i = v - 1; i > 0; i = i >> 1)
                clogb2 = clogb2 + 1;
        end
    endfunction

    localparam AW = clogb2(WORDS);      // 字地址位宽

    assign width  = W[15:0];
    assign height = H[15:0];

    // ------------------------------------------------------------------
    // 帧缓存：写口（简单形式 → ERAM20K）+ 读口（输出带寄存器）
    // ------------------------------------------------------------------
    reg [31:0] fb [0:WORDS-1];

    reg          fb_wr_en;
    reg [AW-1:0] fb_wr_addr;
    reg [31:0]   fb_wr_data;

    always @(posedge clk)
        if (fb_wr_en)
            fb[fb_wr_addr] <= fb_wr_data;

    // 读口按参考工程 f9p_ph1p100_imx415x2/cam_preview.v 的写法：
    // 组合读 + 输出寄存器（TD 对这个形式必推断 ERAM20K）
    wire [AW-1:0] rd_word_idx = rd_addr[31:2];   // 先取字地址再截位（别用参数化位选）
    wire [31:0]   w_fb_rdata = fb[rd_word_idx];
    assign dbg_rd_idx = {15'd0, rd_word_idx};

    reg [31:0] rd_data_r;
    always @(posedge clk)
        rd_data_r <= w_fb_rdata;

    assign rd_data = rd_data_r;

    // ------------------------------------------------------------------
    // 测试图发生器（每 4 拍组一个 32bit 字）
    // ------------------------------------------------------------------
    reg [15:0]   x, y;
    reg [1:0]    lane;
    reg [AW-1:0] widx;
    reg [31:0]   wr_word;
    reg [31:0]   idle;

    // 一个 32bit 字装 4 个像素：第 j 个字节 = (x+j) + y + 帧号
    wire [7:0] pix_now = x[7:0] + y[7:0] + {6'd0, lane} + frame_cnt[7:0] + PIX_ADD;

    wire start = (enable | trigger) && ((ready == 1'b0) || (idle >= IDLE_CYCLE));

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy       <= 1'b0;
            ready      <= 1'b0;
            frame_cnt  <= 32'd0;
            data_len   <= 32'd0;
            fb_wr_en   <= 1'b0;
            fb_wr_addr <= {AW{1'b0}};
            fb_wr_data <= 32'd0;
            x          <= 16'd0;
            y          <= 16'd0;
            lane       <= 2'd0;
            widx       <= {AW{1'b0}};
            wr_word    <= 32'd0;
            idle       <= 32'd0;
        end else begin
            fb_wr_en <= 1'b0;

            if (!busy) begin
                if (start) begin
                    busy  <= 1'b1;
                    ready <= 1'b0;
                    x     <= 16'd0;
                    y     <= 16'd0;
                    lane  <= 2'd0;
                    widx  <= {AW{1'b0}};
                    idle  <= 32'd0;
                end else if (idle < IDLE_CYCLE) begin
                    idle <= idle + 32'd1;
                end
            end else begin
                if (widx == {AW{1'b0}}) begin
                    // 字 0：帧号
                    fb_wr_en   <= 1'b1;
                    fb_wr_addr <= {AW{1'b0}};
                    fb_wr_data <= frame_cnt;
                    widx       <= {{(AW-1){1'b0}}, 1'b1};
                end else begin
                    wr_word <= {pix_now, wr_word[31:8]};

                    if (lane == 2'd3) begin
                        fb_wr_en   <= 1'b1;
                        fb_wr_addr <= widx;
                        fb_wr_data <= {pix_now, wr_word[31:8]};
                        lane       <= 2'd0;

                        if (widx == (WORDS - 1)) begin
                            // 一帧结束
                            busy      <= 1'b0;
                            ready     <= 1'b1;
                            frame_cnt <= frame_cnt + 32'd1;
                            data_len  <= W * H;
                        end else begin
                            widx <= widx + 1'b1;
                            // 一个 32bit 字含 4 个像素 → x 前进 4
                            if (x + 16'd4 >= W) begin
                                x <= 16'd0;
                                y <= y + 16'd1;
                            end else begin
                                x <= x + 16'd4;
                            end
                        end
                    end else begin
                        lane <= lane + 2'd1;
                    end
                end
            end
        end
    end

endmodule
