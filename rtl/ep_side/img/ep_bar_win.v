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
//    0x44 CTRL      R/W  bit0 enable, bit1 trigger, [3:2] pattern,
//                        bit4 cam_sel = 写源选择（1=相机 cam_fb_writer，0=测试图源；
//                        默认 0，原语义不变）
//                        ※ bit4 要送到顶层，但 pcie_ep_engine.v 的端口不许改，
//                          只好借 ctrl_pattern[1] 这个本来没人消费的通道带着走：
//                          端口 ctrl_pattern = {cam_sel, mclk_sel}；
//                          寄存器读回仍然是 bit4=cam_sel、[3:2]=pattern 原值。
//                        bit2 在顶层被当成“传感器 MCLK 源选择”用（ctrl_pattern[0]，
//                        见 ph1p_pcie_ep_top.v 相机段）：0 = 62.5MHz→12.5MHz 旧分频器
//                        （默认，实测能锁），1 = sys_clk(50MHz)÷4 = 12.5MHz 干净。
//                        bit3（pattern[1]）仍然无人消费。
//                        bit5 ddr_en（见下）、bit6 push_en（见下）、
//                        bit7 push_src = 推帧数据源：0 = DDR3（默认），
//                        1 = 片内 ERAM 帧缓存（绕开 DDR 直接推给主机）
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
//    0x9C CAM_TAP   R/W  {manual_en, tap[5:0]}（不是 cam_stat[255:224]）
//    0xA0 DDR_FRAME_SEQ R 已整帧落 DDR3 的帧号（单调递增；= DDR 里该帧字 0 的帧号）
//    0xA4 DDR_BASE      R 该帧在 DDR3 里的字节基址（双缓冲两块交替）
//    0xA8 DDR_STATUS    R bit0 valid / bit1 busy / bit2 err / bit3 alive /
//                          bit4 cal_done / [31:16] err_cnt
//    0xAC DDR_LEN       R 每帧字节数（= 0x58 DATA_LEN）
//  另：CTRL bit5 = ddr_en（1 = 每完成一帧自动搬进 DDR3；默认 0，原语义不变）
//    搬运通路本体在 rtl/ep_side/ddr/ddr_frame_writer.v，这里只做寄存器面。
//
//  另：CTRL bit6 = push_en（1 = 每有一帧就用 MWr 主动推给主机；默认 0，原语义不变）
//    与下面这组「推帧」寄存器。推帧本体在 rtl/ep_side/ddr/ddr_frame_pusher.v，
//    这里同样只做寄存器面。
//    CTRL bit7 = push_src：【本步新增】推帧的数据源选择。0 = 从 DDR3 里已发布的
//    那一帧读（默认，原语义）；1 = 直接读片内 ERAM 帧缓存（img_frame_src 的
//    fb[]），**完全不碰 DDR 通路** —— 用来先把「EP 主动把整帧写进主机内存」
//    这条 DMA 验通，DDR 未就绪时也能用。两条路共用 fb 的唯一读口，仲裁在顶层：
//    push_src=1 且推帧在跑时读口归推帧引擎，DDR 搬运那一帧会被挤（会记 err_cnt）。
//    所以两者不要同时开：验 ERAM 路时把 bit5（ddr_en）留 0。
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
///////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module ep_bar_win #(
    parameter [31:0] MAGIC    = 32'h5043_4946,   // "FICP"
    parameter [31:0] VERSION  = 32'h0002_0000,
    parameter [31:0] PTR_BYTES = 32'h0004_B000,  // 帧缓存字节数（640x480）；用比较回绕，别用掩码
    parameter [8:0]  CLK_MHZ  = 9'd62            // tl_clk_user 频率，给主机算带宽
)(
    input  wire         clk,
    input  wire         rst,

    // 引擎 rx 流水线（同时钟域）
    input  wire         rx_sop_ff,
    input  wire [255:0] rx_data_ff,

    // 完成包数据（回给引擎 TL_TX_ACK_MEMR）
    output wire [255:0] mrdata_rd_data,
    // 完成包 Lower Address 字段（字节地址低 7 位）
    output reg  [6:0]   memrd_addr_lo,
    output reg  [6:0]   cam_tap_cfg,     // {manual_en, tap[5:0]} 主机可写
    // 控制 / 状态（接 img_frame_src）
    output reg          ctrl_enable,
    output reg          ctrl_trigger,
    // ctrl_pattern 端口：bit1 = CTRL[4] 相机写源选择（借道），bit0 = 原 pattern[0]
    output wire [1:0]   ctrl_pattern,
    // DDR3 整帧搬运（CTRL[5] + 只读握手字，字面顺序 {len, status, base, seq}）
    output reg          ctrl_ddr_en,
    input  wire [127:0] ddr_ro,
    // 推帧（CTRL[6]/[7] + 0xB0~0xCC；字面顺序 {tlp_cnt, err, status, done}）
    input  wire [127:0] push_ro,
    output reg          ctrl_push_en,
    output reg          ctrl_push_src,
    output reg  [31:0]  push_dst_lo,
    output reg  [31:0]  push_dst_hi,
    output reg  [31:0]  push_db_lo,
    output reg  [31:0]  push_db_hi,
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
    input  wire [255:0] cam_stat
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

    wire [11:0] r_idx      = rd_addr32[11:0];
    wire [10:0] rd_dw_cnt  = (rd_len_dw > 11'd4) ? 11'd4 : rd_len_dw;
    wire        rd_is_data = (r_idx == 12'h60);

    // ------------------------------------------------------------------
    // 请求锁存 + 寄存器写入 + 指针前进
    // ------------------------------------------------------------------
    reg [31:0] rd_addr32;
    reg [10:0] rd_len_dw;
    reg        rd_data_go;        // 读 DATA 的单拍脉冲（用于指针前进）
    reg [31:0] ptr;
    reg [31:0] scratch;
    reg [31:0] last_wr;
    reg [1:0]  ctrl_pattern_r;   // CTRL[3:2] 原样保存（读回用）
    reg        ctrl_cam_sel;     // CTRL[4] 相机写源选择

    assign ctrl_pattern = {ctrl_cam_sel, ctrl_pattern_r[0]};

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cam_tap_cfg <= 7'b1_101110;   // 默认 manual_en=1, tap=46
            rd_addr32     <= 32'd0;
            rd_len_dw     <= 11'd1;
            rd_data_go    <= 1'b0;
            memrd_addr_lo <= 7'd0;
            ctrl_enable   <= 1'b0;
            ctrl_trigger  <= 1'b0;
            ctrl_pattern_r <= 2'd0;
            ctrl_cam_sel   <= 1'b0;      // 默认走测试图源（向后兼容）
            ctrl_ddr_en    <= 1'b0;      // 默认不往 DDR3 搬（保持原行为）
            ctrl_push_en   <= 1'b0;      // 默认不推帧（保持原行为）
            ctrl_push_src  <= 1'b0;      // 默认推帧数据源取 DDR3（保持原行为）
            push_dst_lo    <= 32'd0;
            push_dst_hi    <= 32'd0;
            push_db_lo     <= 32'd0;
            push_db_hi     <= 32'd0;
            ptr           <= 32'd0;
            scratch       <= 32'd0;
            last_wr       <= 32'd0;
        end else begin
            rd_data_go <= 1'b0;

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
                        ctrl_cam_sel   <= tlp_dw_s[4];   // 1 = 相机写源
                        ctrl_ddr_en    <= tlp_dw_s[5];   // 1 = 每完成一帧自动搬进 DDR3
                        ctrl_push_en   <= tlp_dw_s[6];   // 1 = 每有一帧就推给主机
                        ctrl_push_src  <= tlp_dw_s[7];   // 1 = 推帧数据源取片内 ERAM 帧缓存
                    end
                    12'h5C: ptr     <= ptr_fix(tlp_dw_s);
                    12'h9C: cam_tap_cfg <= tlp_dw_s[6:0];
                    12'hB0: push_dst_lo <= tlp_dw_s;
                    12'hB4: push_dst_hi <= tlp_dw_s;
                    12'hB8: push_db_lo  <= tlp_dw_s;
                    12'hBC: push_db_hi  <= tlp_dw_s;
                    12'h6C: scratch <= tlp_dw_s;
                    12'h74: last_wr <= tlp_dw_s;
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
    // 读数据组装（组合）
    // ------------------------------------------------------------------

    reg [31:0] rd_dw_comb;
    always @(*) begin
        case (r_idx)
            12'h40:  rd_dw_comb = MAGIC;
            12'h44:  rd_dw_comb = {24'd0, ctrl_push_src, ctrl_push_en, ctrl_ddr_en, ctrl_cam_sel, ctrl_pattern_r, ctrl_trigger, ctrl_enable};
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
            12'h9C:  rd_dw_comb = {25'd0, cam_tap_cfg};   // 读回 tap 配置
            // DDR3 整帧搬运握手（ddr_frame_writer，见 rtl/ep_side/ddr/）
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
            default: rd_dw_comb = 32'hDEAD_BEEF;
        endcase
    end

    // 完成包载荷布局（实测）：第 0 个 dw 在 [255:224]，之后依次向下
    wire [31:0] p_dw0 = bswap32(rd_is_data ? pf0 : rd_dw_comb);
    wire [31:0] p_dw1 = bswap32(rd_is_data ? pf1 : 32'd0);
    wire [31:0] p_dw2 = bswap32(rd_is_data ? pf2 : 32'd0);
    wire [31:0] p_dw3 = bswap32(rd_is_data ? pf3 : 32'd0);

    assign mrdata_rd_data = {p_dw0, p_dw1, p_dw2, p_dw3, 128'd0};

endmodule
