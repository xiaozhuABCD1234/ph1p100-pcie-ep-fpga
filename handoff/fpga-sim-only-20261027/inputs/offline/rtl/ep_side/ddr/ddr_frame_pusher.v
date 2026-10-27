///////////////////////////////////////////////////////////////////////////////
//  ddr_frame_pusher.v — 推帧引擎（EP 主动用 MWr 把整帧写进主机内存）
//
//  ===========================================================================
//  0. 本文件相对冻结 peer 2a4b253 的改动（T07.rk-align-backend）
//  ===========================================================================
//  基线：references/peer-fpga-2a4b253/rtl/ep_side/ddr/ddr_frame_pusher.v
//        sha256 397fc5f645ce42384e5bde419242e2356b1c48e6e079d615553e617d258bcd7c
//
//  本版本在**不改变 TLP 线上格式**（F0 头 / FF 载荷 / F8 单 DW 门铃、4DW 地址、
//  128B 载荷、首字节在高位、字节序与 bswap）的前提下，把「只要 push_en 且帧号变
//  就自动连续推帧」改成 contract/registers.json 定义的 RKA1 one-shot 安全语义：
//
//   (1) 默认不发：必须由主机 (a) 打开 CTRL[6]（模式使能，本身不授权），
//       (b) 依次写 DMA_CAP_BYTES / SESSION_ID / 目标与门铃地址，
//       (c) 写 TX_CMD.bit0（ARM_ONE_SHOT）——一个 ARM 额度最多完成 1 帧。
//       CTRL=0x61（bit0/5/6）单独**绝不发送**；push 模式打开但没有 ARM 时，
//       新发布的帧只记错误码 5（E_NOT_ARM），不占 TL 口、不写主机内存。
//   (2) ARM 原子锁存 descriptor：{dst_lo/hi, db_lo/hi, cap_bytes, session_id,
//       frame_bytes, 源选择 src_sel, 相机选择 cam_sel} 在 ARM 那一拍整组锁存；
//       传输期间只用锁存值，现场寄存器改动不影响本帧（busy/held/draining 期间
//       BAR 侧对配置寄存器的写入在 ep_bar_win 里被拒，见那里的 cfg_reject）。
//   (3) ARM 前置校验（任一不满足 → 拒绝，错误码 6，TX_STATUS.bit3 粘滞）：
//       · session_id != 0；cap_bytes != 0 且 cap_bytes >= frame_bytes；
//       · frame_bytes > 0、<= MAX_FRAME_BYTES、4KiB 整数倍；ERAM 源要求
//         frame_bytes == 片内帧长 W*H（否则打包器字预算对不上）；
//       · dst 128B 对齐、非零、dst + frame_bytes 无 64bit 回绕；
//       · db 4B 对齐、非零、[db,db+4) 与 [dst,dst+frame_bytes) 不重叠；
//       · 链路可用（link_up）且协商 MPS 编码合法（>=128B，即编码 <= 5）；
//       · CTRL[6] 已开（模式使能）且当前不在 busy/held/draining；
//       · DDR 源还要 ddr_status[0]=1（已发布过完整帧）。
//   (4) 帧就绪后（源发布新的完整帧号）在**同一时钟域同一拍**决定 claim/pass：
//       · claim（g_st==ARMED 且模式使能）：锁存 {源帧号, 源基址, 门铃值}，
//         开始传输；DDR 源额外保护「本帧所在的双缓冲块」——见 (7)；
//       · pass：不传，立刻给该块发一个 release（toggle），让写者能继续轮转；
//         若 push 模式没开则不做任何保护动作。
//      源选择/相机选择/frame_bytes 在 claim 时与 ARM 锁存值不一致 → 本帧拒绝
//      （错误码 9），不发送、不消耗额度。
//   (5) 包完整性：包内等 tl_tx_wait 持续超时（WAIT_LIMIT）时：
//       · 若本包还没有任何一拍被收走（SOP 未 accepted）→ 立即放弃该包、排空；
//       · 若已有拍被收走 → **先把这个包完整发完**再排空（绝不截半包，也不让
//         CPL 插进一个已开始的包；TL 口在 S_TEND 才还给引擎）。
//   (6) 完成/持有：数据 + 独立单 DW 门铃都发出后才算完成；完成后进 HELD，
//       记录 held_seq（= 门铃里写的已推帧数）/held_sess（= ARM 锁存 session），
//       此后**不启动新帧**，直到主机写 ACK_RELEASE 且 ACK_SEQ/ACK_SESSION 与
//       held 值逐位相等才释放（释放后必须重新 ARM）。错误 ACK 只置
//       reject 粘滞位，绝不覆盖 held 槽。
//   (7) 源缓冲所有权（DDR 相机源）：
//       · 写者（cam_ddr_writer）自己「发布即保护该块，直到收到该块的 release」；
//       · 本模块对每一个被发布的新帧给且只给一个 release 事件（claim 后 ACK/
//         CANCEL 释放，或未 claim 的 pass 立即释放），用每块一根 toggle 跨回
//         ddr 域（rel_tgl0/rel_tgl1）。写者只在「观察到 release 之后」才会重写
//         该块 ⇒ 读窗口与写窗口天然互斥，TL 长时间 stall 也不会被覆盖。
//       · ERAM 源（src_sel=1）：claim 时拉起 fb_hold 冻结 img_frame_src 的帧
//         发生器（只在帧完整后才会被拉起，发生器尚在 IDLE_CYCLE 空档，故源
//         从 claim 起到 release 为止逐字节不可变），release 时放开。
//   (8) CANCEL：ARMED → 直接放弃（DDR 源发 pass release）；TX 中 → 未开始的包
//       直接放弃、已开始的包先补完整，**不发门铃**、不增加成功序号、排空后回到
//       IDLE 并发 release；HELD → 拆除 held 槽并 release（特权撤销，无成功门铃）。
//       RESET：armed/held/锁存值/toggle 全部清零，旧会话的源响应随各域复位隔离。
//   (9) 错误码（0xC8）在原有 0..4 之上新增 5..11；成功序号 st_done 只在
//       「数据 + 门铃都发出」且非取消时 +1；timeout/取消/错误一律不加。
//
//  其余原有说明保持原样在下。
//
//  ===========================================================================
//  一、它接什么
//  ===========================================================================
//   · DDR 侧：u_ddr3_mc_0 的 AXI4 **读**通道（axi_aclk = dhi_clk = IP 的 usr_clk，
//     100MHz；axi_aresetn = ddrphy_rst_n）。数据 256bit = 32 字节/拍，地址是字节
//     地址。每帧字节数 / 32 = 拍数，再按 4KB 切突发（arlen=127、arsize=5、INCR）。
//   · 片内侧：DDR 搬运的握手字（wr_frame_seq / wr_base / wr_status），以及
//     pcie_ep_engine 的「用户侧 TL 发送口」（utx_req/utx_data/utx_sop/utx_eop/
//     utx_valid；引擎只在自己的发送状态机空闲时把发送口让出来）。
//   · 寄存器面：CTRL[6] = push_en（模式使能，不授权）；0xB0/0xB4 = 目标地址
//     低/高 32 位；0xB8/0xBC = 门铃地址低/高 32 位；0xC0 已推帧数；0xC4 状态；
//     0xC8 最近一次错误码；0xCC 最近一帧发出的 MWr 数；0x100..0x11C = RKA1
//     安全扩展（偏移表见 ep_bar_win.v 头部）。
//
//  ===========================================================================
//  二、发出去的 TLP 长什么样
//  ===========================================================================
//   一个 MWr：4DW 头 + 载荷 32 个 dw（128 字节），共 36 个 dw，TL 口占 5 拍：
//     第 0 拍：4 个 dw 头（valid=8'hF0）  第 1..4 拍：各 8 个 dw 载荷（8'hFF）
//   每帧的 MWr 数 = frame_bytes / 128（在帧开头按锁存量现算）。
//   · 4DW 头里 dw2 = 地址高 32 位、dw3 = {地址低 30 位, 2'b00}。
//   · 「首字节在高位」：载荷 dw 整拍字节倒序（bswap256），门铃单 dw bswap32。
//   · 长度 32 的帧 MWr ⇒ First/Last DW BE 全 1；门铃长度 1 ⇒ Last DW BE = 0。
//   · Tag 恒 0（Posted 无需完成包）；TC0、属性位全 0（不带 Relaxed Ordering）。
//   · 门铃是一次只写一个 dw 的独立 MWr，内容是本帧序号（1 起、每帧 +1）。
//
//  ===========================================================================
//  三、反压与让路（不许假设带宽）
//  ===========================================================================
//   · 每一拍都靠 utx_sel & !tl_tx_wait 才算被链路收走；没收走就保持不动。
//   · 等 tl_tx_wait 连续超过 WAIT_LIMIT 拍（默认 65535 拍 ≈ 1.05ms）判超时：
//     未开始的包直接放弃；已开始的包先补完整再停（见头部第 (5) 条）。
//   · 每个 MWr 之间留 1 拍空档（S_TEND），把 TL 发送口还给引擎插 CPL/CPLD。
//
//  ===========================================================================
//  四、数据通路与跨时钟域
//  ===========================================================================
//   ddr 源（usr_clk 100MHz）                     片内域（tl_clk_user 62.5MHz）
//   ─────────────────────────                   ─────────────────────────────
//   每 4KB 一个 AXI4 读突发 ─▶ 异步 FIFO（256bit×2**FIFO_AW 拍，格雷码指针）
//                                        ─▶ 拆成 5 拍 1 个 MWr 交 TL 口
//   ERAM 源（tl_clk_user）  8 个字拼一拍（fb 唯一读口，1 字/拍）─▶ 同一拆包逻辑
//   req_level / base_lat  ◀── 2 级同步 ◀── 片内「有一帧要推」电平
//   done_level / err_sticky ──▶ 2 级同步 ──▶ 片内收尾
//
//  ===========================================================================
//  五、错误码（0xC8）与状态（0xC4）
//  ===========================================================================
//    0 = 正常（数据与门铃都发了）        1 = 目标地址未配置（legacy，本版不出现）
//    2 = 等 tl_tx_wait 超时（本帧停发）  3 = AXI 读响应非 OKAY（本帧停发）
//    4 = 门铃地址未配置（legacy，本版不出现）
//    5 = 未 ARM（有完整帧但没有 one-shot 额度）
//    6 = ARM 被拒（descriptor 校验失败）  7 = CANCEL 取消
//    8 = HELD 期间源又出了新帧（忽略）    9 = 源/描述符不一致
//   10 = busy/held/draining 期间写配置被拒  11 = ACK 不匹配
//  状态位（0xC4）：bit0 busy / bit1 last_ok / bit2 db_sent / bit3 ddr_alive /
//          bit4 ddr_cal_done / [31:16] 错误累计
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

`include "../../common/TLP_FMT_TYPE.v"
`include "../../common/BDF.v"

module ddr_frame_pusher #(
    parameter integer W           = 640,
    parameter integer H           = 480,
    parameter integer PAY_DW      = 32,
    parameter integer MAX_FRAME_BYTES = 3840 * 2160,
    parameter integer FIFO_AW     = 7,
    parameter integer BURST_BEATS = 128,
    parameter [15:0]  WAIT_LIMIT  = 16'hFFFF,
    // ---- DDR 源双缓冲块基址（与 cam_ddr_writer 的 BASE0/BASE1 一致）----
    //   T07 round1：A/B 两路的基址都要给（顶层 cam_ab_sel 选哪一路就用哪一对），
    //   否则 B 路的 release 判定会拿 A 路的基址去比，永远不放行 B 的源块。
    parameter [31:0]  BASE0       = 32'h0010_0000,
    parameter [31:0]  BASE1       = 32'h0090_0000,
    parameter [31:0]  BASE0B      = 32'h0110_0000,
    parameter [31:0]  BASE1B      = 32'h0190_0000
)(
    // ---------------- 片内帧缓存域（tl_clk_user，62.5MHz）----------------
    input  wire         clk_fb,
    input  wire         rst_fb,

    // ---- 寄存器面（模式与目标，ARM 时锁存）----
    input  wire         push_en,       // CTRL[6]
    input  wire [31:0]  dst_lo,        // 0xB0
    input  wire [31:0]  dst_hi,        // 0xB4
    input  wire [31:0]  db_lo,         // 0xB8
    input  wire [31:0]  db_hi,         // 0xBC
    output reg  [31:0]  st_done,       // 0xC0
    output wire [31:0]  st_status,     // 0xC4
    output reg  [7:0]   st_err,        // 0xC8
    output reg  [31:0]  st_tlp_cnt,    // 0xCC

    input  wire [31:0]  frame_bytes,   // 源侧帧长（ARM 校验 + claim 比对）

    // ---- DDR 搬运握手 ----
    input  wire [31:0]  ddr_seq,
    input  wire [31:0]  ddr_base,
    input  wire [31:0]  ddr_status,

    // ---- ERAM 帧缓存源 ----
    input  wire         src_sel,
    input  wire [31:0]  fb_frame_cnt,
    output wire [31:0]  fb_rd_addr,
    input  wire [31:0]  fb_rd_data,
    output wire         fb_req,
    input  wire         fb_grant,
    output wire         src_act,
    output wire         fb_hold,

    // ---- TL 用户发送口 ----
    input  wire         utx_sel,
    input  wire         tl_tx_wait,
    output wire         utx_req,
    output wire [255:0] utx_data,
    output wire         utx_sop,
    output wire         utx_eop,
    output wire [7:0]   utx_valid,

    // ---------------- RKA1 安全扩展（0x100..0x11C，全部 clk_fb 域）----------------
    input  wire         arm_pulse,     // 0x108 TX_CMD.bit0（单拍）
    input  wire         ack_pulse,     // 0x108 TX_CMD.bit1（单拍）
    input  wire         cancel_pulse,  // 0x108 TX_CMD.bit2（单拍）
    input  wire [31:0]  cap_bytes,     // 0x100（暂存；ARM 校验并锁存）
    input  wire [31:0]  session_id,    // 0x104（暂存；ARM 校验并锁存）
    input  wire [31:0]  ack_seq_w,     // 0x10C（暂存）
    input  wire [31:0]  ack_session_w, // 0x110（暂存）
    input  wire         cfg_reject,    // BAR：活动期写配置被拒（单拍）
    input  wire         link_up,       // 链路/时钟就绪
    input  wire [2:0]   mps_code,      // 协商 MPS 编码
    input  wire [31:0]  ddr_cap_bytes, // 实际 DDR 容量（板/IP 参数）
    input  wire         cam_sel_live,  // CTRL[8] 实时值
    output wire [31:0]  tx_status,     // 0x114
    output wire         tx_block_cfg,  // 1 = busy/held/draining
    // T07 round1：release 事件按**相机**分开
    //   rel_tgl0/1 = A 路（cam_ab_sel=0）块 0/1；rel_tgl2/3 = B 路（cam_ab_sel=1）块 0/1。
    //   分开是因为两块 cam_ddr_writer 各有自己的 protect0/1：共享一对 toggle 会让
    //   A 路的 release 误清 B 路同索引块（system round0 F1 实测）。
    output wire         rel_tgl0,      // A 路块 0 release（toggle → cam_ddr_writer A）
    output wire         rel_tgl1,      // A 路块 1 release
    output wire         rel_tgl2,      // B 路块 0 release（toggle → cam_ddr_writer B）
    output wire         rel_tgl3,      // B 路块 1 release
    output wire         tx_src_lock,   // 1 = 本帧/held 帧占着源

    // ---------------- DDR 用户域（usr_clk，100MHz）----------------
    input  wire         clk_ddr,
    input  wire         rst_ddr,

    // ---------------- AXI4 读通道 ----------------
    output wire [3:0]   m_axi_arid,
    output reg  [28:0]  m_axi_araddr,
    output reg  [7:0]   m_axi_arlen,
    output wire [2:0]   m_axi_arsize,
    output wire [1:0]   m_axi_arburst,
    output reg          m_axi_arvalid,
    input  wire         m_axi_arready,
    input  wire [3:0]   m_axi_rid,
    input  wire [255:0] m_axi_rdata,
    input  wire [1:0]   m_axi_rresp,
    input  wire         m_axi_rlast,
    input  wire         m_axi_rvalid,
    output wire         m_axi_rready
);

    // ========================================================================
    //  参数推导
    // ========================================================================
    localparam integer BEAT_BYTES   = 32;
    localparam integer FRAME_BYTES  = W * H;
    localparam integer TLP_BYTES    = PAY_DW * 4;
    localparam integer PAY_BEATS    = PAY_DW / 8;
    localparam integer LAST_K       = PAY_BEATS;
    localparam [7:0]   ARLEN        = BURST_BEATS - 1;
    localparam [9:0]   PAY_LEN      = PAY_DW;
    localparam integer BURST_BYTES  = BURST_BEATS * BEAT_BYTES;

    localparam integer NTLP_CW   = clogb2(MAX_FRAME_BYTES / TLP_BYTES   + 1);
    localparam integer NBURST_CW = clogb2(MAX_FRAME_BYTES / BURST_BYTES + 1);

    localparam [2:0]   AXI_SIZE     = 3'd5;
    localparam [1:0]   AXI_BURST    = 2'b01;
    localparam [28:0] BURST_STEP   = BURST_BEATS * BEAT_BYTES;

    localparam [7:0] E_NONE     = 8'd0,
                     E_NO_DST   = 8'd1,
                     E_WAIT_TO  = 8'd2,
                     E_AXI      = 8'd3,
                     E_NO_DB    = 8'd4,
                     E_NOT_ARM  = 8'd5,
                     E_ARM_REJ  = 8'd6,
                     E_CANCEL   = 8'd7,
                     E_HELD     = 8'd8,
                     E_SRC      = 8'd9,
                     E_CFG      = 8'd10,
                     E_BAD_ACK  = 8'd11;

    localparam [2:0] S_IDLE  = 3'd0, S_FILL  = 3'd1, S_HEAD  = 3'd2, S_DATA  = 3'd3,
                     S_TEND  = 3'd4, S_WAIT  = 3'd5, S_DRAIN = 3'd6;
    localparam [2:0] A_IDLE = 3'd0, A_AR = 3'd1, A_R = 3'd2, A_DONE = 3'd3;

    localparam [2:0] G_IDLE = 3'd0, G_ARMED = 3'd1, G_TX = 3'd2, G_HELD = 3'd3, G_DRAIN = 3'd4;

    // ========================================================================
    //  小函数
    // ========================================================================
    function [255:0] bswap256;
        input [255:0] x;
        begin
            bswap256 = {x[7:0],   x[15:8],  x[23:16], x[31:24],
                        x[39:32], x[47:40], x[55:48], x[63:56],
                        x[71:64], x[79:72], x[87:80], x[95:88],
                        x[103:96],x[111:104],x[119:112],x[127:120],
                        x[135:128],x[143:136],x[151:144],x[159:152],
                        x[167:160],x[175:168],x[183:176],x[191:184],
                        x[199:192],x[207:200],x[215:208],x[223:216],
                        x[231:224],x[239:232],x[247:240],x[255:248]};
        end
    endfunction

    function [31:0] bswap32;
        input [31:0] x;
        begin
            bswap32 = {x[7:0], x[15:8], x[23:16], x[31:24]};
        end
    endfunction

    function integer clogb2;
        input integer v;
        integer i;
        begin
            clogb2 = 0;
            for (i = v - 1; i > 0; i = i >> 1) clogb2 = clogb2 + 1;
        end
    endfunction

    function [FIFO_AW:0] bin2gray;
        input [FIFO_AW:0] b;
        begin
            bin2gray = b ^ (b >> 1);
        end
    endfunction

    // ========================================================================
    //  寄存器/线网声明
    // ========================================================================
    reg  [2:0]  p_st;
    reg  [2:0]  k;
    reg  [NTLP_CW-1:0] tlp;
    reg  [NTLP_CW-1:0] ntlp_m1_lat;
    reg  [31:0] last_seq;
    reg  [63:0] addr_q;
    reg  [63:0] db_a_q;
    reg  [31:0] db_val;
    reg         db_ena;
    reg         db_phase;
    reg         req_level;
    reg  [31:0] base_lat;
    reg         flush;
    reg  [7:0]  err_r;
    reg  [15:0] err_cnt;
    reg  [15:0] wt_cnt;
    reg         rd_have;
    reg         src_lat;
    reg         last_ok;
    reg         db_sent;
    reg  [31:0] tlp_cnt;
    reg         tx_active;
    reg         cancel_r;

    reg  [2:0]  g_st;
    reg  [31:0] lat_dst_lo, lat_dst_hi, lat_db_lo, lat_db_hi;
    reg  [31:0] lat_cap, lat_sess, lat_fbytes;
    reg         lat_src, lat_cam;
    reg  [31:0] held_seq, held_sess;
    reg         reject_sticky;
    reg  [31:0] evt_cnt, rej_cnt;
    reg         claimed_par, claimed_par_v, claimed_cam;
    reg         rel_tgl0_r, rel_tgl1_r, rel_tgl2_r, rel_tgl3_r;
    reg         fb_hold_r;
    reg         tx_go;

    reg  [255:0]     f_mem [0:(1 << FIFO_AW) - 1];
    reg  [FIFO_AW:0] wptr_bin, wptr_gray;
    reg  [FIFO_AW:0] rptr_bin, rptr_gray;
    reg  [FIFO_AW:0] wgray_s1, wgray_s2;
    reg  [FIFO_AW:0] rgray_s1, rgray_s2;
    reg  [255:0]     fifo_rdata;

    reg  [2:0]  a_st;
    reg  [NBURST_CW-1:0] a_bcnt;
    reg  [NBURST_CW-1:0] nburst_m1_lat;
    reg         done_level;
    reg         err_sticky;
    reg         req_s1, req_s2;
    reg  [31:0] base_s1, base_s2;
    reg         done_s1, done_s2;
    reg         derr_s1, derr_s2;
    reg         alive_s1, alive_s2;

    wire alive      = ~rst_ddr;
    wire rst_all_fb = rst_fb | (~alive_s2 & ~src_sel);

    wire utx_ack;
    wire beat_present;
    wire beat_ready;

    // ========================================================================
    //  ARM 校验用组合量（声明放在使用之前）
    // ========================================================================
    wire [31:0] ddr_cap_eff = (ddr_cap_bytes > 32'h2000_0000) ? 32'h2000_0000 : ddr_cap_bytes;
    wire [32:0] dst_sum     = {1'b0, dst_lo} + {1'b0, frame_bytes};
    wire        dst_wrap    = dst_sum[32] & (dst_hi == 32'hFFFF_FFFF);
    wire [63:0] dst_q       = {dst_hi, dst_lo};
    wire [63:0] db_q        = {db_hi, db_lo};
    wire [63:0] dst_end_q   = dst_q + {32'd0, frame_bytes};
    wire        db_overlap  = !((db_q + 64'd4 <= dst_q) || (db_q >= dst_end_q));

    wire [31:0] src_seq = src_sel ? fb_frame_cnt : ddr_seq;
    wire        src_rdy = src_sel ? 1'b1        : ddr_status[0];

    wire src_evt = src_rdy && (src_seq != last_seq);

    // T07 round1：release 判定必须**按当前相机选中的那一对基址**（A/B 两块基址不同），
    // 否则 B 路永远 par_valid=0 → 发布块拿不到 release（system round0 F1）。
    //   cam_sel_live 是准静态配置（claim 时还与 ARM 锁存值比对），帧内不变。
    wire [31:0] par_base0 = cam_sel_live ? BASE0B : BASE0;
    wire [31:0] par_base1 = cam_sel_live ? BASE1B : BASE1;
    wire par_valid = (ddr_base == par_base0) || (ddr_base == par_base1);
    wire par_now   = (ddr_base == par_base1) ? 1'b1 : 1'b0;

    wire claim_desc_ok = (src_sel == lat_src) && (cam_sel_live == lat_cam) &&
                         (frame_bytes == lat_fbytes) &&
                         (!src_sel || (frame_bytes == FRAME_BYTES));
    wire claim_base_ok = src_sel ? 1'b1 :
                         ((ddr_base[11:0] == 12'd0) && (ddr_base != 32'd0) &&
                          ((ddr_base + frame_bytes) <= ddr_cap_eff));
    wire claim = src_evt && push_en && (g_st == G_ARMED) && claim_desc_ok && claim_base_ok;

    // ========================================================================
    //  异步 FIFO（写口 ddr 域、读口片内域）
    // ========================================================================
    wire [FIFO_AW:0] wptr_bin_nxt  = wptr_bin  + {{FIFO_AW{1'b0}}, 1'b1};
    wire [FIFO_AW:0] wptr_gray_nxt = bin2gray(wptr_bin_nxt);
    wire [FIFO_AW:0] rptr_bin_nxt  = rptr_bin  + {{FIFO_AW{1'b0}}, 1'b1};
    wire [FIFO_AW:0] rptr_gray_nxt = bin2gray(rptr_bin_nxt);

    wire fifo_wfull = (wptr_gray_nxt == {~rgray_s2[FIFO_AW:FIFO_AW-1],
                                          rgray_s2[FIFO_AW-2:0]});
    wire fifo_empty = (rptr_gray == wgray_s2);
    wire fifo_wr    = m_axi_rvalid & ~fifo_wfull;

    wire pop_data  = ~src_lat && (p_st == S_DATA)  && utx_ack && (k != LAST_K) && !fifo_empty;
    wire pop_fill  = ~src_lat && (p_st == S_FILL)  && !rd_have && !fifo_empty;
    wire pop_tend  = ~src_lat && (p_st == S_TEND)  && !flush && (tlp != ntlp_m1_lat) && !rd_have && !fifo_empty;
    wire pop_drain = (p_st == S_DRAIN) && !fifo_empty;
    wire fifo_pop  = pop_data | pop_fill | pop_tend | pop_drain;

    wire next_ok   = (k != LAST_K) && !src_lat && !fifo_empty;

    assign m_axi_rready = ~fifo_wfull;

    always @(posedge clk_ddr)
        if (fifo_wr) f_mem[wptr_bin[FIFO_AW-1:0]] <= m_axi_rdata;

    always @(posedge clk_ddr or posedge rst_ddr) begin
        if (rst_ddr) begin
            wptr_bin  <= {(FIFO_AW+1){1'b0}};
            wptr_gray <= {(FIFO_AW+1){1'b0}};
        end else if (fifo_wr) begin
            wptr_bin  <= wptr_bin_nxt;
            wptr_gray <= wptr_gray_nxt;
        end
    end

    always @(posedge clk_ddr or posedge rst_ddr) begin
        if (rst_ddr) begin
            rgray_s1 <= {(FIFO_AW+1){1'b0}};
            rgray_s2 <= {(FIFO_AW+1){1'b0}};
        end else begin
            rgray_s1 <= rptr_gray;
            rgray_s2 <= rgray_s1;
        end
    end

    always @(posedge clk_fb or posedge rst_all_fb) begin
        if (rst_all_fb) begin
            wgray_s1 <= {(FIFO_AW+1){1'b0}};
            wgray_s2 <= {(FIFO_AW+1){1'b0}};
        end else begin
            wgray_s1 <= wptr_gray;
            wgray_s2 <= wgray_s1;
        end
    end

    always @(posedge clk_fb)
        if (fifo_pop) fifo_rdata <= f_mem[rptr_bin[FIFO_AW-1:0]];

    always @(posedge clk_fb or posedge rst_all_fb) begin
        if (rst_all_fb) begin
            rptr_bin  <= {(FIFO_AW+1){1'b0}};
            rptr_gray <= {(FIFO_AW+1){1'b0}};
        end else if (fifo_pop) begin
            rptr_bin  <= rptr_bin_nxt;
            rptr_gray <= rptr_gray_nxt;
        end
    end

    wire beat_consumed = utx_ack && (k != 3'd0);

    always @(posedge clk_fb or posedge rst_all_fb) begin
        if (rst_all_fb)         rd_have <= 1'b0;
        else if (fifo_pop)      rd_have <= 1'b1;
        else if (beat_consumed || (p_st == S_IDLE)) rd_have <= 1'b0;
    end

    // ========================================================================
    //  ERAM 数据源（src_sel=1）
    // ========================================================================
    localparam integer EWORDS = FRAME_BYTES / 4;

    reg  [2:0]   e_lane;
    reg  [3:0]   e_rcnt;
    reg  [255:0] e_pack;
    reg          e_rdy;
    reg          e_go_d;
    reg  [16:0]  e_req;

    wire        e_last     = (e_lane == 3'd7);
    wire        e_rd_go    = src_lat & ~e_rdy & (e_rcnt < 4'd8) & (e_req < EWORDS) & fb_grant;
    wire        e_d_vld    = e_go_d;
    wire        e_taken    = beat_consumed & src_lat;

    assign fb_rd_addr = {e_req, 2'b00};
    assign fb_req     = src_lat & ~e_rdy & (e_rcnt < 4'd8) & (e_req < EWORDS);
    assign src_act    = src_lat;
    assign fb_hold    = fb_hold_r;

    wire [255:0] beat_data = src_lat ? e_pack : fifo_rdata;
    wire         beat_have = src_lat ? e_rdy  : rd_have;

    always @(posedge clk_fb or posedge rst_all_fb) begin
        if (rst_all_fb) begin
            e_lane <= 3'd0; e_rcnt <= 4'd0; e_pack <= 256'd0; e_rdy <= 1'b0; e_go_d <= 1'b0; e_req <= 17'd0;
        end else if (tx_go) begin
            e_lane <= 3'd0; e_rcnt <= 4'd0; e_pack <= 256'd0; e_rdy <= 1'b0; e_go_d <= 1'b0; e_req <= 17'd0;
        end else begin
            e_go_d <= e_rd_go;
            if (e_rd_go) begin
                e_req  <= e_req + 17'd1;
                e_rcnt <= e_rcnt + 4'd1;
            end
            if (e_d_vld) begin
                e_lane <= e_last ? 3'd0 : (e_lane + 3'd1);
                case (e_lane)
                    3'd0: e_pack[31:0]    <= fb_rd_data;
                    3'd1: e_pack[63:32]   <= fb_rd_data;
                    3'd2: e_pack[95:64]   <= fb_rd_data;
                    3'd3: e_pack[127:96]  <= fb_rd_data;
                    3'd4: e_pack[159:128] <= fb_rd_data;
                    3'd5: e_pack[191:160] <= fb_rd_data;
                    3'd6: e_pack[223:192] <= fb_rd_data;
                    3'd7: e_pack[255:224] <= fb_rd_data;
                endcase
                if (e_last) e_rdy <= 1'b1;
            end
            if (e_taken) begin
                e_rdy  <= 1'b0;
                e_rcnt <= 4'd0;
            end
        end
    end

    // ========================================================================
    //  TL 口组合逻辑
    // ========================================================================
    wire [31:0] hdr_dw0 = {`MWR_FMT_4DW , `MWR_TYPE,
                           1'b0, 3'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
                           2'b0, 2'b0, PAY_LEN};
    wire [31:0] hdr_dw1 = {`EP_PF0_BDF, 8'd0, 4'hf, 4'hf};
    wire [31:0] hdr_dw2 = addr_q[63:32];
    wire [31:0] hdr_dw3 = {addr_q[31:2], 2'b00};

    wire [31:0] db_dw0  = {`MWR_FMT_4DW , `MWR_TYPE,
                           1'b0, 3'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
                           2'b0, 2'b0, 10'd1};
    wire [31:0] db_dw1  = {`EP_PF0_BDF, 8'd0, 4'h0, 4'hf};
    wire [31:0] db_dw2  = db_a_q[63:32];
    wire [31:0] db_dw3  = {db_a_q[31:2], 2'b00};

    wire [255:0] data_beat = bswap256(beat_data);

    assign beat_present = (p_st == S_HEAD) || (p_st == S_DATA);
    assign beat_ready   = (k == 3'd0) || beat_have;

    assign utx_req   = beat_present;
    assign utx_valid = (beat_present && beat_ready)
                       ? ((k == 3'd0) ? (db_phase ? 8'hF8 : 8'hF0) : 8'hFF) : 8'h00;
    assign utx_sop   = beat_present && beat_ready && (k == 3'd0);
    assign utx_eop   = beat_present && beat_ready &&
                       (db_phase ? (k == 3'd0) : (k == LAST_K));
    assign utx_data  = (k == 3'd0)
                       ? (db_phase
                          ? {db_dw0, db_dw1, db_dw2, db_dw3, bswap32(db_val), 96'd0}
                          : {hdr_dw0, hdr_dw1, hdr_dw2, hdr_dw3, 128'd0})
                       : data_beat;

    assign utx_ack = utx_sel && !tl_tx_wait && beat_present && beat_ready;

    // ddr → 片内同步器（本块只能用 rst_fb，见基线注释）
    always @(posedge clk_fb or posedge rst_fb) begin
        if (rst_fb) begin
            done_s1 <= 1'b0; done_s2 <= 1'b0;
            derr_s1 <= 1'b0; derr_s2 <= 1'b0;
            alive_s1 <= 1'b0; alive_s2 <= 1'b0;
        end else begin
            done_s1 <= done_level;  done_s2 <= done_s1;
            derr_s1 <= err_sticky;  derr_s2 <= derr_s1;
            alive_s1 <= alive;      alive_s2 <= alive_s1;
        end
    end

    assign st_status = {err_cnt, 11'd0, ddr_status[4], ddr_status[3],
                        db_sent, last_ok, tx_active};

    wire wt_hit     = (wt_cnt == WAIT_LIMIT);

    wire [31:0] arm_req64_lo = dst_lo;
    wire        arm_reject =
        (g_st != G_IDLE) || (session_id == 32'd0) ||
        (cap_bytes == 32'd0) || (frame_bytes == 32'd0) ||
        (frame_bytes > MAX_FRAME_BYTES) || (frame_bytes[11:0] != 12'd0) ||
        (cap_bytes < frame_bytes) ||
        ((dst_lo == 32'd0) && (dst_hi == 32'd0)) || (dst_lo[6:0] != 7'd0) ||
        ((db_lo == 32'd0) && (db_hi == 32'd0)) || (db_lo[1:0] != 2'd0) ||
        !link_up || (mps_code > 3'd5) ||
        (src_sel && (frame_bytes != FRAME_BYTES)) ||
        dst_wrap || db_overlap ||
        ((!src_sel) && (ddr_status[0] == 1'b0));

    // ========================================================================
    //  安全门 + 片内状态机
    // ========================================================================
    always @(posedge clk_fb or posedge rst_fb) begin
        if (rst_fb) begin
            p_st       <= S_IDLE;
            k          <= 3'd0;
            tlp        <= {NTLP_CW{1'b0}};
            ntlp_m1_lat<= {NTLP_CW{1'b0}};
            nburst_m1_lat <= {NBURST_CW{1'b0}};
            last_seq   <= 32'd0;
            src_lat    <= 1'b0;
            addr_q     <= 64'd0;
            db_a_q     <= 64'd0;
            db_val     <= 32'd0;
            db_ena     <= 1'b0;
            db_phase   <= 1'b0;
            req_level  <= 1'b0;
            base_lat   <= 32'd0;
            flush      <= 1'b0;
            err_r      <= E_NONE;
            err_cnt    <= 16'd0;
            wt_cnt     <= 16'd0;
            last_ok    <= 1'b0;
            db_sent    <= 1'b0;
            tlp_cnt    <= 32'd0;
            st_done    <= 32'd0;
            st_err     <= E_NONE;
            st_tlp_cnt <= 32'd0;
            tx_active  <= 1'b0;
            cancel_r   <= 1'b0;

            g_st       <= G_IDLE;
            lat_dst_lo <= 32'd0; lat_dst_hi <= 32'd0;
            lat_db_lo  <= 32'd0; lat_db_hi  <= 32'd0;
            lat_cap    <= 32'd0; lat_sess   <= 32'd0; lat_fbytes <= 32'd0;
            lat_src    <= 1'b0;  lat_cam    <= 1'b0;
            held_seq   <= 32'd0; held_sess  <= 32'd0;
            reject_sticky <= 1'b0;
            evt_cnt    <= 32'd0;
            rej_cnt    <= 32'd0;
            claimed_par<= 1'b0;
            claimed_par_v <= 1'b0;
            claimed_cam <= 1'b0;
            rel_tgl0_r <= 1'b0; rel_tgl1_r <= 1'b0; rel_tgl2_r <= 1'b0; rel_tgl3_r <= 1'b0;
            fb_hold_r  <= 1'b0;
            tx_go      <= 1'b0;
        end else begin
            tx_go <= 1'b0;

            // ---------------- 源帧事件：claim 或 pass（同一拍定） ----------------
            if (src_evt) begin
                evt_cnt  <= evt_cnt + 32'd1;
                last_seq <= src_seq;
                if (claim) begin
                    src_lat     <= src_sel;
                    base_lat    <= ddr_base;
                    db_val      <= st_done + 32'd1;
                    claimed_par   <= par_now;
                    claimed_cam   <= cam_sel_live;
                    claimed_par_v <= (!src_sel) && par_valid && push_en;
                    addr_q      <= {lat_dst_hi, lat_dst_lo};
                    db_a_q      <= {lat_db_hi, lat_db_lo};
                    db_ena      <= (lat_db_lo != 32'd0) || (lat_db_hi != 32'd0);
                    ntlp_m1_lat   <= (lat_fbytes / TLP_BYTES)   - {{(NTLP_CW-1){1'b0}}, 1'b1};
                    nburst_m1_lat <= (lat_fbytes / BURST_BYTES) - {{(NBURST_CW-1){1'b0}}, 1'b1};
                    req_level   <= ~src_sel;
                    flush       <= 1'b0;
                    err_r       <= E_NONE;
                    last_ok     <= 1'b0;
                    db_sent     <= 1'b0;
                    db_phase    <= 1'b0;
                    cancel_r    <= 1'b0;
                    tlp_cnt     <= 32'd0;
                    tlp         <= {NTLP_CW{1'b0}};
                    k           <= 3'd0;
                    tx_active   <= 1'b1;
                    tx_go       <= 1'b1;
                    p_st        <= S_FILL;
                    g_st        <= G_TX;
                    if (src_sel) fb_hold_r <= 1'b1;
                end else begin
                    // ---- pass：不传；DDR 源立刻把**本相机**那块还回去 ----
                    if (push_en && !src_sel && par_valid) begin
                        if (cam_sel_live) begin
                            if (par_now) rel_tgl3_r <= ~rel_tgl3_r;
                            else         rel_tgl2_r <= ~rel_tgl2_r;
                        end else begin
                            if (par_now) rel_tgl1_r <= ~rel_tgl1_r;
                            else         rel_tgl0_r <= ~rel_tgl0_r;
                        end
                    end
                    if (g_st == G_ARMED) begin
                        st_err <= E_SRC;
                        reject_sticky <= 1'b1;
                        rej_cnt <= rej_cnt + 32'd1;
                    end else if (g_st == G_HELD) begin
                        st_err <= E_HELD;
                        rej_cnt <= rej_cnt + 32'd1;
                    end else begin
                        st_err <= E_NOT_ARM;
                    end
                end
            end

            // ---------------- ARM ----------------
            if (arm_pulse) begin
                if (arm_reject) begin
                    st_err <= E_ARM_REJ;
                    reject_sticky <= 1'b1;
                    rej_cnt <= rej_cnt + 32'd1;
                end else begin
                    lat_dst_lo <= dst_lo;   lat_dst_hi <= dst_hi;
                    lat_db_lo  <= db_lo;    lat_db_hi  <= db_hi;
                    lat_cap    <= cap_bytes;
                    lat_sess   <= session_id;
                    lat_fbytes <= frame_bytes;
                    lat_src    <= src_sel;
                    lat_cam    <= cam_sel_live;
                    reject_sticky <= 1'b0;
                    g_st       <= G_ARMED;
                    st_err     <= E_NONE;
                    last_seq   <= src_seq;      // 只推 ARM 之后新发布的帧
                end
            end

            // ---------------- ACK_RELEASE ----------------
            if (ack_pulse) begin
                if ((g_st == G_HELD) && (ack_seq_w == held_seq) &&
                    (ack_session_w == held_sess) && (ack_session_w != 32'd0)) begin
                    g_st      <= G_IDLE;
                    st_err    <= E_NONE;
                    fb_hold_r <= 1'b0;
                    if (claimed_par_v) begin
                        if (claimed_cam) begin
                            if (claimed_par) rel_tgl3_r <= ~rel_tgl3_r;
                            else             rel_tgl2_r <= ~rel_tgl2_r;
                        end else begin
                            if (claimed_par) rel_tgl1_r <= ~rel_tgl1_r;
                            else             rel_tgl0_r <= ~rel_tgl0_r;
                        end
                    end
                    claimed_par_v <= 1'b0;
                end else begin
                    st_err <= E_BAD_ACK;               // 错误 ACK：held 槽不动
                    reject_sticky <= 1'b1;
                    rej_cnt <= rej_cnt + 32'd1;
                end
            end

            // ---------------- CANCEL ----------------
            if (cancel_pulse) begin
                case (g_st)
                    G_ARMED: begin
                        g_st      <= G_IDLE;
                        st_err    <= E_CANCEL;
                        fb_hold_r <= 1'b0;
                        if (push_en && !src_sel && par_valid) begin
                            if (cam_sel_live) begin
                                if (par_now) rel_tgl3_r <= ~rel_tgl3_r;
                                else         rel_tgl2_r <= ~rel_tgl2_r;
                            end else begin
                                if (par_now) rel_tgl1_r <= ~rel_tgl1_r;
                                else         rel_tgl0_r <= ~rel_tgl0_r;
                            end
                        end
                    end
                    G_TX: begin
                        cancel_r <= 1'b1;
                        st_err   <= E_CANCEL;
                        g_st     <= G_DRAIN;
                        // 已拉起的这一拍继续挂着，等它被收走后把本包补完再排空
                    end
                    G_HELD: begin
                        g_st      <= G_IDLE;
                        st_err    <= E_CANCEL;
                        fb_hold_r <= 1'b0;
                        if (claimed_par_v) begin
                            if (claimed_cam) begin
                                if (claimed_par) rel_tgl3_r <= ~rel_tgl3_r;
                                else             rel_tgl2_r <= ~rel_tgl2_r;
                            end else begin
                                if (claimed_par) rel_tgl1_r <= ~rel_tgl1_r;
                                else             rel_tgl0_r <= ~rel_tgl0_r;
                            end
                        end
                        claimed_par_v <= 1'b0;
                    end
                    default: ;
                endcase
            end

            if (cfg_reject) begin
                st_err <= E_CFG;
                reject_sticky <= 1'b1;
                rej_cnt <= rej_cnt + 32'd1;
            end

            // ---------------- 超时（已开始的包一定补完；未开始的拍也继续挂着） ----------------
            //  ★ 不"放弃"首拍：TL 口上 valid 拉起来之后必须**持稳**到被链路收走。
            //    超时只置 flush：等这一拍（若是包头/载荷）被收走后，把本包剩下的拍
            //    补完，再排空收尾。若链路一直不恢复，就停在这个 bounded error 状态
            //    （busy=1、无门铃、成功序号不加），直到真实链路恢复——见文件头 (5)。
            if (utx_sel && beat_present && tl_tx_wait) begin
                if (wt_hit) begin
                    flush <= 1'b1;
                    if (err_r == E_NONE) err_r <= E_WAIT_TO;
                end else begin
                    wt_cnt <= wt_cnt + 16'd1;
                end
            end else if (utx_ack) begin
                wt_cnt <= 16'd0;
            end

            // ---------------- AXI 读响应非 OKAY ----------------
            if (derr_s2 && (p_st != S_IDLE) && (err_r == E_NONE) && !cancel_r) begin
                err_r <= E_AXI;
                flush <= 1'b1;
            end

            // ---------------- 片内状态机 ----------------
            case (p_st)
                S_IDLE:  if (tx_go) p_st <= S_FILL;

                S_FILL:  if (beat_have) p_st <= (k == 3'd0) ? S_HEAD : S_DATA;

                S_HEAD: begin
                    if (utx_ack) begin
                        if (db_phase) begin
                            db_sent <= !cancel_r;
                            p_st    <= S_WAIT;
                        end else begin
                            k    <= 3'd1;
                            p_st <= beat_have ? S_DATA : S_FILL;
                        end
                    end
                end

                S_DATA: begin
                    if (utx_ack) begin
                        if (k == LAST_K) begin
                            k       <= 3'd0;
                            tlp_cnt <= tlp_cnt + 32'd1;
                            p_st    <= S_TEND;
                        end else begin
                            k    <= k + 3'd1;
                            p_st <= next_ok ? S_DATA : S_FILL;
                        end
                    end
                end

                S_TEND: begin
                    if (flush || cancel_r) begin
                        p_st <= S_DRAIN;
                    end else if (tlp == ntlp_m1_lat) begin
                        tlp <= tlp + {{(NTLP_CW-1){1'b0}}, 1'b1};
                        if (db_ena) begin
                            db_phase <= 1'b1;
                            p_st     <= S_HEAD;
                        end else begin
                            p_st     <= S_WAIT;
                        end
                    end else begin
                        tlp    <= tlp + {{(NTLP_CW-1){1'b0}}, 1'b1};
                        addr_q <= addr_q + TLP_BYTES;
                        p_st   <= S_HEAD;
                    end
                end

                S_WAIT: begin
                    if (done_s2 | src_lat) begin
                        st_err     <= cancel_r ? E_CANCEL : err_r;
                        st_tlp_cnt <= tlp_cnt;
                        last_ok    <= !cancel_r && (err_r == E_NONE) && db_sent;
                        if (!cancel_r && (err_r == E_NONE) && db_sent)
                            st_done <= st_done + 32'd1;
                        if (!cancel_r && (err_r != E_NONE)) err_cnt <= err_cnt + 16'd1;
                        req_level <= 1'b0;
                        flush     <= 1'b0;
                        db_phase  <= 1'b0;
                        k         <= 3'd0;
                        tlp       <= {NTLP_CW{1'b0}};
                        p_st      <= S_IDLE;
                    end
                end

                S_DRAIN: begin
                    if (fifo_empty && (done_s2 | src_lat)) begin
                        st_err     <= cancel_r ? E_CANCEL : err_r;
                        st_tlp_cnt <= tlp_cnt;
                        last_ok    <= 1'b0;
                        if (!cancel_r) err_cnt <= err_cnt + 16'd1;
                        req_level  <= 1'b0;
                        flush      <= 1'b0;
                        k          <= 3'd0;
                        tlp        <= {NTLP_CW{1'b0}};
                        p_st       <= S_IDLE;
                    end
                end

                default: p_st <= S_IDLE;
            endcase

            // ---------------- 一帧收尾：HELD / 释放 ----------------
            //  ★ 成功完成 ⇒ 进 HELD，**不释放源缓冲**（held 帧属于主机，直到匹配
            //    ACK 才 release——写者靠这个 release 才知道可以重写该块）。
            //    错误/取消 ⇒ 额度用完，立即释放（没有 held 帧要保）。
            if (tx_active && (p_st == S_IDLE)) begin
                tx_active <= 1'b0;
                if (cancel_r) begin
                    g_st   <= G_IDLE;
                    st_err <= E_CANCEL;
                    fb_hold_r <= 1'b0;
                    if (claimed_par_v) begin
                        if (claimed_cam) begin
                            if (claimed_par) rel_tgl3_r <= ~rel_tgl3_r;
                            else             rel_tgl2_r <= ~rel_tgl2_r;
                        end else begin
                            if (claimed_par) rel_tgl1_r <= ~rel_tgl1_r;
                            else             rel_tgl0_r <= ~rel_tgl0_r;
                        end
                    end
                    claimed_par_v <= 1'b0;
                end else if ((err_r == E_NONE) && db_sent && !flush) begin
                    g_st      <= G_HELD;
                    held_seq  <= db_val;
                    held_sess <= lat_sess;
                    st_err    <= E_NONE;
                    // fb_hold / claimed_par_v / 块 release 都留到 ACK（或 CANCEL）
                end else begin
                    g_st   <= G_IDLE;
                    st_err <= (err_r == E_NONE) ? E_WAIT_TO : err_r;
                    reject_sticky <= 1'b1;
                    rej_cnt <= rej_cnt + 32'd1;
                    fb_hold_r <= 1'b0;
                    if (claimed_par_v) begin
                        if (claimed_cam) begin
                            if (claimed_par) rel_tgl3_r <= ~rel_tgl3_r;
                            else             rel_tgl2_r <= ~rel_tgl2_r;
                        end else begin
                            if (claimed_par) rel_tgl1_r <= ~rel_tgl1_r;
                            else             rel_tgl0_r <= ~rel_tgl0_r;
                        end
                    end
                    claimed_par_v <= 1'b0;
                end
                cancel_r <= 1'b0;
            end
        end
    end

    // ========================================================================
    //  ddr 域：AXI4 读通道
    // ========================================================================
    always @(posedge clk_ddr or posedge rst_ddr) begin
        if (rst_ddr) begin
            req_s1  <= 1'b0;  req_s2  <= 1'b0;
            base_s1 <= 32'd0; base_s2 <= 32'd0;
        end else begin
            req_s1  <= req_level;  req_s2  <= req_s1;
            base_s1 <= base_lat;   base_s2 <= base_s1;
        end
    end

    assign m_axi_arid    = 4'd0;
    assign m_axi_arsize  = AXI_SIZE;
    assign m_axi_arburst = AXI_BURST;

    always @(posedge clk_ddr or posedge rst_ddr) begin
        if (rst_ddr) begin
            a_st          <= A_IDLE;
            a_bcnt        <= {NBURST_CW{1'b0}};
            m_axi_araddr  <= 29'd0;
            m_axi_arlen   <= 8'd0;
            m_axi_arvalid <= 1'b0;
            done_level    <= 1'b0;
            err_sticky    <= 1'b0;
        end else begin
            case (a_st)
                A_IDLE: begin
                    if (req_s2 && !fifo_wfull) begin
                        a_st          <= A_AR;
                        m_axi_araddr  <= base_s2[28:0] + a_bcnt * BURST_STEP;
                        m_axi_arlen   <= ARLEN;
                        m_axi_arvalid <= 1'b1;
                    end else if (!req_s2) begin
                        a_bcnt     <= {NBURST_CW{1'b0}};
                        err_sticky <= 1'b0;
                    end
                end

                A_AR: begin
                    if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        a_st          <= A_R;
                    end
                end

                A_R: begin
                    if (m_axi_rvalid && !fifo_wfull) begin
                        if (m_axi_rresp != 2'b00) err_sticky <= 1'b1;
                        if (m_axi_rlast) begin
                            if (a_bcnt == nburst_m1_lat) begin
                                a_bcnt     <= {NBURST_CW{1'b0}};
                                done_level <= 1'b1;
                                a_st       <= A_DONE;
                            end else begin
                                a_bcnt <= a_bcnt + {{(NBURST_CW-1){1'b0}}, 1'b1};
                                a_st   <= A_IDLE;
                            end
                        end
                    end
                end

                A_DONE: begin
                    if (!req_s2) begin
                        done_level <= 1'b0;
                        a_bcnt     <= {NBURST_CW{1'b0}};
                        err_sticky <= 1'b0;
                        a_st       <= A_IDLE;
                    end
                end

                default: a_st <= A_IDLE;
            endcase
        end
    end

    // ========================================================================
    //  对外状态/诊断
    // ========================================================================
    assign tx_status    = {27'd0, (g_st == G_DRAIN), reject_sticky,
                           (g_st == G_HELD), tx_active, (g_st == G_ARMED)};
    assign tx_block_cfg = (g_st != G_IDLE);
    assign rel_tgl0     = rel_tgl0_r;
    assign rel_tgl1     = rel_tgl1_r;
    assign rel_tgl2     = rel_tgl2_r;
    assign rel_tgl3     = rel_tgl3_r;
    assign tx_src_lock  = (g_st == G_TX) || (g_st == G_HELD) || (g_st == G_DRAIN);

endmodule
