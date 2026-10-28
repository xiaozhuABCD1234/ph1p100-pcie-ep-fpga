///////////////////////////////////////////////////////////////////////////////
//  cam_r10f_writer.v — T11.rk-align-raw：正式非压缩 RAW10 → R10F v1 成帧写者
//
//  一、它在链路里的位置（与 cam_ddr_writer 的关系）
//  ===========================================================================
//  基线是 T07 的 cam_ddr_writer（8bit 灰度诊断帧）。本模块是**正式 RAW10 通路**：
//
//     checked CSI 4px 组（40bit，字节域 187.5MHz）
//       → 窗口裁剪（偶数 ROI，x 按 4 像素组取整）
//       → 异步 FIFO（1024 × {sof,eof,eof_bad,pix40}）
//       → DDR 域（100MHz）拼 5 字节/组 packed RAW10 字节流
//       → R10F v1 内容：128B 头 + packed 载荷 + 4KiB 对齐尾零（1080p 恰 640B）
//       → AXI4 写 DDR3（每帧固定 DMA_BEATS 拍 256bit；633 个 4KiB 突发 + 1 笔重写）
//       → 发布（wr_frame_seq/base/status，所有权 protect/release）→ pusher 发送
//
//  10bit 样本不静默变 8bit：每 4 像素组按合同 frame_contract.py 打包成 5 字节：
//    b0=P0[9:2] b1=P1[9:2] b2=P2[9:2] b3=P3[9:2] b4={P3[1:0],P2[1:0],P1[1:0],P0[1:0]}
//
//  二、R10F v1 头（128B，小端；与 contract/acceptance-vectors.json 逐字段一致）
//  ===========================================================================
//    0x00 magic "R10F"     0x04 version 1.0       0x08 header_bytes=128
//    0x0A camera_id        0x0B format=0         0x0C codec=0
//    0x10 session_id       0x14 capture_seq      0x18 mode_id
//    0x1C width            0x1E height           0x20 stride_bytes
//    0x24 roi_x            0x26 roi_y            0x28 bayer_phase
//    0x29 bayer_dir=0      0x2A valid_bits=10    0x2B packing=0
//    0x2C raw_bytes        0x30 payload_bytes（= raw，非压缩）    0x34 block_count=1
//    0x38/0x3C exposure/gain=0（本版无 AE 通路）   0x40 sof_timestamp=0  0x48 timestamp_hz=0
//    0x4C flags（ROI 原点非零 ⇒ 2=CROPPED，否则 0）0x50 raw_crc32  0x54 payload_crc32  0x58 header_crc32
//    0x5C..0x7F reserved=0
//  CRC32 IEEE reflected poly 0xEDB88320、init/final 全 1（与合同 crc32_rtl_style 一致）：
//    · raw/payload_crc32 都覆盖 packed 有效载荷；
//    · header_crc32 把 0x58..0x5B 清 0 后覆盖完整 128B；
//    · 尾零与 host 前缀/槽末填充不进任何 CRC。
//
//  三、为什么这么写（字节流组装与头 CRC 的三步）
//  ===========================================================================
//   1) 帧内容按**字节流**在 DDR 域组装：breg 是 16 字节窗口（最旧字节在低 8 位），
//      窗口做宽是为了让「取走一个字」和「插入一组(5B)」能在同一拍发生——见 bcnt 处注释。
//      每 4 字节消费成一个 32bit word，每 8 个 word 成为一个 256bit AXI 拍。
//      ── 源排序：header(4 拍) → packed 载荷 → 尾零，总长恒 = DMA_BYTES；
//      ── 载荷按 5 字节/组追加、头/尾按 4 字节/字追加；追加与消费同拍互斥。
//   2) 第 1 遍写头时三个 CRC 字段全 0（模板）；载荷字节全部消费完后，用一个 32 拍
//      专门遍历用**真 CRC 值**再生 128B 头并算 header_crc32（0x58 自身为 0）；
//      再用一笔 4 字节部分写（strb=0x0FFF0000，地址 base+64）把
//      0x50/0x54/0x58 写进 DDR。不把 128B 头存进任何 RAM。
//   3) 载荷 CRC 在**消费侧**按 4 字节/拍递推（扁平 XOR 树，见 crc32_upd4.v）：
//      末字按“实际有效载荷字节数”取 1..4 字节变体（短帧时 ep 在 EOF 冻结）。
//
//  四、发布裁决与所有权（沿用 T07 语义，坏帧绝不成为发送源）
//  ===========================================================================
//   · 只有当「本帧采集组数 == W*H/4」+「见到 EOF」+「无 good 缺失/abort/短行/
//     超预算组」+「DMA 拍数 == DMA_BEATS」+「bresp 全 OKAY」时 pub_ok=1；
//   · 写者发布即保护该块（protect），收到该块的 release toggle（pusher claim 后
//     ACK/CANCEL，或未 claim 的 pass）才允许重写；轮到被保护的块时整帧跳过；
//   · 坏帧仍把整区写完（缺数据处补 0）但不发布序号 —— pusher 只看发布序号；
//   · reset 隔离：ddr/tl 域各自复位清 pending，旧会话未发布内容不会被推。
//
//  五、几何/相位参数（板证前全部按“诊断/未板证”对待）
//  ===========================================================================
//   · W/H/X0/Y0/SKIP_ROWS 从源包实际 WC/行数**标定后写进参数**（本版默认
//     1920×1080、x=960、有效图 y=540、SKIP_ROWS=37 来自 T07 实测，未板证）；
//   · roi_y 记的是**有效图**坐标（跳过 dummy 之后）；物理原点 = SKIP_ROWS+Y0；
//   · ROI 相位 = SRC_BAYER_PHASE 按物理原点 (X0, SKIP_ROWS+Y0) 的奇偶推导：
//       new = src ^ (X0[0]?2:0) ^ (Y_PHYS[0]?3:0)（默认仅占位，需板证）。
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module cam_r10f_writer #(
    // ---- ROI 几何（按源实际 WC/行数标定后写死；“参数 = 标定结果”）----
    parameter integer W           = 1920,          // ROI 宽（像素；须为 4 的倍数）
    parameter integer H           = 1080,          // ROI 高（行）
    parameter [15:0]  X0          = 16'd960,       // ROI x 原点（源行内像素坐标；须为 4 的倍数）
    parameter [15:0]  Y0          = 16'd540,       // ROI y 原点（**有效图**坐标）
    parameter [15:0]  SKIP_ROWS   = 16'd37,        // 帧头 embedded + 物理哑行（4K 实测 37，未板证）
    // 行边界校验：1 = 每行组数必须等于 GPQ，否则整帧判坏（1080p ROI 用）；
    // 0 = 只看整帧组数与 AXI 拍数（全宽 4K 用：CSI 行分隔信号在 4K 全宽下不可靠，
    //     见 docs/BOARD_TEST.md「4K 行边界」；组数/拍数两项仍严格把关）。
    parameter integer LINE_CHECK  = 1,
    // ---- DDR3 双缓冲基址（4KiB 对齐，两块互不重叠且都 >= DMA_BYTES）----
    parameter [31:0]  BASE0       = 32'h0010_0000,
    parameter [31:0]  BASE1       = 32'h0090_0000,
    // ---- 异步 FIFO 深度 = 2**FIFO_AW 条（1 条 = 1 个 4 像素组 = 5 字节）----
    parameter integer FIFO_AW     = 10,
    parameter integer BURST_BEATS = 128,
    // ---- R10F 头参数 ----
    parameter [7:0]   CAMERA_ID        = 8'd0,
    parameter [1:0]   SRC_BAYER_PHASE  = 2'd0,     // 有效源相位（占位；板证前不得称已验证）
    parameter [31:0]  MODE_ID          = 32'd1,
    // ---- 帧内停滞兜底超时（丢标记/帧中止时的收口；仿真可调小）----
    parameter integer CLOSEDLOOP_EN = 0, // debug-only DHI ownership; default preserves legacy
    parameter [20:0]  TMO_LIMIT        = 21'h1F_FFFF,
    // ---- 数据侧长看门狗：mid_frame 期间锁住 tmo，光靠 TMO_LIMIT 兜不住
    //      「相机中途停流、帧尾组数永远到不了突发门槛」的永久卡死（板测已见）。
    //      这里单独计「等数据」的时长，超限就按坏帧自愈（不依赖帧内 tmo）。
    //      0xC0_0000 = 12,582,912 拍 @100MHz ≈ 125.8ms ≈ 3.8 个 30fps 帧周期；
    //      正常等满 410 组只需约 11us，余量 >10000 倍，低帧率模式也不会误触发。
    parameter [23:0]  WDT_LIMIT        = 24'hC0_0000
)(
    // ---------------- MIPI CSI-2 字节时钟域（187.5MHz）----------------
    input  wire          cam_clk,
    input  wire          cam_rst_n,
    input  wire          cam_vsync,
    input  wire          cam_in_frame,
    input  wire          cam_in_line,
    input  wire [39:0]   cam_pix,
    input  wire          cam_pix_valid,
    input  wire          cam_frame_good,
    input  wire          cam_frame_abort,
    // ---- 缓冲区所有权（tl 域电平/toggle，本模块同步）----
    input  wire          prot_en,
    input  wire          rel_tgl0,
    input  wire          rel_tgl1,

    // ---------------- tl_clk_user 域（62.5MHz）----------------
    input  wire          clk_fb,
    input  wire          rst_fb,
    input  wire [31:0]   session_id,      // 0x104（准静态；帧起点锁存进该帧头）
    output reg  [31:0]   wr_frame_seq,
    output reg  [31:0]   wr_base,
    output reg  [31:0]   wr_status,
    output wire [31:0]   wr_len,

    // ---------------- 诊断（tl 域采样；口径与 cam_ddr_writer 相同）----------------
    output reg  [15:0]   dbg_lines_per_frame,
    output reg  [15:0]   dbg_max_grp_per_line,
    output reg           dbg_anomaly,
    output wire [95:0]   dbg_drop,
    // AXI 各阶段最长连续停滞（单位 clk_ddr，饱和计数）+ 突发完成/收口超时次数：
    //   [15:0]  w 阶段最长停滞、[31:16] b 阶段、[47:32] aw 阶段、[63:48] rwd 阶段
    //   [79:72] 突发回执次数[7:0]、[95:88] rwd 超时自愈次数[7:0]
    output wire [95:0]   dbg_stall,
    // 每帧锁存的吞吐/丢组统计（只读诊断，帧收口时取样）：
    //   [31:0]  相机侧本帧实际入队像素组数
    //   [63:32] 相机侧本帧因 wfull 丢掉的像素组数
    //   [95:64] {frame_lines[15:0], y_cnt[15:0]}（EOF 时刻）
    //   [127:96]{16'd0, max_grp[15:0]}
    //   [159:128] 相机侧本帧因 wfull 丢掉的标记数（SOF/EOF）
    //   [191:160] DDR 侧本帧「打包占用」clk_ddr 周期数（不含 S_SYNC/S_WAIT）
    //   [223:192] 收口时刻的 gcnt
    //   [255:224]{27'd0, tmo_seen, p_bad, p_eof_seen, eof_bad_snap}
    output wire [255:0]  dbg_frame,
    // 板级调试用状态快照（只读，不参与任何数据/控制路径）：
    //   [2:0] a_st（AXI 写状态机）、[5:3] s_state（源状态机）、[6] hdr_ready、[7] pub 未回执
    output wire [8:0]    dbg_fsm,

    // ---------------- DDR 用户域（100MHz）----------------
    input  wire          clk_ddr,
    input  wire          rst_ddr,          // 高有效（= !ddrphy_rst_n）
    input  wire          ddr_cal_done,
    input  wire          arm,              // 1 = 本模块拥有 DDR 写口（顶层 sel_eff）
    output wire          axi_busy,

    // All closedloop ports are clk_ddr-domain; no multi-bit control CDC.
    input wire [1:0] cl_release,
    output reg cl_pub_valid,
    output reg [31:0] cl_pub_seq, cl_pub_base, cl_pub_session,
    output wire [31:0] cl_pub_len,
    output reg [31:0] cl_good_count, cl_bad_count,

    // ---------------- AXI4 写通道 ----------------
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
    localparam integer GPQ          = W / 4;                    // 每行 ROI 组数
    localparam integer GROUP_TOTAL  = W * H / 4;                // 整帧组数
    localparam integer PAY_BYTES    = W * H * 5 / 4;            // packed 载荷字节
    localparam integer STRIDE_BYTES = W * 5 / 4;                // 每行 packed 字节
    localparam [15:0]  Y_PHYS       = SKIP_ROWS + Y0;           // ROI 物理 y 原点
    localparam [1:0]   BAYER_DERIV  = SRC_BAYER_PHASE ^ (X0[0] ? 2'd2 : 2'd0)
                                                    ^ (Y_PHYS[0] ? 2'd3 : 2'd0);
    localparam integer HDR_BYTES    = 128;
    localparam integer DMA_BYTES    = ((PAY_BYTES + HDR_BYTES + 4095) / 4096) * 4096;
    localparam integer DMA_BEATS    = DMA_BYTES / 32;

    localparam [31:0]  PAY_BYTES32  = PAY_BYTES;
    localparam [31:0]  GROUP_TOT32  = GROUP_TOTAL;
    localparam [31:0]  DMA_BEATS32  = DMA_BEATS;
    localparam [31:0]  DMA_BYTES32  = DMA_BYTES;
    localparam [31:0]  STRIDE32     = STRIDE_BYTES;
    localparam [15:0]  W16          = W[15:0];
    localparam [15:0]  H16          = H[15:0];
    localparam [15:0]  GPQ16        = GPQ[15:0];
    //  flags：本模块只发布「裁剪后的正式 ROI 帧」；ROI 原点非零 ⇒ 置
    //  FLAG_CROPPED(bit1)=2，与 contract/acceptance-vectors.json 的 1080p 样例
    //  （roi=(960,540)、flags=2）语义一致；原点为 0 的未裁剪帧 flags=0。
    localparam [31:0]  FLAGS_VAL    = ((X0 != 16'd0) || (Y0 != 16'd0)) ? 32'd2 : 32'd0;

    localparam [2:0]   AXI_SIZE     = 3'd5;      // 2**5 = 32 字节/拍
    localparam [1:0]   AXI_BURST    = 2'b01;     // INCR

    function integer clogb2;
        input integer v;
        integer i;
        begin
            clogb2 = 0;
            for (i = v - 1; i > 0; i = i >> 1) clogb2 = clogb2 + 1;
        end
    endfunction

    localparam integer BEAT_CW  = clogb2(BURST_BEATS);
    localparam integer BTL_CW   = clogb2(DMA_BEATS);

    localparam [BTL_CW-1:0] BURST_BEATS_S = BURST_BEATS;   // 参数不能直接位选
    localparam [BTL_CW-1:0] DMA_BEATS_S   = DMA_BEATS;
    // 帧首只发 4 拍（128B 头）：载荷要等 ROI 起始行（577 行），帧首若一次抢 4KB，
    // 这一笔会开着等 9~18ms，axi_busy 一直为 1 把 DDR 写口压死。
    localparam [7:0]        AWLEN_FIRST   = (DMA_BEATS > BURST_BEATS) ? 8'd3
                                                                      : (DMA_BEATS - 1);

    function [FIFO_AW:0] bin2gray;
        input [FIFO_AW:0] b;
        begin
            bin2gray = b ^ (b >> 1);
        end
    endfunction

    // ========================================================================
    //  字节时钟域：行/列计数 + 窗口裁剪 + 组字 + 进 FIFO（与 cam_ddr_writer 同构）
    // ========================================================================
    reg [15:0] x_cnt;
    reg [15:0] y_cnt;
    reg        first_line;
    reg        vsync_d, in_frame_d, in_line_d;
    reg        frame_armed;
    reg [1:0]  arm_c;
    reg        good_seen;
    reg        abort_seen;

    wire [7:0]  g0 = cam_pix[9:2];
    wire [7:0]  g1 = cam_pix[19:12];
    wire [7:0]  g2 = cam_pix[29:22];
    wire [7:0]  g3 = cam_pix[39:32];
    // 低 2bit 字节 = {P3[1:0],P2[1:0],P1[1:0],P0[1:0]}（P0=[9:0]、P1=[19:10]、P2=[29:20]、P3=[39:30]）
    wire [7:0]  g4 = {cam_pix[31:30], cam_pix[21:20], cam_pix[11:10], cam_pix[1:0]};
    wire [39:0] pgroup = {g4, g3, g2, g1, g0};     // packed 40bit（g0 在最低字节）

    wire sof_evt  = cam_vsync & ~vsync_d;
    wire eof_evt  = ~cam_in_frame & in_frame_d;
    wire line_evt = cam_in_line & ~in_line_d;

    wire [15:0] y_img0 = Y0 + SKIP_ROWS;
    wire in_win = (x_cnt >= X0) && (x_cnt < (X0 + W16)) &&
                  (y_cnt >= y_img0) && (y_cnt < (y_img0 + H16));
    wire line_in_win = (y_cnt >= y_img0) && (y_cnt < (y_img0 + H16));

    reg [15:0] cur_grp;
    reg [15:0] max_grp;
    reg [15:0] frame_lines;
    reg [15:0] win_grp;
    reg        line_bad_seen;
    reg        alive_c1, alive_c2;
    wire       rst_cam_all = ~cam_rst_n | ~alive_c2;
    wire       last_line_bad = frame_armed && line_in_win && (win_grp != GPQ16);

    always @(posedge cam_clk or negedge cam_rst_n) begin
        if (!cam_rst_n) begin
            x_cnt <= 16'd0; y_cnt <= 16'd0; first_line <= 1'b1;
            vsync_d <= 1'b0; in_frame_d <= 1'b0; in_line_d <= 1'b0;
            frame_armed <= 1'b0; arm_c <= 2'd0;
            good_seen <= 1'b0; abort_seen <= 1'b0;
            cur_grp <= 16'd0; max_grp <= 16'd0; frame_lines <= 16'd0;
            win_grp <= 16'd0; line_bad_seen <= 1'b0;
            alive_c1 <= 1'b0; alive_c2 <= 1'b0;
        end else begin
            vsync_d    <= cam_vsync;
            in_frame_d <= cam_in_frame;
            in_line_d  <= cam_in_line;
            arm_c      <= {arm_c[0], arm};
            alive_c1   <= ~rst_ddr;
            alive_c2   <= alive_c1;

            if (cam_frame_good)  good_seen  <= 1'b1;
            if (cam_frame_abort) abort_seen <= 1'b1;

            if (sof_evt) begin
                x_cnt         <= 16'd0;
                y_cnt         <= 16'd0;
                first_line    <= 1'b1;
                frame_armed   <= arm_c[1];
                good_seen     <= 1'b0;
                abort_seen    <= 1'b0;
                cur_grp       <= 16'd0;
                max_grp       <= 16'd0;
                frame_lines   <= 16'd0;
                win_grp       <= 16'd0;
                line_bad_seen <= 1'b0;
            end else if (line_evt) begin
                x_cnt <= 16'd0;
                cur_grp <= 16'd0;
                frame_lines <= frame_lines + 16'd1;
                if (~first_line && line_in_win && frame_armed && (win_grp != GPQ16))
                    line_bad_seen <= 1'b1;
                win_grp <= 16'd0;
                if (first_line) first_line <= 1'b0;
                else            y_cnt <= y_cnt + 16'd1;
            end else if (cam_pix_valid) begin
                x_cnt   <= x_cnt + 16'd4;
                cur_grp <= cur_grp + 16'd1;
                if ((cur_grp + 16'd1) > max_grp) max_grp <= cur_grp + 16'd1;
                if (in_win && frame_armed) win_grp <= win_grp + 16'd1;
            end
            // 自愈：写指针已被清掉，帧窗口也一起放开，等下一条 SOF 重新武装
            if (self_flush_cam) frame_armed <= 1'b0;
        end
    end

    // ---- 入队（标记优先）----
    wire        push_sof = sof_evt & arm_c[1];
    wire        push_eof = eof_evt & frame_armed;
    wire        eof_good = cam_frame_good | good_seen;
    wire        line_warn = line_bad_seen | last_line_bad;
    wire        eof_bad  = (~eof_good) | abort_seen | cam_frame_abort |
                           (LINE_CHECK ? line_warn : 1'b0);
    wire        push_pix = cam_pix_valid & in_win & frame_armed & ~push_sof & ~push_eof;
    wire        push     = push_sof | push_eof | push_pix;
    wire [42:0] f_din    = {push_sof, push_eof, (push_eof & eof_bad), pgroup};

    // ---- 异步 FIFO（写口简单 → ERAM20K；读口输出寄存器在 ddr 域）----
    reg  [42:0]      f_mem [0:(1 << FIFO_AW) - 1];
    reg  [FIFO_AW:0] wptr_bin,  wptr_gray;
    reg  [FIFO_AW:0] rptr_bin,  rptr_gray;
    reg  [FIFO_AW:0] wgray_s1,  wgray_s2;
    reg  [FIFO_AW:0] rgray_s1,  rgray_s2;

    wire [FIFO_AW:0] wptr_bin_nxt  = wptr_bin + {{FIFO_AW{1'b0}}, 1'b1};
    wire [FIFO_AW:0] wptr_gray_nxt = bin2gray(wptr_bin_nxt);
    wire [FIFO_AW:0] rptr_bin_nxt  = rptr_bin + {{FIFO_AW{1'b0}}, 1'b1};
    wire [FIFO_AW:0] rptr_gray_nxt = bin2gray(rptr_bin_nxt);

    wire wfull = (wptr_gray_nxt == {~rgray_s2[FIFO_AW:FIFO_AW-1], rgray_s2[FIFO_AW-2:0]});
    wire f_wr  = push & ~wfull;

    always @(posedge cam_clk)
        if (f_wr) f_mem[wptr_bin[FIFO_AW-1:0]] <= f_din;

    // ddr 域自愈请求同步到 cam 域（self_flush 有 255 拍宽，2 级同步够用）
    reg [1:0] self_flush_c1;
    always @(posedge cam_clk or posedge rst_cam_all) begin
        if (rst_cam_all) self_flush_c1 <= 2'b00;
        else             self_flush_c1 <= {self_flush_c1[0], self_flush};
    end
    wire self_flush_cam = self_flush_c1[1];

    always @(posedge cam_clk or posedge rst_cam_all) begin
        if (rst_cam_all || self_flush_cam) begin
            wptr_bin  <= {(FIFO_AW+1){1'b0}};
            wptr_gray <= {(FIFO_AW+1){1'b0}};
        end else if (f_wr) begin
            wptr_bin  <= wptr_bin_nxt;
            wptr_gray <= wptr_gray_nxt;
        end
    end

    always @(posedge cam_clk or posedge rst_cam_all) begin
        if (rst_cam_all) begin rgray_s1 <= {(FIFO_AW+1){1'b0}}; rgray_s2 <= {(FIFO_AW+1){1'b0}}; end
        else begin rgray_s1 <= rptr_gray; rgray_s2 <= rgray_s1; end
    end

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

    // ---- 每帧统计（诊断）：帧首清零、EOF 锁存 ----
    // 关键点：win_grp 只按「窗口内像素」计数，与 wfull 无关，所以 FIFO 溢出丢组
    // **不会**让 line_bad_seen / eof_bad 置位——这正是「gcnt 偏短但 p_bad=0」的
    // 唯一自洽解释。这里把「实际入队组数」和「因满丢掉的组数」分开数出来。
    reg [31:0] fr_push, fr_drop, fr_ovf;
    reg [31:0] sn_push, sn_drop, sn_ovf;
    reg [15:0] sn_lines, sn_y, sn_maxgrp;
    reg        sn_eofbad;
    always @(posedge cam_clk or negedge cam_rst_n) begin
        if (!cam_rst_n) begin
            fr_push  <= 32'd0; fr_drop  <= 32'd0; fr_ovf   <= 32'd0;
            sn_push  <= 32'd0; sn_drop  <= 32'd0; sn_ovf   <= 32'd0;
            sn_lines <= 16'd0; sn_y     <= 16'd0; sn_maxgrp<= 16'd0;
            sn_eofbad<= 1'b0;
        end else if (rst_cam_all) begin
            fr_push  <= 32'd0; fr_drop  <= 32'd0; fr_ovf   <= 32'd0;
        end else begin
            if (sof_evt) begin
                fr_push <= 32'd0; fr_drop <= 32'd0; fr_ovf <= 32'd0;
            end else begin
                if (f_wr & push_pix)          fr_push <= fr_push + 32'd1;
                if (push_blocked & push_pix)  fr_drop <= fr_drop + 32'd1;
                if (push_blocked & ~push_pix) fr_ovf  <= fr_ovf  + 32'd1;
            end
            if (eof_evt & frame_armed) begin
                sn_push   <= fr_push;
                sn_drop   <= fr_drop;
                sn_ovf    <= fr_ovf;
                sn_lines  <= frame_lines;
                sn_y      <= y_cnt;
                sn_maxgrp <= max_grp;
                sn_eofbad <= eof_bad;
            end
        end
    end

    // ========================================================================
    //  ddr 域：声明区（先声明后使用）
    // ========================================================================
    reg  [42:0] f_dout;
    reg         ent_vld;

    localparam [2:0] S_SYNC  = 3'd0,
                     S_HDR   = 3'd1,
                     S_PAY   = 3'd2,
                     S_TAIL  = 3'd3,
                     S_DRAIN = 3'd4,
                     S_WAIT  = 3'd5,
                     S_SKIP  = 3'd6;
    reg  [2:0]  s_state;
    reg  [4:0]  hcnt;
    // ★ 128bit 字节缓冲 + 5bit 占用计数：允许「取走一个字」与「插入一组」同拍进行。
    //   原来的 64bit/4bit 组合下 pay_room(bcnt<=3) 与 word_take(bcnt>=4) 天然互斥，
    //   每 5 字节一组要花 1 拍 pop + 1.25 拍取字 ≈ 2.25 拍/组；双路合计
    //   2*(518400+648192)=2.33M 拍 > 一帧只有 2.08M 拍（62.5MHz）→ 物理上做不完。
    reg  [4:0]  bcnt;
    reg  [127:0] breg;
    reg  [255:0] pack;
    reg  [2:0]  wlane;
    reg         beat_vld;
    reg  [255:0] beat_data;
    reg  [31:0] beat_cnt;
    reg  [31:0] apos;
    reg  [31:0] cpos;
    reg  [31:0] pay_written;
    reg  [31:0] pay_ep;
    reg         ep_frozen;
    reg  [31:0] gcnt;
    reg  [31:0] frame_ord;
    reg  [31:0] f_sess;
    reg  [31:0] f_seq;
    reg         p_bad;
    reg         p_eof_seen;
    reg  [31:0] extra_drop;
    reg  [31:0] crc_pay_q;
    reg  [4:0]  hcnt2;
    reg         hdr_run;
    reg         hdr_done_r;
    reg  [31:0] crc_hdr_q;
    reg  [31:0] hdr_crc_r;
    reg  [20:0] tmo;
    reg  [23:0] wdt;                 // 无前进拍数（数据侧长看门狗）
    reg  [31:0] apos_snap, cpos_snap; // 上一拍进度快照（判停滞用）
    reg  [2:0]  s_state_snap;
    reg         st_frame_go;
    reg         st_skip_done;

    // ---- 所有权同步 ----（块 C）
    reg        prot_en_s1, prot_en_s2;
    reg        rel0_s1, rel0_s2, rel0_s3;
    reg        rel1_s1, rel1_s2, rel1_s3;
    reg        protect0, protect1;
    reg  [31:0] sess_s1, sess_s2;
    reg  [31:0] frame_idx;

    wire rel0_evt = CLOSEDLOOP_EN ? cl_release[0] : (rel0_s2 ^ rel0_s3);
    wire rel1_evt = CLOSEDLOOP_EN ? cl_release[1] : (rel1_s2 ^ rel1_s3);
    wire protect_enabled = CLOSEDLOOP_EN || prot_en_s2;
    wire blk_locked = protect_enabled & (frame_idx[0] ? protect1 : protect0);
    assign cl_pub_len = DMA_BYTES32;
    wire skip_frm_done = st_skip_done;

    // ---- 发布握手/裁决（块 B）----
    localparam [2:0] A_IDLE = 3'd0, A_AW = 3'd1, A_W = 3'd2, A_B = 3'd3,
                     A_RWD  = 3'd4, A_RW = 3'd5, A_RW2 = 3'd6, A_RW3 = 3'd7;
    reg  [2:0]         a_st;
    reg  [28:0]        addr_r;
    reg  [31:0]        base_r;
    reg  [BTL_CW-1:0]  beats_left;
    reg  [BEAT_CW-1:0] w_idx;
    reg  [7:0]         burst_m1;
    reg                frame_close;
    reg                axi_err;
    reg                rw_done_r;
    reg                mid_frame;      // 帧内还有突发没发：停在 A_IDLE 等数据
    reg                need_first;     // 帧首那一笔（4 拍头）无条件放行
    reg  [16:0]        pub_wait_cnt;
    reg                pub_ack;
    reg  [31:0]        pub_base;
    reg                pub_ok;
    reg  [15:0]        pub_err;
    reg  [15:0]        c_stuck, c_notack, c_bad, wcnt_last, beats_last;
    reg  [7:0]         verdict_snap;
    reg                pub_tgl;
    reg                pub_ack_s1, pub_ack_s2;
    reg  [15:0]        err_cnt;
    reg                pub_par;          // 本帧实际用的块（发布置保护用它，不能用自增后的 frame_idx）

    // ========================================================================
    //  头字生成 + 扁平 CRC-32 递推（函数/包含必须在所有使用之前）
    // ========================================================================
    // R10F 头第 n 个字（写第 1 遍 wraw/wpay=0；CRC 遍历传真值；0x58 恒 0）
    function [31:0] hdr_word;
        input [4:0]  n;
        input [31:0] wraw;
        input [31:0] wpay;
        begin
            case (n)
                5'd0:    hdr_word = 32'h4630_3152;                       // "R10F"
                5'd1:    hdr_word = 32'h0000_0001;                       // version 1.0
                5'd2:    hdr_word = {8'h00, CAMERA_ID, 16'h0080};        // header_bytes=128
                5'd3:    hdr_word = 32'd0;                               // codec_id=0
                5'd4:    hdr_word = f_sess;                              // session_id
                5'd5:    hdr_word = f_seq;                               // capture_seq
                5'd6:    hdr_word = MODE_ID;                             // mode_id
                5'd7:    hdr_word = {H16, W16};                          // width/height
                5'd8:    hdr_word = STRIDE32;                            // stride_bytes
                5'd9:    hdr_word = {Y0, X0};                            // roi_x / roi_y
                5'd10:   hdr_word = {8'h00, 8'd10, 8'h00, 6'd0, BAYER_DERIV}; // phase/dir/bits/pack
                5'd11:   hdr_word = PAY_BYTES32;                         // raw_bytes
                5'd12:   hdr_word = PAY_BYTES32;                         // payload_bytes
                5'd13:   hdr_word = 32'd1;                               // block_count
                5'd14:   hdr_word = 32'd0;                               // exposure_code
                5'd15:   hdr_word = 32'd0;                               // gain_code
                5'd16:   hdr_word = 32'd0;                               // sof_timestamp[31:0]
                5'd17:   hdr_word = 32'd0;                               // sof_timestamp[63:32]
                5'd18:   hdr_word = 32'd0;                               // timestamp_hz
                5'd19:   hdr_word = FLAGS_VAL;                           // flags（ROI 裁减置 CROPPED）
                5'd20:   hdr_word = wraw;                                // raw_crc32
                5'd21:   hdr_word = wpay;                                // payload_crc32
                5'd22:   hdr_word = 32'd0;                               // header_crc32（恒 0）
                default: hdr_word = 32'd0;                               // reserved 0
            endcase
        end
    endfunction

    // 扁平 4 字节/拍 CRC-32 递推函数（生成文件；含在模块体内满足 Verilog-2001）
    `include "crc32_upd4.v"

    // ========================================================================
    //  ddr 域：FIFO 读侧
    // ========================================================================
    wire pop;
    wire rempty     = (rptr_gray == wgray_s2);
    wire rempty_nxt = (rptr_gray_nxt == wgray_s2);
    wire is_sof  = ent_vld &  f_dout[42];
    wire is_eof  = ent_vld & (f_dout[41] | f_dout[40]);
    wire is_eofb = ent_vld &  f_dout[40];
    wire is_grp  = ent_vld & ~f_dout[42] & ~f_dout[41] & ~f_dout[40];
    wire [39:0] e_grp = f_dout[39:0];

    wire beat_taken = (a_st == A_W) & m_axi_wready & beat_vld;
    wire beat_busy  = beat_vld & ~beat_taken;
    wire data_ready = ~beat_busy;
    wire word_take  = (bcnt >= 4'd4) & data_ready &
                      (s_state != S_SYNC) & (s_state != S_SKIP);
    wire [31:0] word_now = breg[31:0];

    wire pay_room  = (bcnt <= 5'd10);   // 空出 5 字节：bcnt+5 <= 15
    wire hdr_room  = (bcnt <= 5'd11);   // 空出 4 字节：bcnt+4 <= 15
    wire tail_need = (apos < DMA_BYTES32);
    wire pay_ok    = ((pay_written + 32'd5) <= PAY_BYTES32);

    wire pop_sync = ent_vld;
    wire pop_pay  = (s_state == S_PAY)  & is_grp & pay_room;
    wire pop_mark = (s_state == S_PAY)  & (is_eof | is_sof);
    wire pop_skp  = ent_vld;
    assign pop = (s_state == S_SYNC) ? pop_sync :
                 (s_state == S_SKIP) ? pop_skp :
                 (s_state == S_PAY)  ? (data_ready & (pop_pay | pop_mark)) :
                 1'b0;

    /*
     * 相机域复位必须把读侧指针一起清掉 —— 否则跨域 FIFO 会永久失配。
     *
     * 写指针只在 cam_clk 域，复位源是 rst_cam_all（= !cam_rst_n | !alive_c2，
     * 相机掉时钟/链路抖动都会拉高），是**异步**清 0；而读指针原来只认 rst_ddr。
     * 一旦相机侧重置一次、DDR 侧没重置，wptr 归 0 而 rptr 停在旧值：
     *   · rempty 永远不成立 → 读侧一直「有数据」，取到的是垃圾；
     *   · wfull 按错的 rptr 判 → 写侧很快报满，组被丢光。
     * 板上表现就是写者每帧只写进去 1023 组（正好卡在 FIFO 深度）后整帧超时，
     * 且该路永远恢复不了（板测：B 路 seq 卡死、beats 却是整帧长度）。
     *
     * 这里把 rst_cam_all 同步到 ddr 域并在清零后保持若干拍，让读侧与写侧同拍归零。
     */
    reg [1:0]  cam_rst_sync;
    reg [7:0]  cam_flush_cnt;
    always @(posedge clk_ddr or posedge rst_ddr) begin
        if (rst_ddr) begin
            cam_rst_sync  <= 2'b11;
            cam_flush_cnt <= 8'hFF;
        end else begin
            cam_rst_sync <= {cam_rst_sync[0], rst_cam_all};
            if (cam_rst_sync[1])      cam_flush_cnt <= 8'hFF;      // 见到相机复位就重新装
            else if (cam_flush_cnt != 8'd0) cam_flush_cnt <= cam_flush_cnt - 8'd1;
        end
    end
    wire cam_flush = (cam_flush_cnt != 8'd0);

    always @(posedge clk_ddr or posedge rst_ddr) begin
        if (rst_ddr || cam_flush || self_flush) begin
            rptr_bin  <= {(FIFO_AW+1){1'b0}};
            rptr_gray <= {(FIFO_AW+1){1'b0}};
            ent_vld   <= 1'b0;
        end else begin
            ent_vld <= pop ? ~rempty_nxt : ~rempty;
            if (pop) begin
                rptr_bin  <= rptr_bin_nxt;
                rptr_gray <= rptr_gray_nxt;
            end
        end
    end

    always @(posedge clk_ddr)
        f_dout <= f_mem[pop ? rptr_bin_nxt[FIFO_AW-1:0] : rptr_bin[FIFO_AW-1:0]];

    /*
     * 连续坏帧自愈（板测：某一路会永久卡在「整帧补零」状态，只有重新 arm 才恢复）。
     *
     * 触发：连续 8 帧判定坏 → 拉 255 拍 self_flush。
     * 动作：ddr 域把读指针归零、流状态机回 S_SYNC；cam 域收到同步后的 self_flush 后把
     *       写指针归零并让 frame_armed 掉下来，等下一条 SOF 重新开始。
     * 为什么安全：两侧指针同时归零 → FIFO 回到「空且对齐」；被扔掉的那一帧本来就是
     *       坏帧（会进 err_cnt），不会发布给主机。
     */
    reg  [3:0]  bad_streak_ddr;
    reg  [7:0]  self_flush_cnt;
    wire        self_flush = (self_flush_cnt != 8'd0);

    always @(posedge clk_ddr or posedge rst_ddr) begin
        if (rst_ddr) begin wgray_s1 <= {(FIFO_AW+1){1'b0}}; wgray_s2 <= {(FIFO_AW+1){1'b0}}; end
        else begin wgray_s1 <= wptr_gray; wgray_s2 <= wgray_s1; end
    end

    /*
     * 突发级流控（T07 收帧卡死修复）：每笔突发结束回 A_IDLE 交还 DDR 写口，
     * 等 FIFO 有足够数据再发下一笔；帧首那一笔只有 4 拍（只写头）且无条件放行。
     * 门槛从 827 降到 500：v4 用 827 时 FIFO 只剩 ~197 组余量（一行就 480 组），
     * 末段 wfull 会丢几个组（板测整帧差 4 组、verdict=0x4）。降到 500 后余量 ≈524 组，
     * 代价是发出时 FIFO 可能不足一整笔 128 拍，突发会在中途等一点数据（端口占用略升）。
     */
    function [FIFO_AW:0] gray2bin;
        input [FIFO_AW:0] g;
        integer i;
        begin
            gray2bin[FIFO_AW] = g[FIFO_AW];
            for (i = FIFO_AW-1; i >= 0; i = i - 1)
                gray2bin[i] = gray2bin[i+1] ^ g[i];
        end
    endfunction

    wire [FIFO_AW:0] wbin_sync_ddr = gray2bin(wgray_s2);
    wire [FIFO_AW:0] fifo_occ_ddr  = wbin_sync_ddr - rptr_bin;
    // 64 拍突发 = 409.6 组。门槛必须 >=「2 笔突发的量」，否则一笔突发发到尾部时
    // FIFO 已经见底，wvalid 会断流（此时 busy=1 把写口钉住），双路时正好把换手窗口
    // 和 W 断流撞在一起。820 组 = 4100B ≈ 2 笔，发完还剩一整笔余量。
    // ★ 实测教训（2026-10-27 板测）：门槛不能超过「FIFO 深度 - 帧尾剩余量」的约束。
    //   820 组时，帧尾剩不到 820 组 → 写者停发 → 相机写到 wfull 丢 EOF 标记 → 超时收口，
    //   B 单路 wcnt 从 0xE900 掉到 0xD304、verdict=0x4（好帧 0）。410（一笔突发）是已验证
    //   可用值，改大必须先解决「帧尾没到门槛也继续发」的问题。
    localparam integer BURST_GROUPS = 410;
    wire tail_phase_ddr = (s_state == S_TAIL) || (s_state == S_DRAIN) || (s_state == S_WAIT);
    wire burst_ok_ddr   = tail_phase_ddr || (fifo_occ_ddr >= BURST_GROUPS);

    // ========================================================================
    //  ddr 域：载荷 CRC（消费侧 4 字节/拍；末字按实际有效载荷字节取变体）
    // ========================================================================
    wire [31:0] pay_lim_now = ep_frozen ? (32'd128 + pay_ep) : (32'd128 + PAY_BYTES32);
    wire [31:0] win_lo = (cpos > 32'd128) ? cpos : 32'd128;
    wire [31:0] win_hi = (cpos + 32'd4 < pay_lim_now) ? (cpos + 32'd4) : pay_lim_now;
    wire [31:0] pay_in_word32 = (win_hi > win_lo) ? (win_hi - win_lo) : 32'd0;
    wire [2:0]  pay_k = pay_in_word32[2:0];

    wire [31:0] crc_u1 = crc32_upd1(crc_pay_q, word_now[7:0]);
    wire [31:0] crc_u2 = crc32_upd2(crc_pay_q, word_now[7:0], word_now[15:8]);
    wire [31:0] crc_u3 = crc32_upd3(crc_pay_q, word_now[7:0], word_now[15:8], word_now[23:16]);
    wire [31:0] crc_u4 = crc32_upd4(crc_pay_q, word_now[7:0], word_now[15:8],
                                    word_now[23:16], word_now[31:24]);
    wire [31:0] crc_pay_nxt = (pay_k >= 3'd4) ? crc_u4 :
                              (pay_k == 3'd3) ? crc_u3 :
                              (pay_k == 3'd2) ? crc_u2 :
                              (pay_k == 3'd1) ? crc_u1 : crc_pay_q;
    wire [31:0] crc_pay_final = ~crc_pay_q;
    wire        crc_take = word_take & (pay_k != 3'd0);
    wire        pay_crc_ready = ep_frozen && (cpos >= (32'd128 + pay_ep));

    // 头 CRC 遍历（32 拍；CRC 字段用真值、0x58 自身 0）
    wire [31:0] hdr_w2 = hdr_word(hcnt2, crc_pay_final, crc_pay_final);
    wire [31:0] crc_hdr_nxt = crc32_upd4(crc_hdr_q, hdr_w2[7:0], hdr_w2[15:8],
                                         hdr_w2[23:16], hdr_w2[31:24]);

    // 追加源（128bit 缓冲）：插入与取字同拍时，先把已发出的 4 字节移出，
    // 再把新字节拼在「移出后」的偏移上，这样绝不覆盖还没发走的字。
    wire [4:0]   bcnt_base = word_take ? (bcnt - 5'd4) : bcnt;
    wire [127:0] breg_base = word_take ? {{96{1'b0}}, breg[127:32]} : breg;
    wire [6:0]   ins_sh    = {bcnt_base, 3'b000};
    wire [127:0] pay_ins   = {{88{1'b0}}, e_grp} << ins_sh;
    wire [127:0] hdr_ins   = {{96{1'b0}}, hdr_word(hcnt, 32'd0, 32'd0)} << ins_sh;
    wire pay_app  = (s_state == S_PAY)  & is_grp & pay_room & data_ready & pay_ok;
    wire hdr_app  = (s_state == S_HDR)  & hdr_room & data_ready;
    wire tail_app = (s_state == S_TAIL) & hdr_room & data_ready & tail_need;

    wire tmo_hit = (tmo == TMO_LIMIT);

    // ---- 数据侧长看门狗（与帧内 tmo 独立）----
    // 条件「A_IDLE 里还有突发没发、但 FIFO 永远攒不到 410 组」= 相机停流/丢标记，
    // 此时 mid_frame=1 让帧内 tmo 一直被清零，只能靠这条长计时兜底。
    // 通用停滞判据：不只是 A_IDLE+mid_frame。板测「相机中途 XCLR/停流」会把
    // 状态机留在 S_TAIL（0x170=0x18）等一个永远不来的 tail_app，旧条件
    // (a_st==A_IDLE && mid_frame) 在 S_TAIL 下 burst_ok_ddr 恒 1，永远不触发。
    // 这里改成：只要不在 S_SYNC、AXI 处于 A_IDLE（没有在飞的写事务）、且
    // apos/cpos/pop/beat/frame_close 在 WDT_LIMIT 拍内没有任何前进，就自愈。
    wire wdt_active   = (s_state != S_SYNC) && (a_st == A_IDLE) && !self_flush;
    wire wdt_progress = (s_state != s_state_snap) | (apos != apos_snap) |
                        (cpos != cpos_snap) | pop | beat_taken | frame_close;
    wire waiting_data = wdt_active & ~wdt_progress;
    wire wdt_hit      = (wdt == WDT_LIMIT) && waiting_data;

    // ========================================================================
    //  ddr 域：流状态机 + 消费路径（块 A）
    // ========================================================================
    always @(posedge clk_ddr or posedge rst_ddr) begin
        if (rst_ddr) begin
            s_state   <= S_SYNC;
            hcnt      <= 5'd0;
            bcnt      <= 5'd0;
            breg      <= 128'd0;
            pack      <= 256'd0;
            wlane     <= 3'd0;
            beat_vld  <= 1'b0;
            beat_data <= 256'd0;
            beat_cnt  <= 32'd0;
            apos      <= 32'd0;
            cpos      <= 32'd0;
            pay_written <= 32'd0;
            pay_ep    <= 32'd0;
            ep_frozen <= 1'b0;
            gcnt      <= 32'd0;
            frame_ord <= 32'd0;
            f_sess    <= 32'd0;
            f_seq     <= 32'd0;
            p_bad     <= 1'b1;
            p_eof_seen<= 1'b0;
            extra_drop<= 32'd0;
            crc_pay_q <= 32'hFFFF_FFFF;
            hcnt2     <= 5'd0;
            hdr_run   <= 1'b0;
            hdr_done_r<= 1'b0;
            crc_hdr_q <= 32'hFFFF_FFFF;
            hdr_crc_r <= 32'd0;
            tmo       <= 21'd0;
            st_frame_go  <= 1'b0;
            st_skip_done <= 1'b0;
        end else begin
            st_frame_go  <= 1'b0;
            st_skip_done <= 1'b0;

            // ---- 消费路径 ----
            if (beat_vld & beat_taken) beat_vld <= 1'b0;
            // 取字：字节缓冲右移 4 字节（插入同拍发生时由下面的状态机覆盖为合成值）
            if (word_take) begin
                bcnt <= bcnt_base;
                breg <= breg_base;
                if (wlane == 3'd7) begin
                    beat_vld  <= 1'b1;
                    beat_data <= {word_now, pack[223:0]};
                    wlane     <= 3'd0;
                    pack      <= 256'd0;
                    beat_cnt  <= beat_cnt + 32'd1;
                end else begin
                    case (wlane)
                        3'd0: pack[31:0]    <= word_now;
                        3'd1: pack[63:32]   <= word_now;
                        3'd2: pack[95:64]   <= word_now;
                        3'd3: pack[127:96]  <= word_now;
                        3'd4: pack[159:128] <= word_now;
                        3'd5: pack[191:160] <= word_now;
                        3'd6: pack[223:192] <= word_now;
                        default: pack[255:224] <= word_now;
                    endcase
                    wlane <= wlane + 3'd1;
                end
                cpos <= cpos + 32'd4;
                if (crc_take) crc_pay_q <= crc_pay_nxt;
            end

            // ---- 帧内停滞超时（丢标记兜底；约 10ms @100MHz）----
            // 等突发数据（mid_frame，没有突发在飞）时不计超时
            // 注：这个条件会让「相机中途停掉、帧尾组数永远到不了 410 门槛」的那一路
            //     永久卡在 S_PAY（板测已见）。修它需要单独的长看门狗，不宜和吞吐改动
            //     混在一次构建里，故本轮保持原样、只记录。
            if (((s_state == S_PAY) | (s_state == S_SKIP) | (s_state == S_HDR)) &&
                !pop && !mid_frame) begin
                if (!tmo_hit) tmo <= tmo + 21'd1;
            end else tmo <= 21'd0;

            // ---- 头 CRC 遍历 ----
            if (!hdr_done_r && !hdr_run) begin
                if (pay_crc_ready) begin
                    hdr_run   <= 1'b1;
                    hcnt2     <= 5'd0;
                    crc_hdr_q <= 32'hFFFF_FFFF;
                end
            end else if (hdr_run) begin
                if (hcnt2 == 5'd31) begin
                    hdr_run    <= 1'b0;
                    hdr_done_r <= 1'b1;
                    hdr_crc_r  <= ~crc_hdr_nxt;
                    hcnt2      <= 5'd0;
                end else begin
                    hcnt2     <= hcnt2 + 5'd1;
                    crc_hdr_q <= crc_hdr_nxt;
                end
            end

            // ---- 流状态机 ----
            case (s_state)
            S_SYNC: begin
                if (pop & is_sof) begin
                    frame_ord   <= frame_ord + 32'd1;
                    f_seq       <= frame_ord + 32'd1;
                    f_sess      <= sess_s2;
                    p_bad       <= 1'b0;
                    p_eof_seen  <= 1'b0;
                    gcnt        <= 32'd0;
                    pay_written <= 32'd0;
                    ep_frozen   <= 1'b0;
                    pay_ep      <= 32'd0;
                    apos        <= 32'd0;
                    cpos        <= 32'd0;
                    bcnt        <= 5'd0;
                    breg        <= 128'd0;
                    pack        <= 256'd0;
                    wlane       <= 3'd0;
                    beat_cnt    <= 32'd0;
                    crc_pay_q   <= 32'hFFFF_FFFF;
                    hcnt        <= 5'd0;
                    hcnt2       <= 5'd0;
                    hdr_run     <= 1'b0;
                    hdr_done_r  <= 1'b0;
                    extra_drop  <= 32'd0;
                    if (blk_locked) begin
                        s_state <= S_SKIP;
                        p_bad   <= 1'b1;
                    end else begin
                        s_state     <= S_HDR;
                        st_frame_go <= 1'b1;
                    end
                end
            end

            S_HDR: begin
                if (hdr_app) begin
                    breg <= breg_base | hdr_ins;
                    bcnt <= bcnt_base + 5'd4;
                    apos <= apos + 32'd4;
                    if (hcnt == 5'd31) begin
                        hcnt    <= 5'd0;
                        s_state <= S_PAY;
                    end else hcnt <= hcnt + 5'd1;
                end
            end

            S_PAY: begin
                if (pay_app) begin
                    breg <= breg_base | pay_ins;
                    bcnt <= bcnt_base + 5'd5;
                    apos        <= apos + 32'd5;
                    pay_written <= pay_written + 32'd5;
                    gcnt        <= gcnt + 32'd1;
                end else if (pop & is_grp & pay_room & ~pay_ok) begin
                    p_bad <= 1'b1;                       // 超预算的组：丢弃 + 记坏
                    if (extra_drop != 32'hFFFF_FFFF) extra_drop <= extra_drop + 32'd1;
                end
                if (pop & is_eof) begin
                    p_eof_seen <= 1'b1;
                    ep_frozen  <= 1'b1;
                    pay_ep     <= pay_written;
                    if (is_eofb) p_bad <= 1'b1;
                    s_state    <= S_TAIL;
                end else if (pop & is_sof) begin
                    p_bad <= 1'b1;                       // 帧内又见 SOF：按坏处理，继续填
                end else if (tmo_hit) begin
                    p_bad      <= 1'b1;                  // 丢标记兜底：强制收口
                    ep_frozen  <= 1'b1;
                    pay_ep     <= pay_written;
                    s_state    <= S_TAIL;
                end
            end

            S_TAIL: begin
                if (tail_app) begin
                    breg <= breg_base;
                    bcnt <= bcnt_base + 5'd4;
                    apos <= apos + 32'd4;
                end
                if (apos >= DMA_BYTES32) s_state <= S_DRAIN;
            end

            S_DRAIN: begin
                if ((cpos >= DMA_BYTES32) && (bcnt < 4'd4)) s_state <= S_WAIT;
            end

            S_WAIT: begin
                if (frame_close) begin
                    s_state <= S_SYNC;
                    p_bad   <= 1'b1;      // 下一帧必须重新见 SOF
                end
            end

            S_SKIP: begin
                if (pop & is_eof) begin
                    p_eof_seen   <= 1'b1;
                    st_skip_done <= 1'b1;
                    s_state      <= S_WAIT;
                end else if (pop & is_sof) begin
                    p_bad <= 1'b1;
                end else if (tmo_hit) begin
                    st_skip_done <= 1'b1;
                    s_state      <= S_WAIT;
                end
            end

            default: s_state <= S_SYNC;
            endcase

            // 自愈期间把流状态机拨回 S_SYNC，等下一条 SOF 重新对齐
            // （self_flush_cnt 的递减在 a_st 那个 always 块里做，避免同一寄存器多驱动）
            // ★ 只回 S_SYNC 不够：卡死时 beat_vld 已经为 1，data_ready=~beat_busy 恒 0，
            //   下一帧连 S_HDR 都进不去。自愈必须把字节/拍流水一起清空。
            if (self_flush) begin
                s_state  <= S_SYNC;
                beat_vld <= 1'b0;
                bcnt     <= 5'd0;
                breg     <= 128'd0;
                pack     <= 256'd0;
                wlane    <= 3'd0;
            end
        end
    end

    // 重写那一笔的数据（base+64 起 32B 拍：word4=raw_crc、word5=payload_crc、word6=header_crc）
    wire [255:0] rw_data  = {32'd0, hdr_crc_r, crc_pay_final, crc_pay_final,
                             32'd0, 32'd0, 32'd0, 32'd0};
    wire [31:0]  rw_strb  = 32'h0FFF_0000;
    wire         hdr_ready = hdr_done_r;

    // ========================================================================
    //  ddr 域：所有权保护同步（块 C）
    // ========================================================================
    always @(posedge clk_ddr or posedge rst_ddr) begin
        if (rst_ddr) begin
            prot_en_s1 <= 1'b0; prot_en_s2 <= 1'b0;
            rel0_s1 <= 1'b0; rel0_s2 <= 1'b0; rel0_s3 <= 1'b0;
            rel1_s1 <= 1'b0; rel1_s2 <= 1'b0; rel1_s3 <= 1'b0;
            sess_s1 <= 32'd0; sess_s2 <= 32'd0;
        end else begin
            prot_en_s1 <= prot_en;   prot_en_s2 <= prot_en_s1;
            rel0_s1 <= rel_tgl0; rel0_s2 <= rel0_s1; rel0_s3 <= rel0_s2;
            rel1_s1 <= rel_tgl1; rel1_s2 <= rel1_s1; rel1_s3 <= rel1_s2;
            sess_s1 <= session_id; sess_s2 <= sess_s1;
        end
    end

    // ========================================================================
    //  ddr 域：AXI 写通道 + 发布/所有权（块 B）
    // ========================================================================
    wire verdict_bad = p_bad | ~p_eof_seen | (gcnt != GROUP_TOT32) |
                       (beat_cnt != DMA_BEATS32) | axi_err;
    wire pub_stuck = (pub_wait_cnt == 17'h1_FFFF);

    wire [7:0]        cur_awlen1  = m_axi_awlen + 8'd1;
    // (BTL_CW>8?:0)：小几何（仿真里的 8x4/64x8）BTL_CW=7 时不能出现负的重复次数
    wire [BTL_CW-1:0] cur_beats_x = {{(BTL_CW>8 ? BTL_CW-8 : 0){1'b0}}, cur_awlen1};
    wire [BTL_CW-1:0] burst_beats = (beats_left > cur_beats_x) ? cur_beats_x : beats_left;
    wire [28:0]       burst_step  = {{(29-BTL_CW){1'b0}}, burst_beats} << 5;
    wire [BTL_CW-1:0] next_beats  = beats_left - burst_beats;
    wire [7:0]        next_awlen  = (next_beats > BURST_BEATS_S) ? (BURST_BEATS - 1)
                                                                 : (next_beats - 8'd1);
    // ---- AXI4 强制要求：单笔突发不得跨 4KiB 边界 ----
    // 帧首 4 拍头之后地址恒为 base+128B（不是 4KiB 对齐），64 拍 × 32B = 2048B 的
    // 定长突发必然在第二笔跨 4096。这里按「到下一个 4KiB 边界还剩几拍」钳制本笔
    // awlen：起始地址 32B 对齐 ⇒ 余量恒为 32B 的整数倍（1..128 拍），钳制后正好
    // 落在边界上，随后所有突发都从 4KiB 对齐地址起步、2048B 整除 4096，不再跨越。
    // 代价：每帧仅多 1 笔突发（634 → 635），总拍数、字节流内容完全不变。
    wire [28:0]       nxt_addr    = addr_r + burst_step;
    wire [12:0]       nxt_page_l  = 13'd4096 - {1'b0, nxt_addr[11:0]};
    wire [7:0]        nxt_page_m1 = nxt_page_l[12:5] - 8'd1;       // 到边界可发的拍数-1
    wire [7:0]        next_awlen_c = (next_awlen > nxt_page_m1) ? nxt_page_m1 : next_awlen;

    assign m_axi_awsize  = AXI_SIZE;
    assign m_axi_awburst = AXI_BURST;
    assign m_axi_wdata   = (a_st == A_RW2) ? rw_data : beat_data;
    assign m_axi_wstrb   = (a_st == A_RW2) ? rw_strb : 32'hFFFF_FFFF;
    assign m_axi_wvalid  = (a_st == A_W) ? beat_vld : (a_st == A_RW2);
    assign m_axi_wlast   = (a_st == A_W) ? (beat_vld & (w_idx == burst_m1[BEAT_CW-1:0]))
                                         : (a_st == A_RW2);
    assign m_axi_bready  = (a_st == A_B) | (a_st == A_RW3);

    assign axi_busy      = (a_st != A_IDLE);

    // [31:0]={notack,stuck}  [63:32]={beats_last,wcnt_last}  [95:64]={24'd0,verdict_snap}
    assign dbg_drop      = {24'd0, verdict_snap, beats_last, wcnt_last, c_notack, c_stuck};

    // ========================================================================
    //  AXI 停滞观测 + 安全自愈（只加在「尚未发 W」的两个点，绝不断在突发中间）
    //    · A_AW：awvalid 拉高但长期等不到 awready —— 撤掉 awvalid 不构成事务，
    //      AXI 语义上合法；代价是本笔突发数据作废，帧按 axi_err 判坏。
    //    · A_RWD：只等本地 hdr_ready，还没有任何 AW/W —— 直接跳过 CRC 头重写。
    //    这两个点都不会让从机（DDR MC）等半截突发，因此是安全的兜底。
    // ========================================================================
    localparam integer TMO_AXISAFE = 1;              // 1 = 打开两处自愈
    reg  [15:0] m_aw_cur, m_w_cur, m_b_cur, m_rwd_cur;
    reg  [15:0] m_aw_max, m_w_max, m_b_max, m_rwd_max;
    reg  [7:0]  m_burst_done, m_rwd_tmo_cnt;
    reg  [15:0] rwd_wait;

    wire st_aw  = (a_st == A_AW ) && !m_axi_awready;
    wire st_w   = (a_st == A_W  ) && !(beat_vld & m_axi_wready);
    wire st_b   = (a_st == A_B  ) && !m_axi_bvalid;
    wire st_rwd = (a_st == A_RWD) && !hdr_ready;
    wire rwd_tmo_evt = TMO_AXISAFE && (a_st == A_RWD) && (rwd_wait == 16'hFFFF);
    wire aw_tmo_evt  = TMO_AXISAFE && (a_st == A_AW) && (m_aw_cur == 16'hFFFF);

    always @(posedge clk_ddr or posedge rst_ddr) begin
        if (rst_ddr) begin
            m_aw_cur <= 16'd0; m_w_cur <= 16'd0; m_b_cur <= 16'd0; m_rwd_cur <= 16'd0;
            m_aw_max <= 16'd0; m_w_max <= 16'd0; m_b_max <= 16'd0; m_rwd_max <= 16'd0;
            m_burst_done <= 8'd0; m_rwd_tmo_cnt <= 8'd0; rwd_wait <= 16'd0;
        end else begin
            if (st_aw) m_aw_cur <= (m_aw_cur == 16'hFFFF) ? m_aw_cur : (m_aw_cur + 16'd1);
            else begin if (m_aw_cur > m_aw_max) m_aw_max <= m_aw_cur; m_aw_cur <= 16'd0; end
            if (st_w)  m_w_cur  <= (m_w_cur  == 16'hFFFF) ? m_w_cur  : (m_w_cur  + 16'd1);
            else begin if (m_w_cur  > m_w_max)  m_w_max  <= m_w_cur;  m_w_cur  <= 16'd0; end
            if (st_b)  m_b_cur  <= (m_b_cur  == 16'hFFFF) ? m_b_cur  : (m_b_cur  + 16'd1);
            else begin if (m_b_cur  > m_b_max)  m_b_max  <= m_b_cur;  m_b_cur  <= 16'd0; end
            if (st_rwd) m_rwd_cur <= (m_rwd_cur == 16'hFFFF) ? m_rwd_cur : (m_rwd_cur + 16'd1);
            else begin if (m_rwd_cur > m_rwd_max) m_rwd_max <= m_rwd_cur; m_rwd_cur <= 16'd0; end

            if ((a_st == A_B) && m_axi_bvalid)
                m_burst_done <= m_burst_done + 8'd1;
            if (rwd_tmo_evt)
                m_rwd_tmo_cnt <= m_rwd_tmo_cnt + 8'd1;

            if (a_st != A_RWD) rwd_wait <= 16'd0;
            else if (rwd_wait != 16'hFFFF) rwd_wait <= rwd_wait + 16'd1;
        end
    end
    assign dbg_stall = {m_rwd_tmo_cnt, m_burst_done, m_rwd_max, m_aw_max, m_w_max, m_b_max};

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
            rw_done_r     <= 1'b0;
            mid_frame     <= 1'b0;
            wdt           <= 24'd0;
            // self_flush_cnt 必须复位：漏了它 self_flush 恒为 X，wdt_active/waiting_data
            // 跟着变 X，if (waiting_data) 按假处理 → wdt 永远不计数（仿真 x，实测随机）。
            self_flush_cnt <= 8'd0;
            apos_snap     <= 32'd0;
            cpos_snap     <= 32'd0;
            s_state_snap  <= S_SYNC;
            need_first    <= 1'b0;
            pub_base      <= BASE0;
            pub_ok        <= 1'b0;
            pub_err       <= 16'd0;
            c_stuck <= 16'd0; c_notack <= 16'd0; c_bad <= 16'd0;
            wcnt_last <= 16'd0; beats_last <= 16'd0; verdict_snap <= 8'd0;
            pub_tgl       <= 1'b0;
            err_cnt       <= 16'd0;
            protect0      <= 1'b0;
            protect1      <= 1'b0;
            cl_pub_valid <= 1'b0;
            cl_pub_seq <= 0; cl_pub_base <= 0; cl_pub_session <= 0;
            cl_good_count <= 0; cl_bad_count <= 0;
        end else begin
            frame_close <= 1'b0;
            cl_pub_valid <= 1'b0;
            apos_snap    <= apos;
            cpos_snap    <= cpos;
            s_state_snap <= s_state;

            if (rel0_evt) protect0 <= 1'b0;
            if (rel1_evt) protect1 <= 1'b0;

            // 自愈时清流控状态，否则会停在 A_IDLE 等一个永远不来的 burst_ok
            if (self_flush) begin
                mid_frame  <= 1'b0;
                need_first <= 1'b0;
            end

            // 自愈窗口计数（唯一定义处；触发在下面的 A_IDLE 判定分支里）
            if (self_flush_cnt != 8'd0) self_flush_cnt <= self_flush_cnt - 8'd1;

            // ---- 数据侧长看门狗计时（放在 case 之前，好让下面的超限动作覆盖它）----
            if (waiting_data) begin
                if (!wdt_hit) wdt <= wdt + 24'd1;
            end else wdt <= 24'd0;

            case (a_st)
                A_IDLE: begin
                    // 换手点：停在这里就是交还端口（awvalid/wvalid/bready 全 0）。
                    if (wdt_hit) begin
                        // 长看门狗超限：不只是 mid_frame 丢突发，也包括 S_TAIL 等
                        // tail_app、S_WAIT 等 frame_close。交还写口 + 清流控 + 自愈
                        // （回 S_SYNC 等下一帧 SOF），本帧按「未发布」丢弃。
                        mid_frame      <= 1'b0;
                        need_first     <= 1'b0;
                        axi_err        <= 1'b1;
                        wdt            <= 24'd0;
                        self_flush_cnt <= 8'hFF;
                    end else if (mid_frame) begin
                        if (need_first || burst_ok_ddr) begin
                            mid_frame     <= 1'b0;
                            need_first    <= 1'b0;
                            m_axi_awvalid <= 1'b1;
                            a_st          <= A_AW;
                        end
                    end else if (skip_frm_done) begin
                        if (pub_stuck) begin
                            pub_tgl <= pub_ack_s2;
                            err_cnt <= err_cnt + 16'd1;
                            c_stuck <= c_stuck + 16'd1;
                        end else if (pub_ack_s2 == pub_tgl) begin
                            pub_base <= base_r;
                            pub_ok   <= 1'b0;
                            pub_err  <= err_cnt + 16'd1;
                            pub_tgl  <= ~pub_tgl;
                            err_cnt  <= err_cnt + 16'd1;
                            c_bad    <= c_bad + 16'd1;
                            cl_bad_count <= cl_bad_count + 1'b1;
                        end else begin
                            c_notack <= (c_notack == 16'hFFFF) ? c_notack : (c_notack + 16'd1);
                        end
                        frame_idx   <= frame_idx + 32'd1;
                        frame_close <= 1'b1;
                    end else if (st_frame_go) begin
                        base_r        <= (frame_idx[0]) ? BASE1 : BASE0;
                        addr_r        <= (frame_idx[0]) ? BASE1[28:0] : BASE0[28:0];
                        m_axi_awaddr  <= (frame_idx[0]) ? BASE1[28:0] : BASE0[28:0];
                        pub_par       <= frame_idx[0];
                        beats_left    <= DMA_BEATS_S;
                        m_axi_awlen   <= AWLEN_FIRST;
                        burst_m1      <= AWLEN_FIRST;
                        w_idx         <= {BEAT_CW{1'b0}};
                        m_axi_awvalid <= 1'b0;
                        axi_err       <= 1'b0;
                        rw_done_r     <= 1'b0;
                        frame_idx     <= frame_idx + 32'd1;
                        mid_frame     <= 1'b1;
                        need_first    <= 1'b1;      // 帧首那一笔（4 拍头）立刻放行
                        a_st          <= A_IDLE;
                    end else if (rw_done_r && (s_state == S_WAIT)) begin
                        wcnt_last    <= gcnt[15:0];
                        beats_last   <= beat_cnt[15:0];
                        verdict_snap <= {2'b0, pub_ok, axi_err,
                                         (beat_cnt != DMA_BEATS32),
                                         (gcnt != GROUP_TOT32),
                                         ~p_eof_seen, p_bad};
                        if (pub_stuck) begin
                            pub_tgl <= pub_ack_s2;
                            err_cnt <= err_cnt + 16'd1;
                            c_stuck <= c_stuck + 16'd1;
                        end else if (pub_ack_s2 == pub_tgl) begin
                            pub_base <= base_r;
                            pub_ok   <= ~verdict_bad;
                            pub_err  <= err_cnt + ((~verdict_bad) ? 16'd0 : 16'd1);
                            pub_tgl  <= ~pub_tgl;
                            err_cnt  <= err_cnt + ((~verdict_bad) ? 16'd0 : 16'd1);
                            if (verdict_bad) begin
                                c_bad <= c_bad + 16'd1;
                                cl_bad_count <= cl_bad_count + 1'b1;
                            end else begin
                                cl_good_count <= cl_good_count + 1'b1;
                                if (CLOSEDLOOP_EN) begin
                                    cl_pub_valid <= 1'b1;
                                    cl_pub_seq <= f_seq;
                                    cl_pub_base <= base_r;
                                    cl_pub_session <= f_sess;
                                end
                            end
                            if (protect_enabled && ~verdict_bad) begin
                                if (pub_par) protect1 <= 1'b1;
                                else         protect0 <= 1'b1;
                            end
                        end else begin
                            err_cnt  <= err_cnt + 16'd1;
                            c_notack <= c_notack + 16'd1;
                        end
                        // 连续坏帧计数：8 帧都坏就自愈一次（清 FIFO + 回 S_SYNC）。
                        // 板测：某一路会永久卡在「整帧补零」，只有重新 arm 才恢复，
                        // 自愈把这条恢复路径搬进 RTL，不用主机插手。
                        if (verdict_bad) begin
                            if (bad_streak_ddr == 4'd7) begin
                                bad_streak_ddr <= 4'd0;
                                self_flush_cnt <= 8'hFF;
                            end else begin
                                bad_streak_ddr <= bad_streak_ddr + 4'd1;
                            end
                        end else begin
                            bad_streak_ddr <= 4'd0;
                        end
                        rw_done_r   <= 1'b0;
                        frame_close <= 1'b1;
                    end
                end

                A_AW: if (m_axi_awready) begin
                    m_axi_awvalid <= 1'b0;
                    burst_m1      <= m_axi_awlen;
                    w_idx         <= {BEAT_CW{1'b0}};
                    a_st          <= A_W;
                end else if (aw_tmo_evt) begin
                    // 兜底：撤 awvalid（无事务发生，AXI 合法）→ 放弃本笔突发、判坏、
                    // 释放写口，避免一路把 grant 永久压住把另一路饿死。
                    m_axi_awvalid <= 1'b0;
                    m_axi_awlen   <= 8'd0;
                    axi_err       <= 1'b1;
                    mid_frame     <= 1'b0;
                    a_st          <= A_IDLE;
                    // ★ aw 超时是终态：若此时已在 S_TAIL，A_IDLE 里只有 mid_frame=1
                    //   才会再发突发，beat_vld 会永久卡 1 → data_ready=0 → tail_app
                    //   永不触发 → apos 冻死（板测 0x174=0x18 的真因）。直接自愈。
                    self_flush_cnt <= 8'hFF;
                end

                A_W: if (beat_vld & m_axi_wready) begin
                    if (w_idx == burst_m1[BEAT_CW-1:0]) begin
                        w_idx <= {BEAT_CW{1'b0}};
                        a_st  <= A_B;
                    end else begin
                        w_idx <= w_idx + 1'b1;
                    end
                end

                A_B: if (m_axi_bvalid) begin
                    if (m_axi_bresp != 2'b00) axi_err <= 1'b1;
                    if (beats_left == burst_beats) begin
                        a_st <= A_RWD;
                    end else begin
                        beats_left    <= next_beats;
                        addr_r        <= addr_r + burst_step;
                        m_axi_awaddr  <= addr_r + burst_step;
                        m_axi_awlen   <= next_awlen_c;
                        m_axi_awvalid <= 1'b0;      // 先交还端口，回 A_IDLE 等数据
                        mid_frame     <= 1'b1;
                        a_st          <= A_IDLE;
                    end
                end

                A_RWD: if (hdr_ready) begin
                    m_axi_awaddr  <= base_r[28:0] + 29'd64;
                    m_axi_awlen   <= 8'd0;
                    m_axi_awvalid <= 1'b1;
                    a_st          <= A_RW;
                end else if (rwd_tmo_evt) begin
                    // 兜底：hdr_ready 没等到（CRC 头遍历没启动/没完成）——此时没有
                    // 任何 AW/W，直接跳过「CRC 头重写」，判坏并交还写口。
                    axi_err   <= 1'b1;
                    rw_done_r <= 1'b1;
                    a_st      <= A_IDLE;
                end

                A_RW: if (m_axi_awready) begin
                    m_axi_awvalid <= 1'b0;
                    a_st          <= A_RW2;
                end

                A_RW2: if (m_axi_wready) a_st <= A_RW3;

                A_RW3: if (m_axi_bvalid) begin
                    if (m_axi_bresp != 2'b00) axi_err <= 1'b1;
                    rw_done_r <= 1'b1;
                    a_st      <= A_IDLE;
                end

                default: a_st <= A_IDLE;
            endcase
        end
    end

    always @(posedge clk_ddr or posedge rst_ddr) begin
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
    //  tl_clk_user 域：取走帧结果、拼状态字、诊断采样、回执（块 D）
    // ========================================================================
    reg  [15:0] err_cnt_fb;
    reg         valid_fb;
    reg         busy_s1,  busy_s2;
    reg         alive_s1, alive_s2;
    reg         cal_s1,   cal_s2;
    reg  [15:0] lines_s1, lines_s2, grp_s1, grp_s2;
    reg         anom_s1, anom_s2;
    reg         pub_tgl_s1, pub_tgl_s2, pub_tgl_s3;

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

            busy_s1  <= (s_state != S_SYNC);  busy_s2  <= busy_s1;
            alive_s1 <= ~rst_ddr;             alive_s2 <= alive_s1;
            cal_s1   <= ddr_cal_done;         cal_s2   <= cal_s1;

            lines_s1 <= frame_lines;   lines_s2 <= lines_s1;
            grp_s1   <= max_grp;       grp_s2   <= grp_s1;
            anom_s1  <= (drop_cnt != 16'd0) | (ovf_cnt != 16'd0);
            anom_s2  <= anom_s1;

            if (pub_tgl_s2 ^ pub_tgl_s3) begin
                if (pub_ok) begin
                    wr_frame_seq <= wr_frame_seq + 32'd1;
                    wr_base      <= pub_base;
                    valid_fb     <= 1'b1;
                end
                err_cnt_fb <= pub_err;
                pub_ack    <= pub_tgl_s2;
            end

            wr_status <= {err_cnt_fb, 11'd0, cal_s2, alive_s2, err_sticky_fb,
                          busy_s2, valid_fb};
            dbg_lines_per_frame  <= lines_s2;
            dbg_max_grp_per_line <= grp_s2;
            dbg_anomaly          <= anom_s2;
        end
    end

    assign wr_len = DMA_BYTES32;

    // 板级调试：把「卡在哪」直接露出来（a_st / s_state / hdr_ready / pub 未回执）。
    // 先在本域打一拍再出去，避免把 DDR 域的裸组合量直接给 tl 域读。
    reg [8:0] dbg_fsm_r;
    always @(posedge clk_ddr or posedge rst_ddr) begin
        if (rst_ddr) dbg_fsm_r <= 9'd0;
        else         dbg_fsm_r <= {1'b0, (pub_tgl ^ pub_ack_s2), hdr_ready, s_state, a_st};
    end
    assign dbg_fsm = dbg_fsm_r;

    // ========================================================================
    //  每帧统计（诊断输出，不参与数据/控制路径）
    // ========================================================================
    // 相机域快照 → DDR 域 2 级同步（EOF 之后就是静态值，收口时采样足够安全）
    reg [31:0] s_push1, s_push2, s_drop1, s_drop2, s_ovf1, s_ovf2;
    reg [15:0] s_ln1, s_ln2, s_y1, s_y2, s_mg1, s_mg2;
    reg        s_eb1, s_eb2;
    reg [31:0] fr_cyc;                       // 本帧「打包占用」周期数
    reg [31:0] lat_push, lat_drop, lat_ovf, lat_cyc, lat_gcnt;
    reg [15:0] lat_lines, lat_y, lat_mg;
    reg        lat_eb, lat_pbad, lat_peof, lat_tmo, tmo_seen;
    reg        lat_wdt, wdt_seen;

    always @(posedge clk_ddr or posedge rst_ddr) begin
        if (rst_ddr) begin
            s_push1 <= 32'd0; s_push2 <= 32'd0; s_drop1 <= 32'd0; s_drop2 <= 32'd0;
            s_ovf1  <= 32'd0; s_ovf2  <= 32'd0;
            s_ln1 <= 16'd0; s_ln2 <= 16'd0; s_y1 <= 16'd0; s_y2 <= 16'd0;
            s_mg1 <= 16'd0; s_mg2 <= 16'd0; s_eb1 <= 1'b0; s_eb2 <= 1'b0;
            fr_cyc <= 32'd0; tmo_seen <= 1'b0;
            lat_push <= 32'd0; lat_drop <= 32'd0; lat_ovf <= 32'd0;
            lat_cyc  <= 32'd0; lat_gcnt <= 32'd0;
            lat_lines <= 16'd0; lat_y <= 16'd0; lat_mg <= 16'd0;
            lat_eb <= 1'b0; lat_pbad <= 1'b0; lat_peof <= 1'b0; lat_tmo <= 1'b0;
            lat_wdt <= 1'b0; wdt_seen <= 1'b0;
        end else begin
            s_push1 <= sn_push;  s_push2 <= s_push1;
            s_drop1 <= sn_drop;  s_drop2 <= s_drop1;
            s_ovf1  <= sn_ovf;   s_ovf2  <= s_ovf1;
            s_ln1   <= sn_lines; s_ln2   <= s_ln1;
            s_y1    <= sn_y;     s_y2    <= s_y1;
            s_mg1   <= sn_maxgrp;s_mg2   <= s_mg1;
            s_eb1   <= sn_eofbad;s_eb2   <= s_eb1;

            // 帧起点清零；只统计真正在打包的拍（不含 S_SYNC 空转和 S_WAIT 等回执）
            if (st_frame_go) begin
                fr_cyc   <= 32'd0;
                tmo_seen <= 1'b0;
                wdt_seen <= 1'b0;
            end else if ((s_state != S_SYNC) && (s_state != S_WAIT)) begin
                fr_cyc <= fr_cyc + 32'd1;
            end
            if (tmo_hit) tmo_seen <= 1'b1;
            if (wdt_hit) wdt_seen <= 1'b1;

            if (frame_close) begin
                lat_push  <= s_push2;
                lat_drop  <= s_drop2;
                lat_ovf   <= s_ovf2;
                lat_lines <= s_ln2;
                lat_y     <= s_y2;
                lat_mg    <= s_mg2;
                lat_eb    <= s_eb2;
                lat_cyc   <= fr_cyc;
                lat_gcnt  <= gcnt;
                lat_pbad  <= p_bad;
                lat_peof  <= p_eof_seen;
                lat_tmo   <= tmo_seen;
                lat_wdt   <= wdt_seen;
            end
        end
    end

    assign dbg_frame = {26'd0, lat_wdt, lat_tmo, lat_pbad, lat_peof, lat_eb, // [255:224]
                        lat_gcnt,                                    // [223:192]
                        lat_cyc,                                     // [191:160]
                        lat_ovf,                                     // [159:128]
                        16'd0, lat_mg,                               // [127:96]
                        lat_lines, lat_y,                            // [95:64]
                        lat_drop,                                    // [63:32]
                        lat_push};                                   // [31:0]

endmodule
