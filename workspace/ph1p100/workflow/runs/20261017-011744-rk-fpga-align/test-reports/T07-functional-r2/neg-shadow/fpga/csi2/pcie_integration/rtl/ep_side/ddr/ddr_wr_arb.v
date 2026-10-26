///////////////////////////////////////////////////////////////////////////////
//  ddr_wr_arb.v — DDR3 用户侧 AXI4 **写**通道的 A/B 两路仲裁（本移植新增）
//
//  ===========================================================================
//  一、为什么需要仲裁
//  ===========================================================================
//   DDR3 IP（u_ddr3_mc_0）只有**一个** AXI4 从口（写通道、读通道各一份），
//   而两个相机（A/B）要**同时**把 4K 整帧写进 DDR3：
//     · 0 号：cam_ddr_writer A 路（BASE0/BASE1）
//     · 1 号：cam_ddr_writer B 路（BASE2/BASE3）
//   两个 writer 必须同时 armed，端口只能分时复用，所以不能再用「谁被 arm 谁才动」
//   的互斥二选一 —— 那种做法靠顶层只 arm 一路来回避下面的死锁，两路同时 armed
//   就会死锁（见第三节）。
//
//  （本模块取代了先前的 ddr_wr_mux.v：那是「fb[] → DDR3 老通路 vs 相机直通」的
//    二选一。640x480 预览通路已从设计中移除，写口只剩上面这两路，且两路**同时**
//    在跑，所以换成了这里的仲裁器。）
//
//  ===========================================================================
//  二、仲裁策略：grant 跟随 busy + 轮转
//  ===========================================================================
//   · grant 落在某客户机上时，只要它 busy 就一直保持 —— 保证「一次突发不被拦腰
//     截断」。中途换手会把从机的 bvalid 送给另一个客户机，直接死锁。
//   · 一旦被授权者空闲（busy=0），就把 grant 交给另一个客户机（若它也 busy）；
//     它也不 busy 就保持不动。
//   · 不会死锁：busy 含「进了 A_AW、在等 awready」这一段，所以**在等端口**的客户机
//     自己就是 busy，grant 一转到它立刻被受理（避免了「必须两边都空闲才换手」那种
//     把等待者冻住的规则）。
//   · 不会饿死：相机写突发是「FIFO 攒够 4KB 发一次」——一个突发 128 拍 = 1.28us
//     @100MHz，而攒满一突发要约 31us（4K@15.7fps ≈ 130MB/s）⇒ 每个客户机约 96%
//     的时间是空闲的，grant 有的是机会换。
//   · 未被授权的客户机看到 awready=0 / wready=0 / bvalid=0，它的状态机自然停在
//     原地（不丢拍、不多走一步）。
//   · busy 必须由各客户机自己的 AXI 状态机给出（cam_ddr_writer 的 axi_busy =
//     a_st != A_IDLE），**不能**用「awvalid|wvalid|bready 全 0」去猜：客户机在等
//     写响应那一拍这三个都是 0，而从机的 bvalid 还没回来。
//
//  ===========================================================================
//  三、为什么不能用「两边都空闲才换手」
//  ===========================================================================
//   设客户机 0 在 A_AW 等端口（busy0=1，awvalid=1，awready=0），客户机 1 空闲
//   （busy1=0）。若规则是「busy0=busy1=0 才允许把 sel 改成本客户机」，则 sel 会
//   冻在 1 号上（因为 0 号一直 busy，条件永不满足），0 号永远等不到 awready ——
//   死锁。本模块的 grant 规则里，被授权者一旦空闲就可以立刻交给 busy 的另一方，
//   所以 0 号一定拿得到端口。
//
//  时序：grant 是寄存器，纯组合地把两组信号打到从机口上，不加任何额外一拍。
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module ddr_wr_arb (
    input  wire         clk,
    input  wire         rst,          // 高有效（= !axi_aresetn = ddrphy_rst_n 的反）
    input  wire         busy0,        // 0 号还有突发在飞 / 在等端口 / 在等响应
    input  wire         busy1,
    output wire         grant_out,    // 当前授权号（0 = A 路，1 = B 路；诊断用）

    // ---------------- 客户机 0（cam_ddr_writer A 路）----------------
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
    // ★ 方向别写反：bvalid/bresp 是**从机(DDR) → 客户机**（本模块把它们分发给授权者，
    //   所以是 output）；bready 是**客户机 → 从机**（所以是 input，再二选一送给从机）。
    output wire [1:0]   a0_bresp,
    output wire         a0_bvalid,
    input  wire         a0_bready,

    // ---------------- 客户机 1（cam_ddr_writer B 路）----------------
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

    reg sel;

    // 被授权者仍 busy 就保持；它一空闲就把端口交给 busy 的另一方（另一方也空闲则保持）
    //   注意 sel 的取值含义：0 = 授权 0 号，1 = 授权 1 号。所以「让给 0 号」是 sel<=0，
    //   条件是 busy0=1 ⇒ 写成 ~busy0，别写成 busy0（方向会反，仿真里表现为死锁形态）。
    always @(posedge clk or posedge rst) begin
        if (rst)                          sel <= 1'b0;
        else if (sel ? ~busy1 : ~busy0)   sel <= sel ? ~busy0 : busy1;
    end

    assign grant_out = sel;

    // 写地址通道
    assign m_awaddr   = sel ? a1_awaddr  : a0_awaddr;
    assign m_awlen    = sel ? a1_awlen   : a0_awlen;
    assign m_awsize   = sel ? a1_awsize  : a0_awsize;
    assign m_awburst  = sel ? a1_awburst : a0_awburst;
    assign m_awvalid  = sel ? a1_awvalid : a0_awvalid;
    assign a0_awready = sel ? 1'b0       : m_awready;
    assign a1_awready = sel ? m_awready  : 1'b0;

    // 写数据通道
    assign m_wdata    = sel ? a1_wdata : a0_wdata;
    assign m_wstrb    = sel ? a1_wstrb : a0_wstrb;
    assign m_wlast    = sel ? a1_wlast : a0_wlast;
    assign m_wvalid   = sel ? a1_wvalid: a0_wvalid;
    assign a0_wready  = sel ? 1'b0     : m_wready;
    assign a1_wready  = sel ? m_wready : 1'b0;

    // 写响应通道：bvalid/bresp 从机 → 授权者；bready 授权者 → 从机
    assign a0_bresp  = sel ? 2'b00   : m_bresp;
    assign a1_bresp  = sel ? m_bresp : 2'b00;
    assign a0_bvalid = sel ? 1'b0    : m_bvalid;
    assign a1_bvalid = sel ? m_bvalid: 1'b0;
    assign m_bready  = sel ? a1_bready : a0_bready;

endmodule
