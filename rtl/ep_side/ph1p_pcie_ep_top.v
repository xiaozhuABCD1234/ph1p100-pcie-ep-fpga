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
 module ph1p_pcie_ep_top #(
    // T11 debug：仅 ph1p_pcie_ep_top_dbg 覆盖为 1'b1；生产/00_all 默认 0（行为不变）
    parameter DBG_CTRL_DEFAULT_EN = 1'b0,
    parameter CLOSEDLOOP_EN = 1'b0,
    // 硬件同步：A 主 / B 从，共享 XHS/XVS；开启时由 0x1E0.START 启动。
    // **当前默认关闭**：开启后 sync_start_ctrl 走到 WARM 就等不到 pair_event
    // （A 路能锁、in_frame=1，B 路不出 SOF，见 docs/BOARD_TEST.md「硬件同步未闭合」），
    // 而同步控制器是唯一的 I2C 主人，失败后会把两路 sensor 都停掉，正常取帧也一起没了。
    // 修好 B 路的配对再改回 1'b1。
    parameter SYNC_ENABLE = 1'b0,
    parameter integer SYNC_WAIT_CYCLES = 1500000,   // 24ms @ 62.5MHz
    parameter integer SYNC_FRAME_TIMEOUT = 50000000,
    parameter integer SYNC_PAIR_WINDOW = 100000,
    parameter integer SYNC_I2C_TIMEOUT = 5000000,
    parameter         SYNC_MASTER_B = 1'b0   // 0 = A 主/B 从（默认）；1 = B 主/A 从
)(

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

    // ---- 相机正式 RAW10 通路（cam_r10f_writer）----
    //  传感器固定 4K30 全阵列（I_cam_mode=1、HMAX=1100、VMAX=2250、891Mbps×4lane），
    //  每行 CSI-2 长包 WC=4830B = 3864 像素（3840 有效 + 左右各 12 列 OB），
    //  每帧 2192 行（2160 有效 + 上下各 16 行 OB）。取有效图、不做 ROI：
    //    3840×2160 packed RAW10 → stride 4800B、payload 10,368,000B，
    //    R10F 头 128B + 载荷 + 4KiB 对齐尾 ⇒ 10,371,072B/帧（= 2532 × 4KiB）。
    //  板测：push=2,073,600（=2160×960）、drop=0、beats=324,096、29.9fps。
    //  要回到 1080p ROI 就改 W/H/X0/Y0（ROI 时 X_OFF 保持 0），DDR 基址可不动。
    localparam integer CAMDDR_W   = 3840;
    localparam integer CAMDDR_H   = 2160;
    localparam [15:0]  CAMDDR_X0  = 16'd0;
    localparam [15:0]  CAMDDR_Y0  = 16'd0;
    // 4K 传感器出的是 3864×2192 全阵列：有效图 3840×2160 的物理原点是 (12,16)
    // （左 12 列 / 上 16 行是 OB）。X_OFF 只平移取数窗口、roi_x 仍写 0；
    // SKIP_ROWS=16 跳过上方 OB 行，窗口才是真正的 2160 行（37 是 1080p ROI 时代的
    // 旧标定，2192-37 只有 2155 行，会让帧短 5 行）。
    localparam [15:0]  CAMDDR_X_OFF     = 16'd12;
    localparam [15:0]  CAMDDR_SKIP_ROWS = 16'd16;
    //  两路各一对双缓冲；一帧 10.4MB ⇒ 块间隔 16MB（A 16/32MB，B 48/64MB，共 74MB）
    localparam [31:0]  DDR_CAM_BASE0   = 32'h0100_0000;
    localparam [31:0]  DDR_CAM_BASE1   = 32'h0200_0000;
    localparam [31:0]  DDR_CAM_B_BASE0 = 32'h0300_0000;
    localparam [31:0]  DDR_CAM_B_BASE1 = 32'h0400_0000;
    localparam integer CAMDDR_BYTES  = CAMDDR_W * CAMDDR_H;

    // ---- FPGA 预处理通路的几何（算法 IP 宽度上限 2048，所以只能取 ROI）----
    //  传感器全阵列 3864×2192 的中心 1920×1088：X=(3864-1920)/2=972、Y=(2192-1088)/2=552。
    //  选这个高度而不是 1080，是为了让越界判断留一行余量（适配器窗口 = Y0..Y0+H）。
    localparam integer ALGO_W      = 1920;
    localparam integer ALGO_H      = 1088;
    localparam integer ALGO_X0     = 972;
    localparam integer ALGO_Y0     = 552;
    localparam [1:0]   ALGO_PHASE  = 2'd0;
// LZ77 压缩通路：编码器 2.39 cycle/byte，187.5 MHz 下只有 78.5 MB/s。
// 喂 1920×1088 需要 78.3 MB/s —— 只剩 0.3% 余量，实际跑不动（板测第一版就卡在半帧）。
// 所以压缩 ROI 取 1920×544（中心），只要 39.2 MB/s，留一倍余量，可以每帧都压。
// 容器仍是 1920×1088（packer 补零到定长），主机按 st_stream_len 截取。
localparam integer CODEC_H      = 544;
localparam integer CODEC_Y0     = (2192 - CODEC_H) / 2;   // 824，全阵列居中
// keep_div：0 = 每帧都压；1 = 隔帧压。运行时用 0x240[3] 覆盖，方便现场调。
localparam [31:0]  CODEC_KEEP_DIV = 32'd0;   // ROI 原点偶/偶 ⇒ 与传感器原相位一致（RGGB）
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

// B01 debug-only exclusive reader and same-domain publication contract.
wire [3:0] push_arid;wire [28:0] push_araddr;wire [7:0] push_arlen;
wire [2:0] push_arsize;wire [1:0] push_arburst;wire push_arvalid,push_arready,push_rvalid,push_rready;
// B 路 pusher 的 AXI 读通道 + 两路仲裁后的单一读口
wire [3:0] push_b_arid;wire [28:0] push_b_araddr;wire [7:0] push_b_arlen;
wire [2:0] push_b_arsize;wire [1:0] push_b_arburst;
wire push_b_arvalid,push_b_arready,push_b_rvalid,push_b_rready;
wire [3:0] push_rd_arid;wire [28:0] push_rd_araddr;wire [7:0] push_rd_arlen;
wire [2:0] push_rd_arsize;wire [1:0] push_rd_arburst;
wire push_rd_arvalid,push_rd_arready,push_rd_rvalid,push_rd_rready;
wire [3:0] push_rd_rid;wire [255:0] push_rd_rdata;wire [1:0] push_rd_rresp;wire push_rd_rlast;
wire [3:0] push_rid; wire [255:0] push_rdata; wire [1:0] push_rresp; wire push_rlast;
wire [3:0] push_b_rid; wire [255:0] push_b_rdata; wire [1:0] push_b_rresp; wire push_b_rlast;
wire utx_sel_a, utx_sel_b, utx_req_a, utx_req_b;
wire [255:0] utx_data_a, utx_data_b; wire utx_sop_a, utx_sop_b, utx_eop_a, utx_eop_b;
wire [7:0] utx_valid_a, utx_valid_b;
wire [1:0] cl_release;wire cl_pub_valid;wire [31:0] cl_pub_seq,cl_pub_base,cl_pub_len,cl_pub_session,cl_writer_good,cl_writer_bad;
wire cl_inject_abort;
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
wire         w_cam_ddr_want_a, w_cam_ddr_want_b;

/*
 * 帧级轮转（T07 收帧卡死规避）：一次只 arm 一路写者。
 *
 * 板测事实：两片 cam_r10f_writer 同时 armed 时，DDR 写口上会有一路永久卡在
 * 「AW 已发、等不到 wready」，它 axi_busy 一直为 1、把仲裁器的授权压住，
 * 整条通路（像素 FIFO 塞满 1023 组 → 整帧补零 → 判定坏）再也回不来，
 * 只有重新 arm 一次才能恢复。原因在仲裁器与 DDR 写通道的交互上，还没定死。
 *
 * 在查清之前先用帧级轮转绕开：谁刚发布一帧就把「发包权」交给另一路。
 * 空闲的那一路 arm=0，走的是设计里已有的 skip 路径（跳过但不写），
 * 不会卡。若当前持有方在 WATCHDOG 周期内一帧都没发布，也强制换手，
 * 保证任何一路卡死都不会把另一路饿死。
 */
/*
 * 定时换手（替代原先「按发布事件翻转」的实现）。
 *
 * 原实现挂在 power_on_rst_dly 上做异步复位，板测发现 owner 一直停在 0 ——
 * 结果 A 路被永久 armed、B 路一次都没 arm 过（B 的 verdict=0 是「没被 arm」，不是「轮转等待」）。
 * 现在改成**自由运行的定时器**：不依赖任何复位，每 2^24 个 tl_clk_user 周期换一次手
 * （62.5MHz 下约 268ms ≈ 4 帧），两路各拿一半时间，各约 7.8 fps。
 * 没被 arm 的那一路走设计里已有的 skip 路径（跳过不写），不会卡。
 */
localparam integer CAM_TX_ROT_BITS = 24;
localparam integer SINGLE_B_TEST   = 1;   // （历史）1 = 只 arm B 路（单路扫频）
localparam integer DUAL_TEST       = 1;   // 1 = A/B 同时 arm（并发实验）
// 默认 arm 掩码（scratch=0 时生效）：本轮默认双路，用 0x6C 运行时改
//   0x6C[1:0] = 1 → 只 A；2 → 只 B；3 → 双路；0 → 用下面这个默认
// 4K 单路：双路 4K30 时两片 writer 共用一个 DDR 写口，实测 A 路 FIFO 溢出
// 23%（push 1,583,646 / drop 485,410），出图是横条纹。单路 4K 只占 311 MB/s，
// 不丢组。双路 4K 要先把写通道带宽/仲裁做掉，见 docs/BOARD_TEST.md。
// 当前默认只 arm B 路（= 预处理帧通道）。A 路 4K 与 B 路算法帧同时 arm 时打包预算
// 78% + 20% ≈ 98%，压不住；要两路同时出，得先解决打包节拍（见 docs/BOARD_TEST.md）。
localparam [1:0]   CAM_ARM_DEFAULT = 2'b01;   // 只 arm A 路（预处理帧走 A）
wire [31:0] w_dbg_scratch;                       // 0x6C SCRATCH 直出（pcie_ep_engine）
wire [1:0]  w_cam_arm_sel = (w_dbg_scratch[1:0] == 2'b00) ? CAM_ARM_DEFAULT
                                                          : w_dbg_scratch[1:0];
reg [CAM_TX_ROT_BITS-1:0] cam_tx_rot_cnt;
reg                       cam_tx_owner;         // 0 = A 路持有发包权，1 = B 路

always @(posedge tl_clk_user) begin
    cam_tx_rot_cnt <= cam_tx_rot_cnt + 1'b1;
    if (cam_tx_rot_cnt == {CAM_TX_ROT_BITS{1'b1}})
        cam_tx_owner <= ~cam_tx_owner;
end

assign w_cam_ddr_want   = img_ddr_en;
// 运行时 arm 掩码（0x6C）：1 = 只 A，2 = 只 B，3 = 双路；0 = 用 CAM_ARM_DEFAULT。
// 这样一支位流就能分别验 B 单路 / A 单路 / 双路，不必每次改参数重建。
assign w_cam_ddr_want_a = img_ddr_en &  w_cam_arm_sel[0];
assign w_cam_ddr_want_b = img_ddr_en &  w_cam_arm_sel[1];
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
wire [8:0]  w_dbgfsm_cama, w_dbgfsm_camb;   // 写者状态快照（调试只读，见 0x170/0x174）
wire [95:0] w_dbgstall_a, w_dbgstall_b;    // 写者 AXI 阶段停滞（调试只读，见 0x188~0x19C）
wire [255:0] w_dbgframe_a, w_dbgframe_b;   // 写者每帧统计（调试只读，见 0x1A0~0x1DC）
wire [95:0] w_dbgdrop_b;                  // B 路写者丢帧诊断（调试只读，见 0x17C/0x180/0x184）
wire        w_camddr_anom, w_camddr_b_anom;
// 推帧引擎取哪一路（CTRL[8]）
wire [31:0] w_push_ddr_seq, w_push_ddr_base, w_push_ddr_status, w_push_ddr_len;
wire [31:0] w_push_ddr_seq_b, w_push_ddr_base_b, w_push_ddr_status_b, w_push_ddr_len_b;
// 推帧引擎的「本帧字节数」：DDR 源按选中的写者给，ERAM 源按 fb 的 DATA_LEN 给
wire [31:0] w_push_frame_bytes, w_push_frame_bytes_b;

// ==== 硬件同步曝光控制/状态（0x1E0..0x20C）====
wire        sync_start, sync_abort;
wire        sync_req_valid, sync_req_ready, sync_camera;
wire        sync_a_ready, sync_b_ready, sync_a_rsp, sync_b_rsp, sync_a_ok, sync_b_ok;
wire        sync_ready_ctrl, sync_ready, sync_busy, sync_stopped, sync_pair, sync_locked;
wire [15:0] sync_addr;
wire [7:0]  sync_data;
wire [3:0]  sync_error;
wire [31:0] sync_skew, sync_pairs, sync_warmup, sync_timestamp;
wire [31:0] sync_miss_a, sync_miss_b, sync_overrun_a, sync_overrun_b, sync_relock;
wire [31:0] sync_pair_seq_a, sync_pair_seq_b;
wire [31:0] sync_status_word;
wire [351:0] sync_ro;
// 预处理模式：0x240 bit0=使能，[2:1]=选哪一路（0 灰度 / 1 高斯 / 2 直方图均衡）
wire [31:0] w_algo_ctrl;
// 预处理通路的跨块连线：**必须在这里声明**。Verilog 要求先声明后使用，
// 声明写在使用点附近会被 TD 当成隐式 1 位网（只在 log 里报 undeclared，
// 不报错），结果 40 位像素被截成 1 位、整个算法通路静默失效。
wire [31:0] algo_acc, algo_rej, algo_ovf;
// CODEC 状态（0x250..0x25C）：{commit 计数, blocks, raw_crc, raw_len, stream_len, words, done}
wire [127:0] w_codec_stat;
wire        algo_ms_ready, algo_ms_valid, algo_ms_vsync, algo_ms_frame, algo_ms_line;
wire [39:0] algo_ms_pix;

// ==== 端到端延迟的时间基准 ====
//  自由运行 64 位计数器，clk_ddr 域（100 MHz）。writer 在 SOF 到达时锁存它的值写进
//  R10F 头 16/17/18 字；同一计数器的当前值通过 0x238/0x23C 给主机读（2 级同步到
//  tl_clk_user 域，多比特同步的偏差上限是几十 µs 量级，对 ≤50ms 的判定足够）。
reg  [63:0] r_ts_cnt;
reg  [63:0] r_ts_cnt_s1, r_ts_cnt_s2;
always @(posedge w_ddr_dhi_clk) begin
    if (!w_ddrphy_rst_n) r_ts_cnt <= 64'd0;
    else                 r_ts_cnt <= r_ts_cnt + 64'd1;
end
always @(posedge tl_clk_user) begin
    r_ts_cnt_s1 <= r_ts_cnt;
    r_ts_cnt_s2 <= r_ts_cnt_s1;
end

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
wire         img_pair_en;        // CTRL[9]：1 = A/B 双路同时推帧
wire [31:0]  img_push_dst_lo, img_push_dst_hi, img_push_db_lo, img_push_db_hi;
wire [31:0]  img_push_done, img_push_status, img_push_tlp;
wire [7:0]   img_push_err;
wire [127:0] img_push_ro;        // {tlp_cnt, err, status, done} → ep_bar_win 0xCC/0xC8/0xC4/0xC0
// 双路（B 路）推帧
wire [31:0]  img_pair_dst_lo, img_pair_dst_hi, img_pair_db_lo, img_pair_db_hi;
wire [31:0]  img_pair_ack_seq;
wire         img_pair_arm, img_pair_ack, img_pair_cancel;
wire [31:0]  img_push_done_b, img_push_status_b, img_push_tlp_b;
wire [7:0]   img_push_err_b;
wire [127:0] img_push_ro_b;
wire [31:0]  img_pair_status;
wire         img_pair_block_cfg;
assign img_push_ro_b = {img_push_tlp_b, 24'd0, img_push_err_b, img_push_status_b, img_push_done_b};
// 单路 B 兼容：CTRL[8]=1 且 pair_en=0 时，B 片复用 0xB0/0xB8 的 A 套寄存器。
wire [31:0] w_b_dst_lo = img_pair_en ? img_pair_dst_lo : img_push_dst_lo;
wire [31:0] w_b_dst_hi = img_pair_en ? img_pair_dst_hi : img_push_dst_hi;
wire [31:0] w_b_db_lo  = img_pair_en ? img_pair_db_lo  : img_push_db_lo;
wire [31:0] w_b_db_hi  = img_pair_en ? img_pair_db_hi  : img_push_db_hi;
// [1]=A held, [0]=B held；[15:8]=A err，[23:16]=B err。ACK 后必须两位都为 0。
assign img_pair_status = {14'd0, img_push_err_b, img_push_err,
                          w_tx_status_b[2], w_tx_status[2]};
assign img_pair_block_cfg = img_push_status_b[0] | img_push_status_b[2];
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
wire [31:0]  w_tx_status, w_tx_status_b;
wire         w_tx_block_cfg, w_tx_block_cfg_b, w_tx_cfg_reject;
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

// 推帧引擎的 DDR 源：A 路固定接 A 写者、B 路固定接 B 写者。
// 单路模式下由 ARM 命令选中的那一片 pusher 工作，另一片保持 push_en=0/不授权。
assign w_push_ddr_seq    = w_camddr_seq;
assign w_push_ddr_base   = w_camddr_base;
assign w_push_ddr_status = w_camddr_status;
assign w_push_ddr_len    = w_camddr_len;
assign w_push_ddr_seq_b    = w_camddr_b_seq;
assign w_push_ddr_base_b   = w_camddr_b_base;
assign w_push_ddr_status_b = w_camddr_b_status;
assign w_push_ddr_len_b    = w_camddr_b_len;
// ↑ 方向别写反：w_ddr_ro 是「汇聚到寄存器窗口的那条总线」，四个字是它的源。
//   写反（assign {w_ddr_len,...} = w_ddr_ro;）会让这 128bit 整条悬空，
//   TD 综合报 SYN-5013 Undriven net / SYN-5025 Using 0 for all undriven pins and nets，
//   主机读 0xA0~0xAC 全得 0 —— 连常数 DDR_LEN(0x4B000) 也读 0（因为 0xAC 的源
//   是这条死总线，不是 wr_len 本身）。顺序也要对：{len,status,base,seq}

// 推帧引擎的「本帧字节数」：DDR 源用选中的那组 len；ERAM 源用 fb 的 DATA_LEN。
// 这两个数都必须是 4KB 的整数倍（640x480 = 75x4096、4K = 2025x4096），否则
// 推帧的 MWr 数/突发数不是整数（见 ddr_frame_pusher.v 端口说明）。
assign w_push_frame_bytes   = img_push_src ? img_data_len : w_push_ddr_len;
assign w_push_frame_bytes_b = w_push_ddr_len_b;

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

// T11 r3（issue-02）：调试快照专用复位——与 PCIe 链路无关：板级 POR（pcie_power_on_rst 低有效）
//   或 PLL 未锁时有效；无主机时链路未建立但本复位已释放。仅 debug 构建的 DBG 门控块消费；
//   生产 DBG_CTRL_DEFAULT_EN=0 时该网络无消费者，生产行为不变。
wire    dbg_por_rst = (~pcie_power_on_rst) | (~pcie_pll_locked);

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
    .IMG_CLK_MHZ                             (9'd62                                  ),
    .DBG_CTRL_DEFAULT_EN                     (DBG_CTRL_DEFAULT_EN                    )
) u_pcie_ep_engine (


    // Clock and Reset
    .tl_clk_user                             (tl_clk_user                             ),
    .tl_rst_user                             (tl_rst_user                             ),
    .dbg_por_rst                             (dbg_por_rst                             ),

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
    .img_pair_en                             (img_pair_en                            ),
    .img_push_dst_lo                         (img_push_dst_lo                        ),
    .img_push_dst_hi                         (img_push_dst_hi                        ),
    .img_push_db_lo                          (img_push_db_lo                         ),
    .img_push_db_hi                          (img_push_db_hi                         ),
    .img_pair_dst_lo                         (img_pair_dst_lo                        ),
    .img_pair_dst_hi                         (img_pair_dst_hi                        ),
    .img_pair_db_lo                          (img_pair_db_lo                         ),
    .img_pair_db_hi                          (img_pair_db_hi                         ),
    .img_pair_ack_seq                        (img_pair_ack_seq                       ),
    .img_pair_arm                            (img_pair_arm                           ),
    .img_pair_ack                            (img_pair_ack                           ),
    .img_pair_cancel                         (img_pair_cancel                        ),
    .img_push_ro                             (img_push_ro                            ),
    .img_push_ro_b                           (img_push_ro_b                          ),
    .img_pair_status                         (img_pair_status                        ),
    .img_pair_block_cfg                      (img_pair_block_cfg                     ),
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
    .ts_now                                  (r_ts_cnt_s2                            ),
    .algo_ctrl                               (w_algo_ctrl                            ),
    .algo_dbg                                ({algo_ovf, algo_rej, algo_acc}          ),
    .codec_stat                              (w_codec_stat                           ),
    .cam_tap_cfg                             (cam_tap_cfg                            ),
    .cam_tap_b_cfg                           (cam_tap_b_cfg                          ),
    .cam_ab_sel                              (img_cam_ab_sel                         ),
    .ddr_ro_b                                (w_ddr_ro_b                             ),
    .dbg_scratch                             (w_dbg_scratch                          ),
    .cama_stall                              (w_dbgstall_a                           ),
    .camb_stall                              (w_dbgstall_b                           ),
    .dbg_frame_a                             (w_dbgframe_a                           ),
    .dbg_frame_b                             (w_dbgframe_b                           ),
    .cam_drop_a                              (w_camddr_drop_a                        ),
    .cam_diag_b                              (w_cam_diag_b                           ),
    .dbgfsm_cama                               (w_dbgfsm_cama                            ),
    .dbgdrop_b                                 (w_dbgdrop_b                              ),
    .dbgfsm_camb                               (w_dbgfsm_camb                            ),
    .dbgwr_busya                           (w_camw_busy                            ),
    .dbgwr_busyb                           (w_camw_busy_b                          ),
    .dbgwr_grant                            (w_wr_grant                             ),
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
    .csi_diag_b2                             (r_csi_b_geo2                           ),
    .sync_start                              (sync_start                             ),
    .sync_abort                              (sync_abort                             ),
    .sync_ro                                 (sync_ro                                )
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

    // ---- 50MHz sys_clk → 干净 25MHz（MCLK_SEL=5；先 BUFG 再二分频，50% 占空）----
    wire w_sys_clk_bufg;
    PH1P_LOGIC_BUFG u_sys_clk_bufg (.i(sys_clk), .o(w_sys_clk_bufg));
    reg  r_mclk_25_clean = 1'b0;
    always @(posedge w_sys_clk_bufg) r_mclk_25_clean <= ~r_mclk_25_clean;

    // 62.5MHz → 27MHz 分数分频（MCLK_SEL=6；Bresenham，平均 27.0MHz）
    //   INC = round(65536 * 27 / 62.5) = 56623；平均翻转率 62.5*56623/65536 = 54.0MHz
    localparam [16:0] MCLK27_INC = 17'd56623;
    reg [16:0] r_mclk27_acc = 17'd0;
    reg        r_mclk_27    = 1'b0;
    always @(posedge tl_clk_user) begin
        if (r_mclk27_acc >= (17'd65536 - MCLK27_INC)) begin
            r_mclk27_acc <= r_mclk27_acc + MCLK27_INC - 17'd65536;
            r_mclk_27    <= ~r_mclk_27;
        end else begin
            r_mclk27_acc <= r_mclk27_acc + MCLK27_INC;
        end
    end

    // ---- (a) 62.5MHz → 可选 MCLK（扫频用；默认 12.5MHz 仍是原分频器）----
    //   MCLK_SEL: 0=12.5, 1=15.625, 2=20.833, 3=25, 4=31.25 MHz
    //   非整数半周期用相位状态机在 62.5MHz 边沿上交替 1/2 拍实现：
    //     20.833MHz: 半周期 1.5 拍（1,2 交替）→ 周期 3 拍
    //     25MHz   : 半周期 1.25 拍（1,1,1,2）→ 周期 2.5 拍
    //   输出只在 62.5MHz 边沿翻，最小脉宽 1 拍=16ns；传感器 INCK 的 PLL 需实测。
    localparam integer MCLK_SEL = 6;
    reg [2:0] r_macc     = 3'd0;
    reg [2:0] r_mclk_ph  = 3'd0;
    reg       r_mclk_125 = 1'b0;
    always @(posedge tl_clk_user) begin
        case (MCLK_SEL)
        0: begin
            // 12.5MHz：半周期 2/3 拍交替，周期恒 5 拍（原实现）
            if (r_macc >= 3'd5) begin
                r_macc     <= r_macc - 3'd3;
                r_mclk_125 <= ~r_mclk_125;
            end else begin
                r_macc     <= r_macc + 3'd2;
            end
        end
        1: begin
            // 15.625MHz：半周期 2 拍
            if (r_mclk_ph[0]) begin
                r_mclk_ph  <= 3'd0;
                r_mclk_125 <= ~r_mclk_125;
            end else begin
                r_mclk_ph  <= 3'd1;
            end
        end
        2: begin
            // 20.833MHz：半周期 1.5 拍（toggle, wait, toggle, wait...）
            case (r_mclk_ph)
            3'd0: begin r_mclk_ph <= 3'd1; r_mclk_125 <= ~r_mclk_125; end
            3'd1: begin r_mclk_ph <= 3'd2; end
            default: begin r_mclk_ph <= 3'd0; r_mclk_125 <= ~r_mclk_125; end
            endcase
        end
        3: begin
            // 25MHz：半周期 1.25 拍（1,1,1,2 四个半周期，共 5 拍 = 2.5 拍/周期）
            case (r_mclk_ph)
            3'd0: begin r_mclk_ph <= 3'd1; r_mclk_125 <= ~r_mclk_125; end
            3'd1: begin r_mclk_ph <= 3'd2; r_mclk_125 <= ~r_mclk_125; end
            3'd2: begin r_mclk_ph <= 3'd3; r_mclk_125 <= ~r_mclk_125; end
            3'd3: begin r_mclk_ph <= 3'd4; r_mclk_125 <= ~r_mclk_125; end
            default: begin r_mclk_ph <= 3'd0; end
            endcase
        end
        5: begin
            // 25MHz 干净源由 sys_clk/2 产生；这里不动 r_mclk_125
        end
        6: begin
            // 27MHz 由 r_mclk27_acc 产生；这里不动 r_mclk_125
        end
        default: begin
            // 31.25MHz：半周期 1 拍
            r_mclk_125 <= ~r_mclk_125;
        end
        endcase
    end

    // ---- (b) 已删除：原来的「50MHz sys_clk ÷ 4 = 12.50MHz」那一档 ----
    //   它与 (a) 同频（都是 12.5MHz），唯一区别是占空 50%、周期零抖动；板上从未
    //   选中过（CTRL[2] 默认 0，实测靠 (a) 锁定出帧）。但它一存在，sys_clk 这个
    //   50MHz 输入就必须进通用时钟网络：实测该网（sys_clk_dup_1）走本地绕线，
    //   根就是 H4 那个球，扇出两只挂 r_mdiv2 与 r_mclk_c125，STA 里被算成 local
    //   clock、也没有全局缓冲（DRC RTCLK-5079 / check_timing 的 local clock /
    //   RTCLK-5078 那一类风险）。删掉后 sys_clk 只做 PCIe PLL 的参考时钟，
    //   MCLK 恒等于 (a) 的 12.5MHz，即板上已验证的那一档。
    wire w_mclk = (MCLK_SEL == 5) ? r_mclk_25_clean :
                  (MCLK_SEL == 6) ? r_mclk_27       : r_mclk_125;

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
        .I_ref_clk          (w_sys_clk_bufg),
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
        .I_ref_clk          (w_sys_clk_bufg),
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



    // ==== 硬件同步曝光：A 主 / B 从，共享 XHS/XVS ====
    //  sync_offline_top 通过各自的 ui_cfg I2C 写传感器；sync_frame_gate 只在
    //  pair 锁定并越过 warmup 后放行整帧，避免把失锁/半帧送给 writer。
    assign sync_ready      = SYNC_ENABLE ? (sync_ready_ctrl && sync_locked) : 1'b1;
    assign sync_req_ready  = sync_camera ? sync_b_ready : sync_a_ready;
    generate if (SYNC_ENABLE) begin : g_sync_ctrl
        sync_offline_top #(
            .WAIT_CYCLES   (SYNC_WAIT_CYCLES),
            .WARMUP_FRAMES (8),
            .I2C_TIMEOUT   (SYNC_I2C_TIMEOUT),
            .FRAME_TIMEOUT (SYNC_FRAME_TIMEOUT),
            .PAIR_WINDOW   (SYNC_PAIR_WINDOW),
            .MASTER_B      (SYNC_MASTER_B)
        ) u_sync (
            .clk_ctrl          (tl_clk_user),
            .clk_a             (w_a_byte_clk),
            .clk_b             (w_b_byte_clk),
            .rst_n             (pcie_power_on_rst && r_rst_n_slow),
            .start             (sync_start),
            .abort_req         (sync_abort),
            .prereq_ok         (w_a_cfg_done && w_b_cfg_done && w_ddrphy_rdy),
            .sof_a             (w_a_vsync),
            .sof_b             (w_b_vsync),
            .req_valid         (sync_req_valid),
            .req_ready         (sync_req_ready),
            .camera_id         (sync_camera),
            .reg_addr          (sync_addr),
            .reg_data          (sync_data),
            .rsp_valid         (sync_a_rsp || sync_b_rsp),
            .rsp_ok            ((sync_a_rsp && sync_a_ok) || (sync_b_rsp && sync_b_ok)),
            .ready             (sync_ready_ctrl),
            .busy              (sync_busy),
            .stopped_confirmed (sync_stopped),
            .error_code        (sync_error),
            .pair_valid        (sync_pair),
            .locked            (sync_locked),
            .skew              (sync_skew),
            .pair_seq_a        (sync_pair_seq_a),
            .pair_seq_b        (sync_pair_seq_b),
            .pair_count        (sync_pairs),
            .miss_a            (sync_miss_a),
            .miss_b            (sync_miss_b),
            .overrun_a         (sync_overrun_a),
            .overrun_b         (sync_overrun_b),
            .relock_count      (sync_relock),
            .warmup_count      (sync_warmup),
            .ignored_starts    (),
            .timestamp         (sync_timestamp)
        );
    end else begin : g_no_sync
        assign sync_req_valid = 1'b0;
        assign sync_camera    = 1'b0;
        assign sync_addr      = 16'd0;
        assign sync_data      = 8'd0;
        assign sync_ready_ctrl = 1'b1;
        assign sync_busy      = 1'b0;
        assign sync_stopped   = 1'b0;
        assign sync_error     = 4'd0;
        assign sync_pair      = 1'b0;
        assign sync_locked    = 1'b0;
        assign sync_warmup    = 32'd0;
        assign sync_pairs     = 32'd0;
        assign sync_skew      = 32'd0;
        assign sync_pair_seq_a = 32'd0;
        assign sync_pair_seq_b = 32'd0;
        assign sync_miss_a    = 32'd0;
        assign sync_miss_b    = 32'd0;
        assign sync_overrun_a = 32'd0;
        assign sync_overrun_b = 32'd0;
        assign sync_relock    = 32'd0;
        assign sync_timestamp = 32'd0;
    end endgenerate

    // 状态字：bit0 ready / 2 locked / 3 busy / 4 stopped / 5 pair_valid /
    //         [11:8] error / [31:16] warmup。其余见 0x1E8..0x20C。
    assign sync_status_word = {sync_warmup[15:0], 4'd0, sync_error, 2'b00,
                               sync_pair, sync_stopped, sync_busy, sync_locked, 1'b0, sync_ready};
    wire [31:0] sync_overrun_word = {sync_overrun_b[15:0], sync_overrun_a[15:0]};
    assign sync_ro = {sync_pair_seq_b, sync_pair_seq_a, sync_relock,
                      sync_overrun_word, sync_miss_b, sync_miss_a,
                      sync_timestamp, sync_warmup, sync_pairs, sync_skew, sync_status_word};

    wire gate_a_vsync, gate_b_vsync, gate_a_frame, gate_b_frame;
    wire gate_a_line, gate_b_line, gate_a_pixel_valid, gate_b_pixel_valid;
    wire gate_a_good, gate_b_good, gate_a_abort, gate_b_abort;
    sync_frame_gate #(.ENABLE(SYNC_ENABLE)) u_gate_a (
        .clk(w_a_byte_clk), .rst_n(w_a_rst_out), .permit(sync_ready),
        .sof(w_a_vsync), .in_frame(w_a_in_frame), .in_line(w_a_in_line),
        .pixel_valid(w_a_pixel_valid), .good(w_a_frame_good), .abort_in(w_a_frame_abort),
        .out_sof(gate_a_vsync), .out_frame(gate_a_frame), .out_line(gate_a_line),
        .out_pixel_valid(gate_a_pixel_valid), .out_good(gate_a_good), .out_abort(gate_a_abort)
    );
    sync_frame_gate #(.ENABLE(SYNC_ENABLE)) u_gate_b (
        .clk(w_b_byte_clk), .rst_n(w_b_rst_out), .permit(sync_ready),
        .sof(w_b_vsync), .in_frame(w_b_in_frame), .in_line(w_b_in_line),
        .pixel_valid(w_b_pixel_valid), .good(w_b_frame_good), .abort_in(w_b_frame_abort),
        .out_sof(gate_b_vsync), .out_frame(gate_b_frame), .out_line(gate_b_line),
        .out_pixel_valid(gate_b_pixel_valid), .out_good(gate_b_good), .out_abort(gate_b_abort)
    );

    ui_cfg_imx415 #(.SYNC_ENABLE(SYNC_ENABLE),.CLK_DIV(16'd624)) u_cfg_a (
        .I_sync_req    (sync_req_valid && sync_req_ready && !sync_camera),
        .I_sync_addr   (sync_addr     ),
        .I_sync_data   (sync_data     ),
        .O_sync_ready  (sync_a_ready  ),
        .O_sync_rsp_valid(sync_a_rsp  ),
        .O_sync_rsp_ok (sync_a_ok     ),
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

    ui_cfg_imx415 #(.SYNC_ENABLE(SYNC_ENABLE),.CLK_DIV(16'd624)) u_cfg_b (
        .I_sync_req    (sync_req_valid && sync_req_ready && sync_camera),
        .I_sync_addr   (sync_addr     ),
        .I_sync_data   (sync_data     ),
        .O_sync_ready  (sync_b_ready  ),
        .O_sync_rsp_valid(sync_b_rsp  ),
        .O_sync_rsp_ok (sync_b_ok     ),
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
    .CLOSEDLOOP_EN(CLOSEDLOOP_EN),
    .W           (ALGO_W           ),
    .H           (ALGO_H           ),
    .X0          (16'd0             ),
    .X_OFF       (16'd0             ),
    .Y0          (16'd0             ),
    .SKIP_ROWS   (16'd0             ),
    .LINE_CHECK  (0                 ),   // 算法侧已按 ROI 切好，只查整帧组数/拍数
    .BASE0       (DDR_CAM_BASE0     ),
    .BASE1       (DDR_CAM_BASE1     ),
    .FIFO_AW     (10                ),
    .BURST_BEATS (64                ),
    .CAMERA_ID   (8'd0              ),
    .SRC_BAYER_PHASE (2'd0          ),
    .MODE_ID     (32'd1             )
) u_cam_r10f_writer (
    .cam_clk       (w_a_byte_clk    ),
    .cam_rst_n     (w_a_rst_out     ),
    .cam_vsync     (algo_ms_vsync   ),
    .cam_in_frame  (algo_ms_frame   ),
    .cam_in_line   (algo_ms_line    ),
    .cam_pix       (algo_ms_pix     ),
    .cam_pix_valid (algo_ms_valid   ),
    .cam_frame_good(1'b1            ),
    .cam_frame_abort(1'b0           ),
    // 只有被 CTRL[8] 选中的那一路才做「发布即保护」：pusher 只给选中相机发 release，
    // 未选中那路若也开保护，发布完两块后再没有 release，写者会永久停在封锁态。
    .prot_en       (img_push_en && (img_pair_en || ~img_cam_ab_sel)),
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
    .dbg_fsm              (w_dbgfsm_cama     ),
    .dbg_stall            (w_dbgstall_a      ),
    .dbg_frame            (w_dbgframe_a      ),

    .clk_ddr       (w_ddr_dhi_clk     ),
    .rst_ddr       (~w_ddrphy_rst_n   ),
    .timestamp_in  (r_ts_cnt          ),
    .ddr_cal_done  (w_ddrphy_rdy      ),
    .arm           (w_cam_ddr_want_a  ),
    .axi_busy      (w_camw_busy       ),
    .cl_release(cl_release),.cl_pub_valid(cl_pub_valid),.cl_pub_seq(cl_pub_seq),.cl_pub_base(cl_pub_base),
    .cl_pub_len(cl_pub_len),.cl_pub_session(cl_pub_session),.cl_good_count(cl_writer_good),.cl_bad_count(cl_writer_bad),

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

// ---- B 路 writer 改作「预处理结果写者」----
//  B 相机在本阶段不可用（切 slave 后一帧不出，见 docs/BOARD_TEST.md §9），而 DDR 写口
//  只有两个仲裁通道，所以直接把 B 路 writer 复用来写算法帧：几何换 1920×1088，
//  cam 侧时钟/信号全部来自 A 路的算法链。B 相机恢复后要另开一路时才需要扩仲裁。
cam_r10f_writer #(
    .W           (CAMDDR_W          ),
    .H           (CAMDDR_H          ),
    .X0          (CAMDDR_X0         ),
    .X_OFF       (CAMDDR_X_OFF      ),
    .Y0          (CAMDDR_Y0         ),
    .SKIP_ROWS   (CAMDDR_SKIP_ROWS  ),
    .LINE_CHECK  (0                 ),   // 全宽 4K 只查整帧组数/拍数
    .BASE0       (DDR_CAM_B_BASE0   ),
    .BASE1       (DDR_CAM_B_BASE1   ),
    .FIFO_AW     (10                ),
    .BURST_BEATS (64                ),
    .CAMERA_ID   (8'd1              ),
    .SRC_BAYER_PHASE (2'd0          ),
    .MODE_ID     (32'd2             )
) u_cam_r10f_writer_b (
    .cam_clk       (w_b_byte_clk    ),
    .cam_rst_n     (w_b_rst_out     ),
    .cam_vsync     (gate_b_vsync    ),
    .cam_in_frame  (gate_b_frame    ),
    .cam_in_line   (gate_b_line     ),
    .cam_pix       (w_b_pixel       ),
    .cam_pix_valid (gate_b_pixel_valid ),
    .cam_frame_good(gate_b_good     ),
    .cam_frame_abort(gate_b_abort   ),
    .prot_en       (img_push_en && (img_pair_en || img_cam_ab_sel)),   // 双路时两路都保护
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
    .dbg_fsm              (w_dbgfsm_camb     ),
    .dbg_drop             (w_dbgdrop_b       ),
    .dbg_stall            (w_dbgstall_b      ),
    .dbg_frame            (w_dbgframe_b      ),

    .clk_ddr       (w_ddr_dhi_clk     ),
    .rst_ddr       (~w_ddrphy_rst_n   ),
    .timestamp_in  (r_ts_cnt          ),
    .ddr_cal_done  (w_ddrphy_rdy      ),
    .arm           (w_cam_ddr_want_b  ),
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
    .MAX_FRAME_BYTES (16*1024*1024  ),   // 4K 整帧 10.4MB；默认 8.29MB 会拒 ARM
    .WAIT_LIMIT  (16'hFFFF          ),
    .BASE0       (DDR_CAM_BASE0     ),   // DDR 源 A 路双缓冲块（与 cam_ddr_writer A 一致）
    .BASE1       (DDR_CAM_BASE1     ),
    .BASE0B      (DDR_CAM_B_BASE0   ),   // DDR 源 B 路双缓冲块（release 判定要按相机选对）
    .BASE1B      (DDR_CAM_B_BASE1   )
) u_ddr_frame_pusher (
    .clk_fb        (tl_clk_user       ),
    .rst_fb        (power_on_rst_dly ),

    .push_en       (CLOSEDLOOP_EN ? 1'b0 : (img_push_en && (img_pair_en || ~img_cam_ab_sel))),
    .src_sel       (img_pair_en ? 1'b0 : img_push_src),
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
    .arm_pulse     (img_pair_en ? img_pair_arm    : (w_tx_cmd_arm    && ~img_cam_ab_sel)),
    .ack_pulse     (img_pair_en ? img_pair_ack    : (w_tx_cmd_ack    && ~img_cam_ab_sel)),
    .cancel_pulse  (img_pair_en ? img_pair_cancel : (w_tx_cmd_cancel && ~img_cam_ab_sel)),
    .cap_bytes     (w_tx_cap_bytes   ),
    .session_id    (w_tx_session_id  ),
    .ack_seq_w     (w_tx_ack_seq     ),
    .ack_session_w (w_tx_ack_session ),
    .cfg_reject    (w_tx_cfg_reject  ),
    .link_up       (w_link_up        ),
    .mps_code      (tl_cfg_max_payload_size),
    .ddr_cap_bytes (DDR_CAP_BYTES    ),
    .cam_sel_live  (1'b0              ),
    .tx_status     (w_tx_status      ),
    .tx_block_cfg  (w_tx_block_cfg   ),
    .rel_tgl0      (w_rel_tgl0       ),
    .rel_tgl1      (w_rel_tgl1       ),
    .rel_tgl2      (),
    .rel_tgl3      (),
    .tx_src_lock   (w_push_src_lock  ),

    .frame_bytes   (w_push_frame_bytes),
    .ddr_seq       (w_push_ddr_seq    ),
    .ddr_base      (w_push_ddr_base   ),
    .ddr_status    (w_push_ddr_status  ),

    .utx_sel       (utx_sel_a         ),
    .tl_tx_wait    (tl_tx_wait        ),
    .utx_req       (utx_req_a         ),
    .utx_data      (utx_data_a        ),
    .utx_sop       (utx_sop_a         ),
    .utx_eop       (utx_eop_a         ),
    .utx_valid     (utx_valid_a       ),

    .clk_ddr       (w_ddr_dhi_clk     ),
    .rst_ddr       (~w_ddrphy_rst_n   ),

    .m_axi_arid    (push_arid        ),
    .m_axi_araddr  (push_araddr      ),
    .m_axi_arlen   (push_arlen       ),
    .m_axi_arsize  (push_arsize      ),
    .m_axi_arburst (push_arburst     ),
    .m_axi_arvalid (push_arvalid     ),
    .m_axi_arready (push_arready     ),
    .m_axi_rid     (push_rid         ),
    .m_axi_rdata   (push_rdata       ),
    .m_axi_rresp   (push_rresp       ),
    .m_axi_rlast   (push_rlast       ),
    .m_axi_rvalid  (push_rvalid      ),
    .m_axi_rready  (push_rready      )
);


// --------------------------------------------------------------------
//  B 路推帧引擎（与 A 路完全对称；pair_en=1 时两片同时 ARM）
// --------------------------------------------------------------------
ddr_frame_pusher #(
    .W           (IMG_W             ),
    .H           (IMG_H             ),
    .PAY_DW      (32                ),
    .FIFO_AW     (7                 ),
    .BURST_BEATS (128               ),
    .WAIT_LIMIT  (16'hFFFF          ),
    .BASE0       (DDR_CAM_BASE0     ),
    .BASE1       (DDR_CAM_BASE1     ),
    .BASE0B      (DDR_CAM_B_BASE0   ),
    .BASE1B      (DDR_CAM_B_BASE1   )
) u_ddr_frame_pusher_b (
    .clk_fb        (tl_clk_user       ),
    .rst_fb        (power_on_rst_dly ),

    .push_en       (CLOSEDLOOP_EN ? 1'b0 : (img_push_en && (img_pair_en || img_cam_ab_sel))),
    .src_sel       (1'b0              ),
    .fb_frame_cnt  (img_frame_cnt     ),
    .fb_rd_addr    (),
    .fb_rd_data    (32'd0             ),
    .fb_req        (),
    .fb_grant      (1'b0              ),
    .src_act       (),
    .fb_hold       (),
    .dst_lo        (w_b_dst_lo        ),
    .dst_hi        (w_b_dst_hi        ),
    .db_lo         (w_b_db_lo         ),
    .db_hi         (w_b_db_hi         ),
    .st_done       (img_push_done_b   ),
    .st_status     (img_push_status_b ),
    .st_err        (img_push_err_b    ),
    .st_tlp_cnt    (img_push_tlp_b    ),

    .arm_pulse     (img_pair_en ? img_pair_arm    : (w_tx_cmd_arm    && img_cam_ab_sel)),
    .ack_pulse     (img_pair_en ? img_pair_ack    : (w_tx_cmd_ack    && img_cam_ab_sel)),
    .cancel_pulse  (img_pair_en ? img_pair_cancel : (w_tx_cmd_cancel && img_cam_ab_sel)),
    .cap_bytes     (w_tx_cap_bytes    ),
    .session_id    (w_tx_session_id   ),
    .ack_seq_w     (img_pair_en ? img_pair_ack_seq : w_tx_ack_seq),
    .ack_session_w (w_tx_ack_session  ),
    .cfg_reject    (w_tx_cfg_reject   ),
    .link_up       (w_link_up         ),
    .mps_code      (tl_cfg_max_payload_size),
    .ddr_cap_bytes (DDR_CAP_BYTES     ),
    .cam_sel_live  (1'b1              ),
    .tx_status     (w_tx_status_b     ),
    .tx_block_cfg  (w_tx_block_cfg_b  ),
    .rel_tgl0      (),
    .rel_tgl1      (),
    .rel_tgl2      (w_rel_tgl2        ),
    .rel_tgl3      (w_rel_tgl3        ),
    .tx_src_lock   (),

    .frame_bytes   (w_push_frame_bytes_b),
    .ddr_seq       (w_push_ddr_seq_b    ),
    .ddr_base      (w_push_ddr_base_b   ),
    .ddr_status    (w_push_ddr_status_b ),

    .utx_sel       (utx_sel_b         ),
    .tl_tx_wait    (tl_tx_wait        ),
    .utx_req       (utx_req_b         ),
    .utx_data      (utx_data_b        ),
    .utx_sop       (utx_sop_b         ),
    .utx_eop       (utx_eop_b         ),
    .utx_valid     (utx_valid_b       ),

    .clk_ddr       (w_ddr_dhi_clk     ),
    .rst_ddr       (~w_ddrphy_rst_n   ),

    .m_axi_arid    (push_b_arid        ),
    .m_axi_araddr  (push_b_araddr      ),
    .m_axi_arlen   (push_b_arlen       ),
    .m_axi_arsize  (push_b_arsize      ),
    .m_axi_arburst (push_b_arburst     ),
    .m_axi_arvalid (push_b_arvalid     ),
    .m_axi_arready (push_b_arready     ),
    .m_axi_rid     (push_b_rid         ),
    .m_axi_rdata   (push_b_rdata       ),
    .m_axi_rresp   (push_b_rresp       ),
    .m_axi_rlast   (push_b_rlast       ),
    .m_axi_rvalid  (push_b_rvalid      ),
    .m_axi_rready  (push_b_rready      )
);

// A/B 读通道仲裁：DDR 只有一个用户读口，两片 pusher 串行使用。
ddr_rd_arb2 u_push_rd_arb (
    .clk         (w_ddr_dhi_clk     ),
    .rst         (~w_ddrphy_rst_n   ),
    .m0_arvalid  (push_arvalid      ),
    .m0_arready  (push_arready      ),
    .m0_araddr   (push_araddr       ),
    .m0_arlen    (push_arlen        ),
    .m0_arsize   (push_arsize       ),
    .m0_arburst  (push_arburst      ),
    .m0_arid     (push_arid         ),
    .m0_rready   (push_rready       ),
    .m0_rvalid   (push_rvalid       ),
    .m0_rdata    (push_rdata        ),
    .m0_rresp    (push_rresp        ),
    .m0_rlast    (push_rlast        ),
    .m0_rid      (push_rid          ),
    .m1_arvalid  (push_b_arvalid    ),
    .m1_arready  (push_b_arready    ),
    .m1_araddr   (push_b_araddr     ),
    .m1_arlen    (push_b_arlen      ),
    .m1_arsize   (push_b_arsize     ),
    .m1_arburst  (push_b_arburst    ),
    .m1_arid     (push_b_arid       ),
    .m1_rready   (push_b_rready     ),
    .m1_rvalid   (push_b_rvalid     ),
    .m1_rdata    (push_b_rdata      ),
    .m1_rresp    (push_b_rresp      ),
    .m1_rlast    (push_b_rlast      ),
    .m1_rid      (push_b_rid        ),
    .s_arvalid   (push_rd_arvalid   ),
    .s_arready   (push_rd_arready   ),
    .s_araddr    (push_rd_araddr    ),
    .s_arlen     (push_rd_arlen     ),
    .s_arsize    (push_rd_arsize    ),
    .s_arburst   (push_rd_arburst   ),
    .s_arid      (push_rd_arid      ),
    .s_rvalid    (push_rd_rvalid    ),
    .s_rdata     (push_rd_rdata     ),
    .s_rresp     (push_rd_rresp     ),
    .s_rlast     (push_rd_rlast     ),
    .s_rid       (push_rd_rid       ),
    .s_rready    (push_rd_rready    )
);

// 两路推帧共享 TL 用户发送口：帧级授权，A/B 数据绝不交错。
utx_arb2 u_push_utx_arb (
    .clk    (tl_clk_user),
    .rst    (power_on_rst_dly),
    .utx_sel(utx_sel),
    .req0   (utx_req_a),
    .busy0  (img_push_status[0]),
    .data0  (utx_data_a),
    .sop0   (utx_sop_a),
    .eop0   (utx_eop_a),
    .valid0 (utx_valid_a),
    .sel0   (utx_sel_a),
    .req1   (utx_req_b),
    .busy1  (img_push_status_b[0]),
    .data1  (utx_data_b),
    .sop1   (utx_sop_b),
    .eop1   (utx_eop_b),
    .valid1 (utx_valid_b),
    .sel1   (utx_sel_b),
    .req    (utx_req),
    .data   (utx_data),
    .sop    (utx_sop),
    .eop    (utx_eop),
    .valid  (utx_valid)
);

    // ==== FPGA 预处理通路：灰度 / 3×3 高斯 / 直方图均衡（三路并行，AXI-Stream）====
    //  旁路 A 路 4K 组流，取中心 1920×1088 ROI，送 img_algo_parallel_top；
    //  选中的一路经 algo_y8_to_legacy 转成 writer 的标记时序，写进 DDR3，
    //  再由 B 路 pusher 送主机（B 相机本阶段不用，原因见 docs/BOARD_TEST.md）。
    //  ROI 原点用**传感器全阵列坐标**：3864×2192 的中心 ⇒ (972, 552)。
    wire        algo_s_valid, algo_s_ready, algo_s_sof, algo_s_eol, algo_s_eof, algo_s_abort;
    wire [39:0] algo_s_data;
    wire [2:0]  algo_v, algo_sof, algo_eol, algo_eof, algo_abort;
    wire [2:0]  algo_ready;
    wire [31:0] algo_d0, algo_d1, algo_d2;
    wire        algo_cfg_error;
    reg         algo_cfg_ok;
    wire [1:0]  algo_sel    = w_algo_ctrl[2:1];
    // 配置必须是一个**单拍脉冲**（参考用法如此）：cfg_valid 常 1 会让并行顶层
    // 反复重新锁定配置，流水线一直处于刚复位状态，输出永远不来。
    reg [3:0] algo_cfg_dly;
    always @(posedge w_a_byte_clk or negedge w_a_rst_out) begin
        if (!w_a_rst_out) algo_cfg_dly <= 4'd0;
        else              algo_cfg_dly <= {algo_cfg_dly[2:0], 1'b1};
    end
    wire algo_cfg_pulse = (algo_cfg_dly == 4'b0111);
    always @(posedge w_a_byte_clk or negedge w_a_rst_out) begin
        if (!w_a_rst_out) algo_cfg_ok <= 1'b0;
        else if (algo_cfg_pulse) algo_cfg_ok <= ~algo_cfg_error;
    end



    csi_algo_roi_adapter #(
        .W(ALGO_W), .H(ALGO_H), .X0(ALGO_X0), .Y0(ALGO_Y0), .SKIP_ROWS(0), .FIFO_AW(10)
    ) u_algo_roi (
        .clk(w_a_byte_clk), .rst_n(w_a_rst_out),
        .cam_vsync(gate_a_vsync), .cam_in_frame(gate_a_frame), .cam_in_line(gate_a_line),
        .cam_pix(w_a_pixel), .cam_pix_valid(gate_a_pixel_valid),
        .cam_good(gate_a_good), .cam_abort(gate_a_abort),
        .configured(algo_cfg_ok), .outputs_done(1'b1),
        .s_valid(algo_s_valid), .s_ready(algo_s_ready), .s_data(algo_s_data),
        .s_sof(algo_s_sof), .s_eol(algo_s_eol), .s_eof(algo_s_eof), .s_abort(algo_s_abort),
        .accepted_frames(algo_acc), .rejected_frames(algo_rej), .overflow_frames(algo_ovf),
        .accepted_beats(), .busy()
    );

    img_algo_parallel_top #(.MAX_WORDS(512)) u_algo_top (
        .clk(w_a_byte_clk), .rst_n(w_a_rst_out),
        .cfg_valid(algo_cfg_pulse), .cfg_ready(), .cfg_width(ALGO_W[11:0]), .cfg_height(ALGO_H[11:0]),
        .cfg_phase(ALGO_PHASE), .cfg_error(algo_cfg_error),
        .s_valid(algo_s_valid), .s_ready(algo_s_ready), .s_data(algo_s_data),
        .s_sof(algo_s_sof), .s_eol(algo_s_eol), .s_eof(algo_s_eof), .s_abort(algo_s_abort),
        .y8_valid(algo_v[0]),  .y8_ready(algo_ready[0]),  .y8_data(algo_d0),
        .y8_sof(algo_sof[0]),  .y8_eol(algo_eol[0]),      .y8_eof(algo_eof[0]),  .y8_abort(algo_abort[0]),
        .gau_valid(algo_v[1]), .gau_ready(algo_ready[1]), .gau_data(algo_d1),
        .gau_sof(algo_sof[1]), .gau_eol(algo_eol[1]),     .gau_eof(algo_eof[1]), .gau_abort(algo_abort[1]),
        .he_valid(algo_v[2]),  .he_ready(algo_ready[2]),  .he_data(algo_d2),
        .he_sof(algo_sof[2]),  .he_eol(algo_eol[2]),      .he_eof(algo_eof[2]),  .he_abort(algo_abort[2]),
        .st_frames_good(), .st_frames_abort(), .st_he_published(), .st_he_rejected(),
        .st_gau_abort(), .he_lut_addr(8'd0), .he_lut_data()
    );

    // 并行顶层是单输入流：任一路不 ready 就会卡住共享流，所以未选中的两路恒 ready、
    // 数据直接丢；只有选中的那一路把反压传回 ROI 适配器。
    assign algo_ready[0] = (!codec_sel && algo_sel == 2'd0) ? algo_ms_ready : 1'b1;
    assign algo_ready[1] = (!codec_sel && algo_sel == 2'd1) ? algo_ms_ready : 1'b1;
    assign algo_ready[2] = (!codec_sel && algo_sel == 2'd2) ? algo_ms_ready : 1'b1;

    wire        algo_sel_v = (algo_sel == 2'd0) ? algo_v[0] : (algo_sel == 2'd1) ? algo_v[1] : algo_v[2];
    wire [31:0] algo_sel_d = (algo_sel == 2'd0) ? algo_d0 : (algo_sel == 2'd1) ? algo_d1 : algo_d2;
    wire        algo_sel_s = (algo_sel == 2'd0) ? algo_sof[0] : (algo_sel == 2'd1) ? algo_sof[1] : algo_sof[2];
    wire        algo_sel_l = (algo_sel == 2'd0) ? algo_eol[0] : (algo_sel == 2'd1) ? algo_eol[1] : algo_eol[2];
    wire        algo_sel_e = (algo_sel == 2'd0) ? algo_eof[0] : (algo_sel == 2'd1) ? algo_eof[1] : algo_eof[2];

    // 0x240[0]=1 时改送 LZ77 压缩流（同样 1920×1088 定长帧，主机按长度截取）
    wire        src_v = codec_sel ? cp_valid : algo_sel_v;
    wire [31:0] src_d = codec_sel ? cp_data  : algo_sel_d;
    wire        src_s = codec_sel ? cp_sof   : algo_sel_s;
    wire        src_l = codec_sel ? cp_eol   : algo_sel_l;
    wire        src_e = codec_sel ? cp_eof   : algo_sel_e;

    // ==== LZ77 压缩通路：裁 1920×1088 RAW10 → a1_frame_top → 打包成定长帧 ====
    //  0x240[0] 选源：0 = 预处理（灰度/高斯/均衡），1 = LZ77 压缩流。
    //  压缩流塞进 8bit 采样位，主机按 st_stream_len 截前 N 字节后 zlib 解压。
    wire        cdc_valid, cdc_sof, cdc_ready;
    wire [39:0] cdc_pix;
    wire        cp_valid, cp_sof, cp_eol, cp_eof, cp_ready;
    wire [31:0] cp_data;
    wire [31:0] c_stream_len, c_raw_len, c_raw_crc, c_blocks, c_words;
    wire        c_done, c_overflow;
    wire        c_abort;
    reg  [31:0] c_abort_cnt;
    always @(posedge w_a_byte_clk or negedge w_a_rst_out) begin
        if (!w_a_rst_out) c_abort_cnt <= 32'd0;
        else if (c_abort)  c_abort_cnt <= c_abort_cnt + 32'd1;
    end
    wire        c_commit;
    wire [31:0] c_fed, c_skipped;
    wire [31:0] cp_out_data;
    wire [3:0]  cp_out_keep;
    wire        cp_out_valid, cp_out_last;
    wire        codec_sel = w_algo_ctrl[0];
    wire        cp_out_ready;

    codec_roi_crop #(.W(ALGO_W), .H(CODEC_H), .X0(ALGO_X0), .Y0(CODEC_Y0), .FIFO_AW(10)) u_codec_crop (
        .clk(w_a_byte_clk), .rst_n(w_a_rst_out),
        .cam_vsync(gate_a_vsync), .cam_in_frame(gate_a_frame), .cam_in_line(gate_a_line),
        .cam_pix(w_a_pixel), .cam_pix_valid(gate_a_pixel_valid),
        .enable(1'b1), .keep_div(w_algo_ctrl[3]),
        .o_valid(cdc_valid), .o_pix(cdc_pix), .o_sof(cdc_sof), .o_ready(cdc_ready),
        .frames_fed(c_fed), .frames_skipped(c_skipped), .overflow(c_overflow)
    );

    a1_frame_top #(.W(ALGO_W), .H(CODEC_H)) u_codec (
        .clk(w_a_byte_clk), .rst_n(w_a_rst_out),
        .in_pix(cdc_pix), .in_valid(cdc_valid), .in_ready(cdc_ready), .in_sof(cdc_sof),
        .prep_en(1'b1), .pred_en(1'b1), .abort(1'b0),
        .out_data(cp_out_data), .out_valid(cp_out_valid), .out_ready(cp_out_ready),
        .out_keep(cp_out_keep), .out_last(cp_out_last),
        .frame_commit(c_commit), .frame_abort(c_abort),
        .st_raw_len(c_raw_len), .st_xform_len(), .st_stream_len(c_stream_len),
        .st_raw_crc(c_raw_crc), .st_xform_crc(), .st_stream_crc(),
        .st_blocks(c_blocks), .st_stall_cycles(), .st_busy()
    );

    codec_pack #(.W(ALGO_W), .H(ALGO_H), .GPQ(ALGO_W/4)) u_codec_pack (
        .clk(w_a_byte_clk), .rst_n(w_a_rst_out),
        .c_data(cp_out_data), .c_valid(cp_out_valid), .c_keep(cp_out_keep),
        .c_last(cp_out_last), .c_commit(c_commit), .c_abort(c_abort), .c_ready(cp_out_ready),
        .s_data(cp_data), .s_valid(cp_valid), .s_ready(cp_ready),
        .s_sof(cp_sof), .s_eol(cp_eol), .s_eof(cp_eof),
        .st_stream_len(), .st_words(c_words), .st_done(c_done)
    );

    assign w_codec_stat = {c_fed[15:0], c_abort_cnt[15:0], c_raw_crc, c_raw_len, c_stream_len};

    algo_y8_to_legacy u_algo_ms (
        .clk(w_a_byte_clk), .rst_n(w_a_rst_out),
        .s_valid(src_v), .s_ready(algo_ms_ready), .s_data(src_d),
        .s_sof(src_s), .s_eol(src_l), .s_eof(src_e),
        .o_valid(algo_ms_valid), .o_pix(algo_ms_pix),
        .o_vsync(algo_ms_vsync), .o_frame(algo_ms_frame), .o_line(algo_ms_line)
    );

generate if(CLOSEDLOOP_EN) begin:g_closedloop
    assign push_arready=1'b0;assign push_rvalid=1'b0;
    assign push_b_arready=1'b0;assign push_b_rvalid=1'b0;
    assign push_rd_arready=1'b0;assign push_rd_rvalid=1'b0;
    assign push_rd_rdata=256'd0;assign push_rd_rresp=2'd0;assign push_rd_rlast=1'b0;assign push_rd_rid=4'd0;
    ddr_closedloop_readback u_readback(
        .clk(w_ddr_dhi_clk),.rst(~w_ddrphy_rst_n),
        .pub_valid(cl_pub_valid),.pub_seq(cl_pub_seq),.pub_base(cl_pub_base),.pub_len(cl_pub_len),.pub_session(cl_pub_session),
        .writer_good(cl_writer_good),.writer_bad(cl_writer_bad),.abort(1'b0),.release_slot(cl_release),
        .arid(w_ddr_arid),.araddr(w_ddr_araddr),.arlen(w_ddr_arlen),.arsize(w_ddr_arsize),.arburst(w_ddr_arburst),
        .arvalid(w_ddr_arvalid),.arready(w_ddr_arready),.rid(w_ddr_rid),.rdata(w_ddr_rdata),.rresp(w_ddr_rresp),
        .rlast(w_ddr_rlast),.rvalid(w_ddr_rvalid),.rready(w_ddr_rready));
    // One deliberate internal abort on the third real source frame. No sensor,
    // I2C, link or external wire changes. It must reject RAW publication once.
    reg vs_d, injected,inject_pulse;
    (* MARK_DEBUG="true" *) reg [31:0] source_good,source_bad,source_crc,source_header,source_geometry,source_injected;
    reg [2:0] fe_delay;
    assign cl_inject_abort=inject_pulse;
    always @(posedge w_a_byte_clk or negedge w_a_rst_out) begin
        if(!w_a_rst_out) begin vs_d<=0;injected<=0;inject_pulse<=0;source_good<=0;source_bad<=0;source_crc<=0;source_header<=0;source_geometry<=0;source_injected<=0;fe_delay<=0;end
        else begin
            vs_d<=w_a_vsync;fe_delay<={fe_delay[1:0],w_a_frame_end};
            inject_pulse<=0;
            if(w_a_vsync&&!vs_d&&!injected&&(w_a_good_frm>=2)) begin injected<=1;inject_pulse<=1;source_injected<=source_injected+1'b1;end
            if(fe_delay[2]) begin source_good<=w_a_good_frm;source_bad<=w_a_bad_frm;source_crc<=w_a_crc_err;source_header<=w_a_hdr_err;source_geometry<={w_a_last_lines,w_a_last_wc};end
        end
    end
end else begin:g_original_reader
    assign cl_release=0;assign cl_inject_abort=0;
    assign w_ddr_arid=push_rd_arid;assign w_ddr_araddr=push_rd_araddr;assign w_ddr_arlen=push_rd_arlen;
    assign w_ddr_arsize=push_rd_arsize;assign w_ddr_arburst=push_rd_arburst;assign w_ddr_arvalid=push_rd_arvalid;
    assign push_rd_arready=w_ddr_arready;assign push_rd_rvalid=w_ddr_rvalid;
    assign push_rd_rdata=w_ddr_rdata;assign push_rd_rresp=w_ddr_rresp;assign push_rd_rlast=w_ddr_rlast;assign push_rd_rid=w_ddr_rid;
    assign w_ddr_rready=push_rd_rready;
end endgenerate

endmodule
