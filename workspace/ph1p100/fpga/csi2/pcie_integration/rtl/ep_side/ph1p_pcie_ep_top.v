//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2024 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : ph1p_pcie_ep_top.v
//  Author        : Gehong - hong.ge@anlogic.com
//  Last Modified : 2024-07-10 17:43:34
//  Create        : 2023-05-05 11:06:25
//  Description   : 
//
///////////////////////////////////////////////////////////////

`timescale 1ns/1ps
`include "../common/ph1p_pcie_case_param.v" 
 module ph1p_pcie_ep_top(

    // serdes high speed pin
    input      wire                      ref_pad_clk_p                           ,
    input      wire                      ref_pad_clk_n                           ,
    input      wire  [1:0]               pcie_rx_p                               ,
    input      wire  [1:0]               pcie_rx_n                               ,
    output     wire  [1:0]               pcie_tx_p                               ,
    output     wire  [1:0]               pcie_tx_n                               ,
    input      wire                      user_int_trigger                        ,
    input      wire                      sys_clk                                 ,
    // pcie ip reset
    input      wire                      pcie_mperst                             ,
    input      wire                      pcie_power_on_rst                       ,
    // uart signals（rxd 让位给 MIPI 子卡的 cam_a_xclr_n，板上不再用串口接收）
    // MIPI 摄像头（FEP-VID006 子卡，A/B 两路 IMX415）
    input      wire                      mipi_a_clk_hs_p                         ,
    input      wire                      mipi_a_clk_hs_n                         ,
    input      wire  [3:0]               mipi_a_data_hs_p                        ,
    input      wire  [3:0]               mipi_a_data_hs_n                        ,
    input      wire                      mipi_b_clk_hs_p                         ,
    input      wire                      mipi_b_clk_hs_n                         ,
    input      wire  [3:0]               mipi_b_data_hs_p                        ,
    input      wire  [3:0]               mipi_b_data_hs_n                        ,
    output     wire                      cam_a_mclk                              ,
    output     wire                      cam_a_xclr_n                            ,
    output     wire                      cam_a_scl                               ,
    inout      wire                      cam_a_sda                               ,
    output     wire                      cam_b_mclk                              ,
    output     wire                      cam_b_xclr_n                            ,
    output     wire                      cam_b_scl                               ,
    inout      wire                      cam_b_sda                               ,
    output     wire                      txd                                     ,
    output     wire     [3:0]            debug_led                               ,
    // DDR3 颗粒（板载 DDR3L x16/2048：4 个 DQ byte + AC；球号与 IOSTANDARD 由
    // al_ip/ddr3_mc_0 自带的 src/adc/ddr3_mc_0.adc（set_ippin_assignment）给出，
    // 本工程的 adc 里不写任何 ddr_* 引脚，见文件末 DDR3 段说明）
    output     wire                      ddr_ck_p                                ,
    output     wire                      ddr_ck_n                                ,
    output     wire                      ddr_reset_n                             ,
    output     wire                      ddr_cke                                 ,
    output     wire                      ddr_odt                                 ,
    output     wire                      ddr_cs_n                                ,
    output     wire                      ddr_ras_n                               ,
    output     wire                      ddr_cas_n                               ,
    output     wire                      ddr_we_n                                ,
    output     wire  [2:0]               ddr_ba                                  ,
    output     wire  [13:0]              ddr_addr                                ,
    inout      wire  [3:0]               ddr_dqs_p                               ,
    inout      wire  [3:0]               ddr_dqs_n                               ,
    inout      wire  [31:0]              ddr_dq                                  ,
    inout      wire  [3:0]               ddr_dm                                 

);   

// ====================================================================
// Parameter/wire/reg
// =================================================================== 
/// Simlation
//pragma translate_off
`define         PH1P_HXT_FAST_SIM 
//pragma translate_on 
`ifdef PH1P_HXT_FAST_SIM
    parameter PH1P_HXT_FAST_SIM = 1'b1;
`else
    parameter PH1P_HXT_FAST_SIM = 1'b0;
`endif   

    // ---- 图像通路（本移植新增）----
    localparam IMG_W      = 640;
    localparam IMG_H      = 480;


    localparam IMG_WORDS  = (IMG_W * IMG_H) / 4;
    localparam IMG_PTRBYTES = IMG_W * IMG_H;
    localparam IMG_PTRMSK   = (IMG_WORDS * 4) - 4;   // 保留（未用）

    // ---- 相机正式 RAW10 通路（cam_r10f_writer，T11 新增）----
    //  传感器跑 4K（I_cam_mode=1），MIPI/CSI-2 收到整行 3840 像素；片内帧缓存
    //  装不下 4K，所以正式路走「CSI-2 4 像素组 → 偶数 ROI → packed RAW10 →
    //  R10F v1 → AXI 写 DDR3」。ROI 尺寸必须使 DMA 区为 4KiB 整数倍（1920×1080
    //  packed = 2,592,000B + 128B 头 = 2,592,128B ⇒ dma_bytes = 2,592,768B = 633×4KiB）。
    //  几何（板证前按“未板证”对待；来自源包实际 WC/行数标定）：
    //    3840×2160 有效图居中取 1920×1080：X0=960、有效图 Y0=540（物理行 = 37+540）；
    //    帧头 embedded + 物理哑行 SKIP_ROWS=37（T07 实测来源，未板证）。
    localparam integer CAMDDR_W   = 1920;
    localparam integer CAMDDR_H   = 1080;
    localparam [15:0]  CAMDDR_X0  = 16'd960;
    localparam [15:0]  CAMDDR_Y0  = 16'd540;
    localparam [15:0]  CAMDDR_SKIP_ROWS = 16'd37;
    //  两路各一对双缓冲（A/B 互不重叠；一帧 8294400B = 7.91MB，两块间隔 8MB）：
    //    A: 块0 1MB 起、块1 9MB 起   → 占用 1MB..16.914MB
    //    B: 块0 17MB 起、块1 25MB 起 → 占用 17MB..32.914MB
    localparam [31:0]  DDR_CAM_BASE0   = 32'h0010_0000;   // A 路 4K 帧双缓冲块 0（1MB）
    localparam [31:0]  DDR_CAM_BASE1   = 32'h0090_0000;   // A 路块 1（9MB；一帧 7.9MB，不重叠）
    localparam [31:0]  DDR_CAM_B_BASE0 = 32'h0110_0000;   // B 路块 0（17MB）
    localparam [31:0]  DDR_CAM_B_BASE1 = 32'h0190_0000;   // B 路块 1（25MB）
    localparam integer CAMDDR_BYTES  = CAMDDR_W * CAMDDR_H;   // 2,073,600（ROI 像素数；正式路是 packed，不用这个数）
    // T07：实际板载 DDR3L 容量（x16、2048Mb、单 CS ⇒ 256MB）。依据是本工程匹配
    // 生成的 al_ip/ddr3_mc_0/.params_ddr3_mc_0.txt（PH1P_COMP_DENSITY=2048、
    // PH1P_COMP_TYPE=x16、PH1P_DDR_CS=1）与板载颗粒规格；**不拿 AXI 29 位地址线
    // 宽当容量**（那是 512MB 的地址窗口，比实际容量大）。ARM 校验源基址时用这个数。
    localparam [31:0]  DDR_CAP_BYTES = 32'h1000_0000;

// T07 仿真兼容修正（行为不变）：以下 6 个线网在 peer 原文件里「先使用、后声明」，
// TD 能过、ModelSim vlog 报 vlog-2730/2388（隐式网冲突）。声明挪到所有使用之前，
// 原声明位置改成注释；接线与行为完全不变。
wire         tl_clk_user;
wire         pcie_pll_locked;
wire         tl_clk_locked;
wire         tl_rst_user;
wire         pl_link_up;
wire         img_ddr_en;         // CTRL[5]

// ==== 图像通路（本移植新增：img_regs + img_frame_src）====
wire [31:0]  img_fb_raddr;
wire [31:0]  img_fb_rdata;
wire         img_enable;
wire         img_trigger;
wire         img_ready;
wire         img_busy;
wire [31:0]  img_frame_cnt;
wire [31:0]  img_data_len;
wire [15:0]  img_width;
wire [15:0]  img_height;
wire [1:0]   img_pattern;   // CTRL[3:2]：测试图源图案（[0] 兼作传感器重触发）
wire [31:0]  img_dbg_idx;
wire         img_cam_ab_sel;   // CTRL[8]：推帧引擎取哪一路的已落 DDR 帧（0 = A，1 = B）

// 相机 4K 直通使能：DDR 搬运开着（CTRL[5]）时两片 cam_ddr_writer 都 armed。
// A/B 两路各在自己的字节时钟域收帧，只在 DDR 域用 ddr_wr_arb 分时复用 AXI 写口。
// T07：img_ddr_en 的声明已提前到文件前部（见那里的说明）。
wire         w_cam_ddr_want;
assign w_cam_ddr_want  = img_ddr_en;
// img_pattern[0] = CTRL[2] 用作「传感器重触发」（见顶层相机段说明）。
wire [255:0] w_cam_stat;      // 声明必须早于例化处使用（否则 TD 造 1 位隐式网）
wire [6:0]   cam_tap_cfg;     // A 路 tap（0x9C）
wire [6:0]   cam_tap_b_cfg;   // B 路 tap（0xD4）

wire         w_uart_rxd_unused = 1'b1;

// ==== 相机整帧 → DDR3（A/B 两片 cam_ddr_writer + ddr_wr_arb + u_ddr3_mc_0 写口）====
//  握手寄存器面在 ep_bar_win（A: 0xA0~0xAC，B: 0xE0~0xEC），经 pcie_ep_engine 的
//  img_ctrl_ddr_en / img_ddr_ro / ddr_ro_b 端口过一下（与 cam_stat_bus 同一种做法）。
// T07：img_ddr_en 的声明已提前到文件前部（vlog-2730 兼容），此处不再声明。
wire [127:0] w_ddr_ro;           // A 路 {len, status, base, seq} → ep_bar_win 0xAC/0xA8/0xA4/0xA0
wire [127:0] w_ddr_ro_b;         // B 路同样四个字 → 0xEC/0xE8/0xE4/0xE0
wire [31:0]  w_cam_diag_b;       // B 路相机直通诊断 → 0xD8
wire [95:0]  w_camddr_drop_a;    // A 路丢帧诊断 → 0xDC/0xF0/0xF4
wire [31:0]  img_fb_rd2_data;    // 共用读口回来的数据（推帧的 ERAM 源用）
wire         img_host_rd_prio;   // ep_bar_win 的预取还没刷完 → 读口要还给它
wire         img_host_grant;     // 本拍读口归主机（与 img_fb_rd2_* 配套的仲裁输出）
wire         img_dma_grant;      // 本拍读口归 DMA（未按源细分）
wire [28:0]  w_ddr_awaddr;
wire [7:0]   w_ddr_awlen;
wire [2:0]   w_ddr_awsize;
wire [1:0]   w_ddr_awburst;
wire         w_ddr_awvalid, w_ddr_awready;
wire [255:0] w_ddr_wdata;
wire [31:0]  w_ddr_wstrb;
wire         w_ddr_wlast, w_ddr_wvalid, w_ddr_wready;
wire [1:0]   w_ddr_bresp;
wire         w_ddr_bvalid, w_ddr_bready;
wire         w_ddrphy_rdy;       // = 1 表示 DDRPHY 校准完成（IP 的 cal_done）

// ==== 相机 4K 直通 DDR3（A/B 各一片 cam_ddr_writer）====
//  两片同时 armed，各自的 AXI 写口由 ddr_wr_arb 分时放行（策略见该文件头部）。
wire                w_camw_busy, w_camw_busy_b;
wire                w_wr_grant;         // 当前授权给哪一路的 AXI 写口（诊断）

// A 路（CSI-2 A → DDR3）的 AXI 写口
wire [28:0] w_camw_awaddr;   wire [7:0] w_camw_awlen;   wire [2:0] w_camw_awsize;
wire [1:0]  w_camw_awburst;  wire w_camw_awvalid, w_camw_awready;
wire [255:0] w_camw_wdata;   wire [31:0] w_camw_wstrb;
wire        w_camw_wlast, w_camw_wvalid, w_camw_wready;
wire [1:0]  w_camw_bresp;    wire w_camw_bvalid, w_camw_bready;
// B 路（CSI-2 B → DDR3）的 AXI 写口
wire [28:0] w_camw_b_awaddr; wire [7:0] w_camw_b_awlen; wire [2:0] w_camw_b_awsize;
wire [1:0]  w_camw_b_awburst;wire w_camw_b_awvalid, w_camw_b_awready;
wire [255:0] w_camw_b_wdata; wire [31:0] w_camw_b_wstrb;
wire        w_camw_b_wlast, w_camw_b_wvalid, w_camw_b_wready;
wire [1:0]  w_camw_b_bresp;  wire w_camw_b_bvalid, w_camw_b_bready;
// 两路各自的握手字（{len,status,base,seq}）
wire [31:0] w_camddr_seq, w_camddr_base, w_camddr_status, w_camddr_len;
wire [31:0] w_camddr_b_seq, w_camddr_b_base, w_camddr_b_status, w_camddr_b_len;
// 两路各自的诊断（A → cam_stat[255:224] 即 0xD0；B → 0xD8）
wire [15:0] w_camddr_lines, w_camddr_grp, w_camddr_b_lines, w_camddr_b_grp;
wire        w_camddr_anom, w_camddr_b_anom;
// 推帧引擎取哪一路（CTRL[8]）
wire [31:0] w_push_ddr_seq, w_push_ddr_base, w_push_ddr_status, w_push_ddr_len;
// 推帧引擎的「本帧字节数」：DDR 源按选中的写者给，ERAM 源按 fb 的 DATA_LEN 给
wire [31:0] w_push_frame_bytes;

// ==== 【本步新增】推帧引擎（ddr_frame_pusher）====
//  · 引擎自己的 TL 发送口先接到 e_tl_tx_*，再由顶层 mux 与用户侧那一组合并成
//    tl_tx_*（见下面推帧段）：utx_sel = 1 时 TL 发送口归用户侧。
wire [255:0] e_tl_tx_data;
wire         e_tl_tx_sop, e_tl_tx_eop;
wire [7:0]   e_tl_tx_valid;
wire [255:0] utx_data;
wire         utx_sop, utx_eop, utx_req, utx_sel;
wire [7:0]   utx_valid;
wire         img_push_en;        // CTRL[6]
wire         img_push_src;       // CTRL[7]：1 = 推帧数据源取片内 ERAM 帧缓存
wire [31:0]  img_push_dst_lo, img_push_dst_hi, img_push_db_lo, img_push_db_hi;
wire [31:0]  img_push_done, img_push_status, img_push_tlp;
wire [7:0]   img_push_err;
wire [127:0] img_push_ro;        // {tlp_cnt, err, status, done} → ep_bar_win 0xCC/0xC8/0xC4/0xC0
// 字面顺序必须与 ep_bar_win.v 头部那张表逐位一致（也是主机侧唯一口径）：
//   0xCC=[127:96] TLP 数 / 0xC8=[95:64] 错误码 / 0xC4=[63:32] 状态 / 0xC0=[31:0] 已推帧数
assign img_push_ro = {img_push_tlp, 24'd0, img_push_err, img_push_status, img_push_done};
// ==== 推帧的 ERAM 源与主机预取共用 fb 那一个读口（fb[] 只允许一份读口）====
//  640x480 预览（fb[] → DDR3）从设计里移除后，fb 读口的 DMA 消费者只剩推帧的
//  ERAM 源（CTRL[7]=1 那条调试源），所以不再需要对源做二选一。
//  · src_act 由推帧引擎在每帧开头锁存（帧内不变）；
//  · 主机预取的优先级仍由 img_frame_src 内部的仲裁给出。
wire [31:0]  img_push_fb_addr;   // 推帧 ERAM 源的读地址
wire         img_push_fb_req;    // 推帧 ERAM 源本拍想读一个字
wire         img_push_src_act;   // 推帧本帧实际用的源（推帧引擎锁存后给出）
wire         img_push_fb_grant;  // 读口授权（给推帧的 ERAM 源）
wire [31:0]  img_fb_dma_addr;    // 真正送到 img_frame_src 的读地址
wire         img_fb_dma_req;     // 真正送到 img_frame_src 的读请求
assign img_fb_dma_addr   = img_push_fb_addr;
assign img_fb_dma_req    = img_push_fb_req;
assign img_push_fb_grant = img_dma_grant;
// AXI4 读通道（u_ddr3_mc_0 的用户侧读口，本步从「常量 0」改成接推帧引擎）
wire [3:0]   w_ddr_arid;
wire [28:0]  w_ddr_araddr;
wire [7:0]   w_ddr_arlen;
wire [2:0]   w_ddr_arsize;
wire [1:0]   w_ddr_arburst;
wire         w_ddr_arvalid, w_ddr_arready;
wire [3:0]   w_ddr_rid;
wire [255:0] w_ddr_rdata;
wire [1:0]   w_ddr_rresp;
wire         w_ddr_rlast, w_ddr_rvalid, w_ddr_rready;

// ==== T07.rk-align-backend 新增线网 ====
// RKA1 安全扩展（ep_bar_win ↔ 安全门，都是 tl_clk_user 域，直连）
wire [31:0]  w_tx_cap_bytes, w_tx_session_id, w_tx_ack_seq, w_tx_ack_session;
wire         w_tx_cmd_arm, w_tx_cmd_ack, w_tx_cmd_cancel;
wire [31:0]  w_tx_status;
wire         w_tx_block_cfg, w_tx_cfg_reject;
wire         w_link_up;                       // pl_link_up & 两个锁相都就绪
// 推帧引擎的源所有权信号
// T07 round1：release 按相机分开（A: rel_tgl0/1 → writer A；B: rel_tgl2/3 → writer B），
// 避免共享一对 toggle 时 A 路的 release 误清 B 路的保护位（system round0 F1）。
wire         w_rel_tgl0, w_rel_tgl1;          // A 路块 0/1 release toggle
wire         w_rel_tgl2, w_rel_tgl3;          // B 路块 0/1 release toggle
wire         w_push_fb_hold;                  // ERAM 源冻结（pusher 输出）
wire         w_push_src_lock;                 // 诊断：源被 one-shot 占着
// checked CSI（A/B）：帧裁决 + 错误/几何计数（字节时钟域）
wire         w_a_frame_end, w_a_frame_good, w_a_frame_abort;
wire         w_b_frame_end, w_b_frame_good, w_b_frame_abort;
wire [31:0]  w_a_crc_err, w_a_hdr_err, w_a_pkt_to, w_a_frm_to, w_a_good_frm, w_a_bad_frm;
wire [31:0]  w_b_crc_err, w_b_hdr_err, w_b_pkt_to, w_b_frm_to, w_b_good_frm, w_b_bad_frm;
wire [15:0]  w_a_last_wc, w_a_last_lines, w_b_last_wc, w_b_last_lines;
wire [31:0]  w_a_payload, w_b_payload;
wire [3:0]   w_a_keep, w_b_keep;
wire         w_a_payload_v, w_b_payload_v;
// 诊断跨域采样（字节域 → tl 域；只给人看，不参与控制，见 change-report 边界说明）
reg  [31:0]  r_csi_a_cnt1, r_csi_a_cnt2, r_csi_a_geo1, r_csi_a_geo2;
reg  [31:0]  r_csi_b_cnt1, r_csi_b_cnt2, r_csi_b_geo1, r_csi_b_geo2;
wire [31:0]  w_csi_a_cnt = {w_a_good_frm[7:0], w_a_bad_frm[7:0], w_a_hdr_err[7:0], w_a_crc_err[7:0]};
wire [31:0]  w_csi_a_geo = {w_a_last_lines, w_a_last_wc};
wire [31:0]  w_csi_b_cnt = {w_b_good_frm[7:0], w_b_bad_frm[7:0], w_b_hdr_err[7:0], w_b_crc_err[7:0]};
wire [31:0]  w_csi_b_geo = {w_b_last_lines, w_b_last_wc};

always @(posedge tl_clk_user) begin
    r_csi_a_cnt1 <= w_csi_a_cnt; r_csi_a_cnt2 <= r_csi_a_cnt1;
    r_csi_a_geo1 <= w_csi_a_geo; r_csi_a_geo2 <= r_csi_a_geo1;
    r_csi_b_cnt1 <= w_csi_b_cnt; r_csi_b_cnt2 <= r_csi_b_cnt1;
    r_csi_b_geo1 <= w_csi_b_geo; r_csi_b_geo2 <= r_csi_b_geo1;
end

// 链路就绪（ARM 的「硬核协商能力未知时禁 formal ARM」条件）
assign w_link_up = pl_link_up & tl_clk_locked & pcie_pll_locked;

//  0xA0~0xAC = A 路相机 writer 的握手字；0xE0~0xEC = B 路的（两路各一份，
//  都有「整帧校验通过才发布」的语义，所以主机按序号变化取哪一路都安全）。
//  A 路（0xA0~0xAC）、B 路（0xE0~0xEC）：同一套字序，各走一条汇聚总线给 ep_bar_win
assign w_ddr_ro   = {w_camddr_len,   w_camddr_status,   w_camddr_base,   w_camddr_seq};
assign w_ddr_ro_b = {w_camddr_b_len, w_camddr_b_status, w_camddr_b_base, w_camddr_b_seq};
assign w_cam_diag_b = {w_camddr_b_lines, w_camddr_b_grp};

// 推帧引擎的 DDR 源：按 CTRL[8] 取 A 路或 B 路那组握手字（准静态，帧内不变）
assign w_push_ddr_seq    = img_cam_ab_sel ? w_camddr_b_seq    : w_camddr_seq;
assign w_push_ddr_base   = img_cam_ab_sel ? w_camddr_b_base   : w_camddr_base;
assign w_push_ddr_status = img_cam_ab_sel ? w_camddr_b_status : w_camddr_status;
assign w_push_ddr_len    = img_cam_ab_sel ? w_camddr_b_len    : w_camddr_len;
// ↑ 方向别写反：w_ddr_ro 是「汇聚到寄存器窗口的那条总线」，四个字是它的源。
//   写反（assign {w_ddr_len,...} = w_ddr_ro;）会让这 128bit 整条悬空，
//   TD 综合报 SYN-5013 Undriven net / SYN-5025 Using 0 for all undriven pins and nets，
//   主机读 0xA0~0xAC 全得 0 —— 连常数 DDR_LEN(0x4B000) 也读 0（因为 0xAC 的源
//   是这条死总线，不是 wr_len 本身）。顺序也要对：{len,status,base,seq}

// 推帧引擎的「本帧字节数」：DDR 源用选中的那组 len；ERAM 源用 fb 的 DATA_LEN。
// 这两个数都必须是 4KB 的整数倍（640x480 = 75x4096、4K = 2025x4096），否则
// 推帧的 MWr 数/突发数不是整数（见 ddr_frame_pusher.v 端口说明）。
assign w_push_frame_bytes = img_push_src ? img_data_len : w_push_ddr_len;

    // clock and reset signals
    // T07：tl_clk_user / pcie_pll_locked / tl_clk_locked / tl_rst_user / pl_link_up /
    //      img_ddr_en 的声明已提前到文件前部（ModelSim vlog-2730 兼容），此处不再声明。
    wire                          tl_clk_gate                             ;
    wire       [8:0]              tl_clk_user_freq                        ;
    wire                          uart_clk                                ;
    // T07：pcie_pll_locked / tl_rst_user / tl_clk_locked 声明已提前（同上）
    reg                           power_on_rst_dly                        ;
    // user apb configure signals
    wire                          tl_cfg_pclk                             ;
    wire                          tl_cfg_prst                             ;
    wire                          tl_cfg_penable                          ;
    wire                          tl_cfg_psel                             ;
    wire                          tl_cfg_pwrite                           ;
    wire       [31:0]             tl_cfg_paddr                            ;
    wire       [3:0]              tl_cfg_pstrb                            ;
    wire       [31:0]             tl_cfg_pwdata                           ;
    wire                          tl_cfg_pready                           ;
    wire       [31:0]             tl_cfg_prdata                           ;
    wire                          tl_cfg_pslverr                          ;
    
    // cfg direct access
    wire       [7:0]              tl_cfg_tcvc                             ;
    wire       [12:0]             tl_cfg_busdev                           ;
    wire       [2:0]              tl_cfg_max_payload_size                 ;
    wire       [2:0]              tl_cfg_max_read_request_size            ;
    wire       [2:0]              tl_cfg_current_link_speed               ;
    wire       [3:0]              tl_cfg_negotiated_width                 ;
    wire                          tl_cfg_read_completion_boundary         ;
    wire       [7:0]              tl_cfg_pfregs_cmd                       ;
    wire       [7:0]              tl_cfg_pf0_primary_bus = 8'd0           ;
    wire       [7:0]              tl_cfg_pf1_primary_bus = 8'd0           ;
  
    // physical ltssm signals
    wire       [1:0]              pl_equ_phase                            ;
    wire       [4:0]              tl_ltssm                                ;
    wire       [4:0]              pl_ltssm                                ;
    // T07：pl_link_up 声明已提前（同上）
    wire                          tl_ltssm_enable                         =1'b1;

    // Rx interface
    wire                          tl_rx_wait                              ;
    wire                          tl_rx_masknp                            ;
    wire      [47:0]              tl_rx_bardec                            ;
    wire      [255:0]             tl_rx_data                              ;
    wire                          tl_rx_eop                               ;
    wire      [7:0]               tl_rx_err                               ;
    wire      [9:0]               tl_rx_mchit                             ;
    wire                          tl_rx_sop                               ;
    wire      [7:0]               tl_rx_valid                             ;

    // TX interface
    wire      [255:0]             tl_tx_data                              ;
    wire                          tl_tx_eop                               ;
    wire      [7:0]               tl_tx_err                               ;
    wire                          tl_tx_sop                               ;
    wire                          tl_tx_stream                            ;
    wire      [7:0]               tl_tx_valid                             ;
    wire                          tl_tx_wait                              ;
    wire      [95:0]              tl_tx_credits                           ;

   `ifdef PH1P_PCIE_LEGACY_INT_ENABLE
    wire      [1:0]               tl_int_status                           ;
    wire      [3:0]               tl_int_pincontrol                       ;
    wire      [3:0]               tl_int_pinstate                         ;
  `endif
  
  `ifdef PH1P_PCIE_MSI_INT_ENABLE
    wire      [1:0]               tl_int_msireq                           ;
    wire      [9:0]               tl_int_msinum                           ;
    wire      [1:0]               tl_int_msiack                           ;
    wire      [1:0]               tl_int_msi_enable                       ;
    wire      [5:0]               tl_int_msi_multi_enable                 ;
    wire      [31:0]              tl_int_pf0_msi_pending                  ;
    wire      [31:0]              tl_int_pf1_msi_pending                  ;
    wire      [31:0]              tl_int_pf0_msi_mask                     ;
    wire      [31:0]              tl_int_pf1_msi_mask                     ;
  `endif 
    
  `ifdef PH1P_PCIE_MSIX_INT_ENABLE
    wire      [1:0]               tl_cfg_msix_enable                      ;
    wire      [1:0]               tl_cfg_msix_function_mask               ;
  `endif

    //
    wire                          hxt_apb4_psel_i                         ;
    wire                          hxt_apb4_penable_i                      ;
    wire                          hxt_apb4_pwrite_i                       ;
    wire      [31:0]              hxt_apb4_paddr_i                        ;
    wire      [31:0]              hxt_apb4_pwdata_i                       ;
    wire      [3:0]               hxt_apb4_pstrb_i                        ;
    wire      [2:0]               hxt_apb4_pprot_i                        ;
    wire      [31:0]              hxt_apb4_prdata_o                       ;
    wire                          hxt_apb4_pready_o                       ;
    wire                          hxt_apb4_pslverr_o                      ;

    // Ubus
    wire                          ubus_pcie_wen                           ;
    wire      [31:0]              ubus_pcie_waddr                         ;
    wire      [31:0]              ubus_pcie_wdata                         ;
    wire                          ubus_pcie_ren                           ;
    wire      [31:0]              ubus_pcie_raddr                         ;
    wire                          ubus_pcie_bken                          ;
    wire      [31:0]              ubus_pcie_rdata                         ;

    wire                          ubus_hxt_wen                            ;
    wire      [31:0]              ubus_hxt_waddr                          ;
    wire      [31:0]              ubus_hxt_wdata                          ;
    wire                          ubus_hxt_ren                            ;
    wire      [31:0]              ubus_hxt_raddr                          ;
    wire                          ubus_hxt_bken                           ;
    wire      [31:0]              ubus_hxt_rdata                          ;

    // ubus to logic
    wire                          ubus_wen_logic                          ;
    wire      [31:0]              ubus_waddr_logic                        ;
    wire      [31:0]              ubus_wdata_logic                        ;
    wire                          ubus_ren_logic                          ;
    wire      [31:0]              ubus_raddr_logic                        ;
    wire                          ubus_bken_logic                         ;
    wire      [31:0]              ubus_rdata_logic                        ;
    // Debug Logic 
    reg                           ubus_wen_logic_dly                      ;
    reg       [31:0]              ubus_waddr_logic_dly                    ;
    reg       [31:0]              ubus_wdata_logic_dly                    ;
    reg                           ubus_ren_logic_dly                      ;
    reg       [31:0]              ubus_raddr_logic_dly                    ;
    reg                           ubus_bken_logic_dly                     =1'b0;
    reg       [31:0]              ubus_rdata_logic_dly                    =32'd0;

    reg       [31:0]              rd_data0                                ;
    reg       [31:0]              rd_data1                                ;
    reg       [31:0]              rd_data2                                ;
    reg       [31:0]              rd_data3                                ;
    reg       [31:0]              rd_data4                                ;

    reg       [4:0]               ltssm_reg                               =5'd0;
    reg       [4:0]               ltssm_reg_dly                           =5'd0;
    reg       [4:0]               ltssm_debug[19:0]                       ;
    reg       [31:0]              ltssm_change_cnt                        ;

    wire      [3:0]               tl_int_msix_trigger                     ;
    reg                           pcie_power_on_rst_reg                   ;
    wire                          clk_50M                                 ;
    reg                           pcie_power_on_rst_uart                  ;
    reg                           uart_rst                                ;
// ====================================================================
// PCIe Controller Clock Generate
// ====================================================================
//--------------------------------------------
// clock logic
//--------------------------------------------
pcie_pll_ep u_pcie_pll_ep(
    .refclk                       (sys_clk                    ),
    .reset                        (!pcie_power_on_rst         ),
    .lock                         (pcie_pll_locked            ),
    .clk0_out                     (tl_clk_user                ) 
);

assign  tl_cfg_pclk = tl_clk_user;

always@(posedge tl_clk_user or negedge pcie_power_on_rst )
begin
    if(!pcie_power_on_rst )
        uart_rst <= 1'b1;
    else 
        uart_rst <= ~pcie_pll_locked;
end


always@(posedge tl_clk_user or negedge pcie_power_on_rst )
begin
    if(!pcie_power_on_rst )
        pcie_power_on_rst_reg <= 1'b0;
    else 
        pcie_power_on_rst_reg <= pcie_pll_locked;
end

always@(posedge tl_clk_user or negedge pcie_power_on_rst_reg )
begin
    if(!pcie_power_on_rst_reg )
        power_on_rst_dly <= 1'b1;
    else 
        power_on_rst_dly <= !pcie_mperst | pcie_power_on_rst_uart;
end

ph1p_pcie_rst_sync#(
    .LTSSM_VAULE                  (5'h10                                   )
) u_ph1p_pcie_rst_sync(
    .clk                          (tl_clk_user                             ),
    .rst                          (power_on_rst_dly                        ),
    .tl_ltssm                     (tl_ltssm                                ),
    .pl_link_up                   (pl_link_up&tl_clk_locked&pcie_pll_locked),
    .rst_sync                     (tl_rst_user                             )
);

// ====================================================================
// PCIE IP Inst
// ====================================================================
pcie_ep_core #( 
    .PH1P_HXT_FAST_SIM(PH1P_HXT_FAST_SIM)
)u_ph1p_pcie_ep_subsystem_top(
    
   // serdes high speed pin
    .ref_pad_clk_p                           (ref_pad_clk_p                           ),
    .ref_pad_clk_n                           (ref_pad_clk_n                           ),
    .pcie_rx_p                               (pcie_rx_p                               ),
    .pcie_rx_n                               (pcie_rx_n                               ),
    .pcie_tx_p                               (pcie_tx_p                               ),
    .pcie_tx_n                               (pcie_tx_n                               ),

    // transcation layer clock signals  
    .tl_clk_user                             (tl_clk_user                             ),
    .tl_clk_user_ce_n                        (!pcie_pll_locked                        ),
    .tl_clk_locked                           (tl_clk_locked                           ),

    // clock and reset signals
    .tl_clk_gate                             (tl_clk_gate                             ),
    .tl_power_on_rst                         (power_on_rst_dly                        ),

    // user apb configure signals
    .tl_cfg_pclk                             (tl_cfg_pclk                             ),
    .tl_cfg_prst                             (tl_cfg_prst                             ),
    .tl_cfg_penable                          (tl_cfg_penable                          ),
    .tl_cfg_psel                             (tl_cfg_psel                             ),
    .tl_cfg_pwrite                           (tl_cfg_pwrite                           ),
    .tl_cfg_paddr                            (tl_cfg_paddr                            ),
    .tl_cfg_pstrb                            (tl_cfg_pstrb                            ),
    .tl_cfg_pwdata                           (tl_cfg_pwdata                           ),
    .tl_cfg_pready                           (tl_cfg_pready                           ),
    .tl_cfg_prdata                           (tl_cfg_prdata                           ),
    .tl_cfg_pslverr                          (tl_cfg_pslverr                          ),
    
    .apb4_clk_i                              (tl_cfg_pclk                             ),
    .apb4_preset_i                           (1'b0                                    ),
    .apb4_psel_i                             (hxt_apb4_psel_i                         ),
    .apb4_penable_i                          (hxt_apb4_penable_i                      ),
    .apb4_pwrite_i                           (hxt_apb4_pwrite_i                       ),
    .apb4_paddr_i                            (hxt_apb4_paddr_i                        ),
    .apb4_pwdata_i                           (hxt_apb4_pwdata_i                       ),
    .apb4_pstrb_i                            (hxt_apb4_pstrb_i                        ),
    .apb4_pprot_i                            (hxt_apb4_pprot_i                        ),
    .apb4_prdata_o                           (hxt_apb4_prdata_o                       ),
    .apb4_pready_o                           (hxt_apb4_pready_o                       ),
    .apb4_pslverr_o                          (hxt_apb4_pslverr_o                      ),
    
    // cfg direct access 
    .tl_cfg_tcvc                             (tl_cfg_tcvc                             ),
    .tl_cfg_busdev                           (tl_cfg_busdev                           ),
    .tl_cfg_max_payload_size                 (tl_cfg_max_payload_size                 ),
    .tl_cfg_max_read_request_size            (tl_cfg_max_read_request_size            ),
    .tl_cfg_current_link_speed               (tl_cfg_current_link_speed               ),
    .tl_cfg_negotiated_width                 (tl_cfg_negotiated_width                 ),
    .tl_cfg_read_completion_boundary         (tl_cfg_read_completion_boundary         ),
    .tl_cfg_pfregs_cmd                       (tl_cfg_pfregs_cmd                       ),
    .tl_cfg_pf0_primary_bus                  (tl_cfg_pf0_primary_bus                  ),
    .tl_cfg_pf1_primary_bus                  (tl_cfg_pf1_primary_bus                  ),
 
    // pf legacy int / msi 
    `ifdef PH1P_PCIE_LEGACY_INT_ENABLE
    .tl_int_status                           (tl_int_status                           ),
    .tl_int_pincontrol                       (tl_int_pincontrol                       ),
    .tl_int_pinstate                         (tl_int_pinstate                         ),
    `endif
    
    `ifdef PH1P_PCIE_MSI_INT_ENABLE
    .tl_int_status                           (tl_int_status                           ),
    .tl_int_msireq                           (tl_int_msireq                           ),
    .tl_int_msinum                           (tl_int_msinum                           ),
    .tl_int_msiack                           (tl_int_msiack                           ),
    .tl_int_msi_enable                       (tl_int_msi_enable                       ),
    .tl_int_msi_multi_enable                 (tl_int_msi_multi_enable                 ),
    .tl_int_pf0_msi_pending                  (tl_int_pf0_msi_pending                  ),
    .tl_int_pf1_msi_pending                  (tl_int_pf1_msi_pending                  ),
    .tl_int_pf0_msi_mask                     (tl_int_pf0_msi_mask                     ),
    .tl_int_pf1_msi_mask                     (tl_int_pf1_msi_mask                     ),
    `endif 
      
    // pf msi 
    `ifdef PH1P_PCIE_MSIX_INT_ENABLE
    .tl_cfg_msix_enable                      (tl_cfg_msix_enable                      ),
    .tl_cfg_msix_function_mask               (tl_cfg_msix_function_mask               ),
    `endif

    // physical ltssm signals 
    .pl_equ_phase                            (pl_equ_phase                            ),
    .tl_ltssm                                (tl_ltssm                                ),
    .pl_ltssm                                (pl_ltssm                                ),
    .pl_link_up                              (pl_link_up                              ),
    .tl_ltssm_enable                         (tl_ltssm_enable                         ),

    // Rx interface 
    .tl_rx_wait                              (tl_rx_wait                              ),
    .tl_rx_masknp                            (tl_rx_masknp                            ),
    .tl_rx_bardec                            (tl_rx_bardec                            ),
    .tl_rx_data                              (tl_rx_data                              ),
    .tl_rx_eop                               (tl_rx_eop                               ),
    .tl_rx_err                               (tl_rx_err                               ),
    .tl_rx_mchit                             (tl_rx_mchit                             ),
    .tl_rx_sop                               (tl_rx_sop                               ),
    .tl_rx_valid                             (tl_rx_valid                             ),

    // TX interface 
    .tl_tx_data                              (tl_tx_data                              ),
    .tl_tx_eop                               (tl_tx_eop                               ),
    .tl_tx_err                               (tl_tx_err                               ),
    .tl_tx_sop                               (tl_tx_sop                               ),
    .tl_tx_stream                            (tl_tx_stream                            ),
    .tl_tx_valid                             (tl_tx_valid                             ),
    .tl_tx_wait                              (tl_tx_wait                              ),
    .tl_tx_credits                           (tl_tx_credits                           )
);

pcie_ep_engine #(
    .IMG_PTRBYTES                            (IMG_PTRBYTES                           ),
    .IMG_CLK_MHZ                             (9'd62                                  )
) u_pcie_ep_engine (


    // Clock and Reset
    .tl_clk_user                             (tl_clk_user                             ),
    .tl_rst_user                             (tl_rst_user                             ),

    // Rx interface
    .tl_rx_wait                              (tl_rx_wait                              ),
    .tl_rx_masknp                            (tl_rx_masknp                            ),
    .tl_rx_bardec                            (tl_rx_bardec                            ),
    .tl_rx_data                              (tl_rx_data                              ),
    .tl_rx_eop                               (tl_rx_eop                               ),
    .tl_rx_err                               (tl_rx_err                               ),
    .tl_rx_mchit                             (tl_rx_mchit                             ),
    .tl_rx_sop                               (tl_rx_sop                               ),
    .tl_rx_valid                             (tl_rx_valid                             ),

`ifdef PH1P_PCIE_MSIX_INT_ENABLE
    .tl_int_msix_trigger                     (tl_int_msix_trigger                     ),
`else
    .tl_int_msix_trigger                     (4'b0                                    ),
`endif

    // TX interface 
    .tl_tx_data                              (e_tl_tx_data                           ),
    .tl_tx_eop                               (e_tl_tx_eop                            ),
    .tl_tx_err                               (tl_tx_err                              ),
    .tl_tx_sop                               (e_tl_tx_sop                            ),
    .tl_tx_stream                            (tl_tx_stream                           ),
    .tl_tx_valid                             (e_tl_tx_valid                          ),
    .tl_tx_wait                              (tl_tx_wait                             ),
    .tl_tx_credits                           (tl_tx_credits                          ),
    // ==== 本步新增：推帧寄存器面 + 用户侧 TL 发送口 ====
    .img_push_en                             (img_push_en                            ),
    .img_push_src                            (img_push_src                           ),
    .img_push_dst_lo                         (img_push_dst_lo                        ),
    .img_push_dst_hi                         (img_push_dst_hi                        ),
    .img_push_db_lo                          (img_push_db_lo                         ),
    .img_push_db_hi                          (img_push_db_hi                         ),
    .img_push_ro                             (img_push_ro                            ),
    .utx_req                                 (utx_req                                ),
    .utx_eop                                 (utx_eop                                ),
    .utx_valid                               (utx_valid                              ),
    .utx_sel                                 (utx_sel                                ),
    // ==== 本移植新增：BAR0 真窗口 → 图像源 ====
    .img_ctrl_enable                         (img_enable                             ),
    .img_ctrl_trigger                        (img_trigger                            ),
    .img_ctrl_pattern                        (img_pattern                            ),
    .img_st_ready                            (img_ready                              ),
    .img_st_busy                             (img_busy                               ),
    .img_st_frame_cnt                        (img_frame_cnt                          ),
    .img_st_width                            (img_width                              ),
    .img_st_height                           (img_height                             ),
    .img_st_data_len                         (img_data_len                           ),
    .img_fb_raddr                            (img_fb_raddr                           ),
    .img_fb_rdata                            (img_fb_rdata                           )
    ,.img_dbg_rd_idx                          (img_dbg_idx                            ),
    .cam_stat_bus                            (w_cam_stat                             ),
    .cam_tap_cfg                             (cam_tap_cfg                            ),
    .cam_tap_b_cfg                           (cam_tap_b_cfg                          ),
    .cam_ab_sel                              (img_cam_ab_sel                         ),
    .ddr_ro_b                                (w_ddr_ro_b                             ),
    .cam_drop_a                              (w_camddr_drop_a                        ),
    .cam_diag_b                              (w_cam_diag_b                           ),
    // DDR3 整帧搬运（CTRL[5] + 只读握手字 + fb 读口仲裁）
    .img_ctrl_ddr_en                         (img_ddr_en                             ),
    .img_ddr_ro                              (w_ddr_ro                               ),
    .img_host_rd_prio                        (img_host_rd_prio                       ),
    .img_host_grant                          (img_host_grant                         )
    ,// T07：RKA1 安全扩展寄存器面 + CSI 诊断（过路到安全门/BAR）
    .tx_cap_bytes                            (w_tx_cap_bytes                         ),
    .tx_session_id                           (w_tx_session_id                        ),
    .tx_cmd_arm                              (w_tx_cmd_arm                           ),
    .tx_cmd_ack                              (w_tx_cmd_ack                           ),
    .tx_cmd_cancel                           (w_tx_cmd_cancel                        ),
    .tx_ack_seq                              (w_tx_ack_seq                           ),
    .tx_ack_session                          (w_tx_ack_session                       ),
    .tx_status_in                            (w_tx_status                            ),
    .tx_block_cfg                            (w_tx_block_cfg                         ),
    .cfg_reject                              (w_tx_cfg_reject                        ),
    .csi_diag_a                              (r_csi_a_cnt2                           ),
    .csi_diag_a2                             (r_csi_a_geo2                           ),
    .csi_diag_b                              (r_csi_b_cnt2                           ),
    .csi_diag_b2                             (r_csi_b_geo2                           )
);

pcie_ep_int_handle u_pcie_ep_int_handle(

    // Clock and Reset
    .tl_clk_user                             (tl_clk_user                             )
   ,.tl_rst_user                             (tl_rst_user                             )
   ,.user_int_trigger                        (!user_int_trigger                       )
`ifdef PH1P_PCIE_LEGACY_INT_ENABLE 
   ,.tl_int_status                           (tl_int_status                           )
   ,.tl_int_pincontrol                       (tl_int_pincontrol                       )
   ,.tl_int_pinstate                         (tl_int_pinstate                         )
`endif
`ifdef PH1P_PCIE_MSI_INT_ENABLE 
   ,.tl_int_status                           (tl_int_status                           )
   ,.tl_int_msireq                           (tl_int_msireq                           )
   ,.tl_int_msinum                           (tl_int_msinum                           )
   ,.tl_int_msiack                           (tl_int_msiack                           )
   ,.tl_int_msi_enable                       (tl_int_msi_enable                       )
   ,.tl_int_msi_multi_enable                 (tl_int_msi_multi_enable                 )
   ,.tl_int_pf0_msi_pending                  (tl_int_pf0_msi_pending                  )
   ,.tl_int_pf1_msi_pending                  (tl_int_pf1_msi_pending                  )
   ,.tl_int_pf0_msi_mask                     (tl_int_pf0_msi_mask                     )
   ,.tl_int_pf1_msi_mask                     (tl_int_pf1_msi_mask                     )
`endif
`ifdef PH1P_PCIE_MSIX_INT_ENABLE
   ,.tl_int_msix_trigger                     (tl_int_msix_trigger                     )
`endif
);

pcie_uart
#(
    .BAUDRATE                                (115200                                  ),
    .CLK_RATE                                (16                                      )// Period
)u_uart (
    .aux_clk                                 (tl_clk_user                             ),
    .core_clk                                (tl_clk_user                             ),
    .rst_n                                   (uart_rst                                ),
                                                                                      
    .rx                                      (w_uart_rxd_unused                                     ),
    .tx                                      (txd                                     ),
                                                                                      
    .ubus_pcie_wen                           (ubus_pcie_wen                           ),
    .ubus_pcie_waddr                         (ubus_pcie_waddr                         ),
    .ubus_pcie_wdata                         (ubus_pcie_wdata                         ),
    .ubus_pcie_ren                           (ubus_pcie_ren                           ),
    .ubus_pcie_raddr                         (ubus_pcie_raddr                         ),
    .ubus_pcie_bken                          (ubus_pcie_bken                          ),
    .ubus_pcie_rdata                         (ubus_pcie_rdata                         ),

    .ubus_hxt_wen                            (ubus_hxt_wen                            ),
    .ubus_hxt_waddr                          (ubus_hxt_waddr                          ),
    .ubus_hxt_wdata                          (ubus_hxt_wdata                          ),
    .ubus_hxt_ren                            (ubus_hxt_ren                            ),
    .ubus_hxt_raddr                          (ubus_hxt_raddr                          ),
    .ubus_hxt_bken                           (ubus_hxt_bken                           ),
    .ubus_hxt_rdata                          (ubus_hxt_rdata                          )
);

ep_ubus_bridge u_ep_ubus_bridge(
    .tl_clk_user                             (tl_clk_user                            ),
    .uart_clk                                (tl_clk_user                            ),
    .rst                                     (uart_rst                               ),
    .tl_clk_locked                           (tl_clk_locked                          ),

    // pcie Ubus
    .ubus_pcie_wen                           (ubus_pcie_wen                          ),
    .ubus_pcie_waddr                         (ubus_pcie_waddr                        ),
    .ubus_pcie_wdata                         (ubus_pcie_wdata                        ),
    .ubus_pcie_ren                           (ubus_pcie_ren                          ),
    .ubus_pcie_raddr                         (ubus_pcie_raddr                        ),
    .ubus_pcie_bken                          (ubus_pcie_bken                         ),
    .ubus_pcie_rdata                         (ubus_pcie_rdata                        ),

    // hxt Ubus
    .ubus_hxt_wen                            (ubus_hxt_wen                           ),
    .ubus_hxt_waddr                          (ubus_hxt_waddr                         ),
    .ubus_hxt_wdata                          (ubus_hxt_wdata                         ),
    .ubus_hxt_ren                            (ubus_hxt_ren                           ),
    .ubus_hxt_raddr                          (ubus_hxt_raddr                         ),
    .ubus_hxt_bken                           (ubus_hxt_bken                          ),
    .ubus_hxt_rdata                          (ubus_hxt_rdata                         ),

    // To fabric logic
    .ubus_wen_logic                          (ubus_wen_logic                         ),
    .ubus_waddr_logic                        (ubus_waddr_logic                       ),
    .ubus_wdata_logic                        (ubus_wdata_logic                       ),
    .ubus_ren_logic                          (ubus_ren_logic                         ),
    .ubus_raddr_logic                        (ubus_raddr_logic                       ),
    .ubus_bken_logic                         (ubus_bken_logic                        ),
    .ubus_rdata_logic                        (ubus_rdata_logic                       ),

    // To PCIe APB
    .tl_cfg_prst                             (tl_cfg_prst                            ),
    .tl_cfg_penable                          (tl_cfg_penable                         ),
    .tl_cfg_psel                             (tl_cfg_psel                            ),
    .tl_cfg_pwrite                           (tl_cfg_pwrite                          ),
    .tl_cfg_paddr                            (tl_cfg_paddr                           ),
    .tl_cfg_pstrb                            (tl_cfg_pstrb                           ),
    .tl_cfg_pwdata                           (tl_cfg_pwdata                          ),
    .tl_cfg_pready                           (tl_cfg_pready                          ),
    .tl_cfg_prdata                           (tl_cfg_prdata                          ),
    .tl_cfg_pslverr                          (tl_cfg_pslverr                         ),
    
    // To HXT APB
    .hxt_apb4_psel_o                         (hxt_apb4_psel_i                        ),
    .hxt_apb4_penable_o                      (hxt_apb4_penable_i                     ),
    .hxt_apb4_pwrite_o                       (hxt_apb4_pwrite_i                      ),
    .hxt_apb4_paddr_o                        (hxt_apb4_paddr_i                       ),
    .hxt_apb4_pwdata_o                       (hxt_apb4_pwdata_i                      ),
    .hxt_apb4_pstrb_o                        (hxt_apb4_pstrb_i                       ),
    .hxt_apb4_pprot_o                        (hxt_apb4_pprot_i                       ),
    .hxt_apb4_prdata_i                       (hxt_apb4_prdata_o                      ),
    .hxt_apb4_pready_i                       (hxt_apb4_pready_o                      ),
    .hxt_apb4_pslverr_i                      (hxt_apb4_pslverr_o                     )
);
// Debug Logic 

img_frame_src #(
    .W          (IMG_W),
    .H          (IMG_H),
    .IDLE_CYCLE (1000000)
) u_img_frame_src (
    .clk       (tl_clk_user     ),
    .rst       (power_on_rst_dly),
    .enable    (img_enable      ),
    .trigger   (img_trigger     ),
    // T07：one-shot 捕获停止点——推帧引擎 claim 后冻结发生器，release 后放开
    .hold      (w_push_fb_hold  ),
    .rd_addr   (img_fb_raddr    ),
    .rd_data   (img_fb_rdata    ),
    // fb 唯一读口的仲裁：主机预取 vs DMA（DDR 搬运 / 推帧 ERAM 源）
    // （见本文件头部与 img_frame_src 头部；两个 DMA 消费者在这里按源二选一）
    .host_rd_prio (img_host_rd_prio ),
    .dma_rd_req   (img_fb_dma_req   ),
    .host_grant   (img_host_grant   ),
    .dma_grant    (img_dma_grant    ),
    .rd2_addr     (img_fb_dma_addr  ),
    .rd2_data     (img_fb_rd2_data  ),
    .dbg_rd_idx(img_dbg_idx ),
    .frame_cnt (img_frame_cnt   ),
    .width     (img_width       ),
    .height    (img_height      ),
    .data_len  (img_data_len    ),
    .ready     (img_ready       ),
    .busy      (img_busy        )
);

assign  ubus_bken_logic = ubus_bken_logic_dly ;
assign  ubus_rdata_logic= ubus_rdata_logic_dly;

always@(posedge tl_clk_user or posedge power_on_rst_dly )
begin
    if(power_on_rst_dly)begin
        ubus_wen_logic_dly   <= 'd0 ;
        ubus_waddr_logic_dly <= 'd0 ;
        ubus_wdata_logic_dly <= 'd0 ;
        ubus_ren_logic_dly   <= 'd0 ;
        ubus_raddr_logic_dly <= 'd0 ;
    end else begin
        ubus_wen_logic_dly   <= ubus_wen_logic   ;
        ubus_waddr_logic_dly <= ubus_waddr_logic ;
        ubus_wdata_logic_dly <= ubus_wdata_logic ;
        ubus_ren_logic_dly   <= ubus_ren_logic   ;
        ubus_raddr_logic_dly <= ubus_raddr_logic ;
    end
end 

always@(posedge tl_clk_user or posedge power_on_rst_dly )
begin
    if( power_on_rst_dly )
        ubus_bken_logic_dly <= 1'b0;
    else 
        ubus_bken_logic_dly  <= ubus_bken_logic_dly  ? 1'b0 : 
                                ubus_ren_logic_dly   ? 1'b1 : ubus_bken_logic_dly;
end

always@(posedge tl_clk_user or posedge power_on_rst_dly )
begin
    if( power_on_rst_dly ) begin
        ltssm_reg <= 5'd0;
        ltssm_reg_dly <= 5'd0;
    end
    else begin 
        ltssm_reg <= tl_ltssm;
        ltssm_reg_dly <= ltssm_reg;
    end
end

always@(posedge tl_clk_user or posedge power_on_rst_dly )
begin
    if( power_on_rst_dly ) 
        ltssm_change_cnt <= 5'd0;
    else if( ltssm_reg != ltssm_reg_dly )
        ltssm_change_cnt <= ltssm_change_cnt + 1'b1;
end

always@(posedge tl_clk_user or posedge power_on_rst_dly )
begin
    if( power_on_rst_dly ) begin
        ltssm_debug[0]  <= 5'b0;
        ltssm_debug[1]  <= 5'b0;
        ltssm_debug[2]  <= 5'b0;
        ltssm_debug[3]  <= 5'b0;
        ltssm_debug[4]  <= 5'b0;
        ltssm_debug[5]  <= 5'b0;
        ltssm_debug[6]  <= 5'b0;
        ltssm_debug[7]  <= 5'b0;
        ltssm_debug[8]  <= 5'b0;
        ltssm_debug[9]  <= 5'b0;
        ltssm_debug[10] <= 5'b0;
        ltssm_debug[11] <= 5'b0;
        ltssm_debug[12] <= 5'b0;
        ltssm_debug[13] <= 5'b0;
        ltssm_debug[14] <= 5'b0;
        ltssm_debug[15] <= 5'b0;
        ltssm_debug[16] <= 5'b0;
        ltssm_debug[17] <= 5'b0;
        ltssm_debug[18] <= 5'b0;
        ltssm_debug[19] <= 5'b0;
    end else if( ltssm_reg != ltssm_reg_dly) begin
        ltssm_debug[ltssm_change_cnt] <= ltssm_reg_dly;
    end
end

// read logic
always@(posedge tl_clk_user or posedge power_on_rst_dly )
begin
    if( power_on_rst_dly) begin 
        rd_data0 <= 32'd0;
        rd_data1 <= 32'd0;
        rd_data2 <= 32'd0;
        rd_data3 <= 32'd0;
        ubus_rdata_logic_dly <= 32'd0;
    end else begin 
        rd_data0             <= {27'b0,tl_ltssm[4:0]};
        rd_data1             <= {pl_link_up,11'd0,tl_clk_locked,3'b0,16'd0};
        rd_data2             <= {23'b0,9'd0};
        rd_data3             <= {5'd0,tl_cfg_max_read_request_size[2:0],5'd0,tl_cfg_max_payload_size[2:0],
                                 5'd0,tl_cfg_current_link_speed[2:0],   4'd0,tl_cfg_negotiated_width[3:0]};
        case(ubus_raddr_logic_dly[7:0])
            8'd0 : ubus_rdata_logic_dly <= rd_data0;
            8'd1 : ubus_rdata_logic_dly <= rd_data1;
            8'd2 : ubus_rdata_logic_dly <= rd_data2;
            8'd3 : ubus_rdata_logic_dly <= rd_data3;
            8'd4 : ubus_rdata_logic_dly <= rd_data3;
            8'd5 : ubus_rdata_logic_dly <= rd_data3;
            8'd6 : ubus_rdata_logic_dly <= ltssm_change_cnt;
            8'd10: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[0]};
            8'd11: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[1]};
            8'd12: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[2]};
            8'd13: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[3]};
            8'd14: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[4]};
            8'd15: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[5]};
            8'd16: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[6]};
            8'd17: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[7]};
            8'd18: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[9]};
            8'd19: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[10]};
            8'd20: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[11]};
            8'd21: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[12]};
            8'd22: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[13]};
            8'd23: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[14]};
            8'd24: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[15]};
            8'd25: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[16]};
            8'd26: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[17]};
            8'd27: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[18]};
            8'd28: ubus_rdata_logic_dly <= {27'b0,ltssm_debug[19]};
        default:;
        endcase
    end
end
//write logic

always@(posedge tl_clk_user or negedge pcie_power_on_rst_reg )
begin
    if(!pcie_power_on_rst_reg )begin
        pcie_power_on_rst_uart <= 1'b0;
    end else begin                        
    if(ubus_wen_logic_dly == 1'b1 && ubus_waddr_logic_dly[7:0] == 8'd0)
        pcie_power_on_rst_uart <= ubus_wdata_logic_dly[0];
    end
end

assign  debug_led[0] = power_on_rst_dly;
assign  debug_led[1] = pl_link_up;
assign  debug_led[2] = tl_clk_locked;
assign  debug_led[3] = ltssm_reg_dly[4];
//assign  debug_led[4] = ltssm_reg_dly[3];
//assign  debug_led[5] = ltssm_reg_dly[2];
//assign  debug_led[6] = ltssm_reg_dly[1];
//assign  debug_led[7] = ltssm_reg_dly[0];


// ====================================================================
//  摄像头通路（本移植新增）：2x IMX415 + MIPI CSI-2 软 PHY
//  说明：本步只把“传感器是否起来”通过 PCIe 寄存器暴露出来（0x80~0x94），
//        跨时钟域：慢变电平 + toggle 计数（状态字），像素走各 writer 内部的异步 FIFO。
// ====================================================================
    // ====================================================================
    //  传感器 MCLK（12.5MHz）+ 上电 / 重触发时序
    //
    //  为什么是 12.5MHz（本机上板实测，见本次提交说明）：
    //    · 25MHz（62.5MHz ÷ 2.5 分数分频）    → A 路字节时钟不跳、lane_valid=0、无帧
    //    · 25MHz（50MHz sys_clk ÷ 2，占空 50%）→ 同样不锁（两个独立源都是 25MHz）
    //    · 12.5MHz                                  → 字节时钟跳动、lane_valid=0xf、
    //                                                  约 14.5fps 出帧（链路正常）
    //  参考工程 f9p_imx415x2_top.v:92-98 用 50MHz÷2 = 25MHz，而且两边的 201 条
    //  寄存器表逐字节相同（ui_imx415_reg.v 与参考工程 diff 为空），但本板实测
    //  25MHz 就是不锁——所以本工程改回 12.5MHz。
    //
    //  MCLK = 62.5MHz(tl_clk_user) ÷ 5 = 12.5MHz（半周期 2/3 拍交替 → 周期恒
    //         80ns、占空 40/60）：板上实测能锁、能出帧的就是这一档。
    //  CTRL[2] 现在只当「重触发」用：电平一变 → XCLR 再拉低 134ms → 放开后
    //         重写整张 201 条寄存器表。它原来还兼作 MCLK 源选择（另一档是
    //         50MHz sys_clk ÷ 4），那一档已删，原因见下面 (b) 段。
    // ====================================================================
    wire       w_mclk_sel_raw = img_pattern[0];          // = CTRL[2]

    // CTRL 写在 ep_bar_win.v 里会被解成多拍，期间 img_pattern 会有 1~2 拍的毛刺
    // （实测：同一笔 CTRL 写会造成 2 次模式变化）；按“连续 16 拍相同才认”去抖，
    // 否则一次 CTRL 写会把 XCLR 反复拉低、重触发连跑好几遍。
    reg [15:0] r_sel_sr     = 16'd0;
    reg        r_mclk_sel_f = 1'b0;      // 去抖后的 CTRL[2]（重触发位；名字沿用旧名）
    always @(posedge tl_clk_user) begin
        r_sel_sr <= {r_sel_sr[14:0], w_mclk_sel_raw};
        if (&r_sel_sr)       r_mclk_sel_f <= 1'b1;       // 连续 16 拍为 1
        else if (~|r_sel_sr) r_mclk_sel_f <= 1'b0;       // 连续 16 拍为 0
    end

    // 慢复位：MCLK 先跑，~134ms 后放开 XCLR 并启动 I2C
    //   CTRL[2] 一变就重走一遍（重触发配置：XCLR 再拉低 → 放开 → 重写整张 201 条表）
    reg [22:0] r_pwr_cnt2   = 23'd0;
    reg        r_rst_n_slow = 1'b0;
    reg        r_mclk_sel_d = 1'b0;      // 上一拍的选择位（检测变化）
    reg [3:0]  r_reinit_cnt = 4'd0;      // 重触发次数（诊断）
    wire       w_sel_chg    = (r_mclk_sel_f != r_mclk_sel_d);
    always @(posedge tl_clk_user) begin
        r_mclk_sel_d <= r_mclk_sel_f;
        if (w_sel_chg) begin
            r_pwr_cnt2   <= 23'd0;       // 重新计时 = XCLR 再拉低 134ms
            r_rst_n_slow <= 1'b0;
            if (r_reinit_cnt != 4'hF) r_reinit_cnt <= r_reinit_cnt + 1'b1;
        end else if (r_pwr_cnt2 != 23'h7FFFFF) begin
            r_pwr_cnt2   <= r_pwr_cnt2 + 1'b1;
            r_rst_n_slow <= 1'b0;
        end else begin
            r_rst_n_slow <= 1'b1;
        end
    end

    // CSI 接收器复位：上电计数器一走就放开（原先漏声明 → TD 当悬空网络 → PHY 常复位）
    reg        r_rst_n      = 1'b0;
    always @(posedge tl_clk_user) r_rst_n <= (r_pwr_cnt2 > 23'd1000);

    // ---- (a) 62.5MHz → 12.5MHz（旧分频器：acc+2、>=5 时 -3 并翻转，默认）----
    //   半周期 2/3 拍交替 → 输出周期恒 80ns、瞬时占空 40/60（无周期抖动）
    reg [2:0] r_macc     = 3'd0;
    reg       r_mclk_125 = 1'b0;
    always @(posedge tl_clk_user) begin
        if (r_macc >= 3'd5) begin
            r_macc     <= r_macc - 3'd3;      // 等价 (acc+2)-5
            r_mclk_125 <= ~r_mclk_125;
        end else begin
            r_macc     <= r_macc + 3'd2;
        end
    end

    // ---- (b) 已删除：原来的「50MHz sys_clk ÷ 4 = 12.50MHz」那一档 ----
    //   它与 (a) 同频（都是 12.5MHz），唯一区别是占空 50%、周期零抖动；板上从未
    //   选中过（CTRL[2] 默认 0，实测靠 (a) 锁定出帧）。但它一存在，sys_clk 这个
    //   50MHz 输入就必须进通用时钟网络：实测该网（sys_clk_dup_1）走本地绕线，
    //   根就是 H4 那个球，扇出两只挂 r_mdiv2 与 r_mclk_c125，STA 里被算成 local
    //   clock、也没有全局缓冲（DRC RTCLK-5079 / check_timing 的 local clock /
    //   RTCLK-5078 那一类风险）。删掉后 sys_clk 只做 PCIe PLL 的参考时钟，
    //   MCLK 恒等于 (a) 的 12.5MHz，即板上已验证的那一档。
    wire w_mclk = r_mclk_125;

    // 诊断：img_pattern 历史出现过哪些取值（确认 CTRL 写的毛刺，见 0x80[15:12]）
    reg [3:0] r_mode_hits = 4'd0;
    always @(posedge tl_clk_user) begin
        if (img_pattern == 2'd0) r_mode_hits[0] <= 1'b1;
        if (img_pattern == 2'd1) r_mode_hits[1] <= 1'b1;
        if (img_pattern == 2'd2) r_mode_hits[2] <= 1'b1;
        if (img_pattern == 2'd3) r_mode_hits[3] <= 1'b1;
    end

    assign cam_a_mclk   = w_mclk;
    assign cam_b_mclk   = w_mclk;
    assign cam_a_xclr_n = r_rst_n_slow;
    assign cam_b_xclr_n = r_rst_n_slow;

    // IDELAY tap：参考工程实测 45~47 眼图最好（自动扫描会落到 32，误码很高）
    localparam        USE_MANUAL_TAP = 1'b1;
    localparam [5:0]  CAM_IDELAY_TAP = 6'd46;

    wire [5:0]  w_a_delay_tap, w_b_delay_tap;
    wire        w_a_delay_done, w_b_delay_done;
    wire        w_a_byte_clk, w_b_byte_clk;
    wire        w_a_rst_out, w_b_rst_out;
    wire [3:0]  w_a_lane_valid, w_b_lane_valid;
    wire        w_a_sync_wait, w_b_sync_wait, w_a_pkt_done, w_b_pkt_done;
    wire        w_a_vsync, w_b_vsync, w_a_in_frame, w_b_in_frame;
    wire        w_a_in_line, w_b_in_line;
    wire [39:0] w_a_pixel, w_b_pixel;
    wire        w_a_pixel_valid, w_b_pixel_valid;
    wire        w_a_cfg_done, w_b_cfg_done, w_a_bus_err, w_b_bus_err;
    wire [8:0]  w_a_cfg_idx;   wire w_a_cfg_busy;
    wire        w_a_ae_done, w_b_ae_done;
    wire        w_a_bclk_tgl, w_b_bclk_tgl;

    mipi_csi2_rx_ph1p_checked #(
        .LANE_NUM (4),
        // 合成/诊断几何：正式 RAW10 1080p 几何与 WC/行数约束在 T11 包按板测标定；
        // 本包不把 0 说成「已验证几何」，只把判坏/计数接出来。
        .IMAGE_DT (6'h2b), .IMAGE_WC (16'd0), .EXPECTED_LINES (16'd0), .VC_ID (2'd0)
    ) u_csi_a (
        .I_ref_clk          (tl_clk_user),
        .I_rst_n            (r_rst_n    ),
        .I_rx_en            (r_rst_n    ),
        .I_clk_pad_hs_p     (mipi_a_clk_hs_p ),
        .I_clk_pad_hs_n     (mipi_a_clk_hs_n ),
        .I_data_pad_hs_p    (mipi_a_data_hs_p),
        .I_data_pad_hs_n    (mipi_a_data_hs_n),
        .I_manual_delay     (cam_tap_cfg[5:0]),
        .I_manual_en        (cam_tap_cfg[6]),
        .O_byte_clk         (w_a_byte_clk),
        .O_rst_out          (w_a_rst_out ),
        .O_lane_valid       (w_a_lane_valid),
        .O_delay_tap        (w_a_delay_tap),
        .O_auto_delay_done  (w_a_delay_done),
        .O_sync_wait        (w_a_sync_wait),
        .O_packet_done      (w_a_pkt_done),
        .O_vsync            (w_a_vsync),
        .O_in_frame         (w_a_in_frame),
        .O_in_line          (w_a_in_line),
        .O_pixel_data       (w_a_pixel),
        .O_pixel_valid      (w_a_pixel_valid),
        // T07：整帧裁决与诊断
        .O_frame_end        (w_a_frame_end),
        .O_frame_good       (w_a_frame_good),
        .O_frame_abort      (w_a_frame_abort),
        .O_crc_errors       (w_a_crc_err),
        .O_header_errors    (w_a_hdr_err),
        .O_packet_timeouts  (w_a_pkt_to),
        .O_frame_timeouts   (w_a_frm_to),
        .O_good_frames      (w_a_good_frm),
        .O_bad_frames       (w_a_bad_frm),
        .O_last_wc          (w_a_last_wc),
        .O_last_lines       (w_a_last_lines),
        .O_payload_out      (w_a_payload),
        .O_payload_keep     (w_a_keep),
        .O_payload_valid    (w_a_payload_v)
    );

    mipi_csi2_rx_ph1p_checked #(
        .LANE_NUM (4),
        .IMAGE_DT (6'h2b), .IMAGE_WC (16'd0), .EXPECTED_LINES (16'd0), .VC_ID (2'd0)
    ) u_csi_b (
        .I_ref_clk          (tl_clk_user),
        .I_rst_n            (r_rst_n    ),
        .I_rx_en            (r_rst_n    ),
        .I_clk_pad_hs_p     (mipi_b_clk_hs_p ),
        .I_clk_pad_hs_n     (mipi_b_clk_hs_n ),
        .I_data_pad_hs_p    (mipi_b_data_hs_p),
        .I_data_pad_hs_n    (mipi_b_data_hs_n),
        .I_manual_delay     (cam_tap_b_cfg[5:0]),
        .I_manual_en        (cam_tap_b_cfg[6]),
        .O_byte_clk         (w_b_byte_clk),
        .O_rst_out          (w_b_rst_out ),
        .O_lane_valid       (w_b_lane_valid),
        .O_delay_tap        (w_b_delay_tap),
        .O_auto_delay_done  (w_b_delay_done),
        .O_sync_wait        (w_b_sync_wait),
        .O_packet_done      (w_b_pkt_done),
        .O_vsync            (w_b_vsync),
        .O_in_frame         (w_b_in_frame),
        .O_in_line          (w_b_in_line),
        .O_pixel_data       (w_b_pixel),
        .O_pixel_valid      (w_b_pixel_valid),
        .O_frame_end        (w_b_frame_end),
        .O_frame_good       (w_b_frame_good),
        .O_frame_abort      (w_b_frame_abort),
        .O_crc_errors       (w_b_crc_err),
        .O_header_errors    (w_b_hdr_err),
        .O_packet_timeouts  (w_b_pkt_to),
        .O_frame_timeouts   (w_b_frm_to),
        .O_good_frames      (w_b_good_frm),
        .O_bad_frames       (w_b_bad_frm),
        .O_last_wc          (w_b_last_wc),
        .O_last_lines       (w_b_last_lines),
        .O_payload_out      (w_b_payload),
        .O_payload_keep     (w_b_keep),
        .O_payload_valid    (w_b_payload_v)
    );



    ui_cfg_imx415 #(.CLK_DIV(16'd624)) u_cfg_a (
        .I_clk         (tl_clk_user   ),
        .I_rst_n       (r_rst_n_slow  ),
        .I_cam_mode    (2'd1          ),   // 1 = 4K
        .I_ae_req      (1'b0          ),
        .I_ae_data     (8'd100        ),
        .O_cam_scl     (cam_a_scl     ),
        .IO_cam_sda    (cam_a_sda     ),
        .O_cfg_done    (w_a_cfg_done  ),
        .O_ae_cfg_done (w_a_ae_done   ),
        .O_bus_error   (w_a_bus_err   ),
        .O_dbg_idx     (w_a_cfg_idx   ),
        .O_dbg_busy    (w_a_cfg_busy  )
    );

    ui_cfg_imx415 #(.CLK_DIV(16'd624)) u_cfg_b (
        .I_clk         (tl_clk_user   ),
        .I_rst_n       (r_rst_n_slow  ),
        .I_cam_mode    (2'd1          ),
        .I_ae_req      (1'b0          ),
        .I_ae_data     (8'd100        ),
        .O_cam_scl     (cam_b_scl     ),
        .IO_cam_sda    (cam_b_sda     ),
        .O_cfg_done    (w_b_cfg_done  ),
        .O_ae_cfg_done (w_b_ae_done   ),
        .O_bus_error   (w_b_bus_err   )
    );

    // ---- 诊断：I2C 两根线电平 ----
    //   （原来这里还有一个 always @(posedge sys_clk) 的 r_syscnt 计数器，用来验证
    //     sys_clk 在不在跳；它只写不读、状态字里没有它，综合时已被优化成 0 个
    //     触发器。这里一并删掉，免得以后有人把它接出去、又把 sys_clk 拽回通用
    //     时钟网络。）
    reg [2:0] s_a_scl, s_a_sda, s_b_scl, s_b_sda;
    always @(posedge tl_clk_user) begin
        s_a_scl <= {s_a_scl[1:0], cam_a_scl};
        s_a_sda <= {s_a_sda[1:0], cam_a_sda};
        s_b_scl <= {s_b_scl[1:0], cam_b_scl};
        s_b_sda <= {s_b_sda[1:0], cam_b_sda};
    end

    // ---- I2C 是否至少 NACK 过一次（粘滞，重触发时清零）----
    //   ui_i2c 的 O_iic_bus_error 是「当前这笔没 ACK」的瞬时标志，iic_req 一撤就被清，
    //   事后读它等于没读（所以 B 路状态字的 bus_err=0 证明不了 B 上有摄像头）。
    //   这里各自粘滞一位：置上就说明这一路的 I2C 至少有一次没等到 ACK。
    reg r_a_i2c_nack = 1'b0, r_b_i2c_nack = 1'b0;
    always @(posedge tl_clk_user) begin
        if (w_sel_chg) begin r_a_i2c_nack <= 1'b0; r_b_i2c_nack <= 1'b0; end
        else begin
            if (w_a_bus_err) r_a_i2c_nack <= 1'b1;
            if (w_b_bus_err) r_b_i2c_nack <= 1'b1;
        end
    end

    // ---- I2C 状态机进度（跨到 tl 域只做电平同步，慢变量）----
    reg  [8:0] w_a_i2c_idx;   reg w_a_i2c_busy;
    always @(posedge tl_clk_user) begin w_a_i2c_idx <= w_a_cfg_idx; w_a_i2c_busy <= w_a_cfg_busy; end

    // ---- 字节时钟在不在跑 ----
    clk_activity #(.DIV_BITS(15)) u_a_clk_act (.I_clk(w_a_byte_clk), .I_rst_n(w_a_rst_out), .O_tgl(w_a_bclk_tgl));
    clk_activity #(.DIV_BITS(15)) u_b_clk_act (.I_clk(w_b_byte_clk), .I_rst_n(w_b_rst_out), .O_tgl(w_b_bclk_tgl));

    // ---- 字节域 → tl_clk_user 域：vsync / pixel_valid 边沿做成 toggle 再数 ----
    reg a_vs_tgl = 1'b0, b_vs_tgl = 1'b0, a_pv_tgl = 1'b0, b_pv_tgl = 1'b0;
    reg a_vs_d = 1'b0, b_vs_d = 1'b0, a_pv_d = 1'b0, b_pv_d = 1'b0;
    always @(posedge w_a_byte_clk or negedge w_a_rst_out) begin
        if (!w_a_rst_out) begin a_vs_tgl <= 1'b0; a_pv_tgl <= 1'b0; a_vs_d <= 1'b0; a_pv_d <= 1'b0; end
        else begin
            a_vs_d <= w_a_vsync;   if (w_a_vsync   & ~a_vs_d) a_vs_tgl <= ~a_vs_tgl;
            a_pv_d <= w_a_pixel_valid; if (w_a_pixel_valid & ~a_pv_d) a_pv_tgl <= ~a_pv_tgl;
        end
    end
    always @(posedge w_b_byte_clk or negedge w_b_rst_out) begin
        if (!w_b_rst_out) begin b_vs_tgl <= 1'b0; b_pv_tgl <= 1'b0; b_vs_d <= 1'b0; b_pv_d <= 1'b0; end
        else begin
            b_vs_d <= w_b_vsync;   if (w_b_vsync   & ~b_vs_d) b_vs_tgl <= ~b_vs_tgl;
            b_pv_d <= w_b_pixel_valid; if (w_b_pixel_valid & ~b_pv_d) b_pv_tgl <= ~b_pv_tgl;
        end
    end

    // ---- tl_clk_user 域：同步 + 计数 + 状态字 ----
    reg [2:0]  s_a_vs, s_b_vs, s_a_pv, s_b_pv, s_a_tgl, s_b_tgl;
    reg [3:0]  s_a_lane, s_b_lane;
    reg [5:0]  s_a_tap, s_b_tap;
    reg [2:0]  s_a_cfg, s_b_cfg;
    reg [31:0] r_a_frames = 32'd0, r_b_frames = 32'd0, r_a_pix = 32'd0, r_b_pix = 32'd0;
    reg        r_a_bclk_seen = 1'b0, r_b_bclk_seen = 1'b0;
    reg        r_a_pv_seen = 1'b0, r_b_pv_seen = 1'b0;

    always @(posedge tl_clk_user) begin
        s_a_vs   <= {s_a_vs[1:0],   a_vs_tgl};
        s_b_vs   <= {s_b_vs[1:0],   b_vs_tgl};
        s_a_pv   <= {s_a_pv[1:0],   a_pv_tgl};
        s_b_pv   <= {s_b_pv[1:0],   b_pv_tgl};
        s_a_tgl  <= {s_a_tgl[1:0],  w_a_bclk_tgl};
        s_b_tgl  <= {s_b_tgl[1:0],  w_b_bclk_tgl};
        s_a_lane <= w_a_lane_valid;
        s_b_lane <= w_b_lane_valid;
        s_a_tap  <= w_a_delay_tap;
        s_b_tap  <= w_b_delay_tap;
        s_a_cfg  <= {w_a_bus_err, w_a_delay_done, w_a_cfg_done};
        s_b_cfg  <= {w_b_bus_err, w_b_delay_done, w_b_cfg_done};

        if (s_a_vs[2] ^ s_a_vs[1]) r_a_frames <= r_a_frames + 32'd1;
        if (s_b_vs[2] ^ s_b_vs[1]) r_b_frames <= r_b_frames + 32'd1;
        if (s_a_pv[2] ^ s_a_pv[1]) begin r_a_pix <= r_a_pix + 32'd1; r_a_pv_seen <= 1'b1; end
        if (s_b_pv[2] ^ s_b_pv[1]) begin r_b_pix <= r_b_pix + 32'd1; r_b_pv_seen <= 1'b1; end
        if (s_a_tgl[2] ^ s_a_tgl[1]) r_a_bclk_seen <= 1'b1;
        if (s_b_tgl[2] ^ s_b_tgl[1]) r_b_bclk_seen <= 1'b1;
    end

    // 状态字：bit0 字节时钟在跑 | [4:1] lane_valid | 5 cfg_done | 6 bus_err
    //         7 auto_delay_done | 8 in_frame | 9 in_line | 10 收到过像素
    //         bit15 = 相机直通通路丢过组/标记（cam_ddr_writer.dbg_anomaly，只增不减）
    //         [14:11] img_pattern={CTRL[3:2] 的取值历史，含 CTRL[2]=重触发}
    //         [11]    = 当前 AXI 写口授权给哪一路（0 = A，1 = B；ddr_wr_arb 的 grant）
    //                            历史出现过的取值（每出现一次置 1 位，只增不减，诊断 CTRL 写的毛刺）
    //         [15] = **B 路 I2C 曾经没等到 ACK**（粘滞，重触发清零）—— 用来区分
    //                「B 口上根本没摄像头 / 地址型号不对」与「有摄像头但链路没锁」
    //         [21:16] tap | 22 xclr 已放开 | 23 csi_rst_n | 24/25 SCL/SDA 电平 | [31:26]=110011
    //  其中原来紧跟 s_a_tap 的那个保留 0（bit15）现在放「相机 4K 直通通路是否丢过
    //  像素组/标记」（cam_ddr_writer 的 dbg_anomaly，只增不减）：一眼就能看出
    //  是不是 FIFO 满导致的丢帧，不用再去读别的寄存器。
    wire [31:0] w_cam_a_stat = {6'b110011, s_a_sda[2], s_a_scl[2], r_rst_n, r_rst_n_slow,
                                s_a_tap, w_camddr_anom, r_mode_hits, r_a_pv_seen, w_a_in_line, w_a_in_frame,
                                s_a_cfg[1], s_a_cfg[2], s_a_cfg[0], s_a_lane, r_a_bclk_seen};
    wire [31:0] w_cam_b_stat = {6'b110011, s_b_sda[2], s_b_scl[2], r_rst_n, r_rst_n_slow,
                                s_b_tap, 3'd0, w_wr_grant, r_b_i2c_nack, r_b_pv_seen,
                                w_b_in_line, w_b_in_frame,
                                s_b_cfg[1], s_b_cfg[2], s_b_cfg[0], s_b_lane, r_b_bclk_seen};
    //  0x98 中段 8 位（由原来的 8'd0 改成诊断位）：
    //   [8:5] r_reinit_cnt | [4] 去抖后的 CTRL[2] | [3] A 路 I2C 曾 NACK | [2] r_rst_n_slow(XCLR)
    //   | [1] 0
    //  [255:224] 原来是保留 0，现在放相机直通通路的诊断字（0xD0 读它）：
    //    {lines_per_frame[15:0], max_grp_per_line[15:0]}
    assign w_cam_stat = {{w_camddr_lines, w_camddr_grp},
                         {r_pwr_cnt2, r_reinit_cnt, r_mclk_sel_f, r_a_i2c_nack, r_rst_n_slow, 1'b0, w_a_i2c_busy},
                              r_b_pix, r_a_pix, r_b_frames, r_a_frames,
                              w_cam_b_stat, w_cam_a_stat};

    // 串口接收不用了（管脚让给摄像头）


// ====================================================================
//  DDR3 控制器（al_ip/ddr3_mc_0，本移植新增）
//
//  ★ 本步只接「参考时钟 + 复位 + 颗粒引脚」，用户侧（AXI / 调试 APB / 用户刷新）
//    全部静态化，不接任何主设备。
//
//  (1) 参考时钟 ref_clk = sys_clk
//      板上给 FPGA 的那颗 50MHz 单端时钟就是 H4；IP 生成时按 PH1P_REFCLK_TYPE=SINGLE、
//      PH1P_SYSCLK_LOC=H4 配置，所以接 IP 的单端 ref_clk 一路（IP 没有差分 ref_clk 端口，
//      wrapper 端口表见 al_ip/ddr3_mc_0/.ports_ddr3_mc_0.txt:1 `ref_clk; 1`）。
//      H4 的引脚约束一直在本工程里（constraints/ph1p_pcie_case_ep.adc:17，SSTL135），
//      IP 自己不给 refclk 写引脚约束（src/adc/ddr3_mc_0.adc 里没有 ref_clk / refclks 条目），
//      所以这条网同时喂 PCIe 的 u_pcie_pll_ep 和本 IP，不冲突。
//      IPUG034 §2.1.3 建议参考时钟与 AC 信号同 Bank：H4 在 BANK33 = 本 IP 的 AC bank。
//
//  (2) 复位 sys_rst_n（低有效）= pcie_power_on_rst
//      即板上 SW7 那颗复位按钮所在的球 R14，低有效。依据：厂商 DDR 例程 example_top 的
//      sys_rst_n 就是同一个球（09_ddr3_ddrmc_cal_x32_1066mbps/prj_src/adc/ap115v2.adc:5
//      `sys_rst_n R14 LVCMOS33 PULLUP`，注释写着 SW7）；本工程该球已由
//      constraints/ph1p_pcie_case_ep.adc 分配给 pcie_power_on_rst。
//      刻意不取 power_on_rst_dly / tl_rst_user：那两条与 PCIe 链路状态耦合
//      （pcie_mperst、pcie_pll_locked、tl_ltssm），主机每次 PERST / 重新枚举都会把
//      DDR 拉回复位、白跑一遍初始化与训练。
//
//  (3) 颗粒引脚：从 IP 端口直连到顶层端口，中间不插任何逻辑（IPUG034 §3.3.1 的
//      IO 分配规则；厂商例程同样直连）。1 位信号按厂商例程写成标量，
//      实测该例程的 place 报告里顶层端口 `ddr_ck_p` 就落在 H3/DIFF_SSTL135
//      （09 例程 ph1p_ddr_Runs/phy_1/ph1p_ddr_phy.area:67），说明 IP 的
//      set_ippin_assignment 能派生出顶层管脚。
//
//  (4) 用户侧静态化：
//      · AXI：本设计是主（IP 是从），aw/ar/w 的 valid 与 wlast 恒 0 → IP 收不到任何
//        读写命令；bready/rready 取常数 1（无命令即无响应，取 1 不会产生任何事务）。
//        axi_aclk = dhi_clk、axi_aresetn = ddrphy_rst_n：都是 IP 自己输出的用户侧
//        总线时钟/复位（IPUG034 表 2-1：dhi_clk「DHI 总线的时钟输出」、ddrphy_rst_n
//        「DDRPHY 复位信号输出」）。这样 DDR 用户侧自成一个时钟域，不引入新时钟、
//        也不与 tl_clk_user 打交道。
//      · 调试 APB：本步不读校准状态 → psel/penable/pwrite/paddr/pwdata 全置 0；
//        apb_prst_n = cfg_rst_n（与 apb_pclk = cfg_clk 同域）。
//      · 用户刷新：usr_ref_type = 2'b00（IPUG034 表 2-19：00 = 正常 tREFI 自动刷新），
//        usr_ref_req = 1'b0（不请求用户刷新）。
//      · ecc_err_*、ctl_ram_* 等输出本步不使用，留空（与厂商例程
//        ddrmc_test_top 的接法一致）。
//
//  (5) 【本步新增】用户侧 AXI 写通道接相机整帧搬运（整帧搬进 DDR3）：
//      · 写通道（aw/w/b）从「常量 0」改成 ddr_wr_arb 的输出，客户机是 A/B 两片
//        cam_ddr_writer；
//        读通道仍完全不接（arvalid=0，rready=1）。
//      · ddrphy_rdy 接出来当 DDR_STATUS.bit4（校准完成）—— 板子上一眼就能看出
//        DDR 到底有没有起来，比只看握手卡住强。
//      · cam_ddr_writer 的片内侧时钟/复位是 tl_clk_user / power_on_rst_dly，
//        AXI 侧是 dhi_clk / ddrphy_rst_n，跨域全部走异步 FIFO + 2 级同步器
//        （见 rtl/ep_side/ddr/cam_ddr_writer.v 头部）。
// ====================================================================
// 注意：IP 的 apb_pclk 与 cfg_clk 是同一个物理时钟的两个输出端口，
//       不能同时接到一条 wire（会变成双驱动），这里只取 cfg_clk 一路。
wire w_ddr_cfg_clk   ;   // cfg_clk = IP 的 mcu/APB 域时钟（50MHz）
wire w_ddr_cfg_rst_n ;   // cfg_clk 域复位，用作 apb_prst_n
wire w_ddr_dhi_clk   ;   // 用户总线时钟（= 未来的 AXI 主时钟）
wire w_ddrphy_rst_n  ;   // IP 给用户逻辑的复位

ddr3_mc_0 u_ddr3_mc_0 (
    .ref_clk        (sys_clk             ),
    .sys_rst_n      (pcie_power_on_rst   ),

    .apb_pclk       (                    ),   // 与 cfg_clk 同源，见上方说明
    .apb_prst_n     (w_ddr_cfg_rst_n     ),
    .apb_pready     (                    ),
    .apb_psel       (1'b0                ),
    .apb_penable    (1'b0                ),
    .apb_pwrite     (1'b0                ),
    .apb_paddr      (16'd0               ),
    .apb_pwdata     (32'd0               ),
    .apb_prdata     (                    ),

    .dhi_clk        (w_ddr_dhi_clk       ),
    .cfg_clk        (w_ddr_cfg_clk       ),
    .cfg_rst_n      (w_ddr_cfg_rst_n     ),
    .ddrphy_rst_n   (w_ddrphy_rst_n      ),
    .ddrphy_rdy     (w_ddrphy_rdy       ),

    .axi_aclk       (w_ddr_dhi_clk       ),
    .axi_aresetn    (w_ddrphy_rst_n      ),
    .axi_awid       (4'd0                ),
    .axi_awaddr     (w_ddr_awaddr        ),
    .axi_awlen      (w_ddr_awlen         ),
    .axi_awsize     (w_ddr_awsize        ),
    .axi_awburst    (w_ddr_awburst       ),
    .axi_awvalid    (w_ddr_awvalid       ),
    .axi_awready    (w_ddr_awready       ),
    .axi_wdata      (w_ddr_wdata         ),
    .axi_wstrb      (w_ddr_wstrb         ),
    .axi_wlast      (w_ddr_wlast         ),
    .axi_wvalid     (w_ddr_wvalid        ),
    .axi_wready     (w_ddr_wready        ),
    .axi_bid        (                    ),
    .axi_bresp      (w_ddr_bresp         ),
    .axi_bvalid     (w_ddr_bvalid        ),
    .axi_bready     (w_ddr_bready        ),
    .axi_arid       (w_ddr_arid         ),
    .axi_araddr     (w_ddr_araddr       ),
    .axi_arlen      (w_ddr_arlen        ),
    .axi_arsize     (w_ddr_arsize       ),
    .axi_arburst    (w_ddr_arburst      ),
    .axi_arvalid    (w_ddr_arvalid      ),
    .axi_arready    (w_ddr_arready      ),
    .axi_rid        (w_ddr_rid          ),
    .axi_rdata      (w_ddr_rdata        ),
    .axi_rresp      (w_ddr_rresp        ),
    .axi_rlast      (w_ddr_rlast        ),
    .axi_rvalid     (w_ddr_rvalid       ),
    .axi_rready     (w_ddr_rready       ),

    .usr_ref_type   (2'b00               ),
    .usr_ref_req    (1'b0                ),
    .usr_ref_ack    (                    ),
    .ecc_err_sig    (                    ),
    .ecc_err_mul    (                    ),
    .ctl_ram_rst_n  (                    ),
    .ctl_ram_cke    (                    ),

    .ddr_ck_p       (ddr_ck_p            ),
    .ddr_ck_n       (ddr_ck_n            ),
    .ddr_reset_n    (ddr_reset_n         ),
    .ddr_cke        (ddr_cke             ),
    .ddr_odt        (ddr_odt             ),
    .ddr_cs_n       (ddr_cs_n            ),
    .ddr_ras_n      (ddr_ras_n           ),
    .ddr_cas_n      (ddr_cas_n           ),
    .ddr_we_n       (ddr_we_n            ),
    .ddr_ba         (ddr_ba              ),
    .ddr_addr       (ddr_addr            ),
    .ddr_dqs_p      (ddr_dqs_p           ),
    .ddr_dqs_n      (ddr_dqs_n           ),
    .ddr_dq         (ddr_dq              ),
    .ddr_dm         (ddr_dm              )
);



// ====================================================================
//  相机正式通路：RAW10 → R10F v1（cam_r10f_writer ×2，A/B 各一片）
//
//  数据：CSI-2 字节时钟域的 4 像素组（40bit，checked CSI 输出）→ 偶数 ROI 裁剪
//        → 异步 FIFO → dhi_clk 域拼 packed RAW10 字节流 → R10F 内容
//        （128B 头 + 载荷 + 4KiB 对齐尾零）→ 每 4KB 一个 AXI4 突发写 DDR3。
//  触发：CTRL[5]（ddr_en）为 1 时两片都 armed（w_cam_ddr_want）。
//  两路：A 用 w_a_*，B 用 w_b_*；基址、握手字、诊断各一套
//        （A: 0xA0~0xAC / 0xD0，B: 0xE0~0xEC / 0xD8）。
//  写口：只有一个（u_ddr3_mc_0），由 ddr_wr_arb 在两路之间按突发轮流放行。
//  几何（板证前按“未板证”对待）：4K30 源按实际有效行取偶数 ROI：
//        W=1920、H=1080、x=960、有效图 y=540（物理行 = SKIP_ROWS(37)+540）；
//        Bayer 相位按物理原点奇偶推导，SRC_BAYER_PHASE 默认 0 仅占位（需板证）。
//  T07 的 8bit 灰度写者 cam_ddr_writer.v 保留在树中（供旧 TB/诊断参照），
//  正式顶层已改接本模块。
// ====================================================================
cam_r10f_writer #(
    .W           (CAMDDR_W          ),
    .H           (CAMDDR_H          ),
    .X0          (CAMDDR_X0         ),
    .Y0          (CAMDDR_Y0         ),
    .SKIP_ROWS   (CAMDDR_SKIP_ROWS  ),
    .BASE0       (DDR_CAM_BASE0     ),
    .BASE1       (DDR_CAM_BASE1     ),
    .FIFO_AW     (10                ),
    .BURST_BEATS (128               ),
    .CAMERA_ID   (8'd0              ),
    .SRC_BAYER_PHASE (2'd0          ),
    .MODE_ID     (32'd1             )
) u_cam_r10f_writer (
    .cam_clk       (w_a_byte_clk    ),
    .cam_rst_n     (w_a_rst_out     ),
    .cam_vsync     (w_a_vsync       ),
    .cam_in_frame  (w_a_in_frame    ),
    .cam_in_line   (w_a_in_line     ),
    .cam_pix       (w_a_pixel       ),
    .cam_pix_valid (w_a_pixel_valid ),
    .cam_frame_good(w_a_frame_good  ),
    .cam_frame_abort(w_a_frame_abort),
    .prot_en       (img_push_en     ),
    .rel_tgl0      (w_rel_tgl0      ),
    .rel_tgl1      (w_rel_tgl1      ),

    .clk_fb        (tl_clk_user       ),
    .rst_fb        (power_on_rst_dly ),
    .session_id    (w_tx_session_id   ),
    .wr_frame_seq  (w_camddr_seq      ),
    .wr_base       (w_camddr_base     ),
    .wr_status     (w_camddr_status   ),
    .wr_len        (w_camddr_len      ),

    .dbg_lines_per_frame  (w_camddr_lines),
    .dbg_max_grp_per_line (w_camddr_grp  ),
    .dbg_anomaly          (w_camddr_anom ),
    .dbg_drop             (w_camddr_drop_a ),

    .clk_ddr       (w_ddr_dhi_clk     ),
    .rst_ddr       (~w_ddrphy_rst_n   ),
    .ddr_cal_done  (w_ddrphy_rdy      ),
    .arm           (w_cam_ddr_want    ),
    .axi_busy      (w_camw_busy       ),

    .m_axi_awaddr  (w_camw_awaddr     ),
    .m_axi_awlen   (w_camw_awlen      ),
    .m_axi_awsize  (w_camw_awsize     ),
    .m_axi_awburst (w_camw_awburst    ),
    .m_axi_awvalid (w_camw_awvalid    ),
    .m_axi_awready (w_camw_awready    ),
    .m_axi_wdata   (w_camw_wdata      ),
    .m_axi_wstrb   (w_camw_wstrb      ),
    .m_axi_wlast   (w_camw_wlast      ),
    .m_axi_wvalid  (w_camw_wvalid     ),
    .m_axi_wready  (w_camw_wready     ),
    .m_axi_bresp   (w_camw_bresp      ),
    .m_axi_bvalid  (w_camw_bvalid     ),
    .m_axi_bready  (w_camw_bready     )
);

cam_r10f_writer #(
    .W           (CAMDDR_W          ),
    .H           (CAMDDR_H          ),
    .X0          (CAMDDR_X0         ),
    .Y0          (CAMDDR_Y0         ),
    .SKIP_ROWS   (CAMDDR_SKIP_ROWS  ),
    .BASE0       (DDR_CAM_B_BASE0   ),
    .BASE1       (DDR_CAM_B_BASE1   ),
    .FIFO_AW     (10                ),
    .BURST_BEATS (128               ),
    .CAMERA_ID   (8'd1              ),
    .SRC_BAYER_PHASE (2'd0          ),
    .MODE_ID     (32'd1             )
) u_cam_r10f_writer_b (
    .cam_clk       (w_b_byte_clk    ),
    .cam_rst_n     (w_b_rst_out     ),
    .cam_vsync     (w_b_vsync       ),
    .cam_in_frame  (w_b_in_frame    ),
    .cam_in_line   (w_b_in_line     ),
    .cam_pix       (w_b_pixel       ),
    .cam_pix_valid (w_b_pixel_valid ),
    .cam_frame_good(w_b_frame_good  ),
    .cam_frame_abort(w_b_frame_abort),
    .prot_en       (img_push_en     ),
    .rel_tgl0      (w_rel_tgl2      ),
    .rel_tgl1      (w_rel_tgl3      ),

    .clk_fb        (tl_clk_user       ),
    .rst_fb        (power_on_rst_dly ),
    .session_id    (w_tx_session_id   ),
    .wr_frame_seq  (w_camddr_b_seq    ),
    .wr_base       (w_camddr_b_base   ),
    .wr_status     (w_camddr_b_status ),
    .wr_len        (w_camddr_b_len    ),

    .dbg_lines_per_frame  (w_camddr_b_lines),
    .dbg_max_grp_per_line (w_camddr_b_grp  ),
    .dbg_anomaly          (w_camddr_b_anom ),

    .clk_ddr       (w_ddr_dhi_clk     ),
    .rst_ddr       (~w_ddrphy_rst_n   ),
    .ddr_cal_done  (w_ddrphy_rdy      ),
    .arm           (w_cam_ddr_want    ),
    .axi_busy      (w_camw_busy_b     ),

    .m_axi_awaddr  (w_camw_b_awaddr   ),
    .m_axi_awlen   (w_camw_b_awlen    ),
    .m_axi_awsize  (w_camw_b_awsize   ),
    .m_axi_awburst (w_camw_b_awburst  ),
    .m_axi_awvalid (w_camw_b_awvalid  ),
    .m_axi_awready (w_camw_b_awready  ),
    .m_axi_wdata   (w_camw_b_wdata    ),
    .m_axi_wstrb   (w_camw_b_wstrb    ),
    .m_axi_wlast   (w_camw_b_wlast    ),
    .m_axi_wvalid  (w_camw_b_wvalid   ),
    .m_axi_wready  (w_camw_b_wready   ),
    .m_axi_bresp   (w_camw_b_bresp    ),
    .m_axi_bvalid  (w_camw_b_bvalid   ),
    .m_axi_bready  (w_camw_b_bready   )
);

// ---- A/B 两路共用一个 AXI 写口（仲裁策略与死锁分析见 ddr_wr_arb.v 头部）----
ddr_wr_arb u_ddr_wr_arb (
    .clk       (w_ddr_dhi_clk    ),
    .rst       (~w_ddrphy_rst_n  ),
    .busy0     (w_camw_busy      ),
    .busy1     (w_camw_busy_b    ),
    .grant_out (w_wr_grant       ),
    .a0_awaddr (w_camw_awaddr    ), .a0_awlen (w_camw_awlen),
    .a0_awsize (w_camw_awsize    ), .a0_awburst (w_camw_awburst),
    .a0_awvalid(w_camw_awvalid   ), .a0_awready (w_camw_awready),
    .a0_wdata  (w_camw_wdata     ), .a0_wstrb (w_camw_wstrb),
    .a0_wlast  (w_camw_wlast     ), .a0_wvalid (w_camw_wvalid), .a0_wready (w_camw_wready),
    .a0_bresp  (w_camw_bresp     ), .a0_bvalid (w_camw_bvalid), .a0_bready (w_camw_bready),
    .a1_awaddr (w_camw_b_awaddr  ), .a1_awlen (w_camw_b_awlen),
    .a1_awsize (w_camw_b_awsize  ), .a1_awburst (w_camw_b_awburst),
    .a1_awvalid(w_camw_b_awvalid ), .a1_awready (w_camw_b_awready),
    .a1_wdata  (w_camw_b_wdata   ), .a1_wstrb (w_camw_b_wstrb),
    .a1_wlast  (w_camw_b_wlast   ), .a1_wvalid (w_camw_b_wvalid), .a1_wready (w_camw_b_wready),
    .a1_bresp  (w_camw_b_bresp   ), .a1_bvalid (w_camw_b_bvalid), .a1_bready (w_camw_b_bready),
    .m_awaddr  (w_ddr_awaddr     ), .m_awlen (w_ddr_awlen),
    .m_awsize  (w_ddr_awsize     ), .m_awburst (w_ddr_awburst),
    .m_awvalid (w_ddr_awvalid    ), .m_awready (w_ddr_awready),
    .m_wdata   (w_ddr_wdata      ), .m_wstrb (w_ddr_wstrb),
    .m_wlast   (w_ddr_wlast      ), .m_wvalid (w_ddr_wvalid), .m_wready (w_ddr_wready),
    .m_bresp   (w_ddr_bresp      ), .m_bvalid (w_ddr_bvalid), .m_bready (w_ddr_bready)
);

// ====================================================================
//  【本步新增】推帧引擎：DDR3 → 主机内存（MWr 主动写）
//
//  触发：push_en = CTRL[6] 置 1，且「本源」发布了与上次不同的帧号。
//  取数（两选一，CTRL[7] = push_src）：
//    · 0（默认）：u_ddr3_mc_0 的 AXI4 读通道，每 4KB 一个突发，
//      读进 256bit×128 拍的异步 FIFO，过到 tl_clk_user 域；
//    · 1：【本步新增】直接读片内 ERAM 帧缓存（img_frame_src 的 fb[]），8 个字
//      拼一拍（8 个字拼一个 256bit 拍），完全不碰 DDR。
//      用途：先把「EP 主动把整帧写进 RK 内存」这条 DMA 单独验通。
//      读口就是 fb 那唯一一份（与主机预取 / DDR 搬运共用，见上面 img_frame_src
//      例化处的源二选一）；验 ERAM 路时把 ddr_en（CTRL[5]）留 0，两边不抢口。
//  发数：每 128 字节数据摆成一个 4DW 头的 MWr（5 拍：4 个 dw 头 + 32 个 dw 载荷），
//        整帧 2400 笔；每笔之间空一拍，把 TL 发送口还给引擎发完成包。
//        帧数据全推完后再单发一笔「只写 1 个 dw」的门铃 MWr（地址由主机给）。
//  目标地址：0xB0/0xB4 由主机写（帧内每笔 +128），不写死任何物理地址。
//  TLP 头怎么拼、字节序依据、tag/排序推理、出错策略、已知限制：全写在
//  rtl/ep_side/ddr/ddr_frame_pusher.v 头部。
// ====================================================================
// TL 发送口 mux：引擎空闲且用户侧要发时，把 tl_tx_* 换成用户侧那一组。
//  · utx_sel = 1 期间，引擎的发送状态机停在 TL_TX_USER（它自己那几个寄存器归零），
//    所以这里切过去不会把引擎正在发的包拦腰截断；
//  · 引擎在 TL_TX_IDLE 时它那几根线上全是 0（每个包末拍收走时自己清），
//    所以切回来也不会多出一拍。
assign tl_tx_data  = utx_sel ? utx_data  : e_tl_tx_data ;
assign tl_tx_sop   = utx_sel ? utx_sop   : e_tl_tx_sop  ;
assign tl_tx_eop   = utx_sel ? utx_eop   : e_tl_tx_eop  ;
assign tl_tx_valid = utx_sel ? utx_valid : e_tl_tx_valid;

ddr_frame_pusher #(
    .W           (IMG_W             ),
    .H           (IMG_H             ),
    .PAY_DW      (32                ),   // 128 字节 = 协商出的 MaxPayload
    .FIFO_AW     (7                 ),   // 128 拍 × 32B = 4KB，与突发等长
    .BURST_BEATS (128               ),   // 128 × 32B = 4KB，不跨页
    .WAIT_LIMIT  (16'hFFFF          ),
    .BASE0       (DDR_CAM_BASE0     ),   // DDR 源 A 路双缓冲块（与 cam_ddr_writer A 一致）
    .BASE1       (DDR_CAM_BASE1     ),
    .BASE0B      (DDR_CAM_B_BASE0   ),   // DDR 源 B 路双缓冲块（release 判定要按相机选对）
    .BASE1B      (DDR_CAM_B_BASE1   )
) u_ddr_frame_pusher (
    .clk_fb        (tl_clk_user       ),
    .rst_fb        (power_on_rst_dly ),

    .push_en       (img_push_en       ),
    .src_sel       (img_push_src      ),
    .fb_frame_cnt  (img_frame_cnt     ),
    .fb_rd_addr    (img_push_fb_addr  ),
    .fb_rd_data    (img_fb_rd2_data   ),
    .fb_req        (img_push_fb_req   ),
    .fb_grant      (img_push_fb_grant ),
    .src_act       (img_push_src_act  ),
    .fb_hold       (w_push_fb_hold    ),
    .dst_lo        (img_push_dst_lo   ),
    .dst_hi        (img_push_dst_hi   ),
    .db_lo         (img_push_db_lo    ),
    .db_hi         (img_push_db_hi    ),
    .st_done       (img_push_done    ),
    .st_status     (img_push_status  ),
    .st_err        (img_push_err     ),
    .st_tlp_cnt    (img_push_tlp     ),

    // T07：RKA1 one-shot 安全门
    .arm_pulse     (w_tx_cmd_arm     ),
    .ack_pulse     (w_tx_cmd_ack     ),
    .cancel_pulse  (w_tx_cmd_cancel  ),
    .cap_bytes     (w_tx_cap_bytes   ),
    .session_id    (w_tx_session_id  ),
    .ack_seq_w     (w_tx_ack_seq     ),
    .ack_session_w (w_tx_ack_session ),
    .cfg_reject    (w_tx_cfg_reject  ),
    .link_up       (w_link_up        ),
    .mps_code      (tl_cfg_max_payload_size),
    .ddr_cap_bytes (DDR_CAP_BYTES    ),
    .cam_sel_live  (img_cam_ab_sel   ),
    .tx_status     (w_tx_status      ),
    .tx_block_cfg  (w_tx_block_cfg   ),
    .rel_tgl0      (w_rel_tgl0       ),
    .rel_tgl1      (w_rel_tgl1       ),
    .rel_tgl2      (w_rel_tgl2       ),
    .rel_tgl3      (w_rel_tgl3       ),
    .tx_src_lock   (w_push_src_lock  ),

    .frame_bytes   (w_push_frame_bytes),
    .ddr_seq       (w_push_ddr_seq    ),
    .ddr_base      (w_push_ddr_base   ),
    .ddr_status    (w_push_ddr_status  ),

    .utx_sel       (utx_sel           ),
    .tl_tx_wait    (tl_tx_wait        ),
    .utx_req       (utx_req           ),
    .utx_data      (utx_data          ),
    .utx_sop       (utx_sop           ),
    .utx_eop       (utx_eop           ),
    .utx_valid     (utx_valid         ),

    .clk_ddr       (w_ddr_dhi_clk     ),
    .rst_ddr       (~w_ddrphy_rst_n   ),

    .m_axi_arid    (w_ddr_arid        ),
    .m_axi_araddr  (w_ddr_araddr      ),
    .m_axi_arlen   (w_ddr_arlen       ),
    .m_axi_arsize  (w_ddr_arsize      ),
    .m_axi_arburst (w_ddr_arburst     ),
    .m_axi_arvalid (w_ddr_arvalid     ),
    .m_axi_arready (w_ddr_arready     ),
    .m_axi_rid     (w_ddr_rid         ),
    .m_axi_rdata   (w_ddr_rdata       ),
    .m_axi_rresp   (w_ddr_rresp       ),
    .m_axi_rlast   (w_ddr_rlast       ),
    .m_axi_rvalid  (w_ddr_rvalid      ),
    .m_axi_rready  (w_ddr_rready      )
);

endmodule
