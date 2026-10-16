///////////////////////////////////////////////////////////////////////////////
//  ddr_rd_arb.v — DDR3 用户侧 AXI4 **读**通道的 A/B 两路仲裁（双路同时出）
//
//  ===========================================================================
//  一、为什么需要它
//  ===========================================================================
//   ddr_wr_arb.v 解决的是写通道（两个相机同时写）。把整帧推给主机也要读 DDR，
//   而推帧引擎（ddr_frame_pusher）读的正是 u_ddr3_mc_0 的**同一个** AXI4 从口的
//   读通道 —— 一份。两路要「同时出」（A、B 各自的整帧都主动推给主机）就必须
//   再仲裁一次。
//
//   ===========================================================================
//  二、策略：突发级锁定（burst-atomic），不是拍级
//  ===========================================================================
//   · 读通道与写通道的仲裁粒度**不一样**，不能照抄 ddr_wr_arb：
//     写通道有 AW/W/B 三条子通道，被授权者的 AW 与 W 是它自己按拍推的；
//     读通道的 AR 一旦被受理，数据就由从机按次序吐回来（128 拍一个突发），
//     中途换手会把数据送给另一个客户机 → 直接错帧。所以这里锁定的是
//     **一次突发**：AR 握手那一刻锁住，直到这一突发的 rlast 才放锁。
//   · 锁定期里：
//       - 只有被锁定者的 rvalid/rdata/rresp/rlast 有效，另一路恒 0；
//       - m_rready 由被锁定者驱动；
//       - m_arvalid 强制为 0（不给「同一 ID 多个未完成突发」留任何余地，
//         两路客户机的 arid 都是 4'd0，一旦同时有多个在飞就无法按 ID 区分）。
//         于是任一时刻整个 DDR 读通道上**最多一个未完成突发**。
//   · 放锁时轮转（把机会先给另一路），空闲时谁请求给谁 —— 不会饿死。
//   · 代价可以忽略：一次 4KB 突发 = 128 拍 = 1.28us @100MHz，而一帧 2025 个突发
//     分摊到 127ms 的帧周期里 ⇒ 每路占用读通道约 2.6%，两路合计约 5%。
//     串行化突发带来的等待（最长一次突发 + 一拍换手）远小于客户机自己的
//     FIFO（128 拍 = 一整个突发）能吸收的量。
//   · 客户机侧：未被授权者看到 arready=0，它的 AXI 状态机会停在 A_AR 里继续举着
//     arvalid（AXI 允许），不丢拍、不多走一步。
//
//  时序：sel / lock 都是寄存器，纯组合打到从机口上，不加额外一拍。
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module ddr_rd_arb (
    input  wire         clk,
    input  wire         rst,           // 高有效（= !axi_aresetn = !ddrphy_rst_n）
    output wire         grant_out,     // 当前授权号（0 = A 路，1 = B 路；诊断用）

    // ---------------- 客户机 0（推帧引擎 A 路）----------------
    input  wire [3:0]   a0_arid,
    input  wire [28:0]  a0_araddr,
    input  wire [7:0]   a0_arlen,
    input  wire [2:0]   a0_arsize,
    input  wire [1:0]   a0_arburst,
    input  wire         a0_arvalid,
    output wire         a0_arready,
    output wire [3:0]   a0_rid,
    output wire [255:0] a0_rdata,
    output wire [1:0]   a0_rresp,
    output wire         a0_rlast,
    output wire         a0_rvalid,
    input  wire         a0_rready,

    // ---------------- 客户机 1（推帧引擎 B 路）----------------
    input  wire [3:0]   a1_arid,
    input  wire [28:0]  a1_araddr,
    input  wire [7:0]   a1_arlen,
    input  wire [2:0]   a1_arsize,
    input  wire [1:0]   a1_arburst,
    input  wire         a1_arvalid,
    output wire         a1_arready,
    output wire [3:0]   a1_rid,
    output wire [255:0] a1_rdata,
    output wire [1:0]   a1_rresp,
    output wire         a1_rlast,
    output wire         a1_rvalid,
    input  wire         a1_rready,

    // ---------------- 到 u_ddr3_mc_0 ----------------
    output wire [3:0]   m_arid,
    output wire [28:0]  m_araddr,
    output wire [7:0]   m_arlen,
    output wire [2:0]   m_arsize,
    output wire [1:0]   m_arburst,
    output wire         m_arvalid,
    input  wire         m_arready,
    input  wire [3:0]   m_rid,
    input  wire [255:0] m_rdata,
    input  wire [1:0]   m_rresp,
    input  wire         m_rlast,
    input  wire         m_rvalid,
    output wire         m_rready
);

    reg sel;      // 授权号：0 = 客户机 0，1 = 客户机 1（寄存器，拍内恒定）
    reg lock;     // 1 = 一次突发在飞（AR 已受理，等 rlast）

    // （声明都在使用之前 —— TD 会对 used-before-declaration 报 HDL-5373）
    wire m_rready_now = sel ? a1_rready : a0_rready;   // 授权者给的 rready
    wire cur_arvalid  = sel ? a1_arvalid : a0_arvalid;  // 授权者是否举着 AR
    // AR 握手（只可能发生在被授权者身上：arready 只给授权者）
    wire ar_hs        = !lock && cur_arvalid && m_arready;
    // 一次突发收尾：末拍被双方收走（受授权者 rready 与从机 rvalid 同时有效）
    wire r_done       = lock && m_rvalid && m_rready_now && m_rlast;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sel  <= 1'b0;
            lock <= 1'b0;
        end else if (lock) begin
            if (r_done) begin
                lock <= 1'b0;
                // 轮转：另一路还在请求就把机会让它（请求是电平，走了不丢）
                if (sel ? a0_arvalid : a1_arvalid) sel <= ~sel;
            end
        end else begin
            if (ar_hs) begin
                lock <= 1'b1;                     // 突发已受理 → 锁到 rlast
            end else if (sel ? (!a1_arvalid && a0_arvalid)
                             : (!a0_arvalid && a1_arvalid)) begin
                sel <= ~sel;                      // 授权者不请求、另一方请求 → 让端口
            end
        end
    end

    assign grant_out = sel;

    // ---------------- AR 通道：只放行授权者，且锁定期一律不放 ----------------
    assign m_arid    = sel ? a1_arid    : a0_arid;
    assign m_araddr  = sel ? a1_araddr  : a0_araddr;
    assign m_arlen   = sel ? a1_arlen   : a0_arlen;
    assign m_arsize  = sel ? a1_arsize  : a0_arsize;
    assign m_arburst = sel ? a1_arburst : a0_arburst;
    assign m_arvalid = lock ? 1'b0 : cur_arvalid;
    assign a0_arready = (lock || sel) ? 1'b0 : m_arready;
    assign a1_arready = (lock || !sel) ? 1'b0 : m_arready;

    // ---------------- R 通道：数据只回给锁定的那一路 ----------------
    assign a0_rid    = lock ? (sel ? 4'd0 : m_rid)   : 4'd0;
    assign a1_rid    = lock ? (sel ? m_rid : 4'd0)   : 4'd0;
    assign a0_rdata  = lock ? (sel ? 256'd0 : m_rdata) : 256'd0;
    assign a1_rdata  = lock ? (sel ? m_rdata : 256'd0) : 256'd0;
    assign a0_rresp  = lock ? (sel ? 2'b00 : m_rresp) : 2'b00;
    assign a1_rresp  = lock ? (sel ? m_rresp : 2'b00) : 2'b00;
    assign a0_rlast  = lock ? (sel ? 1'b0 : m_rlast)  : 1'b0;
    assign a1_rlast  = lock ? (sel ? m_rlast : 1'b0)  : 1'b0;
    assign a0_rvalid = lock ? (sel ? 1'b0 : m_rvalid) : 1'b0;
    assign a1_rvalid = lock ? (sel ? m_rvalid : 1'b0) : 1'b0;
    // rready 只由锁定者给：没锁定时不接任何数据（此时从机也不该有数据）
    assign m_rready  = lock ? m_rready_now : 1'b0;

endmodule
