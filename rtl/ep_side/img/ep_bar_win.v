///////////////////////////////////////////////////////////////
//  ep_bar_win.v — PCIe EP 的 BAR0 真窗口
//
//  替换厂商 12_pcie_gen2x2 例程里那块 4KB 玩具 RAM（pcie_ep_engine.v 中的
//  `ram u_pcie_rx_eram`）。原因：那块 RAM 写地址按"包内位置"自增、读地址被当成
//  32 字节字索引，且所有 Memory BAR 共享它、超过 4KB 全部回卷 —— 拿它搬图像不可能
//  （APUG081 原文也是这么写的）。
//
//  本模块直接吃引擎的 rx 流水线信号：
//    写：TLP 头 [191:160] = 32bit 地址，[233:224] = 长度(dw)，
//        首个 payload dword = 4DW ? rx_data_ff[127:96] : rx_data_ff[159:128]
//    读：地址同上；完成包第 0 个 dw 必须落在 mrdata_rd_data[127:96]，
//        第 k 个 dw 在 [96+32k +: 32]（一次最多 4 个 dw = 16 字节）
//
//  时序预算（关键，别改）：引擎在 tl_rx_sop_ff 的下一拍（mem_first_cycle）就把
//  mrdata_rd_data 打进完成包，所以：
//    - 地址必须在 rx_sop_ff 那拍锁存，数据下一拍组合给出
//    - 寄存器区用组合 mux；帧缓存用 4 个预取寄存器轮转刷新，保证"预先备好"
//      （fb 读口只有一份，与 DDR 整帧搬运共用，仲裁在 img_frame_src 里；
//       预取只在 host_grant=1 那拍存/前进，见下面预取段的注释）
//
//  寄存器表（BAR0 字节偏移，4 字节对齐）：
//    0x40 MAGIC     R    0x50434946
//    0x44 CTRL      R/W  bit0 enable（总使能）
//                        bit1 trigger（单帧触发，自清；测试图源用）
//                        [3:2] pattern（测试图源图案，原样送顶层 img_pattern；
//                              bit2 在顶层还兼作「传感器重触发」：电平一变 →
//                              XCLR 拉低 134ms → 放开后重写整张 201 条寄存器表）
//                        bit3/bit4 保留（写 0；读回原样）
//                        bit5 ddr_en（1 = 相机每完成一帧自动搬进 DDR3）
//                        bit6 push_en（1 = 每有一帧就用 MWr 主动推给主机）
//                        bit7 push_src（推帧数据源：0 = DDR3 已发布的那一帧，
//                              1 = 片内 ERAM 帧缓存 fb[]，绕开 DDR）
//                        bit8 cam_ab（推帧取哪一路：0 = A 路，1 = B 路）
//    0x48 STATUS    R    bit0 ready, bit1 busy
//    0x4C FRAME_CNT R
//    0x50 WIDTH     R
//    0x54 HEIGHT    R
//    0x58 DATA_LEN  R    每帧字节数
//    0x5C PTR       R/W  帧数据读指针（字节）
//    0x60 DATA      R    返回 PTR 处起的 dw（按请求长度 1~4 个），PTR 自动前进
//    0x64 VERSION   R
//    0x68 CLK_MHZ   R
//    0x6C SCRATCH   R/W 读写回环自检
//    0x70 PF0       R    PTR 处预取的 dw0（肉眼调试用）
//    0x74 LAST_WR   R/W 主机最后写进来的值（读写回环自检）
//    0x78 FB_RADDR  R    主机预取当前给出的帧缓存字节地址
//    0x7C DBG_RD_IDX R   内部读口字索引（低 17 位有效）
//    0x80..0x98     R    相机状态字 cam_stat[31:0]..cam_stat[223:192]（8 个 dw）
//    0x9C CAM_TAP   R/W  {manual_en, tap[5:0]} A 路 IDELAY
//    0xD4 CAM_B_TAP R/W  {manual_en, tap[5:0]} B 路 IDELAY（两路眼图不同，必须分开配）
//    0xD0 CAM_DDR_DIAG   R A 路相机直通诊断 {lines_per_frame[15:0],
//                          max_grp_per_line[15:0]}（借 cam_stat[255:224]，不新增端口）
//    0xD8 CAM_DDR_DIAG_B R B 路同理（cam_diag_b 端口，新寄存器）
//    0xDC CAM_DROP_A     R A 路丢帧诊断 {notack[15:0], stuck[15:0]}（0xF0 给 {bad,last_wcnt}）
//    0xF0 CAM_DROP_A2    R A 路 {last_beats[15:0], last_wcnt[15:0]}
//    0xF4 CAM_DROP_A3    R A 路判定快照（24'd0 + verdict_snap）：
//                          bit0 p_bad / bit1 没见 EOF / bit2 字数不符 / bit3 拍数不符 /
//                          bit4 axi_err / bit5 该帧 pub_ok
//    0xA0 DDR_FRAME_SEQ R A 路：已整帧落 DDR3 的帧号（单调递增）
//    0xA4 DDR_BASE      R A 路：该帧在 DDR3 里的字节基址（双缓冲两块交替）
//    0xA8 DDR_STATUS    R A 路：bit0 valid / bit1 busy / bit2 err / bit3 alive /
//                          bit4 cal_done / [31:16] err_cnt
//    0xAC DDR_LEN       R A 路：每帧字节数
//    0xE0 DDR_FRAME_SEQ_B R B 路四项，位义与 0xA0~0xAC 逐条相同
//    0xE4 DDR_BASE_B      R
//    0xE8 DDR_STATUS_B    R
//    0xEC DDR_LEN_B       R
//  另：CTRL bit5 = ddr_en（1 = 相机每完成一帧自动搬进 DDR3；默认 0，原语义不变）
//    搬运通路本体在 rtl/ep_side/ddr/cam_ddr_writer.v（A/B 各一片），这里只做寄存器面。
//
//  另：CTRL bit6 = push_en（1 = 每有一帧就用 MWr 主动推给主机；默认 0，原语义不变）
//    与下面这组「推帧」寄存器。推帧本体在 rtl/ep_side/ddr/ddr_frame_pusher.v，
//    这里同样只做寄存器面。
//    CTRL bit7 = push_src：【本步新增】推帧的数据源选择。0 = 从 DDR3 里已发布的
//    那一帧读（默认，原语义）；1 = 直接读片内 ERAM 帧缓存（img_frame_src 的
//    fb[]），**完全不碰 DDR 通路** —— 用来先把「EP 主动把整帧写进主机内存」
//    这条 DMA 验通，DDR 未就绪时也能用。fb 读口只有一个，主机预取的仲裁在
//    img_frame_src 里；推帧的 ERAM 源与主机预取按拍分时，互不饿死。
//    0xB0 PUSH_DST_LO   R/W 主机内存目标地址低 32 位（0 且高也为 0 ⇒ 错误码 1、
//                            整帧不发；地址由主机给，EP 侧不写死任何物理地址）
//    0xB4 PUSH_DST_HI   R/W 目标地址高 32 位；帧内地址每发一个 MWr 自动 +128
//    0xB8 PUSH_DB_LO    R/W 门铃地址低 32 位
//    0xBC PUSH_DB_HI    R/W 门铃地址高 32 位（两个都为 0 ⇒ 不发门铃，错误码 4）
//    0xC0 PUSH_DONE     R   已推帧数（每推完一整帧 +1；门铃里写的序号就是它，1 起）
//    0xC4 PUSH_STATUS   R   bit0 busy / bit1 last_ok / bit2 doorbell_sent /
//                            bit3 ddr_alive / bit4 ddr_cal_done / [31:16] 错误累计
//                            （四位以下由 ph1p_pcie_ep_top.v 的 img_push_ro 拼接给出，
//                              顺序必须与这里逐位一致；上一版拼错，曾把已推帧数读成 0）
//    0xC8 PUSH_ERR      R   最近一次错误码：0 正常 / 1 目标地址未配置 /
//                            2 等 tl_tx_wait 超时 / 3 AXI 读响应非 OKAY /
//                            4 门铃地址未配置（数据推了、门铃没发）
//    0xCC PUSH_TLP_CNT  R   最近一帧实际发出的 MWr 数（正常 2400，不含门铃那笔）
//    · 门铃是推完一帧后单独一笔「只写一个 dw」的 MWr（本 EP 没有 MSI/MSI-X，
//      所以除轮询 0xC0 外再给主机一个中断式通知）；写的内容是本帧序号。
//    · 推帧与门铃都是 TC0 的 Posted 写，PCIe 排序规则不允许 Posted 互相超越，
//      所以主机一定先看到帧数据、最后看到门铃。
//    详细约定（TLP 头怎么拼、字节序、出错怎么办）见 ddr_frame_pusher.v 头部。
//
//  ==== T07.rk-align-backend 新增：RKA1 安全扩展窗口 0x100..0x11C + CSI 诊断 0x120..0x12C ====
//  与 contract/registers.json 逐项对应（扩展窗口默认值/reset 都在这里给）：
//    0x100 DMA_CAP_BYTES R/W 主机分配的传输容量（字节）。默认 0；只在 IDLE 可写，
//                             busy/held/draining 期间写会被拒（cfg_reject）。
//    0x104 SESSION_ID    R/W 非零会话号。默认 0；同上只在 IDLE 可写。
//    0x108 TX_CMD        W1  bit0=ARM_ONE_SHOT / bit1=ACK_RELEASE / bit2=CANCEL。
//                             每笔写只能有 1 个 bit 置 1（多 bit / 未知 bit 全拒），
//                             读恒 0。ARM 原子锁存 descriptor；ACK 必须匹配
//                             held(session,seq)；CANCEL 完成后不发成功门铃。
//    0x10C ACK_SEQ       R/W 待匹配的完成序号（门铃里写的那个值）
//    0x110 ACK_SESSION   R/W 待匹配的会话号
//    0x114 TX_STATUS     R   bit0 armed / bit1 busy / bit2 held / bit3 rejected|error
//                             / bit4 draining；其余位 0
//    0x118 EXT_MAGIC     R   0x31414B52（小端 ASCII "RKA1"）；旧 peer 这段读
//                             DEAD_BEEF ⇒ 主机据此判断扩展不存在并 fail closed
//    0x11C EXT_VERSION   R   0x0001_0000（major1.minor0）
//  以上 8 个偏移严格按合同，不再占用 0xD0..0xF4 的旧诊断。
//
//  0x1E0 SYNC_CMD W1：bit0=START，bit1=ABORT。
//  0x1E4..0x20C 同步只读状态：STATUS/SKEW/PAIR_COUNT/WARMUP/TIMESTAMP/
//    MISS_A/MISS_B/OVERRUN/RELOCK/PAIR_SEQ_A/PAIR_SEQ_B。
//
//  额外只读诊断（**不在合同里，属 T07 新增 diag，主机可忽略**）：
//    0x120 CSI_DIAG_A  R {good[7:0], bad[7:0], hdr_err[7:0], crc_err[7:0]}（A 路低 8 位）
//    0x124 CSI_DIAG_A2 R {last_lines[15:0], last_wc[15:0]}（A 路最近帧几何）
//    0x128 CSI_DIAG_B  R B 路同 0x120
//    0x12C CSI_DIAG_B2 R B 路同 0x124
//  这些字全部来自 checked CSI 的字节时钟域，用两级采样后仅作人看诊断（不参与控制），
//  计数器跨域瞬间可能差一拍，属可接受；板上定位坏帧用。
///////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module ep_bar_win #(
    parameter [31:0] MAGIC    = 32'h5043_4946,   // "FICP"
    parameter [31:0] VERSION  = 32'h0002_0000,
    parameter [31:0] PTR_BYTES = 32'h0004_B000,  // 帧缓存字节数；用比较回绕，别用掩码
    parameter [8:0]  CLK_MHZ  = 9'd62,           // tl_clk_user 频率，给主机算带宽
    parameter [31:0] MAGIC_RKA1  = 32'h3141_4B52, // "RKA1" 小端
    parameter [31:0] VERSION_RKA1= 32'h0001_0000, // 扩展接口 major1.minor0
    // T11 debug：仅 debug 顶层 ph1p_pcie_ep_top_dbg 覆盖为 1'b1（依据 run
    //   debug-spec/enable-state.md §2）；生产/00_all 保持默认 0，行为不变
    parameter        DBG_CTRL_DEFAULT_EN = 1'b0
)(
    input  wire         clk,
    input  wire         rst,
    // T11 r3（issue-02）：调试快照专用复位（与 PCIe 链路无关；仅 DBG 门控块使用，生产未用）
    input  wire         dbg_por_rst,

    // 引擎 rx 流水线（同时钟域）
    input  wire         rx_sop_ff,
    input  wire [255:0] rx_data_ff,

    // 完成包数据（回给引擎 TL_TX_ACK_MEMR）
    output wire [255:0] mrdata_rd_data,
    // 完成包 Lower Address 字段（字节地址低 7 位）
    output reg  [6:0]   memrd_addr_lo,
    input  wire [127:0] ddr_ro_b,        // B 路整帧搬运握手字 {len,status,base,seq}（0xEC/0xE8/0xE4/0xE0）
    input  wire [31:0]  cam_diag_b,      // B 路相机直通诊断 {lines_per_frame, max_grp_per_line}（0xD8）
    // 板级调试（T07 收帧卡死定位用，只读、不参与任何数据路径）：
    //   0x170 A 路写者状态 {7'd0, pub 未回执, hdr_ready, s_state[2:0], a_st[2:0]}
    //   0x174 B 路写者状态（同上）
    //   0x178 DDR 写口仲裁 {30'd0, grant, busy_b, busy_a}
    input  wire [8:0]   dbgfsm_cama,
    input  wire [8:0]   dbgfsm_camb,
    input  wire         dbgwr_busya,
    input  wire         dbgwr_busyb,
    input  wire         dbgwr_grant,
    input  wire [95:0]  dbgdrop_b,       // B 路写者丢帧诊断（0x17C/0x180/0x184）
    output reg  [6:0]   cam_tap_cfg,     // A 路 {manual_en, tap[5:0]} 主机可写（0x9C）
    output reg  [6:0]   cam_tap_b_cfg,   // B 路 {manual_en, tap[5:0]} 主机可写（0xD4）
    output wire         cam_ab_sel,      // CTRL[8]：推帧取哪一路（0 = A，默认；1 = B）
    input  wire [95:0]  cam_drop_a,      // A 路直通通路的丢帧诊断（0xDC/0xF0/0xF4）
    // 0x6C SCRATCH 原样送到顶层：本轮当「写者 arm 掩码」用（bit0=A, bit1=B；
    // 0 = 走编译期默认）。只作调试旋钮，不改变 0x6C 的回读值。
    output wire [31:0]  dbg_scratch,
    input  wire [95:0]  cama_stall,      // A 路写者 AXI 停滞（0x188~0x190）
    input  wire [95:0]  camb_stall,      // B 路写者 AXI 停滞（0x194~0x19C）
    input  wire [255:0] dbg_frame_a,     // A 路写者每帧统计（0x1A0~0x1BC）
    input  wire [255:0] dbg_frame_b,     // B 路写者每帧统计（0x1C0~0x1DC）
    // 控制 / 状态（接 img_frame_src）
    output reg          ctrl_enable,
    output reg          ctrl_trigger,
    // ctrl_pattern 端口（= CTRL[3:2] 原样送出，寄存器的读回也是 CTRL 原样）：
    //   bit1 = CTRL[3] 测试图源图案高位
    //   bit0 = CTRL[2] 测试图源图案低位，顶层还拿它当「传感器重触发」用
    //                   （电平一变 → XCLR 拉低 134ms → 重写整张寄存器表）
    output wire [1:0]   ctrl_pattern,
    // DDR3 整帧搬运（CTRL[5] + 只读握手字，字面顺序 {len, status, base, seq}）
    output reg          ctrl_ddr_en,
    input  wire [127:0] ddr_ro,
    // 推帧（CTRL[6]/[7] + 0xB0~0xCC；字面顺序 {tlp_cnt, err, status, done}）
    input  wire [127:0] push_ro,
    output reg          ctrl_push_en,
    output reg          ctrl_push_src,
    output reg          ctrl_pair_en,
    output reg  [31:0]  push_dst_lo,
    output reg  [31:0]  push_dst_hi,
    output reg  [31:0]  push_db_lo,
    output reg  [31:0]  push_db_hi,
    // 双路推帧：B 路目标/门铃/ACK 序号与状态
    output reg  [31:0]  pair_dst_lo,
    output reg  [31:0]  pair_dst_hi,
    output reg  [31:0]  pair_db_lo,
    output reg  [31:0]  pair_db_hi,
    output reg  [31:0]  pair_ack_seq,
    output reg          pair_cmd_arm,
    output reg          pair_cmd_ack,
    output reg          pair_cmd_cancel,
    input  wire [127:0] push_ro_b,
    input  wire [31:0]  pair_status_in,
    input  wire         pair_block_cfg,
    // 与 DDR 搬运共用 fb 唯一读口的握手指（见 img_frame_src 头部仲裁）
    output wire         host_rd_prio,
    input  wire         host_grant,
    input  wire         st_ready,
    input  wire         st_busy,
    input  wire [31:0]  st_frame_cnt,
    input  wire [15:0]  st_width,
    input  wire [15:0]  st_height,
    input  wire [31:0]  st_data_len,

    // 帧缓存读口（接 img_frame_src 的 rd_addr / rd_data）
    output wire [31:0]  fb_raddr,
    input  wire [31:0]  fb_rdata,
    input  wire [31:0]  dbg_rd_idx,
    input  wire [255:0] cam_stat,

    // ==== 端到端延迟时间基准（0x238/0x23C，只读）====
    input  wire [63:0]  ts_now,

    // ==== 硬件同步曝光控制/状态（0x1E0..0x20C）====
    input  wire [351:0] sync_ro,
    output reg          sync_start,
    output reg          sync_abort,

    // ==== T07 新增：RKA1 安全扩展寄存器面（与 ddr_frame_pusher 的安全门直连）====
    output reg  [31:0]  tx_cap_bytes,     // 0x100（暂存，ARM 时由安全门锁存并校验）
    output reg  [31:0]  tx_session_id,    // 0x104（同上）
    output reg          tx_cmd_arm,       // 0x108.bit0 单拍脉冲
    output reg          tx_cmd_ack,       // 0x108.bit1 单拍脉冲
    output reg          tx_cmd_cancel,    // 0x108.bit2 单拍脉冲
    output reg  [31:0]  tx_ack_seq,       // 0x10C
    output reg  [31:0]  tx_ack_session,   // 0x110
    input  wire [31:0]  tx_status_in,     // 0x114（安全门给）
    input  wire         tx_block_cfg,     // 1 = busy/held/draining：活动期配置写被拒
    output reg          cfg_reject,       // 活动期写配置被拒（单拍，安全门据此记错误码 10）
    // CSI 诊断（checked CSI 字节域两级采样后进来，仅人看）
    input  wire [31:0]  csi_diag_a,
    input  wire [31:0]  csi_diag_a2,
    input  wire [31:0]  csi_diag_b,
    input  wire [31:0]  csi_diag_b2
);

    // 引擎的数据字段是“首字节在高位”，而主机按小端读 → 每个 dw 都要翻转字节序
    // 指针规整：4 字节对齐；>= 帧大小就回卷到 0
    function [31:0] ptr_fix;

        input [31:0] v;
        begin
            ptr_fix = (v >= PTR_BYTES) ? 32'd0 : {v[31:2], 2'b00};
        end
    endfunction

    function [31:0] bswap32;
        input [31:0] x;
        begin
            bswap32 = {x[7:0], x[15:8], x[23:16], x[31:24]};
        end
    endfunction

    // ------------------------------------------------------------------
    // TLP 头字段（Fmt=rx_data_ff[255:253]，Type=rx_data_ff[252:248]）
    //   MRD: 000(3DW)/001(4DW)   MWR: 010(3DW)/011(4DW) → Fmt[1]=写, Fmt[0]=4DW
    // ------------------------------------------------------------------
    wire [2:0]  fmt       = rx_data_ff[255:253];
    wire        is_mem    = (rx_data_ff[252:248] == 5'b0_0000);
    wire        is_wr     = fmt[1];
    wire        is_4dw    = fmt[0];
    wire [31:0] tlp_addr  = rx_data_ff[191:160];
    wire [31:0] tlp_dw    = is_4dw ? rx_data_ff[127:96] : rx_data_ff[159:128];
    wire [31:0] tlp_dw_s  = bswap32(tlp_dw);   // 落寄存器/比较都用这个
    wire [10:0] tlp_len   = (|rx_data_ff[233:224]) ? {1'b0, rx_data_ff[233:224]} : 11'd1;

    wire        req_rd    = rx_sop_ff && is_mem && !is_wr;
    wire        req_wr    = rx_sop_ff && is_mem &&  is_wr;
    wire        req_is_data = req_rd && (tlp_addr[11:0] == 12'h60);

    // T07 仿真兼容修正：原 peer 把 rd_addr32/rd_len_dw 的声明放在下面（使用之后），
    // TD 能过、但 ModelSim vlog 报 vlog-2730/2388（隐式网冲突）。声明挪到使用前，
    // 行为完全不变（仅声明位置）。
    reg [31:0] rd_addr32;
    reg [10:0] rd_len_dw;

    wire [11:0] r_idx      = rd_addr32[11:0];
    wire [10:0] rd_dw_cnt  = (rd_len_dw > 11'd4) ? 11'd4 : rd_len_dw;
    wire        rd_is_data = (r_idx == 12'h60);

    // ------------------------------------------------------------------
    // 请求锁存 + 寄存器写入 + 指针前进
    // ------------------------------------------------------------------
    reg        rd_data_go;        // 读 DATA 的单拍脉冲（用于指针前进）
    reg [31:0] ptr;
    reg [31:0] scratch;
    reg [31:0] last_wr;
    reg [1:0]  ctrl_pattern_r;   // CTRL[3:2] 原样保存（读回用）
    reg        ctrl_cam_ab;      // CTRL[8] 推帧取哪一路的已落 DDR 帧（0 = A）

    assign ctrl_pattern = ctrl_pattern_r;   // CTRL[3:2] 原样送出
    // A/B 路选择独立送出去（不塞进 ctrl_pattern：那边 [2:0] 的位义已被顶层与
    // r_mode_hits 诊断用住，塞进去会改变既有语义）
    assign cam_ab_sel = ctrl_cam_ab;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cam_tap_cfg <= 7'b1_101110;   // 默认 manual_en=1, tap=46（A 路）
            cam_tap_b_cfg <= 7'b1_101110; // 默认 manual_en=1, tap=46（B 路）
            rd_addr32     <= 32'd0;
            rd_len_dw     <= 11'd1;
            rd_data_go    <= 1'b0;
            memrd_addr_lo <= 7'd0;
            ctrl_enable   <= DBG_CTRL_DEFAULT_EN;   // T11 debug: 生产=0（原行为）；debug 顶层=1
            ctrl_trigger  <= 1'b0;
            ctrl_pattern_r <= 2'd0;
            ctrl_cam_ab    <= 1'b0;      // 默认 A 路（老主机不写 bit8）
            ctrl_ddr_en    <= DBG_CTRL_DEFAULT_EN;  // T11 debug: 同上（仅 bit0/bit5 两行，其余位保持 0）
            ctrl_push_en   <= 1'b0;      // 默认不推帧（保持原行为）
            ctrl_push_src  <= 1'b0;      // 默认推帧数据源取 DDR3（保持原行为）
            push_dst_lo    <= 32'd0;
            push_dst_hi    <= 32'd0;
            push_db_lo     <= 32'd0;
            push_db_hi     <= 32'd0;
            pair_dst_lo    <= 32'd0;
            pair_dst_hi    <= 32'd0;
            pair_db_lo     <= 32'd0;
            pair_db_hi     <= 32'd0;
            pair_ack_seq   <= 32'd0;
            pair_cmd_arm   <= 1'b0;
            pair_cmd_ack   <= 1'b0;
            pair_cmd_cancel<= 1'b0;
            ctrl_pair_en   <= 1'b0;
            tx_cap_bytes   <= 32'd0;      // 默认 cap=0（不授权）
            tx_session_id  <= 32'd0;      // 默认 session=0（不授权）
            tx_cmd_arm     <= 1'b0;
            tx_cmd_ack     <= 1'b0;
            tx_cmd_cancel  <= 1'b0;
            tx_ack_seq     <= 32'd0;
            tx_ack_session <= 32'd0;
            cfg_reject     <= 1'b0;
            sync_start     <= 1'b0;
            sync_abort     <= 1'b0;
            ptr           <= 32'd0;
            scratch       <= 32'd0;
            last_wr       <= 32'd0;
        end else begin
            rd_data_go <= 1'b0;
            tx_cmd_arm <= 1'b0;
            tx_cmd_ack <= 1'b0;
            tx_cmd_cancel <= 1'b0;
            pair_cmd_arm  <= 1'b0;
            pair_cmd_ack  <= 1'b0;
            pair_cmd_cancel <= 1'b0;
            cfg_reject <= 1'b0;
            sync_start <= 1'b0;
            sync_abort <= 1'b0;

            if (req_rd) begin
                rd_addr32     <= tlp_addr;
                memrd_addr_lo <= tlp_addr[6:0];
                rd_len_dw     <= tlp_len;
                rd_data_go    <= req_is_data;          // 下一拍有效（与完成包取样同拍）
            end

            if (req_wr) begin
                case (tlp_addr[11:0])
                    12'h44: begin
                        ctrl_enable  <= tlp_dw_s[0];
                        ctrl_trigger <= tlp_dw_s[1];     // 下一拍自动清 → 单帧脉冲
                        ctrl_pattern_r <= tlp_dw_s[3:2];
                        ctrl_cam_ab    <= tlp_dw_s[8];   // 1 = B 路（0 = A 路，默认）
                        ctrl_ddr_en    <= tlp_dw_s[5];   // 1 = 每完成一帧自动搬进 DDR3
                        ctrl_push_en   <= tlp_dw_s[6];   // 1 = 每有一帧就推给主机
                        ctrl_push_src  <= tlp_dw_s[7];   // 1 = 推帧数据源取片内 ERAM 帧缓存
                        ctrl_pair_en   <= tlp_dw_s[9];   // 1 = A/B 双路同时推帧
                    end
                    12'h5C: ptr     <= ptr_fix(tlp_dw_s);
                    12'h9C: cam_tap_cfg   <= tlp_dw_s[6:0];   // A 路 tap
                    12'hD4: cam_tap_b_cfg <= tlp_dw_s[6:0];   // B 路 tap
                    12'hB0: push_dst_lo <= tlp_dw_s;
                    12'hB4: push_dst_hi <= tlp_dw_s;
                    12'hB8: push_db_lo  <= tlp_dw_s;
                    12'hBC: push_db_hi  <= tlp_dw_s;
                    // ---- 双路推帧 B 路目标/门铃/ACK 序号 ----
                    12'h220: pair_ack_seq <= tlp_dw_s;
                    12'h224: pair_dst_lo  <= tlp_dw_s;
                    12'h228: pair_dst_hi  <= tlp_dw_s;
                    12'h22C: pair_db_lo   <= tlp_dw_s;
                    12'h230: pair_db_hi   <= tlp_dw_s;
                    12'h6C: scratch <= tlp_dw_s;
                    12'h74: last_wr <= tlp_dw_s;
                    // ---- RKA1 安全扩展（0x100..0x11C）----
                    // 活动配置（cap/session）只在 IDLE 可写；busy/held/draining
                    // 期间的写被拒并置 cfg_reject（安全门记错误码 10）。
                    12'h100: begin
                        if (tx_block_cfg || pair_block_cfg) cfg_reject <= 1'b1;
                        else                                tx_cap_bytes <= tlp_dw_s;
                    end
                    12'h104: begin
                        if (tx_block_cfg || pair_block_cfg) cfg_reject <= 1'b1;
                        else                                tx_session_id <= tlp_dw_s;
                    end
                    // TX_CMD：每笔写必须恰好一个 bit 置位（W1，读恒 0）
                    12'h108: begin
                        case (tlp_dw_s)
                            32'd1:  tx_cmd_arm     <= 1'b1;
                            32'd2:  tx_cmd_ack     <= 1'b1;
                            32'd4:  tx_cmd_cancel  <= 1'b1;
                            32'd8:  pair_cmd_arm   <= 1'b1;
                            32'd16: pair_cmd_ack   <= 1'b1;
                            32'd32: pair_cmd_cancel<= 1'b1;
                            default: cfg_reject    <= 1'b1; // 0/多 bit 或未知 bit：拒绝
                        endcase
                    end
                    12'h10C: tx_ack_seq     <= tlp_dw_s;
                    12'h110: tx_ack_session <= tlp_dw_s;
                    // 同步控制：W1，单 bit；start/abort 只产生 1 拍脉冲
                    12'h1E0: begin
                        if (tlp_dw_s == 32'h1) sync_start <= 1'b1;
                        else if (tlp_dw_s == 32'h2) sync_abort <= 1'b1;
                        else cfg_reject <= 1'b1;
                    end
                    default: ;
                endcase
            end else begin
                ctrl_trigger <= 1'b0;
            end

            // 读 DATA：按请求长度前进指针（限 4 个 dw）
            if (rd_data_go) begin
                case (rd_dw_cnt)
                    11'd1:   ptr <= ptr_fix(ptr + 32'd4);
                    11'd2:   ptr <= ptr_fix(ptr + 32'd8);
                    11'd3:   ptr <= ptr_fix(ptr + 32'd12);
                    default: ptr <= ptr_fix(ptr + 32'd16);
                endcase
            end
        end
    end

    // ------------------------------------------------------------------
    // 帧缓存预取：4 个 dw 轮转刷新（4 拍一轮，主机访问间隔远大于此）
    //
    //  与 DDR 整帧搬运共用 fb 的***唯一***读口（仲裁在 img_frame_src，见那里头部）：
    //    · host_grant = 1 的那拍读口是我们的 → 下一拍数据也是我们的，
    //      按 pf_sel 回退一格存、pf_sel 前进；
    //    · host_grant = 0（DMA 借走）→ 那拍不存、pf_sel 也不前进
    //      （否则会把 DMA 地址上的数据存进 pf，并且 pf_sel 与实际地址错位）。
    //    · DMA 空闲时 host_grant 恒 1 ⇒ 行为与加仲裁之前完全一样。
    //
    //  host_rd_prio = 「预取寄存器已经不是 ptr..ptr+12 了，读口必须还给我」：
    //    ptr 一变（一次 0x60 读、一次 0x5C 写）就置 1；之后连续拿到 6 拍读口
    //    才清 0（四个字只需 4 拍，多 2 拍是把「地址→数据 1 拍」两级流水算进去，
    //    保证数据真的都到寄存器里了才放手）。原来 ptr 变后自由跑 4 拍刷完，
    //    主机只需间隔 ≥5 拍；这里给的是 ≥6 拍，只强不弱。
    //    复位后先置 1，保证第一拍就刷齐，不依赖复位前的相位。
    // ------------------------------------------------------------------
    reg [31:0] pf0, pf1, pf2, pf3;
    reg [1:0]  pf_sel;
    reg        host_grant_q;      // 上一拍读口是否归我们（fb_rdata 与地址差 1 拍）
    reg        pf_dirty;
    reg [2:0]  pf_cnt;            // 脏状态下已经拿到几拍读口

    assign fb_raddr     = ptr + {30'd0, pf_sel, 2'b00};
    assign host_rd_prio = pf_dirty;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pf0 <= 32'd0; pf1 <= 32'd0; pf2 <= 32'd0; pf3 <= 32'd0;
            pf_sel       <= 2'd0;
            host_grant_q <= 1'b0;
            pf_dirty     <= 1'b1;
            pf_cnt       <= 3'd0;
        end else begin
            host_grant_q <= host_grant;

            // 脏计数器：ptr 变了重新计；连续拿到 6 拍读口（四字刷齐 + 2 拍流水）才放手
            if (rd_data_go || (req_wr && (tlp_addr[11:0] == 12'h5C))) begin
                pf_dirty <= 1'b1;
                pf_cnt   <= 3'd0;
            end else if (pf_dirty && host_grant) begin
                pf_cnt <= pf_cnt + 3'd1;
                if (pf_cnt == 3'd5) pf_dirty <= 1'b0;
            end

            // fb_rdata 是“上一拍地址”的数据（且那一拍读口得是我们的）
            if (host_grant_q) begin
                case (pf_sel)
                    2'd1: pf0 <= fb_rdata;   // 上一拍地址 = ptr+0
                    2'd2: pf1 <= fb_rdata;   // ptr+4
                    2'd3: pf2 <= fb_rdata;   // ptr+8
                    2'd0: pf3 <= fb_rdata;   // ptr+12
                endcase
                pf_sel <= pf_sel + 2'd1;
            end
        end
    end

    // ------------------------------------------------------------------
    // T11 debug 字库 dbg_bank：A 组 9 字只读组合镜像（288 bit，word0..word8）
    //   · 无副作用：纯 wire 组合映像，不驱动任何控制/总线/外发路径；
    //   · 供 ChipWatcher 探针（单实例、tl_clk_user 域）；字序冻结见 run
    //     debug-spec/probe-map.md §2（word0..word8 ↔ 0x040/0x118/0x11C/0x0A0/
    //     0x0A4/0x0AC/0x120/0x124/0x044）；读 mux 新增 0x140..0x160（见下），
    //     不改任何既有偏移读值（default 保持 32'hDEAD_BEEF）。
    // ------------------------------------------------------------------
    wire [31:0] dbg_bank_word0 = MAGIC;                 // 0x040 MAGIC
    wire [31:0] dbg_bank_word1 = MAGIC_RKA1;            // 0x118 EXT_MAGIC
    wire [31:0] dbg_bank_word2 = VERSION_RKA1;          // 0x11C EXT_VERSION
    wire [31:0] dbg_bank_word3 = ddr_ro[31:0];          // 0x0A0 DDR_SEQ_A
    wire [31:0] dbg_bank_word4 = ddr_ro[63:32];         // 0x0A4 DDR_BASE_A
    wire [31:0] dbg_bank_word5 = ddr_ro[127:96];        // 0x0AC DDR_LEN_A
    wire [31:0] dbg_bank_word6 = csi_diag_a;            // 0x120 CSI_DIAG_A
    wire [31:0] dbg_bank_word7 = csi_diag_a2;           // 0x124 CSI_DIAG_A2
    wire [31:0] dbg_bank_word8 =                        // 0x044 CTRL 读回字（位序与 0x44 逐位一致）
        {23'd0, ctrl_cam_ab, ctrl_push_src, ctrl_push_en, ctrl_ddr_en,
         1'b0, ctrl_pattern_r, ctrl_trigger, ctrl_enable};
    wire [287:0] dbg_bank = {dbg_bank_word8, dbg_bank_word7, dbg_bank_word6,
                             dbg_bank_word5, dbg_bank_word4, dbg_bank_word3,
                             dbg_bank_word2, dbg_bank_word1, dbg_bank_word0};

    // ------------------------------------------------------------------
    // T11 P1-fix：ChipWatcher 探针（TD 真实流程：RTL MARK_DEBUG → 流程
    //   insert_debugger 自动建实例 → setup_debugger 产 cw/compiled.cwc|bit）
    //   · 仅当 DBG_CTRL_DEFAULT_EN=1（只由 debug 顶层 ph1p_pcie_ep_top_dbg 覆盖）
    //     → 生产/00_all 参数=0，generate 关闭，生产网表与行为不受影响；
    //   · 打一拍寄存：保证是可综合、不可折叠的真实触发器（MAGIC 等常量字也保留）；
    //     值为字库字 1 拍快照——稳定量逐位相等；计数类最多滞后 1 拍，按跨时刻记录；
    //   · 9 个 32 bit = 288 bit，全部在 tl_clk_user（clk）域，单实例。
    // ------------------------------------------------------------------
    generate
        if (DBG_CTRL_DEFAULT_EN) begin : g_dbg_mark
            (* MARK_DEBUG="true" *) reg [31:0] dbg_mark_word0;
            (* MARK_DEBUG="true" *) reg [31:0] dbg_mark_word1;
            (* MARK_DEBUG="true" *) reg [31:0] dbg_mark_word2;
            (* MARK_DEBUG="true" *) reg [31:0] dbg_mark_word3;
            (* MARK_DEBUG="true" *) reg [31:0] dbg_mark_word4;
            (* MARK_DEBUG="true" *) reg [31:0] dbg_mark_word5;
            (* MARK_DEBUG="true" *) reg [31:0] dbg_mark_word6;
            (* MARK_DEBUG="true" *) reg [31:0] dbg_mark_word7;
            (* MARK_DEBUG="true" *) reg [31:0] dbg_mark_word8;

            // T11 r3（issue-02）：快照复位与 PCIe 链路解耦——dbg_por_rst（板级 POR / PLL 未锁）
            //   异步置位、本域同步释放；tl_rst_user 在无主机时恒有效，不能用于本块。
            //   快照时钟仍为 clk=tl_clk_user（CWC 采样时钟=同一 tl_clk_user 网络，H2 显式一致）。
            reg [1:0] dbg_por_sync;
            always @(posedge clk or posedge dbg_por_rst) begin
                if (dbg_por_rst) dbg_por_sync <= 2'b11;
                else             dbg_por_sync <= {dbg_por_sync[0], 1'b0};
            end
            wire dbg_snap_rst = dbg_por_sync[1];

            always @(posedge clk or posedge dbg_snap_rst) begin
                if (dbg_snap_rst) begin
                    dbg_mark_word0 <= 32'd0;
                    dbg_mark_word1 <= 32'd0;
                    dbg_mark_word2 <= 32'd0;
                    dbg_mark_word3 <= 32'd0;
                    dbg_mark_word4 <= 32'd0;
                    dbg_mark_word5 <= 32'd0;
                    dbg_mark_word6 <= 32'd0;
                    dbg_mark_word7 <= 32'd0;
                    dbg_mark_word8 <= 32'd0;
                end else begin
                    dbg_mark_word0 <= dbg_bank_word0;
                    dbg_mark_word1 <= dbg_bank_word1;
                    dbg_mark_word2 <= dbg_bank_word2;
                    dbg_mark_word3 <= dbg_bank_word3;
                    dbg_mark_word4 <= dbg_bank_word4;
                    dbg_mark_word5 <= dbg_bank_word5;
                    dbg_mark_word6 <= dbg_bank_word6;
                    dbg_mark_word7 <= dbg_bank_word7;
                    dbg_mark_word8 <= dbg_bank_word8;
                end
            end
        end
    endgenerate

    // ------------------------------------------------------------------
    // 读数据组装（组合）
    // ------------------------------------------------------------------

    reg [31:0] rd_dw_comb;
    always @(*) begin
        case (r_idx)
            12'h40:  rd_dw_comb = MAGIC;
            // 位序必须逐位对上 CTRL：bit0 enable / bit1 trigger / [3:2] pattern /
            //   bit4 保留（写 0 读 0）/ bit5 ddr_en / bit6 push_en / bit7 push_src /
            //   bit8 cam_ab —— 中间那个保留位不能省，少一位整段就整体错位。
            12'h44:  rd_dw_comb = {23'd0, ctrl_cam_ab, ctrl_push_src, ctrl_push_en, ctrl_ddr_en,
                                    1'b0, ctrl_pattern_r, ctrl_trigger, ctrl_enable};
            12'h48:  rd_dw_comb = {30'd0, st_busy, st_ready};
            12'h4C:  rd_dw_comb = st_frame_cnt;
            12'h50:  rd_dw_comb = {16'd0, st_width};
            12'h54:  rd_dw_comb = {16'd0, st_height};
            12'h58:  rd_dw_comb = st_data_len;
            12'h5C:  rd_dw_comb = ptr;
            12'h60:  rd_dw_comb = pf0;
            12'h64:  rd_dw_comb = VERSION;
            12'h68:  rd_dw_comb = {23'd0, CLK_MHZ};
            12'h6C:  rd_dw_comb = scratch;
            12'h70:  rd_dw_comb = pf0;
            12'h74:  rd_dw_comb = last_wr;
            12'h78:  rd_dw_comb = fb_raddr;
            12'h7C:  rd_dw_comb = dbg_rd_idx;
            12'h80:  rd_dw_comb = cam_stat[31:0];
            12'h84:  rd_dw_comb = cam_stat[63:32];
            12'h88:  rd_dw_comb = cam_stat[95:64];
            12'h8C:  rd_dw_comb = cam_stat[127:96];
            12'h90:  rd_dw_comb = cam_stat[159:128];
            12'h94:  rd_dw_comb = cam_stat[191:160];
            12'h98:  rd_dw_comb = cam_stat[223:192];
            12'h9C:  rd_dw_comb = {25'd0, cam_tap_cfg};   // 读回 A 路 tap 配置
            12'hD4:  rd_dw_comb = {25'd0, cam_tap_b_cfg}; // 读回 B 路 tap 配置
            12'hD8:  rd_dw_comb = cam_diag_b;            // CAM_DDR_DIAG_B
            // A 路丢帧诊断：0xDC={notack[15:0], stuck[15:0]}，0xF0={bad[15:0], last_wcnt[15:0]}
            12'hDC:  rd_dw_comb = cam_drop_a[31:0];       // CAM_DROP_A
            12'hF0:  rd_dw_comb = cam_drop_a[63:32];      // CAM_DROP_A2
            12'hF4:  rd_dw_comb = cam_drop_a[95:64];      // CAM_DROP_A3 = {24'd0, verdict_snap}
            12'hE0:  rd_dw_comb = ddr_ro_b[31:0];        // DDR_FRAME_SEQ_B
            12'hE4:  rd_dw_comb = ddr_ro_b[63:32];       // DDR_BASE_B
            12'hE8:  rd_dw_comb = ddr_ro_b[95:64];       // DDR_STATUS_B
            12'hEC:  rd_dw_comb = ddr_ro_b[127:96];      // DDR_LEN_B
            // 相机 4K 直通通路的诊断字（cam_ddr_writer 的 dbg_*）：借 cam_stat 的
            // [255:224] 那一段（read 路径上方 8 个 dw 只用到 [223:0]，这段原来是 0）。
            //   [15:0]  = max_grp_per_line：一行最多收到几个组（裁剪前数）→ 量真实行宽
            //   [31:16] = lines_per_frame ：一帧多少行（含 embedded/哑行）→ 量真实帧高
            12'hD0:  rd_dw_comb = cam_stat[255:224];      // CAM_DDR_DIAG
            // 整帧搬运握手（cam_ddr_writer，见 rtl/ep_side/ddr/）
            12'hA0:  rd_dw_comb = ddr_ro[31:0];           // DDR_FRAME_SEQ
            12'hA4:  rd_dw_comb = ddr_ro[63:32];          // DDR_BASE
            12'hA8:  rd_dw_comb = ddr_ro[95:64];          // DDR_STATUS
            12'hAC:  rd_dw_comb = ddr_ro[127:96];         // DDR_LEN
            // 推帧（ddr_frame_pusher，见 rtl/ep_side/ddr/）
            12'hB0:  rd_dw_comb = push_dst_lo;            // PUSH_DST_LO
            12'hB4:  rd_dw_comb = push_dst_hi;            // PUSH_DST_HI
            12'hB8:  rd_dw_comb = push_db_lo;             // PUSH_DB_LO
            12'hBC:  rd_dw_comb = push_db_hi;             // PUSH_DB_HI
            12'hC0:  rd_dw_comb = push_ro[31:0];          // PUSH_DONE（已推帧数）
            12'hC4:  rd_dw_comb = push_ro[63:32];         // PUSH_STATUS
            12'hC8:  rd_dw_comb = push_ro[95:64];         // PUSH_ERR
            12'hCC:  rd_dw_comb = push_ro[127:96];        // PUSH_TLP_CNT
            // ---- RKA1 安全扩展（0x100..0x11C）----
            12'h100: rd_dw_comb = tx_cap_bytes;           // DMA_CAP_BYTES
            12'h104: rd_dw_comb = tx_session_id;          // SESSION_ID
            12'h108: rd_dw_comb = 32'd0;                  // TX_CMD（W1，读恒 0）
            12'h10C: rd_dw_comb = tx_ack_seq;             // ACK_SEQ
            12'h110: rd_dw_comb = tx_ack_session;         // ACK_SESSION
            12'h114: rd_dw_comb = tx_status_in;           // TX_STATUS
            12'h118: rd_dw_comb = MAGIC_RKA1;             // EXT_MAGIC = "RKA1"
            12'h11C: rd_dw_comb = VERSION_RKA1;           // EXT_VERSION
            // ---- T07 附加只读诊断（可忽略）----
            12'h120: rd_dw_comb = csi_diag_a;             // CSI_DIAG_A
            12'h124: rd_dw_comb = csi_diag_a2;            // CSI_DIAG_A2
            12'h128: rd_dw_comb = csi_diag_b;             // CSI_DIAG_B
            12'h12C: rd_dw_comb = csi_diag_b2;            // CSI_DIAG_B2
            // ---- T11 debug 字库读回（0x140..0x160，只读镜像，字序见上）----
            12'h140: rd_dw_comb = dbg_bank_word0;
            12'h144: rd_dw_comb = dbg_bank_word1;
            12'h148: rd_dw_comb = dbg_bank_word2;
            12'h14C: rd_dw_comb = dbg_bank_word3;
            12'h150: rd_dw_comb = dbg_bank_word4;
            12'h154: rd_dw_comb = dbg_bank_word5;
            12'h158: rd_dw_comb = dbg_bank_word6;
            12'h15C: rd_dw_comb = dbg_bank_word7;
            12'h160: rd_dw_comb = dbg_bank_word8;
            // ---- 硬件同步曝光（0x1E0..0x20C）----
            12'h1E0: rd_dw_comb = 32'd0;                  // SYNC_CMD（W1，读恒 0）
            12'h1E4: rd_dw_comb = sync_ro[31:0];           // SYNC_STATUS
            12'h1E8: rd_dw_comb = sync_ro[63:32];          // SYNC_SKEW（signed）
            12'h1EC: rd_dw_comb = sync_ro[95:64];          // SYNC_PAIR_COUNT
            12'h1F0: rd_dw_comb = sync_ro[127:96];         // SYNC_WARMUP
            12'h1F4: rd_dw_comb = sync_ro[159:128];        // SYNC_TIMESTAMP
            12'h1F8: rd_dw_comb = sync_ro[191:160];        // SYNC_MISS_A
            12'h1FC: rd_dw_comb = sync_ro[223:192];        // SYNC_MISS_B
            12'h200: rd_dw_comb = sync_ro[255:224];        // SYNC_OVERRUN {B,A}
            12'h204: rd_dw_comb = sync_ro[287:256];        // SYNC_RELOCK
            12'h208: rd_dw_comb = sync_ro[319:288];        // SYNC_PAIR_SEQ_A
            12'h20C: rd_dw_comb = sync_ro[351:320];        // SYNC_PAIR_SEQ_B
            // ---- 双路推帧：B 路状态 + pair 配置（0x210..0x234）----
            12'h210: rd_dw_comb = push_ro_b[31:0];          // PUSH_DONE_B
            12'h214: rd_dw_comb = push_ro_b[63:32];         // PUSH_STATUS_B
            12'h218: rd_dw_comb = push_ro_b[95:64];         // PUSH_ERR_B
            12'h21C: rd_dw_comb = push_ro_b[127:96];        // PUSH_TLP_B
            12'h220: rd_dw_comb = pair_ack_seq;             // PAIR_ACK_SEQ_B
            12'h224: rd_dw_comb = pair_dst_lo;              // PAIR_DST_LO_B
            12'h228: rd_dw_comb = pair_dst_hi;              // PAIR_DST_HI_B
            12'h22C: rd_dw_comb = pair_db_lo;               // PAIR_DB_LO_B
            12'h230: rd_dw_comb = pair_db_hi;               // PAIR_DB_HI_B
            12'h234: rd_dw_comb = pair_status_in;           // PAIR_STATUS
            12'h238: rd_dw_comb = ts_now[31:0];             // TS_NOW_LO（clk_ddr 100MHz 自由计数）
            12'h23C: rd_dw_comb = ts_now[63:32];            // TS_NOW_HI
            // ---- 板级调试：收帧写者卡死定位（0x170..0x178，只读，非合同寄存器）----
            12'h170: rd_dw_comb = {23'd0, dbgfsm_cama};
            12'h174: rd_dw_comb = {23'd0, dbgfsm_camb};
            12'h178: rd_dw_comb = {29'd0, dbgwr_grant, dbgwr_busyb, dbgwr_busya};
            12'h17C: rd_dw_comb = dbgdrop_b[31:0];    // {notack[15:0], stuck[15:0]}
            12'h180: rd_dw_comb = dbgdrop_b[63:32];   // {bad[15:0], last_wcnt[15:0]}
            12'h184: rd_dw_comb = dbgdrop_b[95:64];   // {24'd0, verdict_snap}
            // 写者 AXI 阶段最长连续停滞（clk_ddr 拍）+ 突发完成/收口超时次数
            12'h188: rd_dw_comb = cama_stall[31:0];    // A {w_max[15:0], b_max[15:0]}
            12'h18C: rd_dw_comb = cama_stall[63:32];   // A {aw_max[15:0], rwd_max[15:0]}
            12'h190: rd_dw_comb = cama_stall[95:64];   // A {16'd0, rwd_tmo[7:0], burst_done[7:0]}
            12'h194: rd_dw_comb = camb_stall[31:0];    // B 同上
            12'h198: rd_dw_comb = camb_stall[63:32];
            12'h19C: rd_dw_comb = camb_stall[95:64];
            // 每帧统计（帧收口时锁存，只读）：
            //   0x1A0 相机侧入队组数 / 0x1A4 因满丢组数 / 0x1A8 {lines,y} /
            //   0x1AC {16'd0,max_grp} / 0x1B0 因满丢标记数 / 0x1B4 打包占用周期数 /
            //   0x1B8 收口 gcnt / 0x1BC {tmo,p_bad,p_eof,eof_bad}
            12'h1A0: rd_dw_comb = dbg_frame_a[31:0];
            12'h1A4: rd_dw_comb = dbg_frame_a[63:32];
            12'h1A8: rd_dw_comb = dbg_frame_a[95:64];
            12'h1AC: rd_dw_comb = dbg_frame_a[127:96];
            12'h1B0: rd_dw_comb = dbg_frame_a[159:128];
            12'h1B4: rd_dw_comb = dbg_frame_a[191:160];
            12'h1B8: rd_dw_comb = dbg_frame_a[223:192];
            12'h1BC: rd_dw_comb = dbg_frame_a[255:224];
            12'h1C0: rd_dw_comb = dbg_frame_b[31:0];
            12'h1C4: rd_dw_comb = dbg_frame_b[63:32];
            12'h1C8: rd_dw_comb = dbg_frame_b[95:64];
            12'h1CC: rd_dw_comb = dbg_frame_b[127:96];
            12'h1D0: rd_dw_comb = dbg_frame_b[159:128];
            12'h1D4: rd_dw_comb = dbg_frame_b[191:160];
            12'h1D8: rd_dw_comb = dbg_frame_b[223:192];
            12'h1DC: rd_dw_comb = dbg_frame_b[255:224];
            default: rd_dw_comb = 32'hDEAD_BEEF;
        endcase
    end

    // 完成包载荷布局（实测）：第 0 个 dw 在 [255:224]，之后依次向下
    wire [31:0] p_dw0 = bswap32(rd_is_data ? pf0 : rd_dw_comb);
    wire [31:0] p_dw1 = bswap32(rd_is_data ? pf1 : 32'd0);
    wire [31:0] p_dw2 = bswap32(rd_is_data ? pf2 : 32'd0);
    wire [31:0] p_dw3 = bswap32(rd_is_data ? pf3 : 32'd0);

    assign mrdata_rd_data = {p_dw0, p_dw1, p_dw2, p_dw3, 128'd0};

    // 0x6C SCRATCH 直出（调试 arm 掩码用）
    assign dbg_scratch = scratch;

endmodule