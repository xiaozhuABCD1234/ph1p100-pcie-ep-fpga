///////////////////////////////////////////////////////////////////////////////
//  ddr_frame_writer.v — 把片内整帧缓存（img_frame_src 的 ERAM fb[]）整帧搬进
//  板上 DDR3（AXI4 突发），双缓冲 + 「第几帧写好了 / 写到哪块」握手。
//
//  ===========================================================================
//  一、它接什么
//  ===========================================================================
//   · 片内侧：img_frame_src 的帧缓存读口（rd_addr / rd_data）。这个读口只有一份，
//     与主机读 0x60 的预取共用，仲裁在 img_frame_src 里（见该文件头部）：
//     本模块用 fb_req 说「这一拍我想读一个字」，拿到 fb_grant 那一拍才发地址。
//     为什么不用「再加一个读口」：实测那张 1W2R 的 fb[] 落不进 ERAM20K，
//     一份进 ERAM、另一份被 TD 落成 DRAM（38600 dram lut），place 直接撞爆
//     （syn_1 日志 SYN-2599 + phy_1 日志 PHY-9009 超过 mslice 限额）。
//     写源 mux 之后的帧计数器 fb_frame_cnt / busy 也从那里来。
//     「字 0..76799 全是像素，4 像素/32bit 字，低字节 = 最左像素」（帧号不占
//     缓存，它只在 0x4C / 0xA0 这些计数器寄存器里），本模块不做任何格式转换、
//     逐字搬，所以 DDR 里读到的字节序与片内逐字节一致（整块都是像素）。
//   · DDR 侧：u_ddr3_mc_0 的 AXI4 写通道（axi_aclk = dhi_clk = IP 的 usr_clk，
//     100MHz；axi_aresetn = ddrphy_rst_n）。数据 256bit = 32 字节/拍。
//     地址是**字节地址**：IP 里 AXI_ADDR_WIDTH(29) = MC_ADDR_WIDTH(27) +
//     clog2(MC_DATA_WIDTH/8) - 3 = 27 + 5 - 3，即 MC 的 27 位是 32bit DRAM 字
//     地址，AXI 再补 2 位字节偏移（见 al_ip/ddr3_mc_0/ddr3_mc_0.v 的参数表）。
//
//  ===========================================================================
//  二、双缓冲（为什么、怎么算）
//  ===========================================================================
//   两块固定基址 BASE0 / BASE1（模块参数，别处不再出现魔数），按帧号奇偶交替：
//       base = seq[0] ? BASE1 : BASE0
//   这样主机正在读的那一块，下一帧不会被覆盖（被覆盖的总是另一块）。
//   两块都必须 ≥ FRAME_BYTES 且 4KB 对齐 —— AXI4 规定一个突发不得跨 4KB 边界，
//   而本模块每个突发正好 4KB（BURST_BEATS × 32B = 128 × 32 = 4096）。
//
//  ===========================================================================
//  三、数据流与跨时钟域（照工程既有做法，别自创）
//  ===========================================================================
//    fb 域（tl_clk_user 62.5MHz）                        ddr 域（usr_clk 100MHz）
//    ───────────────────────────────                     ───────────────────────
//    帧号变化 ⇒ 锁存 seq/base，req_level=1
//    8 个字拼成 1 拍 256bit ─▶ 异步 FIFO（格雷码指针）─▶ 1 拍 1 拍喂 AXI
//      （拿到 fb_grant 才读一个字；FIFO 满同样暂停，不丢字）  每 4KB 一个突发
//    发布 seq/base ◀─ 2 级同步器（done 电平）◀── 所有 bresp 收齐 ⇒ done_level=1
//
//   · 异步 FIFO：与 cam_fb_writer.v 里那个同一套写法（格雷码指针 + 2 级同步器 +
//     简单写口 / 输出寄存器读口 ⇒ TD 推 ERAM20K）。每拍 256bit = 8 个 32bit 字。
//   · 请求/基址（fb→ddr）：req_level 是电平，base_lat 在 req_level=1 期间**不变**；
//     ddr 侧用 2 级同步器采 req_level，看到 1 时 base_s2 早就稳了（≥2 拍）——
//     即工程里的「单比特电平同步 + 数据保持不动」那一类做法
//     （cam_fb_writer 的 FIFO 指针、顶层的三级打拍是同族写法）。
//   · done / err（ddr→fb）：同样 2 级同步器；fb 侧用 done_s2 & ~done_s3 取上升沿。
//     err_sticky 总比 done_level 早 ≥1 个 ddr 周期置起（见 A_B 分支），
//     所以采样 done 上升沿时 derr_s2 已稳定（余量 ≥1 ddr + 1 fb 周期）。
//   · 复位：ddr 域用 ddrphy_rst_n（= axi_aresetn）；fb 域除 power_on_rst 之外，
//     再叠加「ddr 域已出复位」这个同步过来的电平 —— DDR 侧一复位，FIFO 写指针、
//     请求、FILL 状态机跟着一起归零（ddr 侧读指针由 ddrphy_rst_n 归零），
//     避免一端归零另一端不归零导致后续帧在 FIFO 里错位。
//
//  ===========================================================================
//  四、出错与「不虚报」
//  ===========================================================================
//   · torn（撕裂）：搬运期间 fb 又被新一帧写入（busy 拉高）⇒ 这一帧内容不完整，
//     不发布、err_cnt+1。640x480 一帧搬运百微秒级、相机一帧 33ms，正常不会发生，
//     真发生了必须让主机看得出来（DDR_STATUS.bit2 + 0x4C FRAME_CNT 的跳号）。
//   · AXI 非 OKAY：bresp != 2'b00 ⇒ 不发布、err_cnt+1。
//   · FIFO 满：暂停读 fb（不丢字，宁可慢）。DDR 侧若始终不给 awready（例如校准没过），
//     就永远 busy、永不发布 —— 宁可主机看到「还没好」，也不虚报一帧。
//
//  ===========================================================================
//  五、寄存器（沿用 ep_bar_win.v 那张表；偏移与位定义见该文件头部）
//  ===========================================================================
//    0xA0 DDR_FRAME_SEQ R  已整帧落 DDR3 的帧号（单调递增，取自帧计数器）
//    0xA4 DDR_BASE      R  该帧在 DDR3 中的字节基址
//    0xA8 DDR_STATUS    R  bit0 valid / bit1 busy / bit2 err / bit3 alive /
//                          bit4 cal_done / [31:16] err_cnt
//    0xAC DDR_LEN       R  每帧字节数
//    CTRL bit5 = ddr_en：0 = 不搬（复位默认），1 = 每完成一帧自动搬。
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module ddr_frame_writer #(
    // ---- 帧几何：与 img_frame_src / cam_fb_writer 用同一组 W/H ----
    parameter integer W           = 640,
    parameter integer H           = 480,
    // ---- DDR3 里双缓冲的两个固定基址（字节）----
    //   两块都要 ≥ FRAME_BYTES、4KB 对齐、互不重叠（默认 1MB / 1.5MB，
    //   间隔 512KB > 307200B）。基址只在这里出现，别处不写魔数。
    parameter [31:0]  BASE0       = 32'h0010_0000,
    parameter [31:0]  BASE1       = 32'h0018_0000,
    // ---- 跨时钟 FIFO 深度 = 2**FIFO_AW 拍（每拍 256bit）----
    parameter integer FIFO_AW     = 5,
    // ---- 每个 AXI 突发的拍数（awlen = BURST_BEATS-1）；必须整除 NBEATS ----
    parameter integer BURST_BEATS = 128
)(
    // ---------------- 片内帧缓存域（tl_clk_user，62.5MHz）----------------
    input  wire         clk_fb,
    input  wire         rst_fb,        // 高有效（power_on_rst_dly）
    input  wire         ddr_en,        // CTRL[5]：1 = 每完成一帧自动搬
    input  wire [31:0]  fb_frame_cnt,  // 帧计数器（写源 mux 之后）；变化 = 一帧已写好
    input  wire         fb_busy,       // 帧缓存正在被写入（新一帧已开始）
    output wire [31:0]  fb_rd_addr,    // 共用读口地址（字节，低 2 位恒 0）
    input  wire [31:0]  fb_rd_data,    // 该地址的数据（1 拍延迟）
    output wire         fb_req,        // 本拍想读一个字（交给 img_frame_src 仲裁）
    input  wire         fb_grant,      // 本拍读口给了我们（= img_frame_src 的 dma_grant）

    // ---------------- DDR 用户域（u_ddr3_mc_0/usr_clk，100MHz）----------------
    input  wire         clk_ddr,
    input  wire         rst_ddr,       // 高有效（= !ddrphy_rst_n = !axi_aresetn）
    input  wire         ddr_cal_done,  // = ddrphy_rdy（DDRPHY 校准完成）

    // ---------------- AXI4 写通道（接 u_ddr3_mc_0，256bit）----------------
    output reg  [28:0]  m_axi_awaddr,
    output reg  [7:0]   m_axi_awlen,
    output wire [2:0]   m_axi_awsize,
    output wire [1:0]   m_axi_awburst,
    output reg          m_axi_awvalid,
    input  wire         m_axi_awready,
    output wire [255:0] m_axi_wdata,
    output wire [31:0]  m_axi_wstrb,
    output wire         m_axi_wlast,
    output wire         m_axi_wvalid,
    input  wire         m_axi_wready,
    input  wire [1:0]   m_axi_bresp,
    input  wire         m_axi_bvalid,
    output wire         m_axi_bready,

    // ---------------- 握手（fb 域，供寄存器读）----------------
    output reg  [31:0]  wr_frame_seq,  // 已整帧落 DDR3 的帧号
    output reg  [31:0]  wr_base,       // 该帧基址
    output reg  [31:0]  wr_status,     // 位定义见文件头
    output wire [31:0]  wr_len         // 每帧字节数
);

    // ========================================================================
    //  参数推导（只在这里出现，别处不散落魔数）
    // ========================================================================
    localparam integer BEAT_BYTES     = 32;                      // 256bit / 8
    localparam integer WORDS_PER_BEAT = BEAT_BYTES / 4;          // 每拍 8 个 32bit 字
    localparam integer FRAME_BYTES    = W * H;                    // 1 字节 1 像素
    localparam integer FB_WORDS       = FRAME_BYTES / 4;          // 帧缓存字数
    localparam integer NBEATS         = FRAME_BYTES / BEAT_BYTES; // 每帧 AXI 拍数
    localparam integer NBURST         = NBEATS / BURST_BEATS;     // 每帧突发数
    localparam integer BURST_BYTES    = BURST_BEATS * BEAT_BYTES; // 每突发字节数
    localparam [31:0]  WR_LEN_W       = W * H;
    localparam [31:0]  FB_LAST_ADDR   = (FB_WORDS - 1) * 4;       // 末字字节地址

    localparam [2:0]   AXI_SIZE       = 3'd5;    // 2**5 = 32 字节/拍
    localparam [1:0]   AXI_BURST      = 2'b01;   // INCR
    localparam [28:0]  BURST_STEP     = BURST_BYTES;

    function integer clogb2;
        input integer v;
        integer i;
        begin
            clogb2 = 0;
            for (i = v - 1; i > 0; i = i >> 1)
                clogb2 = clogb2 + 1;
        end
    endfunction

    localparam integer BEAT_CW  = clogb2(BURST_BEATS);  // 突发内拍计数位宽
    localparam integer BURST_CW = clogb2(NBURST);       // 突发计数位宽

    function [FIFO_AW:0] bin2gray;
        input [FIFO_AW:0] b;
        begin
            bin2gray = b ^ (b >> 1);
        end
    endfunction

    // ========================================================================
    //  跨时钟域信号（声明放前面，免得 TD 当隐式网）
    // ========================================================================
    reg         req_level;      // fb 域：搬运请求电平（ddr 侧收到 done 后由 fb 侧撤）
    reg  [31:0] base_lat;       // fb 域：本帧基址（req_level=1 期间保持不变）
    reg         done_level;     // ddr 域：本帧全部写完（等 fb 侧撤请求）
    reg         err_sticky;     // ddr 域：本帧出了 AXI 错

    // ========================================================================
    //  ddr → fb 域的同步器（全部是电平，2 级打拍）
    // ========================================================================
    reg  alive_s1, alive_s2;               // ddr 域已出复位
    reg  cal_s1,   cal_s2;                 // DDRPHY 校准完成
    reg  done_s1,  done_s2, done_s3;       // 本帧响应全收齐
    reg  derr_s1,  derr_s2;                // 本帧出了错

    wire alive = ~rst_ddr;

    always @(posedge clk_fb or posedge rst_fb) begin
        if (rst_fb) begin
            alive_s1 <= 1'b0; alive_s2 <= 1'b0;
            cal_s1   <= 1'b0; cal_s2   <= 1'b0;
            done_s1  <= 1'b0; done_s2  <= 1'b0; done_s3 <= 1'b0;
            derr_s1  <= 1'b0; derr_s2  <= 1'b0;
        end else begin
            alive_s1 <= alive;          alive_s2 <= alive_s1;
            cal_s1   <= ddr_cal_done;   cal_s2   <= cal_s1;
            done_s1  <= done_level;     done_s2  <= done_s1;  done_s3 <= done_s2;
            derr_s1  <= err_sticky;     derr_s2  <= derr_s1;
        end
    end

    // 上升沿：done_s2 已经稳住 1、done_s3 还是 0 的那一拍
    wire done_pulse = done_s2 & ~done_s3;

    // DDR 侧一复位，fb 侧的状态机 / FIFO 写指针 / 请求一起归零（见文件头「复位」）
    wire rst_all_fb = rst_fb | ~alive_s2;

    // ========================================================================
    //  fb 域：帧完成检测 → 顺序读 fb → 拼 256bit 拍 → 入队
    // ========================================================================
    localparam [1:0] F_IDLE = 2'd0,   // 等帧计数器变化
                     F_FILL = 2'd1,   // 正在读 fb 并推进 FIFO
                     F_WAIT = 2'd2;   // 数据全进了 FIFO，等 DDR 侧搬完

    reg [31:0]  prev_cnt;
    reg [1:0]   f_st;
    reg [31:0]  seq_lat;
    reg         torn;
    reg [31:0]  iacnt;      // 已发出的读地址数（字）
    reg [31:0]  rcnt;       // 已回收的字数
    reg [2:0]   lane;       // 本拍已收到第几个字（0..7）
    reg [255:0] pack;
    reg         rd_go_d;    // 读地址发出的下一拍：fb_rd_data 有效
    reg [15:0]  err_cnt;
    reg         valid_r;

    // ---- 异步 FIFO（简单写口 + 输出寄存器读口，格雷码指针）----
    reg  [255:0]     f_mem [0:(1 << FIFO_AW) - 1];
    reg  [FIFO_AW:0] wptr_bin,  wptr_gray;
    reg  [FIFO_AW:0] rptr_bin,  rptr_gray;
    reg  [FIFO_AW:0] wgray_s1,  wgray_s2;    // 写指针 → ddr 域
    reg  [FIFO_AW:0] rgray_s1,  rgray_s2;    // 读指针 → fb 域

    wire [FIFO_AW:0] wptr_bin_nxt  = wptr_bin  + {{FIFO_AW{1'b0}}, 1'b1};
    wire [FIFO_AW:0] wptr_gray_nxt = bin2gray(wptr_bin_nxt);
    wire [FIFO_AW:0] rptr_bin_nxt  = rptr_bin  + {{FIFO_AW{1'b0}}, 1'b1};
    wire [FIFO_AW:0] rptr_gray_nxt = bin2gray(rptr_bin_nxt);

    wire wfull = (wptr_gray_nxt == {~rgray_s2[FIFO_AW:FIFO_AW-1], rgray_s2[FIFO_AW-2:0]});

    // 读地址：顺序走 0,4,8,...；越界时钉在末字上（读口没有读使能，地址必须始终在范围内）
    assign fb_rd_addr = (iacnt < FB_WORDS) ? {iacnt[29:0], 2'b00} : FB_LAST_ADDR;

    // 读地址发出条件：只在「开一拍」（lane==0）时看 FIFO 满。
    // 为什么这样是安全的：一拍 8 个字期间 wptr 不动（一拍只 push 一次），
    // 所以 wfull 只可能由 1 变 0（ddr 侧只会 pop），不会由 0 变 1 ——
    // 开拍时不满，push 时一定还是不满，一拍正好占一个空位。
    wire rd_go = (f_st == F_FILL) && (iacnt < FB_WORDS) && ((lane != 3'd0) || ~wfull)
                 && fb_grant;                       // 拿到读口那一拍才算发出地址
    wire d_vld = rd_go_d;                                            // 数据比地址晚 1 拍
    assign fb_req = (f_st == F_FILL) && (iacnt < FB_WORDS) && ((lane != 3'd0) || ~wfull);

    // 第 8 个字到手那一拍凑满一拍：lane k 的字放 [32k +: 32]，与 AXI 字节序一致
    // （wdata[7:0] 就是基址+0 那个字节，wstrb 全 1）
    wire         push     = d_vld & (lane == 3'd7);
    wire [255:0] pack_nxt = {fb_rd_data, pack[223:0]};

    // 帧号一变就开一帧：清零所有读侧计数（与状态机在同一拍生效，故单独成线）
    wire fill_req = (f_st == F_IDLE) & ddr_en & alive_s2 & (fb_frame_cnt != prev_cnt);

    // 写口：单条简单写语句 + 无复位（TD 推断 ERAM20K 的关键，别加分支）
    always @(posedge clk_fb)
        if (push) f_mem[wptr_bin[FIFO_AW-1:0]] <= pack_nxt;

    always @(posedge clk_fb or posedge rst_all_fb) begin
        if (rst_all_fb) begin
            wptr_bin  <= {(FIFO_AW+1){1'b0}};
            wptr_gray <= {(FIFO_AW+1){1'b0}};
        end else if (push) begin
            wptr_bin  <= wptr_bin_nxt;
            wptr_gray <= wptr_gray_nxt;
        end
    end

    always @(posedge clk_fb or posedge rst_all_fb) begin   // 读指针 → fb 域
        if (rst_all_fb) begin rgray_s1 <= {(FIFO_AW+1){1'b0}}; rgray_s2 <= {(FIFO_AW+1){1'b0}}; end
        else begin rgray_s1 <= rptr_gray; rgray_s2 <= rgray_s1; end
    end

    // ---- 逐字拼拍（iacnt/rcnt/lane/pack 只在本块里赋值）----
    always @(posedge clk_fb or posedge rst_all_fb) begin
        if (rst_all_fb) begin
            rd_go_d <= 1'b0;
            iacnt   <= 32'd0;
            rcnt    <= 32'd0;
            lane    <= 3'd0;
            pack    <= 256'd0;
        end else if (fill_req) begin
            rd_go_d <= 1'b0;          // 新一帧从字 0 重新开始
            iacnt   <= 32'd0;
            rcnt    <= 32'd0;
            lane    <= 3'd0;
            pack    <= 256'd0;
        end else begin
            rd_go_d <= rd_go;
            if (rd_go) iacnt <= iacnt + 32'd1;
            if (d_vld) begin
                rcnt <= rcnt + 32'd1;
                lane <= (lane == 3'd7) ? 3'd0 : (lane + 3'd1);
                case (lane)
                    3'd0: pack[31:0]    <= fb_rd_data;
                    3'd1: pack[63:32]   <= fb_rd_data;
                    3'd2: pack[95:64]   <= fb_rd_data;
                    3'd3: pack[127:96]  <= fb_rd_data;
                    3'd4: pack[159:128] <= fb_rd_data;
                    3'd5: pack[191:160] <= fb_rd_data;
                    3'd6: pack[223:192] <= fb_rd_data;
                    3'd7: pack[255:224] <= fb_rd_data;   // 这一拍同时 push，用 pack_nxt
                endcase
            end
        end
    end

    // ---- 帧完成检测 / 搬运状态机 / 握手寄存器 ----
    //  复位一起用 rst_all_fb（含「DDR 域已出复位」）：DDR 侧一复位，本状态机连同
    //  FIFO 写指针、请求一起归零；ddr 侧读指针由 ddrphy_rst_n 归零 ⇒ 两端都回到 0，
    //  不会出现「只剩一端没归零」导致后续帧在 FIFO 里错位。
    wire [31:0] status_nxt = {err_cnt, 11'd0, cal_s2, alive_s2, (err_cnt != 16'd0),
                              (f_st != F_IDLE), valid_r};

    assign wr_len = WR_LEN_W;

    always @(posedge clk_fb or posedge rst_all_fb) begin
        if (rst_all_fb) begin
            prev_cnt     <= 32'd0;
            f_st         <= F_IDLE;
            seq_lat      <= 32'd0;
            base_lat     <= BASE0;
            req_level    <= 1'b0;
            torn         <= 1'b0;
            err_cnt      <= 16'd0;
            valid_r      <= 1'b0;
            wr_frame_seq <= 32'd0;
            wr_base      <= 32'd0;
            wr_status    <= 32'd0;
        end else begin
            wr_status <= status_nxt;

            case (f_st)
                F_IDLE: begin
                    // 帧计数器一变就说明「有一整帧已在 fb[] 里」。当前值就是最新那帧，
                    // 直接按它搬（ddr_en=0 或 DDR 没就绪期间的变化被吸收掉，不补搬）。
                    if (fill_req) begin
                        prev_cnt  <= fb_frame_cnt;
                        seq_lat   <= fb_frame_cnt;
                        base_lat  <= fb_frame_cnt[0] ? BASE1 : BASE0;
                        torn      <= 1'b0;
                        req_level <= 1'b1;
                        f_st      <= F_FILL;
                    end else begin
                        prev_cnt <= fb_frame_cnt;
                    end
                end

                F_FILL: begin
                    if (fb_busy) torn <= 1'b1;             // 新一帧开始写 fb ⇒ 本帧内容被撕
                    if (rcnt == FB_WORDS) f_st <= F_WAIT;   // 整帧已进 FIFO
                end

                F_WAIT: begin
                    if (done_pulse) begin
                        if (~torn & ~derr_s2) begin
                            wr_frame_seq <= seq_lat;        // 只有整帧确认落 DDR 才发布
                            wr_base      <= base_lat;
                            valid_r      <= 1'b1;
                        end else begin
                            err_cnt <= err_cnt + 16'd1;      // 撕裂 / AXI 错：不发布
                        end
                        req_level <= 1'b0;
                        f_st      <= F_IDLE;
                    end
                end

                default: f_st <= F_IDLE;
            endcase
        end
    end

    // ========================================================================
    //  ddr 域：AXI4 写通道（一次一个 4KB 突发，收齐 bresp 再发下一个）
    // ========================================================================
    localparam [2:0] A_IDLE = 3'd0,   // 等请求
                     A_AW   = 3'd1,   // 发写地址
                     A_W    = 3'd2,   // 灌 256bit 数据
                     A_B    = 3'd3,   // 收写响应
                     A_DONE = 3'd4;   // 抬起 done_level，等 fb 侧撤请求

    reg  [2:0]         a_st;
    reg  [28:0]        addr_r;
    reg  [BEAT_CW-1:0] beat;
    reg  [BURST_CW-1:0] bcnt;

    // fb → ddr 的同步器
    reg        req_s1,  req_s2;
    reg [31:0] base_s1, base_s2;

    always @(posedge clk_ddr or posedge rst_ddr) begin
        if (rst_ddr) begin
            req_s1  <= 1'b0;  req_s2  <= 1'b0;
            base_s1 <= 32'd0; base_s2 <= 32'd0;
        end else begin
            req_s1  <= req_level;  req_s2  <= req_s1;
            base_s1 <= base_lat;   base_s2 <= base_s1;
        end
    end

    // ---- FIFO 读出：1 条 skid 缓冲（f_dout 上那拍被 AXI 吃掉的那一拍就把下一拍装好，
    //      所以 steady state 是 1 拍 1 个 beat；FIFO 空、AXI 不 ready 时都自然停住）----
    reg         hold;      // f_dout 上有一拍还没被 AXI 吃掉
    reg [255:0] f_dout;

    wire wempty = (rptr_gray == wgray_s2);
    // pop：取下一拍装进 f_dout。hold=0 ⇒ 空手等；hold=1 ⇒ 当前这拍被吃掉的同一拍预取下一拍
    wire pop    = (a_st == A_W) & ~wempty & (~hold | m_axi_wready);

    always @(posedge clk_ddr) if (pop) f_dout <= f_mem[rptr_bin[FIFO_AW-1:0]];

    always @(posedge clk_ddr or posedge rst_ddr) begin
        if (rst_ddr) begin
            hold      <= 1'b0;
            rptr_bin  <= {(FIFO_AW+1){1'b0}};
            rptr_gray <= {(FIFO_AW+1){1'b0}};
        end else begin
            if (pop) begin
                hold      <= 1'b1;
                rptr_bin  <= rptr_bin_nxt;
                rptr_gray <= rptr_gray_nxt;
            end else if (hold & m_axi_wready) begin
                hold <= 1'b0;    // 吃掉了、后面也没得预取
            end
        end
    end

    always @(posedge clk_ddr or posedge rst_ddr) begin   // 写指针 → ddr 域
        if (rst_ddr) begin wgray_s1 <= {(FIFO_AW+1){1'b0}}; wgray_s2 <= {(FIFO_AW+1){1'b0}}; end
        else begin wgray_s1 <= wptr_gray; wgray_s2 <= wgray_s1; end
    end

    // ---- AXI 通道（组合输出）----
    assign m_axi_awsize  = AXI_SIZE;
    assign m_axi_awburst = AXI_BURST;
    assign m_axi_wdata   = f_dout;
    assign m_axi_wstrb   = {32{1'b1}};
    assign m_axi_wvalid  = hold & (a_st == A_W);
    assign m_axi_wlast   = hold & (a_st == A_W) & (beat == BURST_BEATS - 1);
    assign m_axi_bready  = (a_st == A_B);

    always @(posedge clk_ddr or posedge rst_ddr) begin
        if (rst_ddr) begin
            a_st          <= A_IDLE;
            addr_r        <= 29'd0;
            m_axi_awaddr  <= 29'd0;
            m_axi_awlen   <= BURST_BEATS - 1;
            m_axi_awvalid <= 1'b0;
            beat          <= {BEAT_CW{1'b0}};
            bcnt          <= {BURST_CW{1'b0}};
            done_level    <= 1'b0;
            err_sticky    <= 1'b0;
        end else begin
            case (a_st)
                A_IDLE: if (req_s2) begin
                    // base_lat 从请求拉高到本帧结束一直在那儿不动，2 级同步后已是稳定值
                    addr_r        <= base_s2[28:0];
                    m_axi_awaddr  <= base_s2[28:0];
                    bcnt          <= {BURST_CW{1'b0}};
                    beat          <= {BEAT_CW{1'b0}};
                    m_axi_awvalid <= 1'b1;
                    err_sticky    <= 1'b0;
                    a_st          <= A_AW;
                end

                A_AW: if (m_axi_awready) begin
                    m_axi_awvalid <= 1'b0;
                    a_st          <= A_W;
                end

                A_W: if (m_axi_wvalid & m_axi_wready) begin
                    if (beat == BURST_BEATS - 1) begin
                        beat <= {BEAT_CW{1'b0}};
                        a_st <= A_B;
                    end else begin
                        beat <= beat + 1'b1;
                    end
                end

                A_B: if (m_axi_bvalid) begin
                    if (m_axi_bresp != 2'b00) err_sticky <= 1'b1;   // 非 OKAY ⇒ 本帧不发布
                    if (bcnt == NBURST - 1) begin
                        done_level <= 1'b1;                          // 全部写完，通知 fb 侧
                        a_st       <= A_DONE;
                    end else begin
                        bcnt          <= bcnt + 1'b1;
                        addr_r        <= addr_r + BURST_STEP;
                        m_axi_awaddr  <= addr_r + BURST_STEP;
                        m_axi_awvalid <= 1'b1;
                        a_st          <= A_AW;
                    end
                end

                A_DONE: if (~req_s2) begin
                    done_level <= 1'b0;
                    a_st       <= A_IDLE;
                end

                default: a_st <= A_IDLE;
            endcase
        end
    end

endmodule
