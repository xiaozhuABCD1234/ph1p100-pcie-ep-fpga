///////////////////////////////////////////////////////////////////////////////
//  ddr_rd_arb2.v — 两路 DDR 读通道仲裁（推帧 A/B）
//
//  两个 ddr_frame_pusher 各自只有一条 AXI4 读通道，但 DDR 控制器只有一个读口。
//  本模块把两路串行化：一次只让一路发 AR，等它的 RLAST 收完才换另一路。
//  读数据只回给当前授权方；ID 固定 0，不需要按 ID 分流。
//
//  约束：两路 araddr/arlen 必须保持到 arready；AXI 本来就是这样。
//  优先级：0 路优先，1 路在 0 路空闲时得到授权。帧级公平由上层 one-shot
//  ARM/ACK 控制，不在这里做 round-robin（避免打乱单帧突发）。
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module ddr_rd_arb2 (
    input  wire         clk,
    input  wire         rst,

    // master 0
    input  wire         m0_arvalid,
    output wire         m0_arready,
    input  wire [28:0]  m0_araddr,
    input  wire [7:0]   m0_arlen,
    input  wire [2:0]   m0_arsize,
    input  wire [1:0]   m0_arburst,
    input  wire [3:0]   m0_arid,
    input  wire         m0_rready,
    output wire         m0_rvalid,
    output wire [255:0] m0_rdata,
    output wire [1:0]   m0_rresp,
    output wire         m0_rlast,
    output wire [3:0]   m0_rid,

    // master 1
    input  wire         m1_arvalid,
    output wire         m1_arready,
    input  wire [28:0]  m1_araddr,
    input  wire [7:0]   m1_arlen,
    input  wire [2:0]   m1_arsize,
    input  wire [1:0]   m1_arburst,
    input  wire [3:0]   m1_arid,
    input  wire         m1_rready,
    output wire         m1_rvalid,
    output wire [255:0] m1_rdata,
    output wire [1:0]   m1_rresp,
    output wire         m1_rlast,
    output wire [3:0]   m1_rid,

    // slave
    output wire         s_arvalid,
    input  wire         s_arready,
    output wire [28:0]  s_araddr,
    output wire [7:0]   s_arlen,
    output wire [2:0]   s_arsize,
    output wire [1:0]   s_arburst,
    output wire [3:0]   s_arid,
    input  wire         s_rvalid,
    input  wire [255:0] s_rdata,
    input  wire [1:0]   s_rresp,
    input  wire         s_rlast,
    input  wire [3:0]   s_rid,
    output wire         s_rready
);
    // sel = 当前授权路；active = 已发出 AR，等 RLAST
    reg sel, active;

    assign m0_arready = (sel == 1'b0) ? s_arready : 1'b0;
    assign m1_arready = (sel == 1'b1) ? s_arready : 1'b0;

    assign s_arvalid = ~active & ((sel == 1'b0) ? m0_arvalid : m1_arvalid);
    assign s_araddr  = (sel == 1'b0) ? m0_araddr  : m1_araddr;
    assign s_arlen   = (sel == 1'b0) ? m0_arlen   : m1_arlen;
    assign s_arsize  = (sel == 1'b0) ? m0_arsize  : m1_arsize;
    assign s_arburst = (sel == 1'b0) ? m0_arburst : m1_arburst;
    assign s_arid    = (sel == 1'b0) ? m0_arid    : m1_arid;

    assign s_rready  = (sel == 1'b0) ? m0_rready : m1_rready;
    assign m0_rvalid = s_rvalid & (sel == 1'b0);
    assign m0_rdata  = s_rdata;
    assign m0_rresp  = s_rresp;
    assign m0_rlast  = s_rlast & (sel == 1'b0);
    assign m0_rid    = s_rid;
    assign m1_rvalid = s_rvalid & (sel == 1'b1);
    assign m1_rdata  = s_rdata;
    assign m1_rresp  = s_rresp;
    assign m1_rlast  = s_rlast & (sel == 1'b1);
    assign m1_rid    = s_rid;

    // 授权：空闲时 0 优先，否则选 1。一次 AR 从发出到 RLAST 完成之前不改 sel。
    // active 只在 AR 真正握手后置位；AR 未握手时 sel 可以切到另一路。
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sel    <= 1'b0;
            active <= 1'b0;
        end else if (!active) begin
            if (s_arvalid && s_arready) begin
                active <= 1'b1;
            end else if (!s_arvalid) begin
                if (m0_arvalid)      sel <= 1'b0;
                else if (m1_arvalid) sel <= 1'b1;
            end
        end else if (s_rvalid && s_rready && s_rlast) begin
            active <= 1'b0;
        end
    end
endmodule
