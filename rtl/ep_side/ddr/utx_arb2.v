///////////////////////////////////////////////////////////////////////////////
//  utx_arb2.v — 两路推帧共享一个 TL 用户发送口
//
//  两片 ddr_frame_pusher 各自的 utx_req 是「拍级」请求；本模块做帧级授权：
//  选中的一路从 tx_busy 拉起到 tx_busy 落下期间独占 TL 用户口，另一路只能等。
//  这样 A/B 两帧绝不会在 TL 上交错（交错会让主机收到的 MWr 包不完整）。
//
//  utx_sel 由引擎给（引擎空闲才为 1）；每路的 utx_sel = 引擎 sel & 本路 grant。
//  未授权的路即使 utx_req=1 也不会被收走，状态机自然停在自己的节拍上。
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module utx_arb2 (
    input  wire         clk,
    input  wire         rst,
    input  wire         utx_sel,       // 引擎让出 TL 用户口

    // 路 0
    input  wire         req0,
    input  wire         busy0,
    input  wire [255:0] data0,
    input  wire         sop0,
    input  wire         eop0,
    input  wire [7:0]   valid0,
    output wire         sel0,

    // 路 1
    input  wire         req1,
    input  wire         busy1,
    input  wire [255:0] data1,
    input  wire         sop1,
    input  wire         eop1,
    input  wire [7:0]   valid1,
    output wire         sel1,

    // 合并后的用户口
    output wire         req,
    output wire [255:0] data,
    output wire         sop,
    output wire         eop,
    output wire [7:0]   valid
);
    // grant = 当前被授权的一路；只要该路 tx_busy 还在就保持。
    // 当前授权路空闲时才允许切到另一路；两路都空闲则保持上一次授权。
    reg grant;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            grant <= 1'b0;
        end else if (!(grant ? busy1 : busy0)) begin
            if (busy0)      grant <= 1'b0;
            else if (busy1) grant <= 1'b1;
        end
    end

    assign sel0 = utx_sel & (grant == 1'b0);
    assign sel1 = utx_sel & (grant == 1'b1);

    assign req   = (grant == 1'b0) ? req0   : req1;
    assign data  = (grant == 1'b0) ? data0  : data1;
    assign sop   = (grant == 1'b0) ? sop0   : sop1;
    assign eop   = (grant == 1'b0) ? eop0   : eop1;
    assign valid = (grant == 1'b0) ? valid0 : valid1;
endmodule
