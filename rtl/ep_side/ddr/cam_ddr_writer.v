///////////////////////////////////////////////////////////////////////////////
//  cam_ddr_writer.v — IMX415(MIPI CSI-2) 收到的像素**直接流进板上 DDR3**
//                     （本移植新增；4K 全幅走这条路，不走片内帧缓存）
//
//  ===========================================================================
//  一、为什么需要它（为什么不能沿用 fb[] 那条路）
//  ===========================================================================
//  传感器本来就跑在 4K（顶层 I_cam_mode=1）——MIPI 链路、CSI-2 收包全都已经
//  把每行 3840 个像素收进来了，`cam_fb_writer` 只是把窗口外的一律丢掉，
//  再写进 img_frame_src 的片内帧缓存 fb[]。所以「相机只能出 640x480」不是
//  传感器或链路的事，而是**片内帧缓存放不下 4K**：
//
//    · 器件 PH1P100SBG484 一共 300 块 ERAM20K（= 300 x 2560B = 768000B），
//      当前综合用掉 138 块（见 syn_1/ph1p_pcie_ep_top_gate.area）。
//    · 640x480 灰度 = 307200B = 120 块；4K(3840x2160) 灰度 = 8294400B = 3240 块
//      ——比整颗器件还多一个数量级，没有任何裁剪/拆分办法能把它塞进片内。
//    · 顺带一提：fb[] 那条路的天花板就在 ~0.7MB（960x720 左右），
//      1080p（2073600B = 810 块）同样放不下。所以「超过 720p」必须离开 fb[]。
//
//  于是本模块把「组字 → 异步 FIFO → DDR3」这一路单独做出来，**不碰 fb[]**：
//
//    CSI-2 字节域(187.5MHz)                    DDR 用户域(dhi_clk 100MHz)
//    ─────────────────────                    ────────────────────────
//    行/列计数 + 窗口裁剪 + 4 像素组 1 字
//      → 异步 FIFO（34bit x 1024，格雷码指针）
//      → 弹出条目、8 个字拼 256bit 一拍  → 每 4KB 一个 AXI4 突发写 DDR3
//
//  ===========================================================================
//  二、和 ddr_frame_writer.v 的关系（接口口径刻意做成一样）
//  ===========================================================================
//  两个模块都是「一帧完整落 DDR3 才发布序号」的写者，寄存器口径完全一致：
//    0xA0 DDR_FRAME_SEQ / 0xA4 DDR_BASE / 0xA8 DDR_STATUS / 0xAC DDR_LEN
//  （位定义见 ep_bar_win.v；顶层按当前选中的写者把这两组二选一）。
//  两者**互斥**使用（同一时刻只有一条通路写 DDR3），选谁由顶层 CTRL[3] 定，
//  AXI 写口在顶层用 ddr_wr_mux 二选一，见 ph1p_pcie_ep_top.v 的 DDR 段。
//
//  ===========================================================================
//  三、几何、裁剪与「帧」的边界
//  ===========================================================================
//  参数 W/H/X0/Y0/SKIP_ROWS 的语义与 cam_fb_writer **逐条相同**（那边头部写得很细），
//  复用同一套实测结论：
//    · 1 拍 cam_pix_valid = 1 组 = RAW10 的 4 个像素（[9:0] 最左）；
//    · cam_in_line 是「每行一个 1 拍脉冲」（行首），cam_vsync = FS(SOF)，
//      cam_in_frame 下降沿 = FE(EOF)；
//    · 帧内第 0 行是 embedded data 行，4K 模式其后还有 36 行恒黑哑行
//      → 4K 取图时 SKIP_ROWS = 37（与顶层 CAM_SKIP_ROWS 同一个实测值）；
//    · 10bit RAW10 → 8bit 取高 8 位（>>2）。
//  帧 = 窗口内 W x H 个像素，1 字节 1 像素，在 DDR3 里**线性连续**存放
//  （与 640x480 那一路逐字节同格式，主机侧解析代码不用改）。
//
//  ★ 硬约束（顶层选几何时必须满足，否则帧尾会出现半页突发）：
//    W*H 必须是 4KB 的整数倍。3840x2160 = 8294400 = 2025 x 4096 满足；
//    640x480 = 307200 = 75 x 4096 也满足。本模块仍按「一般不整除」写
//    （末尾残拍用 wstrb 裁字节、末尾突发用短 awlen），只是这组几何用不到。
//
//  ===========================================================================
//  四、一拍一拍怎么对齐（packer 与 AXI 的握手）
//  ===========================================================================
//  · packer（ddr 域）从 FIFO 弹条目：SOF / EOF / 像素字（34bit，与 cam_fb_writer
//    同一个编码）；攒满 8 个字就交出一拍 256bit（beat_vld/beat_data/beat_strb），
//    AXI 侧用 beat_taken 取走（取走那一拍才允许弹下一个条目）。
//  · AXI 侧每帧固定写 NBEATS 拍（= ceil(W*H/4/8)），按 4KB 切突发，最后一个突发
//    可以是短板（awlen = 剩余拍数-1）。这套「预算」是编译期常量：
//    顶层换几何时两边一起变，不会出现「谁先算完谁停」的错位。
//  · 帧内数据不够（丢条目、丢 SOF/EOF、链路异常）时 AXI 侧不空等：packer 一旦
//    收口（C_END），AXI 就用 wstrb=0 的空拍把本帧剩余的拍补满（那段 DDR 是旧的/
//    垃圾数据），而**该帧不发布**（见下面「不虚报」）。
//  · 帧内给的拍数超过预算（同一帧收到两个 SOF 等异常）：packer 停手，AXI 把预算
//    写完就收，同样不发布。
//
//  ===========================================================================
//  五、什么情况才发布（不虚报）
//  ===========================================================================
//  以下条件**全部**成立才把序号 +1、把 base/status 交给主机（与 ddr_frame_writer
//  一样，DDR_LEN 是常量，不进握手）：
//    · 本帧的像素字数正好 = W*H/4（丢一个组就对不上）；
//    · 本帧确实收到了 EOF 标记（SOF/EOF 丢过就不会再对上）；
//    · 本帧交给 AXI 的拍数 = NBEATS，且所有 4KB 突发的 bresp 都是 OKAY；
//    · 没有出现「上一帧还没被 tl 域取走就又写完一帧」这种挤在一起的情况。
//  任意一条不成立：本帧不发布、err_cnt+1（主机读 0xA8 的 bit2 与 [31:16] 看得见），
//  然后自动从下一个 SOF 重新对齐。异常恢复期间可能连丢 1~2 帧（FIFO 里残留的
//  条目要丢到下一个 SOF），这是刻意接受的代价：不虚报 > 不丢帧。
//
//  ===========================================================================
//  六、跨时钟域（三域，全部照工程既有写法，不自创）
//  ===========================================================================
//    · 像素字：异步 FIFO（格雷码指针 + 2 级同步器 + 简单写口/输出寄存器读口
//      ⇒ TD 推 ERAM20K）—— 与 cam_fb_writer.v / ddr_frame_writer.v 同一个套路；
//    · 帧结果（ddr → tl_clk_user）：「数据先稳住 + toggle/ack」握手
//      （pub_tgl / pub_ack）：ddr 侧把 {ok,base,err_cnt} 与 toggle 同时打拍，
//      tl 侧 2 级同步看到变化就取走并回 ack，ddr 侧没收到 ack 之前不改这几个字；
//    · 诊断（字节域 → tl 域）：lines_per_frame / max_grp_per_line / 异常位都是
//      慢变量（一帧 33~68ms 才变一次），按顶层读 lane_valid 那种「直接采两拍」
//      处理，只用于上板量几何，不参与任何控制；
//    · 复位：ddr 域一复位，字节域的写指针/状态也跟着归零（alive 同步过来），
//      避免只复位一半导致 FIFO 两端错位 —— 与 ddr_frame_writer.v 同一做法。
//
//  ===========================================================================
//  七、诊断寄存器（上板第一件事就是量这两个数）
//  ===========================================================================
//  0xD0 CAM_DDR_DIAG = {lines_per_frame[15:0], max_grp_per_line[15:0]}（见 ep_bar_win.v）：
//    · max_grp_per_line：一帧内**单行收到的最多组数**（x 方向，**裁剪之前**计数）。
//      4K 全幅应为 3840/4 = 960；若读到 966（=3864/4）说明传感器读出宽度是 3864
//      而不是 3840，窗口 X0/W 要跟着改，否则右边会少 24 列（或左边多 12 列）；
//    · lines_per_frame：一帧的行数（y 方向，含 embedded/哑行）。4K 下应为
//      SKIP_ROWS + 2160 = 2197；不等于它说明 SKIP_ROWS/H 要重新标定。
//  另：顶层把「字节域丢过组/丢过标记」或到 0x80 相机状态字的 bit15（原来是保留 0），
//  一眼就能看出是不是 FIFO 满导致的丢帧。
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module cam_ddr_writer #(
    // ---- 帧几何：与 cam_fb_writer / 顶层 CAM_* 用同一组 W/H/X0/Y0/SKIP_ROWS ----
    parameter integer W           = 3840,          // 帧宽（像素，须为 4 的倍数）
    parameter integer H           = 2160,          // 帧高（行）
    parameter [15:0]  X0          = 16'd0,         // 裁剪窗左上角（图像域内，裁前坐标）
    parameter [15:0]  Y0          = 16'd0,
    parameter [15:0]  SKIP_ROWS   = 16'd37,        // 帧头 embedded + 哑行数（4K 实测 37）
    // ---- DDR3 双缓冲基址（字节，4KB 对齐，两块互不重叠且都不小于 W*H）----
    parameter [31:0]  BASE0       = 32'h0010_0000, // 1MB
    parameter [31:0]  BASE1       = 32'h0090_0000, // 9MB（4K 一帧 7.9MB，两块不重叠）
    // ---- 异步 FIFO 深度 = 2**FIFO_AW 条（每条约 4 像素）----
    //   1024 条 = 4KB ≈ 1.07 行（4K）。为什么够：一行 960 条在 5.12us 内涌入
    //   （1.5Gbps x 4 lane），而 ddr 域 1 拍吐 1 条（100MHz）：
    //   5.12us 只吐掉 512 条 ⇒ 积压 448 条 < 1024，且行间空档还会继续吐。
    parameter integer FIFO_AW     = 10,
    // ---- 每个 AXI 突发的拍数（awlen = BURST_BEATS-1）；最后一突发可为短板 ----
    parameter integer BURST_BEATS = 128
)(
    // ---------------- MIPI CSI-2 字节时钟域（w_a_byte_clk，187.5MHz）----------------
    input  wire          cam_clk,
    input  wire          cam_rst_n,
    input  wire          cam_vsync,
    input  wire          cam_in_frame,
    input  wire          cam_in_line,
    input  wire [39:0]   cam_pix,
    input  wire          cam_pix_valid,

    // ---------------- tl_clk_user 域（62.5MHz）：发布握手（接 0xA0~0xAC）----------------
    input  wire          clk_fb,
    input  wire          rst_fb,
    output reg  [31:0]   wr_frame_seq,     // 已发布帧数（单调递增；0 = 还没有过完整帧）
    output reg  [31:0]   wr_base,          // 该帧在 DDR3 里的字节基址
    output reg  [31:0]   wr_status,        // bit0 valid / bit1 busy / bit2 err /
                                           // bit3 alive / bit4 cal_done / [31:16] err_cnt
    output wire [31:0]   wr_len,           // 每帧字节数（常量 W*H）

    // ---------------- 诊断（tl_clk_user 域采样；见文件头第七节）----------------
    output reg  [15:0]   dbg_lines_per_frame,
    output reg  [15:0]   dbg_max_grp_per_line,
    output reg           dbg_anomaly,      // 字节域丢过像素组/标记（只增不减）

    // ---------------- DDR 用户域（u_ddr3_mc_0/usr_clk，100MHz）----------------
    input  wire          clk_ddr,
    input  wire          rst_ddr,          // 高有效（= !ddrphy_rst_n = !axi_aresetn）
    input  wire          ddr_cal_done,     // = ddrphy_rdy（DDRPHY 校准完成）
    input  wire          arm,              // 1 = 本模块拥有 DDR 写口（顶层 sel_eff）
    output wire          axi_busy,         // 写口/帧还可能归我（给顶层 mux 判空闲）

    // ---------------- AXI4 写通道（顶层经 ddr_wr_mux 接 u_ddr3_mc_0）----------------
    output reg  [28:0]   m_axi_awaddr,
    output reg  [7:0]    m_axi_awlen,
    output wire [2:0]    m_axi_awsize,
    output wire [1:0]    m_axi_awburst,
    output reg           m_axi_awvalid,
    input  wire          m_axi_awready,
    output wire [255:0]  m_axi_wdata,
    output wire [31:0]   m_axi_wstrb,
    output wire          m_axi_wlast,
    output wire          m_axi_wvalid,
    input  wire          m_axi_wready,
    input  wire [1:0]    m_axi_bresp,
    input  wire          m_axi_bvalid,
    output wire          m_axi_bready
);

    // ========================================================================
    //  参数推导（魔数只在这里出现）
    // ========================================================================
    localparam integer BEAT_BYTES     = 32;                            // 256bit/8
    localparam integer WORDS_PER_BEAT = BEAT_BYTES / 4;                // 每拍 8 个字
    localparam integer FRAME_WORDS    = (W * H) / 4;                    // 每帧字数
    localparam integer FRAME_BYTES    = W * H;                          // 1 字节 1 像素
    localparam integer PART_WORDS     = FRAME_WORDS % WORDS_PER_BEAT;   // 末尾残拍字数（0=整拍）
    localparam integer NBEATS         = (FRAME_WORDS + WORDS_PER_BEAT - 1) / WORDS_PER_BEAT;
    localparam [31:0]  WR_LEN_W       = FRAME_BYTES;

    localparam [2:0]   AXI_SIZE       = 3'd5;      // 2**5 = 32 字节/拍
    localparam [1:0]   AXI_BURST      = 2'b01;     // INCR

    function integer clogb2;
        input integer v;
        integer i;
        begin
            clogb2 = 0;
            for (i = v - 1; i > 0; i = i >> 1)
                clogb2 = clogb2 + 1;
        end
    endfunction

    localparam integer BEAT_CW = clogb2(BURST_BEATS);     // 突发内拍计数位宽
    localparam integer BTL_CW  = clogb2(NBEATS);          // 本帧剩余拍数位宽

    localparam [BTL_CW-1:0] BURST_BEATS_S = BURST_BEATS;  // 参数不能直接位选
    localparam [31:0] STRB_PARTIAL = (PART_WORDS == 0) ? 32'hFFFF_FFFF
                                                       : ((32'h1 << (PART_WORDS * 4)) - 32'h1);

    function [FIFO_AW:0] bin2gray;
        input [FIFO_AW:0] b;
        begin
            bin2gray = b ^ (b >> 1);
        end
    endfunction

    // ========================================================================
    //  字节时钟域：行/列计数 + 窗口裁剪 + 组字 + 进 FIFO
    //  （计数逻辑与 cam_fb_writer.v 逐条相同，只是不再写 fb[]）
    // ========================================================================
    reg [15:0] x_cnt;        // 行内已收到的像素数（按 4 累加）
    reg [15:0] y_cnt;        // 帧内行号（第一个行头 = 0）
    reg        first_line;   // 本帧第一个行头还没来
    reg        vsync_d, in_frame_d, in_line_d;
    reg        frame_armed;  // 本帧是否采集（SOF 那一刻锁存 arm）
    reg [1:0]  arm_c;        // arm（ddr 域电平）同步到字节域

    wire [7:0]  p0 = cam_pix[9:2];
    wire [7:0]  p1 = cam_pix[19:12];
    wire [7:0]  p2 = cam_pix[29:22];
    wire [7:0]  p3 = cam_pix[39:32];
    wire [31:0] pix_word = {p3, p2, p1, p0};   // 低字节 = 最左像素

    wire sof_evt  = cam_vsync & ~vsync_d;             // FS → 帧起始
    wire eof_evt  = ~cam_in_frame & in_frame_d;       // FE → 帧结束
    wire line_evt = cam_in_line & ~in_line_d;         // 长包头 → 行首（1 拍）

    // 图像窗口：先跳过帧头 SKIP_ROWS 行，再从 Y0 起取 H 行（与 cam_fb_writer 同语义）
    wire [15:0] y_img0 = Y0 + SKIP_ROWS;
    wire in_win = (x_cnt >= X0) && (x_cnt < (X0 + W)) &&
                  (y_cnt >= y_img0) && (y_cnt < (y_img0 + H));

    // ---- 诊断：单行最多组数 / 一帧行数（都在**裁剪之前**数，用于量真实几何）----
    reg [15:0] cur_grp;      // 本行已收到的组数
    reg [15:0] max_grp;      // 上一帧的单行最大组数
    reg [15:0] frame_lines;  // 本帧行数（数行头脉冲）

    // ---- DDR 侧是否已出复位：同步到字节域，用来让 FIFO 两端一起归零 ----
    reg        alive_c1, alive_c2;
    wire       rst_cam_all = ~cam_rst_n | ~alive_c2;

    always @(posedge cam_clk or negedge cam_rst_n) begin
        if (!cam_rst_n) begin
            x_cnt <= 16'd0; y_cnt <= 16'd0; first_line <= 1'b1;
            vsync_d <= 1'b0; in_frame_d <= 1'b0; in_line_d <= 1'b0;
            frame_armed <= 1'b0; arm_c <= 2'd0;
            cur_grp <= 16'd0; max_grp <= 16'd0; frame_lines <= 16'd0;
            alive_c1 <= 1'b0; alive_c2 <= 1'b0;
        end else begin
            vsync_d    <= cam_vsync;
            in_frame_d <= cam_in_frame;
            in_line_d  <= cam_in_line;
            arm_c      <= {arm_c[0], arm};
            alive_c1   <= ~rst_ddr;
            alive_c2   <= alive_c1;

            if (sof_evt) begin                 // 帧起始：行列归零，锁存本帧是否采集
                x_cnt       <= 16'd0;
                y_cnt       <= 16'd0;
                first_line  <= 1'b1;
                frame_armed <= arm_c[1];       // 已在字节域稳了 ≥2 拍
                cur_grp     <= 16'd0;
                max_grp     <= 16'd0;
                frame_lines <= 16'd0;
            end else if (line_evt) begin       // 行首：列归零、行号 +1（首行不动）
                x_cnt       <= 16'd0;
                cur_grp     <= 16'd0;
                frame_lines <= frame_lines + 16'd1;
                if (first_line) first_line <= 1'b0;
                else            y_cnt <= y_cnt + 16'd1;
            end else if (cam_pix_valid) begin  // 像素组：列 +4（域外同样累加）
                x_cnt   <= x_cnt + 16'd4;
                cur_grp <= cur_grp + 16'd1;
                if ((cur_grp + 16'd1) > max_grp) max_grp <= cur_grp + 16'd1;
            end
        end
    end

    // ---- 入队（标记优先，保证 SOF/EOF 与像素字的先后顺序）----
    //  ★ push_sof 用的是「SOF 那一拍 arm 的值」（arm_c[1]），不是下面锁存的
    //    frame_armed：frame_armed 要到这一拍结束才更新，拿它当门会把**第一帧的 SOF
    //    吞掉**（那一拍 frame_armed 还是复位的 0），之后整条通路就永远等不到 SOF。
    //    EOF 用 frame_armed 才对：它必须与本帧 SOF 时的采集决定一致。
    wire        push_sof = sof_evt & arm_c[1];
    wire        push_eof = eof_evt & frame_armed;
    wire        push_pix = cam_pix_valid & in_win & frame_armed & ~push_sof & ~push_eof;
    wire        push     = push_sof | push_eof | push_pix;
    wire [33:0] f_din    = {push_sof, push_eof, pix_word};

    // ---- 异步 FIFO（简单写口 → ERAM20K；输出寄存器读口在 ddr 域）----
    reg  [33:0]      f_mem [0:(1 << FIFO_AW) - 1];
    reg  [FIFO_AW:0] wptr_bin,  wptr_gray;
    reg  [FIFO_AW:0] rptr_bin,  rptr_gray;
    reg  [FIFO_AW:0] wgray_s1,  wgray_s2;    // 写指针 → ddr 域
    reg  [FIFO_AW:0] rgray_s1,  rgray_s2;    // 读指针 → 字节域

    wire [FIFO_AW:0] wptr_bin_nxt  = wptr_bin + {{FIFO_AW{1'b0}}, 1'b1};
    wire [FIFO_AW:0] wptr_gray_nxt = bin2gray(wptr_bin_nxt);
    wire [FIFO_AW:0] rptr_bin_nxt  = rptr_bin + {{FIFO_AW{1'b0}}, 1'b1};
    wire [FIFO_AW:0] rptr_gray_nxt = bin2gray(rptr_bin_nxt);

    wire wfull = (wptr_gray_nxt == {~rgray_s2[FIFO_AW:FIFO_AW-1], rgray_s2[FIFO_AW-2:0]});
    wire f_wr  = push & ~wfull;

    // 写口：单条简单写语句（TD 推断 ERAM 的关键，别加复位/多分支）
    always @(posedge cam_clk)
        if (f_wr) f_mem[wptr_bin[FIFO_AW-1:0]] <= f_din;

    always @(posedge cam_clk or posedge rst_cam_all) begin
        if (rst_cam_all) begin
            wptr_bin  <= {(FIFO_AW+1){1'b0}};
            wptr_gray <= {(FIFO_AW+1){1'b0}};
        end else if (f_wr) begin
            wptr_bin  <= wptr_bin_nxt;
            wptr_gray <= wptr_gray_nxt;
        end
    end

    always @(posedge cam_clk or posedge rst_cam_all) begin   // 读指针 → 字节域
        if (rst_cam_all) begin rgray_s1 <= {(FIFO_AW+1){1'b0}}; rgray_s2 <= {(FIFO_AW+1){1'b0}}; end
        else begin rgray_s1 <= rptr_gray; rgray_s2 <= rgray_s1; end
    end

    // ---- 丢包计数（正常时序应为 0；顶层把它或到相机状态字的保留位上暴露）----
    reg [15:0] drop_cnt, ovf_cnt;
    wire       push_blocked = push & wfull;

    always @(posedge cam_clk or posedge rst_cam_all) begin
        if (rst_cam_all) begin
            drop_cnt <= 16'd0;
            ovf_cnt  <= 16'd0;
        end else if (push_blocked) begin
            if (push_pix) drop_cnt <= drop_cnt + 16'd1;
            else          ovf_cnt  <= ovf_cnt  + 16'd1;
        end
    end

    // ========================================================================
    //  ddr 域：寄存器/线网声明（必须早于下面所有 always，免得 TD 造隐式网）
    // ========================================================================
    // FIFO 读侧（输出寄存器 + 有效性；两者始终对应**当前** rptr 上那一条）
    reg  [33:0] f_dout;
    reg         ent_vld;

    // packer
    localparam [1:0] C_SYNC = 2'd0,   // 等 SOF（期间把残留条目丢掉）
                     C_RUN  = 2'd1,   // 帧内：吃像素字、交拍
                     C_END  = 2'd2;   // 本帧数据侧已收口，等 AXI 写完这一帧
    reg  [1:0]   c_st;
    reg  [31:0]  p_wcnt;             // 本帧已消费的像素字数
    reg  [2:0]   p_lane;             // 本拍内已装的字数（0..7）
    reg  [255:0] p_pack;
    reg          p_eof_seen;         // 本帧见过 EOF
    reg          p_bad;              // 本帧出过异常（回到 C_SYNC 才清）
    reg  [31:0]  p_beats;            // 本帧已交给 AXI 的拍数
    reg          beat_vld;           // 手上有一拍没被取走
    reg  [255:0] beat_data;
    reg  [31:0]  beat_strb;
    reg  [20:0]  c_run_tmo;          // C_RUN 停留超时（丢标记兜底，约 10ms@100MHz）

    // AXI 写通道
    localparam [2:0] A_IDLE = 3'd0,
                     A_AW   = 3'd1,
                     A_W    = 3'd2,
                     A_B    = 3'd3,
                     A_DONE = 3'd4;
    reg  [2:0]         a_st;
    reg  [28:0]        addr_r;
    reg  [31:0]        base_r;        // 本帧基址
    reg  [BTL_CW-1:0]  beats_left;    // 本帧剩余拍数
    reg  [BEAT_CW-1:0] w_idx;         // 本突发已发拍数
    reg  [7:0]         burst_m1;      // 本突发拍数 - 1（可以是短板）
    reg                frame_close;   // 给 packer 的收尾脉冲
    reg  [31:0]        frame_idx;     // 已开始的帧数（奇偶选双缓冲块）
    reg                axi_err;       // 本帧 bresp 出过错

    // 帧结果握手（ddr 侧）
    reg  [16:0] pub_wait_cnt;   // 等 tl 域回执的计时（见下面 pub_stuck 的说明）
    reg  [31:0] pub_base;
    reg         pub_ok;
    reg  [15:0] pub_err;
    reg         pub_tgl;
    reg         pub_ack_s1, pub_ack_s2;   // tl 域的 ack 同步回来
    reg  [15:0] err_cnt;                  // 坏帧累计

    // 帧结果握手（tl 侧）
    reg         pub_ack;
    reg         pub_tgl_s1, pub_tgl_s2, pub_tgl_s3;

    // ========================================================================
    //  ddr 域：FIFO 读侧
    //
    //  ★ 「pop 即消费」+ 输出寄存器读（TD 推 ERAM20K 的形式），两者要同时成立，
    //    关键是**pop 的那一拍就让输出寄存器直接装下一条**：
    //        f_dout <= f_mem[pop ? rptr+1 : rptr]
    //    于是「f_dout/ent_vld 永远是当前 rptr 上那一条」，本状态机可以放心地
    //    把「吃不吃这一条」当作 pop 条件（手上还压着一拍、或本帧拍预算用完时不吃）。
    //    ★ 两个踩过的坑，写在这儿免得下次再踩：
    //      (1) pop 用 `ent_vld`（= ~rempty 延迟一拍）而不是 ~rempty：FIFO 变空那一拍
    //          ent_vld 还是 1，会多 pop 一条；rptr 越过 wptr 之后 rempty 永远为 0，
    //          读侧就开始空转狂读（实测就是这么跑飞的）。
    //      (2) 照 cam_fb_writer 那样「pop 用 ~rempty、数据用延迟一拍的 ent_vld」：
    //          那条路每一条都无条件消费，所以指针跑在数据前面一拍没关系；本模块
    //          有「这一拍先不吃」的情况，一停指针、寄存器里那条就被跳过（丢数据）。
    // ========================================================================
    wire rempty     = (rptr_gray == wgray_s2);
    wire rempty_nxt = (rptr_gray_nxt == wgray_s2);     // pop 之后的空标志

    // pop 的定义在下面 packer 那一段（它的操作数都在那儿声明）；这里先声明，
    // 免得 TD 报 HDL-5373「used before its declaration」。
    wire pop;

    // 输出寄存器读口（简单地址 → 下一拍数据；地址按本拍 pop 与否二选一）
    always @(posedge clk_ddr)
        f_dout <= f_mem[pop ? rptr_bin_nxt[FIFO_AW-1:0] : rptr_bin[FIFO_AW-1:0]];

    // 本拍头部的条目（不 pop 就一直挂在这一拍上，不会自己变）
    wire        is_sof  = ent_vld &  f_dout[33];
    wire        is_eof  = ent_vld &  f_dout[32];
    wire        is_pix  = ent_vld & ~f_dout[33] & ~f_dout[32];
    wire [31:0] e_word  = f_dout[31:0];

    // AXI 侧取走手上这一拍
    wire beat_taken = (a_st == A_W) & m_axi_wready & beat_vld;
    // 本拍能不能继续吃 FIFO 条目：手上有拍没交出去就先别吃
    wire data_go    = ent_vld & ~(beat_vld & ~beat_taken);
    wire pix_budget = (p_beats < NBEATS);                    // 还欠拍数就能继续吃像素

    // pop：C_SYNC 一律丢到见到 SOF；C_RUN 只吃「标记」或「预算内的像素字」；C_END 不吃
    assign pop = (c_st == C_SYNC) ? ent_vld :
                 (c_st == C_RUN)  ? (data_go & (is_sof | is_eof | (is_pix & pix_budget))) :
                 1'b0;

    wire beat_full = (p_lane == 3'd7);                       // 攒满 8 个字

    // C_RUN 停留超时：帧内已经没有可消费的条目（例如 EOF 标记被丢了）也要能收口，
    // 否则 AXI 侧会一直等拍、这一帧永远收不了尾。
    wire c_run_tmo_hit = (c_run_tmo == 21'h1F_FFFF);

    always @(posedge clk_ddr or posedge rst_ddr) begin
        if (rst_ddr) begin
            rptr_bin  <= {(FIFO_AW+1){1'b0}};
            rptr_gray <= {(FIFO_AW+1){1'b0}};
            ent_vld   <= 1'b0;
        end else begin
            // 有效性跟着「更新后的指针」走，才与下一拍 f_dout 里的那一条对得上
            ent_vld <= pop ? ~rempty_nxt : ~rempty;
            if (pop) begin                           // pop 即消费：指针只在这里动
                rptr_bin  <= rptr_bin_nxt;
                rptr_gray <= rptr_gray_nxt;
            end
        end
    end

    always @(posedge clk_ddr or posedge rst_ddr) begin       // 写指针 → ddr 域
        if (rst_ddr) begin wgray_s1 <= {(FIFO_AW+1){1'b0}}; wgray_s2 <= {(FIFO_AW+1){1'b0}}; end
        else begin wgray_s1 <= wptr_gray; wgray_s2 <= wgray_s1; end
    end

    always @(posedge clk_ddr or posedge rst_ddr) begin
        if (rst_ddr) c_run_tmo <= 21'd0;
        else if (pop | (c_st != C_RUN)) c_run_tmo <= 21'd0;
        else c_run_tmo <= c_run_tmo + 21'd1;
    end

    // ========================================================================
    //  ddr 域：packer —— 把像素字攒成 256bit 拍，交给 AXI 侧
    // ========================================================================
    always @(posedge clk_ddr or posedge rst_ddr) begin
        if (rst_ddr) begin
            c_st        <= C_SYNC;
            p_wcnt      <= 32'd0;
            p_lane      <= 3'd0;
            p_pack      <= 256'd0;
            p_eof_seen  <= 1'b0;
            p_bad       <= 1'b1;      // 复位后第一帧必须从 SOF 重新起，先按坏处理
            p_beats     <= 32'd0;
            beat_vld    <= 1'b0;
            beat_data   <= 256'd0;
            beat_strb   <= 32'd0;
        end else begin
            if (beat_vld & beat_taken) beat_vld <= 1'b0;      // 交出去就撤

            case (c_st)
            // ---------------- 等 SOF ----------------
            C_SYNC: begin
                if (pop & is_sof) begin
                    c_st       <= C_RUN;
                    p_wcnt     <= 32'd0;
                    p_lane     <= 3'd0;
                    p_pack     <= 256'd0;
                    p_eof_seen <= 1'b0;
                    p_bad      <= 1'b0;
                    p_beats    <= 32'd0;
                end
                // 其余（残留像素字 / 上一个 EOF）：丢掉，继续找 SOF
            end

            // ---------------- 帧内 ----------------
            C_RUN: begin
                if (pop && is_sof) begin                     // 上一帧没收尾又来了 SOF
                    p_bad  <= 1'b1;
                    p_wcnt <= 32'd0;                         // 按新帧重新数
                    p_lane <= 3'd0;
                    p_pack <= 256'd0;
                end else if (pop && is_eof) begin            // 帧数据侧收口
                    p_eof_seen <= 1'b1;
                    if (p_wcnt != FRAME_WORDS) p_bad <= 1'b1;
                    if ((p_lane != 3'd0) && pix_budget) begin // 末尾残拍：交出去并裁字节
                        beat_vld  <= 1'b1;
                        beat_data <= p_pack;
                        beat_strb <= STRB_PARTIAL;
                        p_beats   <= p_beats + 32'd1;
                        p_lane    <= 3'd0;
                    end
                    c_st <= C_END;
                end else if (pop && is_pix) begin
                    p_wcnt <= p_wcnt + 32'd1;
                    if (beat_full) begin                     // 攒满一拍：交出去
                        beat_vld  <= 1'b1;
                        beat_data <= {e_word, p_pack[223:0]};
                        beat_strb <= 32'hFFFF_FFFF;
                        p_beats   <= p_beats + 32'd1;
                        p_lane    <= 3'd0;
                    end else begin
                        p_lane <= p_lane + 3'd1;
                        case (p_lane)
                            3'd0: p_pack[31:0]    <= e_word;
                            3'd1: p_pack[63:32]   <= e_word;
                            3'd2: p_pack[95:64]   <= e_word;
                            3'd3: p_pack[127:96]  <= e_word;
                            3'd4: p_pack[159:128] <= e_word;
                            3'd5: p_pack[191:160] <= e_word;
                            3'd6: p_pack[223:192] <= e_word;
                            3'd7: p_pack[255:224] <= e_word;
                        endcase
                    end
                end else if (c_run_tmo_hit) begin            // 兜底收口
                    p_bad <= 1'b1;
                    c_st  <= C_END;
                end
            end

            // ---------------- 等 AXI 写完本帧 ----------------
            C_END: begin
                if (frame_close) begin                       // AXI 侧收尾干净了
                    c_st   <= C_SYNC;
                    p_bad  <= 1'b1;                          // 下一帧必须重新见 SOF
                    p_lane <= 3'd0;
                    p_pack <= 256'd0;
                end
            end

            default: c_st <= C_SYNC;
            endcase
        end
    end

    // 本帧判定（AXI 侧收尾时采一次）：字数、EOF、拍数三者都要对上，且没出过异常
    wire verdict_bad = p_bad | ~p_eof_seen | (p_wcnt != FRAME_WORDS) | (p_beats != NBEATS);

    // ========================================================================
    //  ddr 域：AXI4 写通道（每帧固定 NBEATS 拍，按 4KB 切突发）
    // ========================================================================
    // pub_stuck 的赋值在下面发布段（操作数都在那儿）；这里先声明，避免 HDL-5373。
    wire pub_stuck;

    wire [BTL_CW-1:0] burst_beats = (beats_left > BURST_BEATS_S) ? BURST_BEATS_S : beats_left;
    wire [28:0]       burst_step  = {{(29-BTL_CW){1'b0}}, burst_beats} << 5;   // x32 字节
    // 下一突发的拍数与 awlen：awlen 必须在 awvalid 拉高那一拍就已经是对的
    // （AXI 只要求握手那一拍稳定，但「awvalid 起来时 awlen 还是上一段的值」
    //   会被从机/监视器看成错，板上 u_ddr3_mc_0 也要求地址与长度同拍稳定）
    wire [BTL_CW-1:0] next_beats  = beats_left - burst_beats;
    wire [7:0]        next_awlen  = (next_beats > BURST_BEATS_S) ? (BURST_BEATS - 1)
                                                                : (next_beats - 8'd1);
    localparam [7:0]  AWLEN_FIRST = (NBEATS > BURST_BEATS) ? (BURST_BEATS - 1)
                                                           : (NBEATS - 1);
    // 本帧数据侧是否已经不再给拍（可以补空拍把突发写满了）
    wire pack_done = (c_st == C_END);

    // 一拍 256bit 的来源：优先用 packer 的拍；packer 收口后用空拍把突发补满
    wire have_beat = beat_vld;
    wire send_beat = have_beat | pack_done;

    assign m_axi_awsize  = AXI_SIZE;
    assign m_axi_awburst = AXI_BURST;
    assign m_axi_wdata   = have_beat ? beat_data : 256'd0;
    assign m_axi_wstrb   = have_beat ? beat_strb : 32'd0;      // 空拍：一字节都不写
    assign m_axi_wvalid  = (a_st == A_W) & send_beat;
    assign m_axi_wlast   = (a_st == A_W) & send_beat & (w_idx == burst_m1[BEAT_CW-1:0]);
    assign m_axi_bready  = (a_st == A_B);
    assign axi_busy      = (a_st != A_IDLE) | (c_st != C_SYNC);

    always @(posedge clk_ddr or posedge rst_ddr) begin
        if (rst_ddr) begin
            a_st          <= A_IDLE;
            addr_r        <= 29'd0;
            base_r        <= 32'd0;
            m_axi_awaddr  <= 29'd0;
            m_axi_awlen   <= BURST_BEATS - 1;
            m_axi_awvalid <= 1'b0;
            beats_left    <= {BTL_CW{1'b0}};
            w_idx         <= {BEAT_CW{1'b0}};
            burst_m1      <= BURST_BEATS - 1;
            frame_close   <= 1'b0;
            frame_idx     <= 32'd0;
            axi_err       <= 1'b0;
            // 发布字的复位也归这里：这几个 reg 只在**本块**里被写
            //   （TD HDL-8007「constantly driven from multiple places」就是
            //    之前把它们同时放在发布握手段里复位造成的：同一个 reg 出现在
            //    两个 always 块里。iverilog 不报，TD 报 —— 所以改完必须过 TD。）
            pub_base      <= BASE0;
            pub_ok        <= 1'b0;
            pub_err       <= 16'd0;
            pub_tgl       <= 1'b0;
            err_cnt       <= 16'd0;
        end else begin
            frame_close <= 1'b0;

            case (a_st)
                // 一帧的数据侧一开始（packer 收到 SOF 进了 C_RUN）就起一帧
                A_IDLE: if (c_st == C_RUN) begin
                    base_r        <= (frame_idx[0]) ? BASE1 : BASE0;
                    addr_r        <= (frame_idx[0]) ? BASE1[28:0] : BASE0[28:0];
                    m_axi_awaddr  <= (frame_idx[0]) ? BASE1[28:0] : BASE0[28:0];
                    beats_left    <= NBEATS;
                    m_axi_awlen   <= AWLEN_FIRST;
                    burst_m1      <= AWLEN_FIRST;
                    w_idx         <= {BEAT_CW{1'b0}};
                    m_axi_awvalid <= 1'b1;
                    axi_err       <= 1'b0;
                    a_st          <= A_AW;
                end

                A_AW: if (m_axi_awready) begin
                    m_axi_awvalid <= 1'b0;
                    burst_m1      <= m_axi_awlen;    // 就用实际发出去的那一份
                    w_idx         <= {BEAT_CW{1'b0}};
                    a_st          <= A_W;
                end

                A_W: if (send_beat & m_axi_wready) begin
                    if (w_idx == burst_m1[BEAT_CW-1:0]) begin
                        w_idx <= {BEAT_CW{1'b0}};
                        a_st  <= A_B;
                    end else begin
                        w_idx <= w_idx + 1'b1;
                    end
                end

                A_B: if (m_axi_bvalid) begin
                    if (m_axi_bresp != 2'b00) axi_err <= 1'b1;      // 非 OKAY ⇒ 本帧不发布
                    if (beats_left == burst_beats) begin
                        a_st <= A_DONE;                             // 本帧突发全发完了
                    end else begin
                        beats_left    <= next_beats;
                        addr_r        <= addr_r + burst_step;
                        m_axi_awaddr  <= addr_r + burst_step;
                        m_axi_awlen   <= next_awlen;
                        m_axi_awvalid <= 1'b1;
                        a_st          <= A_AW;
                    end
                end

                // 等 packer 也收口（数据侧最后一拍已交出去）再判定/发布
                A_DONE: if ((c_st == C_END) & ~beat_vld) begin
                    if (pub_stuck) begin
                        // 回执丢了（tl 域被复位过）：把 toggle 对齐到回执值再继续，
                        // 本帧按坏帧计一次错（不发布）
                        pub_tgl <= pub_ack_s2;
                        err_cnt <= err_cnt + 16'd1;
                    end else if (pub_ack_s2 == pub_tgl) begin   // 上一帧已被 tl 域取走
                        pub_base <= base_r;
                        pub_ok   <= ~verdict_bad & ~axi_err;
                        pub_err  <= err_cnt + ((~verdict_bad & ~axi_err) ? 16'd0 : 16'd1);
                        pub_tgl  <= ~pub_tgl;
                        err_cnt  <= err_cnt + ((~verdict_bad & ~axi_err) ? 16'd0 : 16'd1);
                    end else begin
                        // 上一帧还没被取走（同步链慢，但没到 pub_stuck）：本帧丢弃，
                        // 不覆盖那几个字
                        err_cnt  <= err_cnt + 16'd1;
                    end
                    frame_idx    <= frame_idx + 32'd1;
                    frame_close  <= 1'b1;                // 让 packer 回 C_SYNC
                    m_axi_awaddr <= 29'd0;
                    a_st         <= A_IDLE;
                end

                default: a_st <= A_IDLE;
            endcase
        end
    end

    // 等回执等太久（正常情况下回执只要 ~10 拍）：说明 tl 域那一侧被复位过、
    // 回执丢了 —— 这时 pub_tgl 和 ack 会永远对不上，后面每一帧都会被丢掉。
    // 兜底：把 toggle 强制对齐到回执值（认账），再继续发下一帧。
    // 触发条件举例：只在 tl 域复位（rst_fb）时正好有一帧在握手中间。
    assign pub_stuck = (pub_wait_cnt == 17'h1_FFFF);    // 0.65ms @100MHz

    always @(posedge clk_ddr or posedge rst_ddr) begin
        // 本块只负责 pub_ack 的同步与等回执计时；pub_base/pub_ok/pub_err/pub_tgl/
        // err_cnt 由上面的 AXI 状态机块独家持有（一个 reg 只能出现在一个 always 块里）。
        if (rst_ddr) begin
            pub_ack_s1 <= 1'b0;
            pub_ack_s2 <= 1'b0;
            pub_wait_cnt <= 17'd0;
        end else begin
            pub_ack_s1 <= pub_ack;
            pub_ack_s2 <= pub_ack_s1;
            if (pub_ack_s2 == pub_tgl) pub_wait_cnt <= 17'd0;
            else                       pub_wait_cnt <= pub_wait_cnt + 17'd1;
        end
    end

    // ========================================================================
    //  tl_clk_user 域：取走帧结果、拼状态字、把诊断值采两拍、把 ack 回给 ddr 侧
    // ========================================================================
    reg  [15:0] err_cnt_fb;
    reg         valid_fb;
    reg         busy_s1,  busy_s2;
    reg         alive_s1, alive_s2;
    reg         cal_s1,   cal_s2;
    reg  [15:0] lines_s1, lines_s2, grp_s1, grp_s2;
    reg         anom_s1,  anom_s2;

    wire err_sticky_fb = (err_cnt_fb != 16'd0);

    always @(posedge clk_fb or posedge rst_fb) begin
        if (rst_fb) begin
            pub_tgl_s1 <= 1'b0; pub_tgl_s2 <= 1'b0; pub_tgl_s3 <= 1'b0;
            pub_ack    <= 1'b0;
            wr_frame_seq <= 32'd0;
            wr_base      <= 32'd0;
            wr_status    <= 32'd0;
            err_cnt_fb   <= 16'd0;
            valid_fb     <= 1'b0;
            busy_s1  <= 1'b0; busy_s2  <= 1'b0;
            alive_s1 <= 1'b0; alive_s2 <= 1'b0;
            cal_s1   <= 1'b0; cal_s2   <= 1'b0;
            lines_s1 <= 16'd0; lines_s2 <= 16'd0;
            grp_s1   <= 16'd0; grp_s2   <= 16'd0;
            anom_s1  <= 1'b0;  anom_s2  <= 1'b0;
            dbg_lines_per_frame  <= 16'd0;
            dbg_max_grp_per_line <= 16'd0;
            dbg_anomaly          <= 1'b0;
        end else begin
            pub_tgl_s1 <= pub_tgl;
            pub_tgl_s2 <= pub_tgl_s1;
            pub_tgl_s3 <= pub_tgl_s2;

            busy_s1  <= (c_st != C_SYNC);   busy_s2  <= busy_s1;
            alive_s1 <= ~rst_ddr;           alive_s2 <= alive_s1;
            cal_s1   <= ddr_cal_done;       cal_s2   <= cal_s1;

            // 诊断：慢变量直接采两拍（一帧才变一次，只给人看）
            lines_s1 <= frame_lines;   lines_s2 <= lines_s1;
            grp_s1   <= max_grp;       grp_s2   <= grp_s1;
            anom_s1  <= (drop_cnt != 16'd0) | (ovf_cnt != 16'd0);
            anom_s2  <= anom_s1;

            if (pub_tgl_s2 ^ pub_tgl_s3) begin        // ddr 侧发布了一帧
                if (pub_ok) begin
                    wr_frame_seq <= wr_frame_seq + 32'd1;
                    wr_base      <= pub_base;
                    valid_fb     <= 1'b1;
                end
                err_cnt_fb <= pub_err;
                pub_ack    <= pub_tgl_s2;             // 回执：可以发下一帧了
            end

            wr_status <= {err_cnt_fb, 11'd0, cal_s2, alive_s2, err_sticky_fb,
                          busy_s2, valid_fb};
            dbg_lines_per_frame  <= lines_s2;
            dbg_max_grp_per_line <= grp_s2;
            dbg_anomaly          <= anom_s2;
        end
    end

    assign wr_len = WR_LEN_W;

endmodule
