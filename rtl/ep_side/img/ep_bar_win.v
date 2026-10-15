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
//
//  寄存器表（BAR0 字节偏移，4 字节对齐）：
//    0x40 MAGIC     R    0x50434946
//    0x44 CTRL      R/W  bit0 enable, bit1 trigger(写1出单帧), [3:2] pattern
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
    output reg  [1:0]   ctrl_pattern,
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

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cam_tap_cfg <= 7'b1_101110;   // 默认 manual_en=1, tap=46
            rd_addr32     <= 32'd0;
            rd_len_dw     <= 11'd1;
            rd_data_go    <= 1'b0;
            memrd_addr_lo <= 7'd0;
            ctrl_enable   <= 1'b0;
            ctrl_trigger  <= 1'b0;
            ctrl_pattern  <= 2'd0;
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
                        ctrl_pattern <= tlp_dw_s[3:2];
                    end
                    12'h5C: ptr     <= ptr_fix(tlp_dw_s);
                    12'h9C: cam_tap_cfg <= tlp_dw_s[6:0];
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
    // ------------------------------------------------------------------
    reg [31:0] pf0, pf1, pf2, pf3;
    reg [1:0]  pf_sel;

    assign fb_raddr = ptr + {30'd0, pf_sel, 2'b00};

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pf0 <= 32'd0; pf1 <= 32'd0; pf2 <= 32'd0; pf3 <= 32'd0;
            pf_sel <= 2'd0;
        end else begin
            // fb_rdata 是“上一拍地址”的数据 → 按 pf_sel 回退一格存入
            case (pf_sel)
                2'd1: pf0 <= fb_rdata;   // 上一拍地址 = ptr+0
                2'd2: pf1 <= fb_rdata;   // ptr+4
                2'd3: pf2 <= fb_rdata;   // ptr+8
                2'd0: pf3 <= fb_rdata;   // ptr+12
            endcase
            pf_sel <= pf_sel + 2'd1;
        end
    end

    // ------------------------------------------------------------------
    // 读数据组装（组合）
    // ------------------------------------------------------------------

    reg [31:0] rd_dw_comb;
    always @(*) begin
        case (r_idx)
            12'h40:  rd_dw_comb = MAGIC;
            12'h44:  rd_dw_comb = {28'd0, ctrl_pattern, ctrl_trigger, ctrl_enable};
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
