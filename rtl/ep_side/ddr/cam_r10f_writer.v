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
//   1) 帧内容按**字节流**在 DDR 域组装：breg 是 8 字节窗口（最旧字节在低 8 位），
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
    parameter [20:0]  TMO_LIMIT        = 21'h1F_FFFF
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
    localparam [7:0]        AWLEN_FIRST   = (DMA_BEATS > BURST_BEATS) ? (BURST_BEATS - 1)
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
        end
    end

    // ---- 入队（标记优先）----
    wire        push_sof = sof_evt & arm_c[1];
    wire        push_eof = eof_evt & frame_armed;
    wire        eof_good = cam_frame_good | good_seen;
    wire        eof_bad  = (~eof_good) | abort_seen | cam_frame_abort |
                           line_bad_seen | last_line_bad;
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

    always @(posedge cam_clk or posedge rst_cam_all) begin
        if (rst_cam_all) begin
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
    reg  [3:0]  bcnt;
    reg  [63:0] breg;
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

    wire pay_room  = (bcnt <= 4'd3);
    wire hdr_room  = (bcnt <= 4'd4);
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
        if (rst_ddr || cam_flush) begin
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

    always @(posedge clk_ddr or posedge rst_ddr) begin
        if (rst_ddr) begin wgray_s1 <= {(FIFO_AW+1){1'b0}}; wgray_s2 <= {(FIFO_AW+1){1'b0}}; end
        else begin wgray_s1 <= wptr_gray; wgray_s2 <= wgray_s1; end
    end

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

    // 追加源
    wire [63:0] pay_ins = {24'd0, e_grp} << {bcnt, 3'b000};
    wire [63:0] hdr_ins = {32'd0, hdr_word(hcnt, 32'd0, 32'd0)} << {bcnt, 3'b000};
    wire pay_app  = (s_state == S_PAY)  & is_grp & pay_room & data_ready &
                    pay_ok & ~word_take;
    wire hdr_app  = (s_state == S_HDR)  & hdr_room & data_ready & ~word_take;
    wire tail_app = (s_state == S_TAIL) & hdr_room & data_ready &
                    tail_need & ~word_take;

    wire tmo_hit = (tmo == TMO_LIMIT);

    // ========================================================================
    //  ddr 域：流状态机 + 消费路径（块 A）
    // ========================================================================
    always @(posedge clk_ddr or posedge rst_ddr) begin
        if (rst_ddr) begin
            s_state   <= S_SYNC;
            hcnt      <= 5'd0;
            bcnt      <= 4'd0;
            breg      <= 64'd0;
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
            if (word_take) begin
                bcnt <= bcnt - 4'd4;
                breg <= {32'd0, breg[63:32]};
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
            if (((s_state == S_PAY) | (s_state == S_SKIP)) && !pop) begin
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
                    bcnt        <= 4'd0;
                    breg        <= 64'd0;
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
                    breg <= breg | hdr_ins;
                    bcnt <= bcnt + 4'd4;
                    apos <= apos + 32'd4;
                    if (hcnt == 5'd31) begin
                        hcnt    <= 5'd0;
                        s_state <= S_PAY;
                    end else hcnt <= hcnt + 5'd1;
                end
            end

            S_PAY: begin
                if (pay_app) begin
                    breg <= breg | pay_ins;
                    bcnt <= bcnt + 4'd5;
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
                    breg <= breg | 64'd0;
                    bcnt <= bcnt + 4'd4;
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

    wire [BTL_CW-1:0] burst_beats = (beats_left > BURST_BEATS_S) ? BURST_BEATS_S : beats_left;
    wire [28:0]       burst_step  = {{(29-BTL_CW){1'b0}}, burst_beats} << 5;
    wire [BTL_CW-1:0] next_beats  = beats_left - burst_beats;
    wire [7:0]        next_awlen  = (next_beats > BURST_BEATS_S) ? (BURST_BEATS - 1)
                                                                 : (next_beats - 8'd1);

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

            if (rel0_evt) protect0 <= 1'b0;
            if (rel1_evt) protect1 <= 1'b0;

            case (a_st)
                A_IDLE: begin
                    if (skip_frm_done) begin
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
                        m_axi_awvalid <= 1'b1;
                        axi_err       <= 1'b0;
                        rw_done_r     <= 1'b0;
                        frame_idx     <= frame_idx + 32'd1;
                        a_st          <= A_AW;
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
                        rw_done_r   <= 1'b0;
                        frame_close <= 1'b1;
                    end
                end

                A_AW: if (m_axi_awready) begin
                    m_axi_awvalid <= 1'b0;
                    burst_m1      <= m_axi_awlen;
                    w_idx         <= {BEAT_CW{1'b0}};
                    a_st          <= A_W;
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
                        m_axi_awlen   <= next_awlen;
                        m_axi_awvalid <= 1'b1;
                        a_st          <= A_AW;
                    end
                end

                A_RWD: if (hdr_ready) begin
                    m_axi_awaddr  <= base_r[28:0] + 29'd64;
                    m_axi_awlen   <= 8'd0;
                    m_axi_awvalid <= 1'b1;
                    a_st          <= A_RW;
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

endmodule
