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
//    - 字 0..WORDS-1 全是像素；帧号不占缓存，只在 FRAME_CNT 寄存器（0x4C）里
//    - 像素 pix = x[7:0] + y[7:0] + frame_cnt[7:0] + PIX_ADD
//      （主机可以按公式算任意位置的期望值，用于校验搬运正确性）
//
//  读口：只有**一个**，由主机预取与 DMA 读口共用，就在这里仲裁：
//    · host_rd_prio（来自 ep_bar_win）为 1 时读口必须给主机 —— 那是「端口刚
//      换了 ptr（一次 0x60 读或一次 0x5C 写），4 个字还没重新预取完」的情况，
//      这时不给主机，主机下一拍读 0x60 就会拿到过期数据；
//    · 否则 DMA 想读就把口给它；DMA 空闲时 host_grant 恒 1，
//      预取行为与以前完全一样（所以这是用仲裁代替「加第二个读口」）。
//    为什么加第二个读口不行：fb[] 会从 1W1R 变成 1W2R，实测 TD 无法把这个
//    三端口存储器落进 ERAM20K —— 一次实现用 ERAM、另一份落成 DRAM，
//    38600 个 dram lut 直接把 place 撞爆（日志 SYN-2599 + PHY-9009）。
//    ⇒ 共用唯一读口，ERAM 用量不变，主机读帧路径的时序假设也不变。
//    读数据按「上一拍的授权」分发给两个消费者，两边都仍是「地址→1 拍后数据」。
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
    output wire [31:0] rd_data,       // 读数据（1 拍延迟，且只在 host_grant 那拍成立）,
    input  wire        host_rd_prio,  // 1 = 主机的预取寄存器已经不是 ptr..ptr+12 → 读口必须给主机
    input  wire        dma_rd_req,    // 1 = DDR 搬运本拍想读一个字（ddr_frame_writer 的 fb_req）
    output wire        host_grant,    // 本拍读口归主机（DMA 借走时为 0）
    output wire        dma_grant,     // 本拍读口归 DMA（= !host_grant）
    input  wire [31:0] rd2_addr,      // DDR 搬运的读字节地址
    output wire [31:0] rd2_data,      // 给 DDR 搬运的读数据（1 拍延迟）
    output wire [31:0] dbg_rd_idx,    // 调试：内部字索引（低 17 位有效）

    output wire [31:0] frame_cnt,     // 已完成帧数（按写源选择）
    output wire [15:0] width,
    output wire [15:0] height,
    output wire [31:0] data_len,      // 每帧字节数
    output wire        ready,         // 至少出过一帧
    output wire        busy           // 正在写帧缓存（此间主机读会撕裂）
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

    // 内部状态
    reg [31:0]   frame_cnt_t, data_len_t;
    reg          ready_t, busy_t;

    reg          fb_wr_en;      // 测试图发生器的写口
    reg [AW-1:0] fb_wr_addr;
    reg [31:0]   fb_wr_data;

    // 保持「单条简单写语句」形式，否则 TD 会从 ERAM 落成分布式 RAM
    always @(posedge clk)
        if (fb_wr_en)
            fb[fb_wr_addr] <= fb_wr_data;

    // 状态输出（0x48 STATUS / 0x4C FRAME_CNT / 0x58 DATA_LEN）
    assign frame_cnt = frame_cnt_t;
    assign data_len  = data_len_t;
    assign ready     = ready_t;
    assign busy      = busy_t;

    // 读口按参考工程 f9p_ph1p100_imx415x2/cam_preview.v 的写法：
    // 组合读 + 输出寄存器（TD 对这个形式必推断 ERAM20K）
    wire [AW-1:0] rd_word_idx  = rd_addr[31:2];    // 先取字地址再截位（别用参数化位选）
    wire [AW-1:0] rd2_word_idx = rd2_addr[31:2];

    // 单口仲裁：主机预取一「脏」就优先，否则 DMA 借走
    assign host_grant = host_rd_prio | ~dma_rd_req;
    assign dma_grant  = ~host_grant;

    wire [AW-1:0] sel_word_idx = host_grant ? rd_word_idx : rd2_word_idx;
    wire [31:0]   w_fb_rdata   = fb[sel_word_idx];
    assign dbg_rd_idx = {15'd0, rd_word_idx};

    reg [31:0] fb_rdata_r;
    reg        grant_r;             // 上一拍读口归谁（数据比地址晚 1 拍）
    always @(posedge clk) begin
        fb_rdata_r <= w_fb_rdata;
        grant_r    <= host_grant;
    end

    // 两个消费者各自只看自己拿到口那一拍的数据
    //（主机侧还有 host_grant_q 做二次把关，见 ep_bar_win）
    assign rd_data  = grant_r ? fb_rdata_r : 32'd0;
    assign rd2_data = grant_r ? 32'd0 : fb_rdata_r;

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
                // 字 0 也是像素（帧号不再占缓存）：从 widx=0 起逐字写满 WORDS-1
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

endmodule
