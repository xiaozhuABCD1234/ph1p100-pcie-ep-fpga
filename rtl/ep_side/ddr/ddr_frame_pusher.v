///////////////////////////////////////////////////////////////////////////////
//  ddr_frame_pusher.v — 推帧引擎：EP 主动用 MWr 把 DDR3 里的整帧写进主机内存
//
//  ===========================================================================
//  一、它接什么
//  ===========================================================================
//   · DDR 侧：u_ddr3_mc_0 的 AXI4 **读**通道（axi_aclk = dhi_clk = IP 的 usr_clk，
//     100MHz；axi_aresetn = ddrphy_rst_n）。数据 256bit = 32 字节/拍，地址是字节
//     地址。每帧 307200 字节 = 9600 拍 = 75 个 4KB 突发（arlen=127、arsize=5、INCR）；
//     两块缓冲基址都是 4KB 对齐（见 ddr_frame_writer 的参数），所以一个突发正好
//     一个 4KB 页，不跨页。
//   · 片内侧：DDR 搬运的握手字（wr_frame_seq / wr_base / wr_status，见
//     ddr_frame_writer.v），以及 pcie_ep_engine 里新开的「用户侧 TL 发送口」
//     （utx_req/utx_data/utx_sop/utx_eop/utx_valid；引擎只在自己的发送状态机
//     空闲时把发送口让出来，见 pcie_ep_engine.v 的 TL_TX_USER）。
//   · 寄存器面：CTRL[6] = push_en（默认 0，不置位时行为与改动前完全一致）；
//     0xB0/0xB4 = 目标地址低/高 32 位；0xB8/0xBC = 门铃地址低/高 32 位；
//     0xC0 已推帧数；0xC4 状态；0xC8 最近一次错误码；0xCC 最近一帧发出的 MWr 数。
//     （偏移与位定义写在 ep_bar_win.v 头部那张表里，这里不重复。）
//
//  ===========================================================================
//  二、发出去的 TLP 长什么样（本模块最容易出错的地方，逐条写清依据）
//  ===========================================================================
//   一个 MWr：4DW 头 + 载荷 32 个 dw（128 字节 = 协商出的 MaxPayload），共 36 个 dw。
//   TL 口一拍 256bit = 8 个 dw，所以一个 MWr 占 5 拍：
//     第 0 拍：4 个 dw 头（valid=8'hF0，其余位无效；与厂商 IO 写完成包同形）
//     第 1..4 拍：各 8 个 dw 载荷（valid=8'hFF）
//   每帧 2400 个这样的 MWr；最后一个载荷拍带 eop。
//
//   头里各字段的摆法照 pcie_ep_engine.v 里 MSI-X 那一段（那段就是厂商自己的
//   「用户逻辑拼 MWr 头」的样板），即按 PCIe 规范里**头 dword 的位序**摆：
//     dw0 = {Fmt,Type,R,TC,R,Attr[2],R,TH,TD,EP,Attr[1:0],AT[1:0],Length[9:0]}
//     dw1 = {RequesterID[15:0],Tag[7:0],LastDWBE[3:0],FirstDWBE[3:0]}
//     dw2 / dw3 = 64 位地址
//   · 4DW 头里 **dw2 = 地址的高 32 位、dw3 = 地址的低 30 位 + 00**（不是反过来）。
//     依据两条：(a) 规范里 4DW 头的地址就是「高 32 位在前」；(b) 厂商 MSI-X 那段
//     正是 {addr[63:2], 2'b00} 摆进 [191:128]，即 [191:160]=addr[63:32]、
//     [159:128]={addr[31:2],2'b0}。所以这里 addr_q[63:32] 放 [191:160]。
//   · 「首字节在高位」：TL 口上第 1 个字节在 256bit 的最高字节位。所以
//       - 头的位序就照上面直接摆（Fmt 在最高位），与厂商那段一致；
//       - 载荷 dw 必须整拍字节倒序：DDR/AXI 给的一拍里 rdata[7:0] 是**最低地址**
//         那个字节，线上要求它排在最前面 → 整拍 256bit 字节倒序。
//         这条与 ep_bar_win.v 的 bswap32 是同一个道理（那边逐 dw 翻、这边整拍翻），
//         也是本工程设计里唯一被板上实测过的字节序结论（见 ep_bar_win.v:99-111）。
//       - 门铃那 1 个 dw 载荷同样要 bswap32。
//   · 长度与字节使能：长度 32 的帧 MWr 是 dw 对齐满写 ⇒ First/Last DW BE 全 1；
//     门铃长度 1 ⇒ Last DW BE 必须是 0（规范 2.2.5），与厂商 MSI-X 段一致。
//   · Tag：MWr 是 Posted 请求，**不需要完成包**，Tag 字段对无需完成的请求没有意义
//     （厂商 MSI-X 那段也固定写 8'd0）。所以这里不分配、不释放、恒 0：既没有
//     「等完成」的生命周期，也不存在把两个 TLP 的完成搞混的问题。
//   · 排序：本帧所有 MWr 与最后那笔门铃都是 TC0 的 Posted 写。PCIe 排序规则里
//     Posted 请求之间不许互相超越，所以主机一定先看到帧数据、最后看到门铃；属性位
//     全 0（不带 Relaxed Ordering），与驱动侧「序号那笔不能带 RO」的要求一致
//     （driver/include/anlogic_pci_ioctl.h 的握手约定）。
//   · 门铃是**一次只写一个 dw** 的独立 MWr（不是挂在帧尾那一拍上），地址由主机经
//     0xB8/0xBC 给，内容是本帧序号（1 起、每帧 +1）。
//
//  ===========================================================================
//  三、反压与让路（不许假设带宽）
//  ===========================================================================
//   · 每一拍都靠 utx_sel & !tl_tx_wait 才算被链路收走；没收走就**保持不动**
//     （数据、sop/eop/valid 全保持），一拍一拍等，不做任何时序假设。
//   · 等 tl_tx_wait 连续超过 WAIT_LIMIT 拍（默认 65535 拍 ≈ 1.05ms）判超时，
//     本帧停发（错误码 2）。
//   · 每个 MWr 之间留 1 拍空档（S_TEND，utx_req 拉低那一拍），把 TL 发送口还给
//     引擎，让主机的 MRd 完成包（CPL/CPLD）能插进来。为此 pcie_ep_engine.v 里
//     iow/ior/memrd 三个请求标志改成「发完才清」——否则主机读请求在推帧 TLP 期间
//     到达时，标志两三拍就没了、完成包被丢，主机读到全 F。
//
//  ===========================================================================
//  四、数据通路与跨时钟域
//  ===========================================================================
//   ddr 域（usr_clk 100MHz）                       片内域（tl_clk_user 62.5MHz）
//   ─────────────────────────                     ─────────────────────────────
//   每 4KB 一个 AXI4 读突发 ─▶ 异步 FIFO（256bit×2**FIFO_AW 拍，格雷码指针）
//                                        ─▶ 拆成 5 拍 1 个 MWr 交 TL 口
//   req_level / base_lat  ◀── 2 级同步 ◀── 片内「有一帧要推」电平
//   done_level / err_sticky ──▶ 2 级同步 ──▶ 片内收尾
//   · 读数据不丢：m_axi_rready = FIFO 不满，FIFO 满时链路自己停（AXI 允许）。
//   · FIFO 的读口是「输出寄存器 + 组合 pop」：pop 那一拍装字，下一拍数据就位，
//     所以载荷拍之间不用等（详见 FIFO 那一段的注释）。
//   · 出错（rresp 非 OKAY、超时）不虚报成「推完」：本帧不发门铃、已推帧数不加，
//     只把错误码与错误计数留给主机看。门铃是「这一帧完整落到主机内存」的唯一标记，
//     所以半截数据到主机也无害（主机只认门铃）。
//   · 出错后把 FIFO 排空（S_DRAIN），否则 ddr 侧会卡在「FIFO 满」上永远报不出 done。
//
//  ===========================================================================
//  五、已知限制（不是本模块能自己解决的，写在这里免得上板时误判）
//  ===========================================================================
//   · 双缓冲只能保证「一帧的窗口」：本帧必须在 ddr_frame_writer 再写两块之前推完
//     （相机一帧 30~64ms，链路满速推一帧约 0.4ms，差两个数量级）。链路长时间不通
//     时本模块 1ms 就超时收手，不会长占。
//   · 规范里 4DW 头是给 ≥4GB 地址用的，地址 <4GB 却用 4DW 属「接收方行为未定义」。
//     这里按任务要求固定用 4DW（目标的 DMA 地址由寄存器给，可能落在 4GB 以上）；
//     真遇到 RK3588 的 RC 拒收，改成「高 32 位为 0 时用 3DW」即可（只影响 dw0 的
//     Fmt 与载荷起始拍位置）。
//   · 帧推到一半若 DDR 侧不再给数据（板上 DDR 出问题），本模块会停在 S_FILL、
//     busy 一直为 1 —— 宁可主机看到「还忙着」，也不虚报一帧。
//   · 与主机驱动的接口只做到任务书要求的那一层：目标地址（0xB0/0xB4，主机自己
//     算好放进来）+ 帧内地址递增 + 门铃 1 个 dw。驱动侧 include/anlogic_pci_ioctl.h
//     里的收帧协议比这多两项：帧数据前面的 16 字节槽头（seq/len/flags）和
//     门铃要同时更新 mailbox.seq 与 mailbox.count（2 个 dw）。本模块**没做**这两项，
//     写这两项需要再加一组寄存器（槽头值/槽头写使能）并把门铃写成 2 个 dw，
//     属于任务书之外的范围；主机侧拿 frame_grab 取帧之前要先把这个缺口接上。
//
//  ===========================================================================
//  六、错误码（0xC8）与状态（0xC4）
//  ===========================================================================
//    0 = 正常（数据与门铃都发了）        1 = 目标地址未配置（整帧没发）
//    2 = 等 tl_tx_wait 超时（本帧停发）  3 = AXI 读响应非 OKAY（本帧停发）
//    4 = 门铃地址未配置（数据推了、门铃没发；仍计入已推帧数，last_ok 为 0）
//    状态位：bit0 busy / bit1 last_ok / bit2 db_sent / bit3 ddr_alive /
//            bit4 ddr_cal_done / [31:16] 错误累计
//  两个地址寄存器都写 0 时：目标地址 0 ⇒ 错误码 1、整帧不发；门铃地址 0 ⇒ 错误码 4、
//  只发帧数据。所以主机要么把两个地址都配好，要么显式用 0 表示「不要门铃」。
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

`include "../../common/TLP_FMT_TYPE.v"
`include "../../common/BDF.v"

module ddr_frame_pusher #(
    // ---- 帧几何：与 ddr_frame_writer / img_frame_src 用同一组 W/H ----
    parameter integer W           = 640,
    parameter integer H           = 480,
    // ---- 每个 MWr 的载荷双字数（= MaxPayload/4 = 32，即 128 字节）----
    parameter integer PAY_DW      = 32,
    // ---- 异步 FIFO 深度 = 2**FIFO_AW 拍（每拍 256bit = 32 字节）----
    parameter integer FIFO_AW     = 7,
    // ---- 每个 AXI4 突发的拍数（128 × 32B = 4096 = 4KB，不跨页）----
    parameter integer BURST_BEATS = 128,
    // ---- 等 tl_tx_wait 的超时门限（拍）；62.5MHz 下 0xFFFF ≈ 1.05ms ----
    parameter [15:0]  WAIT_LIMIT  = 16'hFFFF
)(
    // ---------------- 片内帧缓存域（tl_clk_user，62.5MHz）----------------
    input  wire         clk_fb,
    input  wire         rst_fb,        // 高有效（power_on_rst_dly）

    // ---- 寄存器面 ----
    input  wire         push_en,       // CTRL[6]
    input  wire [31:0]  dst_lo,        // 0xB0 目标地址低 32 位
    input  wire [31:0]  dst_hi,        // 0xB4 目标地址高 32 位
    input  wire [31:0]  db_lo,         // 0xB8 门铃地址低 32 位
    input  wire [31:0]  db_hi,         // 0xBC 门铃地址高 32 位
    output reg  [31:0]  st_done,       // 0xC0 已推帧数
    output wire [31:0]  st_status,     // 0xC4 状态（位定义见文件头）
    output reg  [7:0]   st_err,        // 0xC8 最近一次错误码
    output reg  [31:0]  st_tlp_cnt,    // 0xCC 最近一帧发出的 MWr 数（不含门铃）

    // ---- DDR 搬运握手（ddr_frame_writer 的只读字）----
    input  wire [31:0]  ddr_seq,       // 0xA0 已整帧落 DDR3 的帧号
    input  wire [31:0]  ddr_base,      // 0xA4 该帧在 DDR3 里的字节基址
    input  wire [31:0]  ddr_status,    // 0xA8 bit0 valid / bit1 busy / bit2 err /
                                       //       bit3 alive / bit4 cal_done

    // ---- TL 用户发送口（引擎在 TL_TX_USER 态把发送口让出来）----
    input  wire         utx_sel,       // 1 = 本拍 TL 发送口归我们
    input  wire         tl_tx_wait,    // 链路本拍不收
    output wire         utx_req,       // 1 = 我们这一拍要发一拍
    output wire [255:0] utx_data,
    output wire         utx_sop,
    output wire         utx_eop,
    output wire [7:0]   utx_valid,

    // ---------------- DDR 用户域（u_ddr3_mc_0/usr_clk，100MHz）----------------
    input  wire         clk_ddr,
    input  wire         rst_ddr,       // 高有效（= !ddrphy_rst_n = !axi_aresetn）

    // ---------------- AXI4 读通道（接 u_ddr3_mc_0，256bit）----------------
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
    //  参数推导（只在这里出现，别处不散落魔数）
    // ========================================================================
    localparam integer BEAT_BYTES   = 32;                        // 256bit / 8
    localparam integer FRAME_BYTES  = W * H;                     // 307200
    localparam integer TLP_BYTES    = PAY_DW * 4;                // 128（每个 MWr 载荷）
    localparam integer NTLP         = FRAME_BYTES / TLP_BYTES;   // 2400 个 MWr
    localparam integer PAY_BEATS    = PAY_DW / 8;                // 每个 MWr 载荷拍数 = 4
    localparam integer LAST_K       = PAY_BEATS;                 // 一个 MWr 的末拍下标
    localparam integer NBEATS       = FRAME_BYTES / BEAT_BYTES;  // 9600 拍
    localparam integer NBURST       = NBEATS / BURST_BEATS;      // 75 个 4KB 突发
    localparam [7:0]   ARLEN        = BURST_BEATS - 1;           // axi_arlen
    localparam [7:0]   NBURST_M1    = NBURST - 1;
    localparam [11:0]  NTLP_M1      = NTLP - 1;
    localparam [9:0]   PAY_LEN      = PAY_DW;                    // Length 字段（dw）

    localparam [2:0]   AXI_SIZE     = 3'd5;    // 2**5 = 32 字节/拍
    localparam [1:0]   AXI_BURST    = 2'b01;   // INCR

    // 错误码（见文件头）
    localparam [7:0] E_NONE    = 8'd0,
                     E_NO_DST  = 8'd1,
                     E_WAIT_TO = 8'd2,
                     E_AXI     = 8'd3,
                     E_NO_DB   = 8'd4;

    // 片内侧状态机
    localparam [2:0] S_IDLE  = 3'd0,   // 等「DDR 里有新帧 + push_en」
                     S_FILL  = 3'd1,   // 等 FIFO 出数据（补一个字）
                     S_HEAD  = 3'd2,   // 发一个 MWr 的第 0 拍（4 个 dw 头 / 门铃那拍）
                     S_DATA  = 3'd3,   // 发一个 MWr 的载荷拍
                     S_TEND  = 3'd4,   // 一个 MWr 发完，空 1 拍让引擎插完成包
                     S_WAIT  = 3'd5,   // 等 ddr 侧把整帧读完
                     S_DRAIN = 3'd6;   // 出错：把 FIFO 排空，等 ddr 侧收手

    // AXI 读突发状态机
    localparam [2:0] A_IDLE = 3'd0, A_AR = 3'd1, A_R = 3'd2, A_DONE = 3'd3;

    // ========================================================================
    //  小函数
    // ========================================================================
    // 整拍 256bit 字节倒序（见文件头「首字节在高位」）
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

    function [FIFO_AW:0] bin2gray;
        input [FIFO_AW:0] b;
        begin
            bin2gray = b ^ (b >> 1);
        end
    endfunction

    // ========================================================================
    //  信号声明（两域的都先声明，免得 TD 造隐式网）
    // ========================================================================
    // ---- 片内域：状态与握手 ----
    reg  [2:0]  p_st;
    reg  [2:0]  k;              // 本 MWr 内的拍下标：0 = 头，1..LAST_K = 载荷
    reg  [11:0] tlp;            // 本帧第几个 MWr（0..NTLP-1）
    reg  [31:0] last_seq;       // 已经处理过的帧号（含出错停发那帧）
    reg  [63:0] addr_q;         // 帧内当前目标地址（每发一个 MWr +128）
    reg  [63:0] db_a_q;         // 门铃地址（本帧固定）
    reg  [31:0] db_val;         // 门铃里写的那 1 个 dw
    reg         db_ena;
    reg         db_phase;
    reg         req_level;
    reg  [31:0] base_lat;
    reg         flush;
    reg  [7:0]  err_r;
    reg  [15:0] err_cnt;
    reg  [15:0] wt_cnt;
    reg         rd_have;        // fifo_rdata 里有一个还没用掉的载荷拍
    reg         last_ok;
    reg         db_sent;
    reg  [31:0] tlp_cnt;

    // ---- 异步 FIFO ----
    reg  [255:0]     f_mem [0:(1 << FIFO_AW) - 1];
    reg  [FIFO_AW:0] wptr_bin, wptr_gray;
    reg  [FIFO_AW:0] rptr_bin, rptr_gray;
    reg  [FIFO_AW:0] wgray_s1, wgray_s2;   // 写指针 → 片内域（判空）
    reg  [FIFO_AW:0] rgray_s1, rgray_s2;   // 读指针 → ddr 域（判满）
    reg  [255:0]     fifo_rdata;

    // ---- ddr 域 ----
    reg  [2:0]  a_st;
    reg  [7:0]  a_bcnt;
    reg         done_level;
    reg         err_sticky;
    reg         req_s1, req_s2;
    reg  [31:0] base_s1, base_s2;
    reg         done_s1, done_s2;
    reg         derr_s1, derr_s2;
    reg         alive_s1, alive_s2;

    wire alive      = ~rst_ddr;
    wire rst_all_fb = rst_fb | ~alive_s2;

    // TL 口本拍是否被收走（FIFO 的 pop 条件要用，所以先声明、后赋值）
    wire utx_ack;
    wire beat_present;
    wire beat_ready;

    // ========================================================================
    //  异步 FIFO：写口 ddr 域、读口片内域
    //    写法与 ddr_frame_writer.v 里那个同一套：格雷码指针 + 2 级同步器 +
    //    简单写口 + 输出寄存器读口（TD 推 ERAM20K）。
    //    ★ 读口的 pop 是**组合**的：pop 那一拍把字装进 fifo_rdata，下一拍就到
    //      位，所以载荷拍之间不用插等待拍。pop 只在「手上没有字」时才发，避免
    //      一个拍要两个字时多 pop 一次把数据错位。
    // ========================================================================
    wire [FIFO_AW:0] wptr_bin_nxt  = wptr_bin  + {{FIFO_AW{1'b0}}, 1'b1};
    wire [FIFO_AW:0] wptr_gray_nxt = bin2gray(wptr_bin_nxt);
    wire [FIFO_AW:0] rptr_bin_nxt  = rptr_bin  + {{FIFO_AW{1'b0}}, 1'b1};
    wire [FIFO_AW:0] rptr_gray_nxt = bin2gray(rptr_bin_nxt);

    wire fifo_wfull = (wptr_gray_nxt == {~rgray_s2[FIFO_AW:FIFO_AW-1],
                                          rgray_s2[FIFO_AW-2:0]});
    wire fifo_empty = (rptr_gray == wgray_s2);
    wire fifo_wr    = m_axi_rvalid & ~fifo_wfull;

    // pop 条件（组合，见上）：
    //   pop_data  —— 载荷拍被收走的那一拍补下一个载荷字（本拍手上那个字正好被用掉，
    //                所以这里**不能**再判 rd_have：那一拍它一定是 1）
    //   pop_fill  —— S_FILL 里手上没字时补一个
    //   pop_tend  —— MWr 之间那一拍空档里，把下一个 MWr 的第 1 拍数据备好
    //   pop_drain —— 出错排空（拿到就丢，rd_have 无所谓）
    wire pop_data  = (p_st == S_DATA)  && utx_ack && (k != LAST_K) && !fifo_empty;
    wire pop_fill  = (p_st == S_FILL)  && !rd_have && !fifo_empty;
    wire pop_tend  = (p_st == S_TEND)  && !flush && (tlp != NTLP_M1) && !rd_have && !fifo_empty;
    wire pop_drain = (p_st == S_DRAIN) && !fifo_empty;
    wire fifo_pop  = pop_data | pop_fill | pop_tend | pop_drain;

    // 本拍收走后，下一个载荷字能不能马上到位（决定要不要去 S_FILL 等）
    wire next_ok   = (k != LAST_K) && !fifo_empty;

    assign m_axi_rready = ~fifo_wfull;

    // 写口：单条简单写语句 + 无复位（TD 推断 ERAM20K 的关键，别加分支）
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

    always @(posedge clk_ddr or posedge rst_ddr) begin   // 读指针 → ddr 域（判满）
        if (rst_ddr) begin
            rgray_s1 <= {(FIFO_AW+1){1'b0}};
            rgray_s2 <= {(FIFO_AW+1){1'b0}};
        end else begin
            rgray_s1 <= rptr_gray;
            rgray_s2 <= rgray_s1;
        end
    end

    always @(posedge clk_fb or posedge rst_all_fb) begin // 写指针 → 片内域（判空）
        if (rst_all_fb) begin
            wgray_s1 <= {(FIFO_AW+1){1'b0}};
            wgray_s2 <= {(FIFO_AW+1){1'b0}};
        end else begin
            wgray_s1 <= wptr_gray;
            wgray_s2 <= wgray_s1;
        end
    end

    // 读数据寄存器：pop 那一拍装字
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

    // rd_have：手上这个字还在不在（pop 优先：同一拍既 pop 又用掉时，pop 说了算）
    //   S_IDLE 里一律清：这样每一帧开头都是「手上没字」，不会把上一帧最后一个字
    //   （出错排空时可能还留着）当成新帧的第一拍载荷。
    wire beat_consumed = utx_ack && (k != 3'd0);

    always @(posedge clk_fb or posedge rst_all_fb) begin
        if (rst_all_fb)         rd_have <= 1'b0;
        else if (fifo_pop)      rd_have <= 1'b1;
        else if (beat_consumed || (p_st == S_IDLE)) rd_have <= 1'b0;
    end

    // ========================================================================
    //  片内域：帧触发 / 拆 MWr / TL 口时序
    // ========================================================================
    // 头字段（照 MSI-X 段）
    wire [31:0] hdr_dw0 = {`MWR_FMT_4DW , `MWR_TYPE,
                           1'b0, 3'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
                           2'b0, 2'b0, PAY_LEN};
    wire [31:0] hdr_dw1 = {`EP_PF0_BDF, 8'd0, 4'hf, 4'hf};   // tag 恒 0（Posted）
    wire [31:0] hdr_dw2 = addr_q[63:32];                      // 4DW：dw2 = 地址高 32 位
    wire [31:0] hdr_dw3 = {addr_q[31:2], 2'b00};

    wire [31:0] db_dw0  = {`MWR_FMT_4DW , `MWR_TYPE,
                           1'b0, 3'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
                           2'b0, 2'b0, 10'd1};
    wire [31:0] db_dw1  = {`EP_PF0_BDF, 8'd0, 4'h0, 4'hf};   // 长度 1 ⇒ Last DW BE = 0
    wire [31:0] db_dw2  = db_a_q[63:32];
    wire [31:0] db_dw3  = {db_a_q[31:2], 2'b00};

    // 本拍要发的这一拍（组合）
    wire [255:0] data_beat = bswap256(fifo_rdata);

    assign beat_present = (p_st == S_HEAD) || (p_st == S_DATA);
    assign beat_ready   = (k == 3'd0) || rd_have;   // 头/门铃那拍不要 DDR 数据

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

    // 本拍被链路收走（引擎把口子给了我们、链路不反压、且这一拍确实有效）
    assign utx_ack = utx_sel && !tl_tx_wait && beat_present && beat_ready;

    // 起始条件：使能 + DDR 里已发布过一帧 + 帧号与上次处理过的不一样
    wire start = push_en && ddr_status[0] && (ddr_seq != last_seq) && (p_st == S_IDLE);

    // ddr → 片内的同步器（电平，2 级）
    always @(posedge clk_fb or posedge rst_all_fb) begin
        if (rst_all_fb) begin
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
                        last_ok, db_sent, (p_st != S_IDLE)};

    always @(posedge clk_fb or posedge rst_all_fb) begin
        if (rst_all_fb) begin
            p_st       <= S_IDLE;
            k          <= 3'd0;
            tlp        <= 12'd0;
            last_seq   <= 32'd0;
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
        end else begin
            // ---- 等 tl_tx_wait 超时：口子给了我们、链路却一直不收 ----
            if (utx_sel && beat_present && tl_tx_wait) begin
                if (wt_cnt == WAIT_LIMIT) begin
                    flush <= 1'b1;
                    if (err_r == E_NONE) err_r <= E_WAIT_TO;
                end else begin
                    wt_cnt <= wt_cnt + 16'd1;
                end
            end else if (utx_ack) begin
                wt_cnt <= 16'd0;
            end

            // ---- AXI 读响应非 OKAY：本帧不要了（err_sticky 随帧结束清）----
            if (derr_s2 && (p_st != S_IDLE) && (err_r == E_NONE)) begin
                err_r <= E_AXI;
                flush <= 1'b1;
            end

            case (p_st)
                // ------------------------------------------------------------
                S_IDLE: begin
                    if (start) begin
                        if ((dst_lo == 32'd0) && (dst_hi == 32'd0)) begin
                            err_r <= E_NO_DST;      // 目标地址没配：整帧不发
                        end else begin
                            last_seq  <= ddr_seq;   // 这一帧只处理一次
                            base_lat  <= ddr_base;
                            addr_q    <= {dst_hi, dst_lo};
                            db_a_q    <= {db_hi, db_lo};
                            db_ena    <= (db_lo != 32'd0) || (db_hi != 32'd0);
                            db_val    <= st_done + 32'd1;   // 门铃里写本帧序号
                            req_level <= 1'b1;              // 叫 ddr 侧开始读
                            flush     <= 1'b0;
                            err_r     <= ((db_lo == 32'd0) && (db_hi == 32'd0))
                                         ? E_NO_DB : E_NONE;
                            last_ok   <= 1'b0;
                            db_sent   <= 1'b0;
                            db_phase  <= 1'b0;
                            tlp_cnt   <= 32'd0;
                            tlp       <= 12'd0;
                            k         <= 3'd0;
                            p_st      <= S_FILL;    // 先等第一个载荷字到位
                        end
                    end
                end

                // ------------------------------------------------------------
                // 等 FIFO 出数据：来了就装进输出寄存器（组合 pop，下一拍到位）
                S_FILL: begin
                    if (rd_have) p_st <= (k == 3'd0) ? S_HEAD : S_DATA;
                end

                // ------------------------------------------------------------
                // 一个 MWr 的第 0 拍（4 个 dw 头；门铃那一拍是 5 个 dw）
                S_HEAD: begin
                    if (utx_ack) begin
                        if (db_phase) begin
                            db_sent <= 1'b1;      // 门铃是单拍 TLP，收走就完事
                            p_st    <= S_WAIT;
                        end else begin
                            k    <= 3'd1;
                            p_st <= rd_have ? S_DATA : S_FILL;
                        end
                    end
                end

                // ------------------------------------------------------------
                // 载荷拍：每一拍被收走时顺手把下一个载荷字 pop 进来
                S_DATA: begin
                    if (utx_ack) begin
                        if (k == LAST_K) begin
                            k       <= 3'd0;
                            tlp_cnt <= tlp_cnt + 32'd1;
                            p_st    <= S_TEND;
                        end else begin
                            k    <= k + 3'd1;
                            // next_ok：这一拍 pop 了下一个字，下一拍就位
                            p_st <= next_ok ? S_DATA : S_FILL;
                        end
                    end
                end

                // ------------------------------------------------------------
                // 一个 MWr 发完：空 1 拍（utx_req 拉低）把 TL 口还给引擎
                S_TEND: begin
                    if (flush) begin
                        p_st <= S_DRAIN;
                    end else if (tlp == NTLP_M1) begin
                        if (db_ena) begin
                            db_phase <= 1'b1;
                            p_st     <= S_HEAD;   // 接着发门铃那一拍
                        end else begin
                            p_st     <= S_WAIT;
                        end
                    end else begin
                        tlp    <= tlp + 12'd1;
                        addr_q <= addr_q + TLP_BYTES;   // 帧内地址递增
                        p_st   <= S_HEAD;
                    end
                end

                // ------------------------------------------------------------
                // 等 ddr 侧读完整帧。
                // done_level 是「本帧 9600 拍全进过 FIFO」的电平；走到 S_WAIT 说明
                // 数据已从 FIFO 取空，此时 done_s2 只可能是本帧的（上一帧的 done
                // 早在本帧开头几千拍之前就被 ddr 侧撤掉了，见 A_IDLE 的收尾）。
                S_WAIT: begin
                    if (done_s2) begin
                        st_err     <= err_r;
                        st_tlp_cnt <= tlp_cnt;
                        last_ok    <= (err_r == E_NONE);
                        if ((err_r != E_WAIT_TO) && (err_r != E_AXI))
                            st_done <= st_done + 32'd1;   // 数据推出去了就计数
                        if (err_r != E_NONE) err_cnt <= err_cnt + 16'd1;
                        req_level <= 1'b0;
                        flush     <= 1'b0;
                        db_phase  <= 1'b0;
                        k         <= 3'd0;
                        tlp       <= 12'd0;
                        p_st      <= S_IDLE;
                    end
                end

                // ------------------------------------------------------------
                // 出错：不发 TLP，但要把 FIFO 排空，否则 ddr 侧会卡在 FIFO 满上、
                // 永远报不出 done，本模块也就永远回不到 IDLE。
                S_DRAIN: begin
                    // !fifo_empty 时由 pop_drain 一直 pop（拿到的字直接丢掉）
                    if (fifo_empty && done_s2) begin
                        st_err     <= err_r;
                        st_tlp_cnt <= tlp_cnt;
                        last_ok    <= 1'b0;
                        err_cnt    <= err_cnt + 16'd1;
                        req_level  <= 1'b0;
                        flush      <= 1'b0;
                        k          <= 3'd0;
                        tlp        <= 12'd0;
                        p_st       <= S_IDLE;
                    end
                end

                default: p_st <= S_IDLE;
            endcase
        end
    end

    // ========================================================================
    //  ddr 域：AXI4 读通道（一次一个 4KB 突发，读满 NBURST 个报 done）
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
            a_bcnt        <= 8'd0;
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
                        // 突发地址 = 本帧基址 + 已完成突发数 × 4KB。
                        // 注意不能把基址先存进寄存器再用：base_s2 与 req_s2 是同一个
                        // 同步器的同一拍跳变的，存下来的会是上一帧的基址。
                        m_axi_araddr  <= base_s2[28:0] + {a_bcnt, 12'b0};
                        m_axi_arlen   <= ARLEN;
                        m_axi_arvalid <= 1'b1;
                    end else if (!req_s2) begin
                        // 一帧收工（或还没开始）：突发计数与出错一起清
                        a_bcnt     <= 8'd0;
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
                            if (a_bcnt == NBURST_M1) begin
                                a_bcnt     <= 8'd0;
                                done_level <= 1'b1;
                                a_st       <= A_DONE;
                            end else begin
                                a_bcnt <= a_bcnt + 8'd1;
                                a_st   <= A_IDLE;
                            end
                        end
                    end
                end

                A_DONE: begin
                    if (!req_s2) begin
                        done_level <= 1'b0;
                        a_bcnt     <= 8'd0;
                        err_sticky <= 1'b0;
                        a_st       <= A_IDLE;
                    end
                end

                default: a_st <= A_IDLE;
            endcase
        end
    end

endmodule
