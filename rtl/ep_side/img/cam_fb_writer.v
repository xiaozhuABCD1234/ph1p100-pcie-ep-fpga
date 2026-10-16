///////////////////////////////////////////////////////////////////////////////
//  cam_fb_writer.v — IMX415(MIPI CSI-2) 收到的像素 → 帧缓存写口（本移植新增）
//
//  为什么需要它：帧缓存（img_frame_src 内的 fb[]）此前只由测试图发生器填充。
//  RK3588 要拿到"真实图像"，必须把 CSI-2 收包输出的像素按同样布局写进帧缓存。
//
//  ===========================================================================
//  一、输入信号与有效时序约定（全部读自 rtl/ep_side/cam/*.v，逐条附出处）
//  ===========================================================================
//    cam_clk       ← 顶层 w_a_byte_clk   = mipi_csi2_rx_ph1p.v:33 O_byte_clk
//                    软 PHY 字节时钟。1.5Gbps/lane、4 lane、PH1P_LOGIC_LCLK
//                    DIV=4 ⇒ 187.5MHz（constraints/ph1p_pcie_case_ep.sdc:22-26）
//    cam_rst_n     ← 顶层 w_a_rst_out    = mipi_csi2_rx_ph1p.v:34 O_rst_out（低有效）
//    cam_vsync     ← 顶层 w_a_vsync      = mipi_csi2_rx_ph1p.v:39 O_vsync
//                    = 「WAIT_HDR 且包头类型 0x00(FS)」的组合脉冲
//                      （csi_rx_packet_handler.v:314-316）⇒ 1 拍脉冲 = 帧起始 SOF
//    cam_in_frame  ← 顶层 w_a_in_frame   = mipi_csi2_rx_ph1p.v:40 O_in_frame
//                    = 「电平」：FS(0x00) 置 1、FE(0x01) 清 0
//                      （csi_rx_packet_handler.v:222-238）⇒ 下降沿 = 帧结束 EOF
//    cam_in_line   ← 顶层 w_a_in_line    = mipi_csi2_rx_ph1p.v:41 O_in_line
//                    = 长包头（类型高 4 位 = 1/2/3：YUV/RAW/RGB）那一拍为 1，
//                      其余时刻一律清 0（csi_rx_packet_handler.v:240-260，
//                      注意 253-259 的 else 分支把非长包/非 WAIT_HDR 全部清 0）
//                      ⇒ 「每行一个 1 拍脉冲（行头）」，不是行内电平！
//                      （csi_rx_10bit_unpack.v:59-65 正是靠它每个行头复位字节计数）
//    cam_pix[39:0] ← 顶层 w_a_pixel      = mipi_csi2_rx_ph1p.v:42 O_pixel_data
//    cam_pix_valid ← 顶层 w_a_pixel_valid= mipi_csi2_rx_ph1p.v:43 O_pixel_valid
//                    = 1 个有效脉冲 = 1 组 = RAW10 的 4 个像素：
//                      [9:0]=第 1 个（最左）像素，[19:10]/[29:20]/[39:30] 依次向右
//                      （csi_rx_10bit_unpack.v:34-43 的 mipi_unpack 明确写出该位序）
//                      输出与 O_dout_valid 同拍（csi_rx_10bit_unpack.v:128-152）
//
//  由以上约定得到的用法（本模块实现）：
//    * 每个像素组固定 4 像素 ⇒ 与「4 像素/32bit 字」的缓存布局一一对应，不需要再攒；
//    * 帧内第一行 = FS 之后的第 1 个 in_line 脉冲（行号 0），
//      行号 / 列号都只在这里维护，列号按「组」累加 4；
//    * **行号 0 是传感器帧头的 embedded data 行，不是图像**（板上实测：那一行是
//      0x83/0xB2/0x01 之类的固定位模式，第 1 行起才是图像）。所以真正取图前先
//      跳过 SKIP_ROWS 行，窗口从「Y0 + SKIP_ROWS」那一行开始取 H 行；
//      SKIP_ROWS 的值**与传感器模式有关，不是常数**：
//        - binning 模式（1080p/720p）：帧头只有 1 行 → SKIP_ROWS = 1（模块默认值）
//        - 4K 全像素模式：帧头之后还有 36 行恒定黑电平（值恒为 12
//          = 10bit pedestal 50 >> 2）的哑行/光黑行 → SKIP_ROWS = 37
//      顶层 ph1p_pcie_ep_top.v 里按当前传感器模式选了 4K 的那组（CAM_SKIP_ROWS）。
//      换模式时必须跟着改，否则要么把黑带搬进缓存、要么把图像头几行裁掉。
//    * 取值域默认是整幅左上角 640x480（X0/Y0 参数化）。本板顶层传的是
//      4K(3840x2160) 的正中 640x480（X0=1600, Y0=840），所以默认值仍是 0,0、
//      不影响别的工程复用；域外像素丢弃（不进 FIFO），因此 FIFO 只需承受
//      每行 160 组的突发；
//    * 10bit RAW10 → 8bit 灰度取高 8 位（等价 >>2，不四舍五入）。
//
//  ===========================================================================
//  二、帧缓存布局（与 img_frame_src 的测试图源逐字节一致，主机侧工具不用改）
//  ===========================================================================
//    字节 0 .. 307199 : 字 0..76799 = 像素字，低字节 = 最左像素，1 字节 1 像素
//                       （4 像素/字）
//    ⇒ 76800 字 = 307200 字节，整块都是像素、与 0x58 DATA_LEN 一致。
//      帧号**不占缓存**：帧号就是本模块的 FRAME_CNT（0x4C 读回的那个寄存器），
//      所以第 0 行最左 4 个像素也是图像数据。
//
//  ===========================================================================
//  三、跨时钟域
//  ===========================================================================
//    像素在字节时钟域组字 → 异步 FIFO（格雷码指针 + 34bit 双口 RAM，
//    简单写口 + 输出寄存器读口 ⇒ TD 推断 ERAM20K）→ tl_clk_user 域顺序写缓存。
//    FIFO 条目 = {入队时的 SOF 标记, EOF 标记, 像素字}，标记与像素字同队列 ⇒
//    到达顺序即写顺序，SOF/EOF 不会与像素字错序。
//    满标志：只有 FIFO 满才丢（丢的组数记 drop_cnt / ovf_cnt，正常时序应为 0）。
//
//  写源选择在 CTRL[4]（顶层 mux 到 img_frame_src 的写口）。本模块一直跟着
//  相机跑（帧号连续），写口被旁路时写入被丢弃但不影响内部状态与帧号。
//
//  说明：只接 A 路（本板实测锁定的是 A 路）。B 路 FPGA 侧未接（帧缓存只有一份）。
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module cam_fb_writer #(
    parameter [15:0] W       = 16'd640,   // 帧缓存宽（像素，须为 4 的倍数）
    parameter [15:0] H       = 16'd480,   // 帧缓存高（行）
    parameter        AW      = 17,        // 字地址位宽：640*480/4 = 76800 → 17
    parameter [15:0] X0      = 16'd0,     // 裁剪窗口左上角（图像域内）
    parameter [15:0] Y0      = 16'd0,
    // 帧头 embedded data 行数：IMX415 实测第 0 行是固定位模式的 embedded data，
    // 跳过它再取 H 行，缓存第 0 行才是真正的图像行。只跳过、不搬进缓存。
    parameter [15:0] SKIP_ROWS = 16'd1,
    parameter        FIFO_AW = 9          // 异步 FIFO 深度 = 2**FIFO_AW
)(
    // ---------------- MIPI CSI-2 字节时钟域（w_a_byte_clk）----------------
    input  wire          cam_clk,
    input  wire          cam_rst_n,
    input  wire          cam_vsync,
    input  wire          cam_in_frame,
    input  wire          cam_in_line,
    input  wire [39:0]   cam_pix,
    input  wire          cam_pix_valid,

    // ---------------- tl_clk_user 域 ----------------
    input  wire          clk,
    input  wire          rst,

    // 帧缓存写口（字节地址，低 2 位恒 0；接 img_frame_src 的外部写口）
    output reg           fb_wr_en,
    output reg  [31:0]   fb_wr_addr,
    output reg  [31:0]   fb_wr_data,

    // 状态（cam_sel=1 时由 img_frame_src mux 到 0x48/0x4C/0x58）
    output reg  [31:0]   frame_cnt,      // 已完成帧数（= 缓存里最后那帧的帧号）
    output wire [31:0]   data_len,       // 每帧字节数（= W*H，与测试图源一致）
    output reg           ready,          // 至少出过一帧
    output reg           busy,           // 正在写本帧缓存（0 → 1 于 SOF，1 → 0 于 EOF）
    output reg           frame_done,     // 「帧完成」标志：EOF 置 1、下一个 SOF 清 0

    // 诊断（顶层未接寄存器；留给 ChipWatcher/下一轮排查）
    output reg  [31:0]   wr_word_cnt,    // 本帧已写入的像素字数（正常 = WORDS）
    output reg  [15:0]   drop_cnt,       // 因 FIFO 满而丢掉的像素组数（正常 = 0）
    output reg  [15:0]   ovf_cnt         // 因 FIFO 满而丢掉的 SOF/EOF 标记数（正常 = 0）
);

    // 强制 32bit 上下文：W/H 是 16bit 参数，不写宽度的话 640*480 会被按 16bit 截断
    localparam [31:0] WORDS = (W * H) / 4;

    function [FIFO_AW:0] bin2gray;          // 二进制 → 格雷码
        input [FIFO_AW:0] b;
        begin
            bin2gray = b ^ (b >> 1);
        end
    endfunction

    assign data_len = {16'd0, W} * {16'd0, H};

    // =========================================================================
    // 字节时钟域：行/列计数 + 组字 + 入队
    // =========================================================================
    reg [15:0] x_cnt;        // 当前行内已收到的像素数（按组 +4）
    reg [15:0] y_cnt;        // 当前行的行号（帧内第一行 = 0）
    reg        first_line;   // 本帧第一行还没来（SOF 后置位，行头清位）
    reg        vsync_d, in_frame_d, in_line_d;

    wire [7:0]  p0 = cam_pix[9:2];
    wire [7:0]  p1 = cam_pix[19:12];
    wire [7:0]  p2 = cam_pix[29:22];
    wire [7:0]  p3 = cam_pix[39:32];
    wire [31:0] pix_word = {p3, p2, p1, p0};   // 低字节 = 最左像素

    wire sof_evt  = cam_vsync & ~vsync_d;            // FS  → 帧起始
    wire eof_evt  = ~cam_in_frame & in_frame_d;      // FE  → 帧结束
    wire line_evt = cam_in_line & ~in_line_d;        // 长包头 → 行首（1 拍）

    // 图像窗口：先跳过帧头 SKIP_ROWS 行 embedded data，再从 Y0 起取 H 行
    wire [15:0] y_img0 = Y0 + SKIP_ROWS;
    wire in_win = (x_cnt >= X0) && (x_cnt < (X0 + W)) &&
                  (y_cnt >= y_img0) && (y_cnt < (y_img0 + H));

    always @(posedge cam_clk or negedge cam_rst_n) begin
        if (!cam_rst_n) begin
            x_cnt <= 16'd0; y_cnt <= 16'd0; first_line <= 1'b1;
            vsync_d <= 1'b0; in_frame_d <= 1'b0; in_line_d <= 1'b0;
        end else begin
            vsync_d    <= cam_vsync;
            in_frame_d <= cam_in_frame;
            in_line_d  <= cam_in_line;

            if (sof_evt) begin                 // 帧起始：行列归零，等第一个行头
                x_cnt      <= 16'd0;
                y_cnt      <= 16'd0;
                first_line <= 1'b1;
            end else if (line_evt) begin       // 行首：列归零，行号 +1（首行不动）
                x_cnt <= 16'd0;
                if (first_line) first_line <= 1'b0;
                else            y_cnt <= y_cnt + 16'd1;
            end else if (cam_pix_valid) begin  // 像素组：列 +4（域外同样累加）
                x_cnt <= x_cnt + 16'd4;
            end
        end
    end

    // ---- 入队（标记优先，保证 SOF/EOF 与像素字的先后顺序）----
    wire        push_sof = sof_evt;
    wire        push_eof = eof_evt & ~sof_evt;
    wire        push_pix = cam_pix_valid & in_win & ~push_sof & ~push_eof;
    wire        push     = push_sof | push_eof | push_pix;
    wire [33:0] f_din    = {push_sof, push_eof, pix_word};

    // ---- 异步 FIFO ----
    reg  [33:0]      f_mem [0:(1 << FIFO_AW) - 1];
    reg  [FIFO_AW:0] wptr_bin,  wptr_gray;
    reg  [FIFO_AW:0] rptr_bin,  rptr_gray;
    reg  [FIFO_AW:0] wgray_s1,  wgray_s2;    // 写指针同步到读域
    reg  [FIFO_AW:0] rgray_s1,  rgray_s2;    // 读指针同步到写域

    wire [FIFO_AW:0] wptr_bin_nxt  = wptr_bin + {{FIFO_AW{1'b0}}, 1'b1};
    wire [FIFO_AW:0] wptr_gray_nxt = bin2gray(wptr_bin_nxt);
    wire [FIFO_AW:0] rptr_bin_nxt  = rptr_bin + {{FIFO_AW{1'b0}}, 1'b1};
    wire [FIFO_AW:0] rptr_gray_nxt = bin2gray(rptr_bin_nxt);

    wire wfull  = (wptr_gray_nxt == {~rgray_s2[FIFO_AW:FIFO_AW-1], rgray_s2[FIFO_AW-2:0]});
    wire rempty = (rptr_gray == wgray_s2);

    wire f_wr = push & ~wfull;

    // 写口：单条简单写语句（TD 推断 ERAM 的关键，别加复位/多分支）
    always @(posedge cam_clk)
        if (f_wr) f_mem[wptr_bin[FIFO_AW-1:0]] <= f_din;

    always @(posedge cam_clk or negedge cam_rst_n) begin
        if (!cam_rst_n) begin
            wptr_bin <= {(FIFO_AW+1){1'b0}};
            wptr_gray <= {(FIFO_AW+1){1'b0}};
        end else if (f_wr) begin
            wptr_bin  <= wptr_bin_nxt;
            wptr_gray <= wptr_gray_nxt;
        end
    end

    always @(posedge cam_clk or negedge cam_rst_n) begin     // 读指针 → 写域
        if (!cam_rst_n) begin rgray_s1 <= {(FIFO_AW+1){1'b0}}; rgray_s2 <= {(FIFO_AW+1){1'b0}}; end
        else begin rgray_s1 <= rptr_gray; rgray_s2 <= rgray_s1; end
    end

    // ---- 丢弃计数（正常时序应为 0）----
    wire push_blocked = push & wfull;
    always @(posedge cam_clk or negedge cam_rst_n) begin
        if (!cam_rst_n) begin
            drop_cnt <= 16'd0;
            ovf_cnt  <= 16'd0;
        end else if (push_blocked) begin
            if (push_pix) drop_cnt <= drop_cnt + 16'd1;
            else          ovf_cnt  <= ovf_cnt  + 16'd1;
        end
    end

    // =========================================================================
    // tl_clk_user 域：出队 + 顺序写帧缓存
    // =========================================================================
    reg [33:0] f_dout;                 // 组合读 + 输出寄存器（ERAM 风格）
    reg        ent_vld;                // f_dout 上这一条有效（比 rempty 晚 1 拍）

    always @(posedge clk)
        f_dout <= f_mem[rptr_bin[FIFO_AW-1:0]];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rptr_bin  <= {(FIFO_AW+1){1'b0}};
            rptr_gray <= {(FIFO_AW+1){1'b0}};
            ent_vld   <= 1'b0;
        end else begin
            ent_vld <= ~rempty;
            if (~rempty) begin
                rptr_bin  <= rptr_bin_nxt;
                rptr_gray <= rptr_gray_nxt;
            end
        end
    end

    always @(posedge clk or posedge rst) begin      // 写指针 → 读域
        if (rst) begin wgray_s1 <= {(FIFO_AW+1){1'b0}}; wgray_s2 <= {(FIFO_AW+1){1'b0}}; end
        else begin wgray_s1 <= wptr_gray; wgray_s2 <= wgray_s1; end
    end

    localparam [1:0] ST_WAIT = 2'd0,   // 等本帧的 SOF
                     ST_RUN  = 2'd1,   // 正在写像素字
                     ST_FULL = 2'd2;   // 帧缓存已写满（字 0..WORD-1），余下只出队不写

    reg [1:0]    st;
    reg [AW-1:0] widx;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            st          <= ST_WAIT;
            widx        <= {AW{1'b0}};
            fb_wr_en    <= 1'b0;
            fb_wr_addr  <= 32'd0;
            fb_wr_data  <= 32'd0;
            frame_cnt   <= 32'd0;
            ready       <= 1'b0;
            busy        <= 1'b0;
            frame_done  <= 1'b0;
            wr_word_cnt <= 32'd0;
        end else begin
            fb_wr_en <= 1'b0;                       // 默认只有一拍写脉冲

            if (ent_vld) begin
                if (f_dout[33]) begin               // ---- SOF：写指针归零，从字 0 起写像素 ----
                    fb_wr_en    <= 1'b0;            // 字 0 不再是帧号：整块缓存都给像素
                    widx        <= {AW{1'b0}};
                    busy        <= 1'b1;
                    frame_done  <= 1'b0;
                    wr_word_cnt <= 32'd0;
                    st          <= ST_RUN;
                end else if (f_dout[32]) begin      // ---- EOF：置帧完成 ----
                    busy       <= 1'b0;
                    frame_cnt  <= frame_cnt + 32'd1;
                    ready      <= 1'b1;
                    frame_done <= 1'b1;
                    st         <= ST_WAIT;
                end else begin                      // ---- 像素字 ----
                    if (st == ST_RUN) begin
                        // 先把这一笔写下去，再判断是不是最后一个字。
                        // 原来写成「!= WORDS-1 才写、否则直接 ST_FULL」会把字
                        // WORDS-1 整笔漏掉（缓存只填到 WORDS-2），文件比 0x58 声明
                        // 少 4 字节；现在写满 0..WORDS-1 后才转 ST_FULL。
                        fb_wr_en    <= 1'b1;
                        fb_wr_addr  <= {widx, 2'b00};
                        fb_wr_data  <= f_dout[31:0];
                        wr_word_cnt <= wr_word_cnt + 32'd1;
                        if (widx == (WORDS - 1)) st <= ST_FULL;
                        else                     widx <= widx + 1'b1;
                    end
                    // st == ST_WAIT（还没等到 SOF）或 ST_FULL：只出队，不写
                end
            end
        end
    end

endmodule
