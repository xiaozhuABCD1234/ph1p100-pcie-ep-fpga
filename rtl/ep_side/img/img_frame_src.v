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
//
//  写源选择（本移植新增）：
//    - cam_sel=0（默认）：测试图发生器写帧缓存，布局/时序与之前完全一样；
//    - cam_sel=1        ：写口与状态字改由 cam_fb_writer（IMX415/CIS-2）提供，
//                         布局不变（字 0 = 帧号 = FRAME_CNT，之后 4 像素/字）。
//    两种写源都只是「同一块 fb[] 的写口」在 mux，不会同时写也不会写坏地址。
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

    output wire [31:0] frame_cnt,     // 已完成帧数（按写源选择）
    output wire [15:0] width,
    output wire [15:0] height,
    output wire [31:0] data_len,      // 每帧字节数
    output wire        ready,         // 至少出过一帧
    output wire        busy,          // 正在写帧缓存（此间主机读会撕裂）

    // ---- 外部（相机）写源：cam_sel=1 时写口由 cam_fb_writer 驱动 ----
    input  wire        cam_sel,       // 1 = 相机写源（CTRL[4]），0 = 测试图源
    input  wire        cam_wr_en,
    input  wire [31:0] cam_wr_addr,   // 写字节地址（低 2 位恒 0）
    input  wire [31:0] cam_wr_data,
    input  wire [31:0] cam_frame_cnt, // 相机侧已完成帧数
    input  wire [31:0] cam_data_len,
    input  wire        cam_ready,
    input  wire        cam_busy
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

    // 内部状态（带 _t 后缀）：对外按写源 mux（声明必须早于下面的 assign）
    reg [31:0]   frame_cnt_t, data_len_t;
    reg          ready_t, busy_t;

    reg          fb_wr_en;      // 测试图发生器的写口
    reg [AW-1:0] fb_wr_addr;
    reg [31:0]   fb_wr_data;

    // 相机写口：字节地址 → 字索引（截位方式与读口一致：先取[31:2]再截到 AW 位）
    wire [AW-1:0] cam_word_idx = cam_wr_addr[31:2];

    // 写源选择：0 = 测试图发生器（默认，向后兼容），1 = 相机（cam_fb_writer）
    wire          fb_wr_en_m   = cam_sel ? cam_wr_en    : fb_wr_en;
    wire [AW-1:0] fb_wr_addr_m = cam_sel ? cam_word_idx : fb_wr_addr;
    wire [31:0]   fb_wr_data_m = cam_sel ? cam_wr_data  : fb_wr_data;

    // 保持「单条简单写语句」形式，否则 TD 会从 ERAM 落成分布式 RAM
    always @(posedge clk)
        if (fb_wr_en_m)
            fb[fb_wr_addr_m] <= fb_wr_data_m;

    // 状态输出同样按写源选择（0x48 STATUS / 0x4C FRAME_CNT / 0x58 DATA_LEN）
    assign frame_cnt = cam_sel ? cam_frame_cnt : frame_cnt_t;
    assign data_len  = cam_sel ? cam_data_len  : data_len_t;
    assign ready     = cam_sel ? cam_ready     : ready_t;
    assign busy      = cam_sel ? cam_busy      : busy_t;

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
    wire [7:0] pix_now = x[7:0] + y[7:0] + {6'd0, lane} + frame_cnt_t[7:0] + PIX_ADD;

    wire start = (enable | trigger) && ((ready_t == 1'b0) || (idle >= IDLE_CYCLE));

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy_t       <= 1'b0;
            ready_t      <= 1'b0;
            frame_cnt_t  <= 32'd0;
            data_len_t   <= 32'd0;
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

            if (!busy_t) begin
                if (start) begin
                    busy_t  <= 1'b1;
                    ready_t <= 1'b0;
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
                    fb_wr_data <= frame_cnt_t;
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
                            busy_t      <= 1'b0;
                            ready_t     <= 1'b1;
                            frame_cnt_t <= frame_cnt_t + 32'd1;
                            data_len_t  <= W * H;
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
