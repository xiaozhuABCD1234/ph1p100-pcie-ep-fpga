///////////////////////////////////////////////////////////////////////////////
//  ddr_wr_mux.v — DDR3 用户侧 AXI4 **写**通道的二选一（本移植新增）
//
//  为什么需要：DDR3 的 AXI4 写口只有一个（u_ddr3_mc_0），而工程里有两条互斥的
//  「整帧写进 DDR3」通路：
//    · 0 号：ddr_frame_writer —— 片内帧缓存 fb[] → DDR3（测试图源 / 640x480 相机裁剪）
//    · 1 号：cam_ddr_writer  —— CSI-2 像素直通 DDR3（4K 全幅，本步新增）
//  两条通路不会同时用（同一时刻主机只认一组 0xA0~0xAC 握手字），所以这里不是
//  arbiter，而是**带保护的二选一**：
//
//  · 换手只发生在「两边都没有突发在飞」的时刻（busy0=busy1=0）。busyN 由各自
//    的 AXI 状态机给出（a_st != A_IDLE 或 packer 还没回空闲），**不能**用
//    「awvalid|wvalid|bready 全 0」去猜：客户机在「等写响应」那一拍这三个都是 0，
//    但从机的 bvalid 还没回来 —— 那一拍换手就会把 B 通道的响应送给另一个客户机，
//    直接死锁。
//  · 被选中的客户机照旧看到从机的 awready/wready/bvalid；没被选中的客户机看到
//    awready=0 / wready=0 / bvalid=0，它的状态机就自然停在原地（不会丢拍、不会
//    多走一步）。所以「换手会把一拍拦腰截断」这件事在本模块里不存在。
//  · 谁能被启动由顶层另外把关（ddr_frame_writer 的 ddr_en、cam_ddr_writer 的 arm
//    都只在被选中时才置位），本模块只管把通道让给谁。
//
//  时序：sel 是寄存器，纯组合地把五组信号打到从机口上，不加任何额外一拍。
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module ddr_wr_mux (
    input  wire         clk,
    input  wire         rst,          // 高有效（= !axi_aresetn = ddrphy_rst_n 的反）
    input  wire         sel_req,      // 1 = 想选 1 号（相机通路）
    input  wire         busy0,        // 0 号还有突发在飞
    input  wire         busy1,        // 1 号还有突发在飞
    output reg          sel_out,      // 实际选中（1 = 1 号；顶层用它 mux 握手字）

    // ---------------- 客户机 0（fb[] → DDR3）----------------
    input  wire [28:0]  a0_awaddr,
    input  wire [7:0]   a0_awlen,
    input  wire [2:0]   a0_awsize,
    input  wire [1:0]   a0_awburst,
    input  wire         a0_awvalid,
    output wire         a0_awready,
    input  wire [255:0] a0_wdata,
    input  wire [31:0]  a0_wstrb,
    input  wire         a0_wlast,
    input  wire         a0_wvalid,
    output wire         a0_wready,
    // ★ B 通道方向别写反：bvalid/bresp 是**从机( DDR )→客户机**，本模块要把它们
    //   分别送给两个客户机（所以是 output）；bready 是**客户机→从机**（所以是
    //   input，再二选一送给从机）。
    output wire [1:0]   a0_bresp,
    output wire         a0_bvalid,
    input  wire         a0_bready,

    // ---------------- 客户机 1（CSI-2 → DDR3，4K）----------------
    input  wire [28:0]  a1_awaddr,
    input  wire [7:0]   a1_awlen,
    input  wire [2:0]   a1_awsize,
    input  wire [1:0]   a1_awburst,
    input  wire         a1_awvalid,
    output wire         a1_awready,
    input  wire [255:0] a1_wdata,
    input  wire [31:0]  a1_wstrb,
    input  wire         a1_wlast,
    input  wire         a1_wvalid,
    output wire         a1_wready,
    output wire [1:0]   a1_bresp,
    output wire         a1_bvalid,
    input  wire         a1_bready,

    // ---------------- 到 u_ddr3_mc_0 ----------------
    output wire [28:0]  m_awaddr,
    output wire [7:0]   m_awlen,
    output wire [2:0]   m_awsize,
    output wire [1:0]   m_awburst,
    output wire         m_awvalid,
    input  wire         m_awready,
    output wire [255:0] m_wdata,
    output wire [31:0]  m_wstrb,
    output wire         m_wlast,
    output wire         m_wvalid,
    input  wire         m_wready,
    input  wire [1:0]   m_bresp,
    input  wire         m_bvalid,
    output wire         m_bready
);

    // 只有两边都空闲时才换手；busy 是各自状态机给的「还在飞」电平
    always @(posedge clk or posedge rst) begin
        if (rst)                        sel_out <= 1'b0;
        else if (~busy0 & ~busy1)       sel_out <= sel_req;
    end

    // 写地址通道
    assign m_awaddr  = sel_out ? a1_awaddr  : a0_awaddr;
    assign m_awlen   = sel_out ? a1_awlen   : a0_awlen;
    assign m_awsize  = sel_out ? a1_awsize  : a0_awsize;
    assign m_awburst = sel_out ? a1_awburst : a0_awburst;
    assign m_awvalid = sel_out ? a1_awvalid : a0_awvalid;
    assign a0_awready = sel_out ? 1'b0 : m_awready;
    assign a1_awready = sel_out ? m_awready : 1'b0;

    // 写数据通道
    assign m_wdata = sel_out ? a1_wdata : a0_wdata;
    assign m_wstrb = sel_out ? a1_wstrb : a0_wstrb;
    assign m_wlast = sel_out ? a1_wlast : a0_wlast;
    assign m_wvalid= sel_out ? a1_wvalid: a0_wvalid;
    assign a0_wready = sel_out ? 1'b0 : m_wready;
    assign a1_wready = sel_out ? m_wready : 1'b0;

    // 写响应通道：bvalid/bresp 是**从机 → 客户机**（本模块分发给选中的那一个），
    //               bready 是**客户机 → 从机**（从选中的那一个取）
    assign a0_bresp  = sel_out ? 2'b00   : m_bresp;
    assign a1_bresp  = sel_out ? m_bresp : 2'b00;
    assign m_bready  = sel_out ? a1_bready : a0_bready;
    assign a0_bvalid = sel_out ? 1'b0    : m_bvalid;
    assign a1_bvalid = sel_out ? m_bvalid: 1'b0;

endmodule
