///////////////////////////////////////////////////////////////////////////////
//  tl_tx_arb.v — 用户侧 TL 发送口（utx_*）的 A/B 两路仲裁（双路同时出）
//
//  ===========================================================================
//  一、被仲裁的是什么
//  ===========================================================================
//   pcie_ep_engine.v 只有**一套**用户侧 TL 发送口：
//     · 引擎空闲（TL_TX_IDLE）时若看到 utx_req=1，就进 TL_TX_USER 把发送口借出去，
//       此时 utx_sel=1，线上 tl_tx_* 由顶层换成用户侧的 utx_data/sop/eop/valid；
//     · 借用期间引擎盯 utx_eop & |utx_valid & !tl_tx_wait —— 这一拍被链路收走就
//       立刻回 TL_TX_IDLE，把口子还给它自己的 CPL/CPLD 发送；用户侧想要下一拍
//       再拉 utx_req，引擎再借给它。
//   所以**引擎是按「一个 TLP」为单位借口的**，仲裁点天然就在 TLP 边界上。
//   两路推帧引擎（A/B）各有自己的一组 utx_*，必须在这里合成一套给引擎。
//
//  ===========================================================================
//  二、策略：TLP 级原子（TLP-atomic），靠 utx_sel 保位 + 电平请求轮转
//  ===========================================================================
//   · utx_sel=1 期间**绝不换手**：这期间引擎正在收某一笔 TLP 的拍子（可能因为
//     链路反压而停留很多拍），换手就会把 TLP 拦腰截断 —— 与其说"错包"，不如说
//     是两个包拼在一起被从机当成一个坏包。
//   · utx_sel=0 时才换手：被授权者没在请求（utx_req=0，推帧引擎只在两笔 MWr
//     之间的 S_TEND 那 1 拍拉低）而另一方在请求 → 让给另一方。请求是电平，
//     不会丢（AXI/TL 都是「保持到被受理」的语义）。
//   · 于是交替粒度就是「一笔 MWr」：一帧 64800 笔，一笔 5 拍（+1 拍空档）
//     ⇒ 单帧约 6.2ms @62.5MHz，帧周期 127ms ⇒ 每路占用约 5%，两路合计约 10%，
//     换手开销对帧率没有任何影响。
//   · 未被授权者看到的 a_sel/b_sel 恒 0，它的推帧状态机自然停在原地等。
//
//  时序：sel 是寄存器，数据/请求都是纯组合 mux，不加额外一拍；
//  被授权者看到 a_sel 的那一拍与它驱动 a_data 的那一拍同拍有效（与不仲裁时一致）。
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module tl_tx_arb (
    input  wire         clk,
    input  wire         rst,        // 高有效（与推帧引擎同域，顶层用 power_on_rst_dly）
    input  wire         utx_sel,    // 引擎：本拍 TL 发送口借给用户侧
    output wire         grant_out,  // 当前授权（0 = A 路，1 = B 路；诊断用）

    // ---------------- 客户机 0（推帧引擎 A 路）----------------
    input  wire         a_req,
    input  wire [255:0] a_data,
    input  wire         a_sop,
    input  wire         a_eop,
    input  wire [7:0]   a_valid,
    output wire         a_sel,

    // ---------------- 客户机 1（推帧引擎 B 路）----------------
    input  wire         b_req,
    input  wire [255:0] b_data,
    input  wire         b_sop,
    input  wire         b_eop,
    input  wire [7:0]   b_valid,
    output wire         b_sel,

    // ---------------- 到 pcie_ep_engine 的用户 TL 发送口 ----------------
    output wire         m_req,
    output wire [255:0] m_data,
    output wire         m_sop,
    output wire         m_eop,
    output wire [7:0]   m_valid
);

    reg sel;      // 0 = A 路，1 = B 路（寄存器：拍内恒定，TLP 期间不变）

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sel <= 1'b0;
        end else if (utx_sel) begin
            // 引擎正把口子借给当前这一路：保持不动（TLP 不许截断）
            sel <= sel;
        end else if (sel ? (!b_req && a_req) : (!a_req && b_req)) begin
            // 空档：被授权者不请求、另一方请求 → 换手（轮转，不会饿死）
            sel <= ~sel;
        end
    end

    assign grant_out = sel;

    // 授权信号：只有引擎把口子借给用户侧、且轮到自己那一拍才有效
    assign a_sel = utx_sel && !sel;
    assign b_sel = utx_sel &&  sel;

    // 到引擎的用户侧请求/数据：只放行被授权者的那一组
    assign m_req   = sel ? b_req   : a_req;
    assign m_data  = sel ? b_data  : a_data;
    assign m_sop   = sel ? b_sop   : a_sop;
    assign m_eop   = sel ? b_eop   : a_eop;
    assign m_valid = sel ? b_valid : a_valid;

endmodule
