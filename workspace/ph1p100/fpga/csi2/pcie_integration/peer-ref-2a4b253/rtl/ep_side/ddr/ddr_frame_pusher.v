///////////////////////////////////////////////////////////////////////////////
//  ddr_frame_pusher.v — 推帧引擎：EP 主动用 MWr 把 DDR3 里的整帧写进主机内存
//
//  ===========================================================================
//  一、它接什么
//  ===========================================================================
//   · DDR 侧：u_ddr3_mc_0 的 AXI4 **读**通道（axi_aclk = dhi_clk = IP 的 usr_clk，
//     100MHz；axi_aresetn = ddrphy_rst_n）。数据 256bit = 32 字节/拍，地址是字节
//     地址。每帧字节数 / 32 = 拍数，再按 4KB 切突发（arlen=127、arsize=5、INCR）：
//     640x480 = 9600 拍 = 75 个突发，4K = 259200 拍 = 2025 个突发；
//     两块缓冲基址都是 4KB 对齐（见 ddr_frame_writer / cam_ddr_writer 的参数），
//     所以一个突发正好一个 4KB 页，不跨页。
//
//  ★ 帧字节数（端口 frame_bytes，帧开头锁存）：MWr 数 = frame_bytes/128、
//    突发数 = frame_bytes/4096，两个除法都必须是整数 —— 顶层给的两个尺寸都满足。
//    计数器位宽由参数 MAX_FRAME_BYTES 现推（NTLP_CW / NBURST_CW），
//    所以换几何不会撑爆计数器（4K 的 64800 个 MWr / 2025 个突发已经超出
//    老的 12bit/8bit 位宽，这正是本步要改的地方）。
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
//  一之二、数据源：CTRL[7] = push_src（本步新增）
//  ===========================================================================
//   · 0（默认）：从 DDR3 里已发布的那一帧读 —— AXI4 读信道 + 异步 FIFO + 2 级同步器，
//     完全按上面的写法。
//   · 1：直接从片内 ERAM 帧缓存读（img_frame_src 的 fb[]），**不碰 DDR 任何一根线**。
//     用途：把「EP 主动把整帧用 MWr 写进主机内存」这条 DMA 单独验通，
//     DDR 未就绪/出问题时不被拖住。读口总线是同一个（fb[] 只允许一份读口，
//     多一份会被 TD 落成分布式 RAM，见 ddr_frame_writer.v 头部），
//     帧内由顶层按本模块的 src_act 选通，主机预取仍然优先（img_frame_src 的仲裁）。
//   · 两条源在 TL 侧完全合流：都变成「一拍 256bit + 有没有」两个信号，
//     MWr 怎么拼、字节序、门铃、错误码全都不分源。ERAM 源的拼拍与
//     ddr_frame_writer 逐字一致（lane k 的字放 [32k +: 32]），所以 bswap256
//     之后主机看到的字节序与 MMIO 0x60 读到的一模一样。
//   · src_sel 在每帧开头锁存一次（src_act），帧内不再变；ERAM 源的「帧号」
//     就是帧缓存帧计数器（img_frame_cnt，只在 EOF 递增 ⇒ 读到的必定是完整帧），
//     门铃里写的仍是已推帧数。
//   · 两源共用 fb 读口 ⇒ 不要同时开：验 ERAM 路时把 CTRL[5]（ddr_en）留 0。
//
//  ===========================================================================
//  二、发出去的 TLP 长什么样（本模块最容易出错的地方，逐条写清依据）
//  ===========================================================================
//   一个 MWr：4DW 头 + 载荷 32 个 dw（128 字节 = 协商出的 MaxPayload），共 36 个 dw。
//   TL 口一拍 256bit = 8 个 dw，所以一个 MWr 占 5 拍：
//     第 0 拍：4 个 dw 头（valid=8'hF0，其余位无效；与厂商 IO 写完成包同形）
//     第 1..4 拍：各 8 个 dw 载荷（valid=8'hFF）
//   每帧的 MWr 数 = frame_bytes / 128（640x480 → 2400 个；4K → 64800 个），
//   **在每帧开头按主机给的 frame_bytes 现算并锁存**（见下面「帧字节数」一段），
//   所以同一份 RTL 既能推 640x480 也能推 4K。最后一个载荷拍带 eop。
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
//   ===========================================================================
//   四、数据通路与跨时钟域
//   ===========================================================================
//   ddr 源（usr_clk 100MHz）                     片内域（tl_clk_user 62.5MHz）
//   ─────────────────────────                   ─────────────────────────────
//   每 4KB 一个 AXI4 读突发 ─▶ 异步 FIFO（256bit×2**FIFO_AW 拍，格雷码指针）
//                                        ─▶ 拆成 5 拍 1 个 MWr 交 TL 口
//   ERAM 源（tl_clk_user）  8 个字拼一拍（fb 唯一读口，1 字/拍）─▶ 同一拆包逻辑
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
    // ---- 本模块要支持的最大帧字节数（决定 MWr 数/突发数计数器的位宽）----
    //   默认 4K 灰度 3840x2160 = 8294400；640x480 那一路只是它的子集。
    //   计数位宽由它现算（见下面 NTLP_CW / NBURST_CW），所以换几何不会撑爆计数器。
    parameter integer MAX_FRAME_BYTES = 3840 * 2160,
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

    // ---- 本帧字节数（帧开头锁存）----
    //   DDR 源：0xAC DDR_LEN（640x480 = 307200 / 4K = 8294400）；ERAM 源：fb 的 DATA_LEN。
    //   ★ 必须满足：frame_bytes % TLP_BYTES == 0 且 % BURST_BYTES == 0（两个尺寸都满足：
    //     307200 = 2400x128 = 75x4096、8294400 = 64800x128 = 2025x4096）。
    //     否则 MWr 数/突发数不是整数，帧尾会对不上（本模块不再按 W*H 推）。
    input  wire [31:0]  frame_bytes,

    // ---- DDR 搬运握手（ddr_frame_writer 的只读字）----
    input  wire [31:0]  ddr_seq,       // 0xA0 已整帧落 DDR3 的帧号
    input  wire [31:0]  ddr_base,      // 0xA4 该帧在 DDR3 里的字节基址
    input  wire [31:0]  ddr_status,    // 0xA8 bit0 valid / bit1 busy / bit2 err /
                                       //       bit3 alive / bit4 cal_done

    // ---- ERAM 帧缓存源（CTRL[7]=1；见文件头「数据源」）----
    input  wire         src_sel,       // 1 = 数据源取片内 ERAM 帧缓存（绕开 DDR）
    input  wire [31:0]  fb_frame_cnt,  // 帧缓存帧计数器（ERAM 源拿它当「帧号」）
    output wire [31:0]  fb_rd_addr,    // 帧缓存读字节地址（低 2 位恒 0）
    input  wire [31:0]  fb_rd_data,    // 该地址的数据（1 拍延迟）
    output wire         fb_req,        // 本拍想读一个字（交给 img_frame_src 仲裁）
    input  wire         fb_grant,      // 本拍读口给了我们
    output wire         src_act,       // 本帧实际用的源（锁存值；顶层据此分读口）

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
    localparam integer FRAME_BYTES  = W * H;                     // fb 一帧字节数（ERAM 源用）
    localparam integer TLP_BYTES    = PAY_DW * 4;                // 128（每个 MWr 载荷）
    localparam integer PAY_BEATS    = PAY_DW / 8;                // 每个 MWr 载荷拍数 = 4
    localparam integer LAST_K       = PAY_BEATS;                 // 一个 MWr 的末拍下标
    localparam [7:0]   ARLEN        = BURST_BEATS - 1;           // axi_arlen
    localparam [9:0]   PAY_LEN      = PAY_DW;                    // Length 字段（dw）
    localparam integer BURST_BYTES  = BURST_BEATS * BEAT_BYTES;   // 4096

    // ---- 每帧的 MWr 数 / 突发数：由 frame_bytes 现算（4K 与 640x480 共用本模块）----
    //   640x480：2400 个 MWr / 75 个突发；4K：64800 个 MWr / 2025 个突发。
    //   在 S_IDLE 起帧那一拍锁存（帧内不变），计数器位宽按 4K 取值。
    localparam integer NTLP_CW   = clogb2(MAX_FRAME_BYTES / TLP_BYTES   + 1);
    localparam integer NBURST_CW = clogb2(MAX_FRAME_BYTES / BURST_BYTES + 1);
    wire [NTLP_CW-1:0]   ntlp_m1_w   = (frame_bytes / TLP_BYTES)   - {{(NTLP_CW-1){1'b0}}, 1'b1};
    wire [NBURST_CW-1:0] nburst_m1_w = (frame_bytes / BURST_BYTES) - {{(NBURST_CW-1){1'b0}}, 1'b1};

    localparam [2:0]   AXI_SIZE     = 3'd5;    // 2**5 = 32 字节/拍
    localparam [1:0]   AXI_BURST    = 2'b01;   // INCR
    localparam [28:0] BURST_STEP   = BURST_BEATS * BEAT_BYTES;   // 每个突发的字节数
                                 // ★ 地址步长必须由 BURST_BEATS 推出来。原来写的
                                 //   {a_bcnt,12'b0}（= a_bcnt×4096）只在 BURST_BEATS=128 时
                                 //   恰好成立；参数一改（如测试台用 16 拍/突发）突发之间就
                                 //   会空出 3.5KB，DDR 里只有每 4KB 的头 512B 被写，其余是空洞
                                 //  （sim_do/tb_ddr_frame_pusher.v 就是这么暴露出来的）。

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
    //  信号声明（两域的都先声明，免得 TD 造隐式网）
    // ========================================================================
    // ---- 片内域：状态与握手 ----
    reg  [2:0]  p_st;
    reg  [2:0]  k;              // 本 MWr 内的拍下标：0 = 头，1..LAST_K = 载荷
    reg  [NTLP_CW-1:0] tlp;            // 本帧第几个 MWr（0..ntlp_m1_lat）
    reg  [NTLP_CW-1:0] ntlp_m1_lat;    // 本帧 MWr 数 - 1（起帧锁存；640x480=2399 / 4K=64799）
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
    reg         src_lat;        // 本帧实际用的源（每帧开头锁存一次）
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
    reg  [NBURST_CW-1:0] a_bcnt;         // 已完成突发数（0..nburst_m1_lat；4K 要 2025）
    reg  [NBURST_CW-1:0] nburst_m1_lat;  // 本帧突发数 - 1（起帧锁存；640x480=74 / 4K=2024）
    reg         done_level;
    reg         err_sticky;
    reg         req_s1, req_s2;
    reg  [31:0] base_s1, base_s2;
    reg         done_s1, done_s2;
    reg         derr_s1, derr_s2;
    reg         alive_s1, alive_s2;

    wire alive      = ~rst_ddr;
    // 片内域复位：默认（DDR 源）还叠上「ddr 侧已出复位」这个同步电平（见文件头）；
    // 但 ERAM 源（src_sel=1）不该被 DDR 拖住 —— DDR 真死了也要能把帧推出去，
    // 所以这一路只在 src_sel=0 时才受 alive_s2 影响。src_sel 是配置位，别在
    // 一帧推的过程中翻它（翻了会复位本域、放弃当前帧）。
    wire rst_all_fb = rst_fb | (~alive_s2 & ~src_sel);

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

    // pop 条件（组合，见上）：全部只对 DDR 源成立（src_lat=1 时没有任何 pop）
    //   pop_data  —— 载荷拍被收走的那一拍补下一个载荷字（本拍手上那个字正好被用掉，
    //                所以这里**不能**再判 rd_have：那一拍它一定是 1）
    //   pop_fill  —— S_FILL 里手上没字时补一个
    //   pop_tend  —— MWr 之间那一拍空档里，把下一个 MWr 的第 1 拍数据备好
    //   pop_drain —— 出错排空（拿到就丢，rd_have 无所谓）
    wire pop_data  = ~src_lat && (p_st == S_DATA)  && utx_ack && (k != LAST_K) && !fifo_empty;
    wire pop_fill  = ~src_lat && (p_st == S_FILL)  && !rd_have && !fifo_empty;
    wire pop_tend  = ~src_lat && (p_st == S_TEND)  && !flush && (tlp != ntlp_m1_lat) && !rd_have && !fifo_empty;
    wire pop_drain = (p_st == S_DRAIN) && !fifo_empty;
    wire fifo_pop  = pop_data | pop_fill | pop_tend | pop_drain;

    // 本拍收走后，下一个载荷字能不能马上到位（决定要不要去 S_FILL 等）。
    // ERAM 源每拍要现读 8 个字，永远不满「下一拍就到」，所以恒为 0（走 S_FILL 等）。
    wire next_ok   = (k != LAST_K) && !src_lat && !fifo_empty;

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

    // 起始条件：使能 + 本源已有一帧可推 + 帧号与上次处理过的不一样。
    //   · DDR 源（src_sel=0）：要 ddr_frame_writer 发布过一帧（ddr_status[0]）；
    //   · ERAM 源（src_sel=1）：片内帧缓存的帧计数器一变就推（它只在 EOF 递增，
    //     所以读到的必定是刚写完整的那一帧）。
    // 声明放在 ERAM 打包器之前（打包器要用 start 复位字指针）。
    wire [31:0] src_seq = src_sel ? fb_frame_cnt : ddr_seq;
    wire        src_rdy = src_sel ? 1'b1        : ddr_status[0];
    wire        start   = push_en && src_rdy && (src_seq != last_seq) && (p_st == S_IDLE);

    // ========================================================================
    //  ERAM 数据源（CTRL[7]=1）：直接从片内帧缓存凑「一拍 256bit」
    //   · 与 ddr_frame_writer 的拼拍写法逐字一致：lane k 的字放 [32k +: 32]，
    //     所以下游的 bswap256（TL 要求首字节在高位）与 DDR 模式走完全同一条路
    //     ⇒ 主机拿到的字节序与 MMIO 0x60 读到的、以及 DDR 里的都一致。
    //   · 读口是 img_frame_src 那唯一一份，与主机预取 / DDR 搬运共用：
    //     用 fb_req 申请，拿到 fb_grant 那一拍才发地址（数据晚 1 拍）。
    //   · 一帧 = FRAME_BYTES/4 = 76800 字 = 9600 拍；攒满一拍就停（e_rdy=1），
    //     等 TL 侧把这一拍吃掉再接着攒 —— 只提前攒一拍，不预读整帧。
    // ========================================================================
    localparam integer EWORDS = FRAME_BYTES / 4;

    reg  [2:0]   e_lane;
    reg  [3:0]   e_rcnt;         // 本拍已发出的读次数（0..8）——一拍正好 8 个字
    reg  [255:0] e_pack;
    reg          e_rdy;          // 手上有一拍凑好了还没被吃掉
    reg          e_go_d;         // 读地址发出的下一拍：fb_rd_data 有效
    reg  [16:0]  e_req;          // 已发出的读地址数（字索引）
                                 // ★ 两件事必须分开数：
                                 //   ① 地址（e_req）只随 e_rd_go 前进；
                                 //   ② lane（e_lane）只在数据回来的那一拍前进。
                                 //   拿 lane 算地址会把同一个字读两遍（错位旋转）；
                                 //   不给每个拍限制读次数则一拍会多发一次读，那第 9 个
                                 //   数据会在本拍已 e_rdy=1 之后落下来，把 lane0 冲掉。

    wire        e_last     = (e_lane == 3'd7);
    wire        e_rd_go    = src_lat & ~e_rdy & (e_rcnt < 4'd8) & (e_req < EWORDS) & fb_grant;
    wire        e_d_vld    = e_go_d;
    wire        e_taken    = beat_consumed & src_lat;   // TL 侧把手上这一拍吃掉了

    assign fb_rd_addr = {e_req, 2'b00};                 // 字索引 → 字节地址
    assign fb_req     = src_lat & ~e_rdy & (e_rcnt < 4'd8) & (e_req < EWORDS);
    assign src_act    = src_lat;

    // DDR 源与 ERAM 源的「一拍 256bit + 有没有」在这里合流，下游只认 beat_data/beat_have
    wire [255:0] beat_data = src_lat ? e_pack : fifo_rdata;
    wire         beat_have = src_lat ? e_rdy  : rd_have;

    always @(posedge clk_fb or posedge rst_all_fb) begin
        if (rst_all_fb) begin
            e_lane <= 3'd0; e_rcnt <= 4'd0; e_pack <= 256'd0; e_rdy <= 1'b0; e_go_d <= 1'b0; e_req <= 17'd0;
        end else if (start) begin              // 本帧从字 0 重新开始
            e_lane <= 3'd0; e_rcnt <= 4'd0; e_pack <= 256'd0; e_rdy <= 1'b0; e_go_d <= 1'b0; e_req <= 17'd0;
        end else begin
            e_go_d <= e_rd_go;
            if (e_rd_go) begin                     // 地址数随请求前进
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
                if (e_last) e_rdy <= 1'b1;         // 一拍凑齐，等 TL 侧取走
            end
            if (e_taken) begin
                e_rdy  <= 1'b0;                    // 取走了，接着攒下一拍
                e_rcnt <= 4'd0;                    // 下一拍重新数 8 个字
            end
        end
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
    wire [255:0] data_beat = bswap256(beat_data);

    assign beat_present = (p_st == S_HEAD) || (p_st == S_DATA);
    assign beat_ready   = (k == 3'd0) || beat_have;   // 头/门铃那拍不要帧数据

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

    // 起始条件（push_en / 本源就绪 / 帧号变化）与 src_seq、src_rdy 的声明
    // 已提到上面 ERAM 打包器之前（start 是那两个源的公共起点）。

    // ddr → 片内的同步器（电平，2 级）
    //  ★ 本块的复位只能用 rst_fb，**不能用 rst_all_fb**：
    //    rst_all_fb 里含 ~alive_s2，而 alive_s2 就是本块产生的 —— 用 rst_all_fb
    //    会形成自锁：上电时 alive_s2=0 ⇒ rst_all_fb=1 ⇒ 本块永远处于复位 ⇒
    //    alive_s2 永远是 0 ⇒ 整个片内域（状态机 / FIFO 指针 / ERAM 打包器）
    //    永远出不来。实测（sim_do/tb_ddr_frame_pusher.v）：推帧引擎一直是
    //    p_st=S_IDLE、一个 TLP 都不发，与板上「0xC8 恒 0x18、已推帧数恒 0」一致。
    //    ddr_frame_writer.v 里同名的同步块用的就是 rst_fb，这里改成一致。
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

    // 位序逐位对齐 ep_bar_win.v 头部那张表：bit0 busy / bit1 last_ok /
    // bit2 doorbell_sent / bit3 ddr_alive / bit4 ddr_cal_done / [31:16] err_cnt
    assign st_status = {err_cnt, 11'd0, ddr_status[4], ddr_status[3],
                        db_sent, last_ok, (p_st != S_IDLE)};

    always @(posedge clk_fb or posedge rst_all_fb) begin
        if (rst_all_fb) begin
            p_st       <= S_IDLE;
            k          <= 3'd0;
            tlp        <= {NTLP_CW{1'b0}};
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
                            // 目标地址没配：整帧不发。错误码要**当拍就写到 0xC8**，
                            // 否则主机只看到 done 不涨、err 恒 0，跟「引擎没使能」分不清
                            // （本 TB 的 PHASE0 就是拿这一条做判据的）。
                            err_r  <= E_NO_DST;
                            st_err <= E_NO_DST;
                        end else begin
                            last_seq  <= src_seq;   // 这一帧只处理一次
                            src_lat   <= src_sel;   // 本帧用哪个源（帧内不再变）
                            base_lat  <= ddr_base;
                            ntlp_m1_lat   <= ntlp_m1_w;     // 本帧的 MWr 数/突发数
                            nburst_m1_lat <= nburst_m1_w;   // （4K/640x480 都在这儿定死）
                            addr_q    <= {dst_hi, dst_lo};
                            db_a_q    <= {db_hi, db_lo};
                            db_ena    <= (db_lo != 32'd0) || (db_hi != 32'd0);
                            db_val    <= st_done + 32'd1;   // 门铃里写本帧序号
                            req_level <= ~src_sel;          // ERAM 源不叫 ddr 侧读
                            flush     <= 1'b0;
                            err_r     <= ((db_lo == 32'd0) && (db_hi == 32'd0))
                                         ? E_NO_DB : E_NONE;
                            last_ok   <= 1'b0;
                            db_sent   <= 1'b0;
                            db_phase  <= 1'b0;
                            tlp_cnt   <= 32'd0;
                            tlp       <= {NTLP_CW{1'b0}};
                            k         <= 3'd0;
                            p_st      <= S_FILL;    // 先等第一个载荷字到位
                        end
                    end
                end

                // ------------------------------------------------------------
                // 等本拍数据到位：DDR 源是 FIFO 出字，ERAM 源是攒满 8 个字
                S_FILL: begin
                    if (beat_have) p_st <= (k == 3'd0) ? S_HEAD : S_DATA;
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
                            p_st <= beat_have ? S_DATA : S_FILL;
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
                    end else if (tlp == ntlp_m1_lat) begin
                        if (db_ena) begin
                            db_phase <= 1'b1;
                            p_st     <= S_HEAD;   // 接着发门铃那一拍
                        end else begin
                            p_st     <= S_WAIT;
                        end
                    end else begin
                        tlp    <= tlp + {{(NTLP_CW-1){1'b0}}, 1'b1};
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
                    if (done_s2 | src_lat) begin   // ERAM 源没有 DDR 收尾，数据吃完即完成
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
                        tlp       <= {NTLP_CW{1'b0}};
                        p_st      <= S_IDLE;
                    end
                end

                // ------------------------------------------------------------
                // 出错：不发 TLP，但要把 FIFO 排空，否则 ddr 侧会卡在 FIFO 满上、
                // 永远报不出 done，本模块也就永远回不到 IDLE。
                S_DRAIN: begin
                    // !fifo_empty 时由 pop_drain 一直 pop（拿到的字直接丢掉）
                    if (fifo_empty && (done_s2 | src_lat)) begin
                        st_err     <= err_r;
                        st_tlp_cnt <= tlp_cnt;
                        last_ok    <= 1'b0;
                        err_cnt    <= err_cnt + 16'd1;
                        req_level  <= 1'b0;
                        flush      <= 1'b0;
                        k          <= 3'd0;
                        tlp        <= {NTLP_CW{1'b0}};
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
                        // 突发地址 = 本帧基址 + 已完成突发数 × 4KB。
                        // 注意不能把基址先存进寄存器再用：base_s2 与 req_s2 是同一个
                        // 同步器的同一拍跳变的，存下来的会是上一帧的基址。
                        m_axi_araddr  <= base_s2[28:0] + a_bcnt * BURST_STEP;   // 步长=突发字节数（别写死 4KB）
                        m_axi_arlen   <= ARLEN;
                        m_axi_arvalid <= 1'b1;
                    end else if (!req_s2) begin
                        // 一帧收工（或还没开始）：突发计数与出错一起清
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

endmodule
